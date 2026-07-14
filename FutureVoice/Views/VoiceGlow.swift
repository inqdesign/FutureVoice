import SwiftUI

/// Ambient bottom glow for the Talk screen (Shaders/VoiceGlow.metal): a soft
/// aurora anchored to the bottom edge that breathes when idle, lifts with the
/// user's voice while listening, shimmers while thinking, and rides playback
/// while the fluent self speaks. Always present — only its brightness changes,
/// so nothing pops in or out with state transitions. Pure visual; no
/// hit-testing, no implicit animations.
struct VoiceGlow: View {
    enum Mode: Float {
        case idle = 0, listening = 1, thinking = 2, speaking = 3
    }

    var mode: Mode
    /// 0…1 target voice energy — mic RMS or playback RMS by state. Arrives in
    /// coarse steps at the audio-buffer rate; the smoother below interpolates
    /// it per FRAME so the glow glides instead of stepping.
    var level: Float

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
                // Fill color is ignored — the shader owns the palette and
                // paints the full surface, theme-aware via the dark flag.
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.voiceGlow(
                        .float2(Float(geo.size.width), Float(geo.size.height)),
                        .float(t),
                        .float(display),
                        .float(mode.rawValue),
                        .float(colorScheme == .dark ? 1 : 0)
                    ))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Frame-rate exponential smoothing with asymmetric time constants: a fast
/// attack (~60 ms) so the glow leaps with a syllable, a slow release
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
