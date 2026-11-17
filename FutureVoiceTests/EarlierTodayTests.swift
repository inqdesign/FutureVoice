import XCTest
@testable import FutureVoice

/// The second call of the day (2026-11-04, founder: "I call again the same
/// morning and it says 'did you sleep well?' again"). The opener looked only
/// at the hour; a later call now picks up what came earlier — a talk, a tutor
/// lesson, or a pronunciation drill.
final class EarlierTodayTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func talk(endingAt end: Date, said: String = "I have a meeting at ten",
                      counterpart: UUID? = nil, lesson: TutorLessonRecord? = nil) -> Session {
        let turns = [
            Turn(id: UUID(), role: .user, audioURL: nil, transcript: said,
                 durationMs: 1000, timestamp: end.addingTimeInterval(-60), suggestion: nil),
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil, transcript: "Good luck!",
                 durationMs: 1000, timestamp: end, suggestion: nil),
        ]
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: nil, startedAt: end.addingTimeInterval(-300), endedAt: end,
                       turns: turns, summary: nil, counterpartId: counterpart, tutorLesson: lesson)
    }

    private func take(at date: Date, words: [(String, Int)], surface: String = "pron_call") -> PronunciationEntry {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "date": date.timeIntervalSinceReferenceDate,
            "surface": surface, "locale": "en-US", "accuracy": 70, "score": 70,
            "words": words.map { ["w": $0.0, "a": $0.1] },
            "phonemes": [],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(PronunciationEntry.self, from: data)
    }

    // MARK: - The record a later call carries (2026-11-17, learner report)

    private func line(_ role: TurnRole, _ text: String, _ at: Date, misheard: Bool = false) -> Turn {
        var t = Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
                     durationMs: 1000, timestamp: at, suggestion: nil)
        t.excludedFromScoring = misheard
        return t
    }

    /// "On my way home" came early in a talk; the next call must still see it.
    func testALongTalkCarriesMoreThanItsLastTenLines() throws {
        let end = at(4, 8)
        var turns = [line(.user, "I'm on my way back home from lunch", end.addingTimeInterval(-900))]
        for i in 0..<14 {
            turns.append(line(.fluentSelf, "reply \(i)", end.addingTimeInterval(Double(-800 + i * 50))))
            turns.append(line(.user, "answer \(i)", end.addingTimeInterval(Double(-780 + i * 50))))
        }
        let s = Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                        topic: nil, startedAt: end.addingTimeInterval(-1000), endedAt: end,
                        turns: turns, summary: nil)
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 11), sessions: [s], pronEntries: [], calendar: cal))
        XCTAssertTrue(e.record.contains("on my way back home"))
    }

    /// A line flagged as misheard, and the reply built on it, never reach
    /// the next call.
    func testAMisheardLineAndItsReplyStayOut() throws {
        let end = at(4, 8)
        let turns = [
            line(.user, "I'm on my way back home", end.addingTimeInterval(-120)),
            line(.fluentSelf, "Nice, how was lunch?", end.addingTimeInterval(-100)),
            line(.user, "She is here for six month.", end.addingTimeInterval(-60), misheard: true),
            line(.fluentSelf, "Oh, your friend is in Singapore for six months?", end),
        ]
        let s = Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                        topic: nil, startedAt: end.addingTimeInterval(-300), endedAt: end,
                        turns: turns, summary: nil)
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 11), sessions: [s], pronEntries: [], calendar: cal))
        XCTAssertTrue(e.record.contains("how was lunch"))
        XCTAssertFalse(e.record.contains("six month"))
    }

    // MARK: - What came earlier

    func testNothingEarlierTodayIsNil() {
        let e = EarlierToday.latest(now: at(4, 9), sessions: [talk(endingAt: at(3, 22))],
                                    pronEntries: [], calendar: cal)
        XCTAssertNil(e)
    }

    func testTalkEarlierTodayCarriesTheLearnersOwnWords() throws {
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 11), sessions: [talk(endingAt: at(4, 8))],
                                                  pronEntries: [], calendar: cal))
        XCTAssertEqual(e.kind, .talk)
        XCTAssertTrue(e.record.contains("I have a meeting at ten"))
        XCTAssertTrue(e.record.contains("about 3 hours ago"))
    }

    func testATalkWithSomeoneElseIsNotTheFluentSelfsToPickUp() {
        let e = EarlierToday.latest(now: at(4, 11), sessions: [talk(endingAt: at(4, 8), counterpart: UUID())],
                                    pronEntries: [], calendar: cal)
        XCTAssertNil(e)
    }

    func testALessonSaysWhatWasPractised() throws {
        let lesson = TutorLessonRecord(lessonId: UUID(), title: "Ordering coffee",
                                       done: [.init(goal: "ask for a size", line: "Can I get a large one?")],
                                       total: 3, finished: false)
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 11), sessions: [talk(endingAt: at(4, 8), lesson: lesson)],
                                                  pronEntries: [], calendar: cal))
        XCTAssertEqual(e.kind, .lesson)
        XCTAssertTrue(e.record.contains("Ordering coffee"))
        XCTAssertTrue(e.record.contains("1 of 3"))
        XCTAssertTrue(e.record.contains("Can I get a large one?"))
    }

    func testAPronunciationDrillAfterTheTalkWinsAndNamesTheHardWords() throws {
        let takes = [
            take(at: at(4, 9, 0), words: [("think", 40), ("is", 95)]),
            take(at: at(4, 9, 5), words: [("three", 55), ("Think", 50)]),
            take(at: at(4, 9, 6), words: [("hello", 90)], surface: "shadow"),
        ]
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 12), sessions: [talk(endingAt: at(4, 8))],
                                                  pronEntries: takes, calendar: cal))
        XCTAssertEqual(e.kind, .pronunciation)
        XCTAssertTrue(e.record.contains("2 sentences"))
        XCTAssertTrue(e.record.contains("\"think\", \"three\""))
        XCTAssertFalse(e.record.contains("\"is\""))
    }

    func testATalkAfterTheDrillWins() throws {
        let takes = [take(at: at(4, 7), words: [("think", 40)])]
        let e = try XCTUnwrap(EarlierToday.latest(now: at(4, 12), sessions: [talk(endingAt: at(4, 8))],
                                                  pronEntries: takes, calendar: cal))
        XCTAssertEqual(e.kind, .talk)
    }

    // MARK: - The prompt

    // Free talk is facts only (2026-11-12, founder): who you are, what we
    // know, nothing on how to talk.
    func testFreeModePromptIsFactsOnly() {
        let earlier = EarlierToday(kind: .talk, key: "k", endedAt: Date(),
                                   record: "A talk that ended about 2 hours ago.")
        let p = ConversationEngine.conversationSystemPrompt(
            targetLanguage: "en", nativeLanguage: "ko", level: .b1,
            topPatterns: [LearnerPattern(mistake: "I go yesterday", correction: "I went yesterday",
                                         context: "past", frequency: 3, lastSeenAt: Date())],
            weakVocabAreas: [], topic: "", earlierToday: earlier, freeMode: true)
        XCTAssertTrue(p.contains("Talk with them freely, about anything"))
        XCTAssertTrue(p.contains("B1"))
        XCTAssertTrue(p.contains("I go yesterday → I went yesterday"))
        XCTAssertTrue(p.contains("A talk that ended about 2 hours ago."))
        for rule in ["HOW TO TALK", "HARD CEILING", "PITCH TO THEIR LEVEL", "STRICT", "THEY CALLED YOU"] {
            XCTAssertFalse(p.contains(rule), rule)
        }
    }

    func testFreeTalkPromptCarriesEarlierTodayOnlyWhenThereIsOne() {
        func prompt(_ e: EarlierToday?) -> String {
            ConversationEngine.conversationSystemPrompt(
                targetLanguage: "en", nativeLanguage: "ko", level: .b1, topPatterns: [],
                weakVocabAreas: [], topic: "", earlierToday: e)
        }
        let earlier = EarlierToday(kind: .talk, key: "k", endedAt: Date(),
                                   record: "A talk that ended about 2 hours ago.")
        XCTAssertFalse(prompt(nil).contains("EARLIER TODAY"))
        XCTAssertTrue(prompt(nil).contains("only a friend's hello for the time of day"))
        let withIt = prompt(earlier)
        XCTAssertTrue(withIt.contains("EARLIER TODAY"))
        XCTAssertTrue(withIt.contains("A talk that ended about 2 hours ago."))
        XCTAssertTrue(withIt.contains("second call the same day"))
    }
}
