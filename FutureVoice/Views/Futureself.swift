import SwiftUI

/// The six palettes the Futureself surface can wear. Raw value is what the
/// shader receives and what `@AppStorage("futureselfTheme")` persists, so
/// the order here is frozen — append new themes, never reorder.
enum FutureselfTheme: Int, CaseIterable, Identifiable {
    case blue = 0, mono, emerald, amber, coral, aqua

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .blue:    return "Blue"
        case .mono:    return "Mono"
        case .emerald: return "Emerald"
        case .amber:   return "Amber"
        case .coral:   return "Coral"
        case .aqua:    return "Aqua"
        }
    }

    /// Representative SwiftUI color for UI chrome that must match the shader
    /// surface — the call button's outline, the orbiting highlight. Each is
    /// the palette's vivid step (kPalette[theme][*][3] in Futureself.metal);
    /// keep in sync if the shader palettes change.
    var tint: Color {
        switch self {
        case .blue:    return Color(red: 0.040, green: 0.360, blue: 0.960)
        // Mono's accent leans near-black so tinted chrome reads as ink, not a
        // washed-out gray. Adaptive: deep charcoal in light, bright gray in
        // dark — a single fixed near-black would vanish on a dark background.
        case .mono:    return Color(UIColor { $0.userInterfaceStyle == .dark
                                        ? UIColor(white: 0.86, alpha: 1)
                                        : UIColor(white: 0.16, alpha: 1) })
        case .emerald: return Color(red: 0.050, green: 0.640, blue: 0.420)
        case .amber:   return Color(red: 0.960, green: 0.560, blue: 0.050)
        case .coral:   return Color(red: 0.950, green: 0.230, blue: 0.320)
        case .aqua:    return Color(red: 0.040, green: 0.640, blue: 0.760)
        }
    }
}

/// Futureself — the call button's living surface (Shaders/Futureself.metal):
/// a quantized pixel grid in the app icon's mosaic identity. Cells twinkle
/// when idle, ignite bottom-up with the user's voice while listening, sweep
/// with a scanner while thinking, and bloom center-out with playback while
/// the fluent self speaks. Always present — only cell states change, so
/// nothing pops in or out with state transitions. Pure visual; no
/// hit-testing, no implicit animations.
struct Futureself: View {
    enum Mode: Float {
        case idle = 0, listening = 1, thinking = 2, speaking = 3
    }

    var mode: Mode
    /// 0…1 target voice energy — mic RMS or playback RMS by state. Arrives in
    /// coarse steps at the audio-buffer rate; the smoother below interpolates
    /// it per FRAME so the surface glides instead of stepping.
    var level: Float
    /// Explicit palette override (the settings previews). nil — the live
    /// surfaces everywhere — follows the user's chosen theme.
    var theme: FutureselfTheme? = nil
    /// When set, the shader sees THIS height instead of the real one, pinning
    /// the cell size (height/5) no matter how big the rendered frame is. The
    /// Talk home's ring interior passes the call pill's 64 so its big circle
    /// keeps the pill's fine pixel grid — and morphing between the two never
    /// changes the pixel scale. nil = stock behavior (5 rows fill the frame).
    var virtualHeight: CGFloat? = nil

    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue
    @Environment(\.colorScheme) private var colorScheme
    /// Reference type on purpose: mutating it never invalidates the view —
    /// TimelineView already redraws every frame, the smoother just advances.
    @State private var smoother = LevelSmoother()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                // Modulo keeps the float precise enough for the shader's
                // sin() phases; the wrap every ~17 min is imperceptible.
                let t = Float(now.truncatingRemainder(dividingBy: 1000))
                let display = smoother.step(toward: level, at: now)
                let resolved = theme ?? FutureselfTheme(rawValue: storedTheme) ?? .blue
                // The size the shader derives its cell grid from — real by
                // default; the virtualHeight lie keeps width/height ratio so
                // the shader's normalized math stays consistent.
                let realH = Float(geo.size.height)
                let shaderH = virtualHeight.map { Float($0) } ?? realH
                let shaderW = Float(geo.size.width) * (shaderH / max(realH, 1))
                // Fill color is ignored — the shader owns the palette and
                // paints the full surface, theme-aware via the dark flag.
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.futureself(
                        .float2(shaderW, shaderH),
                        .float(t),
                        .float(display),
                        .float(mode.rawValue),
                        .float(colorScheme == .dark ? 1 : 0),
                        .float(Float(resolved.rawValue))
                    ))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Settings picker for the Futureself theme: a 3×2 grid of live mini
/// surfaces. Tapping a theme selects it and fires a center-out voice bloom
/// on that preview, so the choice is felt, not just seen.
struct FutureselfThemePicker: View {
    @AppStorage("futureselfTheme") private var stored = FutureselfTheme.blue.rawValue
    /// Raw value of the theme currently playing its tap bloom, if any.
    @State private var bursting: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(FutureselfTheme.allCases) { theme in
                let selected = stored == theme.rawValue
                Button { select(theme) } label: {
                    VStack(spacing: 6) {
                        // Resting previews idle at a mid level so every
                        // palette actually shows its colors; the tap bloom
                        // then drives to full.
                        Futureself(mode: .speaking,
                                   level: bursting == theme.rawValue ? 1 : 0.32,
                                   theme: theme)
                            .frame(height: 44)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(
                                selected ? Color.accentColor : Color(.separator).opacity(0.5),
                                lineWidth: selected ? 2 : 0.5))
                        Text(theme.label)
                            .font(.caption2)
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                    // The swatch is a shader with `.allowsHitTesting(false)`,
                    // so without this the tappable area shrinks to the thin
                    // capsule border + the label text. Make the whole cell tap.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(theme.label) theme"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func select(_ theme: FutureselfTheme) {
        stored = theme.rawValue
        // The study widgets wear the same theme — repaint them at once.
        StudyWidgetRefresher.refresh()
        // Drive the preview like a real utterance: level jumps to 1 (fast
        // attack blooms the cells center-out), then releases after a beat —
        // the smoother's slow decay handles the exhale.
        bursting = theme.rawValue
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if bursting == theme.rawValue { bursting = nil }
        }
    }
}

/// Frame-rate exponential smoothing with asymmetric time constants: a fast
/// attack (~60 ms) so the surface leaps with a syllable, a slow release
/// (~350 ms) so it exhales instead of flickering out.
private final class LevelSmoother {
    private var value: Float = 0
    private var lastTime: Double = 0

    func step(toward target: Float, at time: Double) -> Float {
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(0.1, max(0.0, time - lastTime))
        lastTime = time
        let tau = target > value ? 0.06 : 0.35
        let k = Float(1 - exp(-dt / tau))
        value += (target - value) * k
        return value
    }
}
