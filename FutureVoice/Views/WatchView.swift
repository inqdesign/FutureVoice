import SwiftUI
import Combine

/// Step 1 of Watch mode: confirm the counterpart, pick or type a scenario,
/// then push into `WatchView` where the dialogue plays out.
struct WatchSetupSheet: View {
    let counterpart: Counterpart
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var topic: SuggestedTopic?
    @State private var customScenario: String = ""
    @State private var loading = false
    @State private var suggestions: [SuggestedTopic] = []
    @State private var error: String?
    @State private var outOfCredits = false
    @State private var showingPaywall = false
    @State private var showingWatch = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(counterpart.name).font(.body.weight(.semibold))
                            Text(counterpart.relationship.isEmpty
                                 ? "voiced by \(VoicePreset.by(id: counterpart.voicePresetId).displayName)"
                                 : "\(counterpart.relationship) · voiced by \(VoicePreset.by(id: counterpart.voicePresetId).displayName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Watching")
                }

                Section {
                    if loading && suggestions.isEmpty {
                        HStack { ProgressView(); Text("Finding scenarios…").foregroundStyle(.secondary) }
                    } else {
                        ForEach(suggestions) { item in
                            Button {
                                topic = item
                                customScenario = ""
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).foregroundStyle(.primary)
                                        if !item.blurb.isEmpty {
                                            Text(item.blurb).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if topic?.id == item.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text("Scenario")
                        Spacer()
                        Button { Task { await regenerate() } } label: {
                            if loading {
                                ProgressView().controlSize(.mini)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .disabled(loading)
                    }
                }

                Section("Or describe one yourself") {
                    TextField("e.g. Boram tells me she's moving back to Seoul",
                              text: $customScenario, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: customScenario) { _, new in
                            if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                                topic = nil
                            }
                        }
                }

                if let e = error {
                    Section {
                        Label(e, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        if outOfCredits {
                            Button("See plans") { showingPaywall = true }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Play") { showingWatch = true }
                        .disabled(!canPlay)
                }
            }
            .navigationDestination(isPresented: $showingWatch) {
                WatchView(
                    counterpart: counterpart,
                    topic: topic,
                    customScenario: customScenario.trimmingCharacters(in: .whitespaces)
                )
                .environmentObject(appState)
            }
            .task {
                if suggestions.isEmpty {
                    // First load: prefer the counterpart's saved library so
                    // we don't re-bill Gemini every time the user comes back
                    // for this same person. Refresh button explicitly regens.
                    if !counterpart.savedScenarios(in: appState.targetLanguage).isEmpty {
                        suggestions = counterpart.savedScenarios(in: appState.targetLanguage)
                    } else {
                        await regenerate()
                    }
                }
            }
        }
    }

    private var canPlay: Bool {
        topic != nil || !customScenario.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func regenerate() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let fresh = try await TopicEngine.suggestForCounterpart(
                persona: appState.persona,
                counterpart: counterpart,
                targetLanguage: appState.targetLanguage
            )
            suggestions = fresh
            // Persist the fresh library onto the counterpart so subsequent
            // opens are instant + free.
            var updated = counterpart
            updated.setSavedScenarios(fresh, in: appState.targetLanguage)
            appState.saveCounterpart(updated)
            return
        } catch {
            outOfCredits = error.isOutOfCredits
            self.error = outOfCredits
                ? "You're out of credits — fresh scenarios need a top-up."
                : error.localizedDescription
        }
    }
}

/// The actual Watch player. Generates the dialogue once on appear, then
/// auto-plays each turn with the right voice. Lines render through the shared
/// `DialogueLine`, the same component the live call transcript and the
/// conversation archive use.
struct WatchView: View {
    let counterpart: Counterpart
    let topic: SuggestedTopic?
    let customScenario: String
    /// When set, skip Gemini generation and just replay this saved dialogue.
    let savedDialogue: WatchDialogue?
    /// Normalized line text → the book's shadow-line id, when this scene came
    /// from a book. Shadowing a bubble then writes its attempt against the
    /// BOOK's line: without it `asTurn` minted a throwaway UUID, so the take
    /// was orphaned — it never checked the line off and no browser could find
    /// it again.
    var shadowLineIds: [String: UUID] = [:]
    /// Whether a freshly generated dialogue is archived for replay.
    /// False for scenario-watch (the book already owns its scene) — those
    /// are one-shot, audio still caches for in-session replay.
    let persist: Bool
    /// Where to go once the scene has played out. nil for callers with
    /// nowhere to send the viewer (a one-shot Watch with no book behind it).
    let handoff: SceneHandoff?
    /// When set, turns arrive progressively from a streaming generation —
    /// play each one as it lands instead of waiting for the whole scene.
    /// The feed's owner (SceneWatchView) drives generation and persistence;
    /// this view only mirrors and plays.
    let feed: SceneFeed?

    /// The "you've watched it — now study it" exit.
    ///
    /// Watch has no save prompt, and shouldn't: unlike a talk (which doesn't
    /// exist until you press End), the scene is absorbed into its book the
    /// moment it's generated — the book is already on the Practice shelf
    /// while you're still watching. So there's nothing to confirm. What was
    /// missing is the other half of Talk's ending: a clear "this is over,
    /// here's what's next".
    struct SceneHandoff {
        /// "Study this" when the book is somewhere the viewer hasn't been;
        /// "Back to the book" when they came FROM it (pushing it again would
        /// stack the same page twice).
        let title: String
        let action: () -> Void
    }

    init(counterpart: Counterpart,
         topic: SuggestedTopic? = nil,
         customScenario: String = "",
         savedDialogue: WatchDialogue? = nil,
         shadowLineIds: [String: UUID] = [:],
         persist: Bool = true,
         handoff: SceneHandoff? = nil,
         feed: SceneFeed? = nil) {
        self.counterpart = counterpart
        self.topic = topic
        self.customScenario = customScenario
        self.savedDialogue = savedDialogue
        self.shadowLineIds = shadowLineIds
        self.persist = persist
        self.handoff = handoff
        self.feed = feed
    }

    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()

    @State private var turns: [DialogueEngine.Turn] = []
    @State private var generatedTitle: String?
    @State private var currentIndex: Int? = nil
    @State private var isPlaying = false
    /// Unified beta feedback modal — presented after the first full listen-through.
    @State private var feedbackContext: FeedbackSheet.Context?
    @State private var loading = true
    @State private var error: String?
    @State private var outOfCredits = false
    @State private var showingPaywall = false
    @State private var shadowTarget: Turn?
    /// True once playback has reached the last line at least once. Drives the
    /// controls' swap from "watch it" to "you've watched it".
    @State private var didFinishScene = false
    #if DEBUG
    /// Screenshot capture only — the finished-scene controls are otherwise
    /// reachable only by sitting through the whole dialogue.
    private var forceFinished: Bool { DebugCapture.previewSceneFinished }
    #endif

    /// We wrap a DialogueEngine.Turn into a Turn (the Models.swift one) for
    /// the shadow practice surface, since ShadowDrillView takes that type.
    /// Generated synthetically — no persistence, just the transient bridge.
    struct ShadowBridge: Identifiable {
        let id = UUID()
        let turn: Turn
    }
    @State private var bridge: ShadowBridge?

    /// Lowercased drill targets already in the queue — drives the per-line
    /// "Save phrase" button state so the same line can't be saved twice.
    @State private var savedPhraseKeys: Set<String> = []

    /// Feed mode: playback auto-starts exactly once, on the first turn.
    @State private var streamAutoStarted = false

    /// True while the playback loop is parked waiting for a line that hasn't
    /// been written yet. It gates the prefetch refill above: a line that is
    /// about to be claimed the instant it appears must NOT be turned into a
    /// buffered prefetch — the loop's own streaming path starts audio on the
    /// first PCM chunk, and re-synthesizing it would also bill the line twice.
    @State private var waitingAtFrontier = false

    /// Audio for the line AFTER the one playing, fetched while it plays.
    /// Without this the loop was fully serial — synthesize, play, synthesize,
    /// play — so a full network round-trip of silence sat between every line,
    /// and the gap was WORSE before the future self's lines because the own
    /// voice runs on the slower fidelity model. Real conversational turn gaps
    /// are ~200 ms; these were seconds, and uneven.
    ///
    /// Never cancelled: a synthesis in flight is already billed, so letting it
    /// finish and land in `PhraseAudioStore` is strictly better than throwing
    /// it away. A stale one is simply not awaited.
    /// TWO lines ahead, not one. One line of lookahead only covers a
    /// synthesis that finishes within the current line's playback, and the
    /// fluent self's lines run on the fidelity model — routinely longer than
    /// the short counterpart line playing in front of them, so the gap landed
    /// on exactly the voice the user is waiting for. A second slot gives a
    /// slow line two lines of speech to hide behind.
    private static let prefetchDepth = 2
    @State private var prefetches: [Int: Task<Data, Error>] = [:]

    /// One key for this whole scene run. Every line sends it, so the plan's
    /// daily scene COUNT is charged once no matter how many lines play — and
    /// a scene already under way is never cut off part-heard. A fresh view
    /// (a replay, a new take) mints a new key, but a fully cached scene never
    /// reaches the server and so never spends one.
    @State private var sceneRunKey = UUID().uuidString

    /// Today's Watch allowance is spent. Not a paywall: they already paid,
    /// and the answer is tomorrow.
    @State private var sceneCapReached = false

    /// WHICH pool ran out. Scenes, normally — but a client that predates
    /// scene counts (or a free account) still meters scene audio in seconds
    /// off the talk pool, and that lands here as the talk cap.
    @State private var capKind: DailyAllowanceSheet.Kind = .scenes

    /// This account is on Light, so the spent-pool sheet has somewhere to
    /// send them. Resolved when the cap actually lands — Watch views are made
    /// often and most never hit it. False on Plus: nothing left to sell
    /// there, and the answer really is next month.
    @State private var canUpgradePlan = false

    /// The pool size for whichever cap landed — scenes or minutes — read
    /// from the account snapshot, never hardcoded.
    @State private var capAllowance: Int?
    /// When that pool refills.
    @State private var renewalLabel = ""
    /// The plan stops on that date instead of refilling (cancelled).
    @State private var planEndsAtPeriodEnd = false

    /// What the cap sheet was dismissed FOR; acted on in `onDismiss`, because
    /// a sheet can't raise the next one while it is closing.
    @State private var capChoice: CapChoice?

    /// Which tier the paywall should open on, when a caller named one.
    @State private var paywallTier: String?

    private enum CapChoice { case upgrade, review }

    /// Everything needed to synthesize one line, resolved on the main actor
    /// before any concurrency so a prefetch can't race `turns` growing under
    /// it while a streamed scene is still arriving.
    private struct SpeechRequest {
        let text: String
        let voiceId: String
        let previousText: String?
        let nextText: String?
    }

    private func speechRequest(at index: Int) -> SpeechRequest {
        let turn = turns[index]
        return SpeechRequest(
            text: turn.text,
            voiceId: turn.speaker == .user
                ? (appState.voiceCloneId ?? "")
                : counterpart.voicePresetId,
            // Both neighbours regardless of who speaks them: the point is that
            // this line lands MID-conversation. `nextText` is simply absent for
            // the line at the frontier of a still-streaming scene.
            previousText: index > 0 ? turns[index - 1].text : nil,
            nextText: index + 1 < turns.count ? turns[index + 1].text : nil
        )
    }

    private var feedTurnsPublisher: AnyPublisher<[DialogueEngineTurn], Never> {
        feed?.$turns.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }
    private var feedTitlePublisher: AnyPublisher<String?, Never> {
        feed?.$title.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    /// Pulled out of `body`: one more argument on this call tipped the whole
    /// view past the type-checker's budget.
    private var capSheet: some View {
        DailyAllowanceSheet(
            kind: capKind,
            canUpgrade: canUpgradePlan,
            allowance: capAllowance,
            renewsOn: renewalLabel,
            endsInstead: planEndsAtPeriodEnd,
            onReview: { capChoice = .review },
            onUpgrade: { capChoice = .upgrade })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    if loading {
                        loadingBlock
                    }
                    ForEach(Array(turns.enumerated()), id: \.element.id) { idx, turn in
                        bubble(turn: turn, isCurrent: currentIndex == idx)
                            .id(idx)
                            .onTapGesture {
                                Task { await playFrom(index: idx) }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .onChange(of: currentIndex) { _, idx in
                if let idx { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(idx, anchor: .center) } }
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                LevelHeaderTitle(title: "Watching",
                                 level: appState.proficiency,
                                 surface: .watch)
                    .environmentObject(appState)
            }
        }
        .toolbar(.hidden, for: .tabBar)   // immersive watching — hide the tab bar
        .safeAreaInset(edge: .bottom) { controls }
        .sheet(item: $feedbackContext) { ctx in
            FeedbackSheet(context: ctx)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            if outOfCredits {
                Button("See plans") { error = nil; showingPaywall = true }
            }
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        // Deliberately NOT the error alert: this learner is a subscriber who
        // used up this month's pool, which is not a failure. Same sheet the
        // call screen raises — one spent-pool surface, so the two can't drift.
        .sheet(isPresented: $sceneCapReached, onDismiss: {
            switch capChoice {
            case .upgrade:
                // "plus", not "unlimited" — the paywall matches this against its
                // own tier ids, so the old name silently preselected nothing
                // and left the sheet on the plan they already hold.
                paywallTier = "plus"
                showingPaywall = true
            // Switching tabs is enough: RootTabView follows the staged route,
            // and this scene stays pushed for whenever they come back to it.
            case .review:  appState.pendingPracticeRoute = .studying
            case nil:      break
            }
            capChoice = nil
        }) {
            capSheet
        }
        .sheet(isPresented: $showingPaywall, onDismiss: { paywallTier = nil }) {
            PaywallView(preselectTier: paywallTier)
        }
        .sheet(item: $bridge) { b in
            ShadowDrillView(turn: b.turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
        .task {
            savedPhraseKeys = Set(DrillStore.shared.load().map { $0.targetPhrase.lowercased() })
            guard feed == nil else { return }   // fed views mirror, never generate
            if turns.isEmpty {
                if let saved = savedDialogue {
                    // Replay a saved dialogue — skip Gemini, just hydrate
                    // turns from disk and auto-play.
                    turns = saved.turns.map { stored in
                        DialogueEngine.Turn(
                            speaker: DialogueEngine.Speaker(rawValue: stored.speaker) ?? .counterpart,
                            text: stored.text
                        )
                    }
                    loading = false
                    await playFrom(index: 0)
                } else {
                    await generate()
                }
            }
        }
        .onReceive(feedTurnsPublisher) { stored in
            // Mirror the feed append-only: re-emissions of the same prefix
            // are no-ops, and the final full write after a degraded
            // (buffered) stream lands here as one big append.
            guard stored.count > turns.count else { return }
            turns.append(contentsOf: stored[turns.count...].map {
                DialogueEngine.Turn(
                    speaker: DialogueEngine.Speaker(rawValue: $0.speaker) ?? .counterpart,
                    text: $0.text
                )
            })
            loading = false
            // First line on screen → start the scene; the playback loop
            // waits at the frontier for the lines still being written.
            if !streamAutoStarted {
                streamAutoStarted = true
                Task { await playFrom(index: 0) }
            } else if isPlaying, !waitingAtFrontier, let idx = currentIndex {
                // A streamed scene starts playing when only the FIRST turn
                // exists, so `startPrefetch(after: 0)` had nothing to reach
                // for and line 1 paid the whole round trip in the open —
                // scene lines are serial server-side (rate · ownership ·
                // scene claim · charge) before ElevenLabs is even called, so
                // that one unhidden gap was seconds long while every later
                // line was covered. Refill the window the moment a new line
                // lands, so line 1 synthesizes behind line 0's playback like
                // every other line does.
                startPrefetch(after: idx)
            }
        }
        .onReceive(feedTitlePublisher) { title in
            if let title { generatedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .onDisappear {
            // Flip the loop gate BEFORE stopping the player: player.stop()
            // fires the current turn's completion, which resumes the
            // sequential playback loop — with isPlaying still true it would
            // synthesize and play the NEXT turn after the view is gone
            // (audio kept narrating after navigating away).
            isPlaying = false
            player.stop()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        // Saved-dialogue replays carry their own title/blurb — without this
        // fallback the header rendered blank on the replay path. Prefer the
        // dialogue-specific title over the generic scenario name.
        let title = generatedTitle
            ?? savedDialogue?.displayTitle
            ?? topic?.title
            ?? customScenario
        let blurb = topic?.blurb ?? savedDialogue?.scenarioBlurb ?? ""
        // Synthetic partners (topic watch, scenario watch) can lack a
        // relationship — join only what's set so no trailing separator.
        let speakerLine = [counterpart.name, counterpart.relationship]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Text(speakerLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            if !blurb.isEmpty {
                Text(blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Writing the dialogue…")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func bubble(turn: DialogueEngine.Turn, isCurrent: Bool) -> some View {
        let isUser = turn.speaker == .user
        // The user's side of a watched scene is performed by the fluent
        // self — label it that way, since the user is watching, not speaking.
        DialogueLine(speaker: isUser ? .user : .other,
                     name: isUser ? "Future self" : counterpart.name,
                     isCurrent: isCurrent) {
            Text(turn.text)
        } accessory: {
            HStack(spacing: 16) {
                Button {
                    // Shadow practice records the mic — stop dialogue
                    // playback so it doesn't bleed under the sheet.
                    pause()
                    bridge = ShadowBridge(turn: asTurn(turn))
                } label: {
                    Label("Shadow this", systemImage: "waveform.badge.mic")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                // Same learning loop as Talk: a line worth keeping goes
                // into the SRS drill queue and resurfaces on schedule.
                if isPhraseSaved(turn.text) {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        savePhrase(turn.text)
                    } label: {
                        Label("Save phrase", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private func isPhraseSaved(_ text: String) -> Bool {
        savedPhraseKeys.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func savePhrase(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPhraseSaved(trimmed) else { return }
        let card = DrillCard(
            sourcePhrase: "",
            targetPhrase: trimmed,
            reason: "From your dialogue with \(counterpart.name) — \(topic?.title ?? savedDialogue?.scenarioTitle ?? customScenario)",
            createdAt: Date(),
            nextReviewAt: Date(),
            box: 0
        )
        DrillStore.shared.save(card)
        savedPhraseKeys.insert(trimmed.lowercased())
        HapticEngine.drillCorrect()
    }

    /// Two states, not two extra buttons. Before the end, watching is the
    /// only thing to do; after it, the study handoff takes the prominent slot
    /// and replay steps back. A third permanent button would have crowded the
    /// bar and offered the exit before it meant anything.
    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 16) {
            #if DEBUG
            let finished = didFinishScene || forceFinished
            #else
            let finished = didFinishScene
            #endif
            if finished, let handoff {
                Button {
                    Task { await playFrom(index: 0) }
                } label: {
                    Label("Watch again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(loading)

                Button(action: handoff.action) {
                    Label(handoff.title, systemImage: "books.vertical.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await playFrom(index: 0) }
                } label: {
                    Label("Restart", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(turns.isEmpty || loading)

                Button {
                    if isPlaying {
                        pause()
                    } else {
                        Task { await playFrom(index: currentIndex ?? 0) }
                    }
                } label: {
                    Label(isPlaying ? "Pause" : "Play",
                          systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(turns.isEmpty || loading)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    /// Bridge to ShadowDrillView's `Turn`. fluentSelf turns get the user's
    /// clone voice; counterpart turns use the preset voice. ShadowDrillView's
    /// prepareAudio will lazily fetch from PhraseAudioStore using that voice.
    private func asTurn(_ d: DialogueEngine.Turn) -> Turn {
        let voiceId = d.speaker == .user
            ? (appState.voiceCloneId ?? "")
            : counterpart.voicePresetId
        // We piggy-back on PhraseAudioStore content-hash caching by writing
        // a placeholder turn with audioURL nil. ShadowDrillView will resolve.
        // NOTE: when speaker is counterpart, ShadowDrillView still uses
        // appState.voiceCloneId in its prepareAudio fallback — for MVP we
        // accept this limitation; counterpart-line shadows pull the user's
        // clone, which arguably is the right thing (you're learning to say
        // a line in your own voice). Refine later if needed.
        _ = voiceId
        return Turn(
            id: shadowLineIds[CarryoverDetector.normalized(d.text)] ?? UUID(),
            role: .fluentSelf,
            audioURL: nil,
            transcript: d.text,
            durationMs: 0,
            timestamp: Date(),
            suggestion: nil
        )
    }

    // MARK: - Actions

    private func generate() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let generated = try await DialogueEngine.generate(
                persona: appState.persona,
                counterpart: counterpart,
                topic: topic,
                topicTitle: customScenario.isEmpty ? nil : customScenario,
                topicBlurb: nil,
                targetLanguage: appState.targetLanguage
            )
            // New script — anything prefetched was keyed to the old line at
            // that index and must not be claimed for this one. In-flight
            // tasks are left to finish into the audio cache, never cancelled.
            prefetches.removeAll()
            turns = generated.turns
            generatedTitle = generated.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Persist so the user can replay later without burning another
            // Gemini call. Audio is cached separately via PhraseAudioStore
            // so replay is genuinely free.
            persistGeneratedDialogue()
            // Auto-play once generation finishes.
            await playFrom(index: 0)
        } catch {
            outOfCredits = error.isOutOfCredits
            self.error = outOfCredits
                ? "You're out of credits — generating this dialogue needs a top-up."
                : error.localizedDescription
        }
    }

    private func persistGeneratedDialogue() {
        guard persist else { return }
        let title  = topic?.title ?? customScenario
        let blurb  = topic?.blurb ?? ""
        let stored = WatchDialogue(
            counterpartId: counterpart.id,
            scenarioTitle: title,
            scenarioBlurb: blurb,
            title: generatedTitle,
            turns: turns.map { DialogueEngineTurn(speaker: $0.speaker.rawValue, text: $0.text) },
            speakerName: counterpart.name,
            voicePresetId: counterpart.voicePresetId
        )
        appState.saveWatchDialogue(stored)
    }

    private func pause() {
        // Gate first, then stop — same reasoning as onDisappear.
        isPlaying = false
        player.stop()
    }

    /// Plays turns sequentially starting at `index`. Each turn synthesizes
    /// (or pulls cached) audio via the appropriate voice id and chains
    /// `.play` calls in a loop. PhraseAudioStore content-cache makes
    /// repeated playback free.
    /// Feed mode only: more lines are still on the wire, so running out of
    /// turns means "wait at the frontier", not "the scene is over".
    private var awaitingMoreTurns: Bool {
        guard let feed else { return false }
        return !feed.isComplete
    }

    private func playFrom(index: Int) async {
        guard index < turns.count else { return }
        isPlaying = true
        var i = index
        while true {
            // Streaming: hold the playhead until the next line lands or the
            // generation closes the scene. In practice the model writes
            // faster than speech, so this only ever waits at the very front.
            while isPlaying && i >= turns.count && awaitingMoreTurns {
                waitingAtFrontier = true
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            waitingAtFrontier = false
            guard isPlaying, i < turns.count else { break }
            currentIndex = i
            let request = speechRequest(at: i)
            do {
                // Fill the lookahead window BEFORE awaiting this line, so the
                // next lines synthesize alongside it instead of after it —
                // this is what covers the very first line's wait too.
                startPrefetch(after: i)
                var data: Data?
                // Claim the prefetch if it was for this line. A failed one
                // falls through to a normal fetch rather than ending the
                // scene — it was only ever an optimization.
                if let pending = prefetches.removeValue(forKey: i) {
                    data = try? await pending.value
                }
                if data == nil {
                    data = PhraseAudioStore.shared.data(text: request.text,
                                                        voiceId: request.voiceId)
                }
                if let audio = data {
                    try await playAndWait(audio)
                } else if try await streamAndPlay(request) == false {
                    // Streaming unavailable — classic fetch-then-play.
                    try await playAndWait(try await loadOrSynthesize(request))
                }
            } catch let capped where capped.isDayCapped {
                // Out of today's allowance. Say so where the scene was going
                // to play. Resolve the plan first so the sheet opens with its
                // button already decided instead of growing one a beat later.
                let account = await AccountStatus.fetch()
                capKind = capped.isDailyCapReached ? .talk : .scenes
                canUpgradePlan = account.isLightPlan
                capAllowance = capKind == .talk
                    ? account.monthlyCapSeconds.map { $0 / 60 }
                    : account.monthlyScenesCap
                renewalLabel = account.renewalLabel
                planEndsAtPeriodEnd = account.cancelAtPeriodEnd
                sceneCapReached = true
                isPlaying = false
                return
            } catch {
                self.error = error.localizedDescription
                isPlaying = false
                return
            }
            i += 1
        }
        // A pause exits with isPlaying already false; only a natural run-out
        // past the LAST line of a closed scene counts as finishing.
        let reachedEnd = isPlaying && i >= turns.count
        isPlaying = false
        currentIndex = nil
        // Reached the last line — the scene is over, so the controls stop
        // offering only "watch it again" and start offering the book.
        if reachedEnd, !didFinishScene {
            withAnimation(.easeOut(duration: 0.25)) { didFinishScene = true }
        }
        // Completed the whole dialogue for the first time → ask for feedback.
        if reachedEnd && FeedbackPrompt.shouldShow(.firstWatch) {
            FeedbackPrompt.markShown(.firstWatch)
            feedbackContext = .firstWatch
        }
    }

    /// Starts fetching the next `prefetchDepth` lines that aren't already in
    /// flight. Cache hits make this nearly free on a replay, and a line that
    /// never gets played still lands in `PhraseAudioStore` for next time.
    private func startPrefetch(after index: Int) {
        for offset in 1...Self.prefetchDepth {
            let next = index + offset
            guard next < turns.count, prefetches[next] == nil else { continue }
            let request = speechRequest(at: next)
            prefetches[next] = Task { try await loadOrSynthesize(request) }
        }
    }

    private func loadOrSynthesize(_ request: SpeechRequest) async throws -> Data {
        let text = request.text
        let voiceId = request.voiceId
        if voiceId.isEmpty {
            throw NSError(domain: "WatchView", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No voice id available."])
        }
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId) {
            return cached
        }
        // The fluent self gets the fidelity model — this is the screen where
        // the user listens hardest for "is that me?", and PhraseAudioStore
        // caches by (voiceId, text), so the pricier synthesis happens once per
        // line, ever. Counterpart preset voices stay on turbo: they're not the
        // user's voice, so similarity buys nothing there, and paying 2x for
        // every other line of every scene is not worth it.
        let isOwnVoice = voiceId == appState.voiceCloneId
        let audio = try await ElevenLabsClient.shared.synthesize(
            voiceId: voiceId, text: text,
            modelId: isOwnVoice ? ElevenLabsClient.fidelityModelId : "eleven_turbo_v2_5",
            purpose: "scene",
            previousText: request.previousText,
            nextText: request.nextText,
            sceneKey: sceneRunKey)
        PhraseAudioStore.shared.save(audio, text: text, voiceId: voiceId)
        return audio
    }

    /// Speak `request` by STREAMING it: audio starts on the first PCM chunk
    /// instead of after the whole file lands. This is the fix for the wait in
    /// front of the fluent self's lines — its fidelity model takes seconds to
    /// synthesize a line, and buffered playback spent every one of them
    /// silent. Prefetched lines keep the buffered path: they arrived while
    /// the previous line was still speaking, so there is nothing to hide.
    ///
    /// Returns false when streaming isn't available (an edge deploy that
    /// ignored `stream`, or an audio engine that refused) so the caller can
    /// fall back to the classic fetch-then-play.
    private func streamAndPlay(_ request: SpeechRequest) async throws -> Bool {
        guard !request.voiceId.isEmpty else { return false }
        let latch = PlaybackLatch()
        var started = false
        let isOwnVoice = request.voiceId == appState.voiceCloneId
        let result = try await ElevenLabsClient.shared.synthesizeStreaming(
            voiceId: request.voiceId,
            text: request.text,
            modelId: isOwnVoice ? ElevenLabsClient.fidelityModelId : "eleven_turbo_v2_5",
            purpose: "scene",
            sceneKey: sceneRunKey
        ) { chunk, sampleRate in
            if !started {
                do {
                    try player.startPCMStream(sampleRate: sampleRate,
                                              voiceKey: request.voiceId) { latch.signal() }
                } catch {
                    return   // engine refused → caller falls back
                }
                started = true
            }
            player.feedPCMStream(chunk)
        }
        switch result {
        case .mp3(let data):
            // Server returned a whole file — nothing streamed, so this is the
            // buffered path with an extra hop. Cache it and let the caller play.
            _ = PhraseAudioStore.shared.save(data, text: request.text, voiceId: request.voiceId)
            return false
        case .pcm(let full, let rate):
            guard started else { return false }
            player.finishPCMStream()
            // Cache as WAV so a replay hits the buffered path for free — the
            // pricier fidelity synthesis stays once per line, ever.
            _ = PhraseAudioStore.shared.save(
                AudioLoudness.wavData(fromPCM16: full, sampleRate: Int(rate)),
                text: request.text, voiceId: request.voiceId)
            await latch.wait()
            return true
        }
    }

    private func playAndWait(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try player.play(data, source: "scene") {
                    cont.resume(returning: ())
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

/// One-shot "playback finished" signal for a streamed line. The player's
/// completion can fire before the caller gets around to awaiting it (a short
/// line finishes while the network stream is still closing), so the latch
/// remembers a signal that arrives early instead of deadlocking on it.
@MainActor
private final class PlaybackLatch {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signal() {
        if let w = waiter {
            waiter = nil
            w.resume()
        } else {
            signalled = true
        }
    }

    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
