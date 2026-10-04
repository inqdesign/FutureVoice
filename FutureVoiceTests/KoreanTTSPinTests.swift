import XCTest
@testable import FutureVoice

/// `language_code` is pinned only for a Korean learner's Hangul line
/// (2026-10-05, `ElevenLabsClient.pinnedLanguage`). Everything else must keep
/// sending what it sent before.
final class KoreanTTSPinTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private func target(_ code: String) {
        UserDefaults.standard.set(code, forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    func testKoreanLineForKoreanLearnerIsPinned() {
        target("ko")
        XCTAssertEqual(ElevenLabsClient.pinnedLanguage(for: "안녕, 몇 년 뒤의 너야. 요즘 어떻게 지내?"), "ko")
        XCTAssertEqual(ElevenLabsClient.pinnedLanguage(for: "nawana 앱을 만들고 있어요"), "ko")
    }

    func testEnglishLineForKoreanLearnerIsNotPinned() {
        target("ko")
        XCTAssertNil(ElevenLabsClient.pinnedLanguage(for: "Hi, it's you from a few years on."))
    }

    func testOtherTargetsAreUntouched() {
        target("en")
        XCTAssertNil(ElevenLabsClient.pinnedLanguage(for: "안녕, 반가워. 오늘 뭐 했어?"))
        target("ja")
        XCTAssertNil(ElevenLabsClient.pinnedLanguage(for: "こんにちは、元気？"))
    }
}
