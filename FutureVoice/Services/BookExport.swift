import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// A Practice book, flattened into something you can study OFF the phone —
/// printed, marked up in an iPad notes app, or pasted into whatever the
/// learner already keeps notes in.
///
/// Both book types collapse into the SAME shape here (`Section` of `Entry`s,
/// plus dialogue blocks), which is the point: a Watch book and a Talk book
/// have the same anatomy on screen — a scene plus material to master — so
/// they should read the same on paper. One document model, two renderers
/// (`markdown`, `pdfData`), and every builder feeds the same thing.
///
/// Language follows the app's split unchanged (see CLAUDE.md, "Two
/// languages"): the material — scene lines, words, expressions, corrected
/// sentences — is in the target language, the notes that explain it are in
/// the learner's own, and the headings are chrome, so a printed book uses the
/// same words as the book on screen.
struct BookDocument: Sendable {

    /// One line of a scene or transcript.
    struct Line: Sendable {
        var speaker: String
        var text: String
        /// The learner's own side — indented differently so a printed
        /// dialogue is still scannable without colour or bubbles.
        var isUser: Bool
        /// The coached rewrite of what they said, when there is one.
        var correction: String? = nil
        var correctionNote: String = ""
    }

    /// One study item: the thing to learn, plus whatever the app knows about
    /// it. `mastered` prints as a ticked box so a paper copy carries the same
    /// progress the book shows.
    struct Entry: Sendable {
        var text: String
        var note: String = ""
        var example: String = ""
        /// The learner's original, for a correction pair ("you said → say").
        var original: String? = nil
        var mastered: Bool? = nil
    }

    struct Section: Sendable {
        var title: String
        var blurb: String = ""
        var entries: [Entry] = []
        var lines: [Line] = []

        var isEmpty: Bool { entries.isEmpty && lines.isEmpty }
    }

    /// Terms this book teaches, in the order they appear. Carried separately
    /// from the sections because a glossary is built LATER and elsewhere:
    /// looking a word up is async (a shared server dictionary), and document
    /// building is synchronous by design so a page can render instantly.
    struct Term: Sendable, Hashable {
        let text: String
        /// Multi-word items get the "explain the whole thing" treatment
        /// rather than a headword entry — asking for a phrase as a word is
        /// what produced a dictionary entry for "hundred".
        let isExpression: Bool
    }

    /// "Watch book" / "Talk book" — the kicker above the title.
    var kind: String
    var title: String
    var subtitle: String = ""
    /// Date, progress, score — one short line each.
    var meta: [String] = []
    var sections: [Section] = []
    var terms: [Term] = []

    /// Filename stem, safe on every filesystem the share sheet can reach.
    var filename: String {
        let base = (title.isEmpty ? kind : title)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = base.isEmpty ? "book" : String(base.prefix(60))
        return stem.replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Builders

@MainActor
extension BookDocument {

    /// A Watch book: the scene it was extracted from, then the words,
    /// expressions and lines to master.
    static func make(scenario: Scenario, appState: AppState) -> BookDocument {
        var doc = BookDocument(kind: chrome("Watch book"),
                               title: scenario.cardTitle)

        let role = scenario.role.trimmingCharacters(in: .whitespaces)
        let persona = scenario.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }?.name
        }
        doc.subtitle = [persona ?? (role.isEmpty ? nil : role), scenario.category]
            .compactMap { $0 }.joined(separator: " · ")

        doc.meta.append(dateLine(scenario.lastUsedAt ?? scenario.createdAt))
        if let c = scenario.curriculum, c.totalCount > 0 {
            doc.meta.append(progressLine(done: c.masteredCount, total: c.totalCount))
        }
        if scenario.isArchived { doc.meta.append(chrome("Archived")) }

        guard let c = scenario.curriculum else { return doc }

        if let dialogue = c.dialogue, !dialogue.isEmpty {
            let other = persona ?? (role.isEmpty ? chrome("The other person") : role)
            doc.sections.append(Section(
                title: c.dialogueTitle ?? chrome("Scene"),
                lines: dialogue.map {
                    Line(speaker: $0.speaker == "user" ? chrome("You") : other,
                         text: $0.text,
                         isUser: $0.speaker == "user")
                }
            ))
        }

        func section(_ title: String, _ items: [ScenarioCurriculum.Item]) -> Section? {
            guard !items.isEmpty else { return nil }
            return Section(title: title, entries: items.map {
                Entry(text: $0.text, note: $0.note, example: $0.example ?? "",
                      mastered: $0.masteredAt != nil)
            })
        }
        doc.sections += [
            section(chrome("Words"), c.words),
            section(chrome("Expressions"), c.expressions),
            section(chrome("Shadow"), c.shadowLines),
        ].compactMap { $0 }

        doc.terms = c.words.map { Term(text: $0.text, isExpression: false) }
                  + c.expressions.map { Term(text: $0.text, isExpression: true) }

        return doc
    }

    /// A Talk book: the score and the coach's note, the material the talk
    /// produced, then the whole conversation with its corrections attached —
    /// the transcript is what makes this worth reading on a bigger screen.
    static func make(session: Session,
                     curriculum: TalkCurriculum.Snapshot,
                     appState: AppState) -> BookDocument {
        var doc = BookDocument(kind: chrome("Talk book"),
                               title: session.displayTitle)

        doc.meta.append(dateLine(session.endedAt ?? session.startedAt))
        if curriculum.totalCount > 0 {
            doc.meta.append(progressLine(done: curriculum.masteredCount,
                                         total: curriculum.totalCount))
        }
        if let card = session.summary?.scorecard {
            doc.meta.append("\(chrome("Score")) \(card.overall)")
        }

        if let note = session.summary?.overallNote.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            doc.sections.append(Section(title: chrome("Overview"), blurb: note))
        }

        let firstTimeWords = session.summary?.newWordsUsed ?? []
        doc.terms = (firstTimeWords + curriculum.words.map(\.text))
            .map { Term(text: $0, isExpression: false) }
        if !firstTimeWords.isEmpty || !curriculum.words.isEmpty {
            var s = Section(title: chrome("Words"))
            s.entries = firstTimeWords.map { Entry(text: $0, note: explain("You used this for the first time.")) }
                + curriculum.words.map {
                    Entry(text: $0.text, note: $0.note, mastered: $0.masteredAt != nil)
                }
            doc.sections.append(s)
        }

        // Both halves of the book's Expressions chapter: the phrases the
        // fluent self offered, then the ones the learner already said.
        let offered = session.summary?.expressionsOffered ?? []
        let expressions = session.summary?.expressionsUsed ?? []
        doc.terms += (offered + expressions).map { Term(text: $0, isExpression: true) }
        if !offered.isEmpty || !expressions.isEmpty {
            var s = Section(title: chrome("Expressions"))
            s.entries = offered.map {
                Entry(text: $0, note: explain("Your fluent self used this — you didn't."))
            } + expressions.map { Entry(text: $0) }
            doc.sections.append(s)
        }

        // The same fluent-self lines the book's Shadow chapter offers — the
        // paper copy carries them too, so it can be read as the whole book.
        let shadowLines = TalkCurriculum.shadowPicks(session: session,
                                                     proficiency: appState.proficiency)
        if !shadowLines.isEmpty {
            doc.sections.append(Section(title: chrome("Shadow"),
                                        entries: shadowLines.map { Entry(text: $0.transcript) }))
        }

        // Corrections — the learner's own sentence next to the fluent one.
        // Same pairing the Drill chapter shows, so the paper copy and the
        // book can't say different things.
        var corrections: [Entry] = []
        var seen = Set<String>()
        for line in curriculum.shadowLines {
            var bytes = line.id.uuid
            bytes.0 ^= 0xFF
            // Quote the SENTENCE the correction rewrites, not the whole turn —
            // same trim the Drill chapter applies (a minute-long turn struck
            // through in full reads as "everything you said was wrong").
            let original = session.turns.first { $0.id == UUID(uuid: bytes) }
                .map { DrillStore.relevantFragment(of: $0.transcript, matching: line.text) }
            corrections.append(Entry(text: line.text, note: line.note,
                                     original: original,
                                     mastered: line.masteredAt != nil))
            seen.insert(CarryoverDetector.normalized(line.text))
        }
        for p in session.summary?.phrasesUsed ?? [] {
            guard seen.insert(CarryoverDetector.normalized(p.fluentAlternative)).inserted
            else { continue }
            corrections.append(Entry(text: p.fluentAlternative, note: p.reason,
                                     original: DrillStore.relevantFragment(
                                        of: p.userSaid, matching: p.fluentAlternative)))
        }
        if !corrections.isEmpty {
            doc.sections.append(Section(title: chrome("Drill"), entries: corrections))
        }

        let transcript = session.turns.filter {
            !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !transcript.isEmpty {
            doc.sections.append(Section(
                title: chrome("Transcript"),
                lines: transcript.map { turn in
                    Line(speaker: turn.role == .user ? chrome("You") : chrome("Future self"),
                         text: turn.transcript,
                         isUser: turn.role == .user,
                         correction: turn.suggestion?.alternative,
                         correctionNote: turn.suggestion?.reason ?? "")
                }
            ))
        }

        return doc
    }

    private static func dateLine(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day()
            .locale(Locale(identifier: LanguageCatalog.currentNative)))
    }

    private static func progressLine(done: Int, total: Int) -> String {
        "\(chrome("Mastered")) \(done)/\(total)"
    }
}

// MARK: - Markdown

extension BookDocument {

    /// Plain-text Markdown — the format that survives being pasted anywhere
    /// (notes apps, Obsidian, a text editor) and still reads as a document if
    /// nothing renders it.
    var markdown: String {
        var out: [String] = []
        out.append("# \(title)")
        var head = [kind]
        if !subtitle.isEmpty { head.append(subtitle) }
        out.append((head + meta).joined(separator: " · "))

        for section in sections where !(section.isEmpty && section.blurb.isEmpty) {
            out.append("\n## \(section.title)")
            if !section.blurb.isEmpty { out.append(section.blurb) }

            for entry in section.entries {
                var line: String
                switch entry.mastered {
                case .some(true):  line = "- [x] "
                case .some(false): line = "- [ ] "
                case .none:        line = "- "
                }
                if let original = entry.original, !original.isEmpty {
                    line += "~~\(original)~~ → **\(entry.text)**"
                } else {
                    line += "**\(entry.text)**"
                }
                out.append(line)
                // Example before note, the same order the PDF prints them:
                // the material first, then the sentence explaining it.
                if !entry.example.isEmpty { out.append("  - _\(entry.example)_") }
                if !entry.note.isEmpty { out.append("  - \(entry.note)") }
            }

            for line in section.lines {
                out.append("\n**\(line.speaker)** — \(line.text)")
                if let c = line.correction, !c.isEmpty {
                    out.append("> → \(c)")
                    if !line.correctionNote.isEmpty { out.append("> \(line.correctionNote)") }
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}

// MARK: - PDF

extension BookDocument {

    /// Print-shaped HTML: black on white, one column, generous leading —
    /// meant to be marked up with a pencil, not to look like the app.
    var html: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        var body = "<header><p class=\"kind\">\(esc(kind))</p><h1>\(esc(title))</h1>"
        let head = (subtitle.isEmpty ? [] : [subtitle]) + meta
        if !head.isEmpty {
            body += "<p class=\"meta\">\(esc(head.joined(separator: " · ")))</p>"
        }
        body += "</header>"

        for section in sections where !(section.isEmpty && section.blurb.isEmpty) {
            body += "<section><h2>\(esc(section.title))</h2>"
            if !section.blurb.isEmpty { body += "<p class=\"blurb\">\(esc(section.blurb))</p>" }

            if !section.entries.isEmpty {
                body += "<ul>"
                for entry in section.entries {
                    let box = switch entry.mastered {
                    case .some(true): "<span class=\"box done\">&#10003;</span>"
                    case .some(false): "<span class=\"box\"></span>"
                    case .none: "<span class=\"box none\"></span>"
                    }
                    body += "<li>\(box)<div class=\"item\">"
                    if let original = entry.original, !original.isEmpty {
                        body += "<p class=\"said\">\(esc(original))</p>"
                    }
                    body += "<p class=\"text\">\(esc(entry.text))</p>"
                    if !entry.example.isEmpty { body += "<p class=\"example\">\(esc(entry.example))</p>" }
                    if !entry.note.isEmpty { body += "<p class=\"note\">\(esc(entry.note))</p>" }
                    body += "</div></li>"
                }
                body += "</ul>"
            }

            for line in section.lines {
                body += "<div class=\"turn\(line.isUser ? " mine" : "")\">"
                body += "<p class=\"speaker\">\(esc(line.speaker))</p>"
                body += "<p class=\"line\">\(esc(line.text))</p>"
                if let c = line.correction, !c.isEmpty {
                    body += "<p class=\"fix\">\(esc(c))</p>"
                    if !line.correctionNote.isEmpty {
                        body += "<p class=\"note\">\(esc(line.correctionNote))</p>"
                    }
                }
                body += "</div>"
            }
            body += "</section>"
        }

        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        * { -webkit-box-sizing: border-box; box-sizing: border-box; }
        body { font: 12pt/1.55 -apple-system, "Helvetica Neue", sans-serif;
               color: #111; margin: 0; }
        header { border-bottom: 1.5px solid #111; padding-bottom: 10pt; margin-bottom: 18pt; }
        .kind { font-size: 8.5pt; letter-spacing: .1em; text-transform: uppercase;
                color: #777; margin: 0 0 4pt; }
        h1 { font-size: 21pt; line-height: 1.2; margin: 0; font-weight: 600; }
        .meta { font-size: 9.5pt; color: #666; margin: 6pt 0 0; }
        section { margin-bottom: 20pt; }
        h2 { font-size: 12.5pt; font-weight: 600; margin: 0 0 8pt;
             padding-bottom: 3pt; border-bottom: .5px solid #ccc; }
        .blurb { margin: 0 0 8pt; color: #333; }
        ul { list-style: none; margin: 0; padding: 0; }
        li { display: flex; align-items: flex-start; page-break-inside: avoid;
             padding: 5pt 0; border-bottom: .5px solid #eee; }
        .box { display: inline-block; width: 11pt; height: 11pt; margin: 3pt 9pt 0 0;
               border: .8px solid #999; border-radius: 2pt; flex: 0 0 auto;
               text-align: center; line-height: 11pt; font-size: 8.5pt; color: #111; }
        .box.done { border-color: #111; }
        .box.none { border: none; }
        .item { flex: 1 1 auto; }
        .item p { margin: 0; }
        .text { font-weight: 600; }
        .said { color: #888; text-decoration: line-through; }
        .example { color: #333; font-style: italic; margin-top: 1pt !important; }
        .note { color: #777; font-size: 10pt; margin-top: 2pt !important; }
        .turn { page-break-inside: avoid; margin-bottom: 10pt; padding-left: 0; }
        .turn.mine { padding-left: 24pt; }
        .speaker { font-size: 8.5pt; letter-spacing: .06em; text-transform: uppercase;
                   color: #888; margin: 0 0 1pt; }
        .line { margin: 0; }
        .fix { margin: 3pt 0 0; padding-left: 8pt; border-left: 2px solid #bbb; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// One A4 PDF with real, selectable text and real pagination.
    ///
    /// `UIMarkupTextPrintFormatter` is doing the layout, which is why the
    /// document is authored as HTML: it is the only thing on iOS that flows
    /// arbitrary-length text across pages without hand-rolling CoreText
    /// pagination. The two `setValue(forKey:)` calls are how a page renderer
    /// is given paper size outside an actual print job.
    @MainActor
    func pdfData() -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4 @72dpi
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 46, dy: 56)),
                          forKey: "printableRect")

        return UIGraphicsPDFRenderer(bounds: paper).pdfData { ctx in
            for page in 0..<max(renderer.numberOfPages, 1) {
                ctx.beginPage()
                renderer.drawPage(at: page, in: paper)
            }
        }
    }
}

// MARK: - Share sheet payloads

/// The book as a PDF. Built only when the share sheet actually asks for it —
/// the document itself is cheap, the render isn't.
struct BookPDFFile: Transferable {
    let document: BookDocument

    static var transferRepresentation: some TransferRepresentation {
        // The parameter type is spelled out on purpose: without it the
        // representation's `Item` can't be inferred from a closure that reads
        // its own argument, and the conformance silently fails to match.
        FileRepresentation(exportedContentType: .pdf) { (file: BookPDFFile) in
            let doc = file.document
            let data = await MainActor.run { doc.pdfData() }
            return SentTransferredFile(try BookExportWriter.write(data, name: "\(doc.filename).pdf"))
        }
    }
}

/// The book as Markdown. `.plainText` with a `.md` name: it opens as text
/// everywhere and renders as a document in anything that knows Markdown.
struct BookTextFile: Transferable {
    let document: BookDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { (file: BookTextFile) in
            let doc = file.document
            let data = Data(doc.markdown.utf8)
            return SentTransferredFile(try BookExportWriter.write(data, name: "\(doc.filename).md"))
        }
    }
}

enum BookExportWriter {
    /// Exports land in `temporaryDirectory` — the share sheet copies what it
    /// needs and the OS reclaims the rest, so nothing accumulates in the
    /// user's documents.
    static func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
