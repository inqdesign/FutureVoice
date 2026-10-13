import XCTest
@testable import FutureVoice

final class ReplyRevealTests: XCTestCase {
    private let text = "Oh nice, that sounds fun. What did you eat there? I'd love to know."

    func testOnlyTheFirstWordsAtVoiceStart() {
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0, charactersPerSecond: 14), "Oh nice,")
    }

    func testWordsFollowThePace() {
        // "Oh nice that" = 10 letters → "sounds" starts at ~0.71 s.
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0.5, charactersPerSecond: 14),
                       "Oh nice, that")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0.6, charactersPerSecond: 14),
                       "Oh nice, that sounds")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 10, charactersPerSecond: 14), text)
    }

    func testSentenceGapHoldsTheNextWord() {
        // "What" starts after 20 letters (1.43 s) plus one sentence gap (0.4 s).
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 1.5, charactersPerSecond: 14),
                       "Oh nice, that sounds fun.")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 1.7, charactersPerSecond: 14),
                       "Oh nice, that sounds fun. What")
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

    func testJapaneseGoesByCharacter() {
        let text = "いいね。何を食べたの？"
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0, charactersPerSecond: 7), "いい")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0.3, charactersPerSecond: 7), "いいね。")
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 5, charactersPerSecond: 7), text)
    }

    func testKoreanGoesByWord() {
        let text = "좋아. 뭐 먹었어?"
        XCTAssertEqual(ReplyReveal.visible(text: text, isFinal: true, elapsed: 0, charactersPerSecond: 7), "좋아.")
    }

    func testOwnRateLeavesTheGapsOut() {
        // 49 letters, 3 sentences → 0.8 s of gaps in 4.3 s of audio.
        XCTAssertEqual(ReplyReveal.charactersPerSecond(text: text, seconds: 4.3)!, 14, accuracy: 0.01)
    }

    func testKoreanDefaultIsSyllabic() {
        XCTAssertEqual(ReplyReveal.defaultCharactersPerSecond(for: "좋아. 뭐 먹었어?", speed: 1), 7)
        XCTAssertEqual(ReplyReveal.defaultCharactersPerSecond(for: "Nice.", speed: 1), 14)
    }
}
