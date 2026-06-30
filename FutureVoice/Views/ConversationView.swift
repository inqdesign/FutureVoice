import AVFoundation
import SwiftUI

/// Voice-first conversation screen, redesigned around a scrolling transcript
/// feed. The mic is small and lives at the bottom; the dominant content is
/// what the user and the fluent self just said — including a live partial
/// transcript while the user speaks, and a gentle inline correction chip
/// underneath each user turn when the LLM finds a more natural alternative.
struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var live = LiveTranscriber()
    @StateObject private var player = AudioPlayer()

    @State private var topic = ""
    @State private var topicBlurb = ""
    @State private var turns: [Turn] = []
    @State private var phase: Phase = .idle
    @State private var error: String?
    @State private var summary: SessionSummary?
    @State private var showTopicPicker = false
    @State private var dueDrillCount = 0
    @State private var phoneCallActive = false
    @State private var silenceTask: Task<Void, Never>?
    /// True only while `endSession` is wrapping up (summary generation in
    /// flight). Distinct from `phase == .thinking`, which also fires per-turn
    /// mid-conversation — this drives the full-screen "wrapping up" overlay so
    /// the End tap gives immediate feedback instead of a silent wait.
    @State private var isEnding = false
    @State private var didAutoStart = false
    @State private var isResuming = false
    /// Set when a reply (Gemini/TTS) fails for the latest user turn — drives
    /// an inline Retry button so a network blip doesn't lose what they said.
    @State private var failedTurnId: UUID?
    @Environment(\.dismiss) private var dismiss

    /// Presented as the immersive "talk seat" from ConversationHome. An initial
    /// topic launches a scenario; empty = free talk. Pass `resumeSession` to
    /// pick up a past conversation where it left off (same session id, prior
    /// turns preloaded as context). The call auto-starts on appear so it feels
    /// like placing a phone call.
    init(initialTopic: String = "", initialBlurb: String = "", resumeSession: Session? = nil) {
        if let s = resumeSession {
            _topic = State(initialValue: s.topic ?? "")
            _topicBlurb = State(initialValue: "")
            _turns = State(initialValue: s.turns)
            _sessionId = State(initialValue: s.id)
            _sessionStartedAt = State(initialValue: s.startedAt)
            _didSaveCurrentSession = State(initialValue: true)
            _isResuming = State(initialValue: true)
        } else {
            _topic = State(initialValue: initialTopic)
            _topicBlurb = State(initialValue: initialBlurb)
        }
    }

    /// Three-tier VAD threshold so brief pauses don't cut the user off mid-thought.
    ///   • `short`   — explicit end-of-sentence punctuation. They wrapped up.
    ///   • `default` — no clear signal either way. Conservative wait so a
    ///     breath or a 2-second think doesn't fire.
    ///   • `long`    — trailing filler / hanging conjunction / stub
    ///     article/preposition. They're clearly still composing.
    // SFSpeechRecognizer rarely inserts terminal punctuation in real time,
    // so the default branch fires far more often than the short one. Bumped
    // default 3.0→5.0 and long 5.0→7.0 in 2026-06 after users reported the
    // avatar cutting in during natural mid-thought breaths.
    private static let vadShortSeconds: Double   = 1.5
    private static let vadDefaultSeconds: Double = 5.0
    private static let vadLongSeconds: Double    = 7.0
    @State private var dashboard: PracticeStats.Snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionId = UUID()
    @State private var sessionStartedAt = Date()
    @State private var didSaveCurrentSession = false
    @State private var userSpeechStartedAt: Date?

    private let userId = ProfileStore.localUserId

    enum Phase: Equatable {
        case idle
        case listening      // mic open, partial STT streaming
        case thinking       // Gemini reply in flight
        case speaking       // ElevenLabs TTS playing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                feed
                Divider().opacity(0.15)
                bottomBar
            }
            .background(Color(.systemBackground))
            .overlay { endingOverlay }
            .navigationTitle(topic.isEmpty ? "Free talk" : topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                // Place the "call" once when the seat opens.
                guard !didAutoStart else { return }
                didAutoStart = true
                phoneCallActive = true
                HapticEngine.phoneCallStarted()
                if isResuming {
                    // Continue from the loaded transcript — open the mic so the
                    // user picks up where they left off (Gemini already has the
                    // prior turns as context).
                    Task { await startRecording() }
                } else {
                    Task { await openConversation() }
                }
            }
            // Drill / Shadow / History / Watch / Profile moved to dedicated
            // tabs in `RootTabView`. ConversationView now owns Talk only.
            .sheet(item: summaryBinding) { s in
                SummarySheet(summary: s, sessionId: sessionId,
                             onDone: endAndClose, onStartNew: startNewSession)
                    .environmentObject(appState)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task { refreshDashboard() }
            .onChange(of: topic) { _, newTopic in
                // Topic just got picked → opener appears AND we auto-enter
                // phone-call mode. Zero-tap start: the user's scenario pick
                // IS the "I want to talk now" signal. They can hang up via
                // the End button (or by tapping mic again) when they're done.
                guard !newTopic.isEmpty, turns.isEmpty, phase == .idle else { return }
                phoneCallActive = true
                HapticEngine.phoneCallStarted()
                Task { await openConversation() }
            }
            .onChange(of: live.transcript) { _, _ in
                // Voice activity detection: every time the live transcript
                // grows, reset the silence countdown. When it stays unchanged
                // for `vadSilenceSeconds`, auto-send.
                guard phoneCallActive, phase == .listening else { return }
                resetSilenceTimer()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await endPhoneCall() }
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !turns.isEmpty {
                Button(role: .destructive) {
                    Task { await endSession() }
                } label: {
                    Text("End")
                        .fontWeight(.semibold)
                }
                .disabled(phase != .idle)
            }
        }
    }

    // MARK: - Ending overlay

    /// Shown while `endSession` generates the summary. Covers the screen with
    /// a translucent veil + spinner so tapping End reads as "working on it",
    /// not a frozen, silent pause before the summary sheet appears.
    @ViewBuilder
    private var endingOverlay: some View {
        if isEnding {
            ZStack {
                Color(.systemBackground).opacity(0.9).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Wrapping up your session…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if turns.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(topic.isEmpty ? "Starting your conversation…" : "Setting the scene…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    }
                    ForEach(turns) { turn in
                        // No implicit morph between adjacent turns — each
                        // bubble fades in / out cleanly. Prevents the
                        // previous bubble's text from being visible inside
                        // the next one during insertion animation.
                        TurnView(turn: turn, nativeLanguage: appState.nativeLanguage)
                            .id(turn.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if phase == .listening {
                        // Separate id from ThinkingIndicator + explicit opacity
                        // transition so SwiftUI doesn't morph one view's text
                        // into another. The previous shared id caused the
                        // user's partial transcript to briefly bleed into the
                        // "Future self is thinking…" bubble during the swap.
                        PartialTurnView(text: live.transcript)
                            .id("partial-listening")
                            .transition(.opacity)
                    } else if phase == .thinking && (turns.last?.role == .user) {
                        ThinkingIndicator()
                            .id("partial-thinking")
                            .transition(.opacity)
                    } else if let fid = failedTurnId, turns.last?.id == fid {
                        RetryReplyRow(onRetry: retryReply)
                            .id("retry-row")
                            .transition(.opacity)
                    }
                    // Bottom spacer so the last line isn't hidden behind controls
                    Color.clear.frame(height: 8).id(Self.bottomId)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .onChange(of: turns.count) { _, _ in scroll(proxy) }
            .onChange(of: phase)       { _, _ in scroll(proxy) }
            .onChange(of: live.transcript) { _, _ in scroll(proxy) }
        }
    }

    private static let partialId = "partial-indicator"
    private static let bottomId  = "feed-bottom"

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
    }

    // MARK: - Bottom bar (mic + level)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if phase == .listening {
                LevelMeter(level: live.level)
                    .frame(height: 18)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            Button { Task { await handleMicTap() } } label: {
                ZStack {
                    Circle()
                        .fill(.tint)
                        .frame(width: 64, height: 64)
                        .opacity(micEnabled ? 1.0 : 0.4)
                        .scaleEffect(phase == .listening ? 1.06 : 1.0)
                        .animation(
                            phase == .listening
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: phase
                        )
                    Image(systemName: micSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            .buttonStyle(.plain)
            .tint(micTint)
            .disabled(!micEnabled)
            .accessibilityLabel(Text(micA11yLabel))

            Text(micHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .animation(nil, value: phase)
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        // No background — the mic floats above the feed and the tab bar gets
        // a clean gap below it, so users don't read mic + tabs as one chunk.
    }

    /// Mic is always tappable — even mid-thinking/speaking it acts as
    /// "hang up" for the phone call. iOS-native phone-call ergonomics.
    private var micEnabled: Bool { true }

    private var micSymbol: String {
        if phoneCallActive {
            switch phase {
            case .listening: return "stop.fill"           // tap to hang up
            case .thinking:  return "ellipsis"
            case .speaking:  return "waveform"
            case .idle:      return "stop.fill"           // mid-cycle, still in call
            }
        }
        return "mic.fill"                                 // not in call → tap to start
    }

    private var micTint: Color {
        if phoneCallActive {
            return phase == .speaking ? .accentColor : .red
        }
        return .accentColor
    }

    private var micA11yLabel: String {
        if phoneCallActive {
            switch phase {
            case .listening: return "Listening — tap to hang up"
            case .thinking:  return "Thinking"
            case .speaking:  return "Future self speaking — tap to hang up"
            case .idle:      return "Hang up"
            }
        }
        return turns.isEmpty ? "Start phone-call mode" : "Resume phone-call mode"
    }

    private var micHint: String {
        if phoneCallActive {
            switch phase {
            case .listening: return "Listening — pause to send"
            case .thinking:  return "Thinking…"
            case .speaking:  return "Speaking…"
            case .idle:      return "On call"
            }
        }
        return turns.isEmpty ? "Tap to start a phone-call" : "Tap to continue"
    }

    // MARK: - Bindings

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private var summaryBinding: Binding<SessionSummary?> {
        Binding(get: { summary }, set: { summary = $0 })
    }

    // MARK: - Flow

    private func handleMicTap() async {
        if phoneCallActive {
            // Tap during an active phone call = hang up.
            await endPhoneCall()
            return
        }
        // Start a phone call. Avatar's reply will auto-restart listening.
        phoneCallActive = true
        HapticEngine.phoneCallStarted()
        await startRecording()
    }

    private func endPhoneCall() async {
        phoneCallActive = false
        cancelSilenceTimer()
        if phase == .listening {
            _ = live.stop()
            userSpeechStartedAt = nil
        }
        if phase == .speaking {
            player.stop()
        }
        phase = .idle
        HapticEngine.phoneCallEnded()
    }

    private func resetSilenceTimer() {
        cancelSilenceTimer()
        let wait = currentVadWaitSeconds()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled,
                  phoneCallActive,
                  phase == .listening,
                  !live.transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            HapticEngine.voiceSent()
            await stopAndSend()
        }
    }

    /// Inspect the latest STT transcript and pick a silence threshold:
    ///   • 5.0s — clearly mid-thought (filler / hanging conjunction / stub).
    ///   • 1.5s — wrapped up cleanly (terminal punctuation .!?).
    ///   • 3.0s — anything in between. Conservative so a breath doesn't fire.
    private func currentVadWaitSeconds() -> Double {
        let trimmed = live.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isLikelyIncomplete(trimmed) {
            return Self.vadLongSeconds
        }
        if let last = trimmed.last, ".!?".contains(last) {
            return Self.vadShortSeconds
        }
        return Self.vadDefaultSeconds
    }

    private static let fillerWords: Set<String> = [
        "uh", "um", "er", "ah", "hmm", "mm", "well",
        "음", "어", "그", "그러니까", "에"
    ]
    private static let trailingConjunctions: Set<String> = [
        "and", "but", "or", "so", "because", "cause",
        "if", "when", "while", "that", "which", "though", "although"
    ]
    private static let trailingFunctionWords: Set<String> = [
        "the", "a", "an", "to", "in", "on", "at", "of",
        "for", "with", "by", "from", "into", "about"
    ]

    private static func isLikelyIncomplete(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let words = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard let last = words.last else { return true }
        // Very short transcripts are almost always still being formed.
        if words.count <= 2,
           !last.hasSuffix("?"),
           !last.hasSuffix("."),
           !last.hasSuffix("!") {
            return true
        }
        let stripped = last.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        if fillerWords.contains(stripped)         { return true }
        if trailingConjunctions.contains(stripped) { return true }
        if trailingFunctionWords.contains(stripped) { return true }
        return false
    }

    private func cancelSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = nil
    }

    private func openConversation() async {
        phase = .thinking
        do {
            let opener = try await GeminiClient.shared.send(
                system: systemPrompt(),
                messages: [GeminiClient.Message(
                    role: .user,
                    content: """
                    Open this conversation with ONE natural opening line in \(appState.targetLanguage).
                    Be IN the scenario — don't summarize it, don't explain it. Just say the first
                    thing you'd say if this were really happening, in a way the user can respond to.
                    """
                )]
            )
            // Text-only opener. No TTS — saves an ElevenLabs call per topic
            // pick. The user reads, responds, and audio kicks in from the
            // avatar's first reply onward.
            turns.append(Turn(
                id: UUID(), role: .fluentSelf, audioURL: nil,
                transcript: opener, durationMs: 0, timestamp: Date(),
                suggestion: nil
            ))
            didSaveCurrentSession = false
            phase = .idle
            if phoneCallActive {
                await startRecording()
            }
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func startRecording() async {
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        do {
            try live.start(locale: appState.targetLanguage)
            userSpeechStartedAt = Date()
            phase = .listening
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopAndSend() async {
        let finalText = live.stop()
        let fluency = live.fluencyStats()
        let elapsedMs = Int((Date().timeIntervalSince(userSpeechStartedAt ?? Date())) * 1000)
        userSpeechStartedAt = nil
        phase = .thinking

        let userTurn = Turn(
            id: UUID(), role: .user, audioURL: nil,
            transcript: finalText, durationMs: max(0, elapsedMs), timestamp: Date(),
            suggestion: nil,
            fluency: fluency
        )
        turns.append(userTurn)
        didSaveCurrentSession = false

        await requestReply(forUserTurn: userTurn.id)
    }

    /// Generate the fluent-self reply for `turnId` (the latest user turn).
    /// Extracted from `stopAndSend` so a failed turn — usually a transient
    /// network error — can be retried from an inline button WITHOUT making
    /// the user speak again. The user turn stays in `turns` either way.
    private func requestReply(forUserTurn turnId: UUID) async {
        failedTurnId = nil
        phase = .thinking
        guard let voiceId = appState.voiceCloneId else { phase = .idle; return }
        do {
            // One structured call returns reply + optional inline correction
            // (repopulates Turn.suggestion: chip UI, SRS ingest, weekly-report
            // pairs, suggestion_rate metric).
            let payload: ConversationTurnPayload
            do {
                payload = try await GeminiClient.shared.sendJSON(
                    system: systemPrompt()
                        + ConversationEngine.turnOutputInstruction(targetLanguage: appState.targetLanguage),
                    messages: ConversationEngine.geminiMessages(from: turns),
                    maxTokens: 512,
                    temperature: 0.7
                )
            } catch GeminiError.jsonNotFound(let raw) {
                // Model slipped out of JSON mode — treat the raw text as the
                // spoken reply rather than failing the whole turn.
                payload = ConversationTurnPayload(reply: raw, suggestion: nil)
            }
            let replyText = payload.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replyText.isEmpty else {
                failedTurnId = turnId
                phase = .idle
                return
            }
            if let s = payload.turnSuggestion(),
               let idx = turns.firstIndex(where: { $0.id == turnId }) {
                turns[idx].suggestion = s
            }
            try await speakAndAppend(replyText, voiceId: voiceId)
            // DO NOT set phase = .idle here. speakAndAppend kicks off audio
            // playback (non-blocking) whose completion flips phase back to
            // .idle AND auto-restarts listening for phone-call mode.
        } catch {
            // Keep the user's turn and offer an inline Retry instead of a
            // dead-end alert, so a network blip doesn't lose what they said.
            failedTurnId = turnId
            phase = .idle
        }
    }

    private func retryReply() {
        guard let id = failedTurnId else { return }
        Task { await requestReply(forUserTurn: id) }
    }

    private func speakAndAppend(_ text: String, voiceId: String) async throws {
        // Content-addressed cache hit avoids re-billing ElevenLabs for repeated
        // fluent-self lines (greetings, short acknowledgements, etc.).
        let audio: Data
        let timings: [WordTiming]
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId) {
            audio = cached
            timings = PhraseAudioStore.shared.timings(text: text, voiceId: voiceId) ?? []
        } else {
            let (newAudio, newTimings) = try await ElevenLabsClient.shared
                .synthesizeWithTimestamps(voiceId: voiceId, text: text)
            audio = newAudio
            timings = newTimings
            PhraseAudioStore.shared.save(newAudio, text: text, voiceId: voiceId, timings: newTimings)
        }
        let turnId = UUID()
        let savedURL = TurnAudioStore.shared.save(audio, turnId: turnId, timings: timings)
        let durationMs = Self.mp3DurationMs(audio)
        turns.append(Turn(
            id: turnId, role: .fluentSelf, audioURL: savedURL,
            transcript: text, durationMs: durationMs, timestamp: Date(),
            suggestion: nil
        ))
        didSaveCurrentSession = false
        phase = .speaking
        // configureSession: false keeps the existing .playAndRecord session
        // (set up by LiveTranscriber) instead of switching to .playback and
        // back. Each switch costs 200–500ms — meaningful in a phone-call
        // loop. Speaker output still works because of .defaultToSpeaker.
        try player.play(audio, configureSession: false) {
            Task { @MainActor in
                guard phase == .speaking else { return }
                phase = .idle
                // Phone call: avatar just finished talking → loop back to
                // listening so the user can reply without tapping.
                if phoneCallActive {
                    await startRecording()
                }
            }
        }
    }

    private func endSession() async {
        guard !turns.isEmpty else { return }
        phoneCallActive = false
        cancelSilenceTimer()
        // If a call is still live, stop the mic/playback so the overlay isn't
        // fighting an open recording while the summary generates.
        if phase == .listening { _ = live.stop(); userSpeechStartedAt = nil }
        if phase == .speaking { player.stop() }
        phase = .thinking
        withAnimation(.easeInOut(duration: 0.2)) { isEnding = true }
        defer { withAnimation(.easeInOut(duration: 0.2)) { isEnding = false } }
        do {
            let systemP = ConversationEngine.summarySystemPrompt(
                targetLanguage: appState.targetLanguage,
                profile: appState.learnerProfile
            )
            let transcript = ConversationEngine.formatTranscript(turns)
            let metrics = ScorecardMetrics.compute(turns: turns)
            let userMessage = """
            transcript:
            \(transcript)

            metrics:
            \(metrics.promptJSON())
            """
            let payload: ClaudeSummaryPayload = try await GeminiClient.shared.sendJSON(
                system: systemP,
                messages: [GeminiClient.Message(role: .user, content: userMessage)],
                maxTokens: 1400
            )
            var computed = payload.toDomain()

            // Fold the user's spoken words into the long-term vocab pool; the
            // freshly-used words ride along on the summary so the wrap-up can
            // celebrate concrete progress.
            let userTexts = turns.filter { $0.role == .user }.map { $0.transcript }
            computed.newWordsUsed = VocabStore.shared.ingest(
                sessionId: sessionId, userTexts: userTexts)

            // Keep only expressions that literally appear in the user's own
            // turns — the LLM occasionally paraphrases, and we never show or
            // store an expression they didn't actually say.
            let haystack = userTexts.joined(separator: " ").lowercased()
            let verifiedExpressions = computed.expressionsUsed.filter { phrase in
                let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !needle.isEmpty && haystack.contains(needle)
            }
            computed.expressionsUsed = verifiedExpressions
            VocabStore.shared.ingestExpressions(
                sessionId: sessionId, phrases: verifiedExpressions)

            summary = computed
            phase = .idle

            // Free-talk sessions (no picked topic) take the summary's
            // generated title so History/Practice lists don't fill with
            // identical "Conversation" rows.
            let generatedTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTopic = topic.isEmpty ? (generatedTitle ?? "") : topic
            let session = Session(
                id: sessionId,
                userId: userId,
                targetLanguage: appState.targetLanguage,
                mode: .conversation,
                topic: resolvedTopic.isEmpty ? nil : resolvedTopic,
                startedAt: sessionStartedAt,
                endedAt: Date(),
                turns: turns,
                summary: computed
            )
            SessionStore.shared.save(session)
            // Clear any cards from a previous end of THIS session (resume
            // re-summarizes the whole thing) so they don't pile up.
            DrillStore.shared.deleteForSession(sessionId)
            DrillStore.shared.ingest(summary: computed, turns: turns, sessionId: sessionId)
            // Grow the long-term learner profile — the next conversation's
            // system prompt picks these patterns up.
            appState.recordSessionOutcome(summary: computed, turns: turns)
            didSaveCurrentSession = true
            refreshDashboard()
            // Kick off async weekly-report generation if unlock conditions
            // are met. Fires-and-forgets — UI doesn't block on Gemini.
            appState.maybeGenerateWeeklyReport()
            // Fresh cards just landed in the queue — (re)schedule the due
            // reminder. This is the one contextual moment where asking for
            // notification permission makes sense.
            Task { await DrillReminder.reschedule(allowPermissionPrompt: true) }
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func refreshDashboard() {
        dueDrillCount = DrillStore.shared.dueCount()
        dashboard = PracticeStats.snapshot()
    }

    private func startNewSession() {
        failedTurnId = nil
        summary = nil
        sessionId = UUID()
        sessionStartedAt = Date()
        turns = []
        didSaveCurrentSession = false
        phase = .idle
        if !topic.isEmpty {
            phoneCallActive = true   // stay in phone-call mode for continuity
            Task { await openConversation() }
        }
    }

    /// Done from the summary sheet → leave the talk seat entirely, back to the
    /// Talk home. Summary is already saved to History.
    private func endAndClose() {
        summary = nil
        phoneCallActive = false
        cancelSilenceTimer()
        dismiss()
    }

    private static func mp3DurationMs(_ data: Data) -> Int {
        guard let player = try? AVAudioPlayer(data: data) else { return 0 }
        return Int(player.duration * 1000)
    }

    private func systemPrompt() -> String {
        let composedTopic = topicBlurb.isEmpty ? topic : "\(topic). \(topicBlurb)"
        return ConversationEngine.conversationSystemPrompt(
            targetLanguage: appState.targetLanguage,
            nativeLanguage: appState.nativeLanguage,
            level: appState.proficiency,
            topPatterns: appState.learnerProfile.recurringMistakes,
            weakVocabAreas: appState.learnerProfile.weakVocabAreas,
            topic: composedTopic,
            persona: appState.persona
        )
    }
}

// MARK: - Subviews

private struct TurnView: View {
    let turn: Turn
    let nativeLanguage: String

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.role == .user ? "You" : "Future self")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.transcript)
                .font(.title3)
                .foregroundStyle(turn.role == .user ? .primary : Color.accentColor)

            Button(action: toggleMeaning) {
                HStack(spacing: 4) {
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "character.bubble")
                    }
                    Text(showing ? "Hide meaning" : "Meaning")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showing, let t = translation {
                Text(t)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if turn.role == .user, let suggestion = turn.suggestion {
                SuggestionChip(suggestion: suggestion, nativeLanguage: nativeLanguage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleMeaning() {
        if showing { showing = false; return }
        showing = true
        guard translation == nil else { return }
        if let c = Translator.cached(turn.transcript, to: nativeLanguage) {
            translation = c
            return
        }
        loading = true
        Task {
            let t = await Translator.translate(turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

private struct SuggestionChip: View {
    let suggestion: TurnSuggestion
    let nativeLanguage: String

    @State private var reasonNative: String?
    @State private var showing = false
    @State private var loading = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .font(.footnote)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.alternative)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: toggle) {
                    HStack(spacing: 4) {
                        if loading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "character.bubble") }
                        Text(showing ? "Hide" : "Explain in my language")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                if showing, let r = reasonNative {
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func toggle() {
        if showing { showing = false; return }
        showing = true
        guard reasonNative == nil else { return }
        if let c = Translator.cached(suggestion.reason, to: nativeLanguage) { reasonNative = c; return }
        loading = true
        Task {
            let t = await Translator.translate(suggestion.reason, to: nativeLanguage)
            reasonNative = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

private struct PartialTurnView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Listening…" : text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .italic(text.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Future self is thinking…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let barCount = 24
            let spacing: CGFloat = 4
            let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let position = Float(i) / Float(barCount - 1)
                    let center: Float = 0.5
                    let distance = abs(position - center) * 2          // 0 at center, 1 at edges
                    let envelope = max(0.15, 1 - distance * distance)  // bell-ish
                    let height = CGFloat(max(0.08, level * envelope)) * geo.size.height
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: barWidth, height: height)
                        .opacity(0.5 + Double(level) * 0.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

// MARK: - Sheets

private struct TopicPickerSheet: View {
    @Binding var topic: String
    @Binding var topicBlurb: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [SuggestedTopic] = []
    @State private var loading = false
    @State private var error: String?
    @State private var customTopic: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading && suggestions.isEmpty {
                        HStack { ProgressView(); Text("Finding scenarios from your life…").foregroundStyle(.secondary) }
                    } else if suggestions.isEmpty {
                        Text("Tap Refresh to generate scenarios.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions) { item in
                            Button {
                                topic = item.title
                                topicBlurb = item.blurb
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.title)
                                            .foregroundStyle(.primary)
                                            .font(.body)
                                        Spacer()
                                        if item.title == topic {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    if !item.blurb.isEmpty {
                                        Text(item.blurb)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } header: {
                    Text("Suggested for you")
                } footer: {
                    if let e = error {
                        Text(e).foregroundStyle(.red)
                    } else {
                        Text("Grounded in your profile — name, city, work, family, interests.")
                    }
                }

                Section("Your own") {
                    TextField("Type a topic", text: $customTopic)
                        .onSubmit { applyCustom() }
                    Button("Use this topic") { applyCustom() }
                        .disabled(customTopic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("What to practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await regenerate() }
                    } label: {
                        if loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(loading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Read from cache first; only hit Gemini when truly empty
                // (first time ever) or after an explicit Refresh tap.
                if suggestions.isEmpty {
                    let cached = appState.topicSuggestions
                    if !cached.isEmpty {
                        suggestions = cached
                    } else {
                        await regenerate()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applyCustom() {
        let trimmed = customTopic.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        topic = trimmed
        topicBlurb = ""
        dismiss()
    }

    private func regenerate() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let fresh = try await TopicEngine.suggest(
                persona: appState.persona,
                targetLanguage: appState.targetLanguage
            )
            suggestions = fresh
            appState.updateTopicSuggestions(fresh)
        } catch {
            self.error = "Couldn't fetch topics: \(error.localizedDescription)"
        }
    }
}

/// Inline recovery row shown under the last user turn when the reply failed
/// (network/Gemini/TTS). Plain feed row (no card) per the transcript style.
private struct RetryReplyRow: View {
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Couldn\'t get a response.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummarySheet: View {
    let summary: SessionSummary
    let sessionId: UUID
    let onDone: () -> Void
    let onStartNew: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Cards this session just produced, loaded once on appear so the bottom
    /// action can route straight into reviewing them.
    @State private var practiceCardCount = 0

    var body: some View {
        NavigationStack {
            List {
                if let card = summary.scorecard {
                    Section("Today's nutrition") {
                        ScorecardView(scorecard: card)
                            .padding(.vertical, 6)
                    }
                }
                if !summary.newWordsUsed.isEmpty || !summary.expressionsUsed.isEmpty {
                    Section("Words & expressions you used") {
                        if !summary.newWordsUsed.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New words")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                FlowLayout {
                                    ForEach(summary.newWordsUsed, id: \.self) { word in
                                        Text(word)
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color(.secondarySystemBackground), in: Capsule())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        ForEach(summary.expressionsUsed, id: \.self) { expr in
                            Label(expr, systemImage: "quote.bubble")
                                .font(.subheadline)
                                .padding(.vertical, 2)
                        }
                    }
                }
                Section("Note") {
                    Text(summary.overallNote)
                }
                if !summary.phrasesUsed.isEmpty {
                    Section("More natural alternatives") {
                        ForEach(summary.phrasesUsed) { phrase in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phrase.userSaid)
                                    .foregroundStyle(.secondary)
                                Text(phrase.fluentAlternative)
                                    .font(.body)
                                Text(phrase.reason)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !summary.suggestedDrills.isEmpty {
                    Section("Drill next") {
                        ForEach(summary.suggestedDrills, id: \.self) { drill in
                            Text(drill)
                        }
                    }
                }
            }
            .navigationTitle("Session summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                practiceCardCount = DrillStore.shared.load()
                    .filter { $0.sourceSessionId == sessionId }.count
            }
            .safeAreaInset(edge: .bottom) { bottomActions }
        }
    }

    /// Practice-first close-out. The cards from this conversation already
    /// exist in the SRS deck (ingested in `endSession`); the primary action
    /// drops the user straight into reviewing just them, closing the
    /// talk → summary → practice loop without a tab hunt.
    @ViewBuilder
    private var bottomActions: some View {
        VStack(spacing: 10) {
            if practiceCardCount > 0 {
                NavigationLink {
                    DrillView(source: .session(sessionId))
                        .navigationTitle("Practice")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label(practiceCardCount == 1
                          ? "Practice this card"
                          : "Practice these \(practiceCardCount) cards",
                          systemImage: "rectangle.stack.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            // Secondary once there are cards to practice (so Practice stays
            // the clear primary); the sole prominent action otherwise.
            if practiceCardCount > 0 {
                startNewButton.buttonStyle(.bordered)
            } else {
                startNewButton.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var startNewButton: some View {
        Button {
            onStartNew()
        } label: {
            Label("Start a new conversation", systemImage: "arrow.uturn.left")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SessionSummary: Identifiable {
    public var id: String { overallNote }
}
