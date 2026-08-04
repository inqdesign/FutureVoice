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

    /// True while capturing the end of a Watch scene: the controls render
    /// their finished state (Watch again + the study handoff).
    static var previewSceneFinished = false

    /// True while capturing the expanded word card: `VocabularyView` opens
    /// its notebook sheet at full height instead of the peek.
    static var previewWordCard = false

    /// True while capturing the drill bin tray: `DrillView` opens already
    /// revealed and "mid-drag" so the drop targets are on screen.
    static var previewDrillTray = false

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
        case "vocab-card":
            // The word card at full height — the peek is the default, so a
            // screenshot can't reach the expanded state without this.
            once("vocab") { seedVocab() }
            previewWordCard = true
            return AnyView(NavigationStack { VocabularyView() })
        case "scene-end":
            previewSceneFinished = true
            let cp = Counterpart(name: "Barista", relationship: "at the cafe",
                                 background: "Makes my coffee most mornings.",
                                 conversationStyle: "friendly, quick",
                                 voicePresetId: VoicePreset.catalog[0].id)
            let dialogue = WatchDialogue(
                counterpartId: cp.id,
                scenarioTitle: "Ordering at a cafe",
                scenarioBlurb: "My order came out wrong and I point it out politely.",
                title: "The wrong order",
                turns: [
                    .init(speaker: "counterpart", text: "Hi! What can I get you today?"),
                    .init(speaker: "user", text: "A flat white, please — for here."),
                    .init(speaker: "counterpart", text: "Coming right up."),
                    .init(speaker: "user", text: "Sorry, I think this is a latte, not a flat white."),
                    .init(speaker: "counterpart", text: "Oh, you're right — let me remake that for you."),
                ],
                speakerName: cp.name)
            return AnyView(NavigationStack {
                WatchView(counterpart: cp, savedDialogue: dialogue, persist: false,
                          handoff: .init(title: "Study this", action: {}))
                    .environmentObject(appState)
            })
        case "level-header":
            // The two-line conversation title in a real inline bar.
            return AnyView(NavigationStack {
                Color(.systemBackground).ignoresSafeArea()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            LevelHeaderTitle(title: "Ordering at a cafe",
                                             level: .b1, surface: .watch)
                                .environmentObject(appState)
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Image(systemName: "xmark")
                        }
                    }
            })
        case "level-sheet":
            once("level") { seedSessions() }
            return AnyView(LevelInfoSheet(level: .b1, surface: .watch)
                .environmentObject(appState))
        case "home":
            once("home") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(ConversationHome())
        case "talk-alt":
            // Layout experiment — How-We-Feel-style Talk home (design review).
            return AnyView(TalkHomeExperiment())
        case "talk-alt-call":
            // The experiment's on-call end state (surface morphed to the pill).
            return AnyView(TalkHomeExperiment(startOnCall: true))
        case "talk-alt-demo":
            // Auto-plays the circle→pill morph — record a video of this.
            return AnyView(TalkHomeExperiment(autoDemo: true))
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
        case "practice-studying":
            once("practice-studying") { seedSessions(scored: true); seedScenarios(into: appState) }
            return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
        case "drills":
            // The SRS review sheet, incl. a legacy card whose source is a whole
            // rambling turn — verifies the render-time fragment trim.
            once("drills") { seedVocab() }
            return AnyView(DrillSheet().environmentObject(appState))
        case "drills-tray":
            // Same deck, frozen mid-drag: the bin tray is a drag-only surface,
            // so a screenshot can't reach it without this.
            once("drills") { seedVocab() }
            previewDrillTray = true
            return AnyView(DrillSheet().environmentObject(appState))
        case "watchtab":
            once("watchtab") { seedScenarios(into: appState) }
            return AnyView(WatchTab())
        case "watchtab-empty":
            // First-run Watch: no saved scenarios, so the "Likely situations"
            // chips sit high enough to capture without scrolling.
            once("watchtab-empty") {
                for s in appState.scenarios { appState.deleteScenario(id: s.id) }
            }
            return AnyView(WatchTab())
        case "intake-people":
            return AnyView(CounterpartVoiceIntakeView())
        case "deepen", "deepen-full":
            // The post-first-talk persona sheet over the real Talk home —
            // "-full" starts at the large detent to review all three fields.
            once("deepen") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(DeepenCaptureHost(expanded: name == "deepen-full")
                .environmentObject(appState))
        case "paywall":
            // The out-of-credits paywall (no trial pitch), as presented from
            // a 402 failure.
            return AnyView(PaywallView(offerTrial: false).environmentObject(appState))
        case "credits-out":
            // The in-call recovery row for a 402 — what the user sees when
            // the fluent self can't reply because credits ran out.
            return AnyView(VStack(alignment: .leading, spacing: 18) {
                DialogueLine(speaker: .user, name: "You") {
                    Text("Honestly, it went really well. I felt prepared.")
                }
                RetryReplyRow(outOfCredits: true, onRetry: {})
                Spacer()
            }
            .padding(20)
            .background(Color(.systemBackground)))
        case "composer":
            once("composer") { seedNews(into: appState); composerPreview = true }
            return AnyView(ScenarioComposerSheet(person: nil, ctaTitle: "Talk", ctaIcon: "mic.fill") { _ in }
                .environmentObject(appState))
        case "carryover":
            // The post-talk receipt with one hit from EVERY source, so the
            // "you used what you practiced" section can be judged at a glance
            // without first earning the hits in a real conversation.
            once("carryover") { carryoverSession = seedCarryoverSession() }
            return AnyView(NavigationStack {
                ConversationDetailView(session: carryoverSession ?? seedCarryoverSession())
                    .environmentObject(appState)
            })
        case "finished":
            // The finished-books shelf, populated — the real sheet, sample rows.
            return AnyView(FinishedBooksSheet(books: sampleFinishedBooks)
                .environmentObject(appState))
        case "finished-empty":
            return AnyView(FinishedBooksSheet(books: []).environmentObject(appState))
        case "progress":
            once("progress") {
                seedVocab(); seedSessions(scored: true)
                _ = seedCarryoverSession(scored: true)
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
        case "widget-progress":
            // Just the progress widget (small + medium), for design review.
            return AnyView(ProgressWidgetGallery().fontDesign(nil))
        case "widget-book":
            // Just the Continue widget (small + medium), for design review.
            return AnyView(BookWidgetGallery().fontDesign(nil))
        case "widget-streak":
            // Just the Streak widget (small + medium), for design review.
            return AnyView(StreakWidgetGallery().fontDesign(nil))
        case "tabs":
            // The full tab shell — used to review the floating Free talk pill
            // sitting above the real tab bar.
            once("tabs") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
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
        // One legacy-style card with a WHOLE rambling turn as its source, to
        // verify the render-time fragment trim keeps the card on screen.
        DrillStore.shared.save(DrillCard(
            sourcePhrase: """
            Hey I'm just wondering if there is any kind of Yeah, where people come and set \
            the same goal and Together towards to the door like English learning I see a lot of \
            people are learning and practicing Gather set the same goal like 100 days challenge \
            your 30 day challenge and they just calm and share their experience in progress. \
            I kinda like this whole community and I'm sure there are tons of community but I'm \
            just trying to. Feel something around Nirvana the app that I'm gonna be working on
            """,
            targetPhrase: "I'm trying to build something around the app that I'm going to work on.",
            reason: "Use \"build something around\" for creating a community around an app.",
            // Newest createdAt → first in the due queue (sorted newest-first),
            // so the capture opens straight on this card.
            createdAt: Date().addingTimeInterval(60), lastReviewedAt: nil,
            nextReviewAt: Date().addingTimeInterval(-7200), box: 0))
    }

    // MARK: - Sessions (Home stats + mission)

    /// Books taken all the way to mastered, for the finished-books shelf.
    static var sampleFinishedBooks: [FinishedBooksSheet.FinishedBook] {
        let day = 86_400.0
        return [
            .init(id: UUID(), title: "Pharmacy · picking up a prescription",
                  subtitle: "Scene · with Pharmacist", icon: "film.fill", itemCount: 14,
                  finishedAt: Date().addingTimeInterval(-2 * day), session: nil, scenario: nil),
            .init(id: UUID(), title: "Job interview", subtitle: "Talk",
                  icon: "bubble.left.and.bubble.right.fill", itemCount: 9,
                  finishedAt: Date().addingTimeInterval(-6 * day), session: nil, scenario: nil),
            .init(id: UUID(), title: "Café · catching up", subtitle: "Scene · with Sarah",
                  icon: "film.fill", itemCount: 14,
                  finishedAt: Date().addingTimeInterval(-13 * day), session: nil, scenario: nil),
            .init(id: UUID(), title: "Four-day work week", subtitle: "Talk",
                  icon: "bubble.left.and.bubble.right.fill", itemCount: 11,
                  finishedAt: Date().addingTimeInterval(-21 * day), session: nil, scenario: nil),
        ]
    }

    /// Held so the "carryover" route seeds once but can still hand the same
    /// session to the view it returns.
    static var carryoverSession: Session?

    /// A finished talk carrying one carryover per source. Quotes are written
    /// as the learner padding the studied item out — exactly what the matcher
    /// accepts — so what renders here is what a real hit looks like.
    /// `scored: false` leaves the scorecard off so the carryover section lands
    /// above the fold — this route exists to look at that section.
    @discardableResult
    static func seedCarryoverSession(scored: Bool = false) -> Session {
        let sessionId = UUID()
        let ended = Date().addingTimeInterval(-1_800)
        let started = ended.addingTimeInterval(-720)

        struct Seed {
            let source: Carryover.Source
            let item: String
            let quote: String
        }
        let seeds = [
            Seed(source: .drillCard, item: "I'd rather stay in tonight.",
                 quote: "Honestly I'd rather just stay in tonight, if that's okay."),
            Seed(source: .curriculumItem, item: "Could you box that up for me?",
                 quote: "Great, could you box that up for me please?"),
            Seed(source: .studyingExpression, item: "it slipped my mind",
                 quote: "Sorry, it totally slipped my mind."),
            Seed(source: .suggestion, item: "I'm really looking forward to it.",
                 quote: "Next Friday. I'm really looking forward to it."),
            Seed(source: .studyingWord, item: "commute",
                 quote: "I commuted for two hours every day back then."),
        ]

        var turns: [Turn] = []
        var carryovers: [Carryover] = []
        for (index, seed) in seeds.enumerated() {
            let at = started.addingTimeInterval(Double(index) * 90)
            turns.append(Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                              transcript: "Mm — and then what?", durationMs: 2400,
                              timestamp: at, suggestion: nil))
            let userTurn = Turn(id: UUID(), role: .user, audioURL: nil,
                                transcript: seed.quote, durationMs: 7200,
                                timestamp: at.addingTimeInterval(4), suggestion: nil)
            turns.append(userTurn)
            carryovers.append(Carryover(
                sessionId: sessionId, source: seed.source, item: seed.item,
                quote: seed.quote, turnId: userTurn.id, sourceId: UUID(),
                detectedAt: ended))
        }

        var summary = SessionSummary(
            phrasesUsed: [], newPatternsDetected: [], suggestedDrills: [],
            overallNote: "Relaxed, natural talk — and you pulled in a lot of what you'd been studying.",
            scorecard: scored ? sampleScorecard : nil)
        summary.carryovers = carryovers

        let session = Session(
            id: sessionId, userId: UUID(), targetLanguage: "en", mode: .conversation,
            topic: "Weekend plans", startedAt: started, endedAt: ended,
            turns: turns, summary: summary, origin: .free)
        SessionStore.shared.save(session)
        return session
    }

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
        // A couple of situation books for the "By scenario" shelf. Shaped like
        // real composer output: environment = the concrete prompt, summary =
        // the tidy card title, category/icon = the composer's filing — so the
        // Watch-tab card renders every field it has in captures.
        appState.saveScenario(Scenario(environment: "At the café with Sarah: catching up after months apart — she asks what I've been up to and I keep the story going.",
                                       role: "Sarah (close friend)", notes: "",
                                       lastUsedAt: Date().addingTimeInterval(-5 * 3600),
                                       curriculum: curriculum(mastered: 5), isTopic: false,
                                       category: "Cafe", categoryIcon: "cup.and.saucer.fill",
                                       summary: "Café · catching up"))
        appState.saveScenario(Scenario(environment: "At the doctor's office: describing a symptom I've had for a week and answering their follow-up questions.",
                                       role: "Doctor", notes: "",
                                       lastUsedAt: Date().addingTimeInterval(-2 * 86400),
                                       curriculum: curriculum(mastered: 3), isTopic: false,
                                       category: "Health", categoryIcon: "cross.case.fill",
                                       summary: "Doctor's visit"))
        // One brand-new 0% book so the Studying page's "Start next" section
        // renders in captures.
        appState.saveScenario(Scenario(environment: "A panel interview: introducing myself, walking through my experience, and handling curveball questions.",
                                       role: "Interviewer", notes: "",
                                       curriculum: curriculum(mastered: 0), isTopic: false,
                                       category: "Work", categoryIcon: "briefcase.fill",
                                       summary: "Job interview · panel round"))
        // …and one taken all the way (14 = every item), so the finished-books
        // shelf renders populated instead of only in its empty state.
        appState.saveScenario(Scenario(environment: "At the pharmacy: picking up a prescription, and the pharmacist has questions about my insurance.",
                                       role: "Pharmacist", notes: "",
                                       lastUsedAt: Date().addingTimeInterval(-10 * 86400),
                                       curriculum: curriculum(mastered: 14), isTopic: false,
                                       category: "Health", categoryIcon: "cross.case.fill",
                                       summary: "Pharmacy · picking up a prescription"))
    }

    // MARK: - Shadow (karaoke line)

    static var shadowTurn: Turn {
        Turn(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
             role: .fluentSelf, audioURL: nil,
             transcript: "I really appreciate you taking the time to help me.",
             durationMs: 3200, timestamp: Date(), suggestion: nil)
    }
}

/// Presents `PersonaDeepenSheet` over the seeded Talk home, exactly as the
/// post-first-talk auto-prompt does (the deepenRow shows underneath too).
private struct DeepenCaptureHost: View {
    let expanded: Bool
    @State private var showing = false

    var body: some View {
        ConversationHome()
            .sheet(isPresented: $showing) {
                PersonaDeepenSheet(startExpanded: expanded)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showing = true }
            }
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
                HStack(alignment: .top, spacing: 18) {
                    progressCard(theme: 5, size: CGSize(width: 158, height: 158), compact: true)
                    progressCard(theme: 0, size: CGSize(width: 338, height: 158), compact: false)
                }
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

    fileprivate func progressCard(theme: Int, size: CGSize, compact: Bool) -> some View {
        ProgressCard(theme: theme, todaySeconds: 7 * 60, goalMinutes: 10,
                     streakDays: 4, dueCount: 12, studyingWords: 18, studyingExpressions: 6,
                     compact: compact)
            .frame(width: size.width, height: size.height)
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

/// The progress widget alone, small + medium, across a couple of themes.
private struct ProgressWidgetGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack(alignment: .top, spacing: 18) {
                    tile(theme: 0, size: CGSize(width: 158, height: 158), compact: true)
                    tile(theme: 5, size: CGSize(width: 158, height: 158), compact: true)
                }
                tile(theme: 0, size: CGSize(width: 338, height: 158), compact: false)
                tile(theme: 3, size: CGSize(width: 338, height: 158), compact: false)
                tile(theme: 2, size: CGSize(width: 338, height: 158), compact: false)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(theme: Int, size: CGSize, compact: Bool) -> some View {
        ProgressCard(theme: theme, todaySeconds: 7 * 60, goalMinutes: 10,
                     streakDays: 4, dueCount: 12, studyingWords: 18, studyingExpressions: 6,
                     compact: compact)
            .frame(width: size.width, height: size.height)
            .background(WidgetGrid(theme: theme,
                                   shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}

/// The Continue widget alone — small + medium, a couple themes, plus the empty
/// state, for design review.
private struct BookWidgetGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack(alignment: .top, spacing: 18) {
                    tile(theme: 3, size: CGSize(width: 158, height: 158), compact: true,
                         kind: "watch", title: "Ordering at a café", subtitle: "with Barista",
                         mastered: 3, total: 8, hasBook: true)
                    tile(theme: 1, size: CGSize(width: 158, height: 158), compact: true,
                         kind: "talk", title: "Weekend plans", subtitle: "Talk",
                         mastered: 5, total: 6, hasBook: true)
                }
                tile(theme: 0, size: CGSize(width: 338, height: 158), compact: false,
                     kind: "watch", title: "Ordering at a busy café", subtitle: "with Barista",
                     mastered: 3, total: 8, hasBook: true)
                tile(theme: 2, size: CGSize(width: 338, height: 158), compact: false,
                     kind: "talk", title: "How the product launch went last week and what surprised me most",
                     subtitle: "Talk", mastered: 7, total: 9, hasBook: true)
                tile(theme: 4, size: CGSize(width: 338, height: 158), compact: false,
                     kind: "talk", title: "", subtitle: "", mastered: 0, total: 0, hasBook: false)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(theme: Int, size: CGSize, compact: Bool, kind: String,
                      title: String, subtitle: String, mastered: Int, total: Int,
                      hasBook: Bool) -> some View {
        BookCard(theme: theme, hasBook: hasBook, kind: kind, title: title,
                 subtitle: subtitle, mastered: mastered, total: total, compact: compact)
            .frame(width: size.width, height: size.height)
            .background(WidgetGrid(theme: theme,
                                   shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}

/// The Streak widget alone — small + medium, done vs at-risk, a few themes.
private struct StreakWidgetGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack(alignment: .top, spacing: 18) {
                    tile(theme: 4, size: CGSize(width: 158, height: 158), compact: true, streak: 1284, done: false)
                    tile(theme: 2, size: CGSize(width: 158, height: 158), compact: true, streak: 7, done: true)
                }
                tile(theme: 0, size: CGSize(width: 338, height: 158), compact: false, streak: 1284, done: false)
                tile(theme: 3, size: CGSize(width: 338, height: 158), compact: false, streak: 7, done: true)
                tile(theme: 1, size: CGSize(width: 338, height: 158), compact: false, streak: 0, done: false)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(theme: Int, size: CGSize, compact: Bool, streak: Int, done: Bool) -> some View {
        StreakCard(theme: theme, streakDays: streak, doneToday: done, compact: compact)
            .frame(width: size.width, height: size.height)
            .background(WidgetGrid(theme: theme,
                                   shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}
#endif
