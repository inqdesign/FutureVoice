import XCTest

/// The Practice/Progress split after merging Practice's two cards into one:
/// Practice answers "what now", Progress answers "how far along".
final class PracticeLayoutUITests: XCTestCase {

    /// Practice must no longer carry the whole-library mastery figure, and
    /// every collection must be reachable from its own tile.
    @MainActor
    func testEveryCategoryTileOffersTodayAndTheWholeCollection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "practice-due"]
        app.launch()

        // Everything here matches by IDENTIFIER: chrome follows the target
        // language, so label-matching tests pass only until translation lands.
        //
        // Every category tile carries BOTH doors — today's hand on top, the
        // whole collection along the bottom. A single entry that hid all of
        // them (the old Library row) is what this replaced.
        let collections = [
            "practice.all.rectangle.stack",       // Sentences
            "practice.all.text.book.closed.fill", // Words
            "practice.all.quote.bubble.fill",     // Expressions
            "practice.all.waveform.badge.mic",    // Shadowing
        ]
        for id in collections {
            let door = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(door.waitForExistence(timeout: 10),
                          "\(id): no way into that collection from its tile")
        }

        // The mastery panel lived directly under the Today card; it moved.
        let mastery = app.descendants(matching: .any)
            .matching(identifier: "progress.materialPanel")
        XCTAssertEqual(mastery.count, 0, "whole-library mastery is still on Practice")

        // …and the door actually opens the collection (the word notebook).
        app.descendants(matching: .any)
            .matching(identifier: "practice.all.text.book.closed.fill").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }

    /// …and it landed on Progress, where measuring lives.
    @MainActor
    func testProgressCarriesTheMaterialPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "progress"]
        app.launch()

        // By identifier — the visible title follows the target language.
        let panel = app.descendants(matching: .any)
            .matching(identifier: "progress.materialPanel").firstMatch
        let overall = app.scrollViews.firstMatch
        XCTAssertTrue(overall.waitForExistence(timeout: 10))
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "the material panel never appeared on Progress")
        // `exists` is true for off-screen panels (this ScrollView isn't lazy),
        // so scroll until it's actually ON screen — that's what "moved to
        // Progress" has to mean, and it's what the screenshot needs.
        let window = app.windows.firstMatch.frame
        for _ in 0..<12 where !window.contains(CGPoint(x: panel.frame.midX,
                                                       y: panel.frame.midY)) {
            overall.swipeUp()
        }

        // Keep the visual: the panel is the whole point of the move.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "progress-material"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
