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

/// A phone whose screen is 667 pt tall (iPhone SE, a mini with Display
/// Zoom). Every layout here was drawn on 844+ pt, and on this class a
/// `.medium` sheet is ~330 pt — less than most sheets' fixed copy and
/// buttons, so the last rows were simply cut off.
enum ScreenClass {
    static var isShort: Bool { UIScreen.main.bounds.height < 700 }
}

extension View {
    /// `presentationDetents`, except that on a short phone `.medium` opens
    /// as `.large`: half of 667 pt holds too little to show a sheet's
    /// buttons. Full-size phones keep exactly the detents asked for.
    func fittingDetents(_ detents: Set<PresentationDetent>) -> some View {
        guard ScreenClass.isShort, detents.contains(.medium) else {
            return presentationDetents(detents)
        }
        var fitted = detents
        fitted.remove(.medium)
        fitted.insert(.large)
        return presentationDetents(fitted)
    }
}
