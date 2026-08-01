import AVFoundation
import SwiftUI
import UIKit

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
    /// The last failure was a 402 — the user is out of credits. Retry is
    /// pointless until they top up, so the recovery UI leads with the paywall.
    @State private var outOfCredits = false
    @State private var showingPaywall = false
    /// Unified beta feedback modal — set to a milestone to present it.
    @State private var feedbackContext: BetaFeedbackSheet.Context?
    /// endAndClose defers its dismiss until the first-talk feedback closes.
    @State private var dismissAfterFeedback = false
    @State private var showMicPermissionAlert = false
    /// Flipped by tearDown() when the screen closes. Every async continuation
    /// (Gemini reply, TTS synthesis, stream chunks, auto-restart) checks it
    /// and bails — otherwise a reply in flight at close time keeps talking
    /// over the home screen and overlaps the next call's session.
    @State private var isTornDown = false
    @Environment(\.dismiss) private var dismiss

    /// RootTabView's free-talk presentation hosts this view in a ZStack (not
    /// a cover), where dismiss() is a no-op — closing must hand control back
    /// to the presenter so it can play the pill morph in reverse.
    private var onClose: (() -> Void)?

    /// Presented as the immersive "talk seat" from ConversationHome. An initial
    /// topic launches a scenario; empty = free talk. Pass `resumeSession` to
    /// pick up a past conversation where it left off (same session id, prior
    /// turns preloaded as context). The call auto-starts on appear so it feels
    /// like placing a phone call.
    init(initialTopic: String = "", initialBlurb: String = "",
         initialIsNews: Bool = false, initialOrigin: SessionOrigin = .free,
         initialScenarioId: UUID? = nil, initialNewsFacts: [String] = [],
         resumeSession: Session? = nil,
         onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        if let s = resumeSession {
            _topic = State(initialValue: s.topic ?? "")
            _topicBlurb = State(initialValue: "")
            _turns = State(initialValue: s.turns)
            _sessionId = State(initialValue: s.id)
            _sessionStartedAt = State(initialValue: s.startedAt)
            _didSaveCurrentSession = State(initialValue: true)
            _isResuming = State(initialValue: true)
            // Carry the original origin so a resumed talk keeps its badge.
            _sessionOrigin = State(initialValue: s.origin ?? (s.topic?.isEmpty == false ? .news : .free))
            _sessionScenarioId = State(initialValue: s.originScenarioId)
        } else {
            _topic = State(initialValue: initialTopic)
            _topicBlurb = State(initialValue: initialBlurb)
            _topicIsNews = State(initialValue: initialIsNews)
            _sessionOrigin = State(initialValue: initialOrigin)
            _sessionScenarioId = State(initialValue: initialScenarioId)
            _newsFacts = State(initialValue: initialNewsFacts)
        }
    }

    /// Three-tier end-of-turn threshold, measured against TRUE AUDIO SILENCE
    /// (`LiveTranscriber.lastVoicedAt` from the mic energy meter) — the same
    /// hybrid used by modern realtime voice stacks: acoustic VAD picks the
    /// endpoint, text completeness modulates how long to wait.
    ///   • `short`   — explicit end-of-sentence punctuation. They wrapped up.
    ///   • `default` — no clear signal either way.
    ///   • `long`    — trailing filler / hanging conjunction / stub
    ///     article/preposition. They're clearly still composing.
    // History: 2026-06 users reported the avatar cutting in during natural
    // mid-thought breaths. That was under TRANSCRIPT-quiet timing — STT
    // partials stall unpredictably while the user is still talking, so the
    // timer measured the recognizer, not the speaker, and the only fix was a
    // padded 5s default. Energy-based silence can't misfire on a breath
    // (breaths are ~0.5–1.5s and unvoiced), so the default drops back to 3s
    // without recreating that bug. `sttSettleSeconds` additionally holds fire
    // while the partial transcript is still moving, so a lagging recognizer
    // never gets its tail truncated.
    // 2026-08 retune: `talk_turn_timing` says the DEFAULT tier fires 53% of
    // turns (95/179) and the short tier 27%, i.e. this wait is the single
    // biggest slice of the silence between "user stops" and "fluent self
    // speaks" — bigger than the whole Gemini call. Every `final_timeout` seen
    // so far is 0 (the rescored FINAL pass always landed with room to spare),
    // so the padding buys nothing. Default 3.0 → 2.2, short 1.5 → 1.2. The
    // LONG tier stays at 5s: it only fires on a hanging conjunction or filler,
    // where cutting in is exactly the failure mode this whole scheme exists to
    // avoid. Roll back if `final_timeout=1` starts appearing in telemetry.
    private static let vadShortSeconds: Double   = 1.2
    private static let vadDefaultSeconds: Double = 2.2
    private static let vadLongSeconds: Double    = 5.0
    /// Don't send while the STT partial is still changing — recognition lag
    /// after the last spoken word is typically 0.3–0.5s.
    private static let sttSettleSeconds: Double  = 0.7
    /// Endpoint monitor tick. 0.2s keeps worst-case added latency ≤ one tick.
    private static let endpointTickSeconds: Double = 0.2
    /// Noisy-room fallback: constant background noise can keep the energy
    /// meter reading "voiced" forever. If the TRANSCRIPT has been still this
    /// long (the old conservative signal), send regardless of energy.
    private static let noisyRoomFallbackSeconds: Double = 6.0
    /// How much true silence before warming the network path. Well under the
    /// shortest VAD tier (1.2s), so by the time the turn actually fires the
    /// TLS handshake + auth token are already in place.
    private static let preconnectAfterSilenceSeconds: Double = 0.6
    /// One preconnect per listening phase — reset when the mic restarts.
    @State private var didPreconnectThisTurn = false
    /// Per-turn latency breadcrumbs, accumulated across the VAD → finalize →
    /// Gemini → first-TTS-chunk pipeline and logged once when the fluent
    /// self actually starts SPEAKING (the moment users experience as "the
    /// answer arrived"). Keys: vad_wait_ms, finalize_ms, gemini_ms,
    /// audio ("aac"/"wav"/"none"/KB), tts ("stream"/"buffered"/"cache"),
    /// tts_first_ms, total_ms.
    @State private var turnTiming: [String: String] = [:]
    /// When the user finished speaking (endpoint fired) — anchor for total_ms.
    @State private var turnEndedSpeakingAt: Date?
    @State private var dashboard: PracticeStats.Snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var sessionId = UUID()
    @State private var sessionStartedAt = Date()
    @State private var didSaveCurrentSession = false
    /// ✕ tapped with unsaved turns — asks save vs. discard before leaving.
    @State private var confirmingDiscard = false
    @State private var userSpeechStartedAt: Date?
    /// Last time the live STT partial changed — the endpoint monitor waits
    /// for BOTH audio silence and a settled transcript before sending.
    @State private var lastTranscriptChangeAt: Date?
    /// True when the topic is a news story ("In the news" picker). The opener
    /// call then runs search-grounded and collects `newsFacts`.
    @State private var topicIsNews = false
    /// Where this talk started from — stamped onto the saved `Session` so
    /// Practice can badge the book (free / news / scenario).
    @State private var sessionOrigin: SessionOrigin = .free
    /// The scenario this talk launched from, carried onto the saved session.
    @State private var sessionScenarioId: UUID? = nil
    /// Real facts from the grounded news lookup — injected into every turn's
    /// system prompt so the future self actually knows the story.
    @State private var newsFacts: [String] = []
    /// Raw 0…1 voice energy target for the mic pill's glow (mic RMS while
    /// listening, playback RMS while speaking). Futureself interpolates it
    /// per frame, so no smoothing here.
    @State private var voiceLevel: Float = 0

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
            .navigationTitle(topic.isEmpty ? "Let's talk" : topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                // A call screen must never auto-lock mid-sentence: a long
                // user turn has no touches, so the system idle timer fires
                // right through it. App-global UIKit flag — re-asserted on
                // every appear (a sheet on top can bounce this view's
                // appearance) and balanced in onDisappear below.
                UIApplication.shared.isIdleTimerDisabled = true
                // Place the "call" once when the seat opens.
                guard !didAutoStart else { return }
                didAutoStart = true
                phoneCallActive = true
                HapticEngine.phoneCallStarted()
                Analytics.capture("conversation_started", [
                    "origin": sessionOrigin.rawValue,
                    "resumed": isResuming
                ])
                if isResuming {
                    // Continue from the loaded transcript — open the mic so the
                    // user picks up where they left off (Gemini already has the
                    // prior turns as context).
                    Task { await startRecording() }
                } else {
                    Task { await openConversation() }
                }
            }
            .onDisappear {
                // Balance the onAppear assert — leaving this true would keep
                // the WHOLE app from ever auto-locking.
                UIApplication.shared.isIdleTimerDisabled = false
            }
            // Drill / Shadow / History / Watch / Profile moved to dedicated
            // tabs in `RootTabView`. ConversationView now owns Talk only.
            .sheet(item: summaryBinding) { s in
                SummarySheet(summary: s, sessionId: sessionId,
                             onDone: endAndClose, onStartNew: startNewSession)
                    .environmentObject(appState)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                if outOfCredits {
                    Button("See plans") { error = nil; showingPaywall = true }
                }
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .sheet(isPresented: $showingPaywall) {
                // Reached here from an out-of-credits failure → no trial pitch.
                PaywallView(offerTrial: false)
            }
            .sheet(item: $feedbackContext, onDismiss: {
                if dismissAfterFeedback { dismissAfterFeedback = false; close() }
            }) { ctx in
                BetaFeedbackSheet(context: ctx)
            }
            // Hitting the credit wall now routes to the paywall's preference
            // survey (see the "See plans" alert button) — no separate feedback
            // sheet at depletion.
            .alert("Microphone access needed", isPresented: $showMicPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("nawana needs the microphone and speech recognition to hear you speak. Turn them on in Settings → nawana.")
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
                // The endpoint monitor measures silence from mic ENERGY, not
                // from this — but it refuses to fire while the partial is
                // still moving (STT settle), so track the last change here.
                guard phoneCallActive, phase == .listening else { return }
                lastTranscriptChangeAt = Date()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                // A talk with unsaved turns doesn't just vanish on a stray ✕
                // tap — closing is gated behind an explicit choice between
                // saving (the End flow: summary + drills) and discarding.
                if !turns.isEmpty && !didSaveCurrentSession {
                    confirmingDiscard = true
                } else {
                    close()
                }
            } label: {
                Label("Close", systemImage: "xmark")
            }
            // Anchored on the ✕ itself, not on the screen: iOS presents a
            // confirmation dialog as a popover that emerges from the view the
            // modifier hangs off. Attached to the root container it pointed at
            // the bottom-center mic pill — the one control it has nothing to
            // do with. Keep it here so the sheet grows out of the button the
            // user actually tapped.
            .confirmationDialog("This conversation isn't saved yet",
                                isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button("Save conversation") {
                    Task { await endSession() }
                }
                Button("Close without saving", role: .destructive) {
                    close()
                }
            } message: {
                Text("Saving wraps up the talk and keeps the transcript, feedback, and drills.")
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
                        RetryReplyRow(outOfCredits: outOfCredits,
                                      onRetry: retryReply,
                                      onGetCredits: { showingPaywall = true })
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
            // The pixel grid lives INSIDE the pill, not across the screen.
            // The shader paints the whole surface theme-aware in a pure-blue
            // mosaic: airy white with blue pixels in light mode, near-black
            // with sky pixels in dark.
            Button { Task { await handleMicTap() } } label: {
                ZStack {
                    Futureself(mode: glowMode, level: voiceLevel)
                    // Glyph ONLY while the conversation is stopped — an
                    // invitation to talk. During the call the living surface
                    // itself is the state display (ignites with your voice,
                    // scans while thinking, blooms while speaking); an icon on
                    // top just fights the pixels and reads poorly.
                    if let symbol = micSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    }
                }
                .frame(width: 156, height: 64)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                // The shader is `.allowsHitTesting(false)`, so with the glyph
                // gone (on call) the label had NO tappable content and the
                // hang-up tap silently died. Make the whole capsule the target.
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
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
        .onChange(of: live.level) { _, new in
            guard phase == .listening else { return }
            voiceLevel = new
        }
        .onChange(of: player.level) { _, new in
            guard phase == .speaking else { return }
            voiceLevel = new
        }
        .onChange(of: phase) { _, _ in voiceLevel = 0 }
    }

    private var glowMode: Futureself.Mode {
        switch phase {
        case .idle:      return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .speaking:  return .speaking
        }
    }


    /// nil while on call — the Futureself surface carries the state; the mic
    /// glyph appears only when the conversation is stopped (tap to start).
    private var micSymbol: String? {
        phoneCallActive ? nil : "mic.fill"
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

    /// With the pill glyph-free while on call, this line is the ONE place
    /// that says tapping hangs up — every in-call state must name it.
    private var micHint: String {
        if phoneCallActive {
            switch phase {
            case .listening: return "Listening · pause to send · tap to stop"
            case .thinking:  return "Thinking… · tap to stop"
            case .speaking:  return "Speaking… · tap to stop"
            case .idle:      return "On call · tap to stop"
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

    /// Energy-based endpointing loop, started with the mic. Every tick it
    /// checks how long the mic has ACTUALLY been silent (last voiced audio,
    /// not last transcript change) against the text-completeness tier, and
    /// auto-sends when both the audio and the STT partial have settled.
    private func startEndpointMonitor() {
        cancelSilenceTimer()
        silenceTask = Task { @MainActor in
            while !Task.isCancelled, phoneCallActive, phase == .listening {
                try? await Task.sleep(nanoseconds: UInt64(Self.endpointTickSeconds * 1_000_000_000))
                guard !Task.isCancelled, phoneCallActive, phase == .listening else { return }
                // Nothing transcribed yet → the user hasn't said anything
                // (or STT hasn't caught up). Never send an empty turn.
                guard !live.transcript.trimmingCharacters(in: .whitespaces).isEmpty,
                      let lastVoiced = live.lastVoicedAt else { continue }
                let audioSilence = Date().timeIntervalSince(lastVoiced)
                let sinceTextChange = lastTranscriptChangeAt.map { Date().timeIntervalSince($0) }
                    ?? .greatestFiniteMagnitude
                // The user has plausibly finished — spend the rest of the VAD
                // wait warming the network path (TLS + auth token) so the turn
                // request fires onto a hot connection.
                if audioSilence >= Self.preconnectAfterSilenceSeconds, !didPreconnectThisTurn {
                    didPreconnectThisTurn = true
                    GeminiClient.shared.preconnect()
                }
                // Primary: real audio silence for the tier duration, AND the
                // recognizer's partial has settled (its lag would otherwise
                // truncate the turn's tail).
                let audioSettled = audioSilence >= currentVadWaitSeconds()
                    && sinceTextChange >= Self.sttSettleSeconds
                // Fallback: steady background noise never reads as silent —
                // fire on the old transcript-quiet signal as an upper bound.
                let transcriptSettled = sinceTextChange >= Self.noisyRoomFallbackSeconds
                guard audioSettled || transcriptSettled else { continue }
                turnTiming = ["vad_wait_ms": String(Int(audioSilence * 1000))]
                turnEndedSpeakingAt = Date()
                HapticEngine.voiceSent()
                await stopAndSend()
                return
            }
        }
    }

    /// Inspect the latest STT transcript and pick a REQUIRED TRUE-SILENCE
    /// duration (seconds since the mic last heard voiced audio):
    ///   • 5.0s — clearly mid-thought (filler / hanging conjunction / stub).
    ///   • 1.2s — wrapped up cleanly (terminal punctuation .!?).
    ///   • 2.2s — anything in between.
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
        // The opener plays before any mic session exists — arm the call's
        // audio session or the greeting streams into `.soloAmbient` (muted by
        // the ring switch on most phones). Detached: `setActive` can block
        // for hundreds of ms, and inline it lands exactly on the open-morph
        // frames. It runs while the opener text is fetched; awaited below
        // before anything plays.
        let audioSessionReady = Task.detached(priority: .userInitiated) {
            AudioSessionRouting.warmUpForConversation()
        }
        do {
            let opener: String
            if topicIsNews, let fromPool = openNewsConversation() {
                opener = fromPool
            } else if topic.isEmpty,
                      let canned = FreeTalkOpeners.shared.next(
                          language: appState.targetLanguage,
                          personaName: appState.persona?.displayName) {
                // Free talk: greetings are interchangeable, so rotate a stored
                // pool instead of paying a Gemini call per session — and since
                // the texts repeat verbatim, the TTS content cache makes the
                // voice free after each line's first play.
                opener = canned
            } else if topic.isEmpty,
                      let generated = try? await FreeTalkOpeners.shared.generatePool(
                          language: appState.targetLanguage,
                          personaName: appState.persona?.displayName,
                          proficiency: appState.proficiency) {
                // First free talk (or language/persona changed): ONE call
                // writes the whole pool; later sessions rotate through it.
                opener = generated
            } else if let sid = sessionScenarioId,
                      let stored = appState.nextScenarioOpener(for: sid) {
                // Scenario talk with a stored opener pool: rotate — instant
                // start, no Gemini call, and the line's TTS is already in the
                // phrase cache after its first play.
                opener = stored
            } else {
                opener = try await generateOpener()
            }
            // The screen may have closed while the opener was being fetched.
            guard !isTornDown else { return }
            // Session must be armed before playback OR the mic fallback below.
            await audioSessionReady.value
            // Speak the opener in the cloned voice — a call starts with the
            // fluent self TALKING, not a line to read. Repeated openers for
            // the same phrasing hit the content cache, and the idempotency
            // key keeps a re-open from billing ElevenLabs twice.
            if let voiceId = appState.voiceCloneId {
                do {
                    try await speakAndAppend(opener, voiceId: voiceId,
                                             idempotencyKey: "tts-opener:\(sessionId.uuidString)")
                    // speakAndAppend owns the phase from here: playback
                    // completion flips back to .idle and re-enters listening
                    // in phone-call mode.
                    return
                } catch {
                    // TTS blip — fall through to the text-only opener rather
                    // than failing the whole session open.
                }
            }
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
            outOfCredits = error.isOutOfCredits
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    /// News topic: ZERO LLM calls. The platform news pool already generated
    /// this story once for everyone — the title is phrased as a friend
    /// bringing it up (that IS the opener) and the blurb is plain facts from
    /// the grounded pool generation. Day-old facts are fine for a practice
    /// talk; the per-user search-grounded opener this replaces was the single
    /// most expensive call in the app. Returns nil when there's nothing to
    /// speak — caller falls back to the plain opener.
    /// Topic/scenario opener. Scenario-backed talks generate a THREE-line
    /// pool in ONE call (same cost as the old single line) and store it on
    /// the scenario — every later talk rotates the pool for free. Custom
    /// topics (no scenario id) keep the single-line call.
    private func generateOpener() async throws -> String {
        let languageName = LanguageCatalog.englishName(appState.targetLanguage)
        if let sid = sessionScenarioId {
            struct OpenerPool: Decodable { let openers: [String] }
            let payload: OpenerPool? = try? await GeminiClient.shared.sendJSON(
                system: systemPrompt(),
                messages: [GeminiClient.Message(
                    role: .user,
                    content: """
                    Write THREE different natural opening lines in \(languageName) for this conversation.
                    Be IN the scenario — don't summarize it, don't explain it. Each line is the first
                    thing you'd say if this were really happening, in a way the user can respond to.
                    Make the three genuinely different angles, not rephrasings.
                    Return STRICT JSON only — no prose: { "openers": ["...", "...", "..."] }
                    """
                )],
                maxTokens: 500,
                purpose: "opener",
                idempotencyKey: "opener:\(sessionId.uuidString)"
            )
            let pool = (payload?.openers ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let first = pool.first {
                appState.storeScenarioOpeners(pool, for: sid)
                return first
            }
            // Pool call failed → fall through to the single-line opener
            // (same idempotency key: one logical opener, one charge).
        }
        return try await GeminiClient.shared.send(
            system: systemPrompt(),
            messages: [GeminiClient.Message(
                role: .user,
                content: """
                Open this conversation with ONE natural opening line in \(languageName).
                Be IN the scenario — don't summarize it, don't explain it. Just say the first
                thing you'd say if this were really happening, in a way the user can respond to.
                """
            )],
            purpose: "opener",
            idempotencyKey: "opener:\(sessionId.uuidString)"
        )
    }

    private func openNewsConversation() -> String? {
        let opener = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !opener.isEmpty else { return nil }
        // Pool facts (seeded via init) win; a pre-facts pool row falls back
        // to the blurb so the talk is never fact-free.
        if newsFacts.isEmpty {
            let fact = topicBlurb.trimmingCharacters(in: .whitespacesAndNewlines)
            newsFacts = fact.isEmpty ? [] : [fact]
        }
        return opener
    }

    private func startRecording() async {
        guard !isTornDown else { return }
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            // iOS won't re-prompt once denied — guide the user to Settings
            // instead of dead-ending on a generic error.
            phoneCallActive = false
            phase = .idle
            showMicPermissionAlert = true
            return
        }
        do {
            // Conversation keeps the Bluetooth (HFP) mic allowed: the whole
            // point of earphones is phone-in-pocket, where the built-in mic
            // hears nothing. Accuracy comes from the server recognition
            // model + the contextual hints below — modern earphones negotiate
            // 16 kHz mSBC, which server ASR handles fine (it's what Siri
            // uses through AirPods too).
            try live.start(locale: appState.targetLanguage,
                           contextualStrings: recognitionHints(),
                           captureToFile: true)   // keep the user's own audio for listen-back
            userSpeechStartedAt = Date()
            lastTranscriptChangeAt = nil
            didPreconnectThisTurn = false
            phase = .listening
            startEndpointMonitor()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Vocabulary the user is LIKELY to say this turn — biases STT toward
    /// the conversation's domain (topic words, names, news terms). Rebuilt
    /// every turn since the mic restarts per turn.
    ///
    /// Deliberately does NOT include the fluent self's last line: contextual
    /// strings make the recognizer substitute toward the hint list whenever
    /// the audio is unclear, so biasing toward the avatar's words puts words
    /// in the user's mouth they never said.
    private func recognitionHints() -> [String] {
        var hints: [String] = []
        if !topic.isEmpty { hints.append(topic) }
        if let name = appState.persona?.displayName, !name.isEmpty { hints.append(name) }
        hints.append(contentsOf: appState.persona?.interests ?? [])
        for fact in newsFacts { hints.append(contentsOf: Self.significantWords(fact)) }
        var seen = Set<String>()
        return hints.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Content-word extraction for recognition hints: keeps tokens ≥ 4 chars
    /// (drops articles/particles that would only add noise to the bias list).
    private static func significantWords(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
    }

    // NOTE: called from INSIDE the endpoint-monitor task — do not
    // cancelSilenceTimer() here, that would self-cancel and abort the
    // Gemini/TTS awaits below. Setting phase = .thinking is what makes the
    // monitor loop exit on its next tick.
    private func stopAndSend() async {
        // .thinking first so the endpoint monitor exits, then wait the beat
        // for the recognizer's FINAL pass — the committed turn text is the
        // language-model-rescored version, not the last raw partial.
        phase = .thinking
        let finalizeStarted = Date()
        let finalText = await live.stopAndFinalize()
        turnTiming["finalize_ms"] = String(Int(Date().timeIntervalSince(finalizeStarted) * 1000))
        // Whether the rescored FINAL pass actually landed before the turn
        // shipped. `final_timeout=1` means the user's words went out as the
        // recognizer's un-rescored partial — previously unobservable, and the
        // only way to tell if `quietCommitThreshold` needs retuning next.
        if let w = live.lastFinalizeWait {
            turnTiming["final_pending"] = String(w.pendingSegments)
            turnTiming["final_timeout"] = w.timedOut ? "1" : "0"
            turnTiming["final_upgraded"] = w.upgradedText ? "1" : "0"
        }
        let fluency = live.fluencyStats()
        let elapsedMs = Int((Date().timeIntervalSince(userSpeechStartedAt ?? Date())) * 1000)
        userSpeechStartedAt = nil

        var userTurn = Turn(
            id: UUID(), role: .user, audioURL: nil,
            transcript: finalText, durationMs: max(0, elapsedMs), timestamp: Date(),
            suggestion: nil,
            fluency: fluency
        )
        // Keep the user's own audio so they can listen back to how they
        // actually sounded (temp AAC from the mic tap → TurnAudioStore).
        if let rec = live.lastRecordingURL, let data = try? Data(contentsOf: rec) {
            userTurn.audioURL = TurnAudioStore.shared.save(data, turnId: userTurn.id)
            try? FileManager.default.removeItem(at: rec)
        }
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
        outOfCredits = false
        phase = .thinking
        guard let voiceId = appState.voiceCloneId else { phase = .idle; return }
        do {
            // Attach the user's own recorded utterance so Gemini hears what
            // was ACTUALLY said — on-device STT is the weak link for accented
            // speech; the model returns its own verbatim transcript alongside
            // the reply. AAC-ADTS at ~32 kbps (8–13× smaller than the old WAV
            // path) so the upload survives weak cellular uplinks; WAV remains
            // as the encode-failure fallback. On a constrained link (Low Data
            // Mode / degraded path) skip the attachment entirely — a text-only
            // turn NOW beats an audio turn that dies at the 40s timeout.
            var turnAudio: GeminiClient.Message.InlineAudio?
            let path = NetworkPathStatus.shared
            if path.isSatisfied, !path.isConstrained,
               let turn = turns.first(where: { $0.id == turnId }), turn.role == .user,
               let url = turn.audioURL {
                if let aac = AudioLoudness.aacADTS16kMono(fromFileAt: url),
                   !aac.isEmpty, aac.count <= 600_000 {   // ~2min at 32kbps
                    turnAudio = .init(mimeType: "audio/aac",
                                      base64Data: aac.base64EncodedString())
                } else if let wav = AudioLoudness.wav16kMono(fromFileAt: url),
                          !wav.isEmpty, wav.count <= 3_000_000 {   // ~90s at 16kHz
                    turnAudio = .init(mimeType: "audio/wav",
                                      base64Data: wav.base64EncodedString())
                }
            }
            switch turnAudio?.mimeType {
            case "audio/aac": turnTiming["audio"] = "aac"
            case "audio/wav": turnTiming["audio"] = "wav"
            default:          turnTiming["audio"] = "none"
            }
            let geminiStarted = Date()
            // The reply is the FIRST field of the streamed turn JSON, so TTS
            // starts the instant it closes — the suggestion and the verbatim
            // transcript that follow it are written while the voice is already
            // loading, instead of ahead of the first sound.
            var speakTask: Task<Void, Error>?
            let speakEarly: @MainActor (String) -> Void = { reply in
                guard speakTask == nil, !isTornDown else { return }
                let text = Self.stripLeakedSchemaTail(reply)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                turnTiming["gemini_first_ms"] =
                    String(Int(Date().timeIntervalSince(geminiStarted) * 1000))
                speakTask = Task { @MainActor in
                    try await speakAndAppend(text, voiceId: voiceId,
                                             idempotencyKey: "tts-turn:\(turnId.uuidString)")
                }
            }
            let payload: ConversationTurnPayload
            do {
                payload = try await turnPayload(audio: turnAudio, turnId: turnId,
                                                onReply: speakEarly)
            } catch where turnAudio != nil && !error.isOutOfCredits {
                // The audio-attached call is the NEW, riskier path (bigger
                // upload, audio ingestion, longer JSON). If it fails for any
                // retryable reason, silently rerun the exact pre-audio call —
                // same idempotency key, so no second charge — instead of
                // showing the error chip. Worst case = old behavior.
                Telemetry.log("talk_audio_rescue", [
                    "error": (error as NSError).domain + ":\((error as NSError).code)",
                ])
                turnAudio = nil
                payload = try await turnPayload(audio: nil, turnId: turnId,
                                                onReply: speakEarly)
            }
            turnTiming["gemini_ms"] = String(Int(Date().timeIntervalSince(geminiStarted) * 1000))
            // The screen may have closed while the reply was in flight.
            guard !isTornDown else { return }
            // Upgrade the turn to what the model actually HEARD (audio is the
            // ground truth) — the feed, session summary, drills, and profile
            // all learn from the real utterance instead of the ASR guess.
            if turnAudio != nil,
               let heard = payload.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
               !heard.isEmpty,
               let idx = turns.firstIndex(where: { $0.id == turnId }) {
                turns[idx].transcript = heard
            }
            let replyText = Self.stripLeakedSchemaTail(payload.reply)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = payload.turnSuggestion(),
               let idx = turns.firstIndex(where: { $0.id == turnId }) {
                turns[idx].suggestion = s
            }
            // Already speaking from the stream callback: adopt its result so a
            // TTS failure still reaches the catch below and offers Retry.
            // Otherwise (no early fire — buffered fallback) speak now.
            if let speakTask {
                try await speakTask.value
            } else {
                try await speakAndAppend(replyText, voiceId: voiceId,
                                         idempotencyKey: "tts-turn:\(turnId.uuidString)")
            }
            // DO NOT set phase = .idle here. speakAndAppend kicks off audio
            // playback (non-blocking) whose completion flips phase back to
            // .idle AND auto-restarts listening for phone-call mode.
        } catch {
            // Keep the user's turn and offer an inline Retry instead of a
            // dead-end alert, so a network blip doesn't lose what they said.
            // Out-of-credits is NOT retryable — flag it so the row shows the
            // paywall instead of a retry loop that can never succeed.
            Telemetry.log("talk_turn_error", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "out_of_credits": error.isOutOfCredits ? "1" : "0",
            ])
            outOfCredits = error.isOutOfCredits
            failedTurnId = turnId
            phase = .idle
        }
    }

    /// One structured turn call: transcript + reply + optional inline
    /// correction (repopulates Turn.suggestion: chip UI, SRS ingest,
    /// weekly-report pairs, suggestion_rate metric). Throws on an empty
    /// reply so the caller's audio→text rescue (and the Retry chip) engage
    /// instead of silently dead-ending the turn.
    private func turnPayload(audio: GeminiClient.Message.InlineAudio?,
                             turnId: UUID,
                             onReply: @MainActor @escaping (String) -> Void)
    async throws -> ConversationTurnPayload {
        do {
            let payload: ConversationTurnPayload = try await GeminiClient.shared.sendJSONStream(
                system: systemPrompt()
                    + ConversationEngine.turnOutputInstruction(targetLanguage: appState.targetLanguage),
                messages: ConversationEngine.geminiMessages(from: turns, lastUserAudio: audio),
                // Headroom for transcript + reply + suggestion: a MAX_TOKENS
                // truncation shows up here as a DecodingError-failed turn.
                // gen-3 counts THINKING tokens against this ceiling too, so the
                // budget is shared with reasoning the user never sees — and the
                // transcript field scales with how long the user just spoke.
                // At 1024 that combination truncated ~8% of turns into a dead
                // Retry chip (evenly split across wifi/cellular, i.e. not a
                // network fault). The ceiling is not billed, only tokens
                // actually produced, so the headroom is free.
                maxTokens: 2048,
                temperature: 0.7,
                purpose: "turn",
                // Keyed to the user turn: the inline Retry button and the
                // audio→text rescue re-run this same logical request without
                // a second charge.
                idempotencyKey: "turn:\(turnId.uuidString)",
                // Audio-attached calls get a short idle timeout so a stalled
                // upload fails into the text-only rescue in seconds instead
                // of eating the session-wide 40s window first.
                requestTimeout: audio != nil ? 20 : nil,
                // Speak as soon as "reply" closes; everything after it in the
                // JSON (suggestion, transcript) lands while the voice loads.
                earlyField: "reply",
                onEarlyField: onReply,
                // Stream cut after the reply shipped: keep the turn the user
                // already heard, minus the correction.
                fallbackFromEarly: { ConversationTurnPayload(reply: $0, suggestion: nil) }
            )
            guard !payload.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.invalidResponse
            }
            return payload
        } catch GeminiError.jsonNotFound(let raw) {
            // Model slipped out of JSON mode. Speak the raw text ONLY when it
            // is actual prose — a fragment starting with "{" is a truncated
            // JSON body, and reading that aloud is worse than failing into
            // the rescue/Retry path.
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else {
                throw GeminiError.invalidResponse
            }
            return ConversationTurnPayload(reply: trimmed, suggestion: nil)
        }
    }

    /// Defensive cleanup: a malformed model turn occasionally NESTS the whole
    /// {reply, suggestion, transcript} schema INSIDE the reply string (escaped),
    /// so after JSON-decoding the reply literally trails with
    /// `","suggestion":null,"transcript":"…"}`. That must never be spoken —
    /// cut the reply at the first such seam.
    static func stripLeakedSchemaTail(_ reply: String) -> String {
        let pattern = #""\s*,\s*"(?:suggestion|transcript|reply)"\s*:"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: reply, range: NSRange(reply.startIndex..., in: reply)),
              let r = Range(m.range, in: reply) else {
            return reply
        }
        return String(reply[..<r.lowerBound])
    }

    private func retryReply() {
        guard let id = failedTurnId else { return }
        Task { await requestReply(forUserTurn: id) }
    }

    /// Log the accumulated per-turn latency breadcrumbs exactly once, at the
    /// moment the fluent self's voice starts (what the user experiences as
    /// "the answer arrived"). No-op for non-turn speech (openers) — their
    /// timing dict is empty.
    private func logTurnTiming(tts: String, ttsFirstMs: Int? = nil) {
        guard !turnTiming.isEmpty else { return }
        var props = turnTiming
        props["tts"] = tts
        if let ttsFirstMs { props["tts_first_ms"] = String(ttsFirstMs) }
        if let anchor = turnEndedSpeakingAt {
            props["total_ms"] = String(Int(Date().timeIntervalSince(anchor) * 1000))
        }
        turnTiming = [:]
        turnEndedSpeakingAt = nil
        Telemetry.log("talk_turn_timing", props)
    }

    private func speakAndAppend(_ text: String, voiceId: String,
                                idempotencyKey: String? = nil) async throws {
        guard !isTornDown else { return }
        // Content-addressed cache hit avoids re-billing ElevenLabs for repeated
        // fluent-self lines (greetings, short acknowledgements, etc.).
        // `allowLineage: false` — a LIVE call must sound like one take, so an
        // older clone's recording is never spliced in mid-conversation. Review
        // surfaces (scenes, drills, shadow) do accept it.
        if let cached = PhraseAudioStore.shared.data(text: text, voiceId: voiceId,
                                                    allowLineage: false) {
            let timings = PhraseAudioStore.shared.timings(text: text, voiceId: voiceId,
                                                          allowLineage: false) ?? []
            try appendTurnAndPlay(cached, timings: timings, transcript: text)
            logTurnTiming(tts: "cache")
            return
        }
        let ttsStarted = Date()

        // Streaming-first: the fluent self starts talking on the FIRST PCM
        // chunk (~0.2s of audio) instead of after the whole file downloads.
        // Any failure BEFORE audio starts falls back silently to the classic
        // buffered call below; a failure mid-playback surfaces as a retry.
        var streamTurnId: UUID?         // set once playback actually started
        var receivedAnyChunk = false
        do {
            let result = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: text,
                modelId: ElevenLabsClient.conversationModelId,
                idempotencyKey: idempotencyKey,
                purpose: "turn"
            ) { chunk in
                // Closed mid-stream: swallow the chunks — never (re)start
                // playback on a dead screen.
                if isTornDown { return }
                if !receivedAnyChunk {
                    receivedAnyChunk = true
                    do {
                        try player.startPCMStream(sampleRate: ElevenLabsClient.streamSampleRate,
                                                  voiceKey: voiceId) {
                            Task { @MainActor in
                                guard phase == .speaking else { return }
                                phase = .idle
                                // Phone call: avatar just finished talking →
                                // loop back to listening without a tap.
                                if phoneCallActive {
                                    await startRecording()
                                }
                            }
                        }
                        let id = UUID()
                        streamTurnId = id
                        turns.append(Turn(
                            id: id, role: .fluentSelf, audioURL: nil,
                            transcript: text, durationMs: 0, timestamp: Date(),
                            suggestion: nil
                        ))
                        didSaveCurrentSession = false
                        phase = .speaking
                        logTurnTiming(tts: "stream",
                                      ttsFirstMs: Int(Date().timeIntervalSince(ttsStarted) * 1000))
                    } catch {
                        // Engine refused to start — keep collecting the PCM;
                        // we'll play the accumulated audio the buffered way.
                        streamTurnId = nil
                    }
                }
                if streamTurnId != nil { player.feedPCMStream(chunk) }
            }

            switch result {
            case .pcm22050(let fullPCM) where streamTurnId != nil && !fullPCM.isEmpty:
                player.finishPCMStream()
                let wav = AudioLoudness.wavData(
                    fromPCM16: fullPCM, sampleRate: Int(ElevenLabsClient.streamSampleRate))
                let durationMs = Int(Double(fullPCM.count / 2)
                    / ElevenLabsClient.streamSampleRate * 1000)
                PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: [])
                let savedURL = TurnAudioStore.shared.save(wav, turnId: streamTurnId!)
                if let idx = turns.firstIndex(where: { $0.id == streamTurnId }) {
                    turns[idx].audioURL = savedURL
                    turns[idx].durationMs = durationMs
                }
                Task {
                    do {
                        let (_, timings) = try await ElevenLabsClient.shared.synthesizeWithTimestamps(
                            voiceId: voiceId, text: text,
                            modelId: ElevenLabsClient.conversationModelId,
                            idempotencyKey: idempotencyKey,
                            purpose: "turn")
                        if !timings.isEmpty {
                            PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: timings)
                            TurnAudioStore.shared.saveTimings(timings, for: streamTurnId!)
                        }
                    } catch {
                        // Timing recovery failed — audio already cached, karaoke will use estimate
                    }
                }
                return
            case .pcm22050(let fullPCM) where !fullPCM.isEmpty:
                let wav = AudioLoudness.wavData(
                    fromPCM16: fullPCM, sampleRate: Int(ElevenLabsClient.streamSampleRate))
                PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: [])
                try appendTurnAndPlay(wav, timings: [], transcript: text)
                Task {
                    do {
                        let (_, timings) = try await ElevenLabsClient.shared.synthesizeWithTimestamps(
                            voiceId: voiceId, text: text,
                            modelId: ElevenLabsClient.conversationModelId,
                            idempotencyKey: idempotencyKey,
                            purpose: "turn")
                        if !timings.isEmpty {
                            PhraseAudioStore.shared.save(wav, text: text, voiceId: voiceId, timings: timings)
                            let turnId = turns.last(where: { $0.transcript == text })?.id
                            if let id = turnId {
                                TurnAudioStore.shared.saveTimings(timings, for: id)
                            }
                        }
                    } catch {
                        // Timing recovery failed — audio already playing, karaoke will use estimate
                    }
                }
                logTurnTiming(tts: "buffered")
                return
            case .mp3(let data) where !data.isEmpty:
                PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId, timings: [])
                try appendTurnAndPlay(data, timings: [], transcript: text)
                Task {
                    do {
                        let (_, timings) = try await ElevenLabsClient.shared.synthesizeWithTimestamps(
                            voiceId: voiceId, text: text,
                            modelId: ElevenLabsClient.conversationModelId,
                            idempotencyKey: idempotencyKey,
                            purpose: "turn")
                        if !timings.isEmpty {
                            PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId, timings: timings)
                            let turnId = turns.last(where: { $0.transcript == text })?.id
                            if let id = turnId {
                                TurnAudioStore.shared.saveTimings(timings, for: id)
                            }
                        }
                    } catch {
                        // Timing recovery failed — audio already playing, karaoke will use estimate
                    }
                }
                logTurnTiming(tts: "buffered")
                return
            default:
                break   // empty payload → buffered fallback below
            }
        } catch {
            Telemetry.log("talk_tts_stream_fallback", [
                "error": (error as NSError).domain + ":\((error as NSError).code)",
                "mid_stream": streamTurnId != nil ? "1" : "0",
            ])
            if let id = streamTurnId {
                // Audio already started, then the stream broke mid-sentence
                // (cellular loves doing this): stop cleanly, drop the
                // half-spoken turn, and fall through to the buffered call —
                // same idempotency key, so the re-synthesis isn't charged
                // again. The line restarts from the top, which beats
                // dead-ending the call on a Retry button. If the buffered
                // call fails too, THAT error surfaces as the retry row.
                // stop() doesn't fire the stream completion, so phase stays
                // ours to manage — back to .thinking while we re-fetch.
                player.stop()
                turns.removeAll { $0.id == id }
                phase = .thinking
            }
            // No audio reached the speaker → silent fallback.
        }

        let (newAudio, newTimings) = try await ElevenLabsClient.shared
            .synthesizeWithTimestamps(voiceId: voiceId, text: text,
                                      modelId: ElevenLabsClient.conversationModelId,
                                      idempotencyKey: idempotencyKey,
                                      purpose: "turn")
        PhraseAudioStore.shared.save(newAudio, text: text, voiceId: voiceId, timings: newTimings)
        try appendTurnAndPlay(newAudio, timings: newTimings, transcript: text)
        logTurnTiming(tts: "buffered")
    }

    /// Buffered playback path: append the fluent-self turn and play the full
    /// audio file (MP3 or WAV). Used for cache hits, the non-streaming
    /// fallback, and older edge deployments.
    private func appendTurnAndPlay(_ audio: Data, timings: [WordTiming],
                                   transcript text: String) throws {
        guard !isTornDown else { return }
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
        try player.play(audio, source: "conversation", configureSession: false) {
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
        // Persist the raw conversation FIRST. The summary call below can fail
        // (network, credits, malformed JSON) and turns live only in memory —
        // without this draft save a failed summary used to lose the whole
        // session. The full save further down overwrites this row (same id).
        SessionStore.shared.save(Session(
            id: sessionId,
            userId: userId,
            targetLanguage: appState.targetLanguage,
            mode: .conversation,
            topic: topic.isEmpty ? nil : topic,
            startedAt: sessionStartedAt,
            endedAt: Date(),
            turns: turns,
            summary: nil,
            origin: sessionOrigin,
            originScenarioId: sessionScenarioId
        ))
        didSaveCurrentSession = true
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
            // Stable idempotency key: re-tapping End after a failure with the
            // same turn count retries the summary without a second charge.
            let payload: ClaudeSummaryPayload = try await GeminiClient.shared.sendJSON(
                system: systemP,
                messages: [GeminiClient.Message(role: .user, content: userMessage)],
                maxTokens: 1400,
                purpose: "summary",
                idempotencyKey: "summary:\(sessionId.uuidString):\(turns.count)"
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

            // Same guard for grammar evidence: a quote the user can't find in
            // their own words destroys trust in the whole list. Compare with
            // punctuation/casing stripped — STT and the LLM disagree on those
            // even when the words match.
            func normalized(_ s: String) -> String {
                s.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            let normalizedHaystack = normalized(haystack)
            computed.grammarIssues = computed.grammarIssues.filter {
                let needle = normalized($0.quote)
                // A "fix" that only touches punctuation/casing (normalized
                // forms identical) is a transcription nitpick, not a spoken
                // grammar error — drop it.
                return !needle.isEmpty && normalizedHaystack.contains(needle)
                    && needle != normalized($0.correction)
            }

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
                summary: computed,
                origin: sessionOrigin,
                originScenarioId: sessionScenarioId
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
            outOfCredits = error.isOutOfCredits
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func refreshDashboard() {
        // Off-main: `PracticeStats.snapshot()` decodes the FULL session
        // archive — on the appear frame it visibly hitches the pill→call
        // morph, and it only gets slower as sessions accumulate. Reads only,
        // so a background hop is safe; results land back on the main actor.
        Task.detached(priority: .utility) {
            let due = DrillStore.shared.dueCount()
            let snap = PracticeStats.snapshot()
            await MainActor.run {
                dueDrillCount = due
                dashboard = snap
            }
        }
    }

    /// Exit the call screen — back to the presenter's morph when hosted in
    /// RootTabView's ZStack, plain dismiss when presented as a cover.
    private func close() {
        tearDown()
        if let onClose { onClose() } else { dismiss() }
    }

    /// Hard-stop every live pipeline this screen owns, and mark the screen
    /// dead so in-flight async work can't resurrect audio after the UI is
    /// gone. Idempotent — safe to call from any close path.
    private func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        if phoneCallActive { HapticEngine.phoneCallEnded() }
        phoneCallActive = false
        cancelSilenceTimer()
        _ = live.stop()
        player.stop()
        phase = .idle
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
        // First-ever finished conversation → ask for feedback before leaving;
        // the sheet's onDismiss completes the exit.
        if BetaFeedback.shouldShow(.firstTalk) {
            BetaFeedback.markShown(.firstTalk)
            dismissAfterFeedback = true
            feedbackContext = .firstTalk
        } else {
            close()
        }
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
            persona: appState.persona,
            newsFacts: newsFacts
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

    /// Speaker separation (side, fill, name label) comes from `DialogueLine`
    /// — the same component Watch and the conversation archive use — so the
    /// three surfaces stay in sync when the style changes.
    private var speaker: DialogueSpeaker { turn.role == .user ? .user : .other }

    var body: some View {
        DialogueLine(speaker: speaker,
                     name: turn.role == .user ? "You" : "Future self",
                     scale: .call) {
            Text(turn.transcript)
        } accessory: {
            VStack(alignment: speaker.alignment, spacing: 6) {
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
                    SuggestionChip(suggestion: suggestion, original: turn.transcript,
                                   nativeLanguage: nativeLanguage)
                }
            }
        }
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
    let original: String
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
                Text(highlightedCorrection(suggestion.alternative, original: original, baseFont: .subheadline))
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
        if let c = Translator.cachedExplanation(original: original, alternative: suggestion.alternative,
                                                to: nativeLanguage) {
            reasonNative = c
            return
        }
        loading = true
        Task {
            let t = await Translator.explainCorrection(original: original, alternative: suggestion.alternative,
                                                       to: nativeLanguage)
            reasonNative = t
            loading = false
            if t == nil { showing = false }
        }
    }
}

private struct PartialTurnView: View {
    let text: String

    /// The in-progress user line — same slot and fill as the finished turn it
    /// becomes, so nothing jumps sideways when the final transcript lands.
    var body: some View {
        DialogueLine(speaker: .user, name: "You", scale: .call) {
            Text(text.isEmpty ? "Listening…" : text)
                .foregroundStyle(.secondary)
                .italic(text.isEmpty)
        }
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

/// Inline recovery row shown under the last user turn when the reply failed.
/// Two personalities: a network/Gemini/TTS blip gets a Retry; running out of
/// credits gets the paywall — retrying a 402 can never succeed, so offering
/// only Retry there reads as "the app is broken".
struct RetryReplyRow: View {   // internal: DebugCaptureHarness renders it
    var outOfCredits: Bool = false
    let onRetry: () -> Void
    var onGetCredits: () -> Void = {}

    var body: some View {
        if outOfCredits {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("You're out of credits, so your future self can't reply.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("See plans", action: onGetCredits)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
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
}

/// Post-talk wrap-up — now just the ONE session detail page
/// (`ConversationDetailView`) in post-talk mode, so what you see right after
/// a talk and what Practice opens later are the same page. The session was
/// saved before this sheet is presented; the page reads it back from the
/// store. The summary parameter only drives the sheet's item identity.
private struct SummarySheet: View {
    let summary: SessionSummary
    let sessionId: UUID
    let onDone: () -> Void
    let onStartNew: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var session: Session?

    var body: some View {
        NavigationStack {
            if let session {
                ConversationDetailView(
                    session: session,
                    postTalk: .init(onDone: onDone, onStartNew: onStartNew))
            } else {
                // Unreachable in practice: endSession saves before presenting.
                ProgressView()
            }
        }
        .onAppear {
            if var s = SessionStore.shared.load().first(where: { $0.id == sessionId }) {
                // Belt and braces: endSession saves a summary-less DRAFT before
                // the summary call. If the row read back is that draft, the
                // page would lose its score/words/expressions sections — the
                // summary we were handed is always the freshest.
                s.summary = summary
                session = s
            }
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SessionSummary: Identifiable {
    public var id: String { overallNote }
}
