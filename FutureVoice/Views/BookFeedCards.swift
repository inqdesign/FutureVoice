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
                            .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(book.tint))
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
