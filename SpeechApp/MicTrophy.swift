import SwiftUI

/// The speech app's trophy is a stand microphone, not a coin (2026-11-12,
/// founder: "it's voice, so a golden stand mic?"). Drawn flat since
/// 2026-11-16 (founder: the 3D one read heavy): a round grille head in a
/// yoke, a thin stand and a weighted base with the place on a plate, in the
/// tier's metal with one light side and one shade side. Lay it out about
/// 1.6 times taller than wide.
struct MicTrophy: View {
    let tier: MedalTier
    var label: String = ""

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(0.625, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        // Everything is laid out on a 100 × 160 grid and scaled to fit.
        let s = min(size.width / 100, size.height / 160)
        let ox = (size.width - 100 * s) / 2
        let oy = (size.height - 160 * s) / 2
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
        }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        let base = Color(tier.metal)
        let light = Color(tier.metal.withBrightness(1.18))
        let shade = Color(tier.metal.withBrightness(0.72))
        let deep = Color(tier.metal.withBrightness(0.5))
        let metal = Gradient(colors: [light, base, shade])
        func across(_ rect: CGRect) -> GraphicsContext.Shading {
            .linearGradient(metal, startPoint: CGPoint(x: rect.minX, y: rect.midY),
                            endPoint: CGPoint(x: rect.maxX, y: rect.midY))
        }

        // A soft shadow on the floor.
        context.fill(Ellipse().path(in: r(14, 150, 72, 8)), with: .color(.black.opacity(0.35)))

        // Base: a low dome on a disc.
        let disc = r(16, 138, 68, 14)
        context.fill(Ellipse().path(in: disc.offsetBy(dx: 0, dy: 3 * s)), with: .color(deep))
        context.fill(Ellipse().path(in: disc), with: across(disc))
        let dome = r(34, 132, 32, 12)
        context.fill(Ellipse().path(in: dome), with: across(dome))

        // The stand.
        let pole = r(47.5, 82, 5, 56)
        context.fill(Capsule().path(in: pole), with: across(pole))
        let collar = r(43, 80, 14, 7)
        context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: collar), with: across(collar))

        // The yoke: a U around the head's lower half.
        var yoke = Path()
        yoke.addArc(center: p(50, 44), radius: 31 * s, startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
        context.stroke(yoke, with: .color(shade), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))
        var yokeStem = Path()
        yokeStem.move(to: p(50, 75))
        yokeStem.addLine(to: p(50, 81))
        context.stroke(yokeStem, with: .color(shade), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))

        // The head: a neck, then the round grille.
        let neck = r(38, 50, 24, 22)
        context.fill(RoundedRectangle(cornerRadius: 5 * s).path(in: neck), with: across(neck))
        let head = r(24, 10, 52, 52)
        let headPath = Circle().path(in: head)
        context.fill(headPath, with: .radialGradient(Gradient(colors: [light, base, shade]),
                                                     center: p(40, 24), startRadius: 0, endRadius: 40 * s))
        // The grille: a mesh of bands, clipped to the head.
        context.drawLayer { mesh in
            mesh.clip(to: headPath)
            var lines = Path()
            for y in stride(from: CGFloat(16), through: 58, by: 6) {
                lines.move(to: p(20, y)); lines.addLine(to: p(80, y))
            }
            for x in stride(from: CGFloat(28), through: 74, by: 6) {
                lines.move(to: p(x, 6)); lines.addLine(to: p(x, 64))
            }
            mesh.stroke(lines, with: .color(deep.opacity(0.3)), lineWidth: 0.8 * s)
        }
        // A band around the middle and a highlight on the light side.
        let band = r(24, 33, 52, 6)
        context.fill(Rectangle().path(in: band).intersection(headPath), with: across(band))
        context.stroke(headPath, with: .color(deep.opacity(0.6)), lineWidth: 1.2 * s)
        context.fill(Ellipse().path(in: r(33, 16, 12, 8)), with: .color(.white.opacity(0.35)))

        // The place, on a dark plate at the front of the base.
        if !label.isEmpty {
            let plate = r(38, 139, 24, 11)
            context.fill(RoundedRectangle(cornerRadius: 2.5 * s).path(in: plate), with: .color(Color(white: 0.1)))
            let text = Text(label)
                .font(.system(size: 8.5 * s, weight: .black, design: .rounded))
                .foregroundColor(light)
            context.draw(text, at: CGPoint(x: plate.midX, y: plate.midY))
        }
    }
}
