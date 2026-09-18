import AVFoundation
import SwiftUI

/// Sync-mode shadow practice — karaoke for speech.
///
/// Tap the mic → 3-2-1 countdown → the target line's words light up on the
/// original rhythm while the learner says it along (nothing plays — speaker
/// audio would bleed into the mic). The take is then read by
/// `ShadowTranscriber`, diffed against the line (`ShadowEngine`), its beat
/// drawn as dots under the words, and Gemini writes three coaching bullets
/// anchored to that diff. Words are tappable: two taps pick a phrase to loop
/// and shadow on its own.
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
    @State private var prevTranscript: String = ""
    /// The take had no speech in it — shown as a line under the target, not
    /// scored: a silent take is not a 0, it is nothing, and it must not be
    /// saved, counted as practice or handed to the coach.
    @State private var heardNothing = false
    /// True when scoring had to use the live partial hypothesis because the
    /// file re-recognition pass failed (usually network) — shown as a
    /// trust-calibrating footnote on the result.
    @State private var usedRoughTranscript = false
    @State private var recordingFileURL: URL?
    @State private var feedback: ShadowFeedback?
    /// The coach call is still writing its bullets for the attempt on
    /// screen. The score, diff and recording are already up — the result
    /// no longer waits for the garnish.
    @State private var coachPending = false
    /// The attempt the result screen is showing. A coach reply that lands
    /// after the learner has started another take updates that attempt's
    /// RECORD and nothing on screen.
    @State private var shownAttemptId: UUID?
    @State private var diffSteps: [ShadowEngine.DiffStep] = []
    /// Word-onset timing comparison for the last attempt — nil whenever the
    /// timing data wasn't trustworthy (see ShadowEngine.analyzeRhythm guards).
    @State private var rhythm: ShadowEngine.RhythmAnalysis?
    /// `diffSteps` and `rhythm` folded onto word indices, computed ONCE when
    /// a result lands (`refreshWordVerdicts`). The karaoke line redraws at
    /// 30 Hz whenever the target plays, and both of these ran the tokenizer
    /// (regex, NumberFormatter) per word per frame when they were computed
    /// in the body.
    @State private var wordOps = PositionAlignment()
    @State private var wordBeats: [Int: ShadowEngine.RhythmWord] = [:]
    /// Word onsets of the SCORED attempt, kept past `analyze` so the duet can
    /// line the take up on its first word instead of on the file's start.
    @State private var attemptWordTimings: [WordTiming] = []
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
    /// The free target alignment was re-run once after a take this visit.
    /// One re-run is the whole benefit; one per attempt is a recognizer
    /// winding down under the next take's scoring pass.
    @State private var recoveryRearmed = false
    /// The target was played since the last attempt — logged with the attempt
    /// so "rhythm goes missing after I press play" can be checked against data.
    @State private var playedSinceLastAttempt = false
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
                    if heardNothing {
                        Label("Didn't hear anything — try again closer to the mic", systemImage: "mic.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            // A swipe-down mid-take used to leave the mic hot and let the
            // auto-stop score, save and count a take for a screen that was
            // gone — and the next line's recognizer collided with it. Done is
            // already disabled in these phases; the gesture now is too.
            .interactiveDismissDisabled(phase == .syncing || phase == .countdown)
            .onDisappear {
                cancelSync()
                recoverTask?.cancel()
                recoverTask = nil
                player.stop()
                attemptPlayer.stop()
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
                if let r = rhythm {
                    // How many words the score stands on, when not all of
                    // them — the header is the only place the number lives.
                    let total = activeRange?.count ?? timings.count
                    let judged = r.words.filter(\.isMeasured).count
                    HStack(spacing: 6) {
                        if judged < total {
                            Text(verbatim: "\(judged)/\(total)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Label("\(r.score)", systemImage: "metronome")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(scoreColor(r.score))
                    }
                } else if timings.isEmpty {
                    Text("no timings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if practiceRange != nil {
                    Text("Practicing the selected phrase")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    // The one thing this screen never said out loud: the
                    // words can be tapped. It replaced a word count nobody
                    // needed.
                    Text("Tap words to pick a phrase")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
        FlowLayout(spacing: 1, lineSpacing: 4) {
            ForEach(Array(timings.enumerated()), id: \.offset) { i, wt in
                let selected = selectedWordRange?.contains(i) ?? false
                VStack(spacing: 0) {
                    Text(wt.word)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(wordColor(at: i, wt: wt))
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                    beatMark(wordBeats[i])
                }
                .contentShape(Rectangle())
                .onTapGesture { tapWord(i) }
            }
        }
    }

    // MARK: - Beat marks

    /// Fold the result onto word indices — once per result, never per frame.
    private func refreshWordVerdicts() {
        wordOps = positionAlignment()
        guard let rhythm else { wordBeats = [:]; return }
        // The practiced range's words are re-based onto the whole line.
        let base = activeRange?.lowerBound ?? 0
        wordBeats = Dictionary(rhythm.words.map { ($0.targetIndex + base, $0) },
                               uniquingKeysWith: { first, _ in first })
    }

    /// 300 ms — the edge of "slightly off" — is 18 pt: visible under a short
    /// word without walking into its neighbour.
    private static let beatPointsPerMs: CGFloat = 0.06
    private static let beatMaxOffset: CGFloat = 24

    /// The rhythm verdict, drawn ON the target line rather than in a card of
    /// its own (2026-09-16): a dot under each word the attempt was timed on,
    /// sitting where the learner started — under the word's centre on the
    /// beat, pushed right if late, left if early — in the same colour scale
    /// the score is built from. A word nobody measured, or the learner
    /// skipped, gets no dot; the header's `6/10` says how many did. The row
    /// is always reserved so the line doesn't jump when a result lands.
    ///
    /// Two things this replaced, same day: bar timelines (Target / You) whose
    /// bar WIDTHS were durations the score never reads and the two sources
    /// couldn't agree on, and a per-word card with `+0.2s` labels that was
    /// right but took a third of the screen for one number per word. Colour
    /// on the word ITSELF was considered and rejected: text colour already
    /// means "wrong word" (orange for a substitution), and one channel can't
    /// carry two verdicts.
    @ViewBuilder
    private func beatMark(_ w: ShadowEngine.RhythmWord?) -> some View {
        ZStack {
            if let w, w.isMeasured {
                let offset = min(Self.beatMaxOffset, max(-Self.beatMaxOffset,
                                 CGFloat(w.deviationMs) * Self.beatPointsPerMs))
                let color = rhythmColor(deviationMs: w.deviationMs)
                let onBeat = ShadowEngine.rhythmGrade(deviationMs: w.deviationMs) == 2
                if !onBeat {
                    // A trace back to where the beat was.
                    Rectangle()
                        .fill(color.opacity(0.5))
                        .frame(width: abs(offset), height: 1)
                        .offset(x: offset / 2)
                }
                Circle()
                    .fill(onBeat ? color.opacity(0.55) : color)
                    .frame(width: 5, height: 5)
                    .offset(x: offset)
            }
        }
        .frame(height: 6)
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

    /// First word to last word — the span the learner's own duration is
    /// measured over (`analyze`). The whole line used to be the FILE length,
    /// lead-in and silent tail included, so a take that matched the voice
    /// exactly read 0.83× and was called rushed by the pace cell and the
    /// coach both; the phrase path always measured it right.
    private var practiceDurationMs: Int {
        if let r = practiceRange {
            return max(0, timings[r.upperBound].endMs - timings[r.lowerBound].startMs)
        }
        if let first = timings.first, let last = timings.last {
            return max(0, last.endMs - first.startMs)
        }
        return targetDurationMs
    }

    /// Picks the color for one target word.
    /// Order of precedence:
    ///   1. Live sync (clock running) → karaoke by elapsed user-time.
    ///   2. Target playback → karaoke by audio current-time. This outranks the
    ///      result: after the first take the line used to freeze on its diff
    ///      colours, so "Hear target" and the timeline's play had no moving
    ///      highlight and the listen→retry half of the loop lost its tempo
    ///      guide.
    ///   3. Post-attempt analysis → content accuracy (orange = said a
    ///      different word, dimmed = skipped).
    ///   4. Otherwise → secondary (waiting).
    private func wordColor(at i: Int, wt: WordTiming) -> Color {
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
        if !diffSteps.isEmpty {
            // Phrase attempts: diff indices are relative to the practiced
            // range; words outside it weren't attempted → stay quiet.
            if let r = activeRange, !r.contains(i) { return .secondary }
            let diffIndex = i - (activeRange?.lowerBound ?? 0)
            switch wordOps.targetOp[diffIndex] {
            case .sub:   return .orange      // user said a different word here
            case .del:   return .secondary   // user skipped this word
            default:     return .primary
            }
        }
        return .secondary
    }

    private func positionalColor(wt: WordTiming, nowMs: Int) -> Color {
        if nowMs >= wt.endMs   { return .primary }      // already passed
        if nowMs >= wt.startMs { return .accentColor }  // current word
        return .secondary                                // upcoming
    }

    /// After analysis only — the two spoken durations side by side and the
    /// pace ratio between them. Overall speed lives here; the SHAPE of the
    /// timing is the beat dots under the line.
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

    private func durationCell(label: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
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

    private func rhythmColor(deviationMs: Int) -> Color {
        switch ShadowEngine.rhythmGrade(deviationMs: deviationMs) {
        case 2:  return .green
        case 1:  return .orange
        default: return .red
        }
    }


    // MARK: - Position alignment (diff-only)

    /// Maps each target word position to its diff op (.match / .sub / .del) —
    /// the WORDS verdict. The timing verdict is `wordBeats`.
    private struct PositionAlignment {
        var targetOp: [Int: ShadowEngine.DiffOp] = [:]
    }

    private func positionAlignment() -> PositionAlignment {
        var out = PositionAlignment()
        guard !diffSteps.isEmpty else { return out }
        // A word of the line is NOT a token of the diff: `expandForDiff`
        // splits hyphens, contractions and digits, so walking the steps and
        // numbering target slots 0,1,2… shifted every colour after the first
        // such word. Ask the engine which tokens each word owns instead.
        let words = (activeRange.map { Array(timings[$0]) } ?? timings).map(\.word)
        let spans = ShadowEngine.tokenSpans(for: words, language: targetLanguage)
        let ops = ShadowEngine.targetOps(diffSteps)
        // Same philosophy as analyzeRhythm's guards: if the two streams don't
        // account for each other exactly, colour nothing rather than something
        // shifted. A wrong word in orange is worse than no orange.
        guard spans.last?.upperBound ?? 0 == ops.count else { return out }

        for (i, span) in spans.enumerated() {
            let slice = ops[span]
            if slice.isEmpty { out.targetOp[i] = .match; continue }        // punctuation-only
            if slice.contains(.sub) { out.targetOp[i] = .sub; continue }   // said differently
            // A word split across tokens counts as attempted unless EVERY
            // piece went missing — "speech text" for "speech-to-text" is a
            // wrong word, not a skipped one.
            out.targetOp[i] = slice.allSatisfy { $0 == .del } ? .del
                            : (slice.contains(.del) ? .sub : .match)
        }
        return out
    }

    @ViewBuilder
    private func feedbackSection(_ fb: ShadowFeedback) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                // Not "Feedback": that key is Settings' "Send feedback" row,
                // so the score header read as a mail link in every language.
                Text("Your take")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // The headline is words AND beat (`overallScore`). When the
                // take could not be timed it is words alone, and the badge
                // says so — a number that quietly changes what it measures
                // is worse than one that admits what it missed.
                HStack(spacing: 6) {
                    if fb.rhythmScore == nil {
                        Text("words only")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Label("\(fb.overallScore)", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(scoreColor(fb.overallScore))
                }
            }

            if !diffSteps.isEmpty {
                diffSection
            }
            if recordingFileURL != nil {
                playbackRow
            }
            if coachPending {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Writing feedback…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        // The take on screen is the card above; listing it again as row one
        // read as a duplicate.
        let past = appState.shadowAttempts
            .filter { $0.turnId == turn.id && $0.id != shownAttemptId }
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
                Text("\(a.overallScore)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(scoreColor(a.overallScore))
                    .monospacedDigit()
                Text(a.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                if a.isPartial {
                    // A phrase take, scored on part of the line — say which
                    // part, or its score reads as the line's.
                    Text(a.targetText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if a.learnerTranscript.isEmpty {
                    Text("(silent)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(a.learnerTranscript)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                // The one bullet worth keeping: what to try next time. It
                // was saved with every attempt and never shown again.
                if !a.fix.isEmpty {
                    Text(a.fix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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
            .accessibilityLabel("Hear my attempt")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteShadowAttempt(id: a.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
            self.error = explain("Recording file missing.")
            return
        }
        playAttempt(data)
    }

    private var playbackRow: some View {
        VStack(spacing: 8) {
            // lineLimit(1) + scale-down keeps both labels single-line so the
            // two bordered buttons render the same height ("Hear my attempt"
            // used to wrap to two lines and grow taller than its sibling).
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
            // Its own row, not a third of the one above: hearing the two takes
            // over each other is the thing worth doing here, and it does not
            // belong squeezed beside the two halves it is made of.
            Button { Task { await playTogether() } } label: {
                Label("Both at once", systemImage: "person.2.wave.2")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("Your take over the line, both starting on their first word — hear where you drift.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.regular)
    }

    private func playMyAttempt() async {
        guard let url = recordingFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            self.error = explain("Recording isn't available.")
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
    private func bullet(icon: String, label: LocalizedStringKey, text: String) -> some View {
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
            // The pulse draws OUTSIDE the circle's 64pt layout frame, and the
            // panel sits flush against the sheet's bottom edge — without this
            // slack the scaled-up rim gets clipped flat there.
            .padding(diameter * 0.03)
        }
        .buttonStyle(.plain)
        .tint(phase == .syncing ? .red : .accentColor)
        .disabled(!syncEnabled)
        .accessibilityLabel(micHint)
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

    /// The mic button's accessibility label — the one place its meaning per
    /// phase is spelled out (a caption under it was dropped on purpose).
    /// `chrome(…)`, not bare literals: this is a `String`-typed switch, so a
    /// plain literal never sees the root's `\.locale` and stayed English in
    /// every language.
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
        playedSinceLastAttempt = true

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
                self.error = explain("Couldn't load audio for this line.")
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

    // MARK: - Both at once

    /// How far back the model line sits, and how wide the two voices are
    /// panned. The learner's own take stays at full level and slightly to the
    /// right; the model is quieter and slightly left, so the pair separates on
    /// earphones without either becoming a background texture.
    private static let duetTargetVolume: Float = 0.4
    private static let duetPan: Float = 0.35

    /// Play the model line and the learner's take AT ONCE, each trimmed to its
    /// own first word so they start together.
    ///
    /// This is the rhythm card with the screen turned off: a learner who ran
    /// late hears themselves drift behind, which no two-row diagram conveys as
    /// directly. Speed is not matched — see `AudioPlayer.armDuet`.
    ///
    /// Honest limit: the takes are different lengths, so the further in you
    /// get the wider the gap. On a short line that gap IS the lesson; on a
    /// long one it degrades into two people talking at once, which is what the
    /// timeline's range selection is for.
    private func playTogether() async {
        error = nil
        player.stop()
        attemptPlayer.stop()

        guard let attemptURL = recordingFileURL,
              let attemptData = try? Data(contentsOf: attemptURL) else {
            self.error = explain("Recording isn't available.")
            return
        }
        if cachedAudioURL == nil || !FileManager.default
            .fileExists(atPath: cachedAudioURL?.path ?? "") {
            await prepareAudio()
        }
        guard let targetURL = cachedAudioURL,
              let targetData = try? Data(contentsOf: targetURL) else {
            if error == nil { self.error = explain("Couldn't load audio for this line.") }
            return
        }

        // Both takes open on silence — the model line on its own lead-in, the
        // attempt on the 350 ms the recorder deliberately keeps in front of
        // the go beat plus however long the learner took to start. Skipping to
        // where each one actually begins is what makes "together" mean
        // together, and the onset comes from the AUDIO (`firstVoiceOnset`):
        // word timings are missing on every take the aligner couldn't anchor
        // and are a character-count estimate on any target line that came from
        // a call, and a missing onset read as 0 — which played the take from
        // the top of the file, the reported "my voice has a big gap in front".
        // A phrase selection is the one case timings must decide, because its
        // start is mid-file, not the first sound in it.
        let targetSlice = activeRange.map { Array(timings[$0]) } ?? timings
        let targetLead = activeRange != nil
            ? Double(targetSlice.first?.startMs ?? 0) / 1000
            : (AudioLoudness.firstVoiceOnset(at: targetURL)
               ?? Double(targetSlice.first?.startMs ?? 0) / 1000)
        let attemptLead = AudioLoudness.firstVoiceOnset(at: attemptURL)
            ?? Double(attemptWordTimings.first?.startMs ?? 0) / 1000

        guard player.armDuet(targetData, skipping: targetLead,
                             volume: Self.duetTargetVolume, pan: -Self.duetPan,
                             configureSession: true),
              attemptPlayer.armDuet(attemptData, skipping: attemptLead,
                                    volume: 1.0, pan: Self.duetPan,
                                    configureSession: false) else {
            self.error = explain("Couldn't play the two takes together.")
            return
        }
        // One clock reading, one start time, both halves. Enough lead for the
        // second `play(atTime:)` call to be made before the moment arrives.
        let go = player.deviceTimeNow + 0.2
        player.startDuet(at: go)
        attemptPlayer.startDuet(at: go)
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
        Telemetry.log("shadow_attempt_started", [
            "recovery_running": recoverTask == nil ? "0" : "1",
            "played_first": playedSinceLastAttempt ? "1" : "0",
            "target_measured": timings.contains(where: \.isMeasured) ? "1" : "0",
        ])
        playedSinceLastAttempt = false
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
            error = explain("Microphone or speech permission denied.")
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
        resetResult()
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
        // Nothing may have moved the phase during the count but a teardown.
        guard phase == .countdown else { return }
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
        guard phase == .syncing || phase == .countdown else { return }
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
        prevTranscript = ""
        activeRange = nil
        resetResult()
        phase = .idle
        HapticEngine.selection()
        Telemetry.log("shadow_attempt_cancelled")
        rearmTimingRecovery()
    }

    /// Everything a result populates, back to nothing — one list, so a new
    /// take and a cancel can't disagree about what a previous result left
    /// behind.
    private func resetResult() {
        feedback = nil
        heardNothing = false
        coachPending = false
        shownAttemptId = nil
        diffSteps = []
        rhythm = nil
        wordOps = PositionAlignment()
        wordBeats = [:]
        attemptWordTimings = []
    }

    /// The free target alignment is killed the moment a recording starts
    /// (two recognizers on one mic truncate the take) and used to stay dead
    /// for the rest of the visit — so a learner who pressed record before it
    /// finished had EVERY attempt's rhythm judged against the character-count
    /// estimate, on a line whose audio came from a live call and so never had
    /// stored timings to begin with. Re-arm it once the mic is down. Only when
    /// `startSync` cleared it: a pass that already ran this visit keeps the
    /// one-try-per-open rule `recoverTimings` documents.
    private func rearmTimingRecovery() {
        // Only while the line is still on the ESTIMATE, and only once: a
        // recovered timeline with a few interpolated words is as good as
        // this pass gets, and a recognizer re-run after every attempt is a
        // recognizer that may still be winding down when the next take's
        // scoring pass starts.
        guard recoverTask == nil, !recoveryRearmed,
              !timings.contains(where: \.isMeasured),
              let url = cachedAudioURL,
              FileManager.default.fileExists(atPath: url.path),
              let voiceId = appState.voiceCloneId else { return }
        recoveryRearmed = true
        recoverTask = Task {
            // A beat before the recognizer opens: a retry tapped straight
            // after the result cancels this while it is still a sleep, not a
            // recognition that has to be wound down under the live mic.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await recoverTimings(url: url, voiceId: voiceId)
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
        // `finalText` is the live recognizer's last PARTIAL hypothesis —
        // stop() can't wait for a final pass, so it is systematically worse
        // than what the learner actually said. The whole attempt is on disk,
        // and reading THAT is `ShadowTranscriber`'s job: levelled audio, the
        // words from an audio-grounded model that is never shown the target,
        // the times carried over from the on-device pass. No pre-roll to
        // strip — the file starts on the go beat, and its only lead-in is the
        // deliberate 350ms that catches a learner who speaks the moment "0"
        // appears, which IS the attempt.
        let reading = await ShadowTranscriber.read(
            audioURL: recordingFileURL,
            liveText: finalText,
            targetLanguage: targetLanguage,
            recognitionHints: Self.recognitionHints(for: attemptTargetText)
        )
        let scoredText = reading.text
        let learnerTimings = reading.wordTimings
        attemptWordTimings = learnerTimings
        prevTranscript = scoredText
        // Nothing read the file — the score is standing on a live partial.
        // Surface it in the result UI and count it, so "the score felt wrong"
        // days are checkable against data.
        usedRoughTranscript = reading.source == .rough
        if usedRoughTranscript {
            Telemetry.log("shadow_rescore_failed")
        }
        // How often the two readers describe different sentences is the only
        // measure of how wrong the old single-reader path was.
        Telemetry.log("shadow_transcript", [
            "source": reading.source.rawValue,
            "disagreed": reading.readersDisagreed ? "1" : "0",
            "timed": learnerTimings.isEmpty ? "0" : "1",
            "audio": reading.audioOutcome.rawValue,
            "device_ms": "\(reading.deviceMs)",
            "audio_ms": "\(reading.audioMs)",
        ])

        // No speech at all — a learner who never started, a mic that never
        // opened. Not a 0: nothing is saved, counted or coached, and the
        // line says so. The auto-stop fires at the line's own length with
        // nobody talking, so this is an ordinary path, not an edge.
        if scoredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            heardNothing = true
            // Nothing references a silent take; don't leave it in Documents.
            if let url = recordingFileURL { try? FileManager.default.removeItem(at: url) }
            recordingFileURL = nil
            phase = .result
            rearmTimingRecovery()
            Telemetry.log("shadow_heard_nothing", ["source": reading.source.rawValue])
            return
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
            learnerTimings: learnerTimings,
            language: targetLanguage
        )
        refreshWordVerdicts()
        rearmTimingRecovery()
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
        // Coaching is gated on the number the learner is JUDGED by, not on
        // the word half of it — a take that hit every word a beat late is
        // exactly the one that needs a bullet, and under the old gate it was
        // the one that never got one.
        let overall = ShadowEngine.overallScore(match: analysis.score, rhythm: rhythm?.score)
        let coachable = overall < 90

        // The result goes up NOW, on the deterministic half. The bullets
        // used to sit in front of it — one more Gemini round trip (3–6 s on
        // the ledger) between "Comparing…" and a score that had been known
        // for all of it. They arrive in place below.
        // The ≥90 line names what was measured: "on the beat" is a claim
        // about rhythm, and beside a "words only" badge it was a lie.
        feedback = ShadowFeedback(
            pronunciation: coachable ? ""
                : (rhythm == nil
                   ? explain("Nailed it — matched the line almost word for word.")
                   : explain("Nailed it — matched the line almost word for word, on the beat.")),
            pacing: "",
            fix: "",
            matchScore: analysis.score,
            rhythmScore: rhythm?.score
        )
        coachPending = coachable
        phase = .result
        HapticEngine.shadowComplete(score: overall)

        // Persist this attempt so the user can revisit / hear it later —
        // before the coach call, so an attempt whose bullets never come is
        // still on file with its score and recording.
        var attempt = ShadowAttempt(
            turnId: turn.id,
            targetText: attemptTargetText,
            learnerTranscript: scoredText,
            recordingFilename: recordingFileURL?.lastPathComponent,
            matchScore: analysis.score,
            rhythmScore: rhythm?.score,
            pronunciation: feedback?.pronunciation ?? "",
            pacing: "",
            fix: "",
            phraseRange: activeRange
        )
        shownAttemptId = attempt.id
        appState.saveShadowAttempt(attempt)
        // A recorded take IS the practice — nothing else to finish.
        PracticeLog.shared.record(.shadow, finished: true)

        guard coachable else { return }
        let coachStartedAt = Date()
        var payload: ShadowEngine.Payload?
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
        Telemetry.log("shadow_coach", [
            "outcome": payload == nil ? "failed" : "ok",
            "ms": "\(Int(Date().timeIntervalSince(coachStartedAt) * 1000))",
        ])

        if let payload {
            attempt.pronunciation = payload.pronunciation
            attempt.pacing = payload.pacing
            attempt.fix = payload.fix
            appState.updateShadowAttempt(attempt)
        }
        // The learner may have started the next take meanwhile; the record
        // above is theirs either way, the screen is not.
        guard shownAttemptId == attempt.id else { return }
        coachPending = false
        feedback?.pronunciation = payload?.pronunciation
            ?? explain("Coach comments couldn't load — the score and highlighted words above are still accurate.")
        feedback?.pacing = payload?.pacing ?? ""
        feedback?.fix = payload?.fix ?? ""
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
                              endMs: max(Int(start) + 1, Int(cursor) - 20),
                              isMeasured: false)
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
