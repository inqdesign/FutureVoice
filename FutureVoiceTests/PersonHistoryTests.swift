import XCTest
@testable import FutureVoice

final class PersonHistoryTests: XCTestCase {
    private let person = UUID()

    private func talk(with id: UUID?, ending end: Date, lines: [String], learnerSpoke: Bool = true) -> Session {
        var turns: [Turn] = []
        for (i, text) in lines.enumerated() {
            let isUser = learnerSpoke && i % 2 == 1
            turns.append(Turn(id: UUID(), role: isUser ? .user : .fluentSelf, audioURL: nil,
                              transcript: text, durationMs: 1000,
                              timestamp: end.addingTimeInterval(Double(i - lines.count)), suggestion: nil))
        }
        var s = Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                        topic: nil, startedAt: end.addingTimeInterval(-300), endedAt: end,
                        turns: turns, summary: nil)
        s.counterpartId = id
        return s
    }

    func testNoTalkWithThemIsNoHistory() {
        let other = talk(with: UUID(), ending: Date(), lines: ["hi", "hello"])
        XCTAssertNil(PersonHistory.build(personId: person, sessions: [other], excluding: nil, pickUp: false))
    }

    func testATalkTheLearnerNeverSpokeInIsNotHistory() {
        let silent = talk(with: person, ending: Date(), lines: ["hi"], learnerSpoke: false)
        XCTAssertNil(PersonHistory.build(personId: person, sessions: [silent], excluding: nil, pickUp: false))
    }

    func testTheLastTalkIsQuotedAndTheOlderOnesCounted() {
        let old = talk(with: person, ending: Date().addingTimeInterval(-86_400 * 3), lines: ["a", "b"])
        let last = talk(with: person, ending: Date().addingTimeInterval(-3600),
                        lines: ["How was the move?", "Still unpacking boxes."])
        let h = PersonHistory.build(personId: person, sessions: [old, last], excluding: nil, pickUp: false)!
        XCTAssertEqual(h.talks, 2)
        XCTAssertEqual(h.earlier.count, 1)
        let block = h.promptBlock(name: "Sarah", languageName: "English")
        XCTAssertTrue(block.contains("Sarah: How was the move?"), block)
        XCTAssertTrue(block.contains("User: Still unpacking boxes."), block)
        XCTAssertTrue(block.contains("talked 2 times"), block)
        XCTAssertFalse(block.contains("PICK UP"), block)
    }

    func testTheCurrentSessionIsNotItsOwnHistory() {
        let resumed = talk(with: person, ending: Date(), lines: ["hi", "hello"])
        XCTAssertNil(PersonHistory.build(personId: person, sessions: [resumed],
                                         excluding: resumed.id, pickUp: true))
    }

    func testPickUpAsksTheFirstLineToComeOutOfTheLastTalk() {
        let last = talk(with: person, ending: Date(), lines: ["hi", "hello"])
        let h = PersonHistory.build(personId: person, sessions: [last], excluding: nil, pickUp: true)!
        XCTAssertTrue(h.promptBlock(name: "Sarah", languageName: "English")
            .contains("THEY CHOSE TO PICK UP WHERE YOU LEFT OFF"))
    }

    func testOnlyTheEndOfALongTalkIsQuoted() {
        let lines = (0..<80).map { "line \($0)" }
        let h = PersonHistory.build(personId: person,
                                    sessions: [talk(with: person, ending: Date(), lines: lines)],
                                    excluding: nil, pickUp: false)!
        XCTAssertEqual(h.lastLines.count, PersonHistory.maxLines)
        XCTAssertEqual(h.lastLines.last?.text, "line 79")
    }
}
