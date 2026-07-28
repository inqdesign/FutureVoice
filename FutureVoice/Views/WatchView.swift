import SwiftUI

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
                PaywallView(offerTrial: false)   // out-of-credits entry
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
                    if !counterpart.savedScenarios.isEmpty {
                        suggestions = counterpart.savedScenarios
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
            updated.savedScenarios = fresh
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
    /// Whether a freshly generated dialogue is archived for replay.
    /// False for scenario-watch (the book already owns its scene) — those
    /// are one-shot, audio still caches for in-session replay.
    let persist: Bool

    init(counterpart: Counterpart,
         topic: SuggestedTopic? = nil,
         customScenario: String = "",
         savedDialogue: WatchDialogue? = nil,
         persist: Bool = true) {
        self.counterpart = counterpart
        self.topic = topic
        self.customScenario = customScenario
        self.savedDialogue = savedDialogue
        self.persist = persist
    }

    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()

    @State private var turns: [DialogueEngine.Turn] = []
    @State private var generatedTitle: String?
    @State private var currentIndex: Int? = nil
    @State private var isPlaying = false
    /// Unified beta feedback modal — presented after the first full listen-through.
    @State private var feedbackContext: BetaFeedbackSheet.Context?
    @State private var loading = true
    @State private var error: String?
    @State private var outOfCredits = false
    @State private var showingPaywall = false
    @State private var shadowTarget: Turn?

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
        .navigationTitle("Watching")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // immersive watching — hide the tab bar
        .safeAreaInset(edge: .bottom) { controls }
        .sheet(item: $feedbackContext) { ctx in
            BetaFeedbackSheet(context: ctx)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            if outOfCredits {
                Button("See plans") { error = nil; showingPaywall = true }
            }
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(offerTrial: false)   // out-of-credits entry
        }
        .sheet(item: $bridge) { b in
            ShadowDrillView(turn: b.turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
        .task {
            savedPhraseKeys = Set(DrillStore.shared.load().map { $0.targetPhrase.lowercased() })
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

    private var controls: some View {
        HStack(spacing: 16) {
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
            id: UUID(),
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
    private func playFrom(index: Int) async {
        guard index < turns.count else { return }
        isPlaying = true
        var i = index
        while isPlaying && i < turns.count {
            currentIndex = i
            let turn = turns[i]
            let voiceId = turn.speaker == .user
                ? (appState.voiceCloneId ?? "")
                : counterpart.voicePresetId
            do {
                let data = try await loadOrSynthesize(text: turn.text, voiceId: voiceId)
                try await playAndWait(data)
            } catch {
                self.error = error.localizedDescription
                isPlaying = false
                return
            }
            i += 1
        }
        isPlaying = false
        currentIndex = nil
        // Completed the whole dialogue for the first time → ask for feedback.
        if i >= turns.count && BetaFeedback.shouldShow(.firstWatch) {
            BetaFeedback.markShown(.firstWatch)
            feedbackContext = .firstWatch
        }
    }

    private func loadOrSynthesize(text: String, voiceId: String) async throws -> Data {
        if voiceId.isEmpty {
            throw NSError(domain: "WatchView", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No voice id available."])
        }
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId) {
            return cached
        }
        let audio = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text)
        PhraseAudioStore.shared.save(audio, text: text, voiceId: voiceId)
        return audio
    }

    private func playAndWait(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try player.play(data) {
                    cont.resume(returning: ())
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
