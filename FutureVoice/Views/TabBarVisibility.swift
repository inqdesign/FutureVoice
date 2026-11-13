import SwiftUI

/// Who is hiding the tab bar right now (2026-11-13, founder: "when it comes
/// back it should slide up from the bottom, smoothly").
///
/// A deeper page used to hide the bar with its own `.toolbar(.hidden, for:
/// .tabBar)`. On the way back that setting simply vanished with the page, so
/// the bar popped in with no animation, and the tab's root changed its bottom
/// inset in the same frame, under whatever it was loading or animating. Now
/// every such page registers here as it appears and leaves as it disappears,
/// both inside an animation, and the tab ROOTS read this
/// (`RootTabView.tabRoot`): the bar stays down until the last page that hid
/// it is gone, then slides up.
@MainActor @Observable
final class TabBarVisibility {
    static let shared = TabBarVisibility()

    private(set) var hiders: Set<UUID> = []
    var isHidden: Bool { !hiders.isEmpty }

    /// Down a touch faster than it comes back up.
    fileprivate func hide(_ id: UUID) {
        guard !hiders.contains(id) else { return }
        withAnimation(.smooth(duration: 0.28)) { _ = hiders.insert(id) }
    }

    fileprivate func show(_ id: UUID) {
        guard hiders.contains(id) else { return }
        withAnimation(.smooth(duration: 0.38)) { _ = hiders.remove(id) }
    }
}

private struct HidesTabBar: ViewModifier {
    let hides: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            // Still said here too, so the bar is down from the push's first
            // frame; the shared state is what holds it down on the way back.
            .toolbar(hides ? MacLayout.tabBarOnPhoneOnly : .automatic, for: .tabBar)
            .onAppear { if hides && !MacLayout.isMac { TabBarVisibility.shared.hide(id) } }
            .onDisappear { TabBarVisibility.shared.show(id) }
            .onChange(of: hides) { _, now in
                if now && !MacLayout.isMac { TabBarVisibility.shared.hide(id) }
                else { TabBarVisibility.shared.show(id) }
            }
    }
}

extension View {
    /// A deeper page that has the whole screen: the tab bar slides away while
    /// it is up and slides back up once it is gone. The Mac keeps its tabs.
    func hidesTabBar(_ hides: Bool = true) -> some View {
        modifier(HidesTabBar(hides: hides))
    }
}
