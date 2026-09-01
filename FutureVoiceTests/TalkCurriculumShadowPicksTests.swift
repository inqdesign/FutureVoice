import XCTest
@testable import FutureVoice

/// `TalkCurriculum.shadowPicks` decides the talk book's Shadow chapter.
/// The failure mode these tests pin down: the chapter kept suggesting the
/// call's opening and closing greetings — ritual lines built entirely from
/// easy words — instead of the reusable middle of the conversation.
final class TalkCurriculumShadowPicksTests: XCTestCase {

    private func turn(_ text: String, role: TurnRole = .fluentSelf,
                      id: UUID = UUID()) -> Turn {
        Turn(id: id, role: role, audioURL: nil, transcript: text,
             durationMs: 0, timestamp: Date(), suggestion: nil)
    }

    private func session(_ turns: [Turn],
                         offered: [String] = []) -> Session {
        var summary: SessionSummary?
        if !offered.isEmpty {
            summary = SessionSummary(phrasesUsed: [], newPatternsDetected: [],
                                     suggestedDrills: [], overallNote: "",
                                     scorecard: nil, expressionsOffered: offered)
        }
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                       mode: .conversation, topic: "Coffee chat",
                       startedAt: Date().addingTimeInterval(-300),
                       endedAt: Date(), turns: turns, summary: summary)
    }

    func testOpenerAndFarewellLoseToTheMiddleOfTheCall() {
        let opener = turn("Hey it is so good to talk to you today my friend!")
        let middle = turn("You could push back on the deadline and end up saving the launch.")
        let farewell = turn("It was so nice to talk have a good day my friend!")
        let picks = TalkCurriculum.shadowPicks(
            session: session([opener, middle, farewell],
                             offered: ["push back on"]),
            proficiency: .b1)
        XCTAssertFalse(picks.isEmpty)
        XCTAssertFalse(picks.contains { $0.id == opener.id })
        XCTAssertFalse(picks.contains { $0.id == farewell.id })
    }

    func testOfferedExpressionOutranksPlainLines() {
        // At C2 almost no lemma clears the level bar, so only the summary's
        // offered expression can score — the line carrying it must be the pick.
        let plain = turn("I think you can just ask them about it again tomorrow.")
        let carrier = turn("If you wait too long you might end up doing it all again.")
        let picks = TalkCurriculum.shadowPicks(
            session: session([turn("Hello there so good to see you!"),
                              plain, carrier,
                              turn("Bye for now have a lovely evening friend!")],
                             offered: ["end up doing"]),
            proficiency: .c2)
        XCTAssertEqual(picks.map(\.id), [carrier.id])
    }

    func testAllRitualTalkStillOffersItsLines() {
        // A two-line call is nothing but opener + farewell; better them than
        // an empty chapter.
        let picks = TalkCurriculum.shadowPicks(
            session: session([turn("Hey it is so good to talk to you today!"),
                              turn("It was so nice to talk have a good day!")]),
            proficiency: .a1)
        XCTAssertFalse(picks.isEmpty)
    }

    func testFallbackPrefersMiddleLinesOverTheFarewell() {
        // Nothing scores at C2 with no offered expressions — the last-lines
        // fallback must still skip the ritual edges.
        let farewell = turn("It was so nice to talk have a good day my friend!")
        let picks = TalkCurriculum.shadowPicks(
            session: session([turn("Hey it is so good to talk to you today!"),
                              turn("I think you can just ask them about it soon."),
                              turn("Maybe they will say yes if you ask them nicely."),
                              farewell]),
            proficiency: .c2)
        XCTAssertFalse(picks.isEmpty)
        XCTAssertFalse(picks.contains { $0.id == farewell.id })
    }
}
