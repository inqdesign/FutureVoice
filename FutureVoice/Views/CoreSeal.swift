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
    /// A taken cell was tapped (its index in the grid).
    var onTap: ((Int) -> Void)? = nil

    private let columns = 10

    private let gap: CGFloat = 4

    /// ONE view whose height is fixed by its width, drawn in a Canvas.
    ///
    /// It was a `LazyVGrid` of a hundred `aspectRatio(1)` cells, and inside a
    /// `List` row that is a self-sizing loop: the row's height depends on the
    /// cells' widths, which round differently each pass on some screen widths,
    /// so the collection view re-laid the row until UIKit aborted
    /// (`_updateVisibleCellsNow` 100 deep, iPhone 13 mini, 375 pt, 1.2.0 —
    /// the Core page closed the app on open). An aspect ratio on the whole
    /// block gives the row one answer for any width.
    var body: some View {
        let seats = max(map?.seats ?? 100, 0)
        let rows = max(1, (seats + columns - 1) / columns)
        Canvas { context, size in
            let side = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            guard side > 0 else { return }
            for index in 0..<seats {
                let rect = CGRect(x: CGFloat(index % columns) * (side + gap),
                                  y: CGFloat(index / columns) * (side + gap),
                                  width: side, height: side)
                // Each seat is a small block of the cube it stands for
                // (2026-10-29: flat fills with a black outline read as a
                // spreadsheet, not a wall of cubes).
                drawBlock(index, in: rect, context: &context)
            }
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .overlay {
            // Tapping a taken cell opens that member's cube: the name for
            // anyone, the hope for members (`CoreSeatDetailSheet`).
            if let onTap {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { point in
                            let side = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                            guard side > 0 else { return }
                            let col = Int(point.x / (side + gap)), row = Int(point.y / (side + gap))
                            let index = row * columns + col
                            guard col < columns, index >= 0, index < (map?.taken ?? 0) else { return }
                            HapticEngine.selection()
                            onTap(index)
                        }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement()
        .accessibilityLabel(Text("The Core"))
        .accessibilityValue(Text(verbatim: "\(map?.taken ?? 0) / \(seats)"))
    }

    @Environment(\.colorScheme) private var scheme

    /// One seat drawn as a small block of the cube it stands for: lit from
    /// above, its own colour carved deeper along the bottom edge, resting on
    /// a soft shadow. An empty seat is a shallow hollow. Yours lifts a little
    /// and glows in its colour instead of wearing a black outline.
    private func drawBlock(_ index: Int, in rect: CGRect, context: inout GraphicsContext) {
        let radius = rect.width * 0.18
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        guard let map, index < map.themes.count else {
            // Hollow: a faint fill, darker along the top inside edge.
            let hollow = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            context.fill(hollow, with: .color(Color.primary.opacity(scheme == .dark ? 0.07 : 0.05)))
            var inner = context
            inner.clip(to: hollow)
            inner.fill(Path(rect.offsetBy(dx: 0, dy: -rect.height + 1.4)),
                       with: .color(Color.black.opacity(scheme == .dark ? 0.35 : 0.08)))
            return
        }
        let base = UIColor(FutureselfTheme(rawValue: map.themes[index])?.tint ?? .secondary)
            .resolvedColor(with: traits)
        let mine = map.mine == index
        let body = rect.offsetBy(dx: 0, dy: mine ? -1.5 : 0)
        let block = Path(roundedRect: body, cornerRadius: radius, style: .continuous)

        // Shadow under it, wider and softer for your own.
        var shadow = context
        shadow.addFilter(.blur(radius: mine ? 3.5 : 1.2))
        shadow.fill(Path(roundedRect: body.offsetBy(dx: 0, dy: mine ? 2.5 : 1.2),
                         cornerRadius: radius, style: .continuous),
                    with: .color(Color(mine ? base : .black).opacity(mine ? 0.55 : 0.18)))

        // The block: its colour, lit from the top, carved darker at the foot.
        context.fill(block, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(Self.mix(base, .white, 0.14)), location: 0),
                .init(color: Color(base), location: 0.45),
                .init(color: Color(base), location: 0.78),
                .init(color: Color(Self.mix(base, CoreCubeView.carved(base), 0.55)), location: 1),
            ]),
            startPoint: CGPoint(x: body.midX, y: body.minY),
            endPoint: CGPoint(x: body.midX, y: body.maxY)))
        // A thin highlight along the top edge.
        var lit = context
        lit.clip(to: block)
        lit.fill(Path(CGRect(x: body.minX, y: body.minY, width: body.width, height: 1.2)),
                 with: .color(.white.opacity(0.3)))
        if mine {
            context.stroke(Path(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius,
                                style: .continuous),
                           with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
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
