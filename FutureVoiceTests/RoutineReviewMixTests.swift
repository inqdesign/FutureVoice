import XCTest
@testable import FutureVoice

final class RoutineReviewMixTests: XCTestCase {
    private typealias C = RoutineReviewMix.Counts

    func testPlentyOfEverythingSplitsByShare() {
        let q = RoutineReviewMix.quotas(goal: 20, available: C(words: 50, expressions: 50, sentences: 50, shadow: 10))
        XCTAssertEqual(q, C(words: 6, expressions: 5, sentences: 6, shadow: 3))
    }

    /// The reported case: a big sentence backlog no longer takes every slot.
    func testSentenceBacklogDoesNotCrowdOutWords() {
        let q = RoutineReviewMix.quotas(goal: 20, available: C(words: 10, expressions: 4, sentences: 80, shadow: 3))
        XCTAssertEqual(q.total, 20)
        XCTAssertGreaterThanOrEqual(q.words, 6)
        XCTAssertEqual(q.expressions, 4)
        XCTAssertEqual(q.shadow, 3)
    }

    func testMissingKindSpillsToCardsNotShadow() {
        let q = RoutineReviewMix.quotas(goal: 20, available: C(words: 30, expressions: 0, sentences: 30, shadow: 10))
        XCTAssertEqual(q, C(words: 9, expressions: 0, sentences: 8, shadow: 3))
    }

    func testShortSupplyGivesWhatThereIs() {
        let q = RoutineReviewMix.quotas(goal: 20, available: C(words: 2, expressions: 1, sentences: 0, shadow: 0))
        XCTAssertEqual(q, C(words: 2, expressions: 1, sentences: 0, shadow: 0))
    }

    func testSmallBlockHasNoShadow() {
        let q = RoutineReviewMix.quotas(goal: 4, available: C(words: 9, expressions: 9, sentences: 9, shadow: 9))
        XCTAssertEqual(q.shadow, 0)
        XCTAssertEqual(q.total, 4)
    }
}
