import Foundation
import UIKit

/// A book as a WORKBOOK — the same `BookDocument`, laid out for a pen.
///
/// The reader PDF (`BookDocument.html`) is a document: everything is printed,
/// nothing is left to do. People who study by hand work differently, and the
/// pages here are built around what they already do rather than a new
/// method:
///
/// - **Cover, write** (words): the word sits left of a fold line, its meaning
///   right of it. Fold the word under (or lay GoodNotes' tape over it), read
///   the meaning, write the word, unfold to check.
/// - **Copying** (expressions): the fluent self's sentence, then lines to copy
///   it and to say it about your own life — 필사, a whole genre of its own.
/// - **Mistake notebook** (corrections): what you said and a blank to redo it.
///   The fix is in the answer pages at the back, never beside the question.
/// - **Dictation** (shadow lines): the line is played in the app, the page has
///   only its number, its length and the lines to write on.
/// - **Blank-page recall**: one empty page — write everything you remember.
///
/// Copying a word ten times (깜지) is deliberately absent: copying with the
/// answer in view trains the hand, recalling it trains the memory, so the
/// space goes to recall.
///
/// Every part starts on its own page and the right edge carries index tabs
/// that are real PDF links — an iPad notes app reads them like a planner's.
/// That is why each part is laid out by its own page renderer: the page a
/// part starts on is only known after the parts before it have been flowed.
@MainActor
struct BookWorkbook {
    let doc: BookDocument

    static let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4 @72dpi
    /// Wider on the right: the tabs live there.
    static let content = CGRect(x: 44, y: 48, width: 595.2 - 44 - 70, height: 841.8 - 48 - 62)

    struct Part {
        let id: String
        let tab: String
        let title: String
        let blurb: String
        let html: String
    }

    // MARK: - Material

    private func section(_ kind: BookDocument.Section.Kind) -> BookDocument.Section? {
        doc.sections.first { $0.kind == kind && !$0.isEmpty }
    }

    /// Dictionary meanings by term, from the glossary the export appended.
    /// Short on purpose: a writing row has room for a gloss, not an entry.
    private var meanings: [String: String] {
        guard let g = section(.glossary) else { return [:] }
        var out: [String: String] = [:]
        for e in g.entries {
            let senses = e.note.components(separatedBy: " · ").prefix(2)
            out[Self.key(e.text)] = senses.joined(separator: " · ")
        }
        return out
    }

    private var examples: [String: String] {
        guard let g = section(.glossary) else { return [:] }
        return Dictionary(g.entries.map { (Self.key($0.text), $0.example) },
                          uniquingKeysWith: { a, _ in a })
    }

    private static func key(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Squares for scripts written one character to a box.
    private var usesCells: Bool {
        let base = doc.language.split(separator: "-").first.map(String.init) ?? doc.language
        return ["ja", "ko", "zh"].contains(base)
    }

    private var drills: [BookDocument.Entry] {
        section(.drill)?.entries.filter { !($0.original ?? "").isEmpty } ?? []
    }

    private var dictation: [BookDocument.Entry] {
        section(.shadow)?.entries ?? []
    }

    // MARK: - Parts

    func parts() -> [Part] {
        var out: [Part] = []
        if let words = section(.words) { out.append(wordsPart(words)) }
        if let expr = section(.expressions) { out.append(expressionsPart(expr)) }
        if !drills.isEmpty { out.append(drillPart()) }
        if !dictation.isEmpty { out.append(dictationPart()) }
        if !out.isEmpty { out.append(recallPart()) }
        if !drills.isEmpty || !dictation.isEmpty { out.append(answersPart()) }
        if let talk = section(.transcript) ?? section(.scene) { out.append(dialoguePart(talk)) }
        return out
    }

    private func header(_ title: String, _ steps: [String]) -> String {
        var h = "<h2>\(esc(title))</h2>"
        if !steps.isEmpty {
            h += "<p class=\"steps\">"
            h += steps.enumerated().map { i, s in
                "<span class=\"st\"><span class=\"n\">\(i + 1)</span>\(esc(s))</span>"
            }.joined(separator: " ")
            h += "</p>"
        }
        return h
    }

    private func wordsPart(_ s: BookDocument.Section) -> Part {
        let title = explain("Cover and write")
        var body = header(title, [
            explain("Say the word out loud"),
            explain("Fold the word column under"),
            explain("Read the meaning, write the word"),
            explain("Unfold and check — tick the box"),
            explain("Use it in a sentence of your own"),
        ])
        let meanings = self.meanings
        for e in s.entries {
            let meaning = meanings[Self.key(e.text)] ?? ""
            body += "<table class=\"word\"><tr><td class=\"wl\">"
            body += "<span class=\"box\"></span>"
            body += "<p class=\"w\">\(esc(e.text))</p>"
            if e.mastered == true { body += "<p class=\"tag\">\(esc(explain("Mastered in the app")))</p>" }
            body += "</td><td class=\"wr\">"
            if meaning.isEmpty {
                body += "<p class=\"m blank\">\(esc(explain("Meaning")))</p>"
            } else {
                body += "<p class=\"m\">\(esc(meaning))</p>"
            }
            body += usesCells ? cells(trace: e.text) : band()
            body += "<p class=\"cap\">\(esc(explain("Your sentence")))</p>"
            body += usesCells ? rule() : band()
            body += "</td></tr></table>"
        }
        return Part(id: "words", tab: explain("Words"), title: title,
                    blurb: explain("Recall each word from its meaning"), html: body)
    }

    private func expressionsPart(_ s: BookDocument.Section) -> Part {
        let title = explain("Copy it out")
        var body = header(title, [
            explain("Read it out loud"),
            explain("Copy the sentence"),
            explain("Say it about your own life"),
        ])
        let meanings = self.meanings
        let examples = self.examples
        for e in s.entries {
            let example = e.example.isEmpty ? (examples[Self.key(e.text)] ?? "") : e.example
            body += "<div class=\"expr\">"
            body += "<p><span class=\"box\"></span><span class=\"w\">\(esc(e.text))</span>"
            if let m = meanings[Self.key(e.text)], !m.isEmpty {
                body += " <span class=\"m\">\(esc(m))</span>"
            }
            body += "</p>"
            if !example.isEmpty { body += "<p class=\"ex\">\(esc(example))</p>" }
            body += "<div class=\"lines\">"
            body += labeledRule(explain("Copy"))
            body += labeledRule(explain("Mine"))
            body += labeledRule("")
            body += "</div>"
            body += "</div>"
        }
        return Part(id: "expressions", tab: explain("Expressions"), title: title,
                    blurb: explain("Copy the fluent self's lines, then make them yours"), html: body)
    }

    private func drillPart() -> Part {
        let title = explain("Mistake notebook")
        var body = header(title, [
            explain("Read what you said"),
            explain("Write it the way you'd say it now"),
            explain("Check the answers at the back"),
            explain("Come back to it — date each look"),
        ])
        for (i, e) in drills.enumerated() {
            body += "<div class=\"card\">"
            body += "<table class=\"cardhead\"><tr><td class=\"q\">Q\(i + 1)</td>"
            body += "<td class=\"dates\">\(esc(explain("Looked again"))) "
            body += "<span class=\"date\"></span><span class=\"date\"></span><span class=\"date\"></span></td></tr></table>"
            body += "<p class=\"lbl\">\(esc(explain("You said")))</p>"
            body += "<p class=\"said\">\(esc(e.original ?? ""))</p>"
            body += "<p class=\"lbl\">\(esc(explain(key: "workbook.redo", default: "Write it again")))</p>"
            body += rule() + rule()
            body += "</div>"
        }
        return Part(id: "drill", tab: explain("Mistakes"), title: title,
                    blurb: explain("Redo what you said, answers at the back"), html: body)
    }

    private func dictationPart() -> Part {
        let title = explain("Dictation")
        var body = header(title, [
            explain("Play the line in the app's Shadow chapter"),
            explain("Write down what you hear"),
            explain("Check it at the back"),
            explain("Read it aloud five times"),
        ])
        for (i, e) in dictation.enumerated() {
            let words = WordSplitter.count(e.text)
            let lines = max(1, Int((Double(e.text.count) / 52).rounded(.up)))
            body += "<div class=\"dict\">"
            body += "<table class=\"cardhead\"><tr><td class=\"q\">D\(i + 1)"
            body += " <span class=\"len\">\(esc(explain("\(words) words")))</span></td>"
            body += "<td class=\"dates\">\(String(repeating: "<span class=\"dot\"></span>", count: 5))</td></tr></table>"
            body += String(repeating: rule(), count: lines + 1)
            body += "</div>"
        }
        return Part(id: "dictation", tab: explain("Dictation"), title: title,
                    blurb: explain("Hear it in the app, write it here"), html: body)
    }

    private func recallPart() -> Part {
        let title = explain("Blank page")
        var body = header(title, [
            explain("Close the book"),
            explain("Write every word, phrase and sentence you remember"),
            explain("Then check against the pages before and fill gaps in another colour"),
        ])
        body += String(repeating: rule(), count: 24)
        return Part(id: "recall", tab: explain("Recall"), title: title,
                    blurb: explain("Everything you remember, from nothing"), html: body)
    }

    private func answersPart() -> Part {
        let title = explain(key: "workbook.answers", default: "Answers")
        var body = "<h2>\(esc(title))</h2>"
        if !drills.isEmpty {
            body += "<h3>\(esc(explain("Mistake notebook")))</h3>"
            for (i, e) in drills.enumerated() {
                body += "<div class=\"ans\"><span class=\"q\">Q\(i + 1)</span> <span class=\"w\">\(esc(e.text))</span>"
                if !e.note.isEmpty { body += "<p class=\"why\">\(esc(e.note))</p>" }
                body += "</div>"
            }
        }
        if !dictation.isEmpty {
            body += "<h3>\(esc(explain("Dictation")))</h3>"
            for (i, e) in dictation.enumerated() {
                body += "<div class=\"ans\"><span class=\"q\">D\(i + 1)</span> \(esc(e.text))</div>"
            }
        }
        return Part(id: "answers", tab: title, title: title,
                    blurb: explain("Look here only after you've written"), html: body)
    }

    private func dialoguePart(_ s: BookDocument.Section) -> Part {
        let title = s.kind == .scene ? s.title : explain("The whole conversation")
        var body = "<h2>\(esc(title))</h2><table class=\"talk\">"
        body += "<tr><td></td><td></td><td class=\"memohead\">\(esc(explain("Notes")))</td></tr>"
        for line in s.lines {
            body += "<tr class=\"\(line.isUser ? "mine" : "")\"><td class=\"who\">\(esc(line.speaker))</td><td class=\"say\">"
            body += "<p>\(esc(line.text))</p>"
            if let c = line.correction, !c.isEmpty { body += "<p class=\"fix\">→ \(esc(c))</p>" }
            for f in line.fixes { body += "<p class=\"why\">\(esc(f))</p>" }
            body += "</td><td class=\"memo\"></td></tr>"
        }
        body += "</table>"
        return Part(id: "dialogue", tab: explain("Talk"), title: title,
                    blurb: explain("With room in the margin"), html: body)
    }

    private func coverHTML(_ parts: [Part], firstPages: [Int]) -> String {
        var body = "<div class=\"cover\"><p class=\"kind\">\(esc(doc.kind)) · \(esc(explain("Workbook")))</p>"
        body += "<h1>\(esc(doc.title))</h1>"
        let head = (doc.subtitle.isEmpty ? [] : [doc.subtitle]) + doc.meta
        if !head.isEmpty { body += "<p class=\"meta\">\(esc(head.joined(separator: " · ")))</p>" }
        if let o = section(.overview), !o.blurb.isEmpty {
            body += "<p class=\"overview\">\(esc(o.blurb))</p>"
        }
        body += "<h3>\(esc(explain("In this book")))</h3><table class=\"toc\">"
        for (p, page) in zip(parts, firstPages) {
            body += "<tr><td class=\"tb\"><span class=\"box\"></span></td>"
            body += "<td><span class=\"w\">\(esc(p.title))</span><br><span class=\"m\">\(esc(p.blurb))</span></td>"
            body += "<td class=\"pg\">\(page + 1)</td></tr>"
        }
        body += "</table>"
        body += "<h3>\(esc(explain("Review days")))</h3>"
        body += "<p class=\"m\">\(esc(explain("Come back after a day, three days, a week and two weeks. Date each box when you do.")))</p>"
        body += "<table class=\"stamps\"><tr>"
        for label in [explain("Day 1"), explain("Day 3"), explain("Day 7"), explain("Day 14")] {
            body += "<td><p class=\"sl\">\(esc(label))</p><p class=\"sd\">&nbsp;&nbsp;&nbsp;/&nbsp;&nbsp;&nbsp;</p></td>"
        }
        body += "</tr></table></div>"
        return body
    }

    // MARK: - Writing surfaces

    /// One handwriting band in four lines — ascender, x-height (dashed),
    /// baseline (darker), descender: the English notebook every Korean
    /// learner wrote their first alphabet in.
    private func band() -> String {
        "<div class=\"band\"><div class=\"b1\"></div><div class=\"b2\"></div><div class=\"b3\"></div></div>"
    }

    private func rule() -> String { "<div class=\"rule\"></div>" }

    private func labeledRule(_ label: String) -> String {
        "<table class=\"lr\" width=\"100%\"><tr><td class=\"ll\">\(esc(label))</td><td><div class=\"rule\"></div></td></tr></table>"
    }

    /// A row of squares with a faint centre cross; the word is traced in the
    /// first boxes in light grey, the rest are empty.
    private func cells(trace: String) -> String {
        let chars = trace.filter { !$0.isWhitespace }.map(String.init)
        var row = "<table class=\"cells\"><tr>"
        for i in 0..<Self.cellsPerRow {
            if i < chars.count {
                row += "<td class=\"c t\">\(esc(chars[i]))</td>"
            } else {
                row += "<td class=\"c\"><table class=\"x\"><tr><td></td><td></td></tr><tr><td></td><td></td></tr></table></td>"
            }
        }
        return row + "</tr></table>"
    }

    static let cellsPerRow = 14

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func page(_ body: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(Self.css)</style></head><body>\(body)</body></html>"
    }

    /// Lines are a light grey that a home printer still prints and a pen
    /// still covers; nothing on these pages is a filled area, so a workbook
    /// costs toner only where there is text.
    static let css = """
    * { -webkit-box-sizing: border-box; box-sizing: border-box; }
    body { font: 11pt/1.45 -apple-system, "Helvetica Neue", sans-serif; color: #111; margin: 0; }
    p { margin: 0; }
    h2 { font-size: 17pt; font-weight: 700; margin: 0 0 6pt; }
    h3 { font-size: 10pt; letter-spacing: .08em; text-transform: uppercase; color: #777;
         font-weight: 600; margin: 18pt 0 6pt; }
    .steps { font-size: 9pt; color: #555; margin: 0 0 14pt; padding-bottom: 10pt;
             border-bottom: 1.2pt solid #111; }
    .st { white-space: nowrap; margin-right: 9pt; line-height: 1.9; }
    .n { display: inline-block; width: 12pt; height: 12pt; border-radius: 6pt; border: .7pt solid #555;
         text-align: center; line-height: 11pt; font-size: 7.5pt; font-weight: 700; margin-right: 3pt; }
    .box { display: inline-block; width: 10pt; height: 10pt; border: .8pt solid #777;
           border-radius: 2pt; margin-right: 6pt; vertical-align: -1pt; }
    .w { font-weight: 650; font-size: 12.5pt; }
    .m { color: #555; font-size: 9.5pt; }
    .m.blank { color: #aaa; border-bottom: .6pt solid #ccc; width: 60%; }
    .tag { font-size: 7.5pt; color: #999; margin-top: 2pt; }
    .cap { font-size: 7.5pt; color: #999; margin: 5pt 0 1pt; letter-spacing: .04em; }

    table { border-collapse: collapse; width: 100%; }
    td { vertical-align: top; padding: 0; }
    .word { page-break-inside: avoid; margin-bottom: 10pt; padding-bottom: 8pt;
            border-bottom: .5pt solid #e2e2e2; }
    .wl { width: 120pt; padding: 2pt 10pt 0 0; border-right: .9pt dashed #999; }
    .wl .w { display: inline; }
    .wr { padding-left: 12pt; }
    .wr .m { margin: 2pt 0 5pt; }

    .band { border-top: .6pt solid #c4c4c4; }
    .b1 { height: 8pt; border-bottom: .6pt dashed #b4b4b4; }
    .b2 { height: 10pt; border-bottom: .9pt solid #8f8f8f; }
    .b3 { height: 8pt; border-bottom: .6pt solid #c4c4c4; }
    .rule { height: 25pt; border-bottom: .6pt solid #bdbdbd; }

    .cells { width: auto; }
    .c { width: 23pt; height: 23pt; border: .7pt solid #a8a8a8; text-align: center;
         vertical-align: middle; font-size: 15pt; line-height: 23pt; }
    .c.t { color: #c4c4c4; }
    .x { width: 100%; height: 100%; }
    .x td { height: 11pt; border: 0; }
    .x tr:first-child td { border-bottom: .4pt dashed #dcdcdc; }
    .x td:first-child { border-right: .4pt dashed #dcdcdc; }

    .expr { page-break-inside: avoid; margin-bottom: 14pt; }
    .ex { font-style: italic; color: #333; margin: 3pt 0 0 16pt; }
    .lines { padding-left: 16pt; }
    .ll { width: 34pt; font-size: 7.5pt; color: #999; vertical-align: bottom; padding-bottom: 2pt; }

    .card { page-break-inside: avoid; border: .7pt solid #bbb; border-radius: 5pt;
            padding: 8pt 10pt 6pt; margin-bottom: 10pt; }
    .dict { page-break-inside: avoid; margin-bottom: 12pt; }
    .cardhead td { vertical-align: middle; }
    .q { font-weight: 700; font-size: 11pt; }
    .len { font-weight: 400; font-size: 8.5pt; color: #888; margin-left: 4pt; }
    .dates { text-align: right; font-size: 7.5pt; color: #999; }
    .date { display: inline-block; width: 34pt; border-bottom: .6pt solid #bbb; margin-left: 6pt; height: 10pt; }
    .dot { display: inline-block; width: 10pt; height: 10pt; border-radius: 5pt; border: .7pt solid #999; margin-left: 4pt; }
    .lbl { font-size: 7.5pt; color: #999; letter-spacing: .04em; margin-top: 6pt; }
    .said { font-size: 11.5pt; margin-top: 1pt; }

    .ans { page-break-inside: avoid; padding: 5pt 0; border-bottom: .5pt solid #e6e6e6; }
    .ans .q { display: inline-block; width: 26pt; color: #777; font-size: 9pt; }
    .ans .w { font-size: 11pt; }
    .why { font-size: 9pt; color: #666; margin-left: 30pt; }

    .talk tr { page-break-inside: avoid; }
    .talk td { padding: 5pt 0; border-bottom: .5pt solid #eee; }
    .who { width: 64pt; font-size: 7.5pt; color: #888; letter-spacing: .05em; text-transform: uppercase; padding-top: 7pt !important; }
    .mine .say { padding-left: 14pt; }
    .say .fix { margin-top: 3pt; padding-left: 7pt; border-left: 1.6pt solid #999; }
    .say .why { margin-left: 9pt; }
    .memo { width: 130pt; border-left: .8pt dashed #bbb !important; }
    .memohead { font-size: 7.5pt; color: #aaa; padding-left: 8pt !important; letter-spacing: .05em; }

    .cover { padding-top: 40pt; }
    .kind { font-size: 9pt; letter-spacing: .12em; text-transform: uppercase; color: #777; }
    h1 { font-size: 28pt; line-height: 1.15; margin: 6pt 0 8pt; font-weight: 700; }
    .meta { color: #666; font-size: 10pt; padding-bottom: 14pt; border-bottom: 1.5pt solid #111; }
    .overview { margin-top: 14pt; color: #333; font-size: 10.5pt; }
    .toc td { padding: 7pt 0; border-bottom: .5pt solid #e2e2e2; vertical-align: middle; }
    .toc .tb { width: 20pt; }
    .toc .w { font-size: 11.5pt; }
    .toc .pg { width: 30pt; text-align: right; color: #777; }
    .stamps td { width: 25%; border: .7pt solid #bbb; height: 74pt; padding: 7pt; }
    .stamps td + td { border-left: none; }
    .sl { font-size: 8.5pt; font-weight: 700; color: #555; }
    .sd { font-size: 10pt; color: #bbb; margin-top: 34pt; text-align: right; }
    """

    // MARK: - PDF

    private func renderer(_ html: String) -> UIPrintPageRenderer {
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: page(html)), startingAtPageAt: 0)
        r.setValue(NSValue(cgRect: Self.paper), forKey: "paperRect")
        r.setValue(NSValue(cgRect: Self.content), forKey: "printableRect")
        return r
    }

    func pdfData() -> Data {
        let parts = parts()
        let renderers = parts.map { renderer($0.html) }
        let counts = renderers.map { max($0.numberOfPages, 1) }

        // The cover lists page numbers, which depend on how long the cover is.
        func starts(after cover: Int) -> [Int] {
            var p = cover, out: [Int] = []
            for c in counts { out.append(p); p += c }
            return out
        }
        var cover = renderer(coverHTML(parts, firstPages: starts(after: 1)))
        let coverCount = max(cover.numberOfPages, 1)
        if coverCount != 1 { cover = renderer(coverHTML(parts, firstPages: starts(after: coverCount))) }
        let total = coverCount + counts.reduce(0, +)

        let tabs: [(id: String, label: String)] = [("cover", explain("Contents"))]
            + parts.map { ($0.id, $0.tab) }

        let title = doc.title
        return UIGraphicsPDFRenderer(bounds: Self.paper).pdfData { ctx in
            var pageNo = 0
            func draw(_ r: UIPrintPageRenderer, pages: Int, partId: String) {
                for i in 0..<pages {
                    ctx.beginPage()
                    if i == 0 { ctx.addDestination(withName: partId, at: .zero) }
                    r.drawPage(at: i, in: Self.paper)
                    Self.drawTabs(ctx, tabs: tabs, current: partId)
                    if pageNo > 0 { Self.drawFooter(title: title, page: pageNo + 1, of: total) }
                    pageNo += 1
                }
            }
            draw(cover, pages: coverCount, partId: "cover")
            for (i, part) in parts.enumerated() {
                draw(renderers[i], pages: counts[i], partId: part.id)
            }
        }
    }

    /// Index tabs down the right edge, each a link to its part — on paper a
    /// way to find your place, in a notes app a tap.
    nonisolated private static func drawTabs(_ ctx: UIGraphicsPDFRendererContext,
                          tabs: [(id: String, label: String)], current: String) {
        let top: CGFloat = 70, bottom: CGFloat = Self.paper.height - 90
        let gap: CGFloat = 4
        let h = min(92, (bottom - top - gap * CGFloat(tabs.count - 1)) / CGFloat(tabs.count))
        let w: CGFloat = 22
        let x = Self.paper.width - w - 14
        for (i, tab) in tabs.enumerated() {
            let rect = CGRect(x: x, y: top + CGFloat(i) * (h + gap), width: w, height: h)
            let on = tab.id == current
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            if on {
                UIColor(white: 0.1, alpha: 1).setFill(); path.fill()
            } else {
                UIColor(white: 0.72, alpha: 1).setStroke(); path.lineWidth = 0.6; path.stroke()
            }
            let text = NSAttributedString(string: tab.label, attributes: [
                .font: UIFont.systemFont(ofSize: 7.5, weight: on ? .bold : .medium),
                .foregroundColor: on ? UIColor.white : UIColor(white: 0.35, alpha: 1),
                .kern: 0.4,
            ])
            let size = text.size()
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: .pi / 2)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
            cg.restoreGState()
            if !on { ctx.setDestinationWithName(tab.id, for: rect) }
        }
    }

    nonisolated private static func drawFooter(title: String, page: Int, of total: Int) {
        let text = NSAttributedString(string: "\(title)   ·   \(page) / \(total)", attributes: [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.55, alpha: 1),
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: Self.content.minX, y: Self.paper.height - 36 - size.height / 2))
        let brand = NSAttributedString(string: "nawana.app", attributes: [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: UIColor(white: 0.65, alpha: 1),
        ])
        brand.draw(at: CGPoint(x: Self.content.maxX - brand.size().width,
                               y: Self.paper.height - 36 - size.height / 2))
    }
}

extension BookDocument {
    @MainActor
    func workbookPDFData() -> Data { BookWorkbook(doc: self).pdfData() }
}
