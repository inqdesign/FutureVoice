import XCTest
@testable import FutureVoice

/// The export is the one place a book leaves the app, so the thing worth
/// guarding is that nothing silently drops on the way out: every scene line,
/// every study item, every correction has to survive into both formats, and
/// the PDF has to be a real, paginated PDF rather than an empty page.
@MainActor
final class BookExportTests: XCTestCase {

    private func sampleDocument() -> BookDocument {
        var doc = BookDocument(kind: "Watch book", title: "Ordering coffee")
        doc.subtitle = "Barista · Cafe"
        doc.meta = ["12 August 2026", "Mastered 1/3"]
        doc.sections = [
            .init(title: "Scene", lines: [
                .init(speaker: "You", text: "Could I get a flat white to go?", isUser: true),
                .init(speaker: "Barista", text: "Sure — anything else with that?", isUser: false),
            ]),
            .init(title: "Words", entries: [
                .init(text: "to go", note: "when you're taking it away",
                      example: "A flat white to go, please.", mastered: true),
                .init(text: "receipt", note: "the slip you get after paying", mastered: false),
            ]),
            .init(title: "Drill", entries: [
                .init(text: "Could I get a flat white?", note: "more natural than 'I want'",
                      original: "I want one flat white", mastered: false),
            ]),
        ]
        return doc
    }

    // MARK: - Markdown

    func testMarkdownKeepsEverySceneLineAndItem() {
        let md = sampleDocument().markdown

        XCTAssertTrue(md.hasPrefix("# Ordering coffee"))
        XCTAssertTrue(md.contains("Watch book · Barista · Cafe · 12 August 2026 · Mastered 1/3"))
        for expected in ["Could I get a flat white to go?",
                         "Sure — anything else with that?",
                         "to go", "receipt", "Could I get a flat white?"] {
            XCTAssertTrue(md.contains(expected), "lost \(expected)")
        }
    }

    func testMarkdownMasteryReadsAsATickedBox() {
        let md = sampleDocument().markdown
        XCTAssertTrue(md.contains("- [x] **to go**"))
        XCTAssertTrue(md.contains("- [ ] **receipt**"))
    }

    func testMarkdownPairsTheOriginalWithTheFix() {
        XCTAssertTrue(sampleDocument().markdown
            .contains("~~I want one flat white~~ → **Could I get a flat white?**"))
    }

    // MARK: - HTML / PDF

    func testHTMLEscapesTextThatWouldOtherwiseBreakTheMarkup() {
        var doc = BookDocument(kind: "Talk book", title: "Tags & <brackets>")
        doc.sections = [.init(title: "Words", entries: [.init(text: "a < b & c")])]
        let html = doc.html
        XCTAssertTrue(html.contains("Tags &amp; &lt;brackets&gt;"))
        XCTAssertTrue(html.contains("a &lt; b &amp; c"))
    }

    func testPDFRendersRealPages() throws {
        let data = sampleDocument().pdfData()
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))

        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertGreaterThanOrEqual(doc.numberOfPages, 1)
    }

    /// A long book has to flow onto more pages rather than being clipped at
    /// one — the whole reason the PDF goes through a page renderer.
    func testLongBookPaginates() throws {
        var doc = BookDocument(kind: "Talk book", title: "A long talk")
        doc.sections = [.init(title: "Transcript", lines: (0..<160).map { i in
            .init(speaker: i.isMultiple(of: 2) ? "You" : "Future self",
                  text: "This is line number \(i), long enough to take a full row of the page.",
                  isUser: i.isMultiple(of: 2))
        })]
        let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: doc.pdfData() as CFData)!))
        XCTAssertGreaterThan(pdf.numberOfPages, 1)
    }

    // MARK: - Filenames

    func testFilenameSurvivesPunctuationAndNonLatinTitles() {
        var doc = BookDocument(kind: "Talk book", title: "Kita: pickup / 하원 시간?")
        XCTAssertFalse(doc.filename.contains("/"))
        XCTAssertFalse(doc.filename.contains(":"))
        XCTAssertTrue(doc.filename.contains("하원"))

        doc = BookDocument(kind: "Talk book", title: "…")
        XCTAssertFalse(doc.filename.isEmpty)
    }
}
