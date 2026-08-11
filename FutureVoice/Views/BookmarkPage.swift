import SwiftUI

/// A book page with ribbon bookmarks on its right edge — shared by the two
/// book detail pages (ScenarioDetailView, ConversationDetailView) so both
/// books read as the same object.
///
/// The selected ribbon shares the page's fill and sits flush against its
/// edge, so tab and page read as one sheet of paper; the others sit dimmer
/// behind it. Tapping a ribbon swaps the page's content IN PLACE — no
/// navigation. Each ribbon carries its chapter's progress (`5/6`, a green
/// check when complete, or a plain count for chapters without mastery).
struct BookmarkedPage<ID: Hashable, Content: View>: View {
    struct Tab {
        let id: ID
        let icon: String
        /// Accessibility label + the page header when selected.
        let title: String
        var done: Int? = nil
        var total: Int? = nil
        var count: Int? = nil
    }

    let tabs: [Tab]
    let selection: ID?
    let onSelect: (ID) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        // The page never ends above its last ribbon — bookmarks hanging off
        // the bottom edge would read as attached to nothing.
        let ribbonStackHeight = CGFloat(tabs.count) * 66 + 24
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: ribbonStackHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            VStack(spacing: 8) {
                ForEach(tabs, id: \.id) { ribbon($0) }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 18)
        }
    }

    private func ribbon(_ tab: Tab) -> some View {
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
            .frame(width: selected ? 42 : 36)
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
