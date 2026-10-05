import SwiftUI

// The pieces of the Welcome film (WelcomeView): the backdrop, the caption
// that writes itself in, the quiet feature line under it, and the fluent
// self's orb. Nothing here knows the script.

/// A warm cream ground with the app's blue coming down from the top centre
/// like a sky — deepest at the top edge, paling through the same blues into
/// the cream — and film grain over everything. One size for the whole film:
/// a light that grew as the story turned was tried and rejected, as were a
/// dark ground and a multicolour light. It only drifts, slowly.
struct StoryBackdrop: View {
    var still: Bool = false

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 10_000)
                canvas(t: t)
            }
            FilmGrain()
        }
        .accessibilityHidden(true)
    }

    static let cream = (0.975, 0.955, 0.915)

    /// The sky from its top to where it meets the cream: the app's blues,
    /// ending in the ground's own colour. Sampled along a smooth curve rather
    /// than a few straight segments — the corner where two segments meet
    /// reads as a pale line across the screen.
    private static let skyStops = smoothStops([
        (0.06, 0.26, 0.90, 1), (0.14, 0.38, 0.96, 1), (0.40, 0.60, 1.00, 1),
        (0.72, 0.82, 1.00, 1), (cream.0, cream.1, cream.2, 0),
    ])

    /// Night at the very top, fading into the sky the same smooth way.
    private static let nightStops = smoothStops([
        (0.015, 0.03, 0.10, 1), (0.03, 0.10, 0.36, 0.6), (0.05, 0.20, 0.70, 0),
    ])

    /// Evenly spaced key colours through a Catmull-Rom curve, sampled finely:
    /// no kinks anywhere, so no Mach bands.
    private static func smoothStops(_ keys: [(Double, Double, Double, Double)],
                                    samples: Int = 40) -> [Gradient.Stop] {
        func at(_ i: Int) -> (Double, Double, Double, Double) { keys[max(0, min(keys.count - 1, i))] }
        func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
            let v = 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                           + (3 * b - a - 3 * c + d) * t * t * t)
            return min(1, max(0, v))
        }
        let segs = Double(keys.count - 1)
        return (0...samples).map { n in
            let x = Double(n) / Double(samples)
            let f = x * segs
            let i = min(Int(f), keys.count - 2)
            let t = f - Double(i)
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let c = Color(red: cr(p0.0, p1.0, p2.0, p3.0, t), green: cr(p0.1, p1.1, p2.1, p3.1, t),
                          blue: cr(p0.2, p1.2, p2.2, p3.2, t))
                .opacity(cr(p0.3, p1.3, p2.3, p3.3, t))
            return .init(color: c, location: x)
        }
    }

    private func canvas(t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(rgb: Self.cream)
                // The sky: a wide ellipse centred above the top edge, so
                // only its soft lower half comes down into the screen.
                let r = h * 0.62
                Ellipse()
                    .fill(RadialGradient(stops: Self.skyStops, center: .center,
                                         startRadius: 0, endRadius: r))
                    .frame(width: r * 2.4, height: r * 2)
                    .position(x: w * (0.5 + 0.04 * sin(t * 0.05)),
                              y: h * (-0.16 + 0.02 * cos(t * 0.04)))
                // Night at the very top: the sky deepens to near-black, so
                // the notch and the status bar sink into it.
                LinearGradient(stops: Self.nightStops,
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.26))
                // A little warmth gathering at the bottom, under the buttons.
                LinearGradient(colors: [.clear, Color(rgb: (0.96, 0.88, 0.78)).opacity(0.7)],
                               startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
            }
            .drawingGroup()
        }
    }
}

/// Static film grain: a small tile of random grey speckle, generated once
/// and repeated over the whole screen at low opacity.
private struct FilmGrain: View {
    private static let tile: UIImage = {
        let side = 160
        // Plain grey, no alpha: under `.overlay`, mid-grey changes nothing
        // and each pixel's distance from it lightens or darkens the ground.
        var bytes = [UInt8](repeating: 0, count: side * side)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                            bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(0.18)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}

private extension Color {
    init(rgb c: (Double, Double, Double)) { self.init(red: c.0, green: c.1, blue: c.2) }
}

extension Color {
    /// The Welcome film's text colour on its cream ground: a deep blue-black,
    /// softer than pure black against the cream.
    static let storyInk = Color(red: 0.11, green: 0.13, blue: 0.20)
}

/// A caption that writes itself in, word by word: each word rises a few
/// points out of a soft blur. A language without spaces between words
/// (Japanese, Chinese) comes in a character at a time instead. `\n` breaks
/// the line; a line too long for the width wraps, centred.
struct RevealText: View {
    let text: String
    var still: Bool = false
    var font: Font = .system(size: 25, weight: .semibold, design: .rounded)

    @State private var shown = false

    private var lines: [[String]] {
        text.components(separatedBy: "\n").map { line in
            line.contains(" ")
                ? line.split(separator: " ").map(String.init)
                : line.map(String.init)
        }
    }

    var body: some View {
        let lines = self.lines
        let total = lines.reduce(0) { $0 + $1.count }
        // The whole line arrives in about a second and a half however long it is.
        let stagger = min(0.18, 2.4 / Double(max(total, 1)))
        let spaced = text.contains(" ")
        VStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { li, tokens in
                let before = lines[..<li].reduce(0) { $0 + $1.count }
                CenteredFlow(spacing: spaced ? 7 : 0, lineSpacing: 6) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { ti, token in
                        Text(token)
                            .font(font)
                            .foregroundStyle(Color.storyInk)
                            .opacity(shown ? 1 : 0)
                            .blur(radius: shown || still ? 0 : 9)
                            .offset(y: shown || still ? 0 : 7)
                            .animation(.easeOut(duration: still ? 0.6 : 1.3)
                                .delay(still ? 0 : Double(before + ti) * stagger),
                                       value: shown)
                    }
                }
                // The second line is the softer half of the thought.
                .opacity(li == 0 || lines.count == 1 ? 1 : 0.78)
            }
        }
        .multilineTextAlignment(.center)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
    }
}

/// Lays its children out in rows, wrapping at the width, each row centred.
struct CenteredFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let added = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if added > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row(indices: [i], width: size.width, height: size.height)
            } else {
                row.indices.append(i)
                row.width = added
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// What the app does, said quietly under a line: one symbol, a few words,
/// arriving after the caption has.
struct Glimpse: View {
    let symbol: String
    let label: String
    var delay: Double = 2.8
    var still: Bool = false

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.storyInk.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.storyInk.opacity(0.10), lineWidth: 0.5))
            .modifier(Arrive(delay: delay, still: still))
    }
}

/// Fades a view up into place after a delay, once, when it appears.
struct Arrive: ViewModifier {
    var delay: Double
    var still: Bool = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || still ? 0 : 8)
            .animation(.easeOut(duration: 0.8).delay(still ? 0 : delay), value: shown)
            .onAppear { shown = true }
    }
}

/// The fluent self on the Welcome film: the call button's own surface. It
/// starts as a circle under the captions and, at the end, stretches into the
/// Get started button. On every new beat it speaks for about as long as the
/// words take to arrive, then rests — so when the voice-over lands, it
/// already moves with it. The pixel grid is pinned to the call pill's height
/// (`virtualHeight`), so the cells keep their size while the shape changes.
struct FutureselfDoor: View {
    var open: Bool
    var beat: Int
    var still: Bool = false
    var action: () -> Void

    @State private var mode: Futureself.Mode = .idle
    @State private var level: Float = 0

    private static let side: CGFloat = 76
    private static let buttonHeight: CGFloat = 58

    var body: some View {
        GeometryReader { geo in
            let w = open ? geo.size.width : Self.side
            let h = open ? Self.buttonHeight : Self.side
            Button(action: action) {
                Futureself(mode: mode, level: level, theme: .blue, virtualHeight: 64)
                    .environment(\.colorScheme, .light)
                    .frame(width: w, height: h)
                    // As it opens, the surface fills with the app's blue and
                    // becomes an ordinary primary button.
                    .overlay {
                        Capsule()
                            .fill(FutureselfTheme.blue.tint)
                            .opacity(open ? 1 : 0)
                            .animation(.easeInOut(duration: 0.8).delay(open ? 0.3 : 0), value: open)
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.storyInk.opacity(open ? 0 : 0.10), lineWidth: 0.5))
                    .overlay {
                        Text("Get started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .opacity(open ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(open ? 0.7 : 0), value: open)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!open)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(!open)
        }
        .task(id: beat) {
            guard !still else { return }
            mode = .speaking
            // A speaking voice's energy: uneven syllables, not a sine.
            let end = Date().addingTimeInterval(2.6)
            while Date() < end && !Task.isCancelled {
                level = Float.random(in: 0.25...0.85)
                try? await Task.sleep(for: .milliseconds(140))
            }
            level = 0
            mode = .idle
        }
    }
}
