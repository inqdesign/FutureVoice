import Foundation

/// The vocabulary pool for the CURRENT target language, loaded from the
/// graded word list that `LanguageCatalog` names for it (English:
/// `cefr_words.tsv`, A1–C2, content words only — from the CEFR-J and Octanove
/// vocabulary profiles). Each word carries its real CEFR level, so the level
/// filter is accurate (frequency rank was NOT a valid level proxy). Headwords
/// are already lemmas, so they match the lemmatized user speech directly.
///
/// Languages without a bundled list yet get an EMPTY pool — vocab tracking
/// honestly shows nothing rather than grading against English words. Pools
/// are cached per language, so a target-language switch swaps pools
/// immediately (pre-multi-language this loaded once per launch).
enum CoreVocabulary {
    struct Entry: Identifiable { let word: String; let level: CEFRLevel; var id: String { word } }

    private struct Pool {
        let entries: [Entry]
        let set: Set<String>
        let levelByWord: [String: CEFRLevel]
        let countByLevel: [CEFRLevel: Int]
    }

    private static var pools: [String: Pool] = [:]
    private static let lock = NSLock()

    private static var current: Pool { pool(for: LanguageScope.active) }

    private static func pool(for code: String) -> Pool {
        lock.lock(); defer { lock.unlock() }
        if let cached = pools[code] { return cached }
        let entries = loadEntries(for: code)
        let pool = Pool(
            entries: entries,
            set: Set(entries.map(\.word)),
            levelByWord: Dictionary(entries.map { ($0.word, $0.level) },
                                    uniquingKeysWith: { a, _ in a }),
            countByLevel: Dictionary(entries.map { ($0.level, 1) }, uniquingKeysWith: +)
        )
        pools[code] = pool
        return pool
    }

    static var entries: [Entry] { current.entries }
    static var set: Set<String> { current.set }
    static var total: Int { current.entries.count }

    static func level(of word: String) -> CEFRLevel? { current.levelByWord[word] }

    /// Grades a SPOKEN surface token. English callers pre-lemmatize so this
    /// is a direct lookup; Korean surface forms carry particles/conjugation,
    /// so they route through the KoreanMorph headword heuristic first.
    static func level(ofSurface token: String) -> CEFRLevel? {
        if isKorean {
            guard let head = KoreanMorph.dictionaryForm(of: token, in: set) else { return nil }
            return level(of: head)
        }
        return level(of: token)
    }

    private static var isKorean: Bool {
        LanguageCatalog.language(LanguageScope.active)?.code == "ko"
    }

    /// Words per CEFR level — for filter-scoped counts in the UI.
    static var countByLevel: [CEFRLevel: Int] { current.countByLevel }
    static func total(at level: CEFRLevel) -> Int { countByLevel[level] ?? 0 }

    static func levelRank(_ l: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: l) ?? 0
    }

    private static func loadEntries(for code: String) -> [Entry] {
        guard let resource = LanguageCatalog.language(code)?.wordlistResource else {
            return []
        }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        var out: [Entry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            guard parts.count == 2,
                  let level = CEFRLevel(rawValue: parts[1].lowercased()) else { continue }
            out.append(Entry(word: String(parts[0]), level: level))
        }
        // Easiest level first, then alphabetical — stable order.
        return out.sorted {
            levelRank($0.level) != levelRank($1.level)
                ? levelRank($0.level) < levelRank($1.level)
                : $0.word < $1.word
        }
    }

    private static let fallback: [Entry] = [
        Entry(word: "talk", level: .a1), Entry(word: "learn", level: .a1),
        Entry(word: "fluent", level: .b2), Entry(word: "practice", level: .a2)
    ]
}
