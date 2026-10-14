import XCTest
@testable import FutureVoice

/// The ≈Fluency band on Progress. Reported 2026-10-14: a B1 learner read
/// ≈C2 after a few plain calls of short answers — pace alone rewards short
/// turns. These pin the two guards: enough speech, and turn length as a cap.
final class FluencyBandTests: XCTestCase {

    private func band(pace: Int, articulation: Bool = true,
                      seconds: Double = 600, wordsPerTurn: Int = 30)
        -> (level: CEFRLevel, cappedAt: CEFRLevel?)? {
        ProgressTab.fluencyBand(pace: pace, isArticulation: articulation,
                                speakingSeconds: seconds, wordsPerTurn: wordsPerTurn)
    }

    /// The reported case: fast, short answers. Turn length decides.
    func testFastShortAnswersAreCappedByTurnLength() {
        // 8 words/turn = ≈A2 expression → cap one above, B1.
        let r = band(pace: 160, wordsPerTurn: 8)
        XCTAssertEqual(r?.level, .b1)
        XCTAssertEqual(r?.cappedAt, .b1)
    }

    /// Long turns at a high pace: the pace stands.
    func testFastLongTurnsReadHigh() {
        let r = band(pace: 160, wordsPerTurn: 40)
        XCTAssertEqual(r?.level, .c2)
        XCTAssertNil(r?.cappedAt)
    }

    /// The cap never RAISES the band.
    func testTurnLengthIsACeilingNotAFloor() {
        let r = band(pace: 70, wordsPerTurn: 40)
        XCTAssertEqual(r?.level, .a2)
        XCTAssertNil(r?.cappedAt)
    }

    /// Under three minutes of the learner's own voice there is no band.
    func testTooLittleSpeechReadsNoBand() {
        XCTAssertNil(band(pace: 160, seconds: 90))
        XCTAssertNotNil(band(pace: 160, seconds: ProgressTab.minFluencySpeakingSeconds))
    }

    /// Wall-clock pace keeps its +20 shift.
    func testWallClockPaceIsShifted() {
        XCTAssertEqual(band(pace: 90, articulation: false)?.level, .b2)
        XCTAssertEqual(band(pace: 90, articulation: true)?.level, .b1)
    }
}
