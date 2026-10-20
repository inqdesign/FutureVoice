import XCTest
@testable import FutureVoice

/// The accent the learner's voice speaks in decides which variety of the
/// language the prompts write and accept — and only a non-default accent
/// adds anything, so every other prompt is byte-identical.
final class LanguageVarietyTests: XCTestCase {

    func testDefaultAndMissingAccentAddNothing() {
        XCTAssertEqual(ConversationEngine.varietyGuard("en", accentId: nil), "")
        XCTAssertEqual(ConversationEngine.varietyGuard("en", accentId: "en-US"), "")
        XCTAssertEqual(ConversationEngine.varietyGuard("es", accentId: "es-MX"), "")
        XCTAssertEqual(ConversationEngine.varietyGuard("de", accentId: "de-DE"), "")
    }

    func testPickedVarietyIsNamed() {
        let british = ConversationEngine.varietyGuard("en", accentId: "en-GB")
        XCTAssertTrue(british.contains("British English"))
        XCTAssertTrue(british.contains("is NEVER a mistake"))
        XCTAssertTrue(ConversationEngine.varietyGuard("en", accentId: "en-AU").contains("Australian English"))
        XCTAssertTrue(ConversationEngine.varietyGuard("es", accentId: "es-ES").contains("Castilian"))
    }

    /// An accent left over from another target language says nothing about
    /// this one.
    func testAccentOfAnotherLanguageIsIgnored() {
        XCTAssertEqual(ConversationEngine.varietyGuard("de", accentId: "en-GB"), "")
        XCTAssertEqual(ConversationEngine.varietyGuard("es", accentId: "en-AU"), "")
    }
}
