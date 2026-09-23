import XCTest
@testable import FutureVoice

/// The code half of the correction guards: a "fix" that changes only what the
/// transcriber chose must never reach the learner, whatever the language.
final class CorrectionGuardTests: XCTestCase {

    private func withActiveLanguage<T>(_ code: String, _ body: () throws -> T) rethrows -> T {
        let key = LanguageCatalog.targetLanguageDefaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(code, forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        return try body()
    }

    func testEnglishContractionsDigitsAndPunctuationAreTheTranscribers() {
        withActiveLanguage("en") {
            XCTAssertTrue(ConversationEngine.saysTheSameThing("I am building an app", "I'm building an app."))
            XCTAssertTrue(ConversationEngine.saysTheSameThing("I said it 3 times", "I said it three times"))
            XCTAssertTrue(ConversationEngine.saysTheSameThing("a check-in at 9", "a check in at nine"))
            XCTAssertFalse(ConversationEngine.saysTheSameThing("I very like it", "I really like it"))
        }
    }

    func testKoreanSpacingIsTheTranscribers() {
        withActiveLanguage("ko") {
            XCTAssertTrue(ConversationEngine.saysTheSameThing("한번 해볼게요", "한 번 해 볼게요."))
            XCTAssertTrue(ConversationEngine.saysTheSameThing("못해요", "못 해요"))
            XCTAssertFalse(ConversationEngine.saysTheSameThing("밥 먹었어", "밥 먹었어요"))
        }
    }

    func testScriptCheckPerLanguage() {
        XCTAssertTrue(TextScript.isInTargetScript("Show me the clock once.", language: "en"))
        XCTAssertFalse(TextScript.isInTargetScript("한번 나올게 해줘 시계.", language: "en"))
        XCTAssertTrue(TextScript.isInTargetScript("nawana 앱을 만들고 있어요", language: "ko"))
        XCTAssertTrue(TextScript.isInTargetScript("時計を見せて。", language: "ja"))
        XCTAssertTrue(TextScript.isInTargetScript("nawana アプリを作っています", language: "ja"))
        XCTAssertFalse(TextScript.isInTargetScript("Show me 時計", language: "ja"))
        XCTAssertTrue(TextScript.isInTargetScript("Ich hätte gern einen Kaffee, bitte.", language: "de"))
        XCTAssertFalse(TextScript.isInTargetScript("", language: "en"))
    }
}
