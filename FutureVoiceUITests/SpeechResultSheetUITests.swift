import XCTest

/// The result page's sheet is the system's (2026-11-09). What moving to it
/// could break: the page behind must stay touchable at the low detent, and
/// the page's own Save button must still open its sheet over this one.
final class SpeechResultSheetUITests: XCTestCase {

    @MainActor
    func testSaveOpensOverTheSheetAndATapOpensIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "speech-result-v5"]
        app.launch()
        let title = app.staticTexts["How noise-cancelling headphones work"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the sheet did not come up")
        sleep(1)
        let lowY = title.frame.minY

        // A tap on the summary opens it.
        title.tap()
        sleep(2)
        XCTAssertLessThan(title.frame.minY, lowY - 200, "a tap on the summary did not open the sheet")
        title.tap()
        sleep(2)
        XCTAssertEqual(title.frame.minY, lowY, accuracy: 4, "a second tap did not bring it back")

        // Behind the sheet, the page's own button.
        let save = app.buttons.matching(NSPredicate(format: "label IN {'사진첩에 저장','Save to Photos'}")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save button")
        save.tap()
        let options = app.staticTexts.matching(NSPredicate(format: "label IN {'카메라 영상 저장','Save camera video'}")).firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 6), "Save did not open its sheet over the system sheet")
    }
}
