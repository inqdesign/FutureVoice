import Foundation

/// The vocabulary pool, loaded from the bundled CEFR-graded word list
/// (`cefr_words.tsv`, A1–C2, content words only — from the CEFR-J and Octanove
/// vocabulary profiles). Each word carries its real CEFR level, so the level
/// filter is accurate (frequency rank was NOT a valid level proxy). Headwords
/// are already lemmas, so they match the lemmatized user speech directly.
enum CoreVocabulary {
    struct Entry: Identifiable { let word: String; let level: CEFRLevel; var id: String { word } }

    static let entries: [Entry] = load()
    static let set: Set<String> = Set(entries.map { $0.word })
    static var total: Int { entries.count }

    private static let levelByWord: [String: CEFRLevel] =
        Dictionary(entries.map { ($0.word, $0.level) }, uniquingKeysWith: { a, _ in a })

    static func level(of word: String) -> CEFRLevel? { levelByWord[word] }

    static func levelRank(_ l: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: l) ?? 0
    }

    private static func load() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "cefr_words", withExtension: "tsv"),
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
