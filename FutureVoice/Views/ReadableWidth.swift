import SwiftUI

extension View {
    /// Adds generous horizontal padding on iPad (regular width) only, leaving
    /// iPhone (compact) layouts untouched. The page still fills the full width;
    /// this just pulls the content in from the edges so single-column,
    /// phone-call style screens don't run edge-to-edge on a wide display.
    ///
    /// Apply to reading/form surfaces (onboarding, welcome, paywall, sheets).
    func iPadContentPadding(_ pad: CGFloat = 96) -> some View {
        modifier(IPadContentPadding(pad: pad))
    }
}

private struct IPadContentPadding: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let pad: CGFloat

    func body(content: Content) -> some View {
        content.padding(.horizontal, sizeClass == .regular ? pad : 0)
    }
}
