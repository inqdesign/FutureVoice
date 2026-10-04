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

    /// Which running state of `SayItAgainView` to park on for a
    /// screenshot ("reading" / "done"), since a capture run has no mic.
    static var sayItAgainStage: String?

    /// True while capturing `home-scenarios`: Talk's discover block opens on
    /// its Everyday chip (the ready-made situations).
    static var previewScenariosTab = false

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

    /// Seconds to stall every dictionary lookup, so a capture run can hold the
    /// loading state open. 0 = off (every case except `vocab-loading`).
    static var slowLookupSeconds = 0

    /// Make every dictionary lookup fail, so the retry affordance can be seen
    /// (offline it fails anyway, but not deterministically enough to shoot).
    static var failLookups = false

    /// Dictionary entry every lookup returns instead of hitting the network.
    /// nil = off. A capture run isn't signed in, so a real lookup always
    /// fails and the study card shows "—" — useless for checking a layout
    /// whose whole question is how much of a full entry fits.
    static var stubWordEntry: WordEntry?

    /// A deliberately FAT entry — three senses, two examples, definitions
    /// long enough to wrap. The worst realistic case for the study card, and
    /// the one that decides what a small screen can show.
    static let fatWordEntry = WordEntry(
        pos: "Adverb",
        senses: [
            .init(pos: "Adverb", meaning: "In a loose or not taut manner; without tension.", note: nil),
            .init(pos: "Adverb", meaning: "In a careless, lazy, or inefficient way.", note: nil),
            .init(pos: "Adverb", meaning: "Of trade or business, in a way that is slow or lacking in activity.", note: nil),
        ],
        examples: [
            .init(text: "The rope hung slackly from the pole.",
                  meaning: "The rope was not pulled tight and hung loosely from the pole."),
            .init(text: "He slackly completed his tasks, missing several deadlines.",
                  meaning: "He finished his tasks carelessly and inefficiently, failing to meet several deadlines."),
        ],
        phrases: [],
        properNoun: nil
    )

    /// True while capturing the drill bin tray: `DrillView` opens already
    /// revealed and "mid-drag" so the drop targets are on screen.
    static var previewDrillTray = false

    /// True while capturing the in-call settings sheet: `ConversationView`
    /// raises it on appear, since a screenshot run can't tap the button.
    static var previewCallSettings = false

    /// Which item kind a freshly built weekly test opens on, so each kind's
    /// screen can be photographed. nil = the engine's own order.
    static var weeklyTestKind: WeeklyTestItem.Kind?
    /// Pre-answer the first item: true = the right answer, false = a wrong
    /// one, so the graded state can be photographed.
    static var weeklyTestAnswer: Bool?

    /// Same trick for the study deck, with the cancel target lit: a drag can
    /// only be photographed from inside itself, and XCUITest has no way to
    /// hold one open while the camera runs.
    static var previewStudyTray = false

    /// True while capturing a folder list: `DrillView` opens with the
    /// Tomorrow folder sheet already presented — chips are tap-only.
    static var previewDrillFolder = false

    /// True while capturing the scenario composer: it pre-selects a category
    /// and injects sample AI chips so the layout renders offline.
    static var composerPreview = false

    /// The scenario seeded for the "book" capture, so the route can open its
    /// detail page directly.
    static var bookScenarioId: UUID?
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

    /// A profile with both halves filled: the typed fields and three lines
    /// the fluent self picked up, classified the way the summary call would.
    private static func seedSamplePersona(_ appState: AppState) {
        var p = UserPersona.empty
        p.displayName = "Eunggyu"
        p.city = "Munich"
        p.country = "Germany"
        p.lengthOfStay = "3 years"
        p.occupation = "Solo founder of an AI app for language learners"
        p.household = "Wife and 4yo daughter at Kita"
        p.interests = ["AI / tech", "parenting", "language learning"]
        p.situations = ["Kita / school", "Client calls", "Daily small talk"]
        p.freeNotes = "Thinking about moving back next year."
        p.metAt = Calendar.current.date(byAdding: .day, value: -20, to: Date())
        let day: TimeInterval = 86_400
        p.learnedNotes = [
            PersonaNote(text: "매주 토요일 아침 이자르 강변에서 달린다",
                        sessionId: nil, learnedAt: Date().addingTimeInterval(-9 * day), share: .all,
                        heard: "Saturday mornings I run along the Isar, every week", why: "취미"),
            PersonaNote(text: "유치원생 딸이 하나 있다",
                        sessionId: nil, learnedAt: Date().addingTimeInterval(-5 * day), share: .gist,
                        heard: "I dropped my daughter off at Kita this morning", gist: "어린 아이를 키우는 부모",
                        why: "가족"),
            PersonaNote(text: "투자자 미팅이 잘 안 풀려서 자금 압박이 있다",
                        sessionId: nil, learnedAt: Date().addingTimeInterval(-2 * day), share: .nothing,
                        heard: "the investor meeting didn't go well, money is getting tight",
                        gist: "회사를 키우는 중", why: "돈 이야기"),
            PersonaNote(text: "서울 다녀와서 시차 적응 중",
                        sessionId: nil, learnedAt: Date().addingTimeInterval(-1 * day), share: .nothing,
                        kind: .now, heard: "I got back from Seoul on Sunday and I'm still waking up at 4",
                        gist: "최근 여행을 다녀옴", why: "지금 상황"),
        ]
        PersonaStore.shared.save(p)
        appState.persona = p
        // The intro is WRITTEN by a Gemini call, and a capture run has no
        // session — so without this the two intro routes would render the
        // offline fallback (the old concatenation) and the screenshots would
        // review a screen nobody sees. This is the paragraph the real prompt
        // returned for exactly this persona on 2026-09-25
        // (`scripts/public-intro-probe.py`), seeded into the composer's own
        // cache: same view, same code path, a fixture for the one thing a
        // capture run can't reach — like `sampleLightAccount` above.
        PublicIntroComposer.save("""
            Hi, I am Eunggyu, and I have been living here in Munich for a while \
            now working on my own AI app for language learning. Since I am quite \
            interested in technology and raising young children, I spend most of \
            my time balancing those two worlds. My daily life usually involves \
            picking up my kids from school or handling client calls, so I am \
            always looking for ways to practice better communication. When I \
            have some free time, I really enjoy going for a long run along the \
            Isar river to clear my head.
            """, for: PublicIntroComposer.sources(p, language: appState.targetLanguage))
    }

    /// Idempotent per name — the resolver may evaluate more than once.
    /// Two written scripts and one scored take on the bundled script.
    @MainActor
    private static func seedSpeech(_ appState: AppState) {
        let store = SpeechStore.shared
        store.reload()
        let lang = appState.targetLanguage
        let written = SpeechScript(
            id: UUID(), title: "Marie Curie, twice a Nobel winner", genre: .person, topic: "Marie Curie",
            body: "Marie Curie is the only person to win Nobel Prizes in two different sciences. Born in Warsaw in 1867, she moved to Paris to study, at a time when few universities admitted women.\n\nWith her husband Pierre, she discovered two new elements, polonium and radium. She coined the word radioactivity.\n\nHer notebooks are still radioactive today, and are kept in lead-lined boxes.",
            summary: "The scientist who discovered radium, and the only person with Nobels in two sciences.",
            keyTerms: [SpeechKeyTerm(term: "radioactivity", meaning: "Strahlung · 방사능"),
                       SpeechKeyTerm(term: "lead-lined", meaning: "lined with lead")],
            sources: ["Nobel Prize Outreach", "Encyclopaedia Britannica"],
            language: lang, targetSeconds: 60, createdAt: Date().addingTimeInterval(-3600), isBuiltIn: false)
        let news = SpeechScript(
            id: UUID(), title: "Why the sky is blue", genre: .explainer, topic: "",
            body: "Sunlight looks white, but it is a mix of every colour. Blue light has a short wavelength, so air molecules scatter it far more than red.",
            summary: "", keyTerms: [], sources: ["NASA"], language: lang, targetSeconds: 30,
            createdAt: Date().addingTimeInterval(-86400), isBuiltIn: false)
        store.add(news)
        store.add(written)
        guard let builtIn = store.scripts.first(where: \.isBuiltIn) else { return }
        let metrics = SpeechMetrics(
            accuracy: 91, rate: 168, rateLow: 120, rateHigh: 160, paceScore: 90,
            pausesAtBreaks: 7, breaks: 9, hesitations: 1, pauseScore: 70,
            fillers: 3, fillerScore: 82, steadiness: 74,
            missed: ["in a fraction of a millisecond", "rising and falling"], overall: 84)
        let take = SpeechTake(
            id: UUID(), scriptId: builtIn.id, createdAt: Date(), durationSeconds: 62,
            audioFilename: "missing.wav", videoFilename: nil,
            transcript: "Good evening. Tonight, a question most of us never um stop to ask: how do noise-cancelling headphones actually work?",
            metrics: metrics,
            coaching: SpeechCoaching(
                headline: "Clear and confident opening — the middle ran a little fast.",
                tips: ["Slow down in the third paragraph and land each sentence on a full stop.",
                       "You skipped “in a fraction of a millisecond” — say it as one breath.",
                       "Keep your volume up on the last word of each sentence."]))
        store.save(take)
    }

    private static func once(_ name: String, _ work: () -> Void) {
        guard !seeded.contains(name) else { return }
        seeded.insert(name)
        work()
    }

    // MARK: - Routing

    /// The account every billing capture renders against: a Light subscriber
    /// mid-period, 55 of 150 minutes and 4 of 10 scenes spent, refilling on
    /// the 14th. ONE sample for all three pages on purpose — they quote each
    /// other's numbers, so reviewing them against different accounts would
    /// hide exactly the disagreement the captures exist to catch. It also has
    /// to be an account that could EXIST: a made-up pool gets the copy checked
    /// against a figure no customer will ever see. `UsageBreakdown.sample` is
    /// written to add up against these.
    static var sampleLightAccount: AccountStatus {
        var out = AccountStatus(
            email: nil, secondsBalance: 0,
            planId: "light_monthly", subscriptionStatus: "active",
            secondsUsedPeriod: 3300, monthlyCapSeconds: 9000,
            scenesUsedPeriod: 4, monthlyScenesCap: 10,
            fullTankSeconds: 9000)
        out.periodEnd = Calendar.current.date(byAdding: .day, value: 18, to: Date())
        out.periodStart = Calendar.current.date(byAdding: .day, value: -12, to: Date())
        // A launch-code subscriber (docs/launch-billing.md §7): the Usage
        // page's subscription section has every row to show.
        out.source = "apple"
        out.startedAt = Calendar.current.date(byAdding: .day, value: -12, to: Date())
        out.lastChargeMilliunits = 7_500_000
        out.lastChargeCurrency = "KRW"
        out.lastChargeDate = out.periodStart
        out.currentOfferType = 3
        out.offerCodeSince = out.startedAt
        // What Apple charges next — the code is already pricing this period,
        // so the next charge is the same discounted figure.
        out.renewalOfferType = 3
        out.renewalPriceMilliunits = 7_500_000
        out.renewalCurrency = "KRW"
        return out
    }

    /// The same Light account in its FIRST week: a launch code redeemed
    /// before the subscription started, so nothing has been charged yet and
    /// the code prices the first renewal rather than this period. Its own
    /// capture because that week is where the receipt is hardest to read —
    /// and where a discounted subscriber was shown the regular price until
    /// 2026-09-18.
    static var sampleTrialAccount: AccountStatus {
        var out = sampleLightAccount
        out.subscriptionStatus = "trialing"
        out.startedAt = Calendar.current.date(byAdding: .day, value: -3, to: Date())
        out.periodStart = out.startedAt
        out.periodEnd = Calendar.current.date(byAdding: .day, value: 4, to: Date())
        // Nothing charged yet: the trial's own transaction is the intro
        // offer, priced at zero, and no offer-code transaction exists.
        out.lastChargeMilliunits = nil
        out.lastChargeCurrency = nil
        out.lastChargeDate = nil
        out.currentOfferType = 1
        out.offerCodeSince = nil
        return out
    }

    /// True from the moment a capture run resolves its screen. A surface
    /// that would otherwise START on appear (a run, a countdown) checks it
    /// and holds still, so the screenshot catches the state it was asked for.
    static var isCapturing = false

    /// Seeds synchronously (before the child view's onAppear reads the stores),
    /// then returns the REAL screen. nil for an unknown name.
    static func view(for name: String, appState: AppState) -> AnyView? {
        isCapturing = true
        switch name {
        case "vocab":
            once("vocab") { seedVocab() }
            return AnyView(NavigationStack { VocabularyView() })
        case "vocab-loading":
            // The word card mid-lookup: WordLore has no entry cached for this
            // word and the capture run is offline, so the peek stays in its
            // loading state for the screenshot.
            once("vocab") { seedVocab() }
            previewWordCard = true
            slowLookupSeconds = 30
            // Staged in a .task — writing @Published state during body
            // evaluation blanks the render (learned the hard way twice).
            return AnyView(NavigationStack { VocabularyView() }
                .task { appState.focusWord = "zzz-uncached-word" })
        case "vocab-failed":
            // The lookup-failed state, with its Try again button.
            once("vocab") { seedVocab() }
            previewWordCard = true
            failLookups = true
            return AnyView(NavigationStack { VocabularyView() }
                .task { appState.focusWord = "zzz-uncached-word" })
        case "vocab-card":
            // The word card at full height — the peek is the default, so a
            // screenshot can't reach the expanded state without this.
            once("vocab") { seedVocab() }
            previewWordCard = true
            return AnyView(NavigationStack { VocabularyView() })
        case "daily-words":
            // The Words challenge session (the dealt hand of recommendations).
            once("vocab") { seedVocab(freshSchedule: true) }
            return AnyView(DailyWordsView().environmentObject(appState))
        case "daily-words-tray":
            // The deck mid-drag: folders out, cancel highlighted.
            once("vocab") { seedVocab(freshSchedule: true) }
            stubWordEntry = fatWordEntry
            previewStudyTray = true
            return AnyView(DailyWordsView().environmentObject(appState))
        case "daily-words-full":
            // Same deck, but every lookup returns the fat entry — how much of
            // a full dictionary entry the card fits, on THIS screen size.
            once("vocab") { seedVocab(freshSchedule: true) }
            stubWordEntry = fatWordEntry
            return AnyView(DailyWordsView().environmentObject(appState))
        case "daily-expressions":
            once("vocab") { seedVocab(freshSchedule: true) }
            return AnyView(DailyExpressionsView().environmentObject(appState))
        case "review-due":
            // What a review reminder opens: items whose snooze already ran
            // out. Seeded in the past so they're due the moment it appears.
            once("review-due") {
                seedVocab()
                let past = Date().addingTimeInterval(-600)
                StudyScheduleStore.shared.snooze(.word, "appreciate", until: past)
                StudyScheduleStore.shared.snooze(.word, "reschedule", until: past)
                StudyScheduleStore.shared.snooze(.expression, "catch up on", until: past)
                // Still waiting — must NOT appear in the due deck.
                StudyScheduleStore.shared.snooze(.word, "nuanced",
                                                 until: Date().addingTimeInterval(3 * 86_400))
            }
            return AnyView(DueReviewView().environmentObject(appState))
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
        case "me":
            // The reorganized settings list, for IA review.
            return AnyView(MeTab().environmentObject(appState))
        case "sync-other-device":
            // The second device when the first never turned sync on: the
            // screen that stands where onboarding otherwise would.
            return AnyView(SyncOtherDeviceHintView(onFound: {}, onSkip: {})
                .environmentObject(appState))
        case "sync":
            return AnyView(NavigationStack {
                List { SyncSection() }
                    .navigationTitle("Devices")
                    .navigationBarTitleDisplayMode(.inline)
            }.environmentObject(appState))
        case "activity-unsaved":
            // The reported bug: a call closed with "Close without saving" —
            // metered, no `Session`. The day must still be on the calendar,
            // in the month total, and able to make its card.
            once("activity-unsaved") {
                TalkTimeLog.add(seconds: 8 * 60, language: appState.targetLanguage)
            }
            return AnyView(NavigationStack { ActivityView().environmentObject(appState) })
        case "plan-editor":
            once("plan-editor-anytime") {
                var plan = StudyPlan()
                plan.blocks = [
                    .init(kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10),
                    .init(kind: .sayItAgain, weekdays: [2, 4], hour: 20, minute: 30, minutes: 1),
                    .init(kind: .words, weekdays: [3, 5], hour: 19, minute: 30, minutes: 10),
                    .init(kind: .shadow, weekdays: [7], hour: 11, minute: 0, minutes: 2),
                    // Blocks with no hour, for the editor's "any time" row.
                    .init(kind: .expressions, weekdays: Set(2...7), hour: 0, minute: 0, minutes: 3, anytime: true),
                    .init(kind: .words, weekdays: [2, 4, 6], hour: 0, minute: 0, minutes: 10, anytime: true),
                    .init(kind: .review, weekdays: Set(1...7), hour: 21, minute: 0, minutes: 20),
                ]
                plan.offWeekdays = [1]
                StudyPlanStore.shared.update(plan)
            }
            return AnyView(WeeklyPlanEditor())
        case "routine-new":
            // A learner who never set a call time: the onboarding routine,
            // talk 10 minutes any time of day.
            once("routine-new") {
                StudyPlanStore.shared.update(StudyPlan.seeded(callTimes: [], goalMinutes: 10, callEnabled: false))
                PromiseLedger.shared.replaceAll([:])
            }
            return AnyView(NavigationStack { ActivityView().environmentObject(appState) })
        case "plan-block":
            return AnyView(PlanBlockEditor(target: .new(day: Date())))
        case "activity-week", "activity-week-edit":
            // The study timetable: a weekday talk at 8:00, words twice a
            // week, a review slot, and a few days of what actually happened —
            // one talk moved to noon, one unplanned shadowing sitting.
            once("activity-week") {
                let cal = Calendar.current
                let today = cal.startOfDay(for: Date())
                func at(_ back: Int, _ h: Int, _ m: Int = 0) -> Date {
                    cal.date(bySettingHour: h, minute: m, second: 0,
                             of: cal.date(byAdding: .day, value: -back, to: today)!)!
                }
                var plan = StudyPlan()
                plan.blocks = [
                    .init(kind: .talk, weekdays: Set(2...6), hour: 8, minute: 0, minutes: 10),
                    .init(kind: .sayItAgain, weekdays: Set(2...6), hour: 8, minute: 10, minutes: 1),
                    .init(kind: .words, weekdays: [3, 5], hour: 19, minute: 30, minutes: 10),
                ]
                plan.blocks.append(.init(kind: .review, weekdays: Set(2...6), hour: 21, minute: 0, minutes: 20))
                // "-capture activity-week" shows a promise kept since Monday;
                // the plain studied-days rule is the default everywhere else.
                plan.streakSince = cal.date(byAdding: .day, value: -4, to: today)
                PromiseLedger.shared.replaceAll([:])
                StudyPlanStore.shared.update(plan)
                for (back, start, end, title) in [(3, at(3, 8, 3), at(3, 8, 15), "Weekend plans"),
                                                  (2, at(2, 12, 20), at(2, 12, 33), "Moving apartments"),
                                                  (1, at(1, 8, 1), at(1, 8, 12), "The interview follow-up"),
                                                  (0, at(0, 8, 2), at(0, 8, 14), "Coffee with Sarah")] {
                    // A fixed id per seeded talk, so a second capture run
                    // replaces it instead of stacking a copy on the grid.
                    var s = Self.talkDetailSession
                    s = Session(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a\(back)")!, userId: s.userId, targetLanguage: s.targetLanguage, mode: s.mode,
                                topic: title, startedAt: start, endedAt: end,
                                turns: s.turns, summary: s.summary)
                    SessionStore.shared.save(s)
                }
                var events: [ActivityEventLog.Event] = []
                for minute in stride(from: 5, to: 20, by: 3) { events.append(.init(kind: .drill, at: at(3, 21, minute))) }
                for minute in stride(from: 0, to: 12, by: 4) { events.append(.init(kind: .shadow, at: at(2, 17, minute))) }
                for minute in stride(from: 32, to: 45, by: 4) { events.append(.init(kind: .word, at: at(2, 19, minute))) }
                for minute in stride(from: 2, to: 18, by: 3) { events.append(.init(kind: .drill, at: at(1, 21, minute))) }
                events.append(.init(kind: .sayItAgain, at: at(0, 8, 20)))
                ActivityEventLog.shared.replaceAll(events)
            }
            return AnyView(NavigationStack { ActivityView().environmentObject(appState) })
        case "activity", "activity-cards":
            // The activity calendar with today selected — the day summary
            // carries the share-card button. "-cards" opens the card grid,
            // seeded with a week of talks so the collection has rows.
            once("activity") {
                SessionStore.shared.save(Self.talkDetailSession)
                // Minutes come from the METER, not from the sessions — so a
                // seed that only writes sessions draws a flat, empty month.
                // TOP UP rather than add: `once` is in-memory, so a plain add
                // grew the day on every launch and no two captures matched.
                @MainActor func meter(_ minutes: Int, on day: Date) {
                    let want = minutes * 60 - TalkTimeLog.seconds(on: day)
                    guard want > 0 else { return }
                    TalkTimeLog.add(seconds: want, language: appState.targetLanguage, now: day)
                }
                meter(11, on: Date())
                for (back, title, mins) in [(1, "Weekend plans", 14), (2, "Moving apartments", 6),
                                            (4, "The interview follow-up", 22), (6, "Coffee with Sarah", 9),
                                            (9, "Explaining my job", 4)] {
                    var s = Self.talkDetailSession
                    let ended = Calendar.current.date(byAdding: .day, value: -back, to: Date())!
                    s = Session(id: UUID(), userId: s.userId, targetLanguage: s.targetLanguage, mode: s.mode,
                                topic: title, startedAt: ended.addingTimeInterval(-600), endedAt: ended,
                                turns: s.turns, summary: s.summary)
                    SessionStore.shared.save(s)
                    meter(mins, on: ended)
                }
            }
            return AnyView(NavigationStack { ActivityView().environmentObject(appState) })
        case "setup":
            // The first-run picker steps (native language, target, level,
            // goal) — the only screen where the app-language choice is made
            // before anything else exists.
            return AnyView(SetupFlowView().environmentObject(appState)
                .environmentObject(AuthService()))
        case "welcome":
            // The first screen, primary path (Get started).
            return AnyView(WelcomeView().environmentObject(appState)
                .environmentObject(AuthService()))
        case "welcome-signin":
            // The sign-in / sign-up buttons: Apple + Google. `register` is
            // process-lifetime only — a persisted `set` here leaked into the
            // NEXT normal launch, which then opened on the sign-in state.
            once("welcome-signin") {
                UserDefaults.standard.register(defaults: ["welcomeSignIn": true])
            }
            return AnyView(WelcomeView().environmentObject(appState)
                .environmentObject(AuthService()))
        case "signup-account":
            // Onboarding's sign-UP moment: the account step after the clone
            // was heard (Back · Apple · Google).
            once("signup-account") {
                UserDefaults.standard.register(defaults: ["cloneStatus": "account"])
            }
            return AnyView(VoiceCloneOnboardingView().environmentObject(appState)
                .environmentObject(AuthService()))
        case "app-guide":
            // Me → App guide: every tab's guide in one list.
            return AnyView(NavigationStack { AppGuideView() }.environmentObject(appState))
        case _ where name.hasPrefix("page-intro-"):
            // The first-visit introduction, over the tab it introduces.
            // `page-intro-<tab>` opens its first page, `-<tab>-2` / `-3` the
            // later ones.
            let parts = name.dropFirst("page-intro-".count).split(separator: "-")
            let page = PageIntro.Page(rawValue: String(parts.first ?? "")) ?? .talk
            let step = parts.count > 1 ? max(0, (Int(parts[1]) ?? 1) - 1) : 0
            return AnyView(PageIntroCaptureHost(page: page, step: step).environmentObject(appState))
        case "watchtab":
            // The Watch tab with the merged People entry in its header.
            return AnyView(WatchTab().environmentObject(appState))
        case "intro-preview":
            // The mirrored Find-people intro, seen before anything is
            // published: work · town · situations · the unlocked lines only.
            once("sample-persona") { seedSamplePersona(appState) }
            return AnyView(PublicIntroPreviewSheet().environmentObject(appState))
        case "profile-name":
            // Me → Profile, first step: the avatar sits in the SAME card as
            // the name field (2026-09-25) — it used to float on the grouped
            // backdrop, reading as cut off from the row under it.
            once("sample-persona") { seedSamplePersona(appState) }
            return AnyView(PersonaOnboardingView(initialPersona: appState.persona, startStep: 0)
                .environmentObject(appState))
        case "profile-notes":
            // Me → Profile, "Your life" step: the remembered lines with their
            // locks — two private, one the summary call let out.
            once("sample-persona") { seedSamplePersona(appState) }
            return AnyView(PersonaOnboardingView(initialPersona: appState.persona, startStep: 1)
                .environmentObject(appState))
        case "people":
            // The ONE people page: own people on top, the shared pool below.
            return AnyView(FindPeopleSheet(onNew: {}, onTalk: { _ in }, onWatch: { _ in },
                                           onCompose: { _ in }).environmentObject(appState))
        case "daycard":
            // Today's share card with a sample day — no camera in the
            // simulator, so this is the ink fallback.
            let sample = DayCardData(
                date: Date(), talkMinutes: 12, studyMinutes: 25,
                streakDays: 7, talks: 3, reviews: 18, shadowTakes: 4,
                topics: ["Did you read about the study on AI replacing language teachers?", "Weekend plans", "Job interview"])
            return AnyView(DayCardSheet(day: Date(), preview: sample).environmentObject(appState))
        case "speech":
            // The Speech tab: the bundled script plus two written ones.
            once("speech") { seedSpeech(appState) }
            return AnyView(SpeechTab().environmentObject(appState))
        case "speech-composer":
            return AnyView(SpeechComposerSheet { _ in }.environmentObject(appState))
        case "speech-prompter":
            // Mid-take look: the prompter a third of the way through, mic
            // panel below (no camera in the simulator).
            let script = SpeechLibrary.builtIn(for: appState.targetLanguage)!
            return AnyView(SpeechPrompterView(script: script, native: appState.nativeLanguage,
                                              level: appState.proficiency, previewCursor: 24))
        case "speech-plus":
            return AnyView(Color(.systemBackground).sheet(isPresented: .constant(true)) {
                SpeechPlusSheet(isLight: true)
            })
        case "speech-own":
            return AnyView(SpeechOwnScriptSheet(existing: nil) { _ in }.environmentObject(appState))
        case "speech-open":
            // The prompter exactly as Practice opens it: cursor 0, ready.
            let script = SpeechLibrary.builtIn(for: appState.targetLanguage)!
            return AnyView(SpeechPrompterView(script: script, native: appState.nativeLanguage,
                                              level: appState.proficiency))
        case "speech-result":
            once("speech") { seedSpeech(appState) }
            let take = SpeechStore.shared.takes.first!
            return AnyView(NavigationStack { SpeechResultView(takeId: take.id) })
        case "plan":
            // Me → Talk time, for a Light subscriber. The receipt used to be
            // its own capture (`-capture usage`); it is this page now, so the
            // sample usage rides along and the whole thing is reviewed at
            // once — which is what the two-capture split kept failing to do.
            return AnyView(NavigationStack {
                PlanPageView(account: Self.sampleLightAccount, previewUsage: .sample)
            })
        case "plan-spent":
            // The same page once the month's minutes are gone: the invite
            // row has grown into the card, and nothing else moves.
            var spent = Self.sampleLightAccount
            spent.secondsUsedPeriod = spent.monthlyCapSeconds ?? 9000
            return AnyView(NavigationStack {
                PlanPageView(account: spent, previewUsage: .sample,
                             previewInvite: InviteOffer(code: "K3MQ9F", invitesUsed: 2))
            })
        case "plan-trial":
            // The same page during the trial week of a launch-code
            // subscriber: no charge yet, the first one dated and priced, and
            // the code named above it.
            return AnyView(NavigationStack {
                PlanPageView(account: Self.sampleTrialAccount, previewUsage: .sample)
            })
        case "plan-guide":
            // The transparency page for a Light subscriber — the one place
            // the plan's shape is stated in full.
            return AnyView(NavigationStack {
                CreditGuideView(account: Self.sampleLightAccount)
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
        case "call-meter", "call-meter-low":
            // The call toolbar with the remaining-talk-time chip, in both of
            // its states (secondary at ≤10 min, orange at ≤3) — the chip is
            // drag-only reachable in real use (needs a nearly-spent balance).
            let mins = name == "call-meter-low" ? 2 : 7
            return AnyView(NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    DialogueLine(speaker: .other, name: "Future self") {
                        Text("So — how did the interview go yesterday?")
                    }
                    DialogueLine(speaker: .user, name: "You") {
                        Text("Honestly, it went really well. I felt prepared.")
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        LevelHeaderTitle(title: "Job interview",
                                         level: .b1, surface: .talk,
                                         minutesLeft: mins)
                            .environmentObject(appState)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "xmark")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("End").fontWeight(.semibold)
                            .foregroundStyle(.red)
                    }
                }
            })
        case "call-goals":
            // The studying-chips row pinned above a call in progress: one item
            // already said (ticked), the rest still open. Real use needs a
            // notebook AND a live call, so the state is staged here.
            let goals = [
                TalkGoalItem(key: "hectic", text: "hectic", isWord: true, claimedKnown: true),
                TalkGoalItem(key: "commute", text: "commute", isWord: true),
                TalkGoalItem(key: "it slipped my mind", text: "it slipped my mind", isWord: false),
                TalkGoalItem(key: "run me through it", text: "run me through it", isWord: false),
                TalkGoalItem(key: "eventually", text: "eventually", isWord: true),
            ]
            return AnyView(NavigationStack {
                VStack(spacing: 0) {
                    TalkGoalChipsRow(items: goals, used: ["commute"])
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 18) {
                        DialogueLine(speaker: .other, name: "Future self") {
                            Text("So — how did the interview go yesterday?")
                        }
                        DialogueLine(speaker: .user, name: "You") {
                            Text("It went well. I commuted for almost an hour, though.")
                        }
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        LevelHeaderTitle(title: "Job interview",
                                         level: .b1, surface: .talk)
                            .environmentObject(appState)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "xmark")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("End").fontWeight(.semibold)
                            .foregroundStyle(.red)
                    }
                }
            })
        case "first-call-check", "first-call-check-hard":
            // The after-first-call sheet (`FirstCallCheckSheet`), on A2.
            once("first-call-check") { appState.proficiency = .a2 }
            return AnyView(Color(.systemGroupedBackground).sheet(isPresented: .constant(true)) {
                FirstCallCheckSheet(feeling: name.hasSuffix("hard") ? .hard : nil)
                    .environmentObject(appState)
            })
        case "call-coach":
            // Coach mode's "try saying" above the pill, the listening bubble
            // plain. Staged like call-focus: a real one needs a live call.
            let ko = appState.nativeLanguage.hasPrefix("ko")
            let reply = CoachReply(say: "Yes, I want to try [the one in Sinjeon].",
                                   meaning: ko ? "응, [신전떡볶이] 먹어보고 싶어." : "",
                                   turnId: UUID())
            return AnyView(NavigationStack {
                VStack(spacing: 0) {
                    TalkGoalChipsRow(items: [
                        TalkGoalItem(key: "total", text: "total", isWord: true),
                        TalkGoalItem(key: "battery", text: "battery", isWord: true),
                        TalkGoalItem(key: "next", text: "next", isWord: true),
                    ], used: ["next"])
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 18) {
                        DialogueLine(speaker: .user, name: "You") {
                            Text("Not yet, but I want to go there next week.")
                        }
                        DialogueLine(speaker: .other, name: "Future self") {
                            Text("Oh, nice! Next week will be here before you know it. Do you have a specific place in mind?")
                        }
                        DialogueLine(speaker: .user, name: "You", scale: .call) {
                            Text("Listening…").foregroundStyle(.secondary).italic()
                        }
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 10) {
                        CoachReplyLabel(reply: reply).padding(.horizontal, 32)
                        Capsule().fill(Color(.secondarySystemBackground))
                            .frame(width: 156, height: 64)
                        Text("Listening · pause to send · tap to stop")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.top, 14).padding(.bottom, 20)
                }
                .background(Color(.systemBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Let's talk").font(.headline) }
                    ToolbarItem(placement: .topBarLeading) { Image(systemName: "xmark") }
                    ToolbarItem(placement: .topBarTrailing) { Text("End").fontWeight(.semibold) }
                }
            })
        case "call-focus", "call-focus-sheet":
            // Coach mode's grammar focus pinned above the chips, one repeat
            // already counted, and the learner's card wearing the badge.
            // Staged: a real focus needs a profile, a live call and a slip.
            let goals = [
                TalkGoalItem(key: "hectic", text: "hectic", isWord: true),
                TalkGoalItem(key: "commute", text: "commute", isWord: true),
                TalkGoalItem(key: "it slipped my mind", text: "it slipped my mind", isWord: false),
            ]
            let ko = appState.nativeLanguage.hasPrefix("ko")
            let label = ko ? "과거 시제" : "Past tense"
            let tip = ko ? "어제·지난주처럼 지난 일을 말할 때는 과거형을 써요."
                         : "Use the past form when you talk about yesterday or last week."
            let suggestion = TurnSuggestion(
                alternative: "I went to the office early yesterday, so I left at four.",
                reason: ko ? "어제 일이라 과거형이 자연스러워요." : "It happened yesterday, so the past form.",
                fixes: [TurnFix(was: "I go to the office", now: "I went to the office",
                                why: ko ? "과거 시제" : "Past tense")])
            return AnyView(NavigationStack {
                VStack(spacing: 0) {
                    GrammarFocusStrip(label: label, mistake: "Yesterday I go to the office",
                                      correction: "Yesterday I went to the office", repeats: 1)
                    Divider().opacity(0.15)
                    TalkGoalChipsRow(items: goals, used: ["commute"])
                    Divider().opacity(0.15)
                    VStack(alignment: .leading, spacing: 18) {
                        DialogueLine(speaker: .other, name: "Future self") {
                            Text("Busy day? What did you do this morning?")
                        }
                        DialogueLine(speaker: .user, name: "You") {
                            Text("I go to the office early yesterday, so I left at four.")
                        } accessory: {
                            SuggestionChip(suggestion: suggestion,
                                           original: "I go to the office early yesterday, so I left at four.",
                                           nativeLanguage: appState.nativeLanguage,
                                           focusRepeatLabel: label)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Free talk").font(.headline) }
                    ToolbarItem(placement: .topBarLeading) { Image(systemName: "xmark") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("End").fontWeight(.semibold).foregroundStyle(.red)
                    }
                }
                .sheet(isPresented: .constant(name == "call-focus-sheet")) {
                    GrammarFocusSheet(label: label, tip: tip,
                                      mistake: "Yesterday I go to the office",
                                      correction: "Yesterday I went to the office", repeats: 1)
                }
            })
        case "focus-result":
            let ko = appState.nativeLanguage.hasPrefix("ko")
            return AnyView(NavigationStack {
                List {
                    Section {
                        GrammarFocusResultRow(record: GrammarFocusRecord(
                            patternKey: "a", label: ko ? "과거 시제" : "Past tense",
                            mistake: "Yesterday I go to the office",
                            correction: "Yesterday I went to the office", repeats: 1))
                    }
                    Section {
                        GrammarFocusResultRow(record: GrammarFocusRecord(
                            patternKey: "b", label: ko ? "요일 전치사" : "Prepositions with days",
                            mistake: "I have a meeting in Monday",
                            correction: "I have a meeting on Monday", repeats: 0))
                    }
                }
                .navigationTitle(Text(verbatim: "Focus"))
            })
        case "call-feed-fade":
            // Geometry check for the call feed's edge under the mic bar: the
            // same attachment ConversationView uses (`fadingBottomBar`), with a
            // stand-in pill. Scrolled to the end so the last line's rest
            // position is visible.
            return AnyView(NavigationStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(0..<14, id: \.self) { i in
                                if i % 2 == 0 {
                                    DialogueLine(speaker: .other, name: "Future self") {
                                        Text("So — how did the interview go yesterday? Anything you'd do differently next time?")
                                    }
                                    .id(i)
                                } else {
                                    DialogueLine(speaker: .user, name: "You") {
                                        Text("Honestly, it went really well. I felt prepared. \(i)")
                                    }
                                }
                            }
                            Color.clear.frame(height: 8).id("end")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
                    // `-captureScrolled`: park a bubble under the bar instead
                    // of resting at the end, to photograph the fade itself.
                    .onAppear {
                        if UserDefaults.standard.bool(forKey: "captureScrolled") {
                            proxy.scrollTo(8, anchor: .top)
                        } else {
                            proxy.scrollTo("end", anchor: .bottom)
                        }
                    }
                }
                .fadingBottomBar {
                    VStack(spacing: 10) {
                        Capsule().fill(Color.accentColor.opacity(0.3))
                            .frame(width: 156, height: 64)
                        Text("Listening").font(.footnote).foregroundStyle(.secondary).frame(height: 16)
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemBackground))
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Let's talk")
            })
        case "summary-progress", "summary-progress-start":
            // The end-of-talk board, mid-build: the analysis has landed and
            // the counts are filling in. `-start` is the long first step,
            // which is what the learner actually sits through.
            var p = SessionSummarizer.Progress()
            if name != "summary-progress-start" {
                p.readBack = true
                p.wroteCorrections = true
                p.phrases = 4
                p.wroteDrills = true
            }
            return AnyView(ZStack {
                Color(.systemBackground).ignoresSafeArea()
                SummaryProgressView(progress: p, facts: "9 of your turns · 6 min")
            })
        case "call-goal-sheet":
            // What a chip opens. A capture run has no session, so the real
            // lookup returns nil and the sheet would render its failure state
            // — stub the entry the same way the word card's capture does.
            stubWordEntry = WordEntry(
                pos: "Adjective",
                senses: [.init(pos: "형용사", meaning: "정신없이 바쁜, 빡빡한",
                               note: "일정·하루처럼 '쉴 틈 없이 바쁜' 상태에 써요.")],
                examples: [.init(text: "It's been a hectic week at work.",
                                 meaning: "회사에서 정신없는 한 주였어요.")],
                phrases: [], properNoun: nil)
            return AnyView(GoalSheetPreview().environmentObject(appState))
        case "first-call":
            // The introduction call — the REAL ConversationView, opened by a
            // learner the fluent self has never met (`UserPersona.metAt` nil).
            // A capture run has no clone, so the opener lands as text rather
            // than speech; the line itself is the one a real first call
            // speaks, and the FIRST CALL prompt block is what would run from
            // the learner's first answer on.
            once("first-call") { seedUnmetPersona(into: appState) }
            return AnyView(ConversationView().environmentObject(appState))
        case "call-settings":
            // The same real call screen as `first-call`, with the settings
            // sheet up — the sheet's detent and the live screen behind it are
            // the whole point, so it is never photographed on its own.
            once("first-call") { seedUnmetPersona(into: appState) }
            previewCallSettings = true
            return AnyView(ConversationView().environmentObject(appState))
        case "level-sheet":
            once("level") { seedSessions() }
            return AnyView(LevelInfoSheet(level: .b1, surface: .watch)
                .environmentObject(appState))
        case "home-scenarios":
            once("home") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            previewScenariosTab = true
            return AnyView(ConversationHome())
        case "home":
            once("home") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(ConversationHome())
        case "home-ring":
            // The hero ring at an exact talk time — `-ringSeconds N` — so the
            // arc can be reviewed short, mid and near-full. Seeds only the
            // shortfall, so reinstall between runs to go DOWN.
            once("home-ring") {
                seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState)
                let want = UserDefaults.standard.integer(forKey: "ringSeconds") - TalkTimeLog.secondsToday()
                TalkTimeLog.add(seconds: want, language: appState.targetLanguage)
            }
            return AnyView(ConversationHome())
        case "home-plus":
            // The same home for a PLUS subscriber, which draws NO ring — an
            // hour a day is a pool the arc would sit near-empty on all month.
            // Its own capture so the absence is reviewed, not assumed.
            once("home-plus") {
                seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState)
                TalkTimeLog.add(seconds: 180, language: appState.targetLanguage)
            }
            return AnyView(ConversationHome())
        case "home-light", "home-light-fresh":
            // The Talk home for a LIGHT subscriber — the avatar ring in the
            // header draws down this month's pool. The account is injected by
            // `ConversationHome.refreshAccount` (it keys off this capture
            // name); `-fresh` seeds nothing so the hero ring sits at zero.
            if name == "home-light" {
                once("home-light") {
                    seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState)
                    // The arc reads TalkTimeLog, not the injected snapshot —
                    // seed today so the ring is shown part-spent rather than
                    // empty, which is the state worth reviewing.
                    TalkTimeLog.add(seconds: 180, language: appState.targetLanguage)
                }
            }
            return AnyView(ConversationHome())
        case "backup-offer":
            // "Keep your practice in iCloud?" over the Talk home.
            once("home") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(ConversationHome().sheet(isPresented: .constant(true)) { BackupOfferSheet() })
        case "voice-revival", "voice-revival-tune":
            // A parked voice brought back at the call tap (`VoiceRevival`):
            // the rebuild, then the speed + accent page.
            let sample = FileManager.default.temporaryDirectory
                .appendingPathComponent("capture-sample.wav")
            return AnyView(VoiceRevivalView(sample: sample, purpose: .call) { _ in }
                .environmentObject(appState))
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
        case "weekly-test", "weekly-test-word", "weekly-test-gap", "weekly-test-build", "weekly-test-listen",
             "weekly-test-speak",
             "weekly-test-word-right", "weekly-test-gap-wrong", "weekly-test-build-wrong", "weekly-test-build-right",
             "weekly-test-grammar", "weekly-test-grammar-right", "weekly-test-grammar-wrong",
             "weekly-test-upgrade", "weekly-test-upgrade-right", "weekly-test-upgrade-wrong":
            // The test sheet, opened on a chosen item kind. Material is the
            // seeded week; the dictionary is stubbed so a meaning item can be
            // built offline.
            once("weekly-test") { seedWeeklyTestWeek() }
            stubWordEntry = fatWordEntry
            weeklyTestKind = switch name {
                case "weekly-test-word", "weekly-test-word-right": .meaning
                case "weekly-test-gap", "weekly-test-gap-wrong": .gap
                case "weekly-test-build", "weekly-test-build-wrong", "weekly-test-build-right": .build
                case "weekly-test-listen": .listen
                case "weekly-test-speak": .speak
                case "weekly-test-grammar", "weekly-test-grammar-right", "weekly-test-grammar-wrong": .grammar
                case "weekly-test-upgrade", "weekly-test-upgrade-right", "weekly-test-upgrade-wrong": .upgrade
                default: nil
            }
            weeklyTestAnswer = name.hasSuffix("-right") ? true : (name.hasSuffix("-wrong") ? false : nil)
            return AnyView(WeeklyTestView().environmentObject(appState))
        case "week-recap", "week-recap-quiet":
            // "Your week", every card dealt from a hand-written week (the
            // real one is built from logs a capture run doesn't have).
            // `-recappage N` opens on card N; the coach card is pre-written
            // so the capture never waits on the network.
            let recap = name == "week-recap-quiet" ? sampleQuietWeek : sampleWeekRecap
            return AnyView(WeekRecapSheet(recap: recap, action: .constant(nil),
                                          startPage: UserDefaults.standard.integer(forKey: "recappage"))
                .environmentObject(appState))
        case "week-archive", "practice-week":
            // "Your week" from Practice: this week in progress, then last
            // week (unseen → "New") and the week before it.
            once(name) { seedWeekArchive() }
            if name == "practice-week" {
                once("practice-week-content") { seedVocab(); seedSessions(); seedScenarios(into: appState) }
                return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
            }
            return AnyView(WeekRecapArchiveView { _ in }.environmentObject(appState))
        case "weekly-test-result":
            once("weekly-test-result") { seedFinishedWeeklyTest() }
            return AnyView(WeeklyTestView().environmentObject(appState))
        case "practice-weekly":
            // The Today card carrying the weekly test row, finished state.
            once("practice-weekly") {
                seedVocab(); seedSessions(); seedScenarios(into: appState); seedFinishedWeeklyTest()
            }
            return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
        case "practice-today":
            // The book-first Studying page: sample talks and scenes, newest
            // first, each with its chapter buttons.
            once("practice-today") {
                seedVocab(); seedSessions(); seedScenarios(into: appState)
                var plan = StudyPlan()
                plan.blocks = [
                    .init(kind: .review, weekdays: Set(1...7), hour: 0, minute: 0, minutes: 4, anytime: true),
                    .init(kind: .words, weekdays: Set(1...7), hour: 0, minute: 0, minutes: 10, anytime: true),
                    .init(kind: .expressions, weekdays: Set(1...7), hour: 0, minute: 0, minutes: 3, anytime: true),
                ]
                StudyPlanStore.shared.update(plan)
                for _ in 0..<6 { PracticeLog.shared.record(.word, finished: true) }
                for _ in 0..<3 { PracticeLog.shared.record(.expression, finished: true) }
                PracticeLog.shared.record(.drill, finished: true)
            }
            return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
        case "practice-due":
            // The Today card with items back from an earlier snooze — the
            // non-notification entry point into the review deck.
            once("practice-due") {
                seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState)
                let past = Date().addingTimeInterval(-900)
                StudyScheduleStore.shared.snooze(.word, "reschedule", until: past)
                StudyScheduleStore.shared.snooze(.word, "overwhelmed", until: past)
                StudyScheduleStore.shared.snooze(.expression, "walk you through", until: past)
            }
            return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
        case "practice-review-route":
            // The half a notification tap actually drives: the staged route
            // is consumed and the due deck opens on top of the tab.
            // (RootTabView owns the URL→route mapping and isn't in this
            // hierarchy, so the route is staged directly here.)
            once("practice-due") {
                seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState)
                let past = Date().addingTimeInterval(-900)
                StudyScheduleStore.shared.snooze(.word, "reschedule", until: past)
                StudyScheduleStore.shared.snooze(.word, "overwhelmed", until: past)
            }
            // Staged in a .task, NOT here: writing @Published state during
            // body evaluation corrupts the render (blank screen).
            return AnyView(PracticeTab(initialShelf: .studying)
                .environmentObject(appState)
                .task { appState.pendingPracticeRoute = .review })
        case "review-item-word":
            // A per-item callback for a WORD: the staged route must open that
            // one card, not the whole queue.
            once("vocab") { seedVocab() }
            return AnyView(PracticeTab(initialShelf: .studying)
                .environmentObject(appState)
                .task { appState.pendingPracticeRoute = .reviewItem(kind: "word", value: "genuinely") })
        case "review-item-sentence":
            // Same for a SENTENCE — its drill card opens on its own.
            once("drills") { seedVocab(); seedDrillFolders() }
            let firstCard = DrillStore.shared.load().first?.id
            return AnyView(PracticeTab(initialShelf: .studying)
                .environmentObject(appState)
                .task {
                    guard let firstCard else { return }
                    appState.pendingPracticeRoute =
                        .reviewItem(kind: "sentence", value: firstCard.uuidString)
                })
        case "practice-studying":
            once("practice-studying") { seedSessions(scored: true); seedScenarios(into: appState) }
            return AnyView(PracticeTab(initialShelf: .studying).environmentObject(appState))
        case "drills":
            // The SRS review sheet, incl. a legacy card whose source is a whole
            // rambling turn — verifies the render-time fragment trim.
            once("drills") { seedVocab(); seedDrillFolders() }
            return AnyView(DrillSheet().environmentObject(appState))
        case "drills-tray":
            // Same deck, frozen mid-drag: the bin tray is a drag-only surface,
            // so a screenshot can't reach it without this.
            once("drills") { seedVocab(); seedDrillFolders() }
            previewDrillTray = true
            return AnyView(DrillSheet().environmentObject(appState))
        case "drills-folder":
            // A folder opened over the deck — the sheet is reachable only by
            // tapping a chip, which a screenshot run can't do.
            once("drills") { seedVocab(); seedDrillFolders() }
            previewDrillFolder = true
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
        case "book", "book-words", "book-lines":
            // One scenario book opened on its detail page — the table of
            // contents (scene chapter + per-chapter progress + Up next).
            // "-words"/"-lines" open pushed onto that chapter's page.
            once("book") {
                var c = curriculum(mastered: 5)
                c.dialogueTitle = "Catching up with Sarah"
                c.dialogue = [
                    .init(speaker: "counterpart", text: "Oh my god, it's been forever! How have you been?"),
                    .init(speaker: "user", text: "I know! Honestly, so much has happened — where do I even start?"),
                    .init(speaker: "counterpart", text: "Start with the new job! How's it going?"),
                    .init(speaker: "user", text: "It turned out to be a bit of a stretch at first, but I'm settling in."),
                ]
                let s = Scenario(environment: "At the café with Sarah: catching up after months apart — she asks what I've been up to and I keep the story going.",
                                 role: "Sarah (close friend)", notes: "",
                                 lastUsedAt: Date().addingTimeInterval(-5 * 3600),
                                 curriculum: c, isTopic: false,
                                 category: "Cafe", categoryIcon: "cup.and.saucer.fill",
                                 summary: "Café · catching up")
                appState.saveScenario(s)
                bookScenarioId = s.id
            }
            let chapter: ScenarioDetailView.Chapter? = switch name {
            case "book-words": .words
            case "book-lines": .shadow
            default: nil
            }
            return AnyView(BookCaptureHost(scenarioId: bookScenarioId, chapter: chapter)
                .environmentObject(appState))
        case "intake-people":
            return AnyView(CounterpartVoiceIntakeView())
        case "deepen", "deepen-full":
            // The post-first-talk persona sheet over the real Talk home —
            // "-full" starts at the large detent to review all three fields.
            once("deepen") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(DeepenCaptureHost(expanded: name == "deepen-full")
                .environmentObject(appState))
        case "free-minutes-welcome":
            // The first-visit free-minutes welcome over the Talk home.
            return AnyView(WelcomeCaptureHost().environmentObject(appState))
        case "paywall", "paywall-plans", "paywall-max",
             "paywall-ladder", "paywall-ladder-yearly", "paywall-ladder-pack", "paywall-ladder-anim",
             "paywall-ladder-yearly-light", "paywall-ladder-max":
            // The out-of-credits paywall (no trial pitch), as presented from
            // a 402 failure.
            return AnyView(PaywallView().environmentObject(appState))
        case "feedback":
            // The feedback sheet, at the medium detent the call ends into.
            // Reachable no other way in a capture run: it fires once, after a
            // minute-long call on a RETURN visit (`shouldShowReturningTalk`).
            return AnyView(FeedbackCaptureHost().environmentObject(appState))
        case "update", "update-required":
            // The update notice, both temperaments. Unreachable in a capture
            // run — it needs a server that has moved past this build.
            return AnyView(UpdateCaptureHost(required: name == "update-required"))
        case "day-spent", "day-spent-unlimited", "day-spent-scenes", "day-spent-invite":
            // The spent-allowance sheet, both sides of it: Daily (there is
            // something to offer) and Unlimited (there isn't). Unreachable in
            // a capture run — it takes a real account that talked out its day.
            // `day-spent-invite` is the same sheet with the invite line,
            // which only a subscriber on a counted pool with rewards left
            // ever sees.
            return AnyView(DaySpentCaptureHost(
                kind: name == "day-spent-scenes" ? .scenes : .talk,
                canUpgrade: name != "day-spent-unlimited",
                invite: name == "day-spent-invite"
                    ? InviteOffer(code: "K3MQ9F", invitesUsed: 2) : nil)
                .environmentObject(appState))
        case "day-spent-trial", "day-spent-trial-plus":
            // The same sheet as a TRIAL account meets it: the pool is the
            // Light pool pro-rated 7/30 (35 min) whatever tier is trialed, and
            // the date is the trial's end (`periodEnd`). A Plus trial gets no
            // upgrade half — `canUpgradePlan` is `isLightPlan`.
            let trialEnd = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
            var account = Self.sampleTrialAccount
            account.periodEnd = trialEnd
            return AnyView(DaySpentCaptureHost(
                kind: .talk,
                canUpgrade: name == "day-spent-trial",
                allowance: 35,
                renewsOn: account.renewalLabel,
                isTrial: true,
                planMinutesAfterTrial: name == "day-spent-trial" ? 150 : nil,
                // A trialer sees the invite line too, and is the one account
                // for which it is the ONLY thing on the sheet besides review.
                invite: InviteOffer(code: "K3MQ9F", invitesUsed: 2))
                .environmentObject(appState))
        case "day-spent-plus":
            // What a Plus subscriber meets TODAY: the month's pool spent,
            // nothing to upgrade to, the minute pack asked for but not on
            // sale (no ASC consumable), so the invite is the only free way
            // forward and Practice takes the lead slot the pack didn't fill.
            return AnyView(DaySpentCaptureHost(
                kind: .talk, canUpgrade: false, allowance: 300,
                invite: InviteOffer(code: "K3MQ9F", invitesUsed: 2),
                canTopUp: true)
                .environmentObject(appState))
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
        case "progress-beginner", "progress-beginner-grammar", "progress-grammar":
            // The 2026-09-24 report: short accurate sentences, no slips —
            // used to read ≈C2. The talks carry a range of a2, so the
            // Grammar row must show ≈A2 with the range line under it.
            // `progress-grammar` seeds the ordinary talks (no range on
            // file) — the vocabulary stand-in ceiling.
            if name == "progress-grammar" {
                once("progress-grammar") { seedVocab(); seedSessions(scored: true) }
                return AnyView(ProgressTab(initialDim: .grammar).environmentObject(appState))
            }
            once("progress-beginner") {
                seedVocab(); seedSessions(scored: true, beginner: true)
                let report = WeeklyReport(
                    id: UUID(),
                    periodStart: Date().addingTimeInterval(-7 * 86_400),
                    periodEnd: Date(),
                    sessionCount: 3, targetLanguage: "en",
                    newExpressions: [], repeatedMistakes: [], suggestedExpressions: [],
                    summary: "Short, clear sentences — start linking two ideas in one.",
                    cefrLevel: "a2", generatedAt: Date())
                WeeklyReportStore.shared.save(report)
                appState.weeklyReports = [report]
            }
            return AnyView(ProgressTab(initialDim: name == "progress-beginner-grammar" ? .grammar : nil)
                            .environmentObject(appState))
        case "shadow-ja":
            // A Japanese line in karaoke: words, not one run — each lights
            // and taps on its own, punctuation riding on the word before.
            once("shadow-ja") { captureShadow = true }
            return AnyView(NavigationStack {
                ShadowDrillView(
                    turn: Turn(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
                               role: .fluentSelf, audioURL: nil,
                               transcript: "なるほど。通勤も長いし、慌てて片付けるより、とりあえず一つずつでいいと思うよ。",
                               durationMs: 4200, timestamp: Date(), suggestion: nil),
                    targetLanguage: "ja")
            })
        case "shadow":
            once("shadow") { captureShadow = true }
            return AnyView(NavigationStack {
                ShadowDrillView(turn: shadowTurn, targetLanguage: "en")
            })
        case "expr":
            once("expr") { seedVocab(); seedSessions(scored: true) }
            return AnyView(NavigationStack { ExpressionsView() })
        case "expr-card":
            // One phrase's card, open over the list — the widget's deep-link
            // path, staged in a .task like `vocab-loading`.
            once("expr") { seedVocab(); seedSessions(scored: true) }
            // Offline, so the card is handed a phrase-shaped entry: one sense
            // with the register line, two examples, two near-variants.
            stubWordEntry = WordEntry(
                pos: "구동사 · 일상 대화",
                senses: [.init(pos: "", meaning: "제안이나 결정에 반대 의견을 내다; 밀어내듯 저항하다.",
                               note: "회의나 협상에서 정중하게 반대할 때 자주 써요.")],
                examples: [.init(text: "I had to push back on the deadline — two weeks wasn't realistic.",
                                 meaning: "마감에 반대 의견을 내야 했어요. 2주는 현실적이지 않았거든요."),
                           .init(text: "Don't be afraid to push back on feedback you disagree with.",
                                 meaning: "동의하지 않는 피드백에는 주저 말고 반대 의견을 내세요.")],
                phrases: [.init(phrase: "raise concerns about", meaning: "~에 대해 우려를 제기하다"),
                          .init(phrase: "challenge", meaning: "이의를 제기하다")],
                properNoun: nil)
            return AnyView(NavigationStack { ExpressionsView() }
                .task { appState.focusPhrase = "push back on" })
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
        case "widget-freetalk":
            // The Free Talk widget — small (circle) and medium (pill).
            return AnyView(FreeTalkWidgetGallery(page: 0).fontDesign(nil))
        case "widget-freetalk-themes":
            return AnyView(FreeTalkWidgetGallery(page: 1).fontDesign(nil))
        case "tabs":
            // The full tab shell — used to review the floating Free talk pill
            // sitting above the real tab bar.
            once("tabs") { seedVocab(); seedSessions(); seedNews(into: appState); seedScenarios(into: appState) }
            return AnyView(RootTabView())
        case "talkdetail-words", "talkdetail-expressions", "talkdetail-lines", "talkdetail-cards":
            // The talk book opened straight onto one chapter's page.
            once("talkdetail") { seedVocab() }
            let chapter: ConversationDetailView.Chapter = switch name {
            case "talkdetail-words": .words
            case "talkdetail-expressions": .expressions
            case "talkdetail-lines": .lines
            default: .cards
            }
            return AnyView(TalkBookCaptureHost(
                session: talkDetailSession,
                chapter: chapter)
                .environmentObject(appState))
        case "wordcard-ja":
            // The word card on a kanji headword: its reading has to sit
            // under it (あわてる), or the card teaches a word nobody can say.
            return AnyView(NavigationStack {
                WordCard(word: "慌てる", currentWord: .constant("慌てる"))
            }.environmentObject(appState))
        case "transcript":
            // The English talk's transcript (Replay) — corrections under the
            // learner's lines, for the feature-series carousel.
            return AnyView(NavigationStack {
                TalkTranscriptView(session: talkDetailSession)
            }.environmentObject(appState))
        case "transcript-ja", "talkdetail-ja":
            // A Japanese talk — the one target with no spaces. The transcript
            // has to draw its 、。 back around highlighted words, the
            // correction has to light up the changed segments only, and the
            // word chapter has to hold headwords (疲れる, not 疲れ). Launch
            // with `-futurevoice.targetLanguage ja` so the stores and the
            // splitter are on the Japanese pool.
            if name == "transcript-ja" {
                return AnyView(NavigationStack {
                    TalkTranscriptView(session: japaneseTalkSession)
                }.environmentObject(appState))
            }
            return AnyView(TalkBookCaptureHost(session: japaneseTalkSession, chapter: .words)
                .environmentObject(appState))
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
                    postTalk: .init(onDone: {}))
            })
        case "say-again", "say-again-reading", "say-again-done",
             "say-again-scene", "say-again-scene-reading", "say-again-scene-done":
            // The talk read back with the learner's lines corrected — or,
            // "-scene", a Watch book's scene with the learner on their own
            // side. The mic can't be driven from a capture, so the two
            // running states are seeded rather than reached.
            let stage = name.split(separator: "-").last.map(String.init)
            sayItAgainStage = stage == "reading" || stage == "done" ? stage : nil
            if name.hasPrefix("say-again-scene") {
                var c = ScenarioCurriculum()
                c.dialogue = [
                    .init(speaker: "counterpart", text: "Oh my god, it's been forever! How have you been?"),
                    .init(speaker: "user", text: "I know! Honestly, so much has happened — where do I even start?"),
                    .init(speaker: "counterpart", text: "Start with the new job! How's it going?"),
                    .init(speaker: "user", text: "It turned out to be a bit of a stretch at first, but I'm settling in."),
                ]
                c.shadowLines = (c.dialogue ?? []).filter { $0.speaker == "user" }
                    .map { .init(text: $0.text, note: "") }
                var sarah = Counterpart.empty
                sarah.name = "Sarah"
                sarah.voicePresetId = VoicePreset.sceneDefault.id
                return AnyView(SayItAgainView(source: .scene(title: "Café · catching up",
                                                               targetLanguage: "en",
                                                               curriculum: c,
                                                               counterpart: sarah))
                    .environmentObject(appState))
            }
            return AnyView(SayItAgainView(source: .talk(talkDetailSession))
                .environmentObject(appState))
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

    /// Accurate but simple: a near-perfect score with no slips, and a range
    /// of a2 — the pair the Progress grammar band has to read as ≈A2.
    static var beginnerScorecard: SessionScorecard {
        SessionScorecard(
            vocabulary: AxisScore(score: 60, note: "Everyday words, used correctly."),
            grammar: AxisScore(score: 96, note: "No slips in what you said."),
            expressiveness: AxisScore(score: 40, note: "Short answers — add a detail."),
            fluency: AxisScore(score: 55, note: "Even pace, short turns."),
            pronunciation: nil,
            topLine: "Clear and simple — try linking two ideas.",
            cefrLevel: "a2",
            grammarRange: "a2")
    }

    /// One fully-populated finished talk — every section of the session
    /// detail page has material (scorecard + grammar slips, new words,
    /// expressions, say-it-better, suggestions → shadow lines, drill next).
    static var japaneseTalkSession: Session {
        let started = Date().addingTimeInterval(-900)
        let turns = [
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "久しぶり！最近、家事に追われてるって言ってたけど、少しは落ち着いた？", durationMs: 3200,
                 timestamp: started, suggestion: nil),
            Turn(id: UUID(), role: .user, audioURL: nil,
                 transcript: "うん、でも洗濯が溜まって、とても面倒くさいでした。", durationMs: 62_000,
                 timestamp: started.addingTimeInterval(6),
                 suggestion: TurnSuggestion(alternative: "うん、でも洗濯が溜まって、とても面倒くさかった。",
                                            reason: "い형용사의 과거형")),
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "なるほど。通勤も長いし、慌てて片付けるより、とりあえず一つずつでいいと思うよ。", durationMs: 4200,
                 timestamp: started.addingTimeInterval(70), suggestion: nil),
            Turn(id: UUID(), role: .user, audioURL: nil,
                 transcript: "そうだね。週末に掃除をするつもりです。", durationMs: 58_000,
                 timestamp: started.addingTimeInterval(80),
                 suggestion: TurnSuggestion(alternative: "そうだね。週末に掃除するつもり。",
                                            reason: "반말로 통일"))
        ]
        var summary = SessionSummary(
            phrasesUsed: [PhraseFeedback(userSaid: "面倒くさいでした",
                                         fluentAlternative: "面倒くさかった",
                                         reason: "い형용사의 과거형")],
            newPatternsDetected: [],
            suggestedDrills: ["週末にまとめて片付けるつもり。", "洗濯が溜まって面倒くさかった。"],
            overallNote: "자연스럽게 이어졌어요. 형용사 과거형만 다듬으면 돼요.",
            scorecard: sampleScorecard)
        summary.newWordsUsed = ["洗濯", "掃除", "溜まる"]
        summary.expressionsUsed = ["週末に掃除をする"]
        summary.expressionsOffered = ["家事に追われる", "とりあえず一つずつ", "少しは落ち着いた"]
        summary.grammarIssues = [
            GrammarIssue(quote: "とても面倒くさいでした",
                         correction: "とても面倒くさかった",
                         note: "い형용사는 かった로 과거를 만들어요")
        ]
        return Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!,
            userId: UUID(), targetLanguage: "ja", mode: .conversation,
            topic: "家事と通勤", startedAt: started,
            endedAt: started.addingTimeInterval(600),
            turns: turns, summary: summary)
    }

    /// Sample coaching text in the learner's language — coaching is native
    /// (see "Two languages"), so an English note on a Korean screenshot
    /// would show something the app never does.
    private static func coachNote(_ en: String, _ ko: String) -> String {
        LanguageCatalog.currentNative == "ko" ? ko : en
    }

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
                                            reason: coachNote("past tense", "지난 일이라 과거형이에요"))),
            Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                 transcript: "That's a compelling perspective — you clearly took the initiative to prioritize what mattered.", durationMs: 4200,
                 timestamp: started.addingTimeInterval(70), suggestion: nil),
            Turn(id: UUID(), role: .user, audioURL: nil,
                 transcript: "How relaxed I stayed, even on hard question.", durationMs: 58_000,
                 timestamp: started.addingTimeInterval(80),
                 suggestion: TurnSuggestion(alternative: "How relaxed I stayed, even on the hard questions.",
                                            reason: coachNote("article + plural", "the를 붙이고 복수형으로")))
        ]
        var summary = SessionSummary(
            phrasesUsed: [PhraseFeedback(userSaid: "it go really well",
                                         fluentAlternative: "it went really well",
                                         reason: coachNote("past tense", "지난 일이라 과거형이에요"))],
            newPatternsDetected: [],
            suggestedDrills: ["I'd say the trade-off was worth it.",
                              "Looking back, I would have prepared differently."],
            overallNote: "Confident, natural talk — tighten a few articles.",
            scorecard: sampleScorecard)
        summary.newWordsUsed = ["prepared", "relaxed", "interview"]
        summary.expressionsUsed = ["felt prepared"]
        summary.expressionsOffered = ["took the initiative", "what mattered most",
                                      "looking back on it"]
        summary.grammarIssues = [
            GrammarIssue(quote: "Honestly, it go really well.",
                         correction: "Honestly, it went really well.",
                         note: coachNote("past tense needed", "지난 일이라 과거형이에요")),
            GrammarIssue(quote: "even on hard question",
                         correction: "even on the hard questions",
                         note: coachNote("article + plural", "the를 붙이고 복수형으로"))
        ]
        return Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            userId: UUID(), targetLanguage: "en", mode: .conversation,
            topic: "Job interview", startedAt: started,
            endedAt: started.addingTimeInterval(600),
            turns: turns, summary: summary)
    }

    // MARK: - Vocabulary + expressions

    /// Cards spread across the drill deck's folder buckets (Soon / Tomorrow /
    /// Later / Learned) plus enough extra due cards to trip the session cap,
    /// so the chips row and "· N waiting" counter render populated.
    static func seedDrillFolders() {
        let hour: TimeInterval = 3600
        let day: TimeInterval = 24 * hour
        let future: [(String, TimeInterval, Int)] = [
            ("Could you say that one more time?", 10 * 60, 0),
            ("I'm still getting the hang of it.", 2 * hour, 0),
            ("That works for me.", day, 1),
            ("Let me get back to you on that.", day + 2 * hour, 1),
            ("I'd rather we met a bit earlier.", 3 * day, 2),
            ("It slipped my mind completely.", 7 * day, 3),
            ("We're on the same page.", 30 * day, 5),
            ("That's a fair point.", 30 * day, 5),
        ]
        for (tgt, delay, box) in future {
            DrillStore.shared.seed(DrillCard(
                sourcePhrase: "", targetPhrase: tgt, reason: "",
                createdAt: Date().addingTimeInterval(-day),
                lastReviewedAt: Date(),
                nextReviewAt: Date().addingTimeInterval(delay), box: box))
        }
        for i in 0..<22 {
            DrillStore.shared.seed(DrillCard(
                sourcePhrase: "I have went there \(i + 1) times",
                targetPhrase: "I have been there \(i + 1) times",
                reason: "past participle",
                createdAt: Date().addingTimeInterval(TimeInterval(-i) * hour),
                lastReviewedAt: nil,
                nextReviewAt: Date().addingTimeInterval(-hour), box: 0))
        }
    }

    /// `freshSchedule` wipes the study schedule first. The deck's folders now
    /// read from disk, and that file survives across launches on a simulator —
    /// so without this a screenshot (and the UI test that asserts every folder
    /// starts at 0) inherits whatever a previous run happened to snooze.
    /// A learner who finished setup and has never talked: the four intake
    /// answers are on file, `metAt` is nil, nothing has been remembered yet.
    /// Written straight to the store rather than through `savePersona`, which
    /// would try to sync a public intro from a capture run.
    static func seedUnmetPersona(into appState: AppState) {
        var p = UserPersona.empty
        p.displayName = "Eunggyu"
        p.city = "Munich"
        p.country = "Germany"
        p.interests = ["AI / tech", "parenting"]
        p.situations = ["Kita / school", "Client calls"]
        PersonaStore.shared.save(p)
        appState.persona = p
    }

    static func seedVocab(freshSchedule: Bool = false) {
        if freshSchedule { StudyScheduleStore.shared.removeAll() }
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
        _ = VocabStore.shared.ingestExpressions(
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            phrases: ["walk you through", "catch up on", "think it through",
                      "turned out to be", "handled it with grace"])
        _ = VocabStore.shared.addExpression("catch up on")
        _ = VocabStore.shared.addExpression("walk you through")
        _ = VocabStore.shared.addExpression("turned out to be")

        // A few review cards due NOW, so Home's "Review N cards" action shows.
        let due: [(String, String, String)] = [
            ("it go really well", "it went really well", coachNote("past tense", "지난 일이라 과거형이에요")),
            ("I very like it", "I really like it", coachNote("adverb choice", "very는 동사를 꾸미지 못해요")),
            ("more easy", "easier", coachNote("comparative form", "짧은 형용사는 -er로 비교해요")),
        ]
        for (src, tgt, why) in due {
            DrillStore.shared.seed(DrillCard(
                sourcePhrase: src, targetPhrase: tgt, reason: why,
                createdAt: Date(), lastReviewedAt: nil,
                nextReviewAt: Date().addingTimeInterval(-3600), box: 0))
        }
        // One legacy-style card with a WHOLE rambling turn as its source, to
        // verify the render-time fragment trim keeps the card on screen.
        DrillStore.shared.seed(DrillCard(
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
            Seed(source: .knownExpression, item: "on the same page",
                 quote: "Just so we're on the same page, it's Friday, right?"),
            Seed(source: .knownWord, item: "hectic",
                 quote: "This week has been pretty hectic at work."),
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


    // MARK: - Weekly test

    /// A week with something on every shelf: notebook words, a talk whose
    /// summary offered phrases the fluent self actually said, corrections
    /// with the learner's own wording, and fluent lines with audio on disk
    /// (the bundled ringtone stands in for a saved line).
    static func seedWeeklyTestWeek() {
        WeeklyTestStore.shared.removeAll()
        seedVocab()
        let uid = UUID()
        let ended = Date().addingTimeInterval(-2 * 3600)
        let started = ended.addingTimeInterval(-900)
        let lines: [(TurnRole, String)] = [
            (.fluentSelf, "So how did the move go? Did you end up hiring movers?"),
            (.user, "It was okay. I end up carrying most boxes myself."),
            (.fluentSelf, "That sounds exhausting. Honestly, next time I'd push back on doing it alone."),
            (.user, "Yeah, my back is still sore from it."),
            (.fluentSelf, "Give yourself a day off. You can always catch up on the unpacking later."),
            (.user, "I have to unpack the kitchen first, it's a chore."),
            (.fluentSelf, "Kitchens are the worst part. Let me walk you through how I did mine."),
            // The week report's quotes (`sampleWeekRecap`), so the grammar
            // and upgrade items find the learner's own lines.
            (.user, "Yesterday I went to the flat and the landlord says it's fine."),
            (.fluentSelf, "That's a relief. Did you sign anything yet?"),
            (.user, "Not yet. I was very tired after the move."),
            (.fluentSelf, "Fair enough. And the flat itself?"),
            (.user, "The flat is good for the price."),
        ]
        var turns: [Turn] = []
        for (i, line) in lines.enumerated() {
            var t = Turn(id: UUID(), role: line.0, audioURL: nil, transcript: line.1,
                         durationMs: line.0 == .user ? 9_000 : 3_500,
                         timestamp: started.addingTimeInterval(Double(i) * 20), suggestion: nil)
            if line.0 == .user, i == 1 {
                t.suggestion = TurnSuggestion(alternative: "I ended up carrying most of the boxes myself.",
                                              reason: "Past tense, and \"most of the\" before a noun.")
            }
            if line.0 == .fluentSelf,
               let wav = Bundle.main.url(forResource: "ringtone", withExtension: "wav"),
               let data = try? Data(contentsOf: wav) {
                // The store reads mp3/m4a only; AVAudioPlayer sniffs the bytes.
                TurnAudioStore.shared.save(data, turnId: t.id, fileExtension: "mp3")
            }
            turns.append(t)
        }
        var summary = SessionSummary(phrasesUsed: [
            PhraseFeedback(userSaid: "my back is still sore from it",
                           fluentAlternative: "my back is still sore from all that lifting",
                           reason: "Name what caused it."),
        ], newPatternsDetected: [], suggestedDrills: [],
           overallNote: "Relaxed and clear.", scorecard: sampleScorecard)
        summary.expressionsOffered = ["end up", "push back on", "catch up on", "walk you through"]
        summary.expressionsUsed = ["a chore"]
        let session = Session(id: UUID(), userId: uid, targetLanguage: "en", mode: .conversation,
                              topic: nil, startedAt: started, endedAt: ended,
                              turns: turns, summary: summary, origin: .free)
        SessionStore.shared.save(session)
        for turn in turns where turn.suggestion != nil {
            DrillStore.shared.seed(DrillCard(
                sourcePhrase: turn.transcript, targetPhrase: turn.suggestion!.alternative,
                reason: turn.suggestion!.reason, createdAt: ended, lastReviewedAt: nil,
                nextReviewAt: ended.addingTimeInterval(86_400), box: 0,
                sourceSessionId: session.id, sourceTurnId: turn.id))
        }
        DrillStore.shared.seed(DrillCard(
            sourcePhrase: "I have to unpack the kitchen first, it's a chore.",
            targetPhrase: "I have to unpack the kitchen first. It's such a chore.",
            reason: "Two sentences read better out loud.", createdAt: ended, lastReviewedAt: nil,
            nextReviewAt: ended.addingTimeInterval(86_400), box: 0,
            sourceSessionId: session.id, sourceTurnId: turns[5].id))
        VocabStore.shared.addStudying("chore")
        VocabStore.shared.addStudying("exhausting")
        // The closed week's report, coach written, so the paper never waits
        // on the network for its grammar and upgrade items.
        WeekRecapStore.shared.save(sampleWeekRecap)
    }

    /// A finished test on file for this week, so the result page and the
    /// Today card's done row render.
    static var sampleWeekRecap: WeekRecap {
        let week = WeekRecapBuilder.lastWeek()
        func day(_ n: Int, _ h: Int) -> Date { week.start.addingTimeInterval(Double(n) * 86_400 + Double(h) * 3600) }
        return WeekRecap(
            start: week.start, end: week.end,
            activeDays: [true, true, false, true, true, false, true],
            streak: 3,
            talkSeconds: 42 * 60, previousTalkSeconds: 28 * 60,
            talks: [.init(title: "Moving flats in Berlin", day: day(0, 2), minutes: 12, kind: "free"),
                    .init(title: "Asking the landlord about the deposit", day: day(1, 9), minutes: 7, kind: "scenario"),
                    .init(title: "Why rents keep rising", day: day(3, 10), minutes: 9, kind: "news"),
                    .init(title: "Catching up with Jenny", day: day(4, 11), minutes: 8, kind: "person"),
                    .init(title: "The weekend plan", day: day(6, 1), minutes: 6, kind: "free")],
            usedCount: 4,
            used: [.init(item: "end up", quote: "I ended up carrying most of the boxes myself."),
                   .init(item: "push back on", quote: "I pushed back on the deadline a little."),
                   .init(item: "chore", quote: "Cleaning the kitchen is my least favourite chore.")],
            cardsCleared: 12, wordsKnown: 9, expressionsKnown: 4,
            shadowTakes: 17, shadowAverage: 81, previousShadowAverage: 74,
            scenes: 3,
            nowYours: ["deposit", "landlord", "sublet", "boiler", "catch up on", "chore", "exhausting", "end up"],
            sentencesGot: ["I ended up carrying most of the boxes myself.", "I've lived here for two years."],
            newExpressionCount: 7,
            newExpressions: [.init(item: "catch up on", quote: "You can always catch up on the unpacking later."),
                             .init(item: "walk you through", quote: "Let me walk you through what the landlord actually needs."),
                             .init(item: "give yourself a day off", quote: "Honestly, give yourself a day off after the move.")],
            newCards: 6,
            stumbles: [.init(was: "I end up carrying", now: "I ended up carrying", count: 3),
                       .init(was: "since two years", now: "for two years", count: 2)],
            shakyLines: [],
            testScore: 5, testTotal: 7,
            coach: .init(
                headline: "You tell stories, but in the present tense",
                insight: "When you talk about something that already happened, you slip back into the present as the story goes on. It starts in the past and ends in the present.",
                insightQuote: "Yesterday I went to the flat and the landlord says it's fine.",
                grammar: [
                    .init(rule: "Past tense drops out halfway through a story",
                          examples: [.init(was: "the landlord says it's fine", now: "the landlord said it was fine"),
                                     .init(was: "I end up carrying", now: "I ended up carrying"),
                                     .init(was: "then she ask me", now: "then she asked me")],
                          tip: "Once a story starts with \u{201C}yesterday\u{201D} or \u{201C}last week\u{201D}, every verb stays in the past until it ends."),
                    .init(rule: "\u{201C}the\u{201D} before a place you both know",
                          examples: [.init(was: "went to kitchen", now: "went to the kitchen"),
                                     .init(was: "called landlord", now: "called the landlord")],
                          tip: "If you could point at it, it takes \u{201C}the\u{201D}.")],
                upgrades: [
                    .init(instead: "very tired", count: 5, better: "exhausted",
                          original: "I was very tired after the move.",
                          rewritten: "I was exhausted after the move.",
                          note: "One word does the work of two. Use it when tired isn't strong enough."),
                    .init(instead: "good", count: 9, better: "decent",
                          original: "The flat is good for the price.",
                          rewritten: "The flat is decent for the price.",
                          note: "Good, but not great: exactly what you meant about the flat.")],
                plan: ["Tell the story of the move again, and keep every verb in the past until the end.",
                       "Say \u{201C}exhausted\u{201D} once in your next talk instead of \u{201C}very tired\u{201D}.",
                       "Take this week's test. The two you missed are back."]))
    }

    static func seedWeekArchive() {
        let store = WeekRecapStore.shared
        let last = sampleWeekRecap
        for recap in store.load() { store.remove(endingAt: recap.end) }
        store.resetShown()
        let week: TimeInterval = 7 * 86_400
        let older = WeekRecap(
            start: last.start.addingTimeInterval(-week), end: last.end.addingTimeInterval(-week),
            activeDays: [true, false, true, false, false, true, false], streak: 1,
            talkSeconds: 28 * 60, previousTalkSeconds: 0, talks: [],
            usedCount: 1, used: [], cardsCleared: 5, wordsKnown: 3, expressionsKnown: 1,
            shadowTakes: 4, shadowAverage: 74, previousShadowAverage: nil, scenes: 1,
            nowYours: [], sentencesGot: [],
            newExpressionCount: 0, newExpressions: [], newCards: 2, stumbles: [], shakyLines: [],
            testScore: nil, testTotal: nil, coach: nil)
        store.save(older)
        store.markShown(older)
        store.save(last)
    }

    static var sampleQuietWeek: WeekRecap {
        let week = WeekRecapBuilder.lastWeek()
        return WeekRecap(
            start: week.start, end: week.end, activeDays: Array(repeating: false, count: 7), streak: 0,
            talkSeconds: 0, previousTalkSeconds: 12 * 60, talks: [],
            usedCount: 0, used: [], cardsCleared: 0, wordsKnown: 0, expressionsKnown: 0,
            shadowTakes: 0, shadowAverage: nil, previousShadowAverage: nil, scenes: 0,
            nowYours: [], sentencesGot: [],
            newExpressionCount: 0, newExpressions: [], newCards: 0, stumbles: [], shakyLines: [],
            testScore: nil, testTotal: nil, coach: nil)
    }

    static func seedFinishedWeeklyTest() {
        WeeklyTestStore.shared.removeAll()
        let now = Date()
        var items: [WeeklyTestItem] = [
            .init(id: UUID(), kind: .meaning, prompt: "A task you have to do regularly and find tedious.",
                  answer: "chore", options: ["chore", "errand", "hobby", "shift"]),
            .init(id: UUID(), kind: .meaning, prompt: "Making you feel very tired.",
                  answer: "exhausting", options: ["thrilling", "exhausting", "soothing", "spare"]),
            .init(id: UUID(), kind: .gap, prompt: "Honestly, next time I'd ______ doing it alone.",
                  answer: "push back on", options: ["end up", "push back on", "catch up on", "walk you through"]),
            .init(id: UUID(), kind: .gap, prompt: "You can always ______ the unpacking later.",
                  answer: "catch up on", options: ["catch up on", "push back on", "end up", "walk you through"]),
            .init(id: UUID(), kind: .build, prompt: "I end up carrying most boxes myself.",
                  answer: "I ended up carrying most of the boxes myself.",
                  options: ["most", "I", "myself.", "ended", "the", "up", "boxes", "carrying", "of", "end"]),
            .init(id: UUID(), kind: .listen, prompt: "", answer: "Give yourself a day off.",
                  options: ["Give yourself a day off.", "Kitchens are the worst part.", "That sounds exhausting."]),
            .init(id: UUID(), kind: .build, prompt: "my back is still sore from it",
                  answer: "my back is still sore from all that lifting",
                  options: ["sore", "from", "my", "all", "back", "that", "is", "lifting", "still", "it"]),
        ]
        let wrong: Set<Int> = [1, 4]
        var test = WeeklyTest(id: UUID(), targetLanguage: "en",
                              periodStart: now.addingTimeInterval(-7 * 86_400), periodEnd: now,
                              createdAt: now.addingTimeInterval(-600), items: items)
        test.startedAt = now.addingTimeInterval(-600)
        for (i, item) in items.enumerated() {
            let ok = !wrong.contains(i)
            let given = ok ? item.answer : (item.kind == .build ? "I end up carrying most of the boxes myself." : item.options.first { $0 != item.answer } ?? "")
            test.answers.append(WeeklyTestAnswer(itemId: item.id, given: given, correct: ok,
                                                 at: now.addingTimeInterval(Double(i) * 30 - 600)))
        }
        test.bestStreak = 3
        test.finishedAt = now.addingTimeInterval(-60)
        test.appliedAt = test.finishedAt
        items.removeAll()
        WeeklyTestStore.shared.save(test)
    }

    static func seedSessions(scored: Bool = false, beginner: Bool = false) {
        let uid = UUID()
        for day in 0..<3 {
            let ended = Date().addingTimeInterval(Double(-day) * 86_400 + 3_600)
            let started = ended.addingTimeInterval(-600)
            // beginner: one-clause present-tense replies with no slips — the
            // shape that read ≈C2 before grammar range existed.
            let turns = beginner ? [
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "How are you today?", durationMs: 1800,
                     timestamp: started, suggestion: nil),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "I am fine. I am tired.", durationMs: 4_000,
                     timestamp: started.addingTimeInterval(4), suggestion: nil),
                Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                     transcript: "What did you do?", durationMs: 1500,
                     timestamp: started.addingTimeInterval(10), suggestion: nil),
                Turn(id: UUID(), role: .user, audioURL: nil,
                     transcript: "I go to work. I eat lunch. I like pasta.", durationMs: 6_000,
                     timestamp: started.addingTimeInterval(14), suggestion: nil)
            ] : [
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
            var summary = scored ? SessionSummary(
                phrasesUsed: [], newPatternsDetected: [], suggestedDrills: [],
                overallNote: beginner ? "Clear and simple — try linking two ideas."
                                      : "Confident, natural talk — tighten a few articles.",
                scorecard: beginner ? beginnerScorecard : sampleScorecard) : nil
            // Phrases the fluent self offered — the library and the daily deck
            // read these off the session, so a capture run needs them to show
            // the heard-in-a-call rows at all.
            summary?.expressionsOffered = ["what surprised you most", "how did it go"]
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

/// The talk book opened on one bookmark tab.
private struct TalkBookCaptureHost: View {
    let session: Session
    let chapter: ConversationDetailView.Chapter

    var body: some View {
        NavigationStack {
            ConversationDetailView(session: session, initialChapter: chapter)
        }
    }
}

/// The seeded scenario book, optionally opened on one bookmark tab.
private struct BookCaptureHost: View {
    let scenarioId: UUID?
    let chapter: ScenarioDetailView.Chapter?

    var body: some View {
        NavigationStack {
            if let id = scenarioId {
                ScenarioDetailView(scenarioId: id, initialChapter: chapter)
            }
        }
    }
}

/// Presents `FeedbackSheet` over the Talk home, the way it arrives at the
/// end of the first call.
/// Presents `DailyAllowanceSheet` over the Talk home, the way the call screen
/// raises it when the day's allowance runs out.
private struct DaySpentCaptureHost: View {
    let kind: DailyAllowanceSheet.Kind
    let canUpgrade: Bool
    var allowance: Int? = nil
    var renewsOn: String = "Sep 14"
    var isTrial: Bool = false
    var planMinutesAfterTrial: Int? = nil
    var invite: InviteOffer? = nil
    var canTopUp: Bool = false
    @State private var showing = false

    var body: some View {
        ConversationHome()
            .sheet(isPresented: $showing) {
                DailyAllowanceSheet(kind: kind, canUpgrade: canUpgrade,
                                    allowance: allowance ?? (kind == .talk ? 150 : 60),
                                    renewsOn: renewsOn,
                                    isTrial: isTrial,
                                    planMinutesAfterTrial: planMinutesAfterTrial,
                                    canTopUp: canTopUp,
                                    invite: invite,
                                    onReview: {}, onUpgrade: {})
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showing = true }
            }
    }
}

/// Presents `UpdateAvailableSheet` over the Talk home, as the tab root does.
private struct UpdateCaptureHost: View {
    let required: Bool
    @State private var showing = false

    /// The notes a real release actually ships — a paragraph plus five
    /// bullets, verbatim from `fastlane/metadata/ko/release_notes.txt`. The
    /// capture is only worth anything at this length: a one-line note fits
    /// anywhere, and it was the real notes that ran off both ends of the sheet.
    private static let releaseNotes = """
    nawana를 시작합니다.

    말이 늘지 않는 이유는 하나 — 충분히 말하지 않아서예요. 60초 녹음으로 유창해진 미래의 내 목소리를 만들고, 매일 통화하세요. 통화가 끝나면 내가 쓴 단어·표현·문법으로 나만의 교재가 만들어져요.

    - 내 관심사에서 시작하는 매일 통화
    - 매 턴 돌아오는 유창한 버전
    - 통화가 끝나면 자동으로 만들어지는 나만의 교재
    - 내 목소리로 하는 섀도잉, 입으로 답하는 복습
    - 실제로 말한 것들로만 측정되는 레벨
    """

    var body: some View {
        ConversationHome()
            .sheet(isPresented: $showing) {
                UpdateAvailableSheet(
                    update: .init(latestBuild: 99, latestVersion: "1.1",
                                  notes: required ? nil : Self.releaseNotes,
                                  required: required),
                    onDismiss: {})
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showing = true }
            }
    }
}

private struct WelcomeCaptureHost: View {
    @State private var showing = false

    var body: some View {
        ConversationHome()
            .sheet(isPresented: $showing) {
                FreeTalkWelcomeSheet(minutes: 10) {}
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showing = true }
            }
    }
}

private struct FeedbackCaptureHost: View {
    @State private var showing = false

    var body: some View {
        ConversationHome()
            .sheet(isPresented: $showing) {
                FeedbackSheet(context: .returningTalk)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showing = true }
            }
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
                    // At the wire (2h left) → anxious.
                    tile(theme: 4, size: CGSize(width: 158, height: 158), compact: true, streak: 1284, done: false, hoursLeft: 2)
                    tile(theme: 2, size: CGSize(width: 158, height: 158), compact: true, streak: 7, done: true, hoursLeft: 0)
                }
                // Plenty of day left (8h) → calm, even at 1,284.
                tile(theme: 0, size: CGSize(width: 338, height: 158), compact: false, streak: 1284, done: false, hoursLeft: 8)
                // Near the wire (2h) → anxious.
                tile(theme: 5, size: CGSize(width: 338, height: 158), compact: false, streak: 1284, done: false, hoursLeft: 2)
                tile(theme: 3, size: CGSize(width: 338, height: 158), compact: false, streak: 7, done: true, hoursLeft: 0)
                tile(theme: 1, size: CGSize(width: 338, height: 158), compact: false, streak: 0, done: false, hoursLeft: 5)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(theme: Int, size: CGSize, compact: Bool, streak: Int, done: Bool, hoursLeft: Double) -> some View {
        let now = Date()
        return StreakCard(theme: theme, streakDays: streak, doneToday: done,
                          renderDate: now, deadline: now.addingTimeInterval(hoursLeft * 3600),
                          compact: compact)
            .frame(width: size.width, height: size.height)
            .background(WidgetGrid(theme: theme, shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)),
                                   step: streakPixel))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}

/// The Free Talk widget's Futureself surface at both families, then every
/// theme — the extension can't be screenshotted headlessly, so this renders the
/// same shared card the widget composes.
private struct FreeTalkWidgetGallery: View {
    private let small = CGSize(width: 158, height: 158)
    private let medium = CGSize(width: 338, height: 158)

    /// 0 = small + medium · 1 = every theme (two screens' worth of tiles).
    var page: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if page == 1 { themePage } else { mainPage }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder private var mainPage: some View {
        HStack(alignment: .top, spacing: 18) {
            tile(theme: 0, size: small, compact: true)
            tile(theme: 4, size: small, compact: true)
        }
        HStack(alignment: .top, spacing: 18) {
            tile(theme: 2, size: small, compact: true)
            tile(theme: 5, size: small, compact: true)
        }
        tile(theme: 0, size: medium, compact: false)
        tile(theme: 3, size: medium, compact: false)
    }

    @ViewBuilder private var themePage: some View {
        ForEach([[0, 1], [2, 3], [4, 5]], id: \.self) { pair in
            HStack(alignment: .top, spacing: 18) {
                ForEach(pair, id: \.self) { t in
                    tile(theme: t, size: small, compact: true)
                }
            }
        }
    }

    private func tile(theme: Int, size: CGSize, compact: Bool) -> some View {
        FreeTalkCard(theme: theme, compact: compact)
            .frame(width: size.width, height: size.height)
            .background(WidgetGrid(theme: theme,
                                   shape: AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)),
                                   step: futureselfCell, freeTalkSurface: compact))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }
}

/// The chip sheet over a call, presented on appear — a detented sheet can only
/// be photographed from inside a real presentation.
private struct GoalSheetPreview: View {
    @EnvironmentObject private var appState: AppState
    @State private var item: TalkGoalItem? = TalkGoalItem(key: "hectic", text: "hectic", isWord: true)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TalkGoalChipsRow(items: [
                    TalkGoalItem(key: "commute", text: "commute", isWord: true),
                    TalkGoalItem(key: "it slipped my mind", text: "it slipped my mind", isWord: false),
                    TalkGoalItem(key: "hectic", text: "hectic", isWord: true),
                ], used: ["commute"])
                Divider().opacity(0.15)
                DialogueLine(speaker: .other, name: "Future self") {
                    Text("So — how did the interview go yesterday?")
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $item) {
            TalkGoalSheet(item: $0, used: false).environmentObject(appState)
        }
    }
}

private struct PageIntroCaptureHost: View {
    let page: PageIntro.Page
    var step = 0
    @State private var showing = false

    var body: some View {
        Group {
            switch page {
            case .talk:     ConversationHome()
            case .watch:    WatchTab()
            case .review:   PracticeTab()
            case .progress: ProgressTab()
            case .routine:  NavigationStack { ActivityView() }
            }
        }
        .sheet(isPresented: $showing) { PageIntroSheet(page: page, initialStep: step) }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            showing = true
        }
    }
}
#endif
