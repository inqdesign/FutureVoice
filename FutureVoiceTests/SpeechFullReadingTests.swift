import XCTest
@testable import FutureVoice

/// A challenge counts only when its script is read to the end (2026-11-18).
@MainActor
final class SpeechFullReadingTests: XCTestCase {
    private let script = """
    Good evening, everyone. Thank you for coming tonight. We started this project two years ago \
    with a small team and a big idea. Today it reaches people in more than forty countries, and \
    every one of them found it because someone told a friend. So tonight is for you, the people \
    who kept telling friends. Raise your glasses, and let's make the next two years even better.
    """

    func testWholeReadingWithASlipCounts() {
        let said = script.replacingOccurrences(of: "small team", with: "smaller team")
        XCTAssertGreaterThanOrEqual(SpeechChallenges.readShare(script: script, transcript: said, language: "en"),
                                    SpeechChallenges.fullReading)
    }

    func testStoppingHalfwayDoesNotCount() {
        let half = "Good evening, everyone. Thank you for coming tonight. We started this project two years ago with a small team and a big idea."
        XCTAssertLessThan(SpeechChallenges.readShare(script: script, transcript: half, language: "en"),
                          SpeechChallenges.fullReading)
    }

    func testSkippingASentenceDoesNotCount() {
        let skipped = script.replacingOccurrences(
            of: "So tonight is for you, the people who kept telling friends. ", with: "")
        XCTAssertLessThan(SpeechChallenges.readShare(script: script, transcript: skipped, language: "en"),
                          SpeechChallenges.fullReading)
    }
}
