import XCTest
@testable import FutureVoice

/// A talk's whole review yield hangs on one model-written JSON object. It
/// missed six times in production between 2026-08-14 and 08-19 — every one of
/// them threw away drills, scorecard and profile evidence the model had
/// already got right, because a field was absent or arrived as the wrong type.
/// These are the shapes that must survive.
final class SummaryPayloadTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeSummaryPayload {
        try JSONDecoder().decode(ClaudeSummaryPayload.self, from: Data(json.utf8))
    }

    /// Everything optional omitted — the model had nothing to report.
    func testMinimalObjectDecodes() throws {
        let p = try decode(#"{"overall_note":"Good talk."}"#)
        XCTAssertEqual(p.overall_note, "Good talk.")
        XCTAssertTrue(p.phrases_used.isEmpty)
        XCTAssertTrue(p.new_patterns_detected.isEmpty)
        XCTAssertTrue(p.suggested_drills.isEmpty)
        XCTAssertNil(p.scorecard)
    }

    /// Even the note can go missing without costing the talk its drills.
    func testEmptyObjectDecodes() throws {
        let p = try decode("{}")
        XCTAssertEqual(p.overall_note, "")
    }

    func testScoreAsDoubleOrString() throws {
        let p = try decode("""
        {"overall_note":"x","scorecard":{
          "vocabulary":{"score":85.6,"note":"a"},
          "grammar":{"score":"70","note":"b"},
          "expressiveness":{"score":60,"note":"c"},
          "fluency":{"score":-1,"note":"d"},
          "top_line":"nice"}}
        """)
        let sc = try XCTUnwrap(p.scorecard)
        XCTAssertEqual(sc.vocabulary.score, 86)
        XCTAssertEqual(sc.grammar.score, 70)
        XCTAssertEqual(sc.expressiveness.score, 60)
        // -1 is the rubric's "no timing data" signal and must reach toDomain
        // intact — it is rewritten there, not here.
        XCTAssertEqual(sc.fluency.score, -1)
        XCTAssertEqual(p.toDomain().scorecard?.fluency.score, 0)
    }

    /// A missing axis is not inventable — the scorecard drops, the rest of
    /// the review material still lands.
    func testIncompleteScorecardDropsOnlyItself() throws {
        let p = try decode("""
        {"overall_note":"x","suggested_drills":["say it again"],
         "scorecard":{"vocabulary":{"score":80,"note":"a"},"top_line":"nice"}}
        """)
        XCTAssertNil(p.scorecard)
        XCTAssertEqual(p.suggested_drills, ["say it again"])
    }

    /// One malformed element must not take its list with it.
    func testMalformedElementIsSkipped() throws {
        let p = try decode("""
        {"overall_note":"x","phrases_used":[
          {"user_said":"I go yesterday","fluent_alternative":"I went yesterday","reason":"past tense"},
          {"fluent_alternative":"no anchor"},
          {"user_said":"me too tired","fluent_alternative":"I'm too tired"}
        ],"suggested_drills":["one",2,"three"]}
        """)
        XCTAssertEqual(p.phrases_used.map(\.user_said), ["I go yesterday", "me too tired"])
        // Prose that went missing costs the phrase nothing.
        XCTAssertEqual(p.phrases_used.last?.reason, nil)
        XCTAssertEqual(p.suggested_drills, ["one", "three"])
    }

    /// The frequency hint is a coarse bucket — absent reads as "once", the
    /// same as any word the mapper doesn't recognize.
    func testPatternWithoutFrequencyHint() throws {
        let p = try decode("""
        {"overall_note":"x","new_patterns_detected":[
          {"mistake":"no article","correction":"the launch"}]}
        """)
        let pattern = try XCTUnwrap(p.toDomain().newPatternsDetected.first)
        XCTAssertEqual(pattern.frequency, 1)
        XCTAssertEqual(pattern.context, "")
    }

    /// A grammar issue still needs both halves — a correction with nothing to
    /// correct teaches nothing and is dropped downstream.
    func testGrammarIssueNeedsQuoteAndCorrection() throws {
        let p = try decode("""
        {"overall_note":"x","grammar_errors":[
          {"quote":"I go yesterday","correction":"I went yesterday"},
          {"quote":"   ","correction":"something"}]}
        """)
        XCTAssertEqual(p.toDomain().grammarIssues.map(\.quote), ["I go yesterday"])
        XCTAssertEqual(p.toDomain().grammarIssues.first?.note, "")
    }
}
