import SwiftUI

/// Watch — simulate a specific situation BEFORE it happens and mine ideas
/// from it: how the fluent self opens, handles the awkward beats, which
/// expressions it reaches for. Three ways in, all landing in the same
/// situation composer:
///
///   1. People row (Instagram-stories style) — tap a persona → composer
///      scoped to them, with relationship-grounded situation ideas.
///   2. "Your own situation" — the real thing coming up ("Lufthansa
///      cabin-crew interview next week") in the composer's one-line BOX,
///      with the posting's link or a CV attached (`ScenarioBrief`). No
///      person required; the scene casts whoever fits.
///   3. "Common situations" — the same composer opened on its category
///      chain (cafe → ordering → order came out wrong).
///
/// Watching mints the scenario book that Practice reviews later.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var composer: ComposerConfig?
    @State private var watchScene: WatchTarget?

    /// What to play + whether to write a new take. A saved scenario is a
    /// TEMPLATE — tapping its card generates a fresh scene every time
    /// (replaying past material is Practice's job); a just-minted scenario
    /// from the composer generates its first scene.
    struct WatchTarget: Identifiable, Hashable {
        let scenario: Scenario
        let fresh: Bool
        var id: UUID { scenario.id }
    }
    @State private var showingNewVoice = false
    @State private var showingFind = false
    /// A Find-people stranger to start a live call with (fullScreenCover).
    @State private var callPerson: Counterpart?
    /// A bookmarked stranger tapped in the stories row — opens their card
    /// (intro, past talks, Preview/Talk) rather than the situation composer.
    @State private var personCard: Counterpart?
    /// Bookmarks live in UserDefaults, which publishes nothing — re-read them
    /// whenever the tab appears or the Find sheet closes.
    @State private var bookmarkedRemoteIds: Set<String> = []

    // The people map (`PeopleSky`) — a DEBUG experiment; the Me → Developer
    // toggle brings back the page below it.
    @AppStorage(PeopleSky.defaultsKey) private var peopleSkyFlag = true
    @State private var skyLens: PeopleSky.Lens =
        PeopleSky.Lens(rawValue: UserDefaults.standard.string(forKey: "skyLens") ?? "") ?? .all
    /// Find-people strangers not met yet, for the map's outer ring.
    @State private var skyPool: [Counterpart] = []
    /// Each pool persona's job, by remote id — the stranger's face icon.
    @State private var skyJobs: [String: String] = [:]
    /// Talks per person, read once per appearance (sessions aren't published).
    @State private var talksByPerson: [UUID: Int] = [:]
    @State private var showingSavedScenarios = false
    /// The category tab picked over the saved situations; nil = all.
    @State private var savedCategory: String?
    @State private var showingProfile = false
    /// The situation box under the map (DEBUG experiment, 2026-10-12): the
    /// person it is with — shared both ways with the box's own partner chip —
    /// and what they say in their bubble: one of THEIR situation ideas (the
    /// ones the person card and the box's reel already show), tapped into
    /// the box.
    @State private var dockPerson: Counterpart?
    /// The box was opened from a person's card: no category chips.
    @State private var dockNoChips = false
    /// The person whose card floats over the map (a tap on them).
    @State private var skyCard: Counterpart?
    @State private var skyCardPaywall = false
    @StateObject private var previewPlayer = AudioPlayer()
    @State private var dockBubble: String?
    @State private var dockFill = ""
    /// "New situation" was tapped: the tab bar steps aside for the box, the
    /// header gets Cancel, the map stays.
    /// Lives outside the view: hiding the tab bar rebuilds this tab's view,
    /// and a @State here came back false — the box vanished the moment it
    /// opened (2026-10-12).
    @ObservedObject private var creation = WatchCreation.shared
    private var creating: Bool {
        get { creation.creating }
        nonmutating set { creation.creating = newValue }
    }
    /// Who is in the middle of the screen, and the pan a pick asks for.
    @State private var skyCentred: Counterpart?
    @State private var skyScrollTarget: String?
    /// A pick is panning the map: the people it passes on the way are not
    /// "in the middle", so their bubbles stay down until it lands.
    @State private var panningUntil: Date = .distantPast
    @State private var bubbleTask: Task<Void, Never>?
    /// Greetings written this visit for strangers (people on file keep theirs).
    @State private var strangerGreetings: [UUID: String] = [:]
    /// The map is drawn once the pool is in, so nobody shifts when it lands.
    @State private var skyReady = false

    private var usesPeopleSky: Bool {
        // On for everyone from 1.1.8 (2026-10-12, founder). The Me →
        // Developer toggle still switches a debug build back to the old screen.
        #if DEBUG
        return peopleSkyFlag
        #else
        return true
        #endif
    }

    struct ComposerConfig: Identifiable {
        let id = UUID()
        var person: Counterpart?
        /// Which door the composer opens on: `.custom` is the one-line box
        /// with material attached (the real thing coming up); `.browse`
        /// starts on the category grid. See `ScenarioComposerSheet.Mode`.
        var mode: ScenarioComposerSheet.Mode = .browse
        /// Pre-selected category (browse mode only).
        var category: ScenarioComposerSheet.Category?
        /// Set when a saved scenario card was tapped — the composer opens
        /// prefilled as a settings sheet (edit, delete, or Watch a fresh take)
        /// instead of generating immediately.
        var editing: Scenario?
        /// A situation idea tapped on a person's page — the box opens with it.
        var situation: String? = nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if usesPeopleSky { peopleSkyPage } else { classicPage }
            }
            .background(Color(.systemGroupedBackground))
            // Writing a situation, the title steps aside for Cancel in its
            // place (top left, like any compose screen); the options on the
            // right stay. With the title showing, a leading item folds into
            // an overflow menu, so the title goes while creating.
            .navigationTitle(creating ? "" : "Watch")
            .toolbarTitleDisplayMode(creating ? .inline : .inlineLarge)
            .toolbar {
                if creating {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { creating = false; dockFill = "" }
                    }
                }
                if usesPeopleSky {
                    // The lens is an occasional choice, so it lives in a menu
                    // rather than a row the map gives up space to. The icon
                    // fills while the map is narrowed, so it can't be missed.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker(selection: $skyLens) {
                                ForEach(PeopleSky.Lens.allCases) { l in Text(l.title).tag(l) }
                            } label: { EmptyView() }
                        } label: {
                            Image(systemName: skyLens == .all
                                  ? "line.3.horizontal.decrease.circle"
                                  : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityLabel(Text(skyLens.title))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Every situation made before the map still has a
                        // home: the map shows people, this lists the rest.
                        Button { showingSavedScenarios = true } label: {
                            Image(systemName: "square.stack")
                        }
                        .accessibilityLabel(Text("Your scenarios"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // ONE people page: your own people and the shared pool,
                    // merged — the header button answers "who can I talk to".
                    Button { showingFind = true } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("People")
                }
            }
            .sheet(isPresented: $showingSavedScenarios) {
                NavigationStack {
                    savedScenariosPage
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Your scenarios")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingSavedScenarios = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                PersonaOnboardingView(initialPersona: appState.persona)
                    .environmentObject(appState)
            }
            .sheet(item: $composer) { cfg in
                // The ONE unified composer — same as Talk's "+", but its action
                // is Watch (play the scene). Saves the scenario, then plays it.
                // A saved card opens the SAME sheet in edit mode (cfg.editing):
                // review/tweak the settings, delete, or Watch a fresh take.
                ScenarioComposerSheet(person: cfg.person,
                                      host: .watch,
                                      mode: cfg.mode,
                                      initialCategory: cfg.category,
                                      editing: cfg.editing,
                                      initialSituation: cfg.situation,
                                      ctaTitle: "Watch", ctaIcon: "play.fill",
                                      onDelete: cfg.editing.map { s in
                                          { appState.deleteScenario(id: s.id); composer = nil }
                                      }) { scenario in
                    appState.saveScenario(scenario)
                    composer = nil
                    // Editing an existing scenario → its Watch is a fresh take
                    // into the same book; a just-minted one plays its first.
                    watchScene = WatchTarget(scenario: scenario, fresh: cfg.editing != nil)
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView().environmentObject(appState)
            }
            .onAppear { bookmarkedRemoteIds = PublicPersonaService.bookmarkedIds() }
            .sheet(item: $personCard) { person in
                NavigationStack {
                    FindPersonCard(
                        person: person,
                        bookmarks: $bookmarkedRemoteIds,
                        onTalk: { p in personCard = nil; callPerson = p },
                        onWatch: { p in
                            personCard = nil
                            watchScene = WatchTarget(scenario: freeTalkScenario(with: p),
                                                     fresh: true)
                        },
                        onCompose: { p in
                            personCard = nil
                            // "Make a situation" on a person is the WRITING
                            // door. Its own caption promises "something
                            // specific coming up with them", and a category
                            // grid answers a different question — you don't
                            // browse for the talk you're dreading with a
                            // particular person, you describe it.
                            if PeopleSky.dockEnabled {
                                // The same box the "New situation" button opens,
                                // with them as the person and no chips above it.
                                // One move: they are set in the same beat the box
                                // opens, so the map pans once, straight to them.
                                dockNoChips = true
                                creating = true
                                dockPerson = p
                            } else {
                                composer = ComposerConfig(person: p, mode: .custom)
                            }
                        })
                        .environmentObject(appState)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { personCard = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingFind,
                   onDismiss: { bookmarkedRemoteIds = PublicPersonaService.bookmarkedIds() }) {
                // Find people — strangers from the shared pool. Talk starts a
                // live call in THEIR preset voice; Preview plays the fluent
                // self and this person just TALKING — meeting a stranger is
                // already the situation, so it never asks the user to invent
                // one first (that's what "Make your own situation" is for).
                FindPeopleSheet(
                    onNew: { showingFind = false; showingNewVoice = true },
                    onTalk: { person in
                        showingFind = false
                        callPerson = person
                    },
                    onWatch: { person in
                        showingFind = false
                        watchScene = WatchTarget(scenario: freeTalkScenario(with: person),
                                                 fresh: true)
                    },
                    onCompose: { person in
                        showingFind = false
                        composer = ComposerConfig(person: person, mode: .custom)
                    },
                    onComposeIdea: { person, idea in
                        showingFind = false
                        composer = ComposerConfig(person: person, mode: .custom,
                                                  situation: idea)
                    })
                    .environmentObject(appState)
            }
            .fullScreenCover(item: $callPerson) { person in
                ConversationView(initialCounterpart: person)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $watchScene) { t in
                SceneWatchView(scenarioId: t.scenario.id, freshTake: t.fresh)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - The people map (DEBUG experiment, see `PeopleSky`)

    private var peopleSkyPage: some View {
        // The map starts panned to its centre, so if the navigation bar read
        // ITS offset the large title would come up already collapsed. An
        // outer vertical ScrollView that never moves is the one the bar
        // tracks, so "Watch" sits large like every other tab.
        // The map is the full screen height whether or not the tab bar is up
        // (it ignores the bottom edge): when "New situation" hides the bar,
        // a map that grew would re-centre and move everyone on it.
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    PeopleSkyMap(nodes: skyNodes,
                                 meName: appState.persona?.displayName ?? "",
                                 lens: $skyLens,
                                 onTap: { n in
                                     switch n.kind {
                                     case .person(let c), .pooled(let c):
                                         // A tap is for who they are; the middle of the
                                         // screen is for what to talk about.
                                         if PeopleSky.dockEnabled && !creating {
                                             openSkyCard(c)
                                         } else {
                                             personCard = c
                                         }
                                     case .role(let cat): composer = ComposerConfig(mode: .browse, category: cat)
                                     }
                                 },
                                 onTapMe: { showingProfile = true },
                                 focusedId: PeopleSky.dockEnabled && creating ? dockPerson?.id.uuidString : nil,
                                 bubbleId: PeopleSky.dockEnabled ? skyCentred?.id.uuidString : nil,
                                 bubble: PeopleSky.dockEnabled ? dockBubble : nil,
                                 onTapBubble: tapBubble,
                                 scrollTarget: skyScrollTarget,
                                 onCenterChange: { id in centre(on: id) },
                                 // The map runs under the tab bar: sit level with
                                 // "New situation", or above the box.
                                 backToMeBottom: creating ? 250 : 104,
                                 softenOthers: PeopleSky.dockEnabled && creating)
                        .frame(height: max(geo.size.height, 200))
                        // The map fades into the page at the bottom instead of
                        // being cut off where the box and the tab bar sit.
                        // The whole screen is the canvas: the map runs under the
                        // title and the tab bar and fades into the page at both
                        // ends instead of being cut off under the header.
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0),
                                                   .init(color: .black, location: 0.2),
                                                   .init(color: .black, location: 0.62),
                                                   .init(color: .clear, location: 0.94)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .opacity(skyReady ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: skyReady)
                }
            }
            .scrollDisabled(true)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
            .overlay(alignment: .bottom) {
                if PeopleSky.dockEnabled && creating {
                    // The "Your situation" box itself — chips, attach, the
                    // person, dictation — exactly as its sheet draws it.
                    ScenarioComposerSheet(person: nil, host: .watch, mode: .custom,
                                          ctaTitle: "Watch", ctaIcon: "play.fill",
                                          embedded: true,
                                          partnerSync: $dockPerson,
                                          situationSync: $dockFill,
                                          onPickCategory: pickDockCategory,
                                          showsCategoryChips: !dockNoChips) { scenario in
                        appState.saveScenario(scenario)
                        watchScene = WatchTarget(scenario: scenario, fresh: false)
                    }
                    .environmentObject(appState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: creating)

            .overlay(alignment: .bottom) {
                // Writing your own situation is its own button, not a tap on
                // "me": tapping a person opens that person, so tapping me
                // opens me (the profile).
                if !creating, PeopleSky.dockEnabled, let card = skyCard {
                    SkyPersonCard(person: appState.counterparts.first { $0.id == card.id } ?? card,
                                  onClose: { skyCard = nil },
                                  onCompose: { composeFromCard(card) },
                                  onWatch: {
                                      BillingGate.startScene(orShow: $skyCardPaywall) {
                                          let p = savedFromCard(card)
                                          skyCard = nil
                                          watchScene = WatchTarget(scenario: freeTalkScenario(with: p), fresh: true)
                                      }
                                  },
                                  onTalk: {
                                      BillingGate.start(orShow: $skyCardPaywall) {
                                          let p = savedFromCard(card)
                                          skyCard = nil
                                          callPerson = p
                                      }
                                  })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !creating {
                Button {
                    if PeopleSky.dockEnabled {
                        // Whoever is in the middle is who it's with — the box
                        // never starts on a default the map would fly to.
                        creating = true
                        if let c = skyCentred { dockPerson = c }
                    } else { composer = ComposerConfig(mode: .custom) }
                } label: {
                    Label("New situation", systemImage: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .modifier(GlassFloatingButton())
                .padding(16)
                }
            }
            .animation(.smooth(duration: 0.3), value: skyCard?.id)
            .sheet(isPresented: $skyCardPaywall) { PaywallView(source: "watch_person_card") }
            .onDisappear { previewPlayer.stop() }
            .task(id: appState.targetLanguage) { await loadSkyPool() }
            .task {
                // A pool that never answers must not leave the tab blank.
                try? await Task.sleep(for: .seconds(2.5))
                if !skyReady { skyReady = true }
            }
            #if DEBUG
            .onChange(of: skyReady) { _, ready in
                guard ready, let chip = UserDefaults.standard.string(forKey: "dockChip"),
                      let cat = ScenarioComposerSheet.presets.first(where: { $0.title == chip }) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pickDockCategory(cat) }
            }
            #endif
            .onChange(of: creation.creating) { _, on in
                if !on { dockNoChips = false } else { skyCard = nil }
            }
            .onChange(of: dockPerson?.id) { _, id in
                // Picked in the box (its person chip, or a category chip):
                // bring them to the middle. Picked BY the middle: already there.
                guard PeopleSky.dockEnabled, creating, let id else { return }
                panningUntil = Date().addingTimeInterval(0.7)
                skyScrollTarget = nil
                DispatchQueue.main.async { skyScrollTarget = id.uuidString }
                // Once there, they are the one in the middle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { centre(on: id.uuidString, force: true) }
            }
            .onAppear {
                countTalks()
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "openSaved") { showingSavedScenarios = true }
                // `-dockChip Work` captures creation mode with a chip picked
                // (once the pool is in); `-dockCreate 1` just opens it.

                #endif
            }
    }

    // MARK: - The situation dock

    /// A chip in the box picks the person that situation is with — someone
    /// of the learner's own first, then a stranger already met, then one from
    /// the pool. No match leaves the box's person as it was.
    private func pickDockCategory(_ cat: ScenarioComposerSheet.Category) {
        let candidates = appState.counterparts.filter { $0.remoteId == nil }
            + appState.counterparts.filter { $0.remoteId != nil }
            + skyPool.filter { p in !appState.counterparts.contains { $0.remoteId == p.remoteId } }
        guard let match = candidates.first(where: { Self.fits($0, cat, job: $0.remoteId.flatMap { skyJobs[$0] }) })
        else { return }
        dockPerson = match
    }

    /// Someone came to the middle of the screen (or nobody is there now).
    /// Their bubble rises once they have settled there; while creating they
    /// also become who the situation is with.
    private func centre(on id: String?, force: Bool = false) {
        if !force, Date() < panningUntil { return }
        if !force, id == skyCentred?.id.uuidString { return }
        bubbleTask?.cancel()
        dockBubble = nil
        previewPlayer.stop()
        let person = id.flatMap { id in
            appState.counterparts.first { $0.id.uuidString == id } ?? skyPool.first { $0.id.uuidString == id }
        }
        skyCentred = person
        guard let person else { return }
        bubbleTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await sayGreeting(for: person)
        }
    }

    /// A tap on someone: their card floats up over the bottom of the map and
    /// they come to the middle, above it, where their greeting rises.
    private func openSkyCard(_ c: Counterpart) {
        skyCard = c
        panningUntil = Date().addingTimeInterval(0.7)
        skyScrollTarget = nil
        let id = c.id.uuidString
        DispatchQueue.main.async { skyScrollTarget = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { centre(on: id, force: true) }
    }

    /// The card's "Make a situation": the card goes down as the box comes
    /// up, in one motion, with them already the person it's with.
    private func composeFromCard(_ c: Counterpart) {
        withAnimation(.smooth(duration: 0.35)) {
            skyCard = nil
            dockNoChips = true
            creating = true
            dockPerson = c
        }
    }

    /// Meeting someone from the pool files them, like the full card does.
    private func savedFromCard(_ c: Counterpart) -> Counterpart {
        if let on = appState.counterparts.first(where: { $0.id == c.id }) { return on }
        appState.saveCounterpart(c)
        return appState.counterparts.first(where: { $0.id == c.id }) ?? c
    }

    /// Tapping their greeting answers it: the box opens with them as the
    /// person the situation is with.
    private func tapBubble() {
        guard let person = skyCentred else { return }
        if creating {
            dockPerson = person
        } else {
            creating = true
            dockPerson = person
        }
    }

    /// Their greeting, over their face: the line written for them (in the
    /// person form, or at publish for someone from the pool), else one written
    /// now — kept on a person on file, remembered this visit for a stranger.
    private func sayGreeting(for person: Counterpart) async {
        let lang = appState.targetLanguage
        let onFile = appState.counterparts.first { $0.id == person.id }
        // A person on file whose line came from an older prompt is written
        // again before it is shown (the learner's own line never is).
        if let onFile, onFile.greetingNeedsWriting(in: lang, current: GreetingEngine.promptVersion),
           !onFile.greeting(in: lang).isEmpty {
            await GreetingEngine.ensure(for: person.id, appState: appState)
        }
        var line = (appState.counterparts.first { $0.id == person.id } ?? person).greeting(in: lang)
        if line.isEmpty { line = strangerGreetings[person.id] ?? "" }
        if line.isEmpty {
            if appState.counterparts.contains(where: { $0.id == person.id }) {
                await GreetingEngine.ensure(for: person.id, appState: appState)
                line = appState.counterparts.first { $0.id == person.id }?.greeting(in: lang) ?? ""
            } else if let fresh = try? await GreetingEngine.write(
                for: person, persona: appState.persona, targetLanguage: lang) {
                strangerGreetings[person.id] = fresh
                line = fresh
            }
        }
        guard !line.isEmpty, skyCentred?.id == person.id else { return }
        dockBubble = line
        // Felt as they speak: one firm tap as the bubble rises.
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()
        haptic.impactOccurred()
        playVoicePreview(for: person)
    }

    /// Their voice as their bubble rises. A person from the pool reads the
    /// start of their own intro in their own voice — clips that ship with
    /// the app (`Resources/PeopleVoices`, one per persona), so scrolling past
    /// people spends nothing. Your own people fall back to their preset's
    /// sample; a voice with no clip stays silent rather than paying for one.
    private func playVoicePreview(for person: Counterpart) {
        previewPlayer.stop()
        let lang = appState.targetLanguage.split(separator: "-").first.map(String.init) ?? appState.targetLanguage
        var url: URL?
        if let rid = person.remoteId, !rid.hasPrefix("builtin:") {
            url = Bundle.main.url(forResource: "intro-\(rid.lowercased())", withExtension: "mp3")
        }
        if url == nil, !person.voicePresetId.isEmpty {
            url = Bundle.main.url(forResource: "preview-\(lang)-\(person.voicePresetId)", withExtension: "mp3")
        }
        guard let url, let data = try? Data(contentsOf: url) else { return }
        try? previewPlayer.play(data, source: "voice_preview") {}
    }

    /// Who a common situation is with, read off what the learner wrote about
    /// their people and what a stranger does.
    static func fits(_ c: Counterpart, _ cat: ScenarioComposerSheet.Category, job: String?) -> Bool {
        let text = [c.relationship, c.relationshipKind ?? "", c.intro, c.background, job ?? ""]
            .joined(separator: " ").lowercased()
        let words: [String]
        switch cat.title {
        case "Work": words = ["coworker", "manager", "boss", "colleague", "team", "상사", "팀장", "동료", "부장", "과장", "上司", "同僚", "kollege"]
        case "Social": words = ["friend", "친구", "友達", "freund"]
        case "School": words = ["teacher", "fellow parent", "parent", "선생님", "학부모", "先生", "lehrer"]
        case "Cafe": words = ["barista", "cafe", "café", "coffee", "바리스타", "카페", "カフェ"]
        case "Travel": words = ["flight", "airline", "hotel", "travel", "guide", "승무원", "호텔", "여행", "ホテル"]
        case "Health": words = ["nurse", "doctor", "pharmac", "간호", "의사", "약사", "看護", "医師", "arzt"]
        case "Shopping": words = ["shop", "store", "retail", "sales", "점원", "가게", "店"]
        case "Phone": words = ["support", "call center", "customer service", "상담", "コールセンター"]
        default: words = []
        }
        return words.contains { text.contains($0) }
    }

    private var skyNodes: [PeopleSky.Node] {
        var practiced: [UUID: Int] = talksByPerson
        var kept: Set<UUID> = []
        for s in appState.scenarios {
            guard let id = s.counterpartId else { continue }
            practiced[id, default: 0] += 1
            if !s.isMeetingScene && s.isTopic != true { kept.insert(id) }
        }
        var nodes: [PeopleSky.Node] = appState.counterparts.map { c in
            PeopleSky.Node(id: c.id.uuidString, name: c.name, kind: .person(c),
                           ring: PeopleSky.ring(for: c), isMine: c.remoteId == nil,
                           practiced: practiced[c.id] ?? 0, hasKept: kept.contains(c.id),
                           symbol: PeopleSky.symbol(for: c, occupation: c.remoteId.flatMap { skyJobs[$0] }),
                           eyebrow: skyEyebrow(c))
        }
        let metRemote = Set(appState.counterparts.compactMap(\.remoteId))
        let unmet = skyPool.filter { !metRemote.contains($0.remoteId ?? "") }
        // a few new faces on "All", the same few every visit
        let featured = Set(unmet.map(\.id.uuidString).sorted().prefix(6))
        nodes += unmet.map { c in
            PeopleSky.Node(id: c.id.uuidString, name: c.name, kind: .pooled(c), ring: 2,
                           isMine: false, practiced: 0, hasKept: false,
                           symbol: PeopleSky.symbol(for: c, occupation: c.remoteId.flatMap { skyJobs[$0] }),
                           eyebrow: skyEyebrow(c),
                           featured: featured.contains(c.id.uuidString))
        }
        // The common situations (cafe, travel, work…) are chips in the
        // "Your own situation" sheet, not faces on the map: the map is people.
        // Seats are dealt in this order, so it must not follow the store's:
        // saving a person (their ideas, a talk) reorders `counterparts`, and
        // the whole map used to reshuffle under the learner's finger.
        return nodes.sorted { $0.id < $1.id }
    }

    /// Over the name on the map: the relationship in the learner's own words
    /// for their people, the job (else the city) for a stranger, and who a
    /// public figure is.
    private func skyEyebrow(_ c: Counterpart) -> String? {
        switch c.cast {
        case .ownPerson: return c.relationship
        case .publicFigure:
            return c.publicIdentity?.components(separatedBy: "·").last?
                .trimmingCharacters(in: .whitespaces)
        case .stranger:
            // a label, not a sentence: the job's first phrase, else the city,
            // else nothing — a cut-off intro line is noise
            let short: (String) -> String? = { text in
                let head = text.split(whereSeparator: { ",.;·(".contains($0) }).first
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                return (1...18).contains(head.count) ? head : nil
            }
            return short(c.remoteId.flatMap { skyJobs[$0] } ?? "") ?? short(c.location)
        }
    }

    private func loadSkyPool() async {
        // The map is shown once the pool is IN (or truly failed) and in a
        // later transaction than it lands in. A cancelled fetch — the tab's
        // task restarts when the view appears twice — used to count as
        // "ready": the half-built map faded in and everyone then slid to
        // their real seats.
        do {
            let pool = try await PublicPersonaService.fetchPool(language: appState.targetLanguage)
            if PublicPersonaService.syncOwnVoices(pool: pool, counterparts: appState.counterparts) {
                appState.reloadCounterparts()
            }
            skyPool = pool.map { PublicPersonaService.asCounterpart($0, existing: appState.counterparts) }
            skyJobs = Dictionary(pool.map { ($0.id, $0.occupation) }, uniquingKeysWith: { a, _ in a })
        } catch {
            if Task.isCancelled || error is CancellationError { return }
        }
        DispatchQueue.main.async { skyReady = true }
        #if DEBUG
        // `-skyCard 1` captures a person's floating card.
        if UserDefaults.standard.bool(forKey: "skyCard"), skyCard == nil,
           let first = appState.counterparts.first(where: { $0.remoteId == nil }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openSkyCard(first) }
        }
        #endif
    }

    private func countTalks() {
        var counts: [UUID: Int] = [:]
        for s in SessionStore.shared.load() {
            if let id = s.counterpartId { counts[id, default: 0] += 1 }
        }
        talksByPerson = counts
    }

    /// Opens the composer, closing the saved-situations sheet first when it
    /// is up — two sheets can't be presented from one stack at once.
    private func open(_ cfg: ComposerConfig) {
        if showingSavedScenarios {
            showingSavedScenarios = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { composer = cfg }
        } else {
            composer = cfg
        }
    }

    /// The page before the people map — three sections stacked.
    private var classicPage: some View {
            // A ScrollView, NOT a List: every section here is a custom grid or
            // card. Inside a List each grid lives in one row, and the
            // inset-grouped cell mask rounds the row's corners — visibly
            // clipping whatever chip/card sits at an edge — and long-press
            // context menus preview the WHOLE row instead of one card.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    peopleSection
                    newSituationSection
                    scenariosSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
    }

    /// The scenario behind "Watch" on a Find-people card: no situation to
    /// build, just the two of them talking. Reused (not re-minted) per person
    /// so every watch lands in the SAME book — the study material from
    /// meeting this person accumulates instead of scattering across one-shot
    /// scenarios, and the second watch replays instead of regenerating.
    ///
    /// Kept DELIBERATELY short. The person's intro, background and style are
    /// already injected by `ScenarioCurriculumEngine`'s counterpart block;
    /// repeating them here only made the prompt longer, and a longer prompt is
    /// a longer wait before the first line is spoken.
    private func freeTalkScenario(with person: Counterpart) -> Scenario {
        if let existing = appState.scenarios.first(where: {
            $0.counterpartId == person.id && $0.category == Self.meetingCategory
        }) {
            return existing
        }
        var s = Scenario(
            environment: "Talking with someone you've just met, already past the hellos",
            role: person.relationship.isEmpty ? person.name : person.relationship,
            // Two rules, in order. FIRST the overlap (the engine computes it
            // and hands it over): strangers open on what they share, and
            // picking a fact off one side's biography at random is what made
            // scenes land on strange subjects — especially against a real
            // user's thin auto-published intro, where there was nothing to
            // pick and the model filled the gap itself. THEN the ban on the
            // interview, because "getting to know each other" is a shape the
            // model will fill identically for everyone.
            notes: "Build the scene on the COMMON GROUND given below — that is "
                + "the subject. Get specific about it fast. NOT a "
                + "get-to-know-you interview: no running through where are you "
                + "from / what do you do / what are your hobbies. Land "
                + "mid-subject, the way real talk does."
        )
        s.counterpartId = person.id
        s.isMeeting = true
        s.category = Self.meetingCategory
        s.categoryIcon = "person.2.wave.2"
        s.summary = "Free talk with \(person.name)"
        appState.saveScenario(s)
        return s
    }

    private static let meetingCategory = "Meeting"

    /// Who the stories row shows: the people the user MADE, plus the Find
    /// people strangers they bookmarked. Having talked with someone is not
    /// enough to earn a slot here — one curious call would otherwise pin a
    /// stranger next to the user's actual friends forever. Every person
    /// talked with is still one tap away under Find people → "People you've
    /// met"; the bookmark is what promotes them to this row.
    private var rowPeople: [Counterpart] {
        let own = appState.counterparts.filter { $0.remoteId == nil }
        let kept = appState.counterparts.filter {
            guard let rid = $0.remoteId else { return false }
            return bookmarkedRemoteIds.contains(rid)
        }
        return own + kept
    }

    // MARK: - 1. People (stories row)

    /// No caption under any section on this page (2026-09-26, user
    /// decision: "none of them are needed"). Each one had grown into a
    /// paragraph that mixed what the screen already shows with a rule it
    /// doesn't — and the mix is what made them read as filler. The rules
    /// they carried are written down in this file's comments instead: a
    /// talk alone doesn't keep someone in this row (a bookmark does), the
    /// two doors mint the same scenario, and every watch writes a fresh
    /// take. If one has to come back, it comes back as ONE sentence
    /// carrying only the part the screen cannot say.
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // No Find button here any more: the page header's person.2 opens
            // the ONE people page (your people + the shared pool), so the row
            // needs no second door beside it.
            sectionHeader("People")
            // Making a person is pinned to the left, outside the scroller —
            // as the last bubble it slid off the row the moment the user had
            // a few people, exactly like Find people did before it moved up
            // into the header.
            HStack(alignment: .top, spacing: 16) {
                addPersonBubble
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(rowPeople) { c in
                            personBubble(c)
                        }
                    }
                    // Full-bleed scroller: cancel the page's side padding so
                    // avatars run to the trailing edge, then restore it inside.
                    .padding(.trailing, 20)
                }
                .padding(.trailing, -20)
            }
            .padding(.vertical, 6)
        }
    }

    private func personBubble(_ c: Counterpart) -> some View {
        Button {
            // EVERY bubble opens the person's card. They sit in one row, so
            // they have to answer a tap the same way — one used to jump
            // straight into the situation composer while the other opened a
            // card, which made two identical-looking circles behave like two
            // different controls. The card is the richer answer: who they are,
            // the talks so far, and every action they support (the composer
            // among them, for the people the user made).
            personCard = c
        } label: {
            VStack(spacing: 6) {
                PersonBubble(name: c.name, photoId: c.id)
                Text(c.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
    }

    private var addPersonBubble: some View {
        Button { showingNewVoice = true } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: 64, height: 64)
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Create")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New person")
    }

    // MARK: - Your scenarios (the same list Talk shows — watch them here too)

    private var savedScenarios: [Scenario] {
        // Meetings are excluded: a talk with someone from Find people is
        // not a situation the user built, and it belongs in Practice with the
        // rest of the review material, not in this list.
        appState.scenarios.filter { $0.isTopic != true && !$0.isMeetingScene }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    @ViewBuilder
    private var scenariosSection: some View {
        if !savedScenarios.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Your scenarios")
                scenariosGrid
            }
        }
    }

    private var scenariosGrid: some View {
        scenarioGrid(savedScenarios)
    }

    private func scenarioGrid(_ list: [Scenario]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(list) { s in
                scenarioCard(s)
            }
        }
    }

    /// The categories the saved situations actually carry, most used first —
    /// the tabs over the list. A category with nothing in it is never a tab.
    private var savedCategories: [(name: String, icon: String?)] {
        var count: [String: Int] = [:], icon: [String: String] = [:]
        for s in savedScenarios {
            guard let c = s.category?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { continue }
            count[c, default: 0] += 1
            if icon[c] == nil { icon[c] = s.categoryIcon }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, icon[$0.key]) }
    }

    /// The saved-situations sheet: category tabs on top, the cards below.
    private var savedScenariosPage: some View {
        let shown = savedCategory.map { c in savedScenarios.filter { $0.category == c } } ?? savedScenarios
        return ScrollView {
            scenarioGrid(shown)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if savedCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryTab(title: explain("All"), icon: nil, selected: savedCategory == nil) {
                            savedCategory = nil
                        }
                        ForEach(savedCategories, id: \.name) { c in
                            categoryTab(title: explain(String.LocalizationValue(c.name)), icon: c.icon,
                                        selected: savedCategory == c.name) {
                                savedCategory = c.name
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: savedCategory)
    }

    @ViewBuilder
    private func categoryTab(title: String, icon: String?, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        let label = Group {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
        }
        Button(action: action) { label }
            .buttonStyle(SoftChipStyle(selected: selected))
    }

    /// Grouped-list-style section title, hand-rolled since the page left List.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func scenarioCard(_ s: Scenario) -> some View {
        let personaName = s.counterpartId.flatMap { id in
            appState.counterparts.first { $0.id == id }?.name
        }
        let partner = personaName
            ?? (s.role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.role)
        // The concrete situation under the tidy title — only when the title
        // isn't already the environment text (rows with no summary show the
        // environment AS the title, so a blurb would just repeat it).
        let env = s.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        let blurb = env.caseInsensitiveCompare(s.cardTitle) == .orderedSame ? nil : env
        return Button {
            // Settings sheet first, not straight to generation — check the
            // situation/voice, tweak or delete, then Watch from there.
            open(ComposerConfig(editing: s))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if let personaName {
                        if let pid = s.counterpartId, CounterpartPhotoStore.shared.hasPhoto(pid) {
                            PersonBubble(name: personaName, photoId: pid, size: 32)
                        } else {
                            Text(Books.initials(personaName))
                                .font(.title3.weight(.bold)).foregroundStyle(.tint)
                        }
                    } else {
                        Image(systemName: s.categoryIcon ?? Books.roleIcon(for: s.role))
                            .font(.title2).foregroundStyle(.tint)
                    }
                    Spacer(minLength: 8)
                    // Tap opens the settings sheet; Watch (a fresh take) is its
                    // CTA — the play glyph still names the card's end action.
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let category = s.category, personaName == nil {
                        Text(category)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(s.cardTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blurb {
                        Text(blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if let partner {
                        Text("with \(partner)").lineLimit(1)
                    }
                    if partner != nil && s.lastUsedAt != nil {
                        Text(verbatim: "·")
                    }
                    if let last = s.lastUsedAt {
                        Text(last, format: .relative(presentation: .named)).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            // Fill the row's height so a short card matches its taller sibling
            // (LazyVGrid sizes the row to the tallest cell).
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Long-press preview hugs THIS card's rounded rect (outside a
            // List it would default to the view's rectangular bounds).
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteScenario(id: s.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - 2. New situation — two doors, side by side

    /// Two ways in, as equals. "Your own situation" is the real thing coming
    /// up — one line, with the posting's link or a CV attached — and opens
    /// the composer's box with no category grid in the way. "Common
    /// situations" opens the same composer on its category chain. Both mint
    /// the same `Scenario`; only the starting point differs. Until 2026-09-25
    /// both landed in ONE composer that opened on the category grid, so
    /// someone writing their own situation scrolled past chips first.
    private var newSituationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("New situation")
            HStack(spacing: 10) {
                doorButton(title: "Your own situation",
                           subtitle: explain("One line, plus your material"),
                           icon: "square.and.pencil",
                           prominent: true) {
                    composer = ComposerConfig(mode: .custom)
                }
                doorButton(title: "Common situations",
                           subtitle: explain("Pick from categories"),
                           icon: "square.grid.2x2",
                           prominent: false) {
                    composer = ComposerConfig(mode: .browse)
                }
            }
        }
    }

    private func doorButton(title: LocalizedStringKey, subtitle: String, icon: String,
                            prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // TOP-aligned, not centred. The two doors are different heights
            // (one subtitle wraps, the other doesn't) and `minHeight` pads
            // the short one, so a centred row floated its icon and title
            // down the card while its neighbour's sat at the top — the two
            // glyphs never lined up with each other.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(prominent ? Color.accentColor.opacity(0.12)
                                : Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The chain data

    /// The situation chain the old "Likely situations" grid was drawn from.
    /// Not rendered on this page since 2026-09-25 (the "Common situations"
    /// door opens the composer's category grid instead); kept as the seed
    /// list of situations the composer's ideas are tuned against.

    struct SituationBranch: Identifiable {
        let id = UUID()
        let label: String
        /// Card symbol — only meaningful on top-level (grid) entries.
        var icon: String = "bubble.left.and.bubble.right"
        var children: [SituationBranch] = []
        /// Set on leaves: the assembled, ready-to-edit situation.
        var situation: String?
    }

    static let situationTree: [SituationBranch] = [
        SituationBranch(label: "Cafe", icon: "cup.and.saucer.fill", children: [
            SituationBranch(label: "Ordering", children: [
                SituationBranch(label: "Order came out wrong",
                                situation: "At a cafe: my order came out wrong, and I want to point it out politely and get it fixed."),
                SituationBranch(label: "Asking for a recommendation",
                                situation: "At a cafe: I can't decide, so I ask the barista what they'd recommend and chat a little."),
                SituationBranch(label: "Complicated custom order",
                                situation: "At a cafe: ordering a drink with several modifications, and the barista has follow-up questions.")
            ]),
            SituationBranch(label: "Paying", children: [
                SituationBranch(label: "Card declined",
                                situation: "At a cafe: my card gets declined at the register and I sort it out without holding up the line.")
            ])
        ]),
        SituationBranch(label: "Travel", icon: "airplane", children: [
            SituationBranch(label: "Immigration control", children: [
                SituationBranch(label: "Purpose-of-visit questions",
                                situation: "At immigration control: the officer asks why I'm visiting, how long I'm staying, and where."),
                SituationBranch(label: "Problem with my documents",
                                situation: "At immigration control: something's off with my documents and I explain calmly.")
            ]),
            SituationBranch(label: "Hotel", children: [
                SituationBranch(label: "Room isn't ready",
                                situation: "Hotel front desk: I arrive early, the room isn't ready, and I negotiate my options."),
                SituationBranch(label: "Something's wrong with the room",
                                situation: "Hotel front desk: the room has a problem and I ask to have it fixed or changed.")
            ])
        ]),
        SituationBranch(label: "Work", icon: "briefcase.fill", children: [
            SituationBranch(label: "Interview", children: [
                SituationBranch(label: "Job interview",
                                situation: "A job interview: introducing myself, walking through my experience, and why I want this role.")
            ]),
            SituationBranch(label: "Meeting", children: [
                SituationBranch(label: "Presenting my idea",
                                situation: "A team meeting: I present my idea, field questions, and handle pushback.")
            ]),
            SituationBranch(label: "With my manager", children: [
                SituationBranch(label: "Asking for time off",
                                situation: "A one-on-one with my manager: asking for time off next month and handling their concerns.")
            ])
        ]),
        SituationBranch(label: "Health", icon: "cross.case.fill", children: [
            SituationBranch(label: "Doctor's visit", children: [
                SituationBranch(label: "Describing a symptom",
                                situation: "At the doctor's office: describing a symptom I've had for a week and answering their questions.")
            ])
        ]),
        SituationBranch(label: "Shopping", icon: "bag.fill", children: [
            SituationBranch(label: "Returns", children: [
                SituationBranch(label: "No receipt",
                                situation: "At a store: returning an item without the receipt, and the clerk is skeptical.")
            ])
        ])
    ]
}

// MARK: - PersonBubble

/// THE counterpart avatar — initials on a tinted circle. Every surface that
/// shows a person (the stories row, the composer header, onboarding's People
/// visual) renders through this one view so they can't drift apart.
/// Whether the Watch tab is writing a new situation: the tab bar steps aside
/// (`RootTabView`), the box shows under the map, Cancel is in the header.
@MainActor
final class WatchCreation: ObservableObject {
    static let shared = WatchCreation()
    @Published var creating: Bool = {
        #if DEBUG
        return DebugCapture.startsCreating
        #else
        return false
        #endif
    }()
}

struct PersonBubble: View {
    let name: String
    /// The person's id, for their photo (`CounterpartPhotoStore`). nil, or an
    /// id with no photo on file, draws initials — the look every person had
    /// until photos existed.
    var photoId: UUID? = nil
    var size: CGFloat = 64

    @ObservedObject private var photos = CounterpartPhotoStore.shared

    var body: some View {
        ZStack {
            if let id = photoId, let img = photos.image(for: id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
            } else {
                Circle().fill(Color.accentColor.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
                Text(Books.initials(name))
                    .font(size >= 56 ? .headline.weight(.bold) : .caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .id(photos.version)
    }
}

/// The floating "Your own situation" button wears the same glass as the tab
/// bar and the header buttons around it — a solid blue pill with a shadow sat
/// on the map like a sticker. Before iOS 26 it falls back to a material pill.
struct GlassFloatingButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.accentColor)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .background(Capsule().fill(.regularMaterial))
        }
    }
}


/// A person, as a card floating over the bottom of the map. Closed, it is
/// who they are in a line or three and one row of actions — less than half
/// the screen, so the map and them in its middle stay in view. Opened (tap
/// the text), it grows upward like an accordion into everything the old
/// full page held: the whole intro, topics, their voice, your talks.
struct SkyPersonCard: View {
    let person: Counterpart
    let onClose: () -> Void
    let onCompose: () -> Void
    let onWatch: () -> Void
    let onTalk: () -> Void

    @State private var expanded: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "skyCardOpen")
        #else
        false
        #endif
    }()

    private var about: String {
        if person.personaKind == "user" { return "" }
        return person.intro.isEmpty ? person.background : person.intro
    }

    private var voiceName: String {
        VoicePreset.known(id: person.voicePresetId)?.displayName ?? explain("Their own")
    }

    private var pastTalks: [Session] {
        SessionStore.shared.load()
            .filter { $0.counterpartId == person.id && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PersonBubble(name: person.name, photoId: person.id, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).font(.headline)
                    let cap = PartnerPickerSheet.caption(for: person)
                    if !cap.isEmpty {
                        Text(cap).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            details

            // One row: the situation keeps its words (it is the card's
            // point), Watch and Talk are their glyphs alone — a label in
            // every language would not fit three across.
            HStack(spacing: 10) {
                Button(action: onCompose) {
                    Label("Make a situation", systemImage: "square.and.pencil")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onWatch) {
                    Image(systemName: "play.fill")
                        .frame(width: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Watch"))
                Button(action: onTalk) {
                    Image(systemName: "phone.fill")
                        .frame(width: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Talk"))
            }
            .font(.body.weight(.semibold))
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .animation(.smooth(duration: 0.3), value: expanded)
    }

    /// The accordion: three lines and a chevron, or everything, scrolling
    /// inside the card once it would pass ~half the screen.
    @ViewBuilder private var details: some View {
        if expanded {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !about.isEmpty {
                        Text(about).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !person.commonTopics.isEmpty {
                        section("Topics") { Text(person.commonTopics).font(.subheadline) }
                    }
                    section("Voice") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voiceName).font(.subheadline)
                            Text("Their own voice, chosen with their introduction. Not a recording of anyone.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    let talks = pastTalks
                    if !talks.isEmpty {
                        section("Your talks together") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(talks) { s in
                                    NavigationLink {
                                        ConversationDetailView(session: s)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(s.displayTitle).font(.subheadline).lineLimit(1)
                                                Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            toggle(open: false)
        } else {
            if !about.isEmpty {
                Text(about)
                    .font(.subheadline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded = true }
            }
            toggle(open: true)
        }
    }

    private func toggle(open: Bool) -> some View {
        Button { expanded = open } label: {
            HStack(spacing: 4) {
                Text(open ? "More" : "Show less")
                Image(systemName: open ? "chevron.down" : "chevron.up")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
