#if DEBUG
import SwiftUI

/// LAYOUT EXPERIMENT — a How-We-Feel-style take on the Talk home, for design
/// review only (never wired into the real tab). A thin, fully-closed goal
/// ring whose interior IS the Futureself surface; tapping it morphs the
/// surface down into the exact 156×64 pill ConversationView's bottom bar
/// uses (same pixel size — the cell scale is pinned to the pill's), while
/// the home chrome fades away. Below the ring: a plain scrolling card list
/// (News + Scenarios) that fades into the background at the screen bottom.
///
/// Capture: `-capture talk-alt` (home) · `-capture talk-alt-call` (on call)
///        · `-capture talk-alt-demo` (auto-plays the tap transition — record
///          a video to review the morph).
struct TalkHomeExperiment: View {
    /// Start on the call side of the transition (still capture).
    var startOnCall = false
    /// Auto-toggle the transition for video capture.
    var autoDemo = false

    @State private var onCall = false
    /// Measured anchor frames (in the experiment's coordinate space). The
    /// surface animates its frame+position between the two — matched-geometry
    /// id swaps snap instead of gliding, so the interpolation is done by hand.
    @State private var anchorRects: [String: CGRect] = [:]

    // Sample numbers — this is a look test, not a data test.
    private let streakDays = 4
    private let todayMinutes = 6
    private let goalMinutes = 10
    private var goalProgress: Double { Double(todayMinutes) / Double(goalMinutes) }

    private var morph: Animation { .spring(response: 0.55, dampingFraction: 0.85) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            homeContent
                .opacity(onCall ? 0 : 1)

            callChrome
                .opacity(onCall ? 1 : 0)

            // The pill-position anchor — exactly where ConversationView's
            // bottom-bar pill sits (156×64, hint line + 20pt under it).
            VStack(spacing: 10) {
                Color.clear
                    .frame(width: 156, height: 64)
                    .anchorRect("pill")
                Text("Tap to talk")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 16)
                    .opacity(onCall ? 1 : 0)
            }
            .padding(.bottom, 20)

            // THE surface — one view, matched to whichever anchor is active,
            // so the circle glides down and reshapes into the pill.
            morphingSurface

            tabBarMock
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
                .opacity(onCall ? 0 : 1)
        }
        .coordinateSpace(name: "exp")
        .onPreferenceChange(AnchorRectsKey.self) { anchorRects = $0 }
        .onAppear { if startOnCall { onCall = true } }
        .task {
            guard autoDemo else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(morph) { onCall = true }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(morph) { onCall = false }
        }
    }

    // MARK: - Home side

    private var homeContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 0) {
                    Text("What's on your mind\nthis evening?")
                        .geistPixel(22)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 32)

                    goalRing
                        .padding(.top, 28)

                    cardList
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                        // Tail room: the last card can scroll up out of the
                        // fade-out zone.
                        .padding(.bottom, 150)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
            // The list runs to the physical bottom and dissolves into the
            // background as it goes — nothing hard-clips behind the tab bar.
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .black.opacity(0)],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                    // Fully gone well before the physical bottom edge.
                    Color.clear.frame(height: 60)
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - Call side (mock of the conversation screen's frame)

    private var callChrome: some View {
        VStack {
            HStack {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Header (chip · streak pill · avatar)

    private var header: some View {
        ZStack {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("\(streakDays) day streak")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.secondarySystemBackground)))

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2.weight(.bold))
                    Text("EN")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                Spacer()
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Text("A")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - The ring (thin, fully closed) + the surface anchor

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.secondarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(goalProgress, 1))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // The circle-position anchor the surface matches at home.
            Color.clear
                .frame(width: 244, height: 244)
                .anchorRect("circle")
        }
        .frame(width: 280, height: 280)
    }

    /// One Futureself surface, framed+positioned onto the active anchor by
    /// hand, so `withAnimation` interpolates the whole journey — size, spot,
    /// and corner radius all glide from circle to pill in one move.
    @ViewBuilder
    private var morphingSurface: some View {
        let rect = anchorRects[onCall ? "pill" : "circle"] ?? .zero
        if rect != .zero {
            Button {
                withAnimation(morph) { onCall.toggle() }
            } label: {
                ZStack {
                    FutureselfPillCell(mode: .idle, level: 0)
                    if onCall {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 6) {
                            Text("Let's talk")
                                .geistPixel(20)
                            Text("\(todayMinutes) of \(goalMinutes) min today")
                                .font(.footnote.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: onCall ? 32 : 122,
                                            style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: onCall ? 32 : 122,
                                          style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: onCall ? 32 : 122))
            }
            .buttonStyle(.plain)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Card list (News + Scenarios)

    private var cardList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("In the news")
            card("Did you hear about OpenAI's model hacking a company?",
                 subtitle: "ai / tech", icon: "cpu")
            card("Have you heard beef tallow is making a comeback?",
                 subtitle: "cooking", icon: "fork.knife")
            card("Did you see the home robot folding laundry?",
                 subtitle: "ai / tech", icon: "cpu")

            sectionHeader("Scenarios")
                .padding(.top, 14)
            card("Café · catching up", subtitle: "with Sarah",
                 icon: "cup.and.saucer.fill")
            card("Doctor's visit", subtitle: "with Doctor",
                 icon: "cross.case.fill")
            card("Job interview · panel round", subtitle: "with Interviewer",
                 icon: "briefcase.fill")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .geistPixel(17)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    /// One list card — category icon in a tinted circle, title + caption,
    /// chevron. Tap would start the talk.
    private func card(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Floating tab bar (mock — the real one is RootTabView's)

    private var tabBarMock: some View {
        HStack(spacing: 4) {
            tabItem("mic.fill", "Talk", selected: true)
            tabItem("play.rectangle", "Watch")
            tabItem("book", "Practice")
            tabItem("chart.bar", "Progress")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        )
    }

    private func tabItem(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(selected ? Color(.secondarySystemFill) : .clear)
        )
    }
}

/// Reports a view's frame (in the experiment's named coordinate space) under
/// a string key, for the hand-driven anchor morph above.
private struct AnchorRectsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func anchorRect(_ key: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: AnchorRectsKey.self,
                                   value: [key: g.frame(in: .named("exp"))])
        })
    }
}

/// Experiment-only Futureself variant with the cell size PINNED to the
/// conversation pill's (64pt tall → 12.8pt cells), regardless of the frame.
/// The stock shader derives cells from the view height (`size.y / 5`), so a
/// 244pt circle gets huge blocks; lying about the size keeps the grid fine
/// at home AND makes the morph land pixel-identical on ConversationView's
/// pill. (Production version would add a row-count knob to the shader.)
private struct FutureselfPillCell: View {
    var mode: Futureself.Mode
    var level: Float

    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let t = Float(now.truncatingRemainder(dividingBy: 1000))
                let resolved = FutureselfTheme(rawValue: storedTheme) ?? .blue
                // Pretend the surface is 64pt tall (width scaled to match):
                // cellPt = 64/5 = 12.8pt at ANY real size.
                let h = max(Float(geo.size.height), 1)
                let fakeH: Float = 64
                let fakeW = Float(geo.size.width) * fakeH / h
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.futureself(
                        .float2(fakeW, fakeH),
                        .float(t),
                        .float(level),
                        .float(mode.rawValue),
                        .float(colorScheme == .dark ? 1 : 0),
                        .float(Float(resolved.rawValue))
                    ))
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
