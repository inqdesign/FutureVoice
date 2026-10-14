import XCTest
@testable import FutureVoice

/// What the Review tab's reload pays to read the sentence cards. Printed,
/// not asserted, like `TalkCurriculumTimingTests`.
///
/// 2026-10-14, simulator, 400 cards: 30 ms per `load()`, asked four times
/// per tab switch. With the file-stamp cache: 29 ms once, then 0 ms.
final class PracticeReloadTimingTests: XCTestCase {
    @MainActor
    func testDrillLoadIsCachedUntilTheFileChanges() {
        let store = DrillStore(filename: "timing-drills-\(UUID().uuidString).json")
        for i in 0..<400 {
            store.save(DrillCard(sourcePhrase: "I go to the store yesterday and buy some bread number \(i)",
                                 targetPhrase: "I went to the store yesterday and bought some bread, number \(i).",
                                 reason: "Past tense for a finished action yesterday.",
                                 createdAt: Date(), lastReviewedAt: Date(),
                                 nextReviewAt: Date().addingTimeInterval(Double(i) * 600),
                                 box: i % 5, sourceSessionId: UUID(), sourceTurnId: UUID()))
        }
        for pass in 0..<3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let n = store.load().count
            print("TIMING drill load pass \(pass): \(n) cards in \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
        }
        // A write must be seen by the next read, cache or not.
        var first = store.load()[0]
        first.box = 4
        store.save(first)
        XCTAssertEqual(store.load().first { $0.id == first.id }?.box, 4)
    }
}
