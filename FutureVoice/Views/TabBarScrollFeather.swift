import SwiftUI

/// The wash that lets scrolling content dissolve into whatever sits below it —
/// the tab bar, a bottom control panel — instead of being sliced off by a hard
/// edge. A ramp from transparent to solid over `ramp` points, then solid for
/// whatever height it's given beyond that.
///
/// `fill` decides how it reads. `.bar` (the nav/tab-bar material) is right when
/// the thing below is itself a bar and content should blur into it; a flat
/// `Color(.systemBackground)` is right on a plain page, where a material would
/// tint a band across the bottom.
struct ScrollEdgeFeather<S: ShapeStyle>: View {
    let fill: S
    /// Length of the transparent → solid ramp, measured from the top edge.
    var ramp: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(fill)
                .mask {
                    LinearGradient(colors: [.clear, .black],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(height: ramp)
            Rectangle().fill(fill)
        }
    }
}

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
    func tabBarScrollFeather(ramp: CGFloat = 72, solid: CGFloat = 44) -> some View {
        // A bottom-aligned OVERLAY would stop at the safe-area edge, leaving
        // the strip beside the floating tab bar razor-sharp — exactly the seam
        // this is here to remove. So the wash rides a full-height container
        // that ignores the bottom inset, and a Spacer pushes it to the
        // physical screen edge.
        overlay {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ScrollEdgeFeather(fill: .bar, ramp: ramp)
                    .frame(height: ramp + solid)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}
