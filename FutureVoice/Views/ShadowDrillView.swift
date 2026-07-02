import AVFoundation
import SwiftUI

/// Sync-mode shadow practice — Guitar-Hero-style for speech.
///
/// Tap the big mic → 3-2-1 countdown → target audio plays AND user records
/// simultaneously. Two horizontal timelines render in parallel:
///   • Target row: a dot for each word at its actual `startMs`
///   • Your row: a dot appears at the wall-clock moment each word lands in
///     the live STT transcript
/// After playback ends, the visual gap between rows shows exactly where you
/// were ahead or behind. Gemini still gives the qualitative pronunciation /
/// pacing / fix bullets, anchored to the diff.
struct ShadowDrillView: View {
    let turn: Turn
    let targetLanguage: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()
    @StateObject private var live = LiveTranscriber()

    @State private var phase: Phase = .idle
    @State private var countdownValue: Int = 0
    @State private var syncStartedAt: Date?
    @State private var userWordTimings: [UserWordHit] = []
    @State private var prevTranscript: String = ""
    @State private var recordingFileURL: URL?
    @State private var feedback: ShadowFeedback?
    @State private var diffSteps: [ShadowEngine.DiffStep] = []
    @State private var error: String?
    @State private var targetDurationMs: Int = 0
    @State private var lastAttemptDurationMs: Int = 0
    @State private var cachedAudioURL: URL?
    @State private var timings: [WordTiming] = []
    @State private var autoStopTask: Task<Void, Never>?
    /// Word-index range selected for loop practice, shared between the target
    /// line text and the timeline player (both read/write it).
    @State private var selectedWordRange: ClosedRange<Int>?
    /// First tapped word when building a range on the target line.
    @State private var selectionAnchor: Int?

    struct UserWordHit: Hashable {
        let word: String
        let ms: Int
    }

    enum Phase: Equatable {
        case idle
        case loadingAudio
        case countdown
        case syncing
        case analyzing
        case result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    targetSection
                    durationCard
                    if let fb = feedback {
                        feedbackSection(fb)
                    }
                    pastAttemptsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Shadow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Archive this line for repeat practice — saved lines
                    // live under Practice → Saved lines.
                    Button {
                        appState.toggleSavedLine(turn: turn)
                    } label: {
                        Image(systemName: appState.isLineSaved(turn.id) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(appState.isLineSaved(turn.id) ? "Remove from saved lines" : "Save line")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(phase == .syncing || phase == .countdown)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay { countdownOverlay }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .onChange(of: live.currentWordTimings) { _, new in
                applyWordTimings(new)
            }
            .task { await prepareAudio() }
        }
    }

    // MARK: - Sections

    /// Scrub / select-a-phrase / loop player. Lives in the unified bottom bar
    /// next to the speak button; hidden while recording so it can't fight the
    /// sync session.
    @ViewBuilder
    private var timelinePlayer: some View {
        if (phase == .idle || phase == .result),
           let url = cachedAudioURL,
           FileManager.default.fileExists(atPath: url.path) {
            ShadowTimelinePlayer(
                audioURL: url,
                timings: timings,
                selectedWordRange: $selectedWordRange,
                player: player
            )
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timings.isEmpty ? "no timings" : "\(timings.count) words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // Re-render at 30 Hz whenever a time-driven highlight is needed:
            // live sync (clock running) OR preview playback.
            if timings.isEmpty {
                Text(turn.transcript)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: !karaokeAnimating)) { _ in
                    karaokeWords
                }
            }
        }
    }

    /// Tappable target words: karaoke color from `wordColor`, plus a selection
    /// background for the loop range (shared with the timeline player).
    private var karaokeWords: some View {
        let alignment = positionAlignment()
        return FlowLayout(spacing: 1, lineSpacing: 6) {
            ForEach(Array(timings.enumerated()), id: \.offset) { i, wt in
                let selected = selectedWordRange?.contains(i) ?? false
                Text(wt.word)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(wordColor(at: i, wt: wt, alignment: alignment, offset: 0))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { tapWord(i) }
            }
        }
    }

    /// Tap a target word to build the loop range: first tap sets an anchor
    /// (single word); the next tap extends to a phrase; a third starts over.
    private func tapWord(_ i: Int) {
        if selectedWordRange == nil { selectionAnchor = nil }
        if let anchor = selectionAnchor {
            selectedWordRange = min(anchor, i)...max(anchor, i)
            selectionAnchor = nil
        } else {
            selectionAnchor = i
            selectedWordRange = i...i
        }
    }

    /// During live sync, the karaoke follows the ORIGINAL rhythm — once the
    /// learner starts speaking, words highlight at their target [startMs,
    /// endMs] just like a real karaoke machine. The learner uses this as a
    /// tempo guide. After analysis, each text word recolors by per-word
    /// timing accuracy (green = on, yellow = slight, orange = off).
    private var karaokeText: Text {
        guard !timings.isEmpty else {
            return Text(turn.transcript).foregroundStyle(.primary)
        }
        let alignment = positionAlignment()
        let offset = 0   // unused now (per-word timing accuracy was dropped)

        var out = Text("")
        for (i, wt) in timings.enumerated() {
            let color = wordColor(at: i, wt: wt, alignment: alignment, offset: offset)
            let word = Text(wt.word).foregroundStyle(color)
            out = i == 0 ? word : out + Text(" ") + word
        }
        return out
    }

    /// Picks the color for one target word.
    /// Order of precedence:
    ///   1. Post-attempt analysis → accuracy grading (green / yellow / orange).
    ///   2. Live sync (clock running) → karaoke by elapsed user-time.
    ///   3. Preview playback (Hear it) → karaoke by audio current-time.
    ///   4. Otherwise → secondary (waiting).
    private func wordColor(
        at i: Int,
        wt: WordTiming,
        alignment: PositionAlignment,
        offset: Int
    ) -> Color {
        if !diffSteps.isEmpty {
            // Post-analysis: text color = content accuracy only. No
            // per-word timing color (SFSpeechRecognizer streaming timestamps
            // aren't reliable enough to grade against ms thresholds).
            switch alignment.targetOp[i] {
            case .sub:   return .orange      // user said a different word here
            case .del:   return .secondary   // user skipped this word
            case .match: return .primary
            default:     return .primary
            }
        }

        if phase == .syncing, let start = syncStartedAt {
            return positionalColor(wt: wt, nowMs: Int(Date().timeIntervalSince(start) * 1000))
        }
        if player.isPlaying {
            return positionalColor(wt: wt, nowMs: Int(player.currentTime * 1000))
        }
        return .secondary
    }

    private func positionalColor(wt: WordTiming, nowMs: Int) -> Color {
        if nowMs >= wt.endMs   { return .primary }      // already passed
        if nowMs >= wt.startMs { return .accentColor }  // current word
        return .secondary                                // upcoming
    }

    /// Two parallel horizontal timelines (target on top, you on bottom).
    /// Width corresponds to the target audio duration so positions are
    /// comparable at a glance.
    /// After analysis only — shows the two durations side-by-side and the
    /// resulting pace ratio. Per-word timing dots were removed because iOS
    /// SFSpeechRecognizer doesn't expose reliable per-word timestamps for
    /// streaming recognition, so the previous green/yellow/orange dots were
    /// effectively guesses. Pacing is now (a) this honest duration card and
    /// (b) the Gemini-judged "Pacing" bullet below.
    @ViewBuilder
    private var durationCard: some View {
        if !diffSteps.isEmpty, targetDurationMs > 0 {
            let targetSec = Double(targetDurationMs) / 1000.0
            let yourSec   = Double(max(0, lastAttemptDurationMs)) / 1000.0
            let ratio     = targetSec > 0 ? yourSec / targetSec : 0

            HStack(spacing: 12) {
                durationCell(label: "Target", value: secondsLabel(targetSec))
                durationCell(label: "You",    value: secondsLabel(yourSec))
                durationCell(label: "Pace",   value: paceLabel(ratio),
                             color: paceColor(ratio))
            }
        }
    }

    private func durationCell(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func secondsLabel(_ s: Double) -> String {
        String(format: "%.1fs", s)
    }

    private func paceLabel(_ ratio: Double) -> String {
        guard ratio > 0 else { return "—" }
        return String(format: "%.2fx", ratio)
    }

    private func paceColor(_ ratio: Double) -> Color {
        // Pace within 85%–125% of target reads as healthy.
        switch ratio {
        case 0.85...1.25: return .green
        case 0.7...1.5:   return .orange
        default:          return ratio == 0 ? .secondary : .red
        }
    }

    private var karaokeAnimating: Bool {
        (phase == .syncing && syncStartedAt != nil) || player.isPlaying
    }


    // MARK: - Position alignment (diff-only)

    /// Maps each target word position to its diff op (.match / .sub / .del).
    /// Per-word timing comparisons were removed because iOS SFSpeechRecognizer
    /// doesn't give reliable streaming timestamps — pacing is now expressed at
    /// the WHOLE-attempt level via `durationCard` and Gemini's Pacing bullet.
    private struct PositionAlignment {
        var targetOp: [Int: ShadowEngine.DiffOp] = [:]
    }

    private func positionAlignment() -> PositionAlignment {
        var out = PositionAlignment()
        guard !diffSteps.isEmpty else { return out }
        var tIdx = 0
        for step in diffSteps {
            switch step.op {
            case .match: out.targetOp[tIdx] = .match; tIdx += 1
            case .sub:   out.targetOp[tIdx] = .sub;   tIdx += 1
            case .del:   out.targetOp[tIdx] = .del;   tIdx += 1
            case .ins:   break  // no target slot to mark
            }
        }
        return out
    }

    @ViewBuilder
    private func feedbackSection(_ fb: ShadowFeedback) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Feedback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(fb.matchScore)", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(scoreColor(fb.matchScore))
            }

            if !diffSteps.isEmpty {
                diffSection
            }
            if recordingFileURL != nil {
                playbackRow
            }
            // Empty bullets happen when the coach call failed — the score,
            // diff and recording above are still shown/saved.
            if !fb.pronunciation.isEmpty {
                bullet(icon: "waveform.badge.mic", label: "Pronunciation", text: fb.pronunciation)
            }
            if !fb.pacing.isEmpty {
                bullet(icon: "metronome", label: "Pacing", text: fb.pacing)
            }
            if !fb.fix.isEmpty {
                bullet(icon: "sparkles", label: "Try this", text: fb.fix)
            }
        }
    }

    /// Lists every saved shadow attempt for THIS target line, newest first.
    /// Each row: score badge + relative date + the user's STT transcript +
    /// a play button that re-plays the recorded WAV.
    @ViewBuilder
    private var pastAttemptsSection: some View {
        let past = appState.shadowAttempts
            .filter { $0.turnId == turn.id }
            .sorted { $0.createdAt > $1.createdAt }
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Past attempts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(past.count) total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(past) { attempt in
                    pastAttemptRow(attempt)
                }
            }
        }
    }

    private func pastAttemptRow(_ a: ShadowAttempt) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text("\(a.matchScore)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(pastAttemptScoreColor(a.matchScore))
                    .monospacedDigit()
                Text(a.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.learnerTranscript.isEmpty ? "(silent)" : a.learnerTranscript)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                Task { await playPastAttempt(a) }
            } label: {
                Image(systemName: pastAttemptPlayIcon(a))
                    .font(.title3)
                    .foregroundStyle(a.recordingFilename == nil
                                     ? Color.secondary.opacity(0.4)
                                     : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(a.recordingFilename == nil)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pastAttemptScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...:    return .green
        case 50..<80:  return .accentColor
        default:       return .orange
        }
    }

    private func pastAttemptPlayIcon(_ a: ShadowAttempt) -> String {
        guard let filename = a.recordingFilename else { return "speaker.slash" }
        let url = recordingFileURLForFilename(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return "speaker.slash" }
        return "play.circle"
    }

    private func recordingFileURLForFilename(_ filename: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private func playPastAttempt(_ a: ShadowAttempt) async {
        guard let filename = a.recordingFilename else { return }
        let url = recordingFileURLForFilename(filename)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            self.error = "Recording file missing."
            return
        }
        playSafely(data)
    }

    private var playbackRow: some View {
        // lineLimit(1) + scale-down keeps both labels single-line so the two
        // bordered buttons render the same height ("Hear my attempt" used to
        // wrap to two lines and grow taller than its sibling).
        HStack(spacing: 10) {
            Button { Task { await previewTarget() } } label: {
                Label("Hear target", systemImage: "play.circle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { Task { await playMyAttempt() } } label: {
                Label("Hear my attempt", systemImage: "person.wave.2")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }

    private func playMyAttempt() async {
        guard let url = recordingFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            self.error = "Recording isn't available."
            return
        }
        playSafely(data)
    }

    private var diffSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text("What I heard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                diffText.font(.body)
            }
        }
    }

    private var diffText: Text {
        var out = Text("")
        var first = true
        for step in diffSteps {
            switch step.op {
            case .match:
                out = out + space(first) + Text(step.target ?? "").foregroundStyle(.primary)
            case .sub:
                out = out + space(first) + Text(step.target ?? "").foregroundStyle(.orange)
            case .del:
                out = out + space(first) + Text(step.target ?? "").foregroundStyle(.secondary).strikethrough()
            case .ins:
                out = out + space(first) + Text("(+\(step.learner ?? ""))").foregroundStyle(.orange)
            }
            first = false
        }
        return out
    }

    private func space(_ first: Bool) -> Text { first ? Text("") : Text(" ") }

    @ViewBuilder
    private func bullet(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(text).font(.body).foregroundStyle(.primary)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }

    // MARK: - Bottom bar

    /// Unified practice panel: listen + loop (timeline) and speak (mic) in one
    /// place. Listening IS the timeline's play button, so there's no separate
    /// "Hear it" — select a phrase, loop it, then tap the mic to shadow it.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            timelinePlayer

            Button {
                Task { await handleSyncTap() }
            } label: {
                ZStack {
                    Circle()
                        .fill(.tint)
                        .frame(width: 64, height: 64)
                        .opacity(syncEnabled ? 1.0 : 0.4)
                        .scaleEffect(phase == .syncing ? 1.06 : 1.0)
                        .animation(
                            phase == .syncing
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
            .tint(phase == .syncing ? .red : .accentColor)
            .disabled(!syncEnabled)

            Text(micHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var countdownOverlay: some View {
        if phase == .countdown {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                Text("\(countdownValue)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdownValue)
            }
        }
    }

    private var previewDisabled: Bool {
        switch phase {
        case .loadingAudio, .countdown, .syncing, .analyzing: return true
        case .idle, .result: return player.isPlaying
        }
    }

    private var syncEnabled: Bool {
        switch phase {
        // Allowed even while the loop is playing — tapping the mic stops
        // playback and starts recording (see startSync).
        case .idle, .result, .syncing: return true
        case .loadingAudio, .countdown, .analyzing: return false
        }
    }

    private var micSymbol: String {
        switch phase {
        case .syncing:   return "stop.fill"
        case .analyzing: return "ellipsis"
        case .result:    return "arrow.counterclockwise"
        default:         return "mic.fill"
        }
    }

    private var micHint: String {
        switch phase {
        case .idle:        return "Tap to sync-shadow"
        case .loadingAudio:return "Loading…"
        case .countdown:   return "Speak when 0 hits"
        case .syncing:     return "Follow the highlight"
        case .analyzing:   return "Comparing…"
        case .result:      return "Tap to try again"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    // MARK: - Actions

    private func previewTarget() async {
        error = nil

        // Fast path: cached and file actually exists on disk.
        if let url = cachedAudioURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url) {
            playSafely(data)
            return
        }

        // Stale cache OR no cache yet → wipe and reload (may re-fetch).
        cachedAudioURL = nil
        await prepareAudio()

        guard let url = cachedAudioURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            // Preserve any specific error prepareAudio surfaced (e.g.
            // ElevenLabs HTTP code) instead of stomping with a generic one.
            if error == nil {
                self.error = "Couldn't load audio for this line."
            }
            return
        }
        playSafely(data)
    }

    private func playSafely(_ data: Data) {
        do {
            // forceSessionReset: a prior sync attempt may have left the
            // audio session in .measurement mode, which makes subsequent
            // .playback noticeably quieter. Force-cycle the session so the
            // preview plays at full speaker volume.
            try player.play(data, forceSessionReset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleSyncTap() async {
        switch phase {
        case .idle, .result:
            await startSync()
        case .syncing:
            finishSync()
        default:
            break
        }
    }

    private func startSync() async {
        // Stop any loop/preview playback before recording so the speaker audio
        // doesn't bleed into the mic.
        player.stop()
        // Ensure we have target timings loaded (used for the visual reference)
        if cachedAudioURL == nil {
            await prepareAudio()
        }
        guard cachedAudioURL != nil else { return }

        // Permissions
        let micOK = await recorder.requestPermission()
        let speechOK = await SpeechTranscriber.requestPermission()
        guard micOK, speechOK else {
            error = "Microphone or speech permission denied."
            return
        }

        // Reset state
        feedback = nil
        diffSteps = []
        userWordTimings = []
        prevTranscript = ""

        // Countdown 3-2-1 with haptic ticks; final "go" is a stronger pulse.
        phase = .countdown
        for n in [3, 2, 1] {
            countdownValue = n
            HapticEngine.countdownTick()
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        HapticEngine.countdownGo()

        // Start mic recognition ONLY — no playback. Playing the target audio
        // through the speaker bleeds into the mic, which inflates the score
        // and falsely advances the karaoke highlight. The visual cursor still
        // sweeps based on syncStartedAt so the user has a tempo reference.
        do {
            try live.start(locale: targetLanguage, preferBuiltInMic: true)
        } catch {
            self.error = "STT failed: \(error.localizedDescription)"
            phase = .idle
            return
        }

        // Save the raw mic input to a WAV so the learner can play their
        // attempt back after analysis. AVAudioRecorder runs alongside the
        // AVAudioEngine tap LiveTranscriber sets up; both see the same mic.
        recordingFileURL = (try? recorder.start(quality: .sttOptimal))

        phase = .syncing
        // Countdown just ended → start the clock and karaoke immediately.
        // STT-triggered clock had unacceptable latency (~300ms) since the
        // first word never arrives in time for the highlight to feel
        // in-sync. With the explicit 3-2-1 the user has a clean cue to
        // start exactly when the karaoke does.
        syncStartedAt = Date()
        let cutoffMs = max(2000, targetDurationMs + 1500)
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(cutoffMs) * 1_000_000)
            guard !Task.isCancelled, phase == .syncing else { return }
            finishSync()
        }
    }

    private func finishSync() {
        guard phase == .syncing else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        let finalText = live.stop()
        // Stop the parallel WAV writer; URL is already stored from start().
        _ = recorder.stop()
        prevTranscript = finalText
        phase = .analyzing
        Task { await analyze(finalText: finalText) }
    }

    private func analyze(finalText: String) async {
        let analysis = ShadowEngine.analyze(target: turn.transcript, learner: finalText)
        diffSteps = analysis.steps
        // Learner duration = measured utterance span (first voice → last
        // voice, incl. mid-speech pauses) from the mic energy meter — NOT the
        // wall clock, which includes lead-in silence and the auto-stop tail
        // and systematically inflated the pace ratio. Wall clock stays as the
        // fallback when the meter heard nothing.
        let stats = live.fluencyStats()
        let spokenMs = Int((stats.speakingSeconds + stats.pauseSeconds) * 1000)
        let wallMs = Int((syncStartedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        let learnerDurMs = spokenMs > 0 ? min(spokenMs, wallMs) : wallMs
        lastAttemptDurationMs = learnerDurMs   // surfaces in durationCard

        // The deterministic score + diff are already computed. The Gemini
        // bullets are garnish — a network failure must not throw away the
        // attempt (score, diff, recording) with it.
        var payload: ShadowEngine.Payload?
        do {
            payload = try await GeminiClient.shared.sendJSON(
                system: ShadowEngine.systemPrompt(targetLanguage: targetLanguage),
                messages: [GeminiClient.Message(
                    role: .user,
                    content: ShadowEngine.userMessage(
                        targetText: turn.transcript,
                        learnerText: finalText,
                        targetDurationMs: targetDurationMs,
                        learnerDurationMs: learnerDurMs,
                        diffSteps: analysis.steps
                    )
                )],
                maxTokens: 300
            )
        } catch {
            payload = nil
        }

        feedback = ShadowFeedback(
            pronunciation: payload?.pronunciation
                ?? "Coach comments couldn't load — the score and highlighted words above are still accurate.",
            pacing: payload?.pacing ?? "",
            fix: payload?.fix ?? "",
            matchScore: analysis.score
        )
        phase = .result
        HapticEngine.shadowComplete(score: analysis.score)

        // Persist this attempt so the user can revisit / hear it later —
        // even when the coach bullets failed to generate.
        let attempt = ShadowAttempt(
            turnId: turn.id,
            targetText: turn.transcript,
            learnerTranscript: finalText,
            recordingFilename: recordingFileURL?.lastPathComponent,
            matchScore: analysis.score,
            pronunciation: payload?.pronunciation ?? "",
            pacing: payload?.pacing ?? "",
            fix: payload?.fix ?? ""
        )
        appState.saveShadowAttempt(attempt)
    }

    /// Replace `userWordTimings` from the LATEST segment-level word timings
    /// published by LiveTranscriber. Each `WordTimingInfo.startSeconds` is
    /// audio-time offset within the current recognition segment (NOT wall
    /// clock). To convert to "ms from syncStart":
    ///   absolute = segmentAnchorAt + startSeconds
    ///   ms = (absolute - syncStartedAt) * 1000
    /// SFSpeechRecognizer may revise earlier words as more audio arrives, so
    /// we replace the whole list rather than appending. Effectively the
    /// final state at finishSync reflects what SFSpeechRecognizer believes
    /// best matches the audio — far more accurate than wall-clock delivery.
    private func applyWordTimings(_ new: [LiveTranscriber.WordTimingInfo]) {
        guard phase == .syncing,
              let syncStart = syncStartedAt,
              let anchor = live.segmentAnchorAt else { return }
        let anchorOffsetMs = Int(anchor.timeIntervalSince(syncStart) * 1000)
        userWordTimings = new.map { w in
            UserWordHit(word: w.word, ms: anchorOffsetMs + Int(w.startSeconds * 1000))
        }
    }

    // MARK: - Audio prep

    private func prepareAudio() async {
        guard let voiceId = appState.voiceCloneId else {
            self.error = "No voice clone yet — record yours under Me → Re-record voice."
            return
        }

        // Only accept turn.audioURL if the file is actually there. The Turn
        // outlives the file (reinstall, voice re-record cleanup, etc.), so
        // a non-nil URL doesn't guarantee bytes on disk.
        var url: URL?
        if let stored = turn.audioURL, FileManager.default.fileExists(atPath: stored.path) {
            url = stored
        }
        if url == nil {
            url = TurnAudioStore.shared.url(for: turn.id)
        }
        if url == nil, let phraseURL = PhraseAudioStore.shared.url(text: turn.transcript, voiceId: voiceId) {
            if let data = try? Data(contentsOf: phraseURL),
               let saved = TurnAudioStore.shared.save(data, turnId: turn.id) {
                url = saved
            } else {
                url = phraseURL
            }
        }

        var loadedTimings = TurnAudioStore.shared.timings(for: turn.id)
            ?? PhraseAudioStore.shared.timings(text: turn.transcript, voiceId: voiceId)
            ?? []

        if url == nil || loadedTimings.isEmpty {
            phase = .loadingAudio
            do {
                let (data, newTimings) = try await ElevenLabsClient.shared
                    .synthesizeWithTimestamps(voiceId: voiceId, text: turn.transcript)
                PhraseAudioStore.shared.save(data, text: turn.transcript, voiceId: voiceId, timings: newTimings)
                if let saved = TurnAudioStore.shared.save(data, turnId: turn.id, timings: newTimings) {
                    url = saved
                }
                if !newTimings.isEmpty { loadedTimings = newTimings }
                phase = .idle
            } catch {
                self.error = "Karaoke timings unavailable: \(error.localizedDescription)"
                phase = .idle
                if url == nil { return }
            }
        }

        if !loadedTimings.isEmpty && TurnAudioStore.shared.timings(for: turn.id) == nil {
            TurnAudioStore.shared.saveTimings(loadedTimings, for: turn.id)
        }

        cachedAudioURL = url
        if let url = url {
            targetDurationMs = Self.durationMs(of: url)
        }
        timings = loadedTimings
    }

    private static func durationMs(of url: URL) -> Int {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return Int(player.duration * 1000)
    }
}
