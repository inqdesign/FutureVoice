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

/// The Core's one glyph: this person is in the Core, right now.
///
/// **It has no second state, and must never get one back** (2026-08-18). It
/// used to come in two — filled for a seated member, outlined for someone who
/// had qualified but currently held no seat — so that the month which earned
/// the badge could never be taken away. That reasoning is sound about the
/// RECORD and wrong about the BADGE, and the place it failed is the only place
/// the seal is ever seen by someone else: a mark beside a stranger's name in
/// Find people. A stranger cannot read one seal, let alone tell two apart, and
/// nothing on that row can explain that this one means "was here once". A
/// badge that needs a legend to say which of two things it means isn't a badge.
///
/// So the rule is the one sentence anyone can hold: the seal means they're in
/// the Core today. Qualification is still permanent where it does real work —
/// the queue, and re-entry on the keep bar — it just isn't something worn.
///
/// A stranger sees the seal and nothing else — no number, no rank, no talk
/// time. Rank decides who gets in; inside the club everyone is equal, and a
/// number next to a name in a browsable list would rebuild the hierarchy the
/// design spent its effort removing.
struct CoreSeal: View {
    var font: Font = .caption

    var body: some View {
        Image(systemName: "seal.fill")
            .font(font)
            .foregroundStyle(Color.coreClub)
            .accessibilityLabel(Text("The Core"))
    }
}

/// The seal with the word for it, on the one surface that is ABOUT this
/// person — their own club screen. Only ever drawn for a member who is in.
///
/// This used to print a join number ("#37"). The number is gone from every
/// surface: it was an ordinal that never gets reused, so it climbs past the
/// seat count forever, and "#137" beside a picture of a hundred seats is a
/// contradiction a learner has to be talked out of. It also used to have a
/// second wording, "Been in the Core", for the seatless — a sentence that told
/// a person what they no longer had, in the colour of the thing they no longer
/// had. Their standing is now said in plain rows, without the seal.
struct CoreSealRow: View {
    var body: some View {
        HStack(spacing: 6) {
            CoreSeal(font: .body)
            Text("In the Core")
                .foregroundStyle(Color.coreClub)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hundred seats as a hundred PIXELS — one square block, ten by ten.
///
/// "37 / 100" is a fact a learner reads; a block with sixty-three empty cells
/// in it is a fact they see. Everything here follows from wanting the second
/// one, and specifically from wanting ONE object rather than a hundred:
///
/// - **Squares, butted up against each other.** Dots with air between them
///   read as a scatter of bullet points — a list. Pixels read as a single
///   surface that happens to be made of people, which is the club. The gap
///   stays at 2pt for exactly that reason; open it further and the block
///   dissolves back into a scatter.
/// - **A filled pixel wears its member's own palette** — the one they picked
///   in Me. It's the only colour in the app that is already theirs by choice,
///   so a wall of them is a wall of PEOPLE. (This is the one screen exempt
///   from "system colours only": the exemption is the point.)
/// - **Oldest first, top-left.** The block is a chronology, so a member can
///   see where in the club's life they arrived, and everyone watches it fill
///   from one corner.
/// - **Empty pixels are drawn, not omitted.** A bar that fills up says "37% of
///   the way to something"; sixty-three blank cells say "someone could sit
///   here, and it could be you."
struct CoreSeatGrid: View {
    /// nil while loading — the grid draws its empty block rather than a
    /// spinner, so nothing jumps when the colours land.
    let map: CoreClubService.SeatMap?

    private let columns = 10

    var body: some View {
        let seats = map?.seats ?? 100
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
            spacing: 2
        ) {
            ForEach(0..<seats, id: \.self) { i in
                seat(i)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement()
        .accessibilityLabel(Text("The Core"))
        .accessibilityValue(Text(verbatim: "\(map?.taken ?? 0) / \(seats)"))
    }

    @ViewBuilder
    private func seat(_ index: Int) -> some View {
        let color = fill(index)
        // Barely-rounded rather than sharp: at this size a true right angle
        // reads as a rendering artifact next to iOS's own geometry, and a
        // radius any larger starts turning the block back into dots.
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color == .clear ? Color.secondary.opacity(0.14) : color)
            .aspectRatio(1, contentMode: .fit)
            // Your own pixel is outlined in place, never recoloured or
            // enlarged: the colour is already saying "this is me" to everyone
            // else, and pulling the cell out of the grid would take you out of
            // the wall you're meant to be part of.
            .overlay {
                if map?.mine == index {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 2)
                }
            }
    }

    private func fill(_ index: Int) -> Color {
        guard let map, index < map.themes.count else { return .clear }
        // An index this build doesn't know is a palette shipped after it —
        // draw the seat as taken in a neutral tone rather than as empty.
        return FutureselfTheme(rawValue: map.themes[index])?.tint ?? .secondary
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 6) {
            Text(verbatim: "Minji").font(.body.weight(.medium))
            CoreSeal()
        }
        HStack(spacing: 6) {
            Text(verbatim: "Joon").font(.body.weight(.medium))
        }
        CoreSealRow()
    }
    .padding()
}
