import XCTest

/// The tutor bot's note and chat.
final class TutorBotUITests: XCTestCase {

    /// "Ask me" on the day's note opens the chat. Before 2026-11-03 it
    /// closed the note and opened nothing on about one tap in four: the
    /// model animated the note shut with `withAnimation`, which flushed a
    /// SwiftUI update mid-method, and `chatOpen = true` written after it
    /// reached no view until the next unrelated update (a tab switch).
    /// Labels are matched in Korean and English; `-capture tabs` runs the
    /// app in Korean on this machine.
    @MainActor
    func testAskMeOnTheNoteOpensTheChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "tabs", "-tutorShow", "plan"]
        app.launch()
        // A recap or another first-run sheet on top: close it.
        for _ in 0..<2 {
            let close = app.buttons.matching(NSPredicate(format: "label IN {'닫기','Close'}")).firstMatch
            if close.waitForExistence(timeout: 3) { close.tap(); sleep(1) } else { break }
        }
        let ask = app.buttons.matching(NSPredicate(format: "label IN {'물어보기','Ask me'}")).firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 15), "no Ask me on the tutor's note")
        ask.tap()
        let title = app.staticTexts.matching(NSPredicate(format: "label IN {'개인 튜터','Personal tutor'}")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "the chat did not open after Ask me")
    }
}
