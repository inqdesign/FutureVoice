import XCTest
@testable import FutureVoice

/// The workbook lays a book out for a pen. What is worth guarding: every
/// study item gets its writing space, every correction's answer lands in the
/// answer pages (never beside its question), and the file is a real
/// multi-page PDF with a part per page run.
///
/// Set `TEST_RUNNER_WORKBOOK_OUT=<dir>` on `xcodebuild test` to also write
/// the sample PDFs there for a look.
@MainActor
final class BookWorkbookTests: XCTestCase {

    static func englishTalkBook() -> BookDocument {
        var doc = BookDocument(kind: "Talk book", title: "Chores, kids and the weekend")
        doc.language = "en"
        doc.meta = ["30 September 2026", "Mastered 3/18", "Score 72"]
        doc.sections = [
            .init(title: "Overview", kind: .overview,
                  blurb: "이야기를 길게 이어 가는 힘이 좋아졌어요. 과거 시제를 섞어 쓸 때 현재형으로 돌아가는 습관이 아직 남아 있어요."),
            .init(title: "Words", kind: .words, entries: [
                .init(text: "chore"), .init(text: "laundry", mastered: true),
                .init(text: "split"), .init(text: "exhausted"),
                .init(text: "take turns"), .init(text: "errand"),
                .init(text: "tidy up"), .init(text: "routine"),
            ]),
            .init(title: "Expressions", kind: .expressions, entries: [
                .init(text: "it's my turn to", note: "Your fluent self used this — you didn't.",
                      example: "Tonight it's my turn to cook, so I'm keeping it simple."),
                .init(text: "end up -ing", example: "We always end up doing the dishes at midnight."),
                .init(text: "to be fair", example: "To be fair, she does most of the laundry."),
                .init(text: "push back on", example: "I pushed back on doing every school run."),
            ]),
            .init(title: "Shadow", kind: .shadow, entries: [
                .init(text: "Honestly, the laundry never really ends — you just catch up for a day."),
                .init(text: "We split it by days, so nobody has to keep score."),
                .init(text: "On Saturdays we tidy up together and then go get pancakes."),
            ]),
            .init(title: "Drill", kind: .drill, entries: [
                .init(text: "Yesterday I did the laundry and cooked dinner.", note: "어제 일이니까 과거형으로",
                      original: "Yesterday I do the laundry and cook dinner."),
                .init(text: "We take turns doing the dishes.", note: "take turns 다음엔 -ing",
                      original: "We take turns to do dishes."),
                .init(text: "I'm exhausted after work.", note: "사람의 상태는 -ed",
                      original: "I'm exhausting after work."),
            ]),
            .init(title: "Transcript", kind: .transcript, lines: [
                .init(speaker: "Future self", text: "So what does a normal weekday evening look like at your place?", isUser: false),
                .init(speaker: "You", text: "Yesterday I do the laundry and cook dinner, and my wife, she put the kids to bed.",
                      isUser: true, correction: "Yesterday I did the laundry and cooked dinner, and my wife put the kids to bed.",
                      fixes: ["do → did · 과거", "cook → cooked · 과거"]),
                .init(speaker: "Future self", text: "That sounds like a fair split. Do you two take turns, or is it more who's free?", isUser: false),
                .init(speaker: "You", text: "We take turns to do dishes. But I'm exhausting after work so…", isUser: true,
                      correction: "We take turns doing the dishes, but I'm exhausted after work, so…",
                      fixes: ["take turns to do → take turns doing", "exhausting → exhausted"]),
            ]),
            .init(title: "Glossary", kind: .glossary, entries: [
                .init(text: "chore", note: "n. 집안일, 허드렛일"),
                .init(text: "laundry", note: "n. 빨래, 세탁물"),
                .init(text: "split", note: "v. 나누다 · n. 분담"),
                .init(text: "exhausted", note: "adj. 기진맥진한"),
                .init(text: "take turns", note: "번갈아 하다"),
                .init(text: "errand", note: "n. 볼일, 심부름"),
                .init(text: "tidy up", note: "정리하다, 치우다"),
                .init(text: "it's my turn to", note: "내가 ~할 차례다"),
                .init(text: "end up -ing", note: "결국 ~하게 되다"),
                .init(text: "to be fair", note: "공정하게 말하자면"),
                .init(text: "push back on", note: "~에 반대 의견을 내다"),
            ]),
        ]
        return doc
    }

    static func japaneseWatchBook() -> BookDocument {
        var doc = BookDocument(kind: "Watch book", title: "カフェで注文が違ったとき")
        doc.language = "ja"
        doc.subtitle = "店員 · カフェ"
        doc.meta = ["1 October 2026", "Mastered 0/6"]
        doc.sections = [
            .init(title: "Scene", kind: .scene, lines: [
                .init(speaker: "店員", text: "お待たせしました。カフェラテです。", isUser: false),
                .init(speaker: "You", text: "すみません、アイスで頼んだんですけど…", isUser: true),
                .init(speaker: "店員", text: "あ、大変失礼しました。すぐお作りし直しますね。", isUser: false),
            ]),
            .init(title: "Words", kind: .words, entries: [
                .init(text: "注文"), .init(text: "違う"), .init(text: "作り直す"), .init(text: "大丈夫"),
            ]),
            .init(title: "Expressions", kind: .expressions, entries: [
                .init(text: "〜んですけど", example: "アイスで頼んだんですけど…"),
            ]),
            .init(title: "Shadow", kind: .shadow, entries: [
                .init(text: "すみません、アイスで頼んだんですけど…"),
            ]),
            .init(title: "Glossary", kind: .glossary, entries: [
                .init(text: "注文", note: "명 주문"), .init(text: "違う", note: "동 다르다, 틀리다"),
                .init(text: "作り直す", note: "동 다시 만들다"), .init(text: "大丈夫", note: "괜찮음"),
                .init(text: "〜んですけど", note: "~인데요 (부드럽게 말 꺼낼 때)"),
            ]),
        ]
        return doc
    }

    func testEveryItemGetsItsPartAndAnswersStayAtTheBack() {
        let parts = BookWorkbook(doc: Self.englishTalkBook()).parts()
        XCTAssertEqual(parts.map(\.id),
                       ["words", "expressions", "drill", "dictation", "recall", "answers", "dialogue"])

        let drill = parts.first { $0.id == "drill" }!.html
        XCTAssertTrue(drill.contains("Yesterday I do the laundry"))
        XCTAssertFalse(drill.contains("Yesterday I did the laundry"), "the answer sits beside its question")
        let answers = parts.first { $0.id == "answers" }!.html
        XCTAssertTrue(answers.contains("Yesterday I did the laundry"))

        let dictation = parts.first { $0.id == "dictation" }!.html
        XCTAssertFalse(dictation.contains("catch up for a day"), "dictation prints the line it asks for")

        let words = parts.first { $0.id == "words" }!.html
        XCTAssertTrue(words.contains("집안일"), "the glossary meaning reaches the word row")
    }

    func testJapaneseWritesInCells() {
        let words = BookWorkbook(doc: Self.japaneseWatchBook()).parts().first { $0.id == "words" }!.html
        XCTAssertTrue(words.contains("class=\"cells\""))
        XCTAssertFalse(words.contains("class=\"band\""))
    }

    func testWorkbookIsARealMultiPagePDF() throws {
        for (name, doc) in [("workbook-en", Self.englishTalkBook()), ("workbook-ja", Self.japaneseWatchBook())] {
            let data = doc.pdfData()
            XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
            let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
            XCTAssertGreaterThan(pdf.numberOfPages, 4)
            if let dir = ProcessInfo.processInfo.environment["WORKBOOK_OUT"] {
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).pdf"))
            }
        }
    }
}

/// Builds a workbook from a REAL saved talk, through the app's own builders —
/// set `TEST_RUNNER_WORKBOOK_SESSION=<one Session as JSON>` and
/// `TEST_RUNNER_WORKBOOK_OUT=<dir>`. Skipped otherwise.
@MainActor
final class BookWorkbookRealSessionTests: XCTestCase {
    func testRealSessionWorkbook() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["WORKBOOK_SESSION"], let out = env["WORKBOOK_OUT"] else {
            throw XCTSkip("no session given")
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let session = try dec.decode(Session.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let level = CEFRLevel(rawValue: env["WORKBOOK_LEVEL"] ?? "b1") ?? .b1
        let curriculum = TalkCurriculum.build(session: session, proficiency: level,
                                              shadowAttempts: [], drillCards: [])
        var doc = BookDocument.make(session: session, curriculum: curriculum, appState: AppState())
        doc.language = session.targetLanguage
        if let glossary = await BookGlossary.section(for: doc, native: "ko", target: doc.language) {
            doc.sections.append(glossary)
        }
        try doc.pdfData().write(to: URL(fileURLWithPath: out).appendingPathComponent("real-workbook.pdf"))
    }
}
