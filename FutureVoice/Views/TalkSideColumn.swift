import SwiftUI

// The Mac's right column on the Talk tab (founder, 2026-11-04): the three
// doors that float at the bottom of the phone's page — the player, the
// topics, the tutor — are three tabs of one column beside Talk, open from
// the start. A narrow window keeps the phone's page and its three buttons.

/// Which tab the column shows. Remembered between launches; the tutor's
/// daily note and anything that asks for the chat bring the Tutor tab
/// forward.
@MainActor
final class TalkSideColumn: ObservableObject {
    static let shared = TalkSideColumn()

    enum Tab: String, CaseIterable, Identifiable {
        case tutor, podcast, topics
        var id: String { rawValue }
    }

    @Published var tab: Tab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }

    private static let key = "mac.talkSideTab"

    private init() {
        tab = Tab(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .tutor
    }
}

private struct InTalkSideColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for a page drawn as a tab of the Talk column: it has no close
    /// button (the column stays) and wears the column's grouped background.
    var inTalkSideColumn: Bool {
        get { self[InTalkSideColumnKey.self] }
        set { self[InTalkSideColumnKey.self] = newValue }
    }
}

/// The column's tabs, one row on top of the column — Progress's chips
/// (the active one filled with the label colour), the tutor first
/// (founder, 2026-11-04). Each page keeps its own bar under it.
struct TalkSideTabPicker: View {
    @ObservedObject private var column = TalkSideColumn.shared

    var body: some View {
        HStack(spacing: 8) {
            chip(.tutor, "Tutor")
            chip(.podcast, "Podcast")
            chip(.topics, "Topics")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func chip(_ tab: TalkSideColumn.Tab, _ title: LocalizedStringKey) -> some View {
        let on = column.tab == tab
        return Button { column.tab = tab } label: {
            Text(title)
                .font(.body.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(on ? Color(.label) : Color(.secondarySystemGroupedBackground)))
                .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
