import XCTest
@testable import FutureVoice

final class CoachPlanTests: XCTestCase {
    private func item(_ w: String) -> TalkGoalItem { TalkGoalItem(key: w, text: w, isWord: true) }

    func testMayHintFromTheFirstLine() {
        XCTAssertTrue(CoachPlan().mayHint)
    }

    func testPlainLinesBetweenHints() {
        var plan = CoachPlan()
        plan.replyFinished()
        plan.hintShown(item("rest"))
        XCTAssertFalse(plan.mayHint)
        plan.replyFinished()
        XCTAssertFalse(plan.mayHint)
        plan.replyFinished()
        XCTAssertTrue(plan.mayHint)
    }

    func testHintedItemsLeaveTheCandidates() {
        var plan = CoachPlan()
        plan.hintShown(item("rest"))
        XCTAssertEqual(plan.candidates(from: [item("rest"), item("plug")]).map(\.key), ["plug"])
    }

    func testCandidatesCapped() {
        let many = (0..<20).map { item("w\($0)") }
        XCTAssertEqual(CoachPlan().candidates(from: many).count, CoachMode.maxCandidates)
    }

    func testCappedPerCall() {
        var plan = CoachPlan()
        var shown = 0
        for i in 0..<30 {
            if plan.mayHint { plan.hintShown(item("w\(i)")); shown += 1 }
            plan.replyFinished()
        }
        XCTAssertEqual(shown, CoachPlan.maxHints)
    }

    func testQuestionDetectionAcrossScripts() {
        XCTAssertTrue(CoachPlan.endsInQuestion("それ、どうだった？"))
        XCTAssertTrue(CoachPlan.endsInQuestion("그래서 어땠어? "))
        XCTAssertTrue(CoachPlan.endsInQuestion("\"Why not?\""))
        XCTAssertFalse(CoachPlan.endsInQuestion("Why? I get it."))
    }
}
