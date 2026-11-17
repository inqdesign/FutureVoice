import XCTest
@testable import FutureVoice

/// `ShadowEngine.restoringClearWords`, on the founder's take of 2026-11-17.
final class ReadBackRestoreTests: XCTestCase {
    private func w(_ word: String, _ acc: Int?, _ error: String = "None") -> PronunciationResult.Word {
        .init(word: word, accuracy: acc, error: error, offsetMs: 0, durationMs: 0, phonemes: [])
    }

    func testBrandNameAzureHeardIsPutBack() {
        let reference = "Good evening, ladies and gentlemen, and welcome aboard this nawana Air flight to London."
        let heard = "Good evening ladies and gentlemen and welcome aboard to this fly to London."
        let words = [w("good", 97), w("evening", 97), w("ladies", 56, "Mispronunciation"), w("and", 100),
                     w("gentlemen", 97), w("and", 100), w("welcome", 97), w("aboard", 94), w("this", 97),
                     w("nawana", 94), w("air", 97), w("flight", 97), w("to", 100), w("london", 91)]
        let r = ShadowEngine.restoringClearWords(heard: heard, reference: reference, words: words, language: "en")
        XCTAssertEqual(r.text, "Good evening ladies and gentlemen and welcome aboard this nawana air flight to London.")
        XCTAssertEqual(ShadowEngine.analyze(target: reference, learner: r.text).ratio, 1, accuracy: 0.001)
    }

    func testWordsAzureFaultedKeepTheReadBack() {
        let reference = "your tray table is stowed. Please switch all mobile phones and other electronic devices"
        let heard = "your tray table is stored. Please switch all mobile devices and other electric devices"
        let words = [w("your", 94), w("tray", 97), w("table", 97), w("is", 94), w("stowed", 29, "Mispronunciation"),
                     w("please", 100), w("switch", 100), w("all", 100), w("mobile", 97),
                     w("devices", 97, "Insertion"), w("phones", nil, "Omission"), w("and", 97), w("other", 97),
                     w("electronic", 19, "Mispronunciation"), w("devices", 100)]
        let r = ShadowEngine.restoringClearWords(heard: heard, reference: reference, words: words, language: "en")
        XCTAssertEqual(r.restored, 0)
        XCTAssertEqual(r.text, heard)
    }

    func testDroppedWordIsInsertedWhereItWasSaid() {
        let r = ShadowEngine.restoringClearWords(
            heard: "thank you for with us.", reference: "thank you for flying with us.",
            words: [w("thank", 97), w("you", 97), w("for", 97), w("flying", 92), w("with", 97), w("us", 97)],
            language: "en")
        XCTAssertEqual(r.text, "thank you for flying with us.")
        XCTAssertEqual(r.restored, 1)
    }

    func testUnspacedLanguagesAreLeftAlone() {
        let r = ShadowEngine.restoringClearWords(heard: "こんにちは", reference: "今日は",
                                                 words: [w("今日は", 97)], language: "ja")
        XCTAssertEqual(r.restored, 0)
    }
}
