import XCTest
@testable import FutureVoice

/// The prompts' clock. Reported by a learner (2026-09-28) as three symptoms —
/// "long time no see" on a second call the same day, "afternoon" at eight in
/// the morning, "our third call" on the first — all from prompts that carried
/// no time at all, and from two helpers that counted days as elapsed seconds.
final class PromptClockTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func talk(endingAt end: Date, learnerSpoke: Bool = true) -> Session {
        let turns: [Turn] = (learnerSpoke ? [Turn(id: UUID(), role: .user, audioURL: nil, transcript: "hi",
                                                    durationMs: 1000, timestamp: end.addingTimeInterval(-60),
                                                    suggestion: nil)] : [])
            + [Turn(id: UUID(), role: .fluentSelf, audioURL: nil, transcript: "hey",
                    durationMs: 1000, timestamp: end, suggestion: nil)]
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation,
                       topic: nil, startedAt: end.addingTimeInterval(-300), endedAt: end,
                       turns: turns, summary: nil)
    }

    // MARK: - Calendar days, not elapsed seconds

    func testLastNightIsYesterdayThoughOnlyNineHoursPassed() {
        XCTAssertEqual(PromptClock.calendarDays(from: at(27, 23), to: at(28, 8), calendar: cal), 1)
        XCTAssertEqual(ConversationEngine.age(of: at(27, 23), at: at(28, 8), calendar: cal), "yesterday")
    }

    func testTwoMorningsAgoIsTwoDaysThoughUnder48Hours() {
        XCTAssertEqual(ConversationEngine.age(of: at(26, 9), at: at(28, 8), calendar: cal), "2 days ago")
    }

    func testSameDayIsToday() {
        XCTAssertEqual(ConversationEngine.age(of: at(28, 0, 5), at: at(28, 23, 55), calendar: cal), "today")
    }

    func testPartOfDay() {
        XCTAssertEqual(PromptClock.partOfDay(hour: 8), "morning")
        XCTAssertEqual(PromptClock.partOfDay(hour: 14), "afternoon")
        XCTAssertEqual(PromptClock.partOfDay(hour: 19), "evening")
        XCTAssertEqual(PromptClock.partOfDay(hour: 2), "night")
    }

    // MARK: - The snapshot

    func testCountsOnlyTalksTheLearnerSpokeInAndNotThisOne() {
        let current = talk(endingAt: at(28, 7))
        let sessions = [
            talk(endingAt: at(28, 7, 20)),                      // earlier today
            talk(endingAt: at(28, 7, 40), learnerSpoke: false), // opened in silence
            talk(endingAt: at(25, 21)),                         // before today
            talk(endingAt: at(28, 9)),                          // "after now" — another device's clock
            current,
        ]
        let clock = PromptClock.make(now: at(28, 8), sessions: sessions,
                                   excluding: current.id, calendar: cal)
        XCTAssertEqual(clock.talksEarlierToday, 1)
        XCTAssertEqual(clock.lastTalkToday, at(28, 7, 20))
        XCTAssertEqual(clock.lastTalkBeforeToday, at(25, 21))
    }

    func testFirstTalkOfTheDaySaysSoAndNamesTheLastDay() {
        let clock = PromptClock.make(now: at(28, 8, 14), sessions: [talk(endingAt: at(23, 20))], calendar: cal)
        let block = clock.promptBlock(includeHistory: true, calendar: cal)
        XCTAssertTrue(block.contains("Monday, 28 September 2026, at 08:14 — morning"), block)
        XCTAssertTrue(block.contains("This is their FIRST talk today."), block)
        XCTAssertTrue(block.contains("5 days ago (Wednesday)"), block)
    }

    func testSecondTalkTodayIsRecentNotALongAbsence() {
        let clock = PromptClock.make(now: at(28, 8), sessions: [talk(endingAt: at(28, 7, 20))], calendar: cal)
        let block = clock.promptBlock(includeHistory: true, calendar: cal)
        XCTAssertTrue(block.contains("already had 1 talk earlier today, the latest ended about 40 minutes ago"), block)
        XCTAssertFalse(block.contains("FIRST talk"), block)
    }

    func testNoHistoryAtAll() {
        let block = PromptClock.make(now: at(28, 8), sessions: [], calendar: cal)
            .promptBlock(includeHistory: true, calendar: cal)
        XCTAssertTrue(block.contains("never had a talk here before"), block)
    }

    func testHistoryCanBeLeftOutButTheTimeCannot() {
        let block = PromptClock.make(now: at(28, 20), sessions: [talk(endingAt: at(28, 7))], calendar: cal)
            .promptBlock(includeHistory: false, calendar: cal)
        XCTAssertTrue(block.contains("evening where the user is"), block)
        XCTAssertFalse(block.contains("already had"), block)
        XCTAssertFalse(block.contains("FIRST talk"), block)
        XCTAssertFalse(block.contains("Before today"), block)
    }

    func testResumedTalkSaysHowLongItPaused() {
        let block = PromptClock.make(now: at(28, 8), sessions: [], resumedFrom: at(25, 22), calendar: cal)
            .promptBlock(includeHistory: true, calendar: cal)
        XCTAssertTrue(block.contains("RESUMES a saved talk that paused 3 days ago (Friday)"), block)
    }

    // MARK: - Where the block lands

    func testConversationPromptCarriesTheClockAndItsGuard() {
        let clock = PromptClock.make(now: at(28, 8), sessions: [talk(endingAt: at(28, 7))], calendar: cal)
        func prompt(firstMeeting: Bool) -> String {
            ConversationEngine.conversationSystemPrompt(
                targetLanguage: "ko", nativeLanguage: "en", level: .b1,
                topPatterns: [], weakVocabAreas: [], topic: "",
                firstMeeting: firstMeeting, clock: clock)
        }
        let plain = prompt(firstMeeting: false)
        XCTAssertTrue(plain.contains("WHEN THIS IS"))
        XCTAssertTrue(plain.contains("already had 1 talk earlier today"))
        // The first meeting's own block says what the relationship is.
        let first = prompt(firstMeeting: true)
        XCTAssertTrue(first.contains("WHEN THIS IS"))
        XCTAssertFalse(first.contains("already had"))
        // No clock, no block — the prompt is otherwise unchanged.
        let none = ConversationEngine.conversationSystemPrompt(
            targetLanguage: "ko", nativeLanguage: "en", level: .b1,
            topPatterns: [], weakVocabAreas: [], topic: "")
        XCTAssertFalse(none.contains("WHEN THIS IS"))
    }

    func testSummaryIsDatedToTheTalkNotToTheSummary() {
        let prompt = ConversationEngine.summarySystemPrompt(
            targetLanguage: "en", nativeLanguage: "ko",
            profile: LearnerProfile(id: UUID(), userId: UUID(), targetLanguage: "en",
                                    proficiencyLevel: .b1, recurringMistakes: [], weakVocabAreas: [],
                                    strongPatterns: [], totalSessions: 0, totalSpeakingSeconds: 0,
                                    lastSessionAt: nil, summaryEmbedding: nil),
            talkDate: at(25, 21), now: at(28, 8))
        XCTAssertTrue(prompt.contains("Friday, 25 September 2026"), String(prompt.prefix(200)))
    }

    // MARK: - The daily call: written tonight, heard tomorrow

    private func voicemail(lastTalk: Date?, rings: [Date]) -> String {
        var c = VoicemailEngine.Context(targetLanguage: "ko", nativeLanguage: "en", proficiency: .b1,
                                        personaName: nil, lastTopic: nil, lastPhrases: [],
                                        lastTalkAt: lastTalk, dueCount: 0)
        c.ringDates = rings
        return VoicemailEngine.systemPrompt(c, calendar: cal)
    }

    func testLastNightsTalkIsYesterdayAtTheMorningRing() {
        let p = voicemail(lastTalk: at(27, 23), rings: [at(28, 8)])
        XCTAssertTrue(p.contains("Their last talk was yesterday."), p)
        XCTAssertFalse(p.contains("earlier today"), p)
        XCTAssertTrue(p.contains("at 08:00 — morning"), p)
    }

    func testSeveralRingsForbidATimeOfDay() {
        let p = voicemail(lastTalk: at(28, 7), rings: [at(28, 13), at(28, 19)])
        XCTAssertTrue(p.contains("They already had a talk earlier today."), p)
        XCTAssertTrue(p.contains("13:00, 19:00"), p)
        XCTAssertTrue(p.contains("cannot know which part of the day"), p)
    }
}
