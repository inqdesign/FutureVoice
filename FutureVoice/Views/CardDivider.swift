import SwiftUI

/// The hairline BETWEEN sections inside one grouped card (Talk's Today card,
/// Practice's study card). Two differences from a bare `Divider()`:
///
/// - it is inset on BOTH edges. A stock divider inside a padded card only gets
///   a leading inset from the caller and runs into the card's right wall,
///   which reads as a mistake rather than as a list separator.
/// - it is lighter. A seam between sections of the SAME object should be
///   quieter than the separator between two independent rows.
///
/// Use it anywhere a card is divided into stacked sections, so every card in
/// the app draws the same seam.
struct CardDivider: View {
    /// Matches the host card's own horizontal content padding.
    var inset: CGFloat = 16
    /// `.vertical` for the seam between columns of a segmented row.
    var axis: Axis = .horizontal

    var body: some View {
        Divider()
            .opacity(0.45)
            .padding(axis == .horizontal ? .horizontal : .vertical, inset)
    }
}
