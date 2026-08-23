import SwiftUI

/// The Welcome carousel's five key visuals — LIVE compositions of the app's
/// real components, not screenshots and not reconstructions:
///
///   1. `TalkHero`    — the actual `Futureself` call pill cycling its modes
///                      while real `DialogueLine`s land in the transcript;
///                      the conversation itself rotates through many topics.
///   2. `PeopleHero`  — real `PersonBubble` avatars drifting around the
///                      user's own Futureself surface.
///   3. `WatchHero`   — a scene played through `DialogueLine` exactly like
///                      `WatchView`: text header, the accent playback ring
///                      walking line to line, Shadow this / Save phrase under
///                      each bubble, and the Restart / Play control bar. The
///                      scene (counterpart + situation) rotates.
///   4. `ShadowHero`  — the shadow target line: real `FlowLayout` karaoke
///                      words sweeping primary → accent → secondary on the
///                      same colour grammar as `ShadowDrillView`.
///   5. `VocabHero`   — the word cloud laid out by the real `CloudLayout`
///                      engine, panning itself the way a finger would.
///
/// Every hero drives a scripted loop; all chrome (fonts, fills, sizes) comes
/// from the shared components or mirrors its home surface 1:1. The heroes
/// assume a `Color(.systemBackground)` ground (like the real conversation
/// screens) so DialogueLine's neutral bubble fill reads as filled, not empty.
///
/// **The carousel's five are now** (2026-08-23) `CallHero`, `HomeHero`,
/// `BookHero`, `ShadowHero`, `LevelHero` — the same five-beat story the
/// landing page's scrollytelling tells, except at beat four, where the app
/// shows shadowing and the page shows the word cloud. The old set pitched
/// FEATURES (Talk, Watch, People, Shadow, Vocabulary) and between them never
/// showed the thing a talk actually LEAVES: the book. `TalkHero`,
/// `WatchHero`, `PeopleHero` and `VocabHero` stay in the file as the
/// alternates; re-pointing `WelcomeView.mock(_:)` at one is a one-line
/// change.

// MARK: - 1. Talk

struct TalkHero: View {
    /// Three ticker lanes flow BEHIND the orb — one per way into Talk —
    /// alternating direction like passing traffic: news leftward, scenarios
    /// rightward, free-talk prompts leftward. The orb, front and center,
    /// keeps taking calls. No transcript here — that's Watch's visual.
    private static let news = [
        "Germany weighs a four-day work week",
        "AI is changing how we interview",
        "Rents keep climbing in big cities",
        "The slow-travel comeback",
    ]
    private static let scenarios = [
        "Ordering at a busy caf\u{00E9}",
        "Asking your boss for Friday off",
        "Small talk with your landlord",
        "Returning shoes without a receipt",
    ]
    private static let freeTalk = [
        "\u{201C}So — anything on your mind?\u{201D}",
        "\u{201C}How did your day actually go?\u{201D}",
        "\u{201C}What made you smile today?\u{201D}",
        "\u{201C}Weekend plans yet?\u{201D}",
    ]

    @State private var mode: Futureself.Mode = .idle
    @State private var level: Float = 0

    var body: some View {
        ZStack {
            // The lanes — full-bleed marquees, each its own pace/direction.
            VStack(spacing: 12) {
                HeroTicker(icon: "newspaper",    items: Self.news,      speed: 24, reverse: false)
                HeroTicker(icon: "theatermasks", items: Self.scenarios, speed: 18, reverse: true)
                HeroTicker(icon: "waveform",     items: Self.freeTalk,  speed: 27, reverse: false)
            }

            // The protagonist — the lanes stream past behind it.
            ZStack {
                Futureself(mode: mode, level: level)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 172, height: 172)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        }
        .task { await run() }
    }

    private var symbol: String {
        switch mode {
        case .idle:      return "mic.fill"
        case .listening: return "waveform"
        case .thinking:  return "ellipsis"
        case .speaking:  return "speaker.wave.2.fill"
        }
    }

    /// The orb's call loop: you speak (listening ignites) → a thinking
    /// beat → the fluent self answers (speaking bloom) → breathe, repeat.
    private func run() async {
        while !Task.isCancelled {
            set(mode: .listening, level: 0.85)
            await pause(1.4)
            set(mode: .thinking, level: 0)
            await pause(0.7)
            set(mode: .speaking, level: 0.7)
            await pause(2.0)
            set(mode: .idle, level: 0)
            await pause(0.6)
        }
    }

    private func set(mode: Futureself.Mode, level: Float) {
        withAnimation(.spring(duration: 0.45)) {
            self.mode = mode
            self.level = level
        }
    }

    private func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}

/// One marquee lane: its items repeat seamlessly (two copies of the segment,
/// offset by time, wrapped at the measured segment width). `reverse` flips
/// the direction so adjacent lanes stream past each other.
private struct HeroTicker: View {
    let icon: String
    let items: [String]
    let speed: Double     // points per second
    let reverse: Bool

    @State private var segmentWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        // GeometryReader is RIGID — it always reports exactly the proposed
        // size, so the marquee's (very wide) fixedSize content can never leak
        // into the page layout; it just overflows and gets clipped.
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSince(start)
                let raw = CGFloat(elapsed * speed)
                let phase = segmentWidth > 0 ? raw.truncatingRemainder(dividingBy: segmentWidth) : 0
                HStack(spacing: 10) {
                    segment
                    segment
                }
                .fixedSize()
                .offset(x: reverse ? phase - segmentWidth : -phase)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: 42)
    }

    private var segment: some View {
        HStack(spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(items[i])
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
            }
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { segmentWidth = geo.size.width + 10 }
        })
    }
}

// MARK: - 2. People

struct PeopleHero: View {
    private struct Person {
        let name: String
        let role: String
        let size: CGFloat
        /// Resting anchor, normalized 0…1 in the hero area.
        let anchor: CGPoint
        /// Bob phase/speed so no two drift in sync.
        let phase: Double
        let speed: Double
    }

    private static let people: [Person] = [
        Person(name: "Sofia",    role: "Barista",       size: 64,
               anchor: CGPoint(x: 0.22, y: 0.20), phase: 0.0, speed: 0.55),
        Person(name: "Dr. Park", role: "Family doctor", size: 56,
               anchor: CGPoint(x: 0.80, y: 0.16), phase: 1.7, speed: 0.45),
        Person(name: "Mina",     role: "Team lead",     size: 72,
               anchor: CGPoint(x: 0.85, y: 0.55), phase: 3.1, speed: 0.60),
        Person(name: "Jake",     role: "Gym buddy",     size: 60,
               anchor: CGPoint(x: 0.16, y: 0.62), phase: 4.4, speed: 0.50),
        Person(name: "Alex",     role: "Landlord",      size: 52,
               anchor: CGPoint(x: 0.30, y: 0.92), phase: 2.3, speed: 0.42),
        Person(name: "Emma",     role: "Classmate",     size: 56,
               anchor: CGPoint(x: 0.72, y: 0.90), phase: 5.2, speed: 0.58),
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    // You, at the centre — the same living surface as the call
                    // button, worn as the home circle.
                    VStack(spacing: 8) {
                        Futureself(mode: .idle, level: 0)
                            .frame(width: 92, height: 92)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                        Text("You")
                            .font(.caption.weight(.semibold))
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.48)

                    // Your people, drifting around you — the SAME PersonBubble
                    // the Watch tab's stories row renders.
                    ForEach(Self.people, id: \.name) { p in
                        VStack(spacing: 6) {
                            PersonBubble(name: p.name, size: p.size)
                            Text(p.name)
                                .font(.caption)
                                .lineLimit(1)
                            Text(p.role)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .position(x: geo.size.width * p.anchor.x + sin(t * p.speed + p.phase) * 7,
                                  y: geo.size.height * p.anchor.y + cos(t * (p.speed * 0.8) + p.phase) * 9)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - 3. Watch

struct WatchHero: View {
    struct Scene {
        let name: String
        let relationship: String
        let title: String
        let lines: [(speaker: DialogueSpeaker, text: String)]
    }

    /// A few real-life scenes, rotated — the situation, the person, and the
    /// dialogue all change so it reads as an endless library, not one clip.
    private static let scenes: [Scene] = [
        Scene(name: "Sofia", relationship: "Your barista", title: "Trying something new",
              lines: [(.other, "Morning! The usual oat latte?"),
                      (.user,  "Actually — can I try something new today?"),
                      (.other, "Ooh, feeling adventurous. How about a cortado?"),
                      (.user,  "What's a cortado like?"),
                      (.other, "Bolder — equal parts espresso and warm milk.")]),

        Scene(name: "Dr. Park", relationship: "Family doctor", title: "The check-up",
              lines: [(.other, "So, what brings you in today?"),
                      (.user,  "I've had a cough that won't quite go away."),
                      (.other, "How long has it been lingering?"),
                      (.user,  "About two weeks now, mostly at night."),
                      (.other, "Let's take a listen to your chest.")]),

        Scene(name: "Mina", relationship: "Team lead", title: "Asking for time off",
              lines: [(.other, "You wanted to chat before standup?"),
                      (.user,  "Yeah — I'd like the last week of March off."),
                      (.other, "Let me check the sprint, but that should work."),
                      (.user,  "I can wrap up the report before I go."),
                      (.other, "Perfect. Send me the dates and I'll approve it.")]),

        Scene(name: "Alex", relationship: "Landlord", title: "The leaky faucet",
              lines: [(.other, "You mentioned something needs fixing?"),
                      (.user,  "The kitchen tap's been dripping all week."),
                      (.other, "I'll send someone over on Thursday."),
                      (.user,  "Morning works best if that's possible."),
                      (.other, "I'll ask them to come before noon.")]),
    ]

    @State private var scene = 0
    @State private var current = 0

    private var s: Scene { Self.scenes[scene] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — WatchView's exact grammar: "name · relationship", title.
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.name) · \(s.relationship)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(s.title)
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The scene, line by line — DialogueLine with the accent playback
            // ring walking down, and Shadow this / Save phrase under each,
            // exactly like WatchView's bubbles.
            VStack(spacing: 12) {
                ForEach(Array(s.lines.enumerated()), id: \.offset) { i, line in
                    // In Watch, YOUR side is performed by the fluent self —
                    // you watch it handle the scene, you don't speak.
                    DialogueLine(speaker: line.speaker,
                                 name: line.speaker.isUser ? "Future self" : s.name,
                                 isCurrent: i == current) {
                        Text(line.text)
                    } accessory: {
                        HStack(spacing: 16) {
                            Label("Shadow this", systemImage: "waveform.badge.mic")
                                .font(.caption)
                                .foregroundStyle(.tint)
                            Label("Save phrase", systemImage: "plus.circle")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // The Restart / Play control bar — WatchView's footer, verbatim.
            HStack(spacing: 16) {
                Label("Restart", systemImage: "backward.end.fill")
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .task {
            while !Task.isCancelled {
                // Walk the playback ring down the scene…
                for i in 0..<s.lines.count {
                    withAnimation(.spring(duration: 0.4)) { current = i }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if Task.isCancelled { return }
                }
                // …then cut to the next scene.
                withAnimation(.easeInOut(duration: 0.3)) { current = 0 }
                try? await Task.sleep(nanoseconds: 300_000_000)
                scene = (scene + 1) % Self.scenes.count
            }
        }
    }
}

// MARK: - 4. Shadow

struct ShadowHero: View {
    /// The sample line, with the evenly-spaced timings `ShadowDrillView`
    /// synthesizes offline (380 ms per word).
    private static let words = "I really appreciate you taking the time to help me."
        .split(separator: " ").map(String.init)
    private static let perWordMs = 380
    private static let selected = 2...5          // "appreciate you taking the"

    private static var durMs: Int { words.count * perWordMs + 200 }
    private static var loopStartMs: Int { selected.lowerBound * perWordMs }
    private static var loopEndMs: Int { (selected.upperBound + 1) * perWordMs }
    /// Playhead loops the selected phrase (like the real loop toggle), pausing
    /// briefly at each end.
    private static var cycleMs: Int { (loopEndMs - loopStartMs) + 900 }

    // Timeline geometry — matched to ShadowTimelinePlayer's TLConst.
    private static let trackHeight: CGFloat = 54
    private static let handleW: CGFloat = 14
    /// What `ShadowTimelinePlayer.speedLabel(1.0)` returns.
    private static let speedLabel = "1×"

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = Int(context.date.timeIntervalSince(start) * 1000)
            let phase = t % Self.cycleMs
            // Playhead sweeps the loop region, then holds at the end.
            let span = Self.loopEndMs - Self.loopStartMs
            let nowMs = Self.loopStartMs + min(span, phase)

            VStack(spacing: 16) {
                targetLine(nowMs: nowMs)
                scrubber(nowMs: nowMs)
            }
            .padding(.horizontal, 22)
        }
        .onAppear { start = Date() }
    }

    // MARK: - Target line (real FlowLayout + karaoke colours)

    private func targetLine(nowMs: Int) -> some View {
        // spacing 8 — ShadowDrillView's targetSection.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target line").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Self.words.count) words").font(.caption2).foregroundStyle(.tertiary)
            }
            // ShadowDrillView's exact grammar: passed = primary, current =
            // accent, upcoming = secondary; the loop phrase carries the wash.
            FlowLayout(spacing: 1, lineSpacing: 6) {
                ForEach(Array(Self.words.enumerated()), id: \.offset) { i, word in
                    Text(word)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(color(at: i, nowMs: nowMs))
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Self.selected.contains(i)
                                      ? Color.accentColor.opacity(0.22)
                                      : Color.clear)
                        )
                }
            }
        }
    }

    // MARK: - Scrubber (mirrors ShadowTimelinePlayer 1:1)

    private func scrubber(nowMs: Int) -> some View {
        VStack(spacing: 16) {
            timeline(nowMs: nowMs)
                .padding(.horizontal, 4)
            labels(nowMs: nowMs)
            controls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        // Glass card + hairline border — matches ShadowTimelinePlayer's
        // current styling (was a solid secondarySystemBackground fill).
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func timeline(nowMs: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = CGFloat(Self.durMs)
            let sx = CGFloat(Self.loopStartMs) / dur * w
            let ex = CGFloat(Self.loopEndMs) / dur * w
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: Self.trackHeight)

                // Per-word tick markers.
                ForEach(0..<Self.words.count, id: \.self) { i in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 1.5, height: 16)
                        .offset(x: CGFloat(i * Self.perWordMs) / dur * w)
                }

                // Loop band + START/END handles.
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: max(0, ex - sx), height: Self.trackHeight)
                    .offset(x: sx)
                handle(at: sx)
                handle(at: ex)

                // Playhead.
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2.5, height: Self.trackHeight + 8)
                    .offset(x: max(0, min(w - 2.5, CGFloat(nowMs) / dur * w)))
                    .shadow(color: Color(.systemBackground), radius: 1)
            }
            .frame(height: Self.trackHeight)
        }
        .frame(height: Self.trackHeight)
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .frame(width: Self.handleW, height: Self.trackHeight)
            .overlay(Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 16))
            .offset(x: x - Self.handleW / 2)
    }

    private func labels(nowMs: Int) -> some View {
        HStack {
            Text(timeLabel(nowMs))
            Spacer()
            Text("loop \(timeLabel(Self.loopStartMs))–\(timeLabel(Self.loopEndMs))")
                .foregroundStyle(.tint)
            Spacer()
            Text(timeLabel(Self.durMs))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    /// The transport row — play and loop (on) hugging the left, the centered
    /// mic, then the speed pill and the back-to-previous-selection button on
    /// the right. Matched 1:1 to ShadowTimelinePlayer's `controls`.
    private var controls: some View {
        HStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .frame(width: 44, height: 44)
                .foregroundStyle(.tint)
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 44))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.accentColor)
            Spacer(minLength: 72)
            // `Text(String)`, never a literal — `ShadowTimelinePlayer` builds
            // this label with `speedLabel(_:)`, so the real pill never goes
            // through the string catalog. Written as a literal here it did,
            // and ko translates "1×" to "1배", which then wrapped inside the
            // capsule as "1 / 배". lineLimit + fixedSize mirror the real one.
            Text(Self.speedLabel)
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.primary)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
            // Step back through the regions you drilled — always visible, gray
            // until there's history to pop.
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 44))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.secondary)
        }
        .overlay {
            // The centered mic — the primary record action, 60pt like the real
            // one (micButton(diameter: 60)), glyph at 0.375 × diameter.
            Image(systemName: "mic.fill")
                .font(.system(size: 60 * 0.375, weight: .semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.accentColor))
        }
    }

    private func color(at i: Int, nowMs: Int) -> Color {
        let start = i * Self.perWordMs
        let end = start + Self.perWordMs
        // Only the loop phrase animates; the rest rests quiet, like loop mode.
        if !Self.selected.contains(i) { return .secondary }
        if nowMs >= end   { return .primary }
        if nowMs >= start { return .accentColor }
        return .secondary
    }

    private func timeLabel(_ ms: Int) -> String {
        let s = Double(ms) / 1000.0
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

// MARK: - 5. Vocabulary

struct VocabHero: View {
    /// A wide spread across levels; sizes come from the real level → size
    /// mapping so the cloud's texture matches the Vocabulary page. A big set
    /// so the self-pan keeps revealing fresh words.
    private static let sample: [(word: String, level: CEFRLevel)] = [
        ("time", .a1), ("people", .a1), ("water", .a1), ("happy", .a1), ("work", .a1),
        ("house", .a1), ("friend", .a1), ("money", .a1), ("today", .a1), ("family", .a1),
        ("travel", .a2), ("weather", .a2), ("moment", .a2), ("decide", .a2), ("weekend", .a2),
        ("remember", .a2), ("plan", .a2), ("busy", .a2), ("early", .a2), ("healthy", .a2),
        ("negotiate", .b1), ("apparently", .b1), ("confident", .b1), ("routine", .b1), ("opinion", .b1),
        ("manage", .b1), ("realize", .b1), ("suggest", .b1), ("prefer", .b1), ("recently", .b1),
        ("tentative", .b2), ("leverage", .b2), ("downplay", .b2), ("insight", .b2), ("subtle", .b2),
        ("reluctant", .b2), ("emphasize", .b2), ("overwhelm", .b2), ("genuine", .b2), ("worthwhile", .b2),
        ("meticulous", .c1), ("profound", .c1), ("revitalize", .c1), ("nuance", .c1), ("pragmatic", .c1),
        ("inevitable", .c1), ("compelling", .c1), ("resilient", .c1),
        ("ubiquitous", .c2), ("ephemeral", .c2), ("eloquent", .c2), ("serendipity", .c2), ("quintessential", .c2),
    ]
    private static let studying: Set<String> = ["negotiate", "meticulous", "leverage", "nuance"]
    private static let known: Set<String> = ["time", "people", "travel", "happy", "work", "plan", "manage"]

    @State private var nodes: [CloudLayout.Node] = []
    @State private var canvas: CGSize = .zero
    @State private var pan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let margin: CGFloat = 70
            ZStack {
                // Transparent ground — the hero sits on the Welcome
                // background; the vignette already fades words at the edges.
                Color.clear
                // Node rendering mirrors VocabularyView's cloud 1:1 — depth
                // parallax, elliptical vignette, status badges.
                ForEach(nodes) { node in
                    let sx = center.x + (node.pos.x + pan.width - center.x) * node.depth
                    let sy = center.y + (node.pos.y + pan.height - center.y) * node.depth
                    if sx > -margin, sx < geo.size.width + margin,
                       sy > -margin, sy < geo.size.height + margin {
                        let nd = hypot((sx - center.x) / center.x, (sy - center.y) / center.y)
                        let opacity = max(0, min(1, 1.25 - nd))
                        let used = Self.known.contains(node.word)
                        let studying = Self.studying.contains(node.word)
                        Text(node.word)
                            .font(.system(size: node.size, weight: used ? .regular : .semibold, design: .rounded))
                            .foregroundStyle(used ? Color.secondary : Color.primary)
                            .overlay(alignment: .topLeading) {
                                if studying || used {
                                    Image(systemName: studying ? "bookmark.fill" : "checkmark")
                                        .font(.system(size: max(8, node.size * 0.42), weight: .semibold))
                                        .foregroundStyle(studying ? Color.accentColor : Color.green)
                                        .offset(x: -4, y: -max(8, node.size * 0.42))
                                }
                            }
                            .opacity(opacity)
                            .fixedSize()
                            .position(x: sx, y: sy)
                    }
                }
            }
            .clipped()
            .task { await run(viewport: geo.size) }
        }
    }

    /// Lays out with the real packing engine, then pans itself the way a
    /// finger would — drift, settle, drift back. Same easing family as the
    /// page's momentum snap (`easeOut(0.6)`).
    private func run(viewport: CGSize) async {
        let cloud = await Task.detached(priority: .userInitiated) {
            CloudLayout.layout(Self.sample.map { ($0.word, VocabularyView.size(for: $0.level)) })
        }.value
        nodes = cloud.nodes
        canvas = cloud.canvas
        let home = CGSize(width: viewport.width / 2 - cloud.canvas.width / 2,
                          height: viewport.height / 2 - cloud.canvas.height / 2)
        pan = home

        // A slow tour around the cloud so different words drift through view.
        let drifts: [CGSize] = [
            CGSize(width: home.width - 90, height: home.height - 50),
            CGSize(width: home.width + 70, height: home.height - 20),
            CGSize(width: home.width + 40, height: home.height + 60),
            CGSize(width: home.width - 60, height: home.height + 30),
            home,
        ]
        var i = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 1.4)) { pan = drifts[i % drifts.count] }
            i += 1
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// The five the carousel actually shows.
//
// Each one is the REAL screen, mirrored — same components where they're
// shareable (`DialogueLine`, `Futureself`, `BookmarkedPage`, `LevelEqualizer`,
// `CloudLayout`), same fonts, fills and metrics where they aren't. Sample
// content is passed as `String` variables on purpose: a `Text(variable)` is
// never localized, so the material stays in the target language while the
// chrome literals around it follow the learner's UI language.
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - 1. The fluent self

/// Slide one has one job: say what this IS. So the protagonist is the
/// `Futureself` surface itself — the same living shader the call button and
/// the home ring wear — taking a turn, with one line of what it says beside
/// it. It used to be the call transcript, and a stack of bubbles reads as a
/// message log: the collection became the subject and the idea never landed.
///
/// The line is the app's own first-call introduction (`FreeTalkOpeners`),
/// because nothing states the concept better than the thing saying it out
/// loud in the learner's own voice.
struct FutureselfHero: View {
    /// The opening of `FreeTalkOpeners.introOpeners["en"]`, split where the
    /// real call breathes. Material, so it stays in the target language.
    private static let lines = [
        "Hi. I'm the future you — the one who speaks English fluently.",
        "I can't wait for all the talks ahead of us.",
        "So — what are you up to these days?",
    ]

    @State private var mode: Futureself.Mode = .idle
    @State private var level: Float = 0
    @State private var line = 0
    @State private var showing = false

    var body: some View {
        // Spacers on BOTH sides of the orb: pinned to the bottom, the state
        // hint sat inside the frame's bottom fade and read as half-erased.
        VStack(spacing: 18) {
            bubble
            Spacer(minLength: 0)
            orb
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .task { await run() }
    }

    /// The line STAYS once it has been said — a transcript doesn't erase
    /// itself between turns, and a bubble that vanishes left a hole above the
    /// orb for half of every loop.
    private var bubble: some View {
        DialogueLine(speaker: .other, name: "Future self") {
            Text(Self.lines[line])
        } accessory: { EmptyView() }
            .id(line)
            .transition(.opacity)
            .opacity(showing ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The home's talk ring, minus the goal arc — this slide is about who is
    /// on the other end, not about today's minutes.
    private var orb: some View {
        VStack(spacing: 12) {
            Futureself(mode: mode, level: level)
                .frame(width: 196, height: 196)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            // No animation on the label — `ConversationView`'s bottom bar
            // does the same. The mode change is animated, and letting the
            // hint ride that animation crossfades two different words on top
            // of each other.
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 18)
                .animation(nil, value: mode)
        }
    }

    private var hint: LocalizedStringKey {
        switch mode {
        case .idle:      return "Tap to talk"
        case .listening: return "Listening…"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Speaking…"
        }
    }

    /// One turn of a call: it speaks, you answer, it thinks, it speaks again.
    private func run() async {
        while !Task.isCancelled {
            for i in Self.lines.indices {
                set(.speaking, 0.7)
                withAnimation(.easeOut(duration: 0.35)) { line = i; showing = true }
                await pause(2.8)
                if Task.isCancelled { return }
                guard i < Self.lines.count - 1 else { break }
                // You answer, it thinks — the line it just said stays up.
                set(.listening, 0.85)
                await pause(1.6)
                set(.thinking, 0)
                await pause(0.8)
                if Task.isCancelled { return }
            }
            set(.idle, 0)
            await pause(1.4)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.3)) { showing = false }
            await pause(0.5)
        }
    }

    private func set(_ m: Futureself.Mode, _ l: Float) {
        withAnimation(.spring(duration: 0.45)) { mode = m; level = l }
    }

    private func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}

// MARK: - 2. What there is to talk about

/// `ConversationHome`'s Discover section, mirrored — the News / Scenarios
/// chips and the cards under them, flipping between the two on their own.
///
/// The greeting and the talk ring were here first and had to go: this slide
/// answers "what would I even say?", and a ring saying "3 of 10 min today"
/// answers a question nobody has yet. The ring is slide one's business, and
/// it has it now.
struct HomeHero: View {
    private struct Row {
        let icon: String
        let title: String
        let caption: String
    }

    private static let news = [
        Row(icon: "cpu", title: "Did you hear about OpenAI's model hacking a company?", caption: "AI / Tech"),
        Row(icon: "chart.line.uptrend.xyaxis", title: "Germany weighs a four-day work week", caption: "Business"),
        Row(icon: "airplane", title: "The slow-travel comeback", caption: "Travel"),
        Row(icon: "figure.run", title: "Why everyone suddenly runs a half marathon", caption: "Sports"),
    ]
    private static let scenarios = [
        Row(icon: "cup.and.saucer", title: "Ordering at a busy café", caption: "with Sofia"),
        Row(icon: "person.badge.clock", title: "Asking your boss for Friday off", caption: "with Mina"),
        Row(icon: "stethoscope", title: "Describing a cough that won't go", caption: "with Dr. Park"),
        Row(icon: "house", title: "The kitchen tap has been dripping all week", caption: "with Alex"),
    ]

    @State private var onScenarios = false

    private var rows: [Row] { onScenarios ? Self.scenarios : Self.news }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 10) {
                ForEach(rows, id: \.title) { listCard($0) }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        // Clear of the frame's top fade — sitting in it, the selected chip
        // looked like it had a gradient fill.
        .padding(.top, 14)
        .task { await run() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            chip("News", on: !onScenarios)
            chip("Scenarios", on: onScenarios)
            Spacer()
            Image(systemName: "slider.horizontal.3")
            Image(systemName: "arrow.clockwise")
        }
        .font(.subheadline)
        .foregroundStyle(.tint)
        .padding(.horizontal, 20)
    }

    private func chip(_ title: LocalizedStringKey, on: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(on ? Color(.label) : Color(.secondarySystemBackground)))
            .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
    }

    private func listCard(_ row: Row) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: row.icon).font(.subheadline).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(row.caption).font(.caption).foregroundStyle(.secondary)
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

    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.35)) { onScenarios.toggle() }
        }
    }
}

// MARK: - 3. The book

/// The book a finished talk becomes — the REAL `BookmarkedPage`, with the
/// same ribbon bookmarks `ConversationDetailView` puts on it, and a tap
/// landing on one ribbon after another so the carousel shows the book being
/// FLIPPED THROUGH rather than a still of its cover. The chapters are the
/// real ones: Overview · Words · Expressions · Shadow · Drill.
struct BookHero: View {
    enum Chapter: Hashable, CaseIterable {
        case intro, words, expressions, lines, cards
    }

    /// Mirrors `ConversationDetailView.allTabs`.
    private static let tabs: [BookmarkTab<Chapter>] = [
        BookmarkTab(id: .intro, icon: "book.closed", title: "Overview"),
        BookmarkTab(id: .words, icon: "textformat", title: "Words", done: 5, total: 9),
        BookmarkTab(id: .expressions, icon: "quote.opening", title: "Expressions", count: 6),
        BookmarkTab(id: .lines, icon: "waveform.badge.mic", title: "Shadow", count: 4),
        BookmarkTab(id: .cards, icon: "rectangle.stack", title: "Drill", count: 3),
    ]

    /// Ribbon geometry, mirrored from `BookmarkPage.swift`: 10pt of padding
    /// above and below, the icon line, then the badge line on every ribbon
    /// but the cover's. Only the tap ripple needs it — the ribbons themselves
    /// are drawn by the real component.
    private static let ribbonHeights: [CGFloat] = [40, 57, 57, 57, 57]
    private static let ribbonSpacing: CGFloat = 4

    /// Material, not chrome — the talk's own title.
    private static let talkTitle = "Job interview"

    @State private var chapter: Chapter = .intro
    @State private var tapAt: Int?
    @State private var tapping = false

    var body: some View {
        BookmarkedPage(tabs: Self.tabs, selection: chapter, onSelect: { chapter = $0 }) {
            page
        }
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topLeading) { ripple }
        .task { await run() }
    }

    /// The tap: a ring that blooms on the ribbon a moment BEFORE the page
    /// turns, so the page reads as its consequence.
    @ViewBuilder
    private var ripple: some View {
        if let i = tapAt {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5))
                .frame(width: 38, height: 38)
                .scaleEffect(tapping ? 1.0 : 0.45)
                .opacity(tapping ? 0 : 0.95)
                .offset(x: 5, y: 8 + ribbonCenter(i) - 19)
                .allowsHitTesting(false)
        }
    }

    private func ribbonCenter(_ index: Int) -> CGFloat {
        let above = Self.ribbonHeights.prefix(index)
        return above.reduce(0, +)
            + CGFloat(index) * Self.ribbonSpacing
            + Self.ribbonHeights[index] / 2
    }

    // MARK: The open chapter

    @ViewBuilder
    private var page: some View {
        switch chapter {
        case .intro:
            cover
            report
        case .words:       chapterPage("Words") { wordRows }
        case .expressions: chapterPage("Expressions") { expressionRows }
        case .lines:       chapterPage("Shadow") { shadowRows }
        case .cards:       chapterPage("Drill") { drillRows }
        }
    }

    private func chapterPage<C: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
            rows()
        }
    }

    /// The cover — `ConversationDetailView`'s intro header: what the talk was,
    /// how much of it is mastered, and the two things you can do with it.
    private var cover: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title2).foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    // A talk's title is MATERIAL — it comes back in the target
                    // language, so it goes through a variable and is never
                    // extracted for translation.
                    Text(Self.talkTitle)
                        .font(.title3.weight(.semibold))
                    // The same two interpolations the real cover builds, so
                    // both lines read in the learner's language and format.
                    Text("\(Date().formatted(date: .abbreviated, time: .shortened)) · \(14) turns spoken")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: 9.0 / 14.0)
                Text("\(9) of \(14) mastered")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label("Continue", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.accentColor))
                Label("Replay", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
        .padding(20)
    }

    /// The cover is the cover AND the report — `ConversationDetailView`'s
    /// intro page runs Score then Coach's note under the buttons, and without
    /// them the page ended in white space directly under Continue/Replay,
    /// which said the talk produced two buttons and nothing else.
    @ViewBuilder
    private var report: some View {
        Divider().padding(.leading, 20)
        groupHeaderWide("Score", icon: "chart.bar")
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Overall").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Self.scorecard.overall)")
                    .font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Self.color(Self.scorecard.overall))
            }
            Text(explain("Graded against your B1 setting — how this talk went, not what your level is."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScorecardView(scorecard: Self.scorecard)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)

        Divider().padding(.leading, 20).padding(.top, 8)
        groupHeaderWide("Coach's note", icon: "text.bubble")
        Text(explain("You carried the whole story yourself and only stalled on tenses when it moved back in time. Next talk, try setting the scene in the past first."))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 8)
    }

    /// `ConversationDetailView.groupLabel` — 20pt gutter, unlike the study
    /// chapters' 16.
    private func groupHeaderWide(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    /// Sample analysis. Notes are COACHING, so they go through `explain` and
    /// come back in the learner's language; a computed property because a
    /// stored static would resolve its strings once per process, before
    /// setup's first question can change that language.
    private static var scorecard: SessionScorecard {
        SessionScorecard(
            vocabulary: AxisScore(score: 78, note: explain("You reached for \"straightforward\" and \"follow-up\" unprompted.")),
            grammar: AxisScore(score: 69, note: explain("Past tense slipped twice once the story moved back in time.")),
            expressiveness: AxisScore(score: 74, note: explain("Nice hedging — \"honestly\", \"to be fair\".")),
            fluency: AxisScore(score: 81, note: explain("Steady pace, and you recovered from pauses without stopping.")),
            pronunciation: nil,
            topLine: explain("A confident talk — you kept the story going and only the tenses tripped you."),
            cefrLevel: "b1")
    }

    private static func color(_ score: Int) -> Color {
        switch score {
        case ..<50: return .red
        case ..<70: return .orange
        case ..<85: return .blue
        default:    return .green
        }
    }

    private var wordRows: some View {
        VStack(spacing: 0) {
            wordRow("prepared", note: "ready in advance", mastered: true)
            Divider().padding(.leading, 44)
            wordRow("nervous", note: "worried, on edge", mastered: true)
            Divider().padding(.leading, 44)
            wordRow("straightforward", note: "easy to understand", mastered: false)
            Divider().padding(.leading, 44)
            wordRow("follow-up", note: "the next contact", mastered: false)
        }
    }

    /// `word` is material and stays in the target language; `note` is the
    /// gloss the learner READS, so it takes a localized key.
    private func wordRow(_ word: String, note: LocalizedStringKey, mastered: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(mastered ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text(word)
                    .font(.body)
                    .foregroundStyle(mastered ? Color.secondary : Color.primary)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var expressionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("From your fluent self", icon: "quote.opening")
            expressionRow("it went really well", icon: "quote.opening")
            expressionRow("I'd prepared for that", icon: "quote.opening")
            Divider().padding(.leading, 16)
            groupHeader("You said these", icon: "checkmark")
            expressionRow("to be honest", icon: "checkmark")
            expressionRow("I was worried about", icon: "checkmark")
        }
    }

    private func groupHeader(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func expressionRow(_ phrase: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.top, 3)
            Text(phrase)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var shadowRows: some View {
        VStack(spacing: 0) {
            shadowRow("It went really well — I'd prepared a lot.", score: 92, mastered: true)
            shadowRow("They asked about my last project first.", score: 78, mastered: false)
            shadowRow("I'll follow up with them on Thursday.", score: 64, mastered: false)
        }
    }

    private func shadowRow(_ line: String, score: Int, mastered: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(mastered ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            Text(line).font(.subheadline).lineSpacing(2)
            Spacer(minLength: 8)
            Text("\(score)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(mastered ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private var drillRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("Say it better", icon: "sparkles")
            drillRow(was: "It went really good.",
                     now: "It went really well.",
                     why: "\u{201C}Well\u{201D} describes how something went.")
            drillRow(was: "I was preparing a lot.",
                     now: "I'd prepared a lot.",
                     why: "The preparing finished before the interview.")
        }
    }

    /// Both sentences are material; the reason is coaching, so it takes a
    /// localized key.
    private func drillRow(was: String, now: String, why: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(was)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                Text(highlightedCorrection(now, original: was, baseFont: .subheadline))
                    .font(.subheadline)
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    // MARK: The flip-through

    private func run() async {
        let order = Array(Chapter.allCases.enumerated())
        while !Task.isCancelled {
            for (i, c) in order {
                tapping = false
                withAnimation(.easeOut(duration: 0.1)) { tapAt = i }
                withAnimation(.easeOut(duration: 0.45)) { tapping = true }
                try? await Task.sleep(nanoseconds: 260_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.25)) { chapter = c }
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                if Task.isCancelled { return }
                tapAt = nil
            }
        }
    }
}

// MARK: - 5. The measured level

/// `ProgressTab`'s estimate panel, mirrored: the band in the pixel face, what
/// it means in a sentence, and the assessment that produced it — then the
/// per-skill rows. It plays the one thing the still can't say: the next
/// assessment filling up, and the band moving when it lands.
struct LevelHero: View {
    @State private var progress: Double = 0.55
    /// The band before and after the assessment the bar is filling toward.
    @State private var reassessed = false

    private var level: String { reassessed ? "B2" : "B1" }
    /// ProgressTab's own can-do lines, quoted verbatim so the carousel and
    /// the real screen say the same sentence in every language.
    private var canDo: String {
        reassessed
            ? explain("Clear, detailed talk on many topics, including some abstract ones.")
            : explain("Familiar topics fluently enough to get by, and tell a simple story.")
    }

    var body: some View {
        VStack(spacing: 14) {
            estimatePanel
            skillsPanel
        }
        .padding(.horizontal, 18)
        .task { await run() }
    }

    private var estimatePanel: some View {
        panel {
            Text("Estimated level")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(level)
                .geistPixel(52)
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
            Text(canDo)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Next assessment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Progress's own key, so the line reads in the learner's
                    // language rather than being a second English one.
                    Text("New talk \(Int((progress * 10).rounded()))/10 min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressView(value: progress)
            }
        }
    }

    private var skillsPanel: some View {
        panel {
            Text("Across skills").font(.headline)
            skillRow("Vocabulary", value: level)
            skillRow("Fluency", value: "\u{2248}B1")
            skillRow("Grammar", value: "\u{2248}B2")
        }
    }

    private func skillRow(_ name: String, value: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func panel<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    /// Talk fills the bar; when it's full the band is re-read. Nothing here
    /// is a number the app doesn't compute — the level moves only because an
    /// assessment ran, which is the whole claim of this slide.
    private func run() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 2.4)) { progress = 1.0 }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.5)) { reassessed = true }
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                progress = 0.55
                reassessed = false
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }
}
