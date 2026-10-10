import XCTest
@testable import FutureVoice

final class ReplyRevealTests: XCTestCase {
    func testFirstSentenceOnlyAtVoiceStart() {
        let text = "Oh nice, that sounds fun. What did you eat there? I'd love to know."
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0, charactersPerSecond: 14),
                       "Oh nice, that sounds fun.")
    }

    func testSentencesFollowThePace() {
        let text = "Oh nice, that sounds fun. What did you eat there? I'd love to know."
        // "Oh nice that sounds fun" = 20 letters → second sentence at ~1.43 s.
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 1.0, charactersPerSecond: 14),
                       "Oh nice, that sounds fun.")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 1.3, charactersPerSecond: 14),
                       "Oh nice, that sounds fun. What did you eat there?")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 10, charactersPerSecond: 14), text)
    }

    func testUnfinishedTailWaitsForFinal() {
        let text = "Sure thing. And then we"
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: false, elapsed: 10, charactersPerSecond: 14),
                       "Sure thing.")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 10, charactersPerSecond: 14), text)
    }

    func testNothingBeforeTheFirstSentenceEnds() {
        XCTAssertEqual(ReplyReveal.visible(text: "Well I think", isFinal: false, elapsed: 5, charactersPerSecond: 14), "")
    }

    func testJapaneseNeedsNoSpace() {
        let text = "いいね。何を食べたの？"
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0, charactersPerSecond: 7), "いいね。")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 5, charactersPerSecond: 7), text)
    }

    func testKoreanDefaultIsSyllabic() {
        XCTAssertEqual(ReplyReveal.defaultCharactersPerSecond(for: "좋아. 뭐 먹었어?", speed: 1), 7)
        XCTAssertEqual(ReplyReveal.defaultCharactersPerSecond(for: "Nice.", speed: 1), 14)
    }
}
