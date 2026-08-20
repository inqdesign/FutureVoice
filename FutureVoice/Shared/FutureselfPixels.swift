import SwiftUI

/// Futureself's 5-step ramps, lifted from `Shaders/Futureself.metal`
/// (`kPalette`) — indexed [theme][dark ? 0 : 1][step], base → hottest. The
/// shader owns the live surface; this table is what lets a surface that CANNOT
/// run Metal (a widget) paint the same mosaic. Keep in sync with the shader and
/// with `FutureselfTheme`.
enum FutureselfRamp {
    typealias RGB = (Double, Double, Double)

    static let table: [[[RGB]]] = [
        [ // 0 blue
            [(0.020, 0.028, 0.060), (0.080, 0.095, 0.130), (0.020, 0.130, 0.400),
             (0.040, 0.360, 0.960), (0.480, 0.720, 1.000)],
            [(0.965, 0.972, 1.000), (0.900, 0.922, 0.970), (0.720, 0.830, 1.000),
             (0.450, 0.680, 1.000), (0.030, 0.340, 0.950)],
        ],
        [ // 1 mono
            [(0.020, 0.020, 0.022), (0.090, 0.090, 0.095), (0.220, 0.220, 0.230),
             (0.550, 0.550, 0.560), (0.960, 0.960, 0.970)],
            [(0.970, 0.970, 0.972), (0.905, 0.905, 0.910), (0.760, 0.760, 0.770),
             (0.420, 0.420, 0.430), (0.070, 0.070, 0.080)],
        ],
        [ // 2 emerald
            [(0.015, 0.030, 0.025), (0.075, 0.100, 0.090), (0.020, 0.230, 0.160),
             (0.050, 0.640, 0.420), (0.560, 0.940, 0.760)],
            [(0.960, 0.980, 0.970), (0.885, 0.925, 0.905), (0.700, 0.900, 0.800),
             (0.350, 0.780, 0.560), (0.020, 0.480, 0.300)],
        ],
        [ // 3 amber
            [(0.040, 0.028, 0.015), (0.110, 0.095, 0.070), (0.400, 0.220, 0.020),
             (0.960, 0.560, 0.050), (1.000, 0.830, 0.480)],
            [(1.000, 0.975, 0.950), (0.945, 0.910, 0.860), (1.000, 0.850, 0.620),
             (1.000, 0.690, 0.330), (0.900, 0.450, 0.020)],
        ],
        [ // 4 coral
            [(0.040, 0.015, 0.030), (0.110, 0.070, 0.085), (0.380, 0.050, 0.140),
             (0.950, 0.230, 0.320), (1.000, 0.640, 0.660)],
            [(1.000, 0.960, 0.960), (0.950, 0.890, 0.890), (1.000, 0.760, 0.760),
             (0.990, 0.500, 0.520), (0.870, 0.120, 0.230)],
        ],
        [ // 5 aqua
            [(0.012, 0.030, 0.036), (0.070, 0.100, 0.108), (0.015, 0.230, 0.280),
             (0.040, 0.640, 0.760), (0.560, 0.940, 1.000)],
            [(0.955, 0.980, 0.985), (0.880, 0.925, 0.930), (0.680, 0.890, 0.930),
             (0.300, 0.760, 0.850), (0.020, 0.480, 0.590)],
        ],
    ]

    static func rgb(theme: Int, dark: Bool, step: Int) -> RGB {
        let t = min(max(theme, 0), table.count - 1)
        return table[t][dark ? 0 : 1][min(max(step, 0), 4)]
    }

    static func color(theme: Int, dark: Bool, step: Int) -> Color {
        let v = rgb(theme: theme, dark: dark, step: step)
        return Color(red: v.0, green: v.1, blue: v.2)
    }
}

/// A STATIC Futureself surface, drawn on the CPU.
///
/// The live surface is a Metal shader (`Views/Futureself.swift`), and WidgetKit
/// renders out of process where that shader never runs — which is why the Free
/// Talk widget wore a plain SF Symbol. This is a faithful port of the shader's
/// per-cell math at one frozen instant: the same hash-driven cell life, the
/// same ignition ordering, the same 5-step palette snap with per-cell dither,
/// the same hairline mosaic gap, and the same capsule-SDF recess. Only the film
/// grain is dropped — it's per-pixel noise nobody can see in a still.
///
/// **Cell size is FIXED, not derived from the frame** (the shader's 5-rows rule
/// is what `virtualHeight` overrides in the app for exactly this reason): a
/// bigger surface gets MORE cells, not bigger ones, so the circle and the pill
/// wear the same pixel scale.
///
/// Clip it — circle or capsule, never a bare rectangle and never the background.
struct FutureselfPixels: View {
    /// 0 idle · 1 listening · 2 thinking · 3 speaking — the shader's modes.
    enum Mode: Double { case idle = 0, listening = 1, thinking = 2, speaking = 3 }

    var theme: Int = 0
    var mode: Mode = .speaking
    /// 0…1 frozen voice energy. Idle runs at 0.7× brightness in the shader, so
    /// a still needs some drive or the surface reads as a flat dark disc.
    var level: Double = 0.36
    /// The instant of the shader's clock this still is taken at. Vary it to get
    /// a different arrangement of the same surface.
    var time: Double = 3.2
    /// Cell edge in points. 12.8 = the app's pill (64 / 5 rows), the size every
    /// live surface is pinned to.
    var cell: CGFloat = 12.8
    /// Where this surface sits inside the lattice it shares with something else
    /// — the widget's background grid. Without it the surface starts its own
    /// cells at its own top-left corner and the two grids beat against each
    /// other; with it, a lit cell IS a cell of the graph paper underneath.
    var phase: CGSize = .zero
    /// Fill the gaps between cells with the palette's base colour. False leaves
    /// them clear, so whatever is behind the surface — the background grid's
    /// own lines — runs straight through it.
    var opaqueGaps: Bool = true
    /// How reluctantly a cell takes COLOUR. The ramp's first two steps are
    /// neutral darks and the last three carry the hue, so raising this pushes
    /// the middle of the distribution down: the mosaic keeps every one of its
    /// cells, but fewer of them are coloured. 1 = the shader's own curve.
    var colourFalloff: Double = 1
    /// Ceiling on the ramp step, 0…4. Dropping it to 3 withholds the lightest,
    /// hottest tone — the one that reads as a sparkle in a still.
    var maxStep: Int = 4
    var dark: Bool = true

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            guard size.width > 0, size.height > 0 else { return }
            if opaqueGaps {
                let base = FutureselfRamp.rgb(theme: theme, dark: dark, step: 0)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: base.0, green: base.1, blue: base.2)))
            }

            // The lattice runs from the shared origin, not this view's corner,
            // so the first column may start off the left edge.
            let x0 = -phase.width.truncatingRemainder(dividingBy: cell)
            let y0 = -phase.height.truncatingRemainder(dividingBy: cell)
            let cols = Int(ceil((size.width - x0) / cell))
            let rows = Int(ceil((size.height - y0) / cell))
            // The hairline gap between cells — this is what keeps the surface
            // reading as a mosaic instead of colored noise.
            let gap: CGFloat = 1

            for cy in 0..<rows {
                for cx in 0..<cols {
                    let origin = CGPoint(x: x0 + CGFloat(cx) * cell, y: y0 + CGFloat(cy) * cell)
                    let center = CGPoint(x: origin.x + cell / 2, y: origin.y + cell / 2)
                    let c = shade(cx: cx, cy: cy, center: center, size: size)
                    let rect = CGRect(x: origin.x + gap / 2, y: origin.y + gap / 2,
                                      width: cell - gap, height: cell - gap)
                    ctx.fill(Path(rect), with: .color(c))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - The shader, on the CPU

    private func shade(cx: Int, cy: Int, center: CGPoint, size: CGSize) -> Color {
        let cellV = SIMD2<Double>(Double(cx), Double(cy))
        let cuv = SIMD2<Double>(center.x / size.width, center.y / size.height)

        let r1 = hash21(cellV + 0.13)
        let r2 = hash21(cellV + 7.77)
        let r3 = hash21(cellV + 23.19)

        // Ambient life — every cell breathes on its own slow phase.
        var v = 0.16 + 0.14 * sin(time * (0.35 + 0.55 * r2) + r3 * 2 * .pi)

        // Ignition order: random, blended with a directional bias so the bloom
        // grows coherently (center-out speaking, bottom-up listening).
        let bias = mode == .speaking ? abs(cuv.x - 0.5) * 2 : (1 - cuv.y)
        let order = min(max(r1 + (bias - r1) * 0.45, 0), 1)
        let drive = min(max(level, 0), 1) * 1.15
        let ignite = smoothstep(order, order + 0.22, drive)
        v += ignite * (0.55 + 0.30 * r2)
        v += ignite * 0.08 * sin(time * (2 + 3 * r1) + r2 * 2 * .pi)

        if mode == .thinking {
            let sx = 0.5 + 0.46 * sin(time * 1.4)
            v += exp(-pow((cuv.x - sx) * 3.5, 2)) * (0.45 + 0.35 * r1)
        }
        if mode == .idle { v *= 0.7 }

        // Snap to the 5 steps, dithered per cell so neighbours never snap in
        // unison — the grid mutates cell by cell.
        if colourFalloff != 1 { v = pow(min(max(v, 0), 1), colourFalloff) }
        let top = Double(min(max(maxStep, 0), 4))
        let step = Int(min(max((v * 4 + (r3 - 0.5) * 0.9 + 0.5).rounded(.down), 0), top))
        var (r, g, b) = FutureselfRamp.rgb(theme: theme, dark: dark, step: step)

        // Capsule-SDF recess — shadow pools along the top edge (light from
        // above), a faint rim light lifts the bottom lip. Evaluated at the cell
        // centre, so the recess is quantized like everything else here.
        let rad = size.height / 2
        let pc = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let axx = max(size.width / 2 - rad, 0)
        let qx = min(max(pc.x, -axx), axx)
        let inset = rad - hypot(pc.x - qx, pc.y)
        let rim = exp(-max(inset, 0) / 7)
        let topW = min(max(0.5 - pc.y / size.height, 0), 1)
        let shadeAmount = rim * (0.14 + 0.34 * topW)
        let k = 1 - shadeAmount * (dark ? 0.85 : 0.45)
        let lift = rim * (1 - topW) * (dark ? 0.06 : 0.05)
        r = r * k + lift; g = g * k + lift; b = b * k + lift

        return Color(red: min(r, 1), green: min(g, 1), blue: min(b, 1))
    }

    private func hash21(_ p: SIMD2<Double>) -> Double {
        var q = fract(p * SIMD2(123.34, 456.21))
        let dot = q.x * (q.x + 45.32) + q.y * (q.y + 45.32)
        q += SIMD2(dot, dot)
        return fract(q.x * q.y)
    }

    private func fract(_ v: Double) -> Double { v - v.rounded(.down) }
    private func fract(_ v: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(fract(v.x), fract(v.y))
    }

    private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        guard e1 > e0 else { return x < e0 ? 0 : 1 }
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
