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
        case podcast, topics, tutor
        var id: String { rawValue }
    }

    @Published var tab: Tab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }

    private static let key = "mac.talkSideTab"

    private init() {
        tab = Tab(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .topics
    }
}

private struct InTalkSideColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for a page drawn as a tab of the Talk column: it wears the tab
    /// switcher in its bar and has no close button (the column stays).
    var inTalkSideColumn: Bool {
        get { self[InTalkSideColumnKey.self] }
        set { self[InTalkSideColumnKey.self] = newValue }
    }
}

/// The column's tabs, in the bar of whichever page is showing — in the
/// order the phone's bottom row has them.
struct TalkSideTabPicker: View {
    @ObservedObject private var column = TalkSideColumn.shared

    var body: some View {
        Picker(selection: $column.tab) {
            Text("Podcast").tag(TalkSideColumn.Tab.podcast)
            Text("Topics").tag(TalkSideColumn.Tab.topics)
            Text("Tutor").tag(TalkSideColumn.Tab.tutor)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

extension View {
    /// The tab switcher in this page's bar, when the page is a column tab.
    func talkSideTabBar(_ inColumn: Bool) -> some View {
        toolbar {
            if inColumn {
                ToolbarItem(placement: .principal) { TalkSideTabPicker() }
            }
        }
    }
}
