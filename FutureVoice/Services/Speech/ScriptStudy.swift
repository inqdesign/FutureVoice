import CryptoKit
import Foundation
import Supabase   // FunctionInvokeOptions for the shared challenge study

/// "Study" on a Speech script (2026-10-14, founder decision): the script's
/// most useful expressions, grammar patterns and words marked IN the text,
/// and under each paragraph its translation into the learner's own language
/// (founder, same day: a one-line summary of what the paragraph "does" told
/// a reader nothing they needed — the translation is what they reach for).
///
/// MATERIAL vs NOTES: every highlighted span is the script's own text (target
/// language, verbatim — `locate` drops any span that isn't); every `note` and
/// paragraph translation is in the native language, and a learner whose
/// native language IS the target gets no translation at all.
///
/// Written once per (script text, target, native, level) by one call on the
/// default model (`purpose: "script-study"`) and kept on disk, so reopening a
/// script is instant and costs nothing.
struct ScriptStudy: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case expression, grammar, word
    }

    struct Highlight: Codable, Equatable, Identifiable {
        var id: Int
        /// Exactly as it stands in the script.
        var text: String
        var kind: Kind
        /// A word's dictionary form, for the word card's lookup.
        var lemma: String?
        /// What it means and does HERE, in the native language.
        var note: String
        /// A fresh line using it, in the target language.
        var example: String?
        /// Where it is: paragraph index and Character offset/length inside
        /// that paragraph's text.
        var paragraph: Int
        var offset: Int
        var length: Int
    }

    var highlights: [Highlight]
    /// One per paragraph, in order; "" where the model had nothing.
    var paragraphNotes: [String]

    func count(_ kind: Kind) -> Int { highlights.filter { $0.kind == kind }.count }
    func highlights(in paragraph: Int) -> [Highlight] {
        highlights.filter { $0.paragraph == paragraph }.sorted { $0.offset < $1.offset }
    }

    // MARK: - Paragraphs

    /// The script's paragraphs exactly as the prompter splits them
    /// (`SpeechPrompterTrack`): one per non-empty line.
    static func paragraphs(_ body: String) -> [String] {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Verifying spans

    struct Candidate: Equatable {
        var text: String
        var kind: Kind
        var lemma: String? = nil
        var note: String = ""
        var example: String? = nil
    }

    /// Keeps only spans that occur VERBATIM in the script, each at its first
    /// place not already taken by an earlier span. Case may differ only when
    /// no exact match exists (a model that capitalised a sentence-initial
    /// word). In a spaced language a span must start and end on a word
    /// boundary, so "art" can never light up inside "start". At most `limit`.
    static func locate(_ candidates: [Candidate], in paragraphs: [String],
                       spaced: Bool, limit: Int = 10) -> [Highlight] {
        var taken: [Int: [Range<Int>]] = [:]
        var out: [Highlight] = []
        for c in candidates {
            guard out.count < limit else { break }
            let span = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !span.isEmpty, span.count <= 80 else { continue }
            var placed: (Int, Int)?
            search: for exactFirst in [true, false] {
                for (p, para) in paragraphs.enumerated() {
                    for start in occurrences(of: span, in: para, caseSensitive: exactFirst) {
                        let r = start ..< start + span.count
                        if spaced && !onBoundary(para, r) { continue }
                        if (taken[p] ?? []).contains(where: { $0.overlaps(r) }) { continue }
                        placed = (p, start)
                        break search
                    }
                }
            }
            guard let (p, start) = placed else { continue }
            taken[p, default: []].append(start ..< start + span.count)
            let chars = Array(paragraphs[p])
            out.append(Highlight(id: out.count, text: String(chars[start ..< start + span.count]),
                                 kind: c.kind, lemma: c.lemma, note: c.note,
                                 example: c.example, paragraph: p,
                                 offset: start, length: span.count))
        }
        return out
    }

    /// Character offsets where `needle` starts in `hay`.
    static func occurrences(of needle: String, in hay: String, caseSensitive: Bool) -> [Int] {
        let h = Array(caseSensitive ? hay : hay.lowercased())
        let n = Array(caseSensitive ? needle : needle.lowercased())
        // `lowercased` can change a string's length (İ); then only exact.
        guard !n.isEmpty, n.count <= h.count,
              caseSensitive || (h.count == hay.count && n.count == needle.count) else { return [] }
        var out: [Int] = []
        var i = 0
        while i + n.count <= h.count {
            if Array(h[i ..< i + n.count]) == n { out.append(i) }
            i += 1
        }
        return out
    }

    private static func onBoundary(_ para: String, _ r: Range<Int>) -> Bool {
        let chars = Array(para)
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        if r.lowerBound > 0, isWordChar(chars[r.lowerBound - 1]), isWordChar(chars[r.lowerBound]) { return false }
        if r.upperBound < chars.count, isWordChar(chars[r.upperBound]), isWordChar(chars[r.upperBound - 1]) { return false }
        return true
    }

    // MARK: - Cache key

    /// Bumped whenever the prompt changes what a study is.
    static let promptVersion = 2

    static func textHash(_ body: String) -> String {
        sha(body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func cacheKey(body: String, target: String, native: String, level: String) -> String {
        sha("study\(promptVersion)|\(textHash(body))|\(LanguageCatalog.base(target))|\(native)|\(level.lowercased())")
    }

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// `Documents/ScriptStudy/<key>.json`. Never pruned — a study is small, and
/// re-making one is a paid call.
enum ScriptStudyStore {
    private static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("ScriptStudy", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func load(key: String) -> ScriptStudy? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(key).json")) else { return nil }
        return try? JSONDecoder().decode(ScriptStudy.self, from: data)
    }

    static func save(_ study: ScriptStudy, key: String) {
        guard let data = try? JSONEncoder().encode(study) else { return }
        try? data.write(to: dir.appendingPathComponent("\(key).json"), options: [.atomic])
    }
}

enum ScriptStudyEngine {
    enum StudyError: LocalizedError {
        case empty
        var errorDescription: String? { explain("The study notes couldn't be prepared. Try again.") }
    }

    /// From disk when it was made before; otherwise a challenge's notes come
    /// from the shared cache (`script-study`, made once per native language
    /// and level for every learner), and a learner's own script is one model
    /// call on this phone. A failed shared read falls back to the phone, so
    /// the feature never depends on the function being up.
    static func study(for script: SpeechScript, native: String, level: CEFRLevel) async throws -> ScriptStudy {
        let key = ScriptStudy.cacheKey(body: script.body, target: script.language,
                                       native: native, level: level.rawValue)
        if let cached = ScriptStudyStore.load(key: key) { return cached }
        var made: ScriptStudy?
        if let challengeId = script.challengeId {
            made = try? await shared(script: script, challengeId: challengeId, native: native, level: level)
        }
        if made == nil { made = try await generate(script: script, native: native, level: level) }
        guard let made else { throw StudyError.empty }
        ScriptStudyStore.save(made, key: key)
        return made
    }

    private struct Item: Decodable {
        let text: String?
        let kind: String?
        let lemma: String?
        let note: String?
        let example: String?
    }
    private struct Payload: Decodable {
        let highlights: [Item]?
        let paragraph_notes: [String]?
        let shared: Bool?
    }

    /// A challenge's notes from the shared cache. The function reads the
    /// challenge text itself and holds the prompt (a copy of `generate`'s);
    /// what comes back is the model's raw answer, placed here like any other.
    private static func shared(script: SpeechScript, challengeId: UUID,
                               native: String, level: CEFRLevel) async throws -> ScriptStudy {
        struct Body: Encodable { let challenge_id: String; let native: String; let level: String }
        let payload: Payload = try await SupabaseProvider.shared.functions.invoke(
            "script-study",
            options: FunctionInvokeOptions(body: Body(
                challenge_id: challengeId.uuidString.lowercased(),
                native: native, level: level.rawValue)))
        return try build(payload, script: script, shared: payload.shared ?? true)
    }

    /// KEEP IN STEP with `supabase/functions/script-study` — challenges are
    /// studied with that copy of this prompt.
    private static func generate(script: SpeechScript, native: String, level: CEFRLevel) async throws -> ScriptStudy {
        let paragraphs = ScriptStudy.paragraphs(script.body)
        guard !paragraphs.isEmpty else { throw StudyError.empty }
        let target = LanguageCatalog.englishName(script.language)
        let nativeName = LanguageCatalog.englishName(native)
        let sameLanguage = LanguageCatalog.sameLanguage(native, script.language)
        let paragraphRule = sameLanguage
            ? "PARAGRAPH NOTES — return an empty list: the learner reads \(target) natively."
            : """
            PARAGRAPH NOTES — exactly one per numbered paragraph, in order: that
            paragraph TRANSLATED into \(nativeName). The whole paragraph, every
            sentence, faithful to its meaning and tone, written the way a native
            \(nativeName) speaker would say it — not word for word, not a summary,
            nothing added or left out.
            """
        let system = """
        You are a language teacher preparing a script for a learner
        (\(level.rawValue.uppercased())) who will read it aloud in \(target).
        Output STRICT JSON only — no prose, no code fences:
        { "highlights": [ { "text": "...", "kind": "expression|grammar|word",
            "lemma": "...", "note": "...", "example": "..." } ],
          "paragraph_notes": ["...", "..."] }

        \(CoachingLanguage.contract(target: script.language, native: native))

        HIGHLIGHTS — 7 or 8 in total, the ones most worth learning for THIS
        learner: a little above their level, reusable outside this script.
        Spread them over the paragraphs. Mostly expressions (fixed phrases,
        phrasal verbs, collocations), then grammar patterns (a structure
        like "only to", "tends to"), then single words.
        - "text": copied EXACTLY from the script — same spelling, same case,
          one contiguous stretch, never rewritten, never a whole sentence.
          A grammar pattern is the few words that carry it.
        - "kind": "expression", "grammar" or "word".
        - "lemma": for a word, its dictionary form in \(target); else omit.
        - "note": \(nativeName). One or two short sentences: what it means and
          what it does HERE. For grammar, the pattern and when it is used.
        - "example": \(target). One new short sentence using it, not from the
          script. Omit when you have none.

        \(paragraphRule)
        """
        let numbered = paragraphs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let user = "SCRIPT (\(paragraphs.count) paragraphs):\n\(numbered)"
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system, messages: [.init(role: .user, content: user)],
            model: .flash36, maxTokens: 8192, purpose: "script-study", requestTimeout: 90)
        return try build(payload, script: script, shared: false)
    }

    /// Places the model's spans in the script and pads the paragraph notes.
    private static func build(_ payload: Payload, script: SpeechScript, shared: Bool) throws -> ScriptStudy {
        let paragraphs = ScriptStudy.paragraphs(script.body)
        let candidates: [ScriptStudy.Candidate] = (payload.highlights ?? []).compactMap { item in
            guard let text = item.text, let kind = ScriptStudy.Kind(rawValue: (item.kind ?? "").lowercased()) else { return nil }
            func clean(_ s: String?) -> String? {
                let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return t.isEmpty ? nil : t
            }
            return .init(text: text, kind: kind, lemma: clean(item.lemma),
                         note: clean(item.note) ?? "", example: clean(item.example))
        }
        let highlights = ScriptStudy.locate(candidates, in: paragraphs,
                                            spaced: LanguageCatalog.writesSpaces(script.language))
        var notes = (payload.paragraph_notes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if notes.count > paragraphs.count { notes = Array(notes.prefix(paragraphs.count)) }
        while notes.count < paragraphs.count { notes.append("") }
        guard !highlights.isEmpty || notes.contains(where: { !$0.isEmpty }) else { throw StudyError.empty }
        Analytics.capture("speech_study_made", ["highlights": highlights.count, "shared": shared])
        return ScriptStudy(highlights: highlights, paragraphNotes: notes)
    }
}
