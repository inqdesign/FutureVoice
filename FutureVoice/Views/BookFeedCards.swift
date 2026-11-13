import SwiftUI

// The Review tab's Studying page, book-first (2026-10-03, user decision).
//
// Every word, expression, correction and shadow line on Review came out of a
// talk or a scene — it is a chapter of some book. Studying them as four
// free-floating piles threw away the one thing no word-list app has (this is
// the line YOU stumbled on, in THAT call), so the page is books now: the ones
// newest first, each the shelves' own card with one button per chapter under
// it, so a chapter is one tap from the shelf. The order never moves by itself: a
// sort by "most due" reshuffled the page every time a card was cleared.

/// One book as the Studying page shows it — a talk or a scene, flattened.
struct BookPreview: Identifiable {
    enum Source {
        case talk(Session)
        case scenario(Scenario)
    }

    struct Chapter: Identifiable {
        enum Kind: String { case words, expressions, shadow, grammar }
        let kind: Kind
        var id: String { kind.rawValue }
        let title: LocalizedStringKey
        let icon: String
        let items: [ScenarioCurriculum.Item]
        var progress: Double { items.isEmpty ? 0 : Double(mastered) / Double(items.count) }
        var mastered: Int { items.filter { $0.masteredAt != nil }.count }
        /// What the chapter still teaches, first — a preview of a finished
        /// chapter shows what it taught.
        var preview: [String] {
            let open = items.filter { $0.masteredAt == nil }
            return (open.isEmpty ? items : open).map(\.text)
        }
    }

    let id: UUID
    let source: Source
    let title: String
    let created: Date
    let tint: Color
    /// Empty while a talk's chapters are still being derived.
    let chapters: [Chapter]
    /// Items of this book whose review time has come.
    let due: Int

    var total: Int { chapters.reduce(0) { $0 + $1.items.count } }
    var mastered: Int { chapters.reduce(0) { $0 + $1.mastered } }
    var progress: Double { total == 0 ? 0 : Double(mastered) / Double(total) }
}

/// Under every book's card on the Studying page (the shelves' own card, not
/// redrawn — user decision 2026-10-03): one button per chapter in a row — words,
/// expressions, shadowing, grammar — each an icon over its progress bar.
/// A tap opens that chapter's own deck as a sheet, so studying a book is one
/// tap from the shelf instead of a trip through its page.
struct BookChapterButtons: View {
    let book: BookPreview
    let study: (BookPreview.Chapter) -> Void

    var body: some View {
        // All four, always, in the same order — a chapter this book has
        // nothing in (a scene has no grammar) stays in its place, dimmed.
        HStack(spacing: 8) {
            ForEach(book.chapters) { chapter in
                let empty = chapter.items.isEmpty
                let done = !empty && chapter.mastered == chapter.items.count
                Button { study(chapter) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: chapter.icon)
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(height: 24)
                        ProgressView(value: chapter.progress)
                            .tint(done ? .green : book.tint)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.quaternarySystemFill)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .opacity(empty ? 0.4 : 1)
                .accessibilityLabel(Text(chapter.title))
                .accessibilityValue(Text("\(chapter.mastered)/\(chapter.items.count)"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

/// The four kinds of study material, one icon each — the SAME glyph on the
/// library tiles, a book card's chapter buttons and a book page's ribbon
/// tabs, and the same ORDER everywhere: words, expressions, grammar,
/// shadowing (2026-10-03, user decision — each surface had its own set).
enum StudyIcon {
    static let words = "text.book.closed.fill"
    static let expressions = "quote.bubble.fill"
    static let grammar = "checkmark.bubble.fill"
    static let shadowing = "waveform.badge.mic"
}

/// Today's review, one book at a time (2026-11-11, founder: "one card, and
/// they finish them one by one; swipe sideways for the next book; a bigger
/// card with the key things from the talk's summary; a tap opens the book").
/// The top of the card is the book — where it came from, its title, the
/// summary's one line, and what it still teaches per chapter — and opens its
/// page. Under it: how much is left, and the four chapter buttons the feed
/// always had.
struct TodayBookCard: View {
    let book: BookPreview
    /// A scene's linked person, when it has one.
    var personaName: String? = nil
    /// The last mastery event in a talk book; nil before any.
    var lastStudied: Date? = nil
    /// The room the page has left above the tab bar. The card is EXACTLY
    /// this tall, so its chapter buttons never slide under the tab bar; what
    /// the book still teaches gives way instead (2026-11-13, founder).
    var height: CGFloat = TodayBookCard.minHeight
    let open: () -> Void
    let study: (BookPreview.Chapter) -> Void

    /// The floor on a small phone, where the page then scrolls.
    static let minHeight: CGFloat = 280

    private var left: Int { book.total - book.mastered }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The fullest version that fits the room: every row at full
            // length, then one line a row, then no rows at all.
            ViewThatFits(in: .vertical) {
                top(rowLines: nil, noteLines: 3)
                top(rowLines: 1, noteLines: 3)
                top(rowLines: 1, noteLines: 2)
                top(rowLines: 0, noteLines: 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .tint(book.tint)
    }

    /// The book's half of the card. `rowLines` nil = each row at its own
    /// length, 0 = no rows.
    private func top(rowLines: Int?, noteLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(noteLines)
                }
            }
            if rowLines != 0 { keyRows(lines: rowLines) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: The book

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
            meta
            Spacer(minLength: 8)
            if case .talk(let s) = book.source,
               let sc = s.summary?.scorecard, !s.isPractice {
                Text("\(sc.overall)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().stroke(Color(.separator), lineWidth: 2))
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch book.source {
        case .talk:
            BookIconDisc {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title3).foregroundStyle(.tint)
            }
        case .scenario(let sc):
            if let personaName {
                BookIconDisc(photoId: sc.counterpartId) {
                    Text(Books.initials(personaName)).font(.headline.weight(.bold)).foregroundStyle(.tint)
                }
            } else if sc.isPodcastBook {
                BookIconDisc {
                    Image(systemName: NewsShow.icon(for: sc.category)).font(.title3).foregroundStyle(.tint)
                }
            } else if sc.isTopic == true {
                BookIconDisc { Image(systemName: "newspaper.fill").font(.title3).foregroundStyle(.tint) }
            } else {
                BookIconDisc {
                    Image(systemName: Books.roleIcon(for: sc.role)).font(.title3).foregroundStyle(.tint)
                }
            }
        }
    }

    @ViewBuilder
    private var meta: some View {
        switch book.source {
        case .talk(let s):
            let last = [lastStudied, s.endedAt, s.startedAt].compactMap { $0 }.max() ?? s.startedAt
            let when = last.formatted(Date.RelativeFormatStyle(
                presentation: .named, locale: Locale(identifier: UILanguage.chromeLanguage)))
            OriginTag(session: s)?.with(when) ?? .detail(when)
        case .scenario(let sc):
            let role = sc.role.trimmingCharacters(in: .whitespaces)
            OriginTag(scenario: sc).with(personaName ?? (role.isEmpty ? nil : role))
        }
    }

    private var title: String {
        switch book.source {
        case .talk(let s):      return s.displayTitle
        case .scenario(let sc): return sc.cardTitle
        }
    }

    /// The summary's one line: how the talk went, or what the situation is.
    private var note: String? {
        let text: String?
        switch book.source {
        case .talk(let s):
            let top = s.summary?.scorecard?.topLine ?? ""
            text = top.isEmpty ? s.summary?.overallNote : top
        case .scenario(let sc):
            text = sc.cardTitle != sc.environment ? sc.environment : sc.brief?.summary
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// What each chapter still teaches, one line a chapter: the open items
    /// first, so the card shows what finishing this book means.
    @ViewBuilder
    private func keyRows(lines: Int?) -> some View {
        let rows = book.chapters.filter { !$0.items.isEmpty }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { chapter in
                    let done = chapter.mastered == chapter.items.count
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: done ? "checkmark.circle.fill" : chapter.icon)
                            .font(.subheadline)
                            .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .frame(width: 22)
                        Text(preview(chapter))
                            .font(.subheadline)
                            .foregroundStyle(done ? .secondary : .primary)
                            .lineLimit(lines ?? (chapter.kind == .words || chapter.kind == .expressions ? 2 : 4))
                        Spacer(minLength: 6)
                        Text("\(chapter.mastered)/\(chapter.items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func preview(_ chapter: BookPreview.Chapter) -> String {
        switch chapter.kind {
        case .words, .expressions:
            return chapter.preview.prefix(chapter.kind == .words ? 8 : 4).joined(separator: " · ")
        case .grammar, .shadow:
            return chapter.preview.prefix(2).joined(separator: "\n")
        }
    }

    // MARK: Finishing it

    @ViewBuilder
    private var footer: some View {
        if book.chapters.isEmpty {
            // A talk whose chapters are still being derived.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
        } else if book.total == 0 {
            Label("Replay anytime", systemImage: "play.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: book.progress)
                        .tint(left == 0 ? .green : book.tint)
                    HStack {
                        Text("\(left) left")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                        Spacer()
                        Text("\(book.mastered)/\(book.total) mastered")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            BookChapterButtons(book: book, study: study)
        }
    }
}
