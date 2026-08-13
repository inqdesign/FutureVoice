import XCTest

/// The Practice/Progress split after merging Practice's two cards into one:
/// Practice answers "what now", Progress answers "how far along".
final class PracticeLayoutUITests: XCTestCase {

    /// Practice must no longer carry the whole-library mastery figure, and the
    /// three collections must still be reachable (through Library).
    @MainActor
    func testPracticeShowsOneCardAndKeepsTheCollectionsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "practice-due"]
        app.launch()

        let today = app.staticTexts["Heute"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "Today card never appeared")

        // The mastery line lived directly under it and is gone from this tab.
        let mastery = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'gemeistert · alles' OR label CONTAINS[c] 'mastered · everything'"))
        XCTAssertEqual(mastery.count, 0, "whole-library mastery is still on Practice")

        // …and the collections are one tap away.
        let library = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Library'")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 3), "no way into the collections")
        library.tap()
        XCTAssertTrue(app.staticTexts["Wörter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wendungen"].exists)
        XCTAssertTrue(app.staticTexts["Nachsprechen"].exists)
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
        for _ in 0..<12 where !panel.exists {
            overall.swipeUp()
        }
        XCTAssertTrue(panel.exists, "the material panel never appeared on Progress")

        // Keep the visual: the panel is the whole point of the move.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "progress-material"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
