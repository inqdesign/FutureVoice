import SwiftUI

/// The bottom action row of a study card — the word card and the expression
/// card share these so the two can't drift apart (they had, 2026-09-23:
/// different labels, chevrons in different places, and titles typed as
/// `String`, which `Label` does not localize).
///
/// `CardActionButton`: a labelled glass capsule (Keep / I know).
/// `CardStepButton`: its icon-only sibling for the ↑ ↓ chevrons, sized to the
/// glyph so the two labelled buttons keep the width.
struct CardActionButton: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                // One line, always. Four controls share this row, so a label
                // that wraps ("I" / "know") both looks broken and grows the
                // bar's height.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(tint)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            // .bordered alone is a translucent tint with NO blur, so over the
            // scrolling sheet content the label fought whatever sat beneath
            // it (visible on pre-26 iPads). A material capsule underneath
            // gives the same read-through-blur the glass style provides.
            button.buttonStyle(.bordered)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

struct CardStepButton: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                // Just the glyph — every point saved here is a point the two
                // labelled buttons get to keep.
                .frame(width: 14)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .accessibilityLabel(label)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
                .background(.regularMaterial, in: Capsule())
        }
    }
}
