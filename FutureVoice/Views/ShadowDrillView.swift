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
    /// Separate player for the learner's own attempt recordings. The shared
    /// `player` is the TIMELINE's ground truth — its duration/currentTime
    /// drive the trimmer track and karaoke highlight — so loading a 30s mic
    /// recording into it squished the word band to the left of a mostly-empty
    /// track (the "tail") and made the timeline's play button replay the
    /// attempt instead of the target line.
    @StateObject private var attemptPlayer = AudioPlayer()
    @StateObject private var live = LiveTranscriber()

    @State private var phase: Phase = .idle
    @State private var countdownValue: Int = 0
    @State private var syncStartedAt: Date?
    @State private var userWordTimings: [UserWordHit] = []
    @State private var prevTranscript: String = ""
    /// True when scoring had to use the live partial hypothesis because the
    /// file re-recognition pass failed (usually network) — shown as a
    /// trust-calibrating footnote on the result.
    @State private var usedRoughTranscript = false
    @State private var recordingFileURL: URL?
    @State private var feedback: ShadowFeedback?
    @State private var diffSteps: [ShadowEngine.DiffStep] = []
    /// Word-onset timing comparison for the last attempt — nil whenever the
    /// timing data wasn't trustworthy (see ShadowEngine.analyzeRhythm guards).
    @State private var rhythm: ShadowEngine.RhythmAnalysis?
    @State private var error: String?
    /// The last failure was the 402 credit gate — the error alert then leads
    /// with the paywall instead of a dead-end OK.
    @State private var outOfCredits = false
    @State private var showingPaywall = false
    @State private var targetDurationMs: Int = 0
    @State private var lastAttemptDurationMs: Int = 0
    @State private var cachedAudioURL: URL?
    @State private var timings: [WordTiming] = []
    @State private var autoStopTask: Task<Void, Never>?
    /// Background karaoke-timing recovery (file speech-recognition). Cancelled
    /// before a live mic session starts — two speech recognizers running at
    /// once break the recording (it cut off after the first line).
    @State private var recoverTask: Task<Void, Never>?
    /// Word-index range selected for loop practice, shared between the target
    /// line text and the timeline player (both read/write it).
    @State private var selectedWordRange: ClosedRange<Int>?
    /// First tapped word when building a range on the target line.
    @State private var selectionAnchor: Int?
    /// Practice target frozen at mic start — the selected phrase (or the whole
    /// line) THIS attempt is scored against. Frozen so changing the selection
    /// mid-attempt or after the result can't shift what the diff refers to.
    @State private var activeRange: ClosedRange<Int>?
    @State private var attemptTargetText: String = ""
    @State private var attemptTargetDurationMs: Int = 0
    /// One-time "which mic?" question (see `MicPreferenceStore`). The take
    /// waits on the answer, so the choice applies to the very first attempt
    /// rather than to the one after it.
    @State private var askingMicChoice = false
    @State private var micChoiceContinuation: CheckedContinuation<Void, Never>?

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
                    rhythmCard
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
                if outOfCredits {
                    Button("See plans") { error = nil; showingPaywall = true }
                }
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $askingMicChoice, onDismiss: resumeAfterMicChoice) {
                MicChoiceSheet { _ in }
            }
            .onChange(of: live.currentWordTimings) { _, new in
                applyWordTimings(new)
            }
            .task { await prepareAudio() }
        }
    }

    // MARK: - Sections

    /// True when the trimmer/transport row is on screen (idle or result with
    /// cached audio) — in those phases the mic control rides inside that row
    /// rather than as a standalone block.
    private var timelineAvailable: Bool {
        guard phase == .idle || phase == .result, let url = cachedAudioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Scrub / select-a-phrase / loop player. Lives in the unified bottom bar
    /// next to the speak button; hidden while recording so it can't fight the
    /// sync session.
    @ViewBuilder
    private var timelinePlayer: some View {
        if timelineAvailable, let url = cachedAudioURL {
            ShadowTimelinePlayer(
                audioURL: url,
                timings: timings,
                selectedWordRange: $selectedWordRange,
                player: player
            ) {
                // Inline in the transport row, but still the primary action —
                // bigger than the 44pt glyph buttons around it so it clearly
                // leads, without owning a whole block below.
                micButton(diameter: 60)
            }
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
    /// Re-tapping the lone selected word CLEARS the selection — the way back
    /// to whole-line practice must be as easy as the way in.
    private func tapWord(_ i: Int) {
        guard phase == .idle || phase == .result else { return }
        if selectedWordRange == i...i {
            selectedWordRange = nil
            selectionAnchor = nil
            return
        }
        if selectedWordRange == nil { selectionAnchor = nil }
        if let anchor = selectionAnchor {
            selectedWordRange = min(anchor, i)...max(anchor, i)
            selectionAnchor = nil
        } else {
            selectionAnchor = i
            selectedWordRange = i...i
        }
    }

    // MARK: - Practice target (whole line vs selected phrase)

    /// The selection as a scoring range — nil when nothing is selected, the
    /// selection is stale against a reloaded timing set, or it spans the whole
    /// line (identical to whole-line practice).
    private var practiceRange: ClosedRange<Int>? {
        guard let r = selectedWordRange, !timings.isEmpty,
              r.upperBound < timings.count,
              r != 0...(timings.count - 1) else { return nil }
        return r
    }

    private var practiceText: String {
        guard let r = practiceRange else { return turn.transcript }
        return timings[r].map(\.word).joined(separator: " ")
    }

    private var practiceDurationMs: Int {
        guard let r = practiceRange else { return targetDurationMs }
        return max(0, timings[r.upperBound].endMs - timings[r.lowerBound].startMs)
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
            // Phrase attempts: diff indices are relative to the practiced
            // range; words outside it weren't attempted → stay quiet.
            if let r = activeRange, !r.contains(i) { return .secondary }
            let diffIndex = i - (activeRange?.lowerBound ?? 0)
            switch alignment.targetOp[diffIndex] {
            case .sub:   return .orange      // user said a different word here
            case .del:   return .secondary   // user skipped this word
            case .match: return .primary
            default:     return .primary
            }
        }

        if phase == .syncing, let start = syncStartedAt {
            // Phrase attempts: the sync clock's zero IS the phrase's first
            // word, so shift elapsed time to the phrase's position in the
            // line; the rest of the line stays quiet.
            if let r = activeRange {
                guard r.contains(i) else { return .secondary }
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                return positionalColor(wt: wt, nowMs: elapsed + timings[r.lowerBound].startMs)
            }
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
        if !diffSteps.isEmpty, attemptTargetDurationMs > 0 {
            let targetSec = Double(attemptTargetDurationMs) / 1000.0
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

    // MARK: - Rhythm card

    /// Two parallel word-onset timelines — target rhythm on top, the
    /// learner's (pace-normalized) below. Because both rows are re-zeroed
    /// and the learner row is scaled to the same span, a vertical offset
    /// between a pair of bars reads directly as "you were early/late on this
    /// word", independent of overall speed (which the duration card owns).
    @ViewBuilder
    private var rhythmCard: some View {
        if let r = rhythm, !diffSteps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rhythm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("\(r.score)", systemImage: "metronome")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(scoreColor(r.score))
                }
                VStack(spacing: 6) {
                    rhythmRow(label: "Target", analysis: r, learner: false)
                    rhythmRow(label: "You", analysis: r, learner: true)
                }
                Text(explain("Word starts, speed-matched — orange landed off the target's beat."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rhythmRow(
        label: String,
        analysis: ShadowEngine.RhythmAnalysis,
        learner: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                let span = CGFloat(max(1, analysis.targetSpanMs))
                ZStack(alignment: .topLeading) {
                    ForEach(analysis.words, id: \.self) { w in
                        let onsetMs = learner ? w.learnerOnsetMs : w.targetOnsetMs
                        let durMs = learner ? w.learnerDurationMs : w.targetDurationMs
                        let x = min(1, max(0, CGFloat(onsetMs) / span)) * geo.size.width
                        let width = min(geo.size.width - x,
                                        max(4, CGFloat(durMs) / span * geo.size.width))
                        Capsule()
                            .fill(learner
                                  ? rhythmColor(deviationMs: w.deviationMs)
                                  : Color.secondary.opacity(0.35))
                            .frame(width: width, height: 8)
                            .offset(x: x)
                    }
                }
            }
            .frame(height: 8)
        }
    }

    private func rhythmColor(deviationMs: Int) -> Color {
        switch ShadowEngine.rhythmGrade(deviationMs: deviationMs) {
        case 2:  return .green
        case 1:  return .orange
        default: return .red
        }
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
        playAttempt(data)
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
        playAttempt(data)
    }

    private var diffSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                // The colored line is the TARGET scored against the attempt —
                // it was previously titled "What I heard", which read as a
                // transcript and made honest recognition feel wrong.
                Text("Your match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                diffText.font(.body)
                if !prevTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("What I heard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text(prevTranscript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if usedRoughTranscript {
                    Label("Rough transcript — the final recognition pass didn't finish (network). The score may be off this time.",
                          systemImage: "wifi.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
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
            // In idle/result the mic rides INSIDE the trimmer's transport row
            // (see timelinePlayer). Only when that row is absent — recording,
            // counting down, analyzing — does the mic stand alone at full size.
            if timelineAvailable {
                timelinePlayer
            } else {
                micButton(diameter: 64)
            }
        }
        // Feedback scrolls UNDER this panel and the trimmer card's edge used to
        // slice the last line clean in half. Feather the seam so a line
        // dissolves on its way down, the way it does under the tab bar
        // elsewhere. A wash of the PAGE colour, not `.bar`: this page is plain
        // `systemBackground`, where a material would sit as a visible grey band.
        .overlay(alignment: .top) {
            ScrollEdgeFeather(fill: Color(.systemBackground), ramp: Self.feather)
                .frame(height: Self.feather)
                .offset(y: -Self.feather)
                .allowsHitTesting(false)
        }
        // Sheet-like: the card hugs the screen edges (small side inset) with a
        // generous corner radius. No status caption — the mic's own state
        // (idle / red-pulsing / countdown overlay) already says enough. No
        // bottom padding — the panel sits as low as the home indicator allows.
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        // Still no outer MATERIAL — the trimmer's own rounded card is the only
        // container, and a second full-width one read as a box-in-a-box. This
        // is the page colour continuing through the home-indicator strip, so
        // content can't scroll past the panel into the bottom corner.
        .background { Color(.systemBackground).ignoresSafeArea(edges: .bottom) }
    }

    /// Height of the dissolve above the panel.
    private static let feather: CGFloat = 56

    /// The primary record/redo control. `diameter` lets it be full-size when
    /// standalone (64) or compact inside the transport row (52); the glyph and
    /// pulse scale with the phase either way.
    private func micButton(diameter: CGFloat) -> some View {
        Button {
            Task { await handleSyncTap() }
        } label: {
            ZStack {
                Circle()
                    .fill(.tint)
                    .frame(width: diameter, height: diameter)
                    .opacity(syncEnabled ? 1.0 : 0.4)
                    .scaleEffect(phase == .syncing ? 1.06 : 1.0)
                    .animation(
                        phase == .syncing
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: phase
                    )
                Image(systemName: micSymbol)
                    .font(.system(size: diameter * 0.375, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
            }
        }
        .buttonStyle(.plain)
        .tint(phase == .syncing ? .red : .accentColor)
        .disabled(!syncEnabled)
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
        // An X, not a stop square: mid-attempt this button DISCARDS the take
        // (see handleSyncTap). A stop glyph would promise "end and score it",
        // which is the auto-stop's job and the opposite of what a tap does.
        case .syncing:   return "xmark"
        case .analyzing: return "ellipsis"
        case .result:    return "arrow.counterclockwise"
        default:         return "mic.fill"
        }
    }

    /// `chrome(…)`, not bare literals: this is a `String`-typed switch, so a
    /// plain literal never sees the root's `\.locale` and stayed English in
    /// every language. Exactly the case `chrome` exists for.
    private var micHint: String {
        switch phase {
        case .idle:        return practiceRange == nil
            ? chrome("Tap to sync-shadow") : chrome("Tap to shadow the selected phrase")
        case .loadingAudio:return chrome("Loading…")
        case .countdown:   return chrome("Speak when 0 hits")
        // Recording ends by itself, so the only thing left to say about the
        // button is what it now does — discard this take.
        case .syncing:     return chrome("Follow the highlight · tap to cancel")
        case .analyzing:   return chrome("Comparing…")
        case .result:      return practiceRange == nil
            ? chrome("Tap to try again") : chrome("Tap to shadow the selected phrase")
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
            attemptPlayer.stop()
            try player.play(data, source: "shadow", forceSessionReset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Attempt recordings go through `attemptPlayer`, never the shared
    /// `player` (see its declaration for why). Target playback is paused
    /// first so the two can't overlap.
    private func playAttempt(_ data: Data) {
        do {
            player.pause()
            try attemptPlayer.play(data, source: "shadow", forceSessionReset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleSyncTap() async {
        switch phase {
        case .idle, .result:
            await startSync()
        case .syncing:
            // CANCEL, not stop (2026-08-15). Ending an attempt is the
            // auto-stop's job — it waits out the line's own length and then
            // 1.5s of real quiet, so a learner who is finished never has to
            // press anything. That leaves the button with exactly one useful
            // meaning mid-attempt: "this one went wrong, throw it away."
            // Scoring a botched take isn't just noise in the history — below
            // 90 it also spends a Gemini coach call on an attempt the learner
            // has already disowned.
            cancelSync()
        default:
            break
        }
    }

    /// Vocabulary bias for both the live recognizer and the file re-score:
    /// the target line's words plus the whole line as one phrase. STT then
    /// resolves accented pronunciations to the words actually being practiced.
    /// `SFSpeechRecognitionRequest.contextualStrings` is documented as "limit
    /// to around 100" — past that the recognizer degrades instead of helping,
    /// and the list here grows with the LINE, so a long shadow target blew
    /// straight through it. Whole line first (the most informative hint),
    /// then unique words until the budget runs out.
    static let maxRecognitionHints = 100

    static func recognitionHints(for target: String) -> [String] {
        var hints = [target]
        var seen = Set<String>()
        for word in target.components(separatedBy: .whitespacesAndNewlines) {
            let w = word.trimmingCharacters(in: .punctuationCharacters)
            guard w.count > 1, seen.insert(w.lowercased()).inserted else { continue }
            hints.append(w)
            if hints.count >= maxRecognitionHints { break }
        }
        return hints
    }

    /// Suspends until the learner answers the mic sheet, and does nothing at
    /// all once they have (or with no Bluetooth device connected). `onDismiss`
    /// is what resumes, so either button — and any future dismissal path —
    /// lands in exactly one place.
    private func askMicChoiceIfNeeded() async {
        guard MicPreferenceStore.shouldAsk() else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            micChoiceContinuation = cont
            askingMicChoice = true
        }
    }

    private func resumeAfterMicChoice() {
        micChoiceContinuation?.resume()
        micChoiceContinuation = nil
    }

    private func startSync() async {
        // Stop any loop/preview playback before recording so the speaker audio
        // doesn't bleed into the mic.
        player.stop()
        attemptPlayer.stop()
        // Kill the background timing-recovery recognizer FIRST — a second
        // speech recognizer running against the file collides with the live
        // mic recognizer and truncates the recording after the first line.
        recoverTask?.cancel()
        recoverTask = nil
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

        // First mic use with earphones connected: ask once which mic records
        // (`MicPreferenceStore`). Right after the permission prompts so the
        // questions don't stack, and BEFORE the countdown so the answer
        // governs this take. Returns immediately every other time.
        await askMicChoiceIfNeeded()

        // Freeze what this attempt practices: the selected phrase, or the
        // whole line. Everything downstream — STT bias, scoring, coach
        // bullets, the saved attempt — uses this, not turn.transcript.
        activeRange = practiceRange
        attemptTargetText = practiceText
        attemptTargetDurationMs = practiceDurationMs

        // Reset state
        feedback = nil
        diffSteps = []
        rhythm = nil
        userWordTimings = []
        prevTranscript = ""

        // Start mic recognition BEFORE the countdown — no playback. Playing
        // the target audio through the speaker bleeds into the mic, which
        // inflates the score and falsely advances the karaoke highlight.
        // Mic-first matters: setup used to run AFTER the "go" beat, so a
        // learner who started speaking ON the beat had their first word(s)
        // missing from the scoring file and marked as deletions through no
        // fault of their own. The countdown's lead-in silence is harmless —
        // recognition skips it and rhythm timing is relative to first voice.
        do {
            // Bias recognition toward the exact line being shadowed — we know
            // what the learner is TRYING to say, so accented pronunciations
            // resolve to the right words instead of soundalikes.
            // measurementMode: false — `.measurement` disables iOS output
            // processing, which made the karaoke line (and everything after)
            // noticeably QUIETER than a Talk call. Conversation already opts
            // out for the same reason; recognition runs fine in `.default`
            // (it's the live call's own STT mode).
            //
            // preferBuiltInMic (2026-08-15): the LEARNER's answer, not ours.
            // This hard-forced the built-in mic on the theory that scoring
            // needs the cleanest input; that theory ignores WHERE the mic is.
            // A phone on the desk or in a pocket is metres from the mouth
            // while the earphone mic sits at it, so forcing built-in traded a
            // wider band for a far worse signal — and the learner reads the
            // resulting low score as the app misjudging them. Which of the two
            // is true depends on where the phone is, which only they can see,
            // so `MicPreferenceStore` asks once and remembers. HFP output
            // narrowing costs nothing here: nothing plays while the mic is hot
            // (see above), and both the target line and the attempt play back
            // through a fresh `playbackOptions` session.
            //
            // voiceProcessing: true (2026-08-14) — this ran on the RAW mic
            // until now, on the reasoning that shadow scores deterministically
            // off raw levels. Nothing here actually does: the match score is a
            // token-level Levenshtein over the TRANSCRIPT, the rhythm card is
            // built from STT word TIMINGS, and the only real raw-level
            // analysis in the app (`AudioSampleQuality`) is voice-clone-only.
            // Meanwhile the room was costing this surface three times over —
            // noise into the recognizer (which the score is computed from),
            // noise counted as voiced time (which inflates the pace card), and
            // a noise floor high enough that `lastVoicedAt` never went stale,
            // so the auto-stop below could only ever fire on its hard ceiling.
            // Talk made exactly this trade earlier in 2026-08.
            try live.start(locale: targetLanguage,
                           preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                           measurementMode: false,
                           contextualStrings: Self.recognitionHints(for: attemptTargetText),
                           voiceProcessing: true)
        } catch {
            self.error = "STT failed: \(error.localizedDescription)"
            phase = .idle
            return
        }

        // Save the raw mic input to a WAV so the learner can play their
        // attempt back after analysis. AVAudioRecorder runs alongside the
        // AVAudioEngine tap LiveTranscriber sets up; both see the same mic.
        //
        // PREPARED here, STARTED on the beat. This file is both the audio
        // `analyze` re-recognizes to score the attempt and the take the
        // learner plays back, and it used to open right here — so 2.4s of
        // countdown sat in front of both. Session + file setup is the slow
        // part and stays here; `record()` on a prepared recorder is not.
        recordingFileURL = (try? recorder.prepare(quality: .sttOptimal))

        // Countdown 3-2-1-0 with haptic ticks; "0" IS the go beat so the
        // start lands on a visible number instead of an unmarked pause after
        // "1" (which made the exact start moment hard to catch). The mic is
        // already hot, so speaking right on (or slightly before) the beat is
        // fully captured.
        phase = .countdown
        for n in [3, 2, 1] {
            countdownValue = n
            HapticEngine.countdownTick()
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        countdownValue = 0
        // Capture starts HERE — on "0", the beat the learner is cued by, not
        // back at setup. The 350 ms below is deliberate lead-in: "0" appears
        // before the karaoke does, so anyone who starts speaking the instant
        // they see it is inside the file. Everything earlier — the 3-2-1, a
        // throat-clear, a rehearsal — never reaches the scored audio or the
        // take they play back, because it was never recorded.
        try? recorder.beginPrepared()
        HapticEngine.countdownGo()
        try? await Task.sleep(nanoseconds: 350_000_000)

        phase = .syncing
        // Countdown just ended → start the clock and karaoke immediately.
        // STT-triggered clock had unacceptable latency (~300ms) since the
        // first word never arrives in time for the highlight to feel
        // in-sync. With the explicit 3-2-1 the user has a clean cue to
        // start exactly when the karaoke does.
        syncStartedAt = Date()
        // A 0 here means the duration lookup failed (unreadable container,
        // audio still landing) — and the old `max(3000, 0 + 2500)` silently
        // turned that into a THREE-SECOND cap on every line, however long.
        // Fall back to the text's own length instead.
        let targetMs = attemptTargetDurationMs > 0
            ? attemptTargetDurationMs
            : Self.durationFromText(attemptTargetText)
        // Headroom past the target duration. It has to SCALE: a learner
        // shadowing runs slower than the model line by a percentage, not by a
        // constant, so the flat +2.5s that comfortably covered a 3s line was
        // nowhere near enough on a 20s one — long attempts got cut off
        // mid-sentence. Tapping stop early is always available.
        let ceilingMs = Self.attemptCutoffMs(targetMs: targetMs)
        let earliestMs = max(1000, targetMs)
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            // Nothing can end the attempt before the line's OWN length — the
            // learner can't be finished sooner, so a pause before that is
            // always mid-attempt, never the end.
            try? await Task.sleep(nanoseconds: UInt64(earliestMs) * 1_000_000)
            guard !Task.isCancelled, phase == .syncing else { return }
            // Past that, stop as soon as they have genuinely gone quiet, and
            // never before. "Quiet" is 1.5s, not 0.5s — a mid-sentence BREATH
            // runs 0.5–1.5s (the figure Talk's endpointer is built on), so the
            // old threshold read an ordinary breath as "finished". On a long
            // line, where breaths are unavoidable, that ended the recording in
            // the middle of the sentence every time.
            let hardStop = Date().addingTimeInterval(Double(ceilingMs - earliestMs) / 1000)
            while !Task.isCancelled, phase == .syncing, Date() < hardStop {
                guard let lastVoiced = live.lastVoicedAt else { break }
                if Date().timeIntervalSince(lastVoiced) >= Self.stillSpeakingSeconds { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled, phase == .syncing else { return }
            finishSync()
        }
    }

    /// Abandon the take: no scoring, no coach call, nothing written to
    /// history, and the WAV is deleted rather than left to accumulate in
    /// Documents under a filename no attempt references.
    ///
    /// Deliberately synchronous and complete — a cancel that leaves the
    /// recognizer running would keep the mic hot and let a late final result
    /// arrive into the next attempt.
    private func cancelSync() {
        guard phase == .syncing else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        _ = live.stop()
        _ = recorder.stop()
        if let url = recordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileURL = nil
        // Everything the attempt would have populated, back to pre-attempt —
        // otherwise a previous result's diff/rhythm sits under an idle mic.
        syncStartedAt = nil
        userWordTimings = []
        prevTranscript = ""
        activeRange = nil
        feedback = nil
        diffSteps = []
        rhythm = nil
        phase = .idle
        HapticEngine.selection()
        Telemetry.log("shadow_attempt_cancelled")
    }

    private func finishSync() {
        guard phase == .syncing else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        phase = .analyzing
        Task { @MainActor in
            // Tail grace: a stop tap usually lands mid-final-syllable — give
            // the recorder 300ms so the last word's tail reaches the file the
            // scoring pass reads (a clipped tail reads as a deletion).
            try? await Task.sleep(nanoseconds: 300_000_000)
            let finalText = live.stop()
            // Stop the parallel WAV writer; URL is already stored from start().
            _ = recorder.stop()
            prevTranscript = finalText
            await analyze(finalText: finalText)
        }
    }

    private func analyze(finalText: String) async {
        // The live transcript is the recognizer's last PARTIAL hypothesis —
        // stop() can't wait for the final pass, so it's systematically worse
        // than what the learner actually said (soundalike words, truncated
        // tails). We have the full attempt on disk: re-run recognition on the
        // file, final result only, biased toward the target line. Falls back
        // to the live text when the file pass fails (network, timeout).
        var scoredText = finalText
        var learnerTimings: [WordTiming] = []
        usedRoughTranscript = true
        if let url = recordingFileURL {
            let rescored = await SpeechTranscriber.transcribeForScoring(
                audioURL: url,
                languageCode: targetLanguage,
                contextualStrings: Self.recognitionHints(for: attemptTargetText)
            )
            if let rescored, !rescored.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // No pre-roll to strip: the file starts on the go beat. Its
                // only lead-in is the deliberate 350ms that catches a learner
                // who speaks the moment "0" appears — that IS the attempt.
                scoredText = rescored.text
                prevTranscript = rescored.text
                learnerTimings = rescored.wordTimings
                usedRoughTranscript = false
            }
        }
        // Scoring fell back to the live PARTIAL hypothesis — systematically
        // worse than the file pass. Surface it in the result UI and count it,
        // so "the score felt wrong" days are checkable against data.
        if usedRoughTranscript {
            Telemetry.log("shadow_rescore_failed")
        }

        let analysis = ShadowEngine.analyze(target: attemptTargetText, learner: scoredText,
                                            language: targetLanguage)
        diffSteps = analysis.steps

        // Rhythm: pair the diff's matched slots with the target's word map
        // and the learner's file-recognition timestamps. Every guard lives in
        // analyzeRhythm — a nil here just means the card stays hidden.
        let targetSlice = activeRange.map { Array(timings[$0]) } ?? timings
        rhythm = ShadowEngine.analyzeRhythm(
            steps: analysis.steps,
            targetTimings: targetSlice,
            learnerTimings: learnerTimings
        )
        // Learner duration = measured utterance span (first voice → last
        // voice, incl. mid-speech pauses) — NOT the wall clock, which includes
        // lead-in silence and the auto-stop tail and systematically inflated
        // the pace ratio.
        //
        // The SCORED words' own span is the best source: it begins at the
        // first word that survived the pre-beat cut, so it cannot carry
        // countdown speech. The energy meter can — it has been running since
        // before the 3-2-1 — so it drops to second, ahead of the wall clock.
        let stats = live.fluencyStats()
        let spokenMs = Int((stats.speakingSeconds + stats.pauseSeconds) * 1000)
        let wallMs = Int((syncStartedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        let scoredSpanMs = learnerTimings.first.map { first in
            max(0, (learnerTimings.last?.endMs ?? first.endMs) - first.startMs)
        } ?? 0
        let learnerDurMs = scoredSpanMs > 0
            ? scoredSpanMs
            : (spokenMs > 0 ? min(spokenMs, wallMs) : wallMs)
        lastAttemptDurationMs = learnerDurMs   // surfaces in durationCard

        // The deterministic score + diff are already computed. The Gemini
        // bullets are garnish — a network failure must not throw away the
        // attempt (score, diff, recording) with it.
        //
        // Coach bullets only when there's something to coach: at ≥90 the
        // diff highlights already tell the story, and heavy shadowers repeat
        // lines many times — charging a call per near-perfect rep added cost
        // without adding signal.
        var payload: ShadowEngine.Payload?
        if analysis.score < 90 {
            do {
                payload = try await GeminiClient.shared.sendJSON(
                    system: ShadowEngine.systemPrompt(targetLanguage: targetLanguage,
                                                      nativeLanguage: appState.nativeLanguage),
                    messages: [GeminiClient.Message(
                        role: .user,
                        content: ShadowEngine.userMessage(
                            targetText: attemptTargetText,
                            learnerText: scoredText,
                            targetDurationMs: attemptTargetDurationMs,
                            learnerDurationMs: learnerDurMs,
                            diffSteps: analysis.steps,
                            rhythm: rhythm
                        )
                    )],
                    // Three native-language bullets — cheap, but 300 left no
                    // room for thinking, and a truncation drops the feedback
                    // entirely (payload = nil) leaving a bare score.
                    maxTokens: 1024,
                    purpose: "shadow"
                )
            } catch {
                payload = nil
            }
        }

        feedback = ShadowFeedback(
            pronunciation: payload?.pronunciation
                ?? (analysis.score >= 90
                    ? "Nailed it — matched the line almost word for word."
                    : "Coach comments couldn't load — the score and highlighted words above are still accurate."),
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
            targetText: attemptTargetText,
            learnerTranscript: scoredText,
            recordingFilename: recordingFileURL?.lastPathComponent,
            matchScore: analysis.score,
            rhythmScore: rhythm?.score,
            pronunciation: payload?.pronunciation ?? "",
            pacing: payload?.pacing ?? "",
            fix: payload?.fix ?? ""
        )
        appState.saveShadowAttempt(attempt)
        // A recorded take IS the practice — nothing else to finish.
        PracticeLog.shared.record(.shadow, finished: true)
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
        #if DEBUG
        // Screenshot capture: synthesize evenly-spaced karaoke timings locally
        // and skip the voice-clone/network path so the timeline renders offline.
        if DebugCapture.captureShadow {
            let words = turn.transcript.split(separator: " ").map(String.init)
            let per = 380
            timings = words.enumerated().map { i, w in
                WordTiming(word: w, startMs: i * per, endMs: (i + 1) * per - 60)
            }
            targetDurationMs = words.count * per
            if words.count >= 5 { selectedWordRange = 2...4 }   // show a loop region
            phase = .idle
            return
        }
        #endif
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

        var storedTimings = TurnAudioStore.shared.timings(for: turn.id)
            ?? PhraseAudioStore.shared.timings(text: turn.transcript, voiceId: voiceId)
            ?? []
        // Earlier builds cached ElevenLabs' NORMALIZED alignment, whose words
        // are a romanization of non-Latin text — Korean lines came back as
        // "geureomyeon". Those caches are still on disk, and these words are
        // what the learner reads, so refuse any set that doesn't spell out the
        // line; the estimate + free local alignment rebuild it in real script.
        if !ElevenLabsClient.alignmentMatches(text: turn.transcript, timings: storedTimings) {
            storedTimings = []
        }

        // Audio already on disk → make the UI usable IMMEDIATELY, and karaoke
        // ALWAYS lights up: real timings when stored, otherwise an instant
        // duration-proportional estimate while the free on-device alignment
        // runs in the background. Audio that was already synthesized is NEVER
        // re-billed for shadowing — timings come from stored data, local
        // alignment, or the estimate; there is no paid recovery path.
        if let ready = url, FileManager.default.fileExists(atPath: ready.path) {
            cachedAudioURL = ready
            targetDurationMs = Self.durationMs(of: ready)
            timings = Self.fits(storedTimings, durationMs: targetDurationMs) ? storedTimings : []
            phase = .idle
            if timings.isEmpty {
                timings = Self.estimatedTimings(for: turn.transcript,
                                                durationMs: targetDurationMs)
                // Cancellable + off the critical path: the UI is already live,
                // and this MUST be cancellable so it doesn't run alongside the
                // mic recognizer.
                recoverTask?.cancel()
                recoverTask = Task { await recoverTimings(url: ready, voiceId: voiceId) }
            }
            return
        }

        // No cached audio at all — synthesizing it IS the blocking step, since
        // nothing is playable until it lands. This is the FIRST synthesis of
        // this audio (nothing existed to reuse), so it's the one place a
        // shadow open may bill — and it fetches timings in the same call.
        phase = .loadingAudio
        do {
            let (data, newTimings) = try await ElevenLabsClient.shared
                .synthesizeWithTimestamps(voiceId: voiceId, text: turn.transcript, purpose: "shadow")
            PhraseAudioStore.shared.save(data, text: turn.transcript, voiceId: voiceId, timings: newTimings)
            let saved = TurnAudioStore.shared.save(data, turnId: turn.id, timings: newTimings)
            cachedAudioURL = saved
            if let saved { targetDurationMs = Self.durationMs(of: saved) }
            timings = newTimings.isEmpty
                ? Self.estimatedTimings(for: turn.transcript, durationMs: targetDurationMs)
                : newTimings
            phase = .idle
        } catch {
            outOfCredits = error.isOutOfCredits
            phase = .idle
            self.error = outOfCredits
                ? "You're out of credits — synthesizing this line needs a top-up."
                : "Couldn't load audio for this line: \(error.localizedDescription)"
        }
    }

    /// Upgrade karaoke word-timings in the BACKGROUND (never blocks the UI)
    /// via the FREE on-device alignment. On success the real timings replace
    /// the duration-proportional estimate and persist; on failure the estimate
    /// simply stays — estimates are deliberately NOT persisted so alignment
    /// gets another free try on the next open. This path must never call
    /// ElevenLabs: re-billing audio the user already paid for, just to
    /// recover timings, is what caused runaway duplicate generations.
    private func recoverTimings(url: URL, voiceId: String) async {
        let local = await LocalAlignment.wordTimings(
            audioURL: url, languageCode: targetLanguage, expectedText: turn.transcript,
            durationMs: targetDurationMs)
        if Task.isCancelled || local.isEmpty { return }
        // The SAME gate the load path applies. Persisting a timeline that
        // reload would reject is what made every open re-run this 15s
        // recognition and show the estimate in the meantime — the write side
        // has to agree with the read side or the cache never converges.
        guard Self.fits(local, durationMs: targetDurationMs) else { return }
        TurnAudioStore.shared.saveTimings(local, for: turn.id)
        timings = local
    }

    /// A timeline built from THIS audio can never end after the file does, and
    /// legitimately ends BEFORE it. Undershoot must be tolerated: the smallest
    /// unit that must cover the file is 1 - `minTimingCoverage`.
    static let minTimingCoverage = 0.6

    /// Do these timings belong to THIS recording?
    ///
    /// Until now Talk stored timings fetched from a SECOND ElevenLabs render
    /// of the same sentence. TTS isn't deterministic, so those word onsets
    /// describe audio the learner never hears — the highlight ran ahead of or
    /// behind the voice, drifting further the longer the line. Those caches
    /// are still on disk, and this is what keeps them out.
    ///
    /// It used to reject on `abs(last - durationMs) > max(300ms, 12%)`, which
    /// measured the wrong thing (2026-08-14). `LocalAlignment.fill` ends its
    /// timeline at the last WORD, not the last sample, so every alignment this
    /// app produces is legitimately shorter than the file by whatever silent
    /// tail the render carries. That symmetric test threw those away — and
    /// since `recoverTimings` persisted them without the same check, each open
    /// went: align → store → reject on reload → fall back to the estimate →
    /// re-align, forever. The learner saw the ESTIMATE, which spreads the words
    /// across the full duration INCLUDING the silent tail, so the highlight
    /// trailed the voice and the timeline outran the speech.
    ///
    /// Overshoot is the honest tell: words cannot end after the audio does, so
    /// only a foreign take can do it. Undershoot is bounded by coverage alone.
    static func fits(_ timings: [WordTiming], durationMs: Int) -> Bool {
        guard !timings.isEmpty else { return false }
        guard durationMs > 0, let last = timings.last?.endMs else { return true }
        let tolerance = max(300, Int(Double(durationMs) * 0.12))
        if last > durationMs + tolerance { return false }
        return Double(last) >= Double(durationMs) * minTimingCoverage
    }

    /// Karaoke fallback when no real alignment exists yet: spread the audio
    /// duration across the words proportionally to their character counts.
    /// Approximate, but it keeps the highlight moving with the audio — the
    /// product rule is that karaoke always works, at zero synthesis cost.
    static func estimatedTimings(for text: String, durationMs: Int) -> [WordTiming] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, durationMs > 0 else { return [] }
        let totalChars = words.reduce(0) { $0 + max($1.count, 1) }
        let msPerChar = Double(durationMs) / Double(totalChars)
        var cursor = 0.0
        return words.map { w in
            let start = cursor
            cursor += msPerChar * Double(max(w.count, 1))
            // Small trailing gap so adjacent highlights read as distinct words.
            return WordTiming(word: w, startMs: Int(start),
                              endMs: max(Int(start) + 1, Int(cursor) - 20))
        }
    }

    /// How much longer than the model line a learner's own attempt runs. They
    /// hesitate, re-start words and articulate deliberately, and all of that
    /// grows WITH the line — hence a multiplier rather than a constant.
    static let slowLearnerFactor = 1.5

    /// Silence that means "they've stopped", not "they took a breath".
    /// Matches the range Talk's endpointer is built on (breaths run 0.5–1.5s).
    static let stillSpeakingSeconds: TimeInterval = 1.5

    /// Absolute ceiling on one attempt, given the model line's length. The
    /// attempt normally ends before this, the moment the learner goes quiet;
    /// this only catches a room noisy enough that they never read as quiet.
    static func attemptCutoffMs(targetMs: Int) -> Int {
        max(3000, Int(Double(targetMs) * slowLearnerFactor) + 2500)
    }

    /// Rough spoken length of a line, for when the real audio duration isn't
    /// available. Only ever used to size a SAFETY cutoff, so it errs long.
    static func durationFromText(_ text: String) -> Int {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return max(6000, words * 400)
    }

    private static func durationMs(of url: URL) -> Int {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return Int(player.duration * 1000)
    }
}
