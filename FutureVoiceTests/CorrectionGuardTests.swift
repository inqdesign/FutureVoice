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

    func testKoreanReorderAloneIsNotACorrection() {
        withActiveLanguage("ko") {
            XCTAssertTrue(ConversationEngine.changesOnlyWordOrder("먹었어 아까 라면", "아까 라면 먹었어."))
            XCTAssertFalse(ConversationEngine.changesOnlyWordOrder("나는 너를 보고 싶어 어제", "어제 너를 보고 싶었어"))
            XCTAssertFalse(ConversationEngine.changesOnlyWordOrder("밥 먹었어", "밥 먹었어"))
            XCTAssertFalse(ConversationEngine.changesOnlyWordOrder("밥 먹었어", "밥 먹었어요"))
        }
        withActiveLanguage("en") {
            XCTAssertFalse(ConversationEngine.changesOnlyWordOrder("I yesterday went home", "I went home yesterday"))
        }
    }

    func testSpeechLevelGuardRidesOnlyKoreanAndJapanese() {
        XCTAssertTrue(ConversationEngine.registerGuard("en").isEmpty)
        XCTAssertTrue(ConversationEngine.registerGuard("de").isEmpty)
        XCTAssertTrue(ConversationEngine.registerGuard("ko").contains("KOREAN HONORIFICS"))
        XCTAssertTrue(ConversationEngine.registerGuard("ja").contains("SPEECH LEVEL"))
        XCTAssertFalse(ConversationEngine.registerGuard("ja").contains("KOREAN"))
        XCTAssertTrue(ConversationEngine.registerGuard("ja").contains("JAPANESE HONORIFICS"))
        XCTAssertFalse(ConversationEngine.registerGuard("ko").contains("JAPANESE"))
        let live = ConversationEngine.correctionOnlyPrompt(targetLanguage: "ko", nativeLanguage: "en", level: .a2)
        XCTAssertTrue(live.contains("KOREAN HONORIFICS"))
        let http = ConversationEngine.turnOutputInstruction(targetLanguage: "ko", nativeLanguage: "en")
        XCTAssertTrue(http.contains("KOREAN HONORIFICS"))
        let profile = LearnerProfile(
            id: UUID(), userId: UUID(), targetLanguage: "ko",
            proficiencyLevel: .a2, recurringMistakes: [], weakVocabAreas: [],
            strongPatterns: [], totalSessions: 0, totalSpeakingSeconds: 0,
            lastSessionAt: nil, summaryEmbedding: nil)
        let summary = ConversationEngine.summarySystemPrompt(targetLanguage: "ko", nativeLanguage: "en", profile: profile)
        XCTAssertTrue(summary.contains("KOREAN HONORIFICS"))
        XCTAssertFalse(ConversationEngine.correctionOnlyPrompt(targetLanguage: "en", nativeLanguage: "ko", level: .a2).contains("SPEECH LEVEL"))
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
