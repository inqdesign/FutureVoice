import XCTest
@testable import FutureVoice

/// A free talk's memory of the talks before it (2026-11-17, `TalkRecall`).
final class TalkRecallTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func line(_ role: TurnRole, _ text: String, _ at: Date, misheard: Bool = false) -> Turn {
        var t = Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
                     durationMs: 1000, timestamp: at, suggestion: nil)
        t.excludedFromScoring = misheard
        return t
    }

    private func talk(_ title: String?, end: Date, lines: [(TurnRole, String)],
                      counterpart: UUID? = nil) -> Session {
        let turns = lines.enumerated().map { i, l in
            line(l.0, l.1, end.addingTimeInterval(Double(i - lines.count) * 20))
        }
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: title, startedAt: end.addingTimeInterval(-600), endedAt: end,
                       turns: turns, summary: nil, counterpartId: counterpart)
    }

    private lazy var interview = talk("Interview at the bank on Friday", end: at(10, 9), lines: [
        (.fluentSelf, "Hey, how are you?"),
        (.user, "I have an interview at the bank on Friday and I am nervous."),
        (.fluentSelf, "Which part worries you?"),
        (.user, "The salary question, I never know what number to say."),
    ])
    private lazy var trip = talk("Weekend trip to Busan", end: at(14, 20), lines: [
        (.user, "We went to Busan and ate raw fish at the market."),
        (.fluentSelf, "Nice. Was it crowded?"),
    ])

    func testTheIndexIsTalksWithTheFluentSelfNewestFirst() {
        let withFriend = talk("Coffee with Sarah", end: at(15, 9), lines: [(.user, "hi")], counterpart: UUID())
        let silent = talk("Nothing said", end: at(15, 10), lines: [(.fluentSelf, "Hello?")])
        let index = TalkRecall.index(sessions: [interview, trip, withFriend, silent],
                                     now: at(17, 9), excluding: [])
        XCTAssertEqual(index.map(\.title), ["Weekend trip to Busan", "Interview at the bank on Friday"])
        XCTAssertEqual(TalkRecall.index(sessions: [interview, trip], now: at(17, 9),
                                        excluding: [trip.id]).map(\.title),
                       ["Interview at the bank on Friday"])
        let lines = TalkRecall.indexLines(index, now: at(17, 9), calendar: cal)
        XCTAssertTrue(lines[0].contains("Weekend trip to Busan"))
        XCTAssertTrue(lines[0].hasPrefix("3 days ago"), lines[0])
    }

    func testOnlyALineThatPointsBackIsAskedAbout() {
        let index = TalkRecall.index(sessions: [interview, trip], now: at(17, 9), excluding: [])
        XCTAssertTrue(TalkRecall.mayRecall("Remember what I told you last week?", entries: index))
        XCTAssertTrue(TalkRecall.mayRecall("So the interview went well", entries: index))
        XCTAssertFalse(TalkRecall.mayRecall("I am cooking pasta now", entries: index))
        XCTAssertFalse(TalkRecall.mayRecall("Remember what I told you?", entries: []))
    }

    func testTheRecordCentresOnWhatIsBeingTalkedAbout() {
        var long: [(TurnRole, String)] = []
        for i in 0..<30 {
            long.append((.user, "filler number \(i) about nothing much at all today"))
            long.append((.fluentSelf, "reply number \(i)"))
        }
        long.insert((.user, "My landlord wants to raise the rent by ten percent."), at: 40)
        let s = talk("A long one", end: at(12, 9), lines: long)
        let entry = TalkRecall.index(sessions: [s], now: at(17, 9), excluding: [])[0]
        let record = TalkRecall.record(of: entry, about: "the landlord thing got worse", now: at(17, 9),
                                       calendar: cal)
        XCTAssertTrue(record.contains("landlord wants to raise the rent"))
        XCTAssertTrue(record.contains("Part of it, oldest first:"))
        XCTAssertFalse(record.contains("filler number 0 "))
        XCTAssertLessThan(record.count, 2700)
    }

    func testAMisheardLineAndItsReplyStayOut() {
        var s = interview
        s.turns.append(line(.user, "She is here for six month.", at(10, 9), misheard: true))
        s.turns.append(line(.fluentSelf, "Oh, your friend is staying six months?", at(10, 9)))
        let entry = TalkRecall.index(sessions: [s], now: at(17, 9), excluding: [])[0]
        let record = TalkRecall.record(of: entry, about: "", now: at(17, 9), calendar: cal)
        XCTAssertTrue(record.contains("All of it, oldest first:"))
        XCTAssertTrue(record.contains("salary question"))
        XCTAssertFalse(record.contains("six month"))
    }

    /// No earlier talk, nothing looked up: the prompt is what it was.
    func testThePromptIsUnchangedWithoutThem() {
        func prompt(_ past: [String], _ recalled: [String]) -> String {
            ConversationEngine.freeTalkPrompt(
                targetLanguage: "en", nativeLanguage: "ko", level: .b2, topPatterns: [],
                weakVocabAreas: [], topic: "", persona: nil, newsFacts: [], clock: nil,
                earlierToday: nil, learnerPicksTopic: false, pastTalks: past, recalledTalks: recalled,
                gender: nil)
        }
        let bare = prompt([], [])
        XCTAssertFalse(bare.contains("other talks you two had"))
        let full = prompt(["3 days ago: \"Weekend trip to Busan\""],
                          ["A talk you two had 3 days ago, \"Weekend trip to Busan\".\nAll of it, oldest first:\nthem: \"We went to Busan\""])
        XCTAssertTrue(full.contains("  · 3 days ago: \"Weekend trip to Busan\""))
        XCTAssertTrue(full.contains("It went like this: them: \"We went to Busan\""))
    }
}
