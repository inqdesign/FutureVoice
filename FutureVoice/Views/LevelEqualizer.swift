import SwiftUI

/// Audio-equalizer level display — the "how your level gets built" glyph for
/// a voice-first app. Four vertical bars (vocabulary / fluency / grammar /
/// expression), each made of six LED blocks, one per CEFR band (A1 at the
/// bottom → C2 at the top). Lit blocks = that axis's level, so a weak axis
/// reads instantly as a shorter column. Levels derived from proxy
/// measurements carry an "≈" in their label.
struct LevelEqualizer: View {
    struct Bar: Identifiable {
        let name: String
        /// "B2", "≈B1", or "—" while that axis has no data yet.
        let level: String
        /// Number of lit blocks, 0…6 (A1 = 1 … C2 = 6).
        let lit: Int
        let color: Color
        var id: String { name }
    }

    let bars: [Bar]

    private static let bands = ["C2", "C1", "B2", "B1", "A2", "A1"]   // top → bottom
    private let blockHeight: CGFloat = 15
    private let blockSpacing: CGFloat = 4

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // CEFR scale — shared y-axis for every bar.
            VStack(spacing: blockSpacing) {
                ForEach(Self.bands, id: \.self) { band in
                    Text(band)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(height: blockHeight)
                }
                labelSpacer
            }

            ForEach(bars) { bar in
                VStack(spacing: blockSpacing) {
                    ForEach(0..<6, id: \.self) { row in
                        // row 0 is the TOP block (C2): lit when the level
                        // reaches this band counted from the bottom.
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill((6 - row) <= bar.lit ? bar.color : Color(.tertiarySystemFill))
                            .frame(height: blockHeight)
                    }
                    VStack(spacing: 1) {
                        Text(bar.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(bar.level)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(bar.lit > 0
                                ? AnyShapeStyle(bar.color)
                                : AnyShapeStyle(.tertiary))
                    }
                    .frame(height: labelHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private let labelHeight: CGFloat = 30

    /// Keeps the y-axis column the same total height as the bar columns.
    private var labelSpacer: some View {
        Color.clear.frame(width: 1, height: labelHeight)
    }
}
