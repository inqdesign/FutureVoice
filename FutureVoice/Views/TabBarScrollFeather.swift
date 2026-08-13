import SwiftUI

extension View {
    /// Feathers the bottom edge of a screen whose scrolling content is nested
    /// inside a horizontal pager, so cards dissolve as they slide under the
    /// tab bar instead of running razor-sharp off the screen.
    ///
    /// Talk and Watch scroll in the tab's OWN scroll view, so the tab bar's
    /// scroll edge effect attaches to it and they get that dissolve for free.
    /// Practice and Progress page horizontally and their real (vertical)
    /// scroll views are CHILDREN of that pager — the system never attaches the
    /// effect to a nested scroll view, which is the same reason both screens
    /// already hand-roll their header panel. This is that panel mirrored: the
    /// same `.bar` material behind the same gradient mask, feathered at the
    /// top edge instead of the bottom.
    ///
    /// Apply to the pager itself, not to a page — one wash covers every page.
    func tabBarScrollFeather(height: CGFloat = 116) -> some View {
        // A bottom-aligned OVERLAY would stop at the safe-area edge, leaving
        // the strip beside the floating tab bar razor-sharp — exactly the seam
        // this is here to remove. So the wash rides a full-height container
        // that ignores the bottom inset, and a Spacer pushes it to the
        // physical screen edge.
        overlay {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(.bar)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.62),
                                               .init(color: .black, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: height)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}
