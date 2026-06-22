import SwiftUI

/// Spaced-repetition drill queue. Walks through the cards that are currently
/// due — the learner hears the target phrase in their cloned voice, then
/// self-rates Got it / Try again to advance the Leitner box.
///
/// Shadow practice lives in its own sheet (`ShadowBrowserSheet`); the two are
/// surfaced from separate toolbar entries so the home dashboard can track each
/// independently.
/// Card-deck SRS practice. Swipe right = Got it, left = Try again. Tap to
/// hear it. No bottom button bar — important under a tab bar so the controls
/// don't visually merge with system chrome. A faint "next card" preview sits
/// behind the active card for the deck-of-cards feel.
struct DrillView: View {
    /// Optional filter. `.due` (default) = the Leitner-scheduled queue.
    /// `.session(id)` = every card whose source matches the given session,
    /// regardless of due date. Lets the user post-mortem a specific
    /// conversation by walking just its cards.
    /// `.ahead(n)` = the n soonest-due cards regardless of schedule — for
    /// "practice ahead" when nothing is due but the user wants reps anyway.
    enum Source: Equatable {
        case due
        case session(UUID)
        case ahead(Int)
    }
    var source: Source = .due

    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @StateObject private var live = LiveTranscriber()

    @State private var queue: [DrillCard] = []
    @State private var initialCount: Int = 0
    @State private var isLoadingAudio = false
    @State private var error: String?
    @State private var dragOffset: CGSize = .zero
    @State private var showingEnrichmentFor: DrillCard?
    @State private var shadowingCard: DrillCard?
    /// Active-recall gate: when the top card has a sourcePhrase, the target
    /// stays hidden until the learner taps to check — they should produce
    /// the fluent version in their head (or out loud) FIRST. Grading swipes
    /// are disabled until revealed, so "Got it" always means actual recall.
    @State private var topCardRevealed = false

    /// "Say it" quick check — speak the revealed target, get a deterministic
    /// ShadowEngine score + diff right on the card. No LLM call, so it's
    /// instant and free; full karaoke practice stays in the Shadow sheet.
    @State private var sayIt: SayItState = .idle
    @State private var sayItStopTask: Task<Void, Never>?

    enum SayItState: Equatable {
        case idle
        case listening
        case result(score: Int, steps: [ShadowEngine.DiffStep])
    }

    private static let swipeThreshold: CGFloat = 100

    var body: some View {
        Group {
            if !queue.isEmpty {
                cardDeck
            } else {
                emptyState
            }
        }
        .alert("Couldn't play audio", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .sheet(item: $showingEnrichmentFor, onDismiss: refreshTopCard) { card in
            DrillEnrichmentSheet(card: card)
                .environmentObject(appState)
        }
        .sheet(item: $shadowingCard) { card in
            // Build a synthetic fluentSelf turn from the drill card so we
            // can reuse the existing ShadowDrillView surface. Deterministic
            // id (derived from card.id) keeps saved attempts linked to the
            // same card across sessions.
            ShadowDrillView(
                turn: Turn(
                    id: card.id,
                    role: .fluentSelf,
                    audioURL: nil,
                    transcript: card.targetPhrase,
                    durationMs: 0,
                    timestamp: card.createdAt,
                    suggestion: nil
                ),
                targetLanguage: appState.targetLanguage
            )
            .environmentObject(appState)
        }
        .onAppear(perform: loadQueue)
        .onChange(of: live.transcript) { _, _ in
            // Silence-based auto-stop: every transcript change pushes the
            // stop deadline 1.5s out; when the user pauses, we grade.
            guard case .listening = sayIt,
                  !live.transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            scheduleSayItStop(after: 1.5)
        }
        .onDisappear { cancelSayIt() }
    }

    /// After dismissing the enrichment sheet, the top card may have had its
    /// enrichment persisted — pull the fresh copy from disk so the in-memory
    /// queue reflects it.
    private func refreshTopCard() {
        guard let top = queue.first else { return }
        let fresh = DrillStore.shared.due().first(where: { $0.id == top.id })
        if let fresh = fresh {
            queue[0] = fresh
        }
    }

    private var cardDeck: some View {
        VStack(spacing: 12) {
            counterRow
            ZStack {
                // Peek of the next card so the user feels there's a deck.
                // Recall cards stay concealed in the peek so the upcoming
                // answer doesn't leak while grading the current one.
                if queue.count > 1 {
                    cardSurface(queue[1], revealed: !needsReveal(queue[1]))
                        .scaleEffect(0.95)
                        .opacity(0.45)
                        .offset(y: 14)
                }
                cardSurface(queue[0], revealed: isTopRevealed, isTop: true)
                    .overlay(swipeIndicator)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = isTopRevealed ? $0.translation : .zero }
                            .onEnded { handleDragEnded($0) }
                    )
                    .onTapGesture {
                        guard !isTopRevealed else { return }
                        HapticEngine.drillCorrect()
                        withAnimation(.easeOut(duration: 0.2)) { topCardRevealed = true }
                    }
            }
            .padding(.horizontal, 16)
            hintRow
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var counterRow: some View {
        Text("\(initialCount - queue.count + 1) of \(initialCount)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var swipeIndicator: some View {
        Group {
            if dragOffset.width > 20 {
                Label("Got it", systemImage: "checkmark")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.green))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-12))
                    .opacity(min(1.0, Double(dragOffset.width) / 120.0))
            } else if dragOffset.width < -20 {
                Label("Try again", systemImage: "arrow.counterclockwise")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(12))
                    .opacity(min(1.0, Double(-dragOffset.width) / 120.0))
            }
        }
    }

    /// Recall cards (those with a sourcePhrase) start concealed.
    private func needsReveal(_ card: DrillCard) -> Bool {
        !card.sourcePhrase.isEmpty
    }

    private var isTopRevealed: Bool {
        guard let top = queue.first else { return true }
        return topCardRevealed || !needsReveal(top)
    }

    @ViewBuilder
    private var hintRow: some View {
        if isTopRevealed {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left").foregroundStyle(.red)
                    Text("Try again")
                }
                Text("·").foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Text("Got it")
                    Image(systemName: "arrow.right").foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        } else {
            Label("Say it out loud, then tap the card to check", systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        // No grading before recall — spring back until the card is revealed.
        guard isTopRevealed else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
            return
        }
        let width = value.translation.width
        if width > Self.swipeThreshold {
            HapticEngine.drillCorrect()
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = CGSize(width: 600, height: value.translation.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                markCorrect()
                dragOffset = .zero
            }
        } else if width < -Self.swipeThreshold {
            HapticEngine.drillIncorrect()
            withAnimation(.easeOut(duration: 0.25)) {
                dragOffset = CGSize(width: -600, height: value.translation.height)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                markIncorrect()
                dragOffset = .zero
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
    }
}

/// Sheet wrapper — kept for backward compat; main app uses `DrillView`
/// directly inside `PracticeTab` now.
struct DrillSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DrillView()
                .navigationTitle("Drills")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private extension DrillView {

    // MARK: - Card surface

    @ViewBuilder
    func cardSurface(_ card: DrillCard, revealed: Bool = true, isTop: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !card.sourcePhrase.isEmpty {
                labeled("You said") {
                    Text(card.sourcePhrase)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .strikethrough(revealed)
                }
            }

            labeled(revealed ? "Try saying" : "How would a fluent speaker say it?") {
                Text(card.targetPhrase)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .redacted(reason: revealed ? [] : .placeholder)
            }

            if revealed, !card.reason.isEmpty {
                labeled("Why") {
                    Text(card.reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            if isTop, revealed {
                sayItSection(card)
            }

            Spacer(minLength: 12)

            if revealed {
                HStack(spacing: 8) {
                    pillButton(systemImage: isLoadingAudio ? nil : "speaker.wave.2.fill",
                               text: isLoadingAudio ? "Loading…" : "Hear it",
                               showSpinner: isLoadingAudio) {
                        Task { await playTarget(card) }
                    }
                    .disabled(isLoadingAudio)

                    pillButton(systemImage: "waveform.badge.mic", text: "Shadow") {
                        cancelSayIt()
                        shadowingCard = card
                    }

                    pillButton(systemImage: card.enrichment == nil ? "books.vertical" : "books.vertical.fill",
                               text: "Examples") {
                        cancelSayIt()
                        showingEnrichmentFor = card
                    }
                }
            } else {
                Label("Tap to reveal", systemImage: "eye")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        // Dropped the 360pt minHeight — long targetPhrases were being
        // clipped because Spacer + tight box left no room. Now the card
        // grows to fit the text; minHeight kept just for visual presence
        // on short cards.
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    @ViewBuilder
    func pillButton(systemImage: String?, text: String, showSpinner: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showSpinner {
                    ProgressView().controlSize(.mini)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Say it (deterministic speak-to-check)

    @ViewBuilder
    func sayItSection(_ card: DrillCard) -> some View {
        switch sayIt {
        case .idle:
            Button {
                Task { await startSayIt() }
            } label: {
                Label("Say it", systemImage: "mic")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

        case .listening:
            Button {
                finishSayIt()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text(live.transcript.isEmpty ? "Listening…" : live.transcript)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "stop.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.red)

        case .result(let score, let steps):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(score)", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(sayItScoreColor(score))
                        .monospacedDigit()
                    Spacer()
                    Button("Retry") { Task { await startSayIt() } }
                        .font(.caption.weight(.medium))
                }
                sayItDiffText(steps)
                    .font(.subheadline)
                Text(score >= 75
                     ? "Nailed it — swipe right."
                     : "Close — hear it again, or swipe left to retry later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
    }

    func sayItScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }

    /// Same rendering convention as ShadowDrillView's diff: matches plain,
    /// substitutions orange, skipped words struck through, extras as (+word).
    func sayItDiffText(_ steps: [ShadowEngine.DiffStep]) -> Text {
        var out = Text("")
        var first = true
        for step in steps {
            let space = first ? Text("") : Text(" ")
            switch step.op {
            case .match:
                out = out + space + Text(step.target ?? "").foregroundStyle(.primary)
            case .sub:
                out = out + space + Text(step.target ?? "").foregroundStyle(.orange)
            case .del:
                out = out + space + Text(step.target ?? "").foregroundStyle(.secondary).strikethrough()
            case .ins:
                out = out + space + Text("(+\(step.learner ?? ""))").foregroundStyle(.orange)
            }
            first = false
        }
        return out
    }

    func startSayIt() async {
        player.stop()
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        do {
            try live.start(locale: appState.targetLanguage, preferBuiltInMic: true)
            sayIt = .listening
            // Backstop if the user never speaks; silence watcher takes over
            // once the first words arrive.
            scheduleSayItStop(after: 8)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scheduleSayItStop(after seconds: Double) {
        sayItStopTask?.cancel()
        sayItStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, case .listening = sayIt else { return }
            finishSayIt()
        }
    }

    func finishSayIt() {
        sayItStopTask?.cancel()
        sayItStopTask = nil
        let text = live.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let card = queue.first, !text.isEmpty else {
            sayIt = .idle
            return
        }
        let analysis = ShadowEngine.analyze(target: card.targetPhrase, learner: text)
        sayIt = .result(score: analysis.score, steps: analysis.steps)
        HapticEngine.shadowComplete(score: analysis.score)
    }

    func cancelSayIt() {
        sayItStopTask?.cancel()
        sayItStopTask = nil
        if case .listening = sayIt { _ = live.stop() }
        sayIt = .idle
    }

    private var emptyState: some View {
        ContentUnavailableView(
            initialCount == 0 ? "No drills due" : "Nice work",
            systemImage: initialCount == 0 ? "lightbulb" : "checkmark.circle.fill",
            description: Text(initialCount == 0
                ? "Drills appear here after you end a conversation."
                : "You finished \(initialCount) card\(initialCount == 1 ? "" : "s"). They'll surface again on the Leitner schedule.")
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    // MARK: - Actions

    private func loadQueue() {
        switch source {
        case .due:
            queue = DrillStore.shared.due()
        case .session(let sid):
            queue = DrillStore.shared.load()
                .filter { $0.sourceSessionId == sid }
                .sorted { $0.createdAt < $1.createdAt }
        case .ahead(let limit):
            queue = Array(
                DrillStore.shared.load()
                    .sorted { $0.nextReviewAt < $1.nextReviewAt }
                    .prefix(limit)
            )
        }
        initialCount = queue.count
    }

    private func markCorrect() {
        guard let card = queue.first else { return }
        DrillStore.shared.markCorrect(card)
        advance()
    }

    private func markIncorrect() {
        guard let card = queue.first else { return }
        DrillStore.shared.markIncorrect(card)
        advance()
    }

    private func advance() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        topCardRevealed = false
        cancelSayIt()
    }

    private func playTarget(_ card: DrillCard) async {
        guard let voiceId = appState.voiceCloneId else { return }
        // A prior Say-it run leaves the session in .measurement mode, which
        // makes plain playback noticeably quiet — force-reset (same fix as
        // ShadowDrillView's preview).
        cancelSayIt()
        if let cached = PhraseAudioStore.shared.data(text: card.targetPhrase, voiceId: voiceId) {
            do { try player.play(cached, forceSessionReset: true) } catch { self.error = error.localizedDescription }
            return
        }
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let audio = try await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId,
                text: card.targetPhrase
            )
            PhraseAudioStore.shared.save(audio, text: card.targetPhrase, voiceId: voiceId)
            try player.play(audio, forceSessionReset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
