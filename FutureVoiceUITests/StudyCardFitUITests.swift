import XCTest

/// The study card's meaning side has no scroll view and never has had one —
/// it's a slab you drag into a folder, so it can't also be a scroller. That
/// makes "does the entry fit" a layout question with a real failure mode:
/// every `Text` on the card is `fixedSize(vertical:)`, so content that
/// overruns doesn't truncate, it draws straight over the drag hint and the
/// folder chips underneath.
///
/// `ViewThatFits` is what keeps that from happening (`StudyDeckView`'s
/// `meaningBlock`), and only a real screen can tell whether it chose right —
/// the same entry is four lines on a 6.3" phone and seven on an SE. So this
/// runs against whatever device it's given, with the harness's deliberately
/// fat entry (three senses, two long examples) behind every lookup.
final class StudyCardFitUITests: XCTestCase {

    @MainActor
    func testRevealedEntryStaysInsideTheCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-capture", "daily-words-full"]
        app.launch()

        let card = app.descendants(matching: .any)
            .matching(identifier: "studyDeck.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the deck never dealt a card")

        // Flip it to the meaning side and let the (stubbed) lookup land.
        card.tap()
        let meaning = card.staticTexts.element(boundBy: 0)
        XCTAssertTrue(meaning.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)

        // Slack for the slab's own rounding/stroke — a descender touching the
        // corner radius isn't the failure this is looking for.
        let bounds = card.frame.insetBy(dx: -2, dy: -2)
        let texts = card.staticTexts
        XCTAssertGreaterThan(texts.count, 1, "the card never revealed its meaning")
        for i in 0..<texts.count {
            let t = texts.element(boundBy: i)
            guard t.exists, !t.frame.isEmpty else { continue }
            XCTAssertTrue(bounds.contains(t.frame),
                          "\"\(t.label)\" spilled outside the card: \(t.frame) vs \(card.frame)")
        }

        // The chips are what the spill would land on, and they have to stay
        // usable — an unreachable folder is the whole cost of getting this
        // wrong.
        let chip = app.descendants(matching: .any)
            .matching(identifier: "studyDeck.folder.gotIt").firstMatch
        XCTAssertTrue(chip.exists, "the folder chips are gone")
        XCTAssertFalse(card.frame.intersects(chip.frame),
                       "the card is sitting on top of the folder chips")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "study-card-revealed"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
