import Foundation
import Supabase

/// The words and expressions learners added that the bundled graded list
/// doesn't carry — one library per target language, shared by everyone who
/// learns it (`library_terms`, written only by the `library-add` function,
/// which reads every entry before it goes in: a typo, a made-up word or a
/// name never does).
///
/// Words join `CoreVocabulary`'s pool with their level, so the Words page,
/// the cloud, the level filters and everything that grades a word see them
/// like any bundled word. Expressions have no bundled list; they are the
/// Expressions page's "All" lens.
///
/// A local copy per language lives in Caches (it can always be fetched
/// again) and is read when a pool is built; `refresh` pulls only what changed
/// since the last pull.
enum SharedLibrary {
    struct Term: Codable, Hashable {
        let term: String
        let kind: String     // "word" | "expression"
        let level: String    // "a1"…"c2"
        var key: String { term.lowercased() }
        var cefr: CEFRLevel? { CEFRLevel(rawValue: level) }
    }

    private struct Snapshot: Codable {
        var terms: [Term]
        var since: Date?
        var fetchedAt: Date?
    }

    private static let lock = NSLock()
    private static var snapshots: [String: Snapshot] = [:]

    private static func fileURL(_ language: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shared_library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(language).json")
    }

    private static func snapshot(_ language: String) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        if let s = snapshots[language] { return s }
        let s = (try? Data(contentsOf: fileURL(language)))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            ?? Snapshot(terms: [], since: nil, fetchedAt: nil)
        snapshots[language] = s
        return s
    }

    private static func store(_ s: Snapshot, _ language: String) {
        lock.lock()
        snapshots[language] = s
        lock.unlock()
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: fileURL(language), options: .atomic) }
    }

    static func words(_ language: String) -> [Term] {
        snapshot(language).terms.filter { $0.kind == "word" }
    }

    static func expressions(_ language: String) -> [Term] {
        snapshot(language).terms.filter { $0.kind == "expression" }
    }

    static func expressionLevel(of phrase: String, language: String = LanguageScope.active) -> CEFRLevel? {
        let key = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return expressions(language).first { $0.key == key }?.cefr
    }

    /// Fold terms into the local copy (a pull, or one this learner just
    /// added) and let the word pool pick new words up.
    private static func merge(_ incoming: [Term], since: Date?, language: String, fetched: Bool) {
        var s = snapshot(language)
        var byKey = Dictionary(s.terms.map { ("\($0.kind)|\($0.key)", $0) }, uniquingKeysWith: { a, _ in a })
        for t in incoming { byKey["\(t.kind)|\(t.key)"] = t }
        let before = s.terms.count
        s.terms = Array(byKey.values).sorted { $0.key < $1.key }
        if let since { s.since = max(s.since ?? since, since) }
        if fetched { s.fetchedAt = Date() }
        store(s, language)
        if s.terms.count != before || !incoming.isEmpty {
            CoreVocabulary.invalidate(language)
        }
    }

    static func adopt(_ term: Term, language: String) {
        merge([term], since: nil, language: language, fetched: false)
    }

    // MARK: - Pull

    private struct Row: Decodable {
        let term: String
        let kind: String
        let level: String
        let updated_at: Date
    }

    /// Pull what changed since the last pull, at most every few hours.
    static func refreshIfStale(language: String) async {
        if let at = snapshot(language).fetchedAt, Date().timeIntervalSince(at) < 6 * 3600 { return }
        await refresh(language: language)
    }

    static func refresh(language: String) async {
        let since = snapshot(language).since ?? .distantPast
        var cursor = since
        var all: [Term] = []
        // Pages of 1,000, oldest change first, so a cut-off pull resumes.
        for _ in 0..<20 {
            guard let rows: [Row] = try? await SupabaseProvider.shared
                .from("library_terms")
                .select("term, kind, level, updated_at")
                .eq("target_lang", value: language)
                .gt("updated_at", value: ISO8601DateFormatter().string(from: cursor))
                .order("updated_at", ascending: true)
                .limit(1000)
                .execute()
                .value
            else { return }
            all += rows.map { Term(term: $0.term, kind: $0.kind, level: $0.level) }
            if let last = rows.last?.updated_at { cursor = last }
            if rows.count < 1000 { break }
        }
        merge(all, since: cursor, language: language, fetched: true)
    }

    // MARK: - Add

    enum AddResult {
        /// In the library now (or already was), as its dictionary form.
        case added(Term)
        /// Misspelt; this is what was probably meant.
        case typo(String)
        /// Not something the library takes (`reason` is the server's).
        case rejected(String)
        /// Couldn't ask.
        case failed
    }

    private struct AddRequest: Encodable {
        let text: String
        let kind: String
        let target_lang: String
        let native_lang: String
    }
    private struct AddResponse: Decodable {
        let status: String
        let term: String?
        let level: String?
        let suggestion: String?
        let reason: String?
    }

    static func add(_ text: String, kind: String, target: String, native: String) async -> AddResult {
        do {
            let res: AddResponse = try await SupabaseProvider.shared.functions.invoke(
                "library-add",
                options: FunctionInvokeOptions(body: AddRequest(text: text, kind: kind,
                                                                target_lang: target, native_lang: native)))
            switch res.status {
            case "ok":
                guard let term = res.term, let level = res.level else { return .failed }
                let t = Term(term: term, kind: kind, level: level)
                adopt(t, language: target)
                return .added(t)
            case "typo":
                return res.suggestion.map { .typo($0) } ?? .rejected("not_real")
            default:
                return .rejected(res.reason ?? "not_real")
            }
        } catch {
            return .failed
        }
    }
}
