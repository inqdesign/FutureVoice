import SwiftUI

extension Color {
    /// RESERVED FOR THE CORE. Nothing else in the app may use indigo.
    ///
    /// The UI rules allow only system colors, so a badge can't be made
    /// special by drawing it differently. Scarcity of the colour is the
    /// badge instead: if indigo appears nowhere else, indigo *means* the
    /// Core. Spend it on anything else and the seal stops reading as one.
    static let coreClub = Color(.systemIndigo)
}

/// The Core's one glyph, everywhere it appears.
///
/// - **Filled** — seated right now.
/// - **Outlined** — qualified (permanently) but currently without a seat.
///
/// Outlined has to read as dormant, never as a demerit: the month that earned
/// the badge happened, and nobody takes it back. That's why the difference is
/// fill weight rather than colour or a slash.
///
/// A stranger sees the seal and nothing else — no number, no rank, no talk
/// time. Rank decides who gets in; inside the club everyone is equal, and a
/// number next to a name in a browsable list would rebuild the hierarchy the
/// design spent its effort removing.
struct CoreSeal: View {
    let seated: Bool
    var font: Font = .caption

    var body: some View {
        Image(systemName: seated ? "seal.fill" : "seal")
            .font(font)
            .foregroundStyle(Color.coreClub)
            .accessibilityLabel(Text("The Core"))
    }
}

/// The seal with the person's number, for surfaces that are ABOUT them —
/// their own Me tab, their card. Never a browsable row.
struct CoreSealLabel: View {
    let seated: Bool
    let joinNumber: Int

    var body: some View {
        HStack(spacing: 5) {
            CoreSeal(seated: seated, font: .caption)
            Text(verbatim: "#\(joinNumber)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.coreClub)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 6) {
            Text(verbatim: "Minji").font(.body.weight(.medium))
            CoreSeal(seated: true)
        }
        HStack(spacing: 6) {
            Text(verbatim: "Joon").font(.body.weight(.medium))
            CoreSeal(seated: false)
        }
        CoreSealLabel(seated: true, joinNumber: 72)
    }
    .padding()
}
