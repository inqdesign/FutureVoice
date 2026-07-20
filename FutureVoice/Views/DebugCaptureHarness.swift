#if DEBUG
import SwiftUI

/// Screenshot capture harness (DEBUG only — never compiled into release).
///
/// Seeds representative sample data into the real stores, then routes the app
/// straight to the REAL screen (VocabularyView, ConversationHome, WatchTab,
/// ShadowDrillView) so the simulator can capture genuine UI — not a mockup —
/// for the Welcome carousel. Launch with `-capture <name>`:
///   vocab · home · watch · shadow
@MainActor
enum DebugCapture {
    private static var seeded = Set<String>()

    /// True while capturing the Shadow screen: ShadowDrillView then synthesizes
    /// evenly-spaced karaoke timings locally and skips the voice-clone/network
    /// path, so the timeline renders offline for the screenshot.
    static var captureShadow = false

    /// Idempotent per name — the resolver may evaluate more than once.
    private static func once(_ name: String, _ work: () -> Void) {
        guard !seeded.contains(name) else { return }
        seeded.insert(name)
        work()
    }

    // MARK: - Routing

    /// Seeds synchronously (before the child view's onAppear reads the stores),
    /// then returns the REAL screen. nil for an unknown name.
    static func view(for name: String, appState: AppState) -> AnyView? {
        switch name {
        case "vocab":
            once("vocab") { seedVocab() }
            return AnyView(NavigationStack { VocabularyView() })
        case "home":
            once("home") { seedVocab(); seedSessions() }
            return AnyView(ConversationHome())
        case "watch":
            once("watch") { seedScenarios(into: appState) }
            return AnyView(WatchTab())
        case "shadow":
            once("shadow") { captureShadow = true }
            return AnyView(NavigationStack {
                ShadowDrillView(turn: shadowTurn, targetLanguage: "en")
            })
        default:
            return nil
        }
    }

    // MARK: - Vocabulary + expressions

    static func seedVocab() {
        let texts = [
            "I really appreciate you taking the time to meet me today.",
            "Honestly I appreciate how straightforward the whole process was.",
            "My commute is long so I usually catch up on podcasts.",
            "The commute gave me time to genuinely think it through.",
            "We had to negotiate the deadline because the scope grew.",
            "I felt a little overwhelmed but I managed to reschedule everything.",
            "My colleague suggested we reschedule the meeting to Friday.",
            "I didn't hesitate to ask for help when I got stuck.",
            "Let me walk you through the reasoning behind this decision.",
            "It turned out to be more nuanced than I first assumed.",
            "I want to sound confident without being arrogant.",
            "She handled the awkward moment with a lot of grace."
        ]
        _ = VocabStore.shared.ingest(sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                                     userTexts: texts)
        for w in ["appreciate", "genuinely", "negotiate", "overwhelmed",
                  "straightforward", "reschedule", "nuanced", "hesitate"] {
            VocabStore.shared.addStudying(w)
        }
        _ = VocabStore.shared.addExpression("catch up on")
        _ = VocabStore.shared.addExpression("walk you through")
        _ = VocabStore.shared.addExpression("turned out to be")
    }

    // MARK: - Sessions (Home stats + mission)

    static func seedSessions() {
        let uid = UUID()
        for day in 0..<3 {
            let ended = Date().addingTimeInterval(Double(-day) * 86_400 + 3_600)
            let started = ended.addingTimeInterval(-600)
            let turns = [
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "So — how did the interview go?", durationMs: 3200,
                     timestamp: started, suggestion: nil),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "Honestly, it went really well. I felt prepared.", durationMs: 62_000,
                     timestamp: started.addingTimeInterval(6), suggestion: nil),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "That's great. What surprised you most?", durationMs: 2600,
                     timestamp: started.addingTimeInterval(70), suggestion: nil),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "How relaxed I stayed, even on the hard questions.", durationMs: 58_000,
                     timestamp: started.addingTimeInterval(80), suggestion: nil)
            ]
            SessionStore.shared.save(Session(
                id: UUID(), userId: uid, targetLanguage: "en", mode: .conversation,
                topic: "Job interview", startedAt: started, endedAt: ended,
                turns: turns, summary: nil))
        }
    }

    // MARK: - Watch (curriculum books)

    private static func item(_ text: String, _ note: String, mastered: Bool = false) -> ScenarioCurriculum.Item {
        ScenarioCurriculum.Item(text: text, note: note,
                                masteredAt: mastered ? Date() : nil)
    }

    /// A 14-item curriculum with the first `mastered` items checked off, so
    /// cards show varied progress bars.
    private static func curriculum(mastered: Int) -> ScenarioCurriculum {
        let words = ["appreciate", "straightforward", "negotiate", "reschedule", "nuanced", "overwhelmed"]
        let exprs = ["catch up on", "walk you through", "turned out to be", "a bit of a stretch"]
        let lines = [
            "I really appreciate you making the time.",
            "Let me walk you through what happened.",
            "Honestly, it turned out better than expected.",
            "Could we reschedule for later this week?"
        ]
        var n = mastered
        func take(_ texts: [String]) -> [ScenarioCurriculum.Item] {
            texts.map { t in defer { n -= 1 }; return item(t, "", mastered: n > 0) }
        }
        var c = ScenarioCurriculum()
        c.words = take(words)
        c.expressions = take(exprs)
        c.shadowLines = take(lines)
        c.dialogueTitle = "The scene"
        return c
    }

    static func seedScenarios(into appState: AppState) {
        seedVocab()
        // Clear any scenarios left over from a previous capture run, so the
        // grid shows exactly these four distinct books (no accumulation).
        for s in appState.scenarios { appState.deleteScenario(id: s.id) }

        let topics: [(String, Int)] = [
            ("Germany weighs a nationwide four-day work week", 4),
            ("AI tutors are reshaping how adults learn languages", 8),
            ("Why night trains are quietly making a comeback in Europe", 2),
            ("The unexpected revival of handwritten letters", 11)
        ]
        for (title, done) in topics {
            appState.saveScenario(Scenario(environment: title, role: "the discussion",
                                           notes: "", curriculum: curriculum(mastered: done),
                                           isTopic: true))
        }
        // A couple of situation books for the "By scenario" shelf.
        appState.saveScenario(Scenario(environment: "Café · catching up",
                                       role: "Sarah (close friend)", notes: "",
                                       curriculum: curriculum(mastered: 5), isTopic: false))
        appState.saveScenario(Scenario(environment: "Doctor's visit", role: "Doctor",
                                       notes: "", curriculum: curriculum(mastered: 3), isTopic: false))
    }

    // MARK: - Shadow (karaoke line)

    static var shadowTurn: Turn {
        Turn(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
             role: .fluentSelf, audioURL: nil,
             transcript: "I really appreciate you taking the time to help me.",
             durationMs: 3200, timestamp: Date(), suggestion: nil)
    }
}
#endif
