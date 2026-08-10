import XCTest
@testable import FutureVoice

/// The streaming turn decides what the fluent self SAYS, from JSON that is
/// still half-written. Both halves are covered here: pulling a field out of a
/// partial body, and cutting the first sentence off it early.
final class StreamingReplyTests: XCTestCase {

    // MARK: - streamingStringField

    func testReportsPartialValueBeforeClosingQuote() {
        let partial = #"{"reply": "Sure, let's talk about"#
        let field = GeminiClient.streamingStringField("reply", in: partial)
        XCTAssertEqual(field?.value, "Sure, let's talk about")
        XCTAssertEqual(field?.isComplete, false)
        XCTAssertNil(GeminiClient.completedStringField("reply", in: partial))
    }

    func testReportsCompleteValueAtClosingQuote() {
        let partial = #"{"reply": "Sure.", "suggestion":"#
        let field = GeminiClient.streamingStringField("reply", in: partial)
        XCTAssertEqual(field?.value, "Sure.")
        XCTAssertEqual(field?.isComplete, true)
        XCTAssertEqual(GeminiClient.completedStringField("reply", in: partial), "Sure.")
    }

    func testFieldAbsentUntilItsKeyArrives() {
        XCTAssertNil(GeminiClient.streamingStringField("reply", in: #"{"rep"#))
    }

    /// A value that OPENS a nested body is the model re-emitting the whole
    /// schema inside the field. Speaking "{" is worse than staying silent.
    func testPartialNestedSchemaIsNotReported() {
        XCTAssertNil(GeminiClient.streamingStringField("reply", in: #"{"reply": "{"repl"#))
    }

    // MARK: - firstSpeakableSentence

    func testSplitsAtFirstSentenceOnceWhitespaceConfirmsIt() {
        let partial = "That sounds like a great plan. I went there"
        XCTAssertEqual(GeminiClient.firstSpeakableSentence(in: partial),
                       "That sounds like a great plan.")
    }

    /// The terminator is the last character on the wire — it could still be a
    /// decimal point or an abbreviation. Wait one more token.
    func testWaitsForTheCharacterAfterTheTerminator() {
        XCTAssertNil(GeminiClient.firstSpeakableSentence(in: "That sounds like a great plan."))
    }

    func testDoesNotSplitInsideADecimal() {
        let partial = "It costs about 12.50 euros in that neighbourhood, which is fine. Next"
        XCTAssertEqual(GeminiClient.firstSpeakableSentence(in: partial),
                       "It costs about 12.50 euros in that neighbourhood, which is fine.")
    }

    /// Below the minimum there is nothing to gain — a seam would cost more
    /// than the few milliseconds saved.
    func testShortOpenerIsNotWorthSplitting() {
        XCTAssertNil(GeminiClient.firstSpeakableSentence(in: "Sure. I went there last year"))
        XCTAssertNil(GeminiClient.firstSpeakableSentence(in: "네, 맞아요. 그래서"))
    }

    /// A Hangul syllable is a whole syllable of speech, a Latin letter is a
    /// fraction of one. Counting raw characters would never split Korean.
    func testKoreanSentenceSplitsAtItsOwnLength() {
        XCTAssertEqual(
            GeminiClient.firstSpeakableSentence(in: "저도 그 영화를 지난주에 봤어요. 정말"),
            "저도 그 영화를 지난주에 봤어요.")
    }

    func testNoSplitWithoutASentenceBreak() {
        XCTAssertNil(GeminiClient.firstSpeakableSentence(
            in: "I have been thinking about that for a while and honestly"))
    }

    func testHandlesQuestionMarksAndFullWidthTerminators() {
        XCTAssertEqual(
            GeminiClient.firstSpeakableSentence(in: "So how did the interview actually go? Tell me"),
            "So how did the interview actually go?")
        XCTAssertEqual(
            GeminiClient.firstSpeakableSentence(in: "그 인터뷰는 어떻게 됐는지 정말 궁금해요。 그리고"),
            "그 인터뷰는 어떻게 됐는지 정말 궁금해요。")
    }

    /// The caller joins the two halves with `hasPrefix` + `dropFirst`, so the
    /// sentence must be a literal prefix of the finished reply.
    func testSentenceIsAPrefixOfTheFullReply() {
        let full = "That sounds like a great plan. When are you going?"
        let sentence = GeminiClient.firstSpeakableSentence(in: full)
        XCTAssertNotNil(sentence)
        XCTAssertTrue(full.hasPrefix(sentence!))
        let rest = String(full.dropFirst(sentence!.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(rest, "When are you going?")
    }
}
