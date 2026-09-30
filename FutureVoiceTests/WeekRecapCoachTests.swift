import XCTest
@testable import FutureVoice

/// The coach's read is only shown as far as the learner's own lines bear it
/// out — these pin the checks in `WeekRecapCoach.verified`.
@MainActor
final class WeekRecapCoachTests: XCTestCase {

    private let lines = [
        "Yesterday I went to the new flat and the landlord says it's fine.",
        "Then she ask me if I want to sign the contract today.",
        "I end up carrying most boxes myself.",
        "I was very tired after the move, very very tired.",
        "It's good, I think it's good for me.",
    ]

    private func payload(_ json: String) throws -> WeekRecapCoach.Payload {
        try JSONDecoder().decode(WeekRecapCoach.Payload.self, from: Data(json.utf8))
    }

    func testPatternNeedsTwoExamplesTheLearnerActuallySaid() throws {
        let r = try payload("""
        {"headline": "h", "grammar": [
          {"rule": "past tense", "tip": "t", "examples": [
            {"was": "the landlord says it's fine", "now": "the landlord said it was fine"},
            {"was": "she ask me", "now": "she asked me"},
            {"was": "he go home", "now": "he went home"}]},
          {"rule": "seen once", "tip": "t", "examples": [
            {"was": "I end up carrying", "now": "I ended up carrying"},
            {"was": "we was late", "now": "we were late"}]}
        ]}
        """)
        let coach = WeekRecapCoach.verified(r, lines: lines)
        XCTAssertEqual(coach.grammar.count, 1, "a point with one real sentence is not a pattern")
        XCTAssertEqual(coach.grammar[0].examples.map(\.was),
                       ["the landlord says it's fine", "she ask me"],
                       "an example the learner never said is dropped")
    }

    func testUpgradeIsCountedHereAndItsLineMustBeTheirs() throws {
        let r = try payload("""
        {"headline": "h", "upgrades": [
          {"instead": "very tired", "better": "exhausted",
           "original": "I was very tired after the move, very very tired.",
           "rewritten": "I was exhausted after the move.", "note": "n"},
          {"instead": "good", "better": "decent",
           "original": "The flat is good for the price.", "rewritten": "The flat is decent.", "note": "n"},
          {"instead": "contract", "better": "lease", "original": "", "rewritten": "", "note": "n"},
          {"instead": "tired", "better": "Tired", "original": "", "rewritten": "", "note": "n"}
        ]}
        """)
        let coach = WeekRecapCoach.verified(r, lines: lines)
        XCTAssertEqual(coach.upgrades.map(\.instead), ["very tired", "good"])
        XCTAssertEqual(coach.upgrades[0].count, 2)
        XCTAssertEqual(coach.upgrades[1].count, 2)
        XCTAssertEqual(coach.upgrades[1].original, "", "an invented example line is not shown")
    }

    func testCountingIsWholeWords() {
        XCTAssertEqual(WeekRecapCoach.occurrences(of: "good", in: ["goodbye, good day", "Good."]), 2)
    }

    func testInsightQuoteMustBeTheirs() throws {
        let invented = WeekRecapCoach.verified(
            try payload(#"{"headline": "h", "insight": "i", "insight_quote": "I never said this"}"#), lines: lines)
        XCTAssertEqual(invented.insightQuote, "")
        let real = WeekRecapCoach.verified(
            try payload(#"{"headline": "h", "insight": "i", "insight_quote": "It's good, I think it's good for me."}"#), lines: lines)
        XCTAssertFalse(real.insightQuote.isEmpty)
    }
}
