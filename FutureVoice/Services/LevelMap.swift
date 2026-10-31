import Foundation

/// The level map for one target language: what each spoken step needs
/// (docs/personal-report-plan.md, part 1). The same for every learner;
/// `LearnerState` is where one learner stands on it.
///
/// Read from `level_map_<code>.json` in the bundle. Only English exists
/// (2026-10-27); every other language returns nil, and everything built on
/// the map — the tagging call, the learner state, the prompt block — stands
/// down for it without a word. Grammar differs per language, so a map is
/// written and probed per language (plan step 6), never translated.
struct LevelMap: Decodable {
    /// A grammar structure, tagged right/wrong per talk.
    struct Grammar: Decodable, Hashable {
        let id: String
        /// The step at which the item should be SOLID.
        let level: CEFRLevel
        let name: String
        /// What counts as a use — read by the tagging prompt.
        let counts: String
        let example: String
        let error: String
        /// Items this one builds on (past simple before present perfect).
        let requires: [String]
    }

    /// Something a speaker DOES with the language (tell a story in order,
    /// give a reason). Tagged when the learner did it; there is no "wrong".
    struct Function: Decodable, Hashable {
        let id: String
        let level: CEFRLevel
        let name: String
        let counts: String
    }

    let language: String
    let version: Int
    let grammar: [Grammar]
    let functions: [Function]

    /// Every item id, grammar and function — the tagger drops anything else.
    var itemIds: Set<String> { Set(grammar.map(\.id) + functions.map(\.id)) }

    // MARK: - Loading

    private static let lock = NSLock()
    /// Decoded once per language per launch; `nil` cached too, so a language
    /// with no map costs one bundle lookup, not one per talk.
    private static var cache: [String: LevelMap?] = [:]

    /// The map for `code` ("en", "en-GB" → "en"), or nil when the language
    /// has none.
    static func load(_ code: String) -> LevelMap? {
        let base = LanguageCatalog.base(code)
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[base] { return hit }
        let name = "level_map_\(base)"
        // xcodegen copies a folder's files to the bundle root; a folder
        // reference would keep `LevelMap/`. Either way is found.
        let url = Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "LevelMap")
        let map = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(LevelMap.self, from: $0) }
        cache[base] = map
        return map
    }
}
