import Foundation

// Test-harness stubs for the pieces the vector'd algorithms merely touch.
enum LanguageScope {
    static var active: String = "en"
    static var activeDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vecgen", isDirectory: true)
    }
}
protocol LanguageScopedStore: AnyObject { func languageScopeDidChange() }
enum StudyWidgetRefresher { static func schedule() {} }
enum Analytics { static func capture(_ name: String, _ props: [String: Any] = [:]) {} }
enum CoreVocabulary {
    static var set: Set<String> = []
    static func level(of word: String) -> CEFRLevel? { nil }
    static func level(ofSurface token: String) -> CEFRLevel? { nil }
    static func levelRank(_ l: CEFRLevel) -> Int { CEFRLevel.allCases.firstIndex(of: l) ?? 0 }
}
enum VocabStore {
    // Lemma paths are NOT vector'd (platform lemmatizers differ) — the
    // fixtures avoid studyingWords / word curriculum items entirely.
    static func lemmas(in texts: [String]) -> Set<String> { [] }
}
func explain(_ s: String) -> String { s }
func chrome(_ s: String) -> String { s }
enum PublicPersonaService { enum Group: String { case character, person } }

// ShadowEngine.matchWords references this; the vector'd `analyze` path never
// calls it, so a stub only needs to exist.
enum LocalAlignment { static func normalized(_ s: String) -> String { s } }
