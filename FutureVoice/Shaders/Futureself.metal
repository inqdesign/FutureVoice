#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Futureself — the call button's living surface: a quantized PIXEL GRID in
// the app icon's mosaic identity. Cells breathe individually in silence and
// ignite with the voice; color is snapped to a 5-step palette (no gradients
// inside a cell) so the surface always reads as pixels, never as a blur.
// A capsule-SDF inner shadow recesses the whole surface so it has depth
// instead of sitting flat, and animated film grain textures everything.
//
//   listening: cells bloom upward from the bottom edge with mic energy
//   speaking:  cells bloom outward from the center with playback energy
//   thinking:  a scanner column sweeps the grid
//   idle:      dim ambient twinkle, still alive
//
// mode: 0 idle · 1 listening · 2 thinking · 3 speaking
// level: 0…1 smoothed voice energy
// dark: 1 when the app is in dark mode, else 0
// theme: FutureselfTheme.rawValue — selects one of the palettes below

// 5-step ramps (base → hottest), one pair (dark, light) per theme. Indexed
// [theme][dark ? 0 : 1][step]. Must stay in sync with FutureselfTheme.
constant half3 kPalette[6][2][5] = {
    { // 0 blue
        { half3(0.020, 0.028, 0.060), half3(0.080, 0.095, 0.130),
          half3(0.020, 0.130, 0.400), half3(0.040, 0.360, 0.960),
          half3(0.480, 0.720, 1.000) },
        { half3(0.965, 0.972, 1.000), half3(0.900, 0.922, 0.970),
          half3(0.720, 0.830, 1.000), half3(0.450, 0.680, 1.000),
          half3(0.030, 0.340, 0.950) },
    },
    { // 1 mono
        { half3(0.020, 0.020, 0.022), half3(0.090, 0.090, 0.095),
          half3(0.220, 0.220, 0.230), half3(0.550, 0.550, 0.560),
          half3(0.960, 0.960, 0.970) },
        { half3(0.970, 0.970, 0.972), half3(0.905, 0.905, 0.910),
          half3(0.760, 0.760, 0.770), half3(0.420, 0.420, 0.430),
          half3(0.070, 0.070, 0.080) },
    },
    { // 2 emerald
        { half3(0.015, 0.030, 0.025), half3(0.075, 0.100, 0.090),
          half3(0.020, 0.230, 0.160), half3(0.050, 0.640, 0.420),
          half3(0.560, 0.940, 0.760) },
        { half3(0.960, 0.980, 0.970), half3(0.885, 0.925, 0.905),
          half3(0.700, 0.900, 0.800), half3(0.350, 0.780, 0.560),
          half3(0.020, 0.480, 0.300) },
    },
    { // 3 amber
        { half3(0.040, 0.028, 0.015), half3(0.110, 0.095, 0.070),
          half3(0.400, 0.220, 0.020), half3(0.960, 0.560, 0.050),
          half3(1.000, 0.830, 0.480) },
        { half3(1.000, 0.975, 0.950), half3(0.945, 0.910, 0.860),
          half3(1.000, 0.850, 0.620), half3(1.000, 0.690, 0.330),
          half3(0.900, 0.450, 0.020) },
    },
    { // 4 coral
        { half3(0.040, 0.015, 0.030), half3(0.110, 0.070, 0.085),
          half3(0.380, 0.050, 0.140), half3(0.950, 0.230, 0.320),
          half3(1.000, 0.640, 0.660) },
        { half3(1.000, 0.960, 0.960), half3(0.950, 0.890, 0.890),
          half3(1.000, 0.760, 0.760), half3(0.990, 0.500, 0.520),
          half3(0.870, 0.120, 0.230) },
    },
    { // 5 aqua
        { half3(0.012, 0.030, 0.036), half3(0.070, 0.100, 0.108),
          half3(0.015, 0.230, 0.280), half3(0.040, 0.640, 0.760),
          half3(0.560, 0.940, 1.000) },
        { half3(0.955, 0.980, 0.985), half3(0.880, 0.925, 0.930),
          half3(0.680, 0.890, 0.930), half3(0.300, 0.760, 0.850),
          half3(0.020, 0.480, 0.590) },
    },
};

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

[[ stitchable ]] half4 futureself(float2 position, half4 color, float2 size,
                                  float time, float level, float mode,
                                  float dark, float theme) {
    // 5 rows of square cells; column count follows the surface width, so
    // the same shader stays icon-scaled on the pill and the home circle.
    float cellPt = size.y / 5.0;
    float2 cell = floor(position / cellPt);
    float2 cuv = (cell + 0.5) * cellPt / size;   // cell center, 0…1, y down

    float r1 = hash21(cell + 0.13);
    float r2 = hash21(cell + 7.77);
    float r3 = hash21(cell + 23.19);

    // Ambient life: each cell breathes on its own slow phase so the grid
    // shimmers gently in silence instead of sitting frozen.
    float v = 0.16 + 0.14 * sin(time * (0.35 + 0.55 * r2) + r3 * 6.2831);

    // Ignition order — which cells light first as the voice gets louder.
    // Randomness is blended with a directional bias (bottom-up while
    // listening, center-out while speaking) so the bloom grows coherently
    // but never reads as clean rows.
    float bias = (mode == 3.0) ? abs(cuv.x - 0.5) * 2.0 : (1.0 - cuv.y);
    float order = clamp(mix(r1, bias, 0.45), 0.0, 1.0);
    float drive = clamp(level, 0.0, 1.0) * 1.15;
    float ignite = smoothstep(order, order + 0.22, drive);
    v += ignite * (0.55 + 0.30 * r2);
    // Lit cells flicker faintly on personal phases — the mass sparkles.
    v += ignite * 0.08 * sin(time * (2.0 + 3.0 * r1) + r2 * 6.2831);

    if (mode == 2.0) {
        // Thinking: no voice to ride, so a scanner column ping-pongs across.
        float sx = 0.5 + 0.46 * sin(time * 1.4);
        float sweep = exp(-pow((cuv.x - sx) * 3.5, 2.0));
        v += sweep * (0.45 + 0.35 * r1);
    }
    if (mode == 0.0) { v *= 0.7; }               // idle: dimmer, still alive

    // Snap to the 5-step palette. Per-cell dither on the threshold so
    // neighbors never snap in unison — the grid mutates cell by cell.
    int step5 = int(clamp(floor(v * 4.0 + (r3 - 0.5) * 0.9 + 0.5), 0.0, 4.0));
    int ti = clamp(int(theme), 0, 5);
    int di = (dark == 1.0) ? 0 : 1;
    half3 p0 = kPalette[ti][di][0];
    half3 col = kPalette[ti][di][step5];

    // Hairline gap between cells, antialiased, in the base color — this is
    // what keeps the surface reading as a mosaic instead of colored noise.
    float2 f = position - cell * cellPt;
    float gapDist = min(min(f.x, f.y), min(cellPt - f.x, cellPt - f.y));
    col = mix(p0, col, half(smoothstep(0.35, 1.1, gapDist)));

    // Inner shadow — the surface reads as recessed, not flat. Capsule SDF
    // (a circle when w == h) matches both clip shapes this view lives in,
    // so the shading hugs the real edge without knowing the clip. Shadow
    // pools along the top edge (light from above); a faint rim light along
    // the bottom edge lifts the lower lip.
    float rad = size.y * 0.5;
    float2 pc = position - size * 0.5;
    float2 ax = float2(max(size.x * 0.5 - rad, 0.0), 0.0);
    float inset = rad - length(pc - clamp(pc, -ax, ax));
    float rim = exp(-max(inset, 0.0) / 7.0);         // 1 at edge → 0 inward
    float topW = clamp(0.5 - pc.y / size.y, 0.0, 1.0);
    float shade = rim * (0.14 + 0.34 * topW);
    // Light palettes show the darkening far more than dark ones, so the
    // light-mode strength runs well BELOW dark's — a hint of recess, not a
    // dirty top edge.
    col *= half(1.0 - shade * (dark == 1.0 ? 0.85 : 0.45));
    col += half3(half(rim * (1.0 - topW) * (dark == 1.0 ? 0.06 : 0.05)));

    // Film grain over everything — a whisper of texture, not a filter. Fine
    // per-point noise reshuffled at a filmic ~18fps (not every frame, so it
    // flickers organically instead of buzzing). The frame index is wrapped
    // to keep hash inputs small — large offsets degrade float precision and
    // flatten the noise. Gentler in light mode where grain reads as dirt.
    float tq = fmod(floor(time * 18.0), 64.0);
    float g = hash21(position * 1.7 + tq * float2(13.7, 91.3)) - 0.5;
    col += half3(half(g * (dark == 1.0 ? 0.06 : 0.04)));

    return half4(col, 1.0);
}
