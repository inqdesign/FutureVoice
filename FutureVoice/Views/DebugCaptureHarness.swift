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

    /// True while capturing the scenario composer: it pre-selects a category
    /// and injects sample AI chips so the layout renders offline.
    static var composerPreview = false
    static let sampleCategoryIdeas: [SuggestedTopic] = [
        .init(title: "order came out wrong", blurb: "At a cafe: my order came out wrong and I want to point it out politely."),
        .init(title: "asking for a recommendation", blurb: "At a cafe: I can't decide, so I ask the barista what they'd recommend."),
        .init(title: "the wifi is down", blurb: "At a cafe: the wifi is down and I ask the barista for the password / a fix."),
        .init(title: "card reader won't work", blurb: "At a cafe: the card reader keeps failing and I sort out paying without holding up the line."),
        .init(title: "running into an old colleague", blurb: "At a cafe: I run into a former colleague at the next table and we catch up."),
        .init(title: "keeping a table while I step out", blurb: "At a cafe: I ask someone to watch my table while I take a quick call."),
        .init(title: "complimenting the latte art", blurb: "At a cafe: I compliment the barista's latte art and chat a little."),
        .init(title: "a mix-up with someone's name", blurb: "At a cafe: they called the wrong name for my drink and I sort it out."),
    ]

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
            once("home") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(ConversationHome())
        case "watch":
            // The Watch tab folded into Practice's shelves — capture that.
            once("watch") { seedScenarios(into: appState) }
            return AnyView(PracticeTab())
        case "practice-talk":
            once("practice-talk") { seedSessions(scored: true); seedScenarios(into: appState) }
            return AnyView(PracticeTab(initialShelf: .talk).environmentObject(appState))
        case "practice-watch":
            once("practice-watch") { seedSessions(scored: true); seedScenarios(into: appState) }
            return AnyView(PracticeTab(initialShelf: .watch).environmentObject(appState))
        case "watchtab":
            once("watchtab") { seedScenarios(into: appState) }
            return AnyView(WatchTab())
        case "intake-people":
            return AnyView(CounterpartVoiceIntakeView())
        case "builder":
            // Renders the sheet's content full-screen (no host to present it).
            return AnyView(SituationBuilderSheet(root: WatchTab.situationTree[0]) { _ in })
        case "composer":
            once("composer") { seedNews(into: appState); composerPreview = true }
            return AnyView(ScenarioComposerSheet(person: nil, ctaTitle: "Talk", ctaIcon: "mic.fill") { _ in }
                .environmentObject(appState))
        case "progress":
            once("progress") {
                seedVocab(); seedSessions(scored: true)
                // A pooled weekly read so the big CEFR level (not "building")
                // renders for design capture.
                let report = WeeklyReport(
                    id: UUID(),
                    periodStart: Date().addingTimeInterval(-7 * 86_400),
                    periodEnd: Date(),
                    sessionCount: 6, targetLanguage: "en",
                    newExpressions: [], repeatedMistakes: [], suggestedExpressions: [],
                    summary: "Steady, confident week — your range is widening.",
                    cefrLevel: "b2", generatedAt: Date())
                WeeklyReportStore.shared.save(report)
                appState.weeklyReports = [report]
            }
            return AnyView(ProgressTab().environmentObject(appState))
        case "shadow":
            once("shadow") { captureShadow = true }
            return AnyView(NavigationStack {
                ShadowDrillView(turn: shadowTurn, targetLanguage: "en")
            })
        case "expr":
            once("expr") { seedVocab() }
            return AnyView(NavigationStack { ExpressionsView() })
        case "score":
            once("score") { seedVocab() }
            return AnyView(NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Last talk").font(.caption).foregroundStyle(.secondary)
                        ScorecardView(scorecard: sampleScorecard)
                            .padding(18)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(.secondarySystemBackground)))
                    }
                    .padding(20)
                }
                .navigationTitle("Scorecard")
                .navigationBarTitleDisplayMode(.inline)
            })
        case "glow":
            // The call button's pixel surface across its states, for design
            // review screenshots (the live surface animates; this freezes
            // representative frames side by side).
            return AnyView(GlowGallery())
        case "widget":
            // Design-review of the single-word widget card. NOTE: the app's
            // global .fontDesign(.rounded) forces the pixel title font to
            // render rounded HERE — the real widget target has no such
            // ancestor, so on the home screen it shows GeistPixel as designed.
            return AnyView(WidgetGallery().fontDesign(nil))
        case "tabs":
            // The full tab shell — used to review the floating Free talk pill
            // sitting above the real tab bar.
            once("tabs") { seedVocab(); seedSessions(); seedScenarios(into: appState) }
            return AnyView(RootTabView())
        case "talkdetail", "talkdetail-mid", "talkdetail-low":
            // The ONE session detail page in post-talk mode — exactly what
            // the wrap-up sheet presents when a talk ends. Lists don't honor
            // an initial scroll offset, so the "-mid"/"-low" variants blank
            // out the UPPER sections' data instead, letting screenshots reach
            // the lower ones.
            once("talkdetail") { seedVocab() }
            var s = talkDetailSession
            if name != "talkdetail" {
                s.summary?.scorecard = nil
                s.summary?.overallNote = ""
            }
            if name == "talkdetail-low" {
                // No substantial fluent lines → the fresh-shadow list and
                // word chips drop out; the page starts at Expressions.
                s.turns = s.turns.filter { $0.role == .user }
                s.summary?.newWordsUsed = []
            }
            let session = s
            return AnyView(NavigationStack {
                ConversationDetailView(
                    session: session,
                    postTalk: .init(onDone: {}, onStartNew: {}))
            })
        case "themes":
            // The settings grid of Futureself themes, in its List habitat.
            return AnyView(NavigationStack {
                List {
                    Section {
                        FutureselfThemePicker()
                    } header: {
                        Text("Appearance")
                    } footer: {
                        Text("Future self is the pixel surface behind every call button — tap a theme to feel it.")
                    }
                }
                .navigationTitle("Me")
            })
        default:
            return nil
        }
    }

    static var sampleScorecard: SessionScorecard {
        SessionScorecard(
            vocabulary: AxisScore(score: 82, note: "Reached for precise, specific words."),
            grammar: AxisScore(score: 71, note: "A few article and tense slips to tidy."),
            expressiveness: AxisScore(score: 68, note: "Getting more natural and idiomatic."),
            fluency: AxisScore(score: 74, note: "Steady pace, fewer long pauses."),
            pronunciation: AxisScore(score: 80, note: "Clear, with good linking."),
            topLine: "Confident, natural talk — tighten a few articles.",
            cefrLevel: "b1")
    }

    /// One fully-populated finished talk — every section of the session
    /// detail page has material (scorecard + grammar slips, new words,
    /// expressions, say-it-better, suggestions → shadow lines, drill next).
    static var talkDetailSession: Session {
        let started = Date().addingTimeInterval(-900)
        let turns = [
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "So — how did the interview go yesterday?", durationMs: 3200,
                 timestamp: started, suggestion: nil),
            Turn(id: UUID(), role: .user, audioURL: nil,
                 transcript: "Honestly, it go really well. I felt prepared.", durationMs: 62_000,
                 timestamp: started.addingTimeInterval(6),
                 suggestion: TurnSuggestion(alternative: "Honestly, it went really well — I felt prepared.",
                                            reason: "past tense")),
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "That's a compelling perspective — you clearly took the initiative to prioritize what mattered.", durationMs: 4200,
                 timestamp: started.addingTimeInterval(70), suggestion: nil),
            Turn(id: UUID(), role: .user, audioURL: nil,
                 transcript: "How relaxed I stayed, even on hard question.", durationMs: 58_000,
                 timestamp: started.addingTimeInterval(80),
                 suggestion: TurnSuggestion(alternative: "How relaxed I stayed, even on the hard questions.",
                                            reason: "article + plural"))
        ]
        var summary = SessionSummary(
            phrasesUsed: [PhraseFeedback(userSaid: "it go really well",
                                         fluentAlternative: "it went really well",
                                         reason: "past tense")],
            newPatternsDetected: [],
            suggestedDrills: ["I'd say the trade-off was worth it.",
                              "Looking back, I would have prepared differently."],
            overallNote: "Confident, natural talk — tighten a few articles.",
            scorecard: sampleScorecard)
        summary.newWordsUsed = ["prepared", "relaxed", "interview"]
        summary.expressionsUsed = ["felt prepared"]
        summary.grammarIssues = [
            GrammarIssue(quote: "Honestly, it go really well.",
                         correction: "Honestly, it went really well.",
                         note: "past tense needed"),
            GrammarIssue(quote: "even on hard question",
                         correction: "even on the hard questions",
                         note: "article + plural")
        ]
        return Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            userId: UUID(), targetLanguage: "en", mode: .conversation,
            topic: "Job interview", startedAt: started,
            endedAt: started.addingTimeInterval(600),
            turns: turns, summary: summary)
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

        // A few review cards due NOW, so Home's "Review N cards" action shows.
        let due: [(String, String, String)] = [
            ("it go really well", "it went really well", "past tense"),
            ("I very like it", "I really like it", "adverb choice"),
            ("more easy", "easier", "comparative form"),
        ]
        for (src, tgt, why) in due {
            DrillStore.shared.save(DrillCard(
                sourcePhrase: src, targetPhrase: tgt, reason: why,
                createdAt: Date(), lastReviewedAt: nil,
                nextReviewAt: Date().addingTimeInterval(-3600), box: 0))
        }
    }

    // MARK: - Sessions (Home stats + mission)

    static func seedSessions(scored: Bool = false) {
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
            // scored: attach a scorecard summary so ProgressTab's assessed
            // branch (chip header + level pages) renders instead of the
            // empty state.
            let summary = scored ? SessionSummary(
                phrasesUsed: [], newPatternsDetected: [], suggestedDrills: [],
                overallNote: "Confident, natural talk — tighten a few articles.",
                scorecard: sampleScorecard) : nil
            // Vary origin across the three so the Talk shelf shows every badge.
            let origin: SessionOrigin = [.free, .news, .scenario][day % 3]
            let topic: String? = origin == .free ? nil
                : (origin == .news ? "Four-day work week" : "Job interview")
            SessionStore.shared.save(Session(
                id: UUID(), userId: uid, targetLanguage: "en", mode: .conversation,
                topic: topic, startedAt: started, endedAt: ended,
                turns: turns, summary: summary, origin: origin))
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

    /// Interests + a cached news pool, so the home capture renders the news
    /// card rail offline (no edge-function call).
    static func seedNews(into appState: AppState) {
        let interests = ["ai / tech", "cooking"]
        if var p = appState.persona {
            if p.interests.isEmpty { p.interests = interests; appState.persona = p }
        } else {
            appState.persona = UserPersona(
                displayName: "Alex", city: "Munich", country: "Germany",
                lengthOfStay: "", occupation: "", household: "",
                interests: interests, situations: [], freeNotes: "", updatedAt: Date())
        }
        let effective = appState.persona?.interests ?? interests
        NewsTopicStore.shared.save([
            SuggestedTopic(title: "Did you hear about OpenAI's model hacking a company?",
                           blurb: "An AI model reportedly breached another tech firm, leading to discussions about controlling autonomous agents.",
                           category: "ai / tech"),
            SuggestedTopic(title: "Have you heard beef tallow is making a comeback?",
                           blurb: "The traditional cooking fat is seeing a resurgence in restaurants and home kitchens.",
                           category: "cooking"),
            SuggestedTopic(title: "Did you see the home robot folding laundry?",
                           blurb: "A startup demoed a household robot completing chores end to end.",
                           category: "ai / tech"),
        ], interests: effective)
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

/// Every state of the call button's pixel surface, in the exact pill styling
/// ConversationView uses, so a single screenshot reviews the whole design.
private struct GlowGallery: View {
    var body: some View {
        VStack(spacing: 28) {
            pill(.idle, level: 0, symbol: "mic.fill", caption: "idle")
            pill(.listening, level: 0.35, symbol: "stop.fill", caption: "listening · quiet")
            pill(.listening, level: 0.95, symbol: "stop.fill", caption: "listening · loud")
            pill(.thinking, level: 0, symbol: "ellipsis", caption: "thinking")
            pill(.speaking, level: 0.7, symbol: "waveform", caption: "speaking")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func pill(_ mode: Futureself.Mode, level: Float,
                      symbol: String, caption: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Futureself(mode: mode, level: level)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 156, height: 64)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The two home-screen widgets at their real families — the shared pinboard
/// render (cork + stickies), exactly what `StudyWidgetView` composes, for
/// design review (the extension can't be screenshotted headlessly).
private struct WidgetGallery: View {
    // 0 blue · 1 mono · 2 emerald · 3 amber · 4 coral · 5 aqua
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack(alignment: .top, spacing: 18) {
                    freeTalkCard(theme: 0)
                    freeTalkCard(theme: 4)
                    freeTalkCard(theme: 3)
                }
                HStack(alignment: .top, spacing: 18) {
                    card(.words, word: "Correspondent", note: "C1", theme: 0,
                         size: CGSize(width: 158, height: 158), compact: true)
                    card(.words, word: "Negotiate", note: "B1", theme: 2,
                         size: CGSize(width: 338, height: 158), compact: false)
                }
                card(.expressions, word: "Walk me through it", note: "", theme: 3,
                     size: CGSize(width: 338, height: 158), compact: false)
                card(.words, word: "Meticulous", note: "C1", theme: 4,
                     size: CGSize(width: 338, height: 354), compact: false)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func freeTalkCard(theme: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(WidgetTheme.vivid(theme))
            Text("Let's talk").font(pixelFont(16)).foregroundStyle(WidgetTheme.vivid(theme))
        }
        .frame(width: 158, height: 158)
        .background(WidgetGrid(theme: theme,
                               shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    private func card(_ section: StudyWidgetSection, word: String, note: String, theme: Int,
                      size: CGSize, compact: Bool) -> some View {
        let nav: CGFloat = compact ? 30 : 38
        return StudyCard(label: section.shortLabel, word: word,
                         note: section.showsNote ? note : "",
                         emptyText: "", compact: compact,
                         wordColor: WidgetTheme.vivid(theme)) {
            NavCircle(direction: .prev, size: nav)
        } next: {
            NavCircle(direction: .next, size: nav)
        }
        .frame(width: size.width, height: size.height)
        .background(WidgetGrid(theme: theme,
                               shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}
#endif
