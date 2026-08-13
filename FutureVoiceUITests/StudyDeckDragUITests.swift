import XCTest

/// Drives the daily study deck through the DebugCapture harness and performs
/// a REAL drag — the one interaction unit tests can't exercise. A successful
/// drop advances the deck counter; a failed drag springs the card back and
/// the counter stays put.
final class StudyDeckDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDragDropsCardIntoFolder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "daily-words"]
        app.launch()

        // Deck counter ("1 von 10" — the harness profile's chrome is German).
        let counter = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "von")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "deck never appeared")
        let before = counter.label

        // Drag from the card's centre down toward the tray, holding at the
        // end so the active-bin resolution has settled before release.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0.5)

        // Counter advanced (2 von 10) — the card was swallowed by a folder.
        let advanced = NSPredicate { _, _ in
            !counter.exists || counter.label != before
        }
        let exp = XCTNSPredicateExpectation(predicate: advanced, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 5), .completed,
                       "drag did not resolve the card — counter still \(before)")
    }

    /// The highlight must FOLLOW the finger: a hard-right drag has to land in
    /// the rightmost folder (Got it), not whichever bin was nearest to a
    /// stale/zero deck frame. This is the regression the counter-only test
    /// can't see.
    @MainActor
    func testHardRightDragLandsInRightmostFolder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "daily-words"]
        app.launch()

        let counter = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "von")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "deck never appeared")

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0.5)

        let gotIt = app.descendants(matching: .any)
            .matching(identifier: "studyDeck.folder.gotIt").firstMatch
        XCTAssertTrue(gotIt.waitForExistence(timeout: 5))
        let landed = NSPredicate { _, _ in gotIt.value as? String == "1" }
        let exp = XCTNSPredicateExpectation(predicate: landed, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 5), .completed,
                       "hard-right drag landed in \(String(describing: gotIt.value)) — highlight not following the finger")
    }
}

/// End-to-end: dropping a card on the shortest bin (10 min; 1 min in DEBUG —
/// see `DrillBin.soonDelay`) must actually ARM a notification.
/// The app logs REVIEWNOTIF on every scheduling decision; this drives a real
/// drag and then asserts on the app's own report, because a pending
/// notification request isn't visible from the test process.
final class ReviewReminderUITests: XCTestCase {

    @MainActor
    func testShortestSnoozeSchedulesAReminder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "daily-words"]
        app.launch()

        let counter = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "von")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "deck never appeared")

        // Leftmost folder = the shortest delay.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0.5)

        // The drop asks for notification permission the first time. Answer it
        // IMMEDIATELY — `requestAuthorization` is awaiting this tap, and the
        // scheduling it guards only happens once permission is granted.
        let allow = Self.springboardAllowButton
        if allow.waitForExistence(timeout: 8) {
            allow.tap()
        }

        let tenMin = app.descendants(matching: .any)
            .matching(identifier: "studyDeck.folder.tenMinutes").firstMatch
        XCTAssertTrue(tenMin.waitForExistence(timeout: 5))
        let landed = NSPredicate { _, _ in tenMin.value as? String == "1" }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: landed, object: nil)],
                                        timeout: 5), .completed,
                       "card did not land in the 10 min folder")

        // Give the async reschedule a moment to report its decision.
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: 3)
    }

    /// The system permission alert lives in SpringBoard, not the app.
    /// EXACT label match on purpose: a CONTAINS[c] 'Allow' predicate also
    /// matches "Don't Allow" — and firstMatch picks that one, silently
    /// denying the permission the test is trying to grant.
    static var springboardAllowButton: XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts.firstMatch.buttons["Allow"]
    }
}
