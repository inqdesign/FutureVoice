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
    /// Non-blocking notice when karaoke timings couldn't be synthesized but
    /// cached audio still lets practice continue (e.g. out of credits).
    @State private var timingNote: String?
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
                PaywallView(offerTrial: false)   // out-of-credits entry
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
            if let note = timingNote {
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                Text("Word starts, speed-matched — orange landed off the target's beat.")
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
        // Sheet-like: the card hugs the screen edges (small side inset) with a
        // generous corner radius. No status caption — the mic's own state
        // (idle / red-pulsing / countdown overlay) already says enough.
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        // No outer material — the trimmer's own rounded card is the only
        // container; a second full-width background read as a box-in-a-box.
    }

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
        case .syncing:   return "stop.fill"
        case .analyzing: return "ellipsis"
        case .result:    return "arrow.counterclockwise"
        default:         return "mic.fill"
        }
    }

    private var micHint: String {
        switch phase {
        case .idle:        return practiceRange == nil
            ? "Tap to sync-shadow" : "Tap to shadow the selected phrase"
        case .loadingAudio:return "Loading…"
        case .countdown:   return "Speak when 0 hits"
        case .syncing:     return "Follow the highlight"
        case .analyzing:   return "Comparing…"
        case .result:      return practiceRange == nil
            ? "Tap to try again" : "Tap to shadow the selected phrase"
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

    /// Vocabulary bias for both the live recognizer and the file re-score:
    /// the target line's words plus the whole line as one phrase. STT then
    /// resolves accented pronunciations to the words actually being practiced.
    static func recognitionHints(for target: String) -> [String] {
        var hints = target
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 1 }
        hints.append(target)
        return hints
    }

    private func startSync() async {
        // Stop any loop/preview playback before recording so the speaker audio
        // doesn't bleed into the mic.
        player.stop()
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
            try live.start(locale: targetLanguage, preferBuiltInMic: true,
                           contextualStrings: Self.recognitionHints(for: attemptTargetText))
        } catch {
            self.error = "STT failed: \(error.localizedDescription)"
            phase = .idle
            return
        }

        // Save the raw mic input to a WAV so the learner can play their
        // attempt back after analysis. AVAudioRecorder runs alongside the
        // AVAudioEngine tap LiveTranscriber sets up; both see the same mic.
        recordingFileURL = (try? recorder.start(quality: .sttOptimal))

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
        HapticEngine.countdownGo()
        try? await Task.sleep(nanoseconds: 350_000_000)

        phase = .syncing
        // Countdown just ended → start the clock and karaoke immediately.
        // STT-triggered clock had unacceptable latency (~300ms) since the
        // first word never arrives in time for the highlight to feel
        // in-sync. With the explicit 3-2-1 the user has a clean cue to
        // start exactly when the karaoke does.
        syncStartedAt = Date()
        // Headroom past the target duration: learners start a beat after
        // "go" and speak a touch slower — a tight cutoff truncated final
        // words, which scored as deletions/garbage through no fault of
        // theirs. Tapping stop early is always available.
        let cutoffMs = max(3000, attemptTargetDurationMs + 2500)
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(cutoffMs) * 1_000_000)
            guard !Task.isCancelled, phase == .syncing else { return }
            // Never cut a speaker mid-word: while the mic still hears voice,
            // extend in 200ms steps (up to +4s) and only stop once they've
            // actually gone quiet. The fixed cutoff was truncating slow
            // attempts' tails, which then scored as deletions of words the
            // learner clearly said.
            let hardCap = Date().addingTimeInterval(4)
            while !Task.isCancelled, phase == .syncing, Date() < hardCap,
                  let lastVoiced = live.lastVoicedAt,
                  Date().timeIntervalSince(lastVoiced) < 0.5 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled, phase == .syncing else { return }
            finishSync()
        }
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
                        targetText: attemptTargetText,
                        learnerText: scoredText,
                        targetDurationMs: attemptTargetDurationMs,
                        learnerDurationMs: learnerDurMs,
                        diffSteps: analysis.steps,
                        rhythm: rhythm
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
        PracticeLog.shared.record(.shadow)
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

        let loadedTimings = TurnAudioStore.shared.timings(for: turn.id)
            ?? PhraseAudioStore.shared.timings(text: turn.transcript, voiceId: voiceId)
            ?? []

        // Audio already on disk → make the UI usable IMMEDIATELY. The trimmer
        // and mic work with time-based looping even without word timings, so
        // recovering karaoke timings — a possibly multi-second on-device
        // alignment, or a paid re-synth — must NOT block practice behind a
        // "Loading…" state. It runs in the background; karaoke just lights up
        // if/when the timings land.
        if let ready = url, FileManager.default.fileExists(atPath: ready.path) {
            cachedAudioURL = ready
            targetDurationMs = Self.durationMs(of: ready)
            timings = loadedTimings
            phase = .idle
            if loadedTimings.isEmpty {
                // Cancellable + off the critical path: the UI is already live,
                // and this MUST be cancellable so it doesn't run alongside the
                // mic recognizer.
                recoverTask?.cancel()
                recoverTask = Task { await recoverTimings(url: ready, voiceId: voiceId) }
            }
            return
        }

        // No cached audio at all — synthesizing it IS the blocking step, since
        // nothing is playable until it lands.
        phase = .loadingAudio
        do {
            let (data, newTimings) = try await ElevenLabsClient.shared
                .synthesizeWithTimestamps(voiceId: voiceId, text: turn.transcript)
            PhraseAudioStore.shared.save(data, text: turn.transcript, voiceId: voiceId, timings: newTimings)
            let saved = TurnAudioStore.shared.save(data, turnId: turn.id, timings: newTimings)
            cachedAudioURL = saved
            if let saved { targetDurationMs = Self.durationMs(of: saved) }
            timings = newTimings
            phase = .idle
        } catch {
            outOfCredits = error.isOutOfCredits
            phase = .idle
            self.error = outOfCredits
                ? "You're out of credits — synthesizing this line needs a top-up."
                : "Couldn't load audio for this line: \(error.localizedDescription)"
        }
    }

    /// Recover karaoke word-timings in the BACKGROUND (never blocks the UI):
    /// the free on-device alignment first, then — only if that can't match the
    /// line — a paid re-synth. Any failure just leaves karaoke off; the
    /// trimmer's time-based looping already works.
    private func recoverTimings(url: URL, voiceId: String) async {
        let local = await LocalAlignment.wordTimings(
            audioURL: url, languageCode: targetLanguage, expectedText: turn.transcript)
        if Task.isCancelled { return }
        if !local.isEmpty {
            TurnAudioStore.shared.saveTimings(local, for: turn.id)
            timings = local
            return
        }
        do {
            let (data, newTimings) = try await ElevenLabsClient.shared
                .synthesizeWithTimestamps(voiceId: voiceId, text: turn.transcript)
            PhraseAudioStore.shared.save(data, text: turn.transcript, voiceId: voiceId, timings: newTimings)
            _ = TurnAudioStore.shared.save(data, turnId: turn.id, timings: newTimings)
            if !newTimings.isEmpty { timings = newTimings }
        } catch {
            // The audio already plays; only karaoke is affected. A credit
            // gate gets a quiet inline note, other failures stay silent.
            if error.isOutOfCredits {
                timingNote = "Word timings need credits — karaoke highlighting is off, but you can still loop any part by dragging on the timeline."
            }
        }
    }

    private static func durationMs(of url: URL) -> Int {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return Int(player.duration * 1000)
    }
}
