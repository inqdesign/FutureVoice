import XCTest
@testable import FutureVoice

/// The per-language call lines (2026-11-06) must reach their own language
/// only: every other language's prompt stays byte-identical.
final class LanguageLineTests: XCTestCase {

    func testOtherLanguagesGetNothing() {
        for lang in ["en", "fr", "zh-Hans"] {
            XCTAssertEqual(ConversationEngine.beginnerQuestionLanguageLine(lang), "", lang)
            XCTAssertEqual(ConversationEngine.selfAddressLine(lang, asFutureSelf: true), "", lang)
            XCTAssertEqual(ConversationEngine.spanishGuard(lang, asFutureSelf: true, accentId: nil), "", lang)
        }
        for lang in ["en", "es", "zh-Hans"] {
            XCTAssertEqual(ConversationEngine.frenchGuard(lang, asFutureSelf: true), "", lang)
        }
        XCTAssertEqual(ConversationEngine.beginnerQuestions(.a2, targetLanguage: "en"),
                       ConversationEngine.beginnerQuestions(.a2))
        XCTAssertEqual(ConversationEngine.beginnerQuestions(.b1, targetLanguage: "ko"), "")
    }

    func testEachLanguageGetsItsLine() {
        XCTAssertTrue(ConversationEngine.beginnerQuestions(.a1, targetLanguage: "ko").contains("KOREAN, BEGINNER"))
        XCTAssertTrue(ConversationEngine.beginnerQuestions(.a2, targetLanguage: "ja").contains("JAPANESE, BEGINNER"))
        XCTAssertEqual(ConversationEngine.beginnerQuestionLanguageLine("de"), "")
        XCTAssertEqual(ConversationEngine.beginnerQuestionLanguageLine("es"), "")
    }

    func testFutureSelfOnlyLines() {
        XCTAssertTrue(ConversationEngine.selfAddressLine("ja", asFutureSelf: true).contains("bare name"))
        XCTAssertEqual(ConversationEngine.selfAddressLine("ja", asFutureSelf: false), "")
        let cast = ConversationEngine.spanishGuard("es", asFutureSelf: false, accentId: nil)
        XCTAssertFalse(cast.contains("GENDER"))
        XCTAssertTrue(cast.contains("WHICH SPANISH"))
        XCTAssertTrue(ConversationEngine.spanishGuard("es", asFutureSelf: true, accentId: nil).contains("GENDER"))
        XCTAssertTrue(ConversationEngine.frenchGuard("fr", asFutureSelf: true).contains("FRENCH, GENDER"))
        XCTAssertEqual(ConversationEngine.frenchGuard("fr", asFutureSelf: false), "")
    }

    func testCoachingLinesStayInTheirLanguage() {
        for lang in ["en", "ko", "it"] {
            XCTAssertEqual(ConversationEngine.spokenGrammarGuard(lang), "", lang)
            XCTAssertEqual(CoachSuggester.bracketAgreementLine(lang), "", lang)
            XCTAssertEqual(ConversationEngine.notesLanguageGuard(lang, nativeLanguage: "ko"), "", lang)
        }
        XCTAssertEqual(ConversationEngine.tutorRegisterLine("en"), "")
        XCTAssertEqual(ConversationEngine.tutorRegisterLine("de"), "")
        // A learner whose native language IS the target gets no notes line.
        XCTAssertEqual(ConversationEngine.notesLanguageGuard("de", nativeLanguage: "de"), "")
        XCTAssertTrue(ConversationEngine.notesLanguageGuard("ja", nativeLanguage: "ko").contains("NOTES IN KOREAN"))
        XCTAssertTrue(ConversationEngine.notesLanguageGuard("de", nativeLanguage: "ko").contains("NOTES IN KOREAN"))
        XCTAssertTrue(ConversationEngine.notesLanguageGuard("ja", nativeLanguage: "en").contains("never in Japanese"))
        XCTAssertTrue(ConversationEngine.spokenGrammarGuard("es").contains("REPORTED SPEECH"))
        XCTAssertTrue(ConversationEngine.spokenGrammarGuard("de").contains("DEMONSTRATIVES"))
        XCTAssertTrue(ConversationEngine.spokenGrammarGuard("fr").contains("SPOKEN FRENCH"))
        XCTAssertTrue(ConversationEngine.notesLanguageGuard("fr", nativeLanguage: "ko").contains("NOTES IN KOREAN"))
        XCTAssertTrue(ConversationEngine.tutorRegisterLine("ko").contains("반말"))
        XCTAssertTrue(ConversationEngine.tutorRegisterLine("ja").contains("plain form"))
        XCTAssertTrue(ConversationEngine.tutorRegisterLine("es").contains("Dilo otra vez"))
        XCTAssertTrue(CoachSuggester.bracketAgreementLine("de").contains("seit [zwei Jahren]"))
        XCTAssertTrue(CoachSuggester.bracketAgreementLine("es").contains("tengo [un hermano]"))
    }
}
