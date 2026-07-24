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

// MARK: - 1. Talk

struct TalkHero: View {
    struct Line: Identifiable {
        let id: Int
        let speaker: DialogueSpeaker
        let text: String
    }

    /// Many short exchanges, rotated one per loop — so the transcript feels
    /// like a living stream of different calls, not one canned demo.
    private static let conversations: [[Line]] = [
        [Line(id: 0, speaker: .other, text: "So — how'd the interview go?"),
         Line(id: 1, speaker: .user,  text: "Honestly? It went really well."),
         Line(id: 2, speaker: .other, text: "That's huge. What surprised you most?")],

        [Line(id: 0, speaker: .other, text: "You sound lighter today."),
         Line(id: 1, speaker: .user,  text: "I finally booked the trip to Lisbon."),
         Line(id: 2, speaker: .other, text: "No way! When do you leave?")],

        [Line(id: 0, speaker: .user,  text: "Can I run something by you?"),
         Line(id: 1, speaker: .other, text: "Always. What's on your mind?"),
         Line(id: 2, speaker: .user,  text: "I'm thinking of switching teams at work.")],

        [Line(id: 0, speaker: .other, text: "How was dinner with her parents?"),
         Line(id: 1, speaker: .user,  text: "Nerve-wracking — but they were lovely."),
         Line(id: 2, speaker: .other, text: "See? You worried over nothing.")],

        [Line(id: 0, speaker: .other, text: "Did you make it to the gym?"),
         Line(id: 1, speaker: .user,  text: "I did — first time in weeks."),
         Line(id: 2, speaker: .other, text: "Proud of you. How'd it feel?")],

        [Line(id: 0, speaker: .user,  text: "I keep freezing when they speak fast."),
         Line(id: 1, speaker: .other, text: "Then let's slow it down together."),
         Line(id: 2, speaker: .user,  text: "Okay. That actually helps.")],
    ]

    @State private var convo = 0
    @State private var visible = 0
    @State private var mode: Futureself.Mode = .idle
    @State private var level: Float = 0

    private var lines: [Line] { Self.conversations[convo] }

    var body: some View {
        VStack(spacing: 0) {
            // The call transcript — same DialogueLine, same .call scale as the
            // live conversation screen. Bottom-aligned like a real call feed.
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                ForEach(lines.prefix(visible)) { line in
                    DialogueLine(speaker: line.speaker,
                                 name: line.speaker.isUser ? "You" : "Future self",
                                 scale: .call) {
                        Text(line.text)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 24)
            .clipped()

            // The mic pill — exact chrome from ConversationView's call button.
            ZStack {
                Futureself(mode: mode, level: level)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 156, height: 64)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            .padding(.top, 22)
            .padding(.bottom, 6)
        }
        .task { await run() }
    }

    private var symbol: String {
        switch mode {
        case .idle:      return "mic.fill"
        case .listening: return "stop.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        }
    }

    /// One call turn, looped over a fresh conversation each time: fluent self
    /// speaks → you answer (listening ignites) → thinking sweep → the reply
    /// blooms → advance to the next conversation.
    private func run() async {
        while !Task.isCancelled {
            set(mode: .idle, level: 0, visible: 0)
            await pause(0.7)
            let opensWithUser = lines.first?.speaker.isUser ?? false
            // First line.
            set(mode: opensWithUser ? .listening : .speaking,
                level: opensWithUser ? 0.8 : 0.65, visible: 1)
            await pause(opensWithUser ? 1.4 : 1.8)
            // Second line — the other party.
            set(mode: opensWithUser ? .thinking : .listening,
                level: opensWithUser ? 0 : 0.5, visible: 1)
            await pause(0.5)
            set(mode: opensWithUser ? .speaking : .listening,
                level: opensWithUser ? 0.7 : 0.85, visible: 2)
            await pause(1.7)
            // Third line.
            set(mode: .thinking, level: 0, visible: 2)
            await pause(1.0)
            set(mode: .speaking, level: 0.7, visible: 3)
            await pause(2.1)
            // Next conversation.
            withAnimation(.easeInOut(duration: 0.4)) { visible = 0 }
            await pause(0.35)
            convo = (convo + 1) % Self.conversations.count
        }
    }

    private func set(mode: Futureself.Mode, level: Float, visible: Int) {
        withAnimation(.spring(duration: 0.45)) {
            self.mode = mode
            self.level = level
            self.visible = visible
        }
    }

    private func pause(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
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
                      (.other, "Ooh, feeling adventurous. How about a cortado?")]),

        Scene(name: "Dr. Park", relationship: "Family doctor", title: "The check-up",
              lines: [(.other, "So, what brings you in today?"),
                      (.user,  "I've had a cough that won't quite go away."),
                      (.other, "How long has it been lingering?")]),

        Scene(name: "Mina", relationship: "Team lead", title: "Asking for time off",
              lines: [(.other, "You wanted to chat before standup?"),
                      (.user,  "Yeah — I'd like the last week of March off."),
                      (.other, "Let me check the sprint, but that should work.")]),

        Scene(name: "Alex", relationship: "Landlord", title: "The leaky faucet",
              lines: [(.other, "You mentioned something needs fixing?"),
                      (.user,  "The kitchen tap's been dripping all week."),
                      (.other, "I'll send someone over on Thursday.")]),
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
                    DialogueLine(speaker: line.speaker,
                                 name: line.speaker.isUser ? "You" : s.name,
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
    /// The same sample line the shadow capture uses, with the evenly-spaced
    /// timings `ShadowDrillView` synthesizes offline (380 ms per word).
    private static let words = "I really appreciate you taking the time to help me."
        .split(separator: " ").map(String.init)
    private static let perWordMs = 380
    private static let selected = 2...4          // "appreciate you taking"
    private static let cycleMs = words.count * perWordMs + 1400

    @State private var cycleStart = Date()

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Target line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Self.words.count) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                // Karaoke words — real FlowLayout, and ShadowDrillView's exact
                // colour grammar: passed = primary, current = accent,
                // upcoming = secondary; the practiced phrase carries the
                // accent selection wash.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(cycleStart) * 1000)
                    let nowMs = elapsed % Self.cycleMs
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
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            // The player's controls, at a glance: loop the phrase, slow it down.
            HStack(spacing: 10) {
                Label("Loop", systemImage: "repeat")
                    .foregroundStyle(.tint)
                Text("0.75×")
                Label("Your voice", systemImage: "waveform")
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .onAppear { cycleStart = Date() }
    }

    private func color(at i: Int, nowMs: Int) -> Color {
        let start = i * Self.perWordMs
        let end = start + Self.perWordMs
        if nowMs >= end   { return .primary }
        if nowMs >= start { return .accentColor }
        return .secondary
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
