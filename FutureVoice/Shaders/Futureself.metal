#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Talk mic pill's living surface. Paints the WHOLE pill (alpha 1):
// a theme-aware base with an aurora band near the bottom that glows in
// silence and blooms with the voice.
//
//   light theme: near-white base, periwinkle → indigo bloom, deeper blue rim
//   dark theme:  deep-navy base, indigo → periwinkle bloom (reference look)
//
// mode: 0 idle · 1 listening · 2 thinking · 3 speaking
// level: 0…1 smoothed voice energy (mic RMS while listening, playback RMS
//        while speaking)
// dark: 1 when the app is in dark mode, else 0
[[ stitchable ]] half4 voiceGlow(float2 position, half4 color, float2 size,
                                 float time, float level, float mode, float dark) {
    float2 uv = position / size;             // 0…1, y grows downward
    float x = uv.x, y = uv.y;

    // Luminous horizon band in the pill's lower third.
    float band = exp(-pow((y - 0.78) * 4.5, 2.0));

    // Two blobs riding the band (right of center bright, left dim) keep the
    // horizon asymmetric and slowly alive.
    float2 c1 = float2(0.58 + 0.10 * sin(time * 0.33), 0.80);
    float2 c2 = float2(0.26 + 0.08 * sin(time * 0.21 + 2.1), 0.84);
    float2 d1 = (uv - c1) * float2(1.7, 3.6);
    float2 d2 = (uv - c2) * float2(2.4, 4.2);
    float blob = exp(-dot(d1, d1)) * 0.65 + exp(-dot(d2, d2)) * 0.3;

    // Thinking: a slow shimmer sweeping along the horizon.
    float horizon = 1.0;
    if (mode == 2.0) {
        horizon = 0.75 + 0.25 * sin(x * 5.0 - time * 1.6);
    }

    // Visibly glowing even in silence; the voice blooms on top.
    float breathe = 0.05 * sin(time * 1.1);
    float energy = 0.60 + breathe + level * 0.55;
    if (mode == 0.0) { energy *= 0.70; }     // idle: dimmer, still alive

    float intensity = (band * 0.5 + blob) * horizon * energy;
    // Ease the brightness back gently at the very bottom edge.
    intensity *= 1.0 - 0.45 * smoothstep(0.92, 1.0, y);
    // Compress so even a shout never blows out.
    float t = clamp(intensity, 0.0, 1.0) * 0.80;

    // Cooler blue pooling in the bottom corners (both themes) — cast stays
    // in the BLUE family, never violet.
    float corner = smoothstep(0.35, 1.0, abs(x - 0.5) * 2.0)
                 * smoothstep(0.55, 1.0, y);
    // Saturated (not dark) rim right at the bottom edge grounds the pill
    // without turning it muddy.
    float rim = smoothstep(0.90, 1.0, y);

    half3 col;
    if (dark == 1.0) {
        half3 base = half3(0.03, 0.05, 0.14);     // deep navy
        half3 blue = half3(0.16, 0.38, 0.92);     // vivid blue
        half3 sky  = half3(0.55, 0.73, 1.00);
        col = mix(base, blue, half(smoothstep(0.04, 0.45, t)));
        col = mix(col,  sky,  half(smoothstep(0.40, 0.85, t)));
        col = mix(col,  half3(0.20, 0.45, 0.98), half(corner * 0.25));
        col = mix(col,  half3(0.10, 0.22, 0.55), half(rim * 0.40));
    } else {
        half3 base = half3(0.97, 0.98, 1.00);     // airy near-white
        half3 sky  = half3(0.55, 0.73, 1.00);
        half3 blue = half3(0.18, 0.47, 0.98);     // vivid blue, no red lean
        col = mix(base, sky,  half(smoothstep(0.04, 0.50, t)));
        col = mix(col,  blue, half(smoothstep(0.50, 0.95, t)));
        col = mix(col,  half3(0.30, 0.55, 1.00), half(corner * 0.18));
        col = mix(col,  half3(0.16, 0.42, 0.96), half(rim * 0.35));
    }
    return half4(col, 1.0);
}
