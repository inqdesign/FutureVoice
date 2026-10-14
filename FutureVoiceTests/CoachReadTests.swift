import XCTest
@testable import FutureVoice

/// Coach mode is judged per line: only a line READ off the "try saying" is
/// practice; an answer in the learner's own words, or one built around the
/// word hint, is evidence (`CoachRead`, 2026-10-14).
final class CoachReadTests: XCTestCase {
    private let line = "I usually get up at [7] on weekdays."

    func testReadingTheSuggestionIsRead() {
        XCTAssertTrue(CoachRead.isRead("I usually get up at 7 on weekdays.", line: line))
        // The faded example is theirs to swap.
        XCTAssertTrue(CoachRead.isRead("I usually get up at six thirty on weekdays", line: line))
    }

    func testOwnWordsAreNotRead() {
        XCTAssertFalse(CoachRead.isRead("Honestly I sleep in, my job starts at noon.", line: line))
        // Read the start, then carried on in their own words.
        XCTAssertFalse(CoachRead.isRead(
            "I usually get up at 7 on weekdays, but lately my daughter wakes me before that and I can't fall asleep again",
            line: line))
    }

    func testAShortSuggestionNeverCountsAsRead() {
        XCTAssertFalse(CoachRead.isRead("Yes, I do.", line: "Yes, [I do]."))
    }

    func testNoSuggestionIsNeverRead() {
        XCTAssertFalse(CoachRead.isRead("I usually get up at 7 on weekdays.", line: nil))
    }

    func testReadLineIsNotEvidence() {
        var turn = Turn(id: UUID(), role: .user, audioURL: nil,
                        transcript: "I usually get up at 7 on weekdays.",
                        durationMs: 0, timestamp: Date(), suggestion: nil)
        XCTAssertTrue(turn.isEvidence)
        turn.coachLine = line
        XCTAssertTrue(turn.readFromCoach)
        XCTAssertFalse(turn.isEvidence)
        // Survives a save.
        let back = try! JSONDecoder().decode(Turn.self, from: JSONEncoder().encode(turn))
        XCTAssertEqual(back.coachLine, line)
        XCTAssertFalse(back.isEvidence)
    }
}
