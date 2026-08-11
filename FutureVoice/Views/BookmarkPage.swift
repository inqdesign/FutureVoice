import SwiftUI

/// One ribbon bookmark's data — id, icon, and the progress it carries.
struct BookmarkTab<ID: Hashable> {
    let id: ID
    let icon: String
    /// Accessibility label for the ribbon.
    let title: String
    var done: Int? = nil
    var total: Int? = nil
    var count: Int? = nil
}

/// A full-height book page with ribbon bookmarks fixed on its right edge —
/// shared by the two book detail pages (ScenarioDetailView,
/// ConversationDetailView) so both books read as the same object.
///
/// The book's layout is FIXED: the page fills the available space and the
/// ribbons never move; only the page's content scrolls, inside the page.
/// The selected ribbon shares the page's fill and sits flush against its
/// edge, so tab and page read as one sheet of paper. Tapping a ribbon swaps
/// the page's content in place — no navigation.
struct BookmarkedPage<ID: Hashable, Content: View>: View {
    let tabs: [BookmarkTab<ID>]
    let selection: ID?
    let onSelect: (ID) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .background(Color(.secondarySystemGroupedBackground))
            // Square where the ribbons attach (top trailing) — a rounded
            // corner there would curve away from the first ribbon and break
            // the tab-and-page-are-one-paper illusion.
            .clipShape(UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 16, bottomLeading: 16,
                                   bottomTrailing: 16, topTrailing: 0),
                style: .continuous))
            VStack(spacing: 4) {
                ForEach(tabs, id: \.id) { ribbon($0) }
            }
            .frame(width: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func ribbon(_ tab: BookmarkTab<ID>) -> some View {
        let selected = tab.id == selection
        return Button {
            onSelect(tab.id)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                if let done = tab.done, let total = tab.total, total > 0 {
                    if done == total {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(done)/\(total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                } else if let count = tab.count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            .frame(width: 40)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                       bottomTrailing: 10, topTrailing: 10),
                    style: .continuous)
                    // The selected ribbon is the page's own paper; the rest
                    // sit tucked behind, dimmer and slightly shorter.
                    .fill(Color(.secondarySystemGroupedBackground)
                        .opacity(selected ? 1 : 0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
