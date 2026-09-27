import AVFoundation
import SwiftUI

/// Teleprompter mode — the talk, run AGAIN, with the learner's own lines
/// replaced by their corrected versions.
///
/// The third door on a talk book, beside Continue and Replay, and the only
/// one that puts the learner back INSIDE the call. Replay plays the
/// conversation back at them; Continue starts a new one. This re-runs the
/// same conversation with them in it: the corrected line comes up on the
/// prompter, they read it out loud, the fluent self's stored answer plays,
/// and the next line comes up. Live shadowing, in the shape of the call it
/// came from.
///
/// A Watch book gets the same door (2026-09-27): its scene is run with the
/// learner reading the fluent self's side — the book's Shadow chapter, in
/// order, between the counterpart's lines — instead of one line at a time.
/// `Source` is the only thing that knows which of the two it is running.
///
/// Three rules it is built on:
///
/// - **Nothing is synthesized and nothing is metered.** Every fluent-self
///   line is the audio that call already produced (`TurnAudioStore`) — or,
///   for a Watch scene, the counterpart's lines already in the audio cache
///   (`PhraseAudioStore`); a line with no recording is READ, never
///   synthesized, since a scene is claimed by count — and the
///   only network call is the free audio-grounded read of a take
///   (`purpose: "transcribe"`). A learner whose month is spent can run this
///   all day — it is the "Shadowing · replays — Unlimited" the paywall card
///   already promises, so there is deliberately no `BillingGate` here.
/// - **A score walks through the one door.** `ShadowTranscriber` reads the
///   take and `ShadowEngine` grades it, exactly as `ShadowDrillView` does.
///   `rhythmScore` is nil by construction: a correction was never spoken by
///   anyone, so there is no beat to measure against, and
///   `ShadowAttempt.overallScore` falls back to the match score on its own.
/// - **It never stops.** A weak read is scored, shown and left behind — the
///   run keeps its shape as a conversation — and the line keeps a Retry
///   button for as long as the screen is open (user decision, 2026-09-27).
struct TeleprompterView: View {
    /// What is being run again — a finished talk or a Watch book's scene.
    /// Everything that differs between the two is resolved here by the
    /// caller, so the run itself never asks which one it is.
    struct Source {
        /// "talk" / "scene" — telemetry only.
        let kind: String
        let title: String
        let targetLanguage: String
        /// Name on the OTHER side's lines ("Future self", or the scene's
        /// counterpart), already localized.
        let otherName: String
        var otherAvatar: UIImage? = nil
        let steps: [TeleprompterScript.Step]
        /// The other side's line as it was ALREADY recorded. Nil means the
        /// line is read, never synthesized: a talk replays for free and a
        /// scene's lines are claimed by count, so a new synthesis here would
        /// be the one metered thing on a screen that promises none.
        let audio: (TeleprompterScript.Step) -> Data?

        @MainActor
        static func talk(_ session: Session) -> Source {
            Source(kind: "talk",
                   title: session.displayTitle,
                   targetLanguage: session.targetLanguage,
                   otherName: chrome("Future self"),
                   steps: TeleprompterScript.build(session: session),
                   audio: { TurnAudioStore.shared.data(for: $0.id) })
        }

        /// A Watch book's scene. The counterpart's lines play from the audio
        /// cache under the SAME key `WatchView` wrote them with (text + the
        /// counterpart's preset voice), so a scene that has been watched once
        /// runs here without a single request.
        @MainActor
        static func scene(title: String, targetLanguage: String,
                          curriculum: ScenarioCurriculum,
                          counterpart: Counterpart) -> Source {
            let voiceId = counterpart.voicePresetId
            return Source(kind: "scene",
                          title: title,
                          targetLanguage: targetLanguage,
                          otherName: counterpart.name,
                          otherAvatar: CounterpartPhotoStore.shared.image(for: counterpart.id),
                          steps: TeleprompterScript.build(scene: curriculum.dialogue ?? [],
                                                          shadowLines: curriculum.shadowLines),
                          audio: { PhraseAudioStore.shared.data(text: $0.text, voiceId: voiceId) })
        }
    }

    let source: Source

    init(source: Source) {
        self.source = source
        _steps = State(initialValue: source.steps)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var live = LiveTranscriber()

    @State private var steps: [TeleprompterScript.Step] = []
    /// The step the run is on. Everything before it is history.
    @State private var index = 0
    @State private var phase: Phase = .intro
    /// Per step id — filled as each take is graded, in the background.
    @State private var takes: [UUID: Take] = [:]
    @State private var runTask: Task<Void, Never>?
    @State private var scoreTasks: [UUID: Task<Void, Never>] = [:]
    /// What the prompter is showing. Held separately from `index` so the
    /// one-off retry from the finished screen doesn't wind the history back.
    @State private var promptStep: TeleprompterScript.Step?
    @State private var oneOffRetry = false
    /// Set by "Done reading" so the wait ends without ending the run, and by
    /// Skip so the step is abandoned unscored.
    @State private var endReadingNow = false
    @State private var skipRequested = false
    /// The playing file reached its end (or was stopped).
    @State private var playbackDone = false
    /// The last step held the mic, so the next playback has to put the audio
    /// session back — capture leaves it configured for capture.
    @State private var justRecorded = false
    @State private var micError: String?
    @State private var askingMicChoice = false
    @State private var micChoiceContinuation: CheckedContinuation<Void, Never>?

    /// Where a run is. Scoring is deliberately NOT a phase: a take is graded
    /// behind the fluent self's answer, which is the pause a call already has.
    private enum Phase { case intro, listening, reading, finished }

    /// One read line. `heardNothing` is not a 0 — the same rule
    /// `ShadowDrillView` holds: nothing is saved, counted or coached.
    private struct Take {
        enum Outcome: Equatable { case scored(Int), heardNothing, skipped }
        var outcome: Outcome
        var heard: String = ""
        var score: Int? { if case .scored(let s) = outcome { return s } else { return nil } }
    }

    /// How long the prompter waits for the learner to START before letting
    /// the conversation move on. Generous: a line you have never read takes
    /// a beat, and the run's whole promise is that it doesn't stop.
    private static let firstVoiceSeconds: TimeInterval = 8
    /// Earliest a read can end, per word — measured from the learner's FIRST
    /// WORD, not from the mic opening, which is where `ShadowDrillView`
    /// measures from because its countdown puts the two at the same moment.
    private static let readMsPerWord = 380
    /// Reading pace for a fluent-self line whose recording didn't survive.
    /// Only ever sizes a pause; the line is already on screen.
    private static let silentReadMsPerWord = 380

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if phase == .intro {
                        introHero
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { i, step in
                                historyRow(step, isCurrent: phase == .listening && i == index)
                                    .id(step.id)
                            }
                        }
                        .padding(20)
                    }
                }
                // The run reads like a call: the newest line sits above the
                // prompter, not at the top of an empty page.
                .defaultScrollAnchor(.bottom)
                .onChange(of: index) { _, _ in scrollToEnd(proxy) }
                .onChange(of: phase) { _, _ in scrollToEnd(proxy) }
            }
            .navigationTitle("Teleprompter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { finishAndDismiss() }
                }
            }
            .fadingBottomBar { prompterPanel }
        }
        // A swipe-down mid-take leaves the mic hot and the run half torn
        // down — the trap `ShadowDrillView` documents. Close is explicit.
        .interactiveDismissDisabled(phase == .reading)
        .sheet(isPresented: $askingMicChoice, onDismiss: resumeAfterMicChoice) {
            MicChoiceSheet { _ in }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { micError != nil },
                                    set: { if !$0 { micError = nil } })) {
            Button("OK") { micError = nil }
        } message: { Text(micError ?? "") }
        .onAppear {
            #if DEBUG
            seedCaptureStage()
            #endif
        }
        .onDisappear(perform: tearDown)
    }

    // MARK: - The conversation so far

    /// Everything already played or read. While the learner is READING, the
    /// current line lives on the prompter and nowhere else — it is the script
    /// in front of them, not a line of the transcript yet. A one-off retry
    /// from the finished screen is the exception: the run is over, so the
    /// history stays whole underneath it.
    private var history: [TeleprompterScript.Step] {
        guard phase != .intro else { return [] }
        let upTo = (phase == .reading && !oneOffRetry) ? index : index + 1
        return Array(steps.prefix(max(0, min(upTo, steps.count))))
    }

    @ViewBuilder
    private func historyRow(_ step: TeleprompterScript.Step, isCurrent: Bool) -> some View {
        let take = takes[step.id]
        // `DialogueLine.name` is a `String`, so a literal here would be
        // frozen English — see "UI text has ONE language".
        DialogueLine(speaker: step.isSpoken ? .user : .other,
                     name: step.isSpoken ? chrome("You") : source.otherName,
                     avatar: step.isSpoken ? nil : source.otherAvatar,
                     isCurrent: isCurrent) {
            if step.isCorrected {
                Text(highlightedCorrection(step.text, original: step.said, baseFont: .body))
            } else {
                Text(step.text)
            }
        } accessory: {
            if step.isSpoken { takeAccessory(step, take: take) }
        }
        // A weak read is told in the learner's own words as well as a number:
        // which words drifted is the only actionable half of a low score.
        if step.isSpoken, let take, let score = take.score,
           score < PracticeStats.retryThreshold, !take.heard.isEmpty {
            Text(chrome("Heard") + ": " + take.heard)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func takeAccessory(_ step: TeleprompterScript.Step, take: Take?) -> some View {
        HStack(spacing: 8) {
            switch take?.outcome {
            case .scored(let score):
                Label(String(score),
                      systemImage: score >= ScenarioCurriculum.shadowMasteryScore
                        ? "checkmark.circle.fill" : "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scoreColor(score))
            case .heardNothing:
                Label("Didn't hear that", systemImage: "mic.slash")
                    .font(.caption).foregroundStyle(.secondary)
            case .skipped:
                Label("Skipped", systemImage: "forward")
                    .font(.caption).foregroundStyle(.secondary)
            case nil:
                ProgressView().controlSize(.mini)
            }
            if take != nil {
                Button { retry(step) } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case ScenarioCurriculum.shadowMasteryScore...: return .green
        case PracticeStats.retryThreshold..<ScenarioCurriculum.shadowMasteryScore: return .accentColor
        default: return .orange
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = history.last else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    // MARK: - The prompter

    @ViewBuilder
    private var prompterPanel: some View {
        VStack(spacing: 12) {
            switch phase {
            case .intro:     introPanel
            case .listening: listeningPanel
            case .reading:   readingPanel
            case .finished:  finishedPanel
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// The cover of a run: what is about to happen, and how much of it. It
    /// sits in the PAGE rather than in the bar, because until Start there is
    /// no conversation underneath it to leave room for.
    private var introHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
            Text(source.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(explain("Your lines come back one at a time, corrected. Read each one out loud — the answer you got plays, and the next line comes up."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if correctedCount > 0 {
                Label("\(spokenCount) lines · \(correctedCount) corrected",
                      systemImage: "sparkles")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .frame(maxWidth: .infinity)
    }

    private var introPanel: some View {
        Group {
            if spokenCount == 0 {
                Label("Nothing to read in this talk", systemImage: "text.bubble")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button {
                    start(from: 0)
                } label: {
                    Label("Start", systemImage: "text.viewfinder")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var listeningPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3).foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text("\(source.otherName) is answering").font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Skip") { skipRequested = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    @ViewBuilder
    private var readingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)
                Text(promptStep?.isCorrected == true ? "Say it the fixed way" : "Say your line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let step = promptStep {
                Group {
                    if step.isCorrected {
                        Text(highlightedCorrection(step.text, original: step.said, baseFont: .title2))
                    } else {
                        Text(step.text)
                    }
                }
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)
                if !step.note.isEmpty {
                    Text(step.note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button("Skip") { skipRequested = true }
                    .buttonStyle(.bordered)
                Button {
                    endReadingNow = true
                } label: {
                    Label("Done reading", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var finishedPanel: some View {
        VStack(spacing: 10) {
            if let average = averageScore {
                Label("\(readCount) of \(spokenCount) lines read · \(average) average",
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text(explain("Nothing was scored this time — the mic heard no speech."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button {
                    takes.removeAll()
                    start(from: 0)
                } label: {
                    Label("Run again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    finishAndDismiss()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
    }

    private var spokenCount: Int { steps.filter(\.isSpoken).count }
    private var correctedCount: Int { steps.filter { $0.isSpoken && $0.isCorrected }.count }
    private var readCount: Int { takes.values.filter { $0.score != nil }.count }
    private var averageScore: Int? {
        let scores = takes.values.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    // MARK: - The run

    private func start(from i: Int) {
        runTask?.cancel()
        runTask = Task { @MainActor in await run(from: i) }
    }

    /// Walk the script. Every step awaits its own end, so the loop IS the
    /// pacing — there is no timer anywhere on this screen.
    private func run(from start: Int) async {
        oneOffRetry = false
        await askMicChoiceIfNeeded()
        var i = start
        while !Task.isCancelled, i < steps.count {
            index = i
            let step = steps[i]
            if step.isSpoken { await readStep(step) } else { await listenStep(step) }
            guard !Task.isCancelled else { return }
            i += 1
        }
        guard !Task.isCancelled else { return }
        index = max(0, steps.count - 1)
        phase = .finished
        Telemetry.log("teleprompter_run", [
            "kind": source.kind,
            "lines": "\(spokenCount)",
            "read": "\(readCount)",
            "avg": averageScore.map(String.init) ?? "",
        ])
    }

    /// The fluent self's answer — the audio that call already produced, never
    /// a new synthesis. A turn whose recording didn't survive is READ
    /// instead: the line is on screen, so the pause is all that's missing.
    private func listenStep(_ step: TeleprompterScript.Step) async {
        phase = .listening
        skipRequested = false
        guard let data = source.audio(step) else {
            await waitUnlessSkipped(untilMs: silentReadPause(for: step.text))
            return
        }
        let reset = justRecorded
        justRecorded = false
        playbackDone = false
        do {
            try player.play(data, source: "teleprompter", forceSessionReset: reset) {
                playbackDone = true
            }
        } catch {
            await waitUnlessSkipped(untilMs: silentReadPause(for: step.text))
            return
        }
        while !Task.isCancelled, !skipRequested, !playbackDone {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Gate first: `stop()` fires the completion, which is harmless here
        // but is the same trap TalkTranscriptView documents for a sequence.
        player.stop()
    }

    private func waitUnlessSkipped(untilMs ms: Int) async {
        let deadline = Date().addingTimeInterval(Double(ms) / 1000)
        while !Task.isCancelled, !skipRequested, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func silentReadPause(for text: String) -> Int {
        min(8000, max(1500, WordSplitter.count(text) * Self.silentReadMsPerWord))
    }

    /// The learner's line. The mic opens with the line, the take ends when
    /// they go quiet, and the GRADING is handed to a task of its own so the
    /// fluent self answers immediately — the conversation's own pause is
    /// where the scoring goes.
    private func readStep(_ step: TeleprompterScript.Step) async {
        phase = .reading
        promptStep = step
        endReadingNow = false
        skipRequested = false
        takes[step.id] = nil
        scoreTasks[step.id]?.cancel()
        player.stop()

        do {
            // The same three choices `ShadowDrillView` makes, for the same
            // reasons: bias the on-device recognizer toward the line being
            // read (its text is only the FALLBACK here), let the learner's
            // own mic preference stand, and keep voice processing on so a
            // room can't hold the take open forever.
            try live.start(locale: source.targetLanguage,
                           preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                           measurementMode: false,
                           contextualStrings: ShadowDrillView.recognitionHints(for: step.text),
                           voiceProcessing: true)
        } catch {
            micError = error.localizedDescription
            takes[step.id] = Take(outcome: .skipped)
            return
        }
        let url = try? recorder.prepare(quality: .sttOptimal)
        try? recorder.beginPrepared()
        justRecorded = true

        let spoke = await waitForReadToEnd(text: step.text)

        // Tail grace — a "Done reading" tap lands mid-syllable, and a clipped
        // tail reads as a deletion in the diff.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let liveText = live.stop()
        _ = recorder.stop()

        guard spoke else {
            if let url { try? FileManager.default.removeItem(at: url) }
            takes[step.id] = Take(outcome: skipRequested ? .skipped : .heardNothing)
            return
        }
        scoreTasks[step.id] = Task { @MainActor in
            await score(step: step, url: url, liveText: liveText)
        }
    }

    /// True once the learner actually said something. Waits for their FIRST
    /// word, then for the line's own length, then for silence.
    private func waitForReadToEnd(text: String) async -> Bool {
        let firstVoiceDeadline = Date().addingTimeInterval(Self.firstVoiceSeconds)
        while !Task.isCancelled, !skipRequested, !endReadingNow,
              live.lastVoicedAt == nil, Date() < firstVoiceDeadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        guard !Task.isCancelled, !skipRequested else { return false }
        guard live.lastVoicedAt != nil || endReadingNow else { return false }

        let lineMs = max(1200, WordSplitter.count(text) * Self.readMsPerWord)
        let began = Date()
        let earliest = began.addingTimeInterval(Double(lineMs) / 1000)
        let hardStop = began.addingTimeInterval(
            Double(ShadowDrillView.attemptCutoffMs(targetMs: lineMs)) / 1000)
        while !Task.isCancelled, !skipRequested, !endReadingNow, Date() < hardStop {
            // "Quiet" is the shadow surface's 1.5 s, not a call's 0.6 s: a
            // mid-sentence breath runs up to 1.5 s, and someone reading a
            // line for the first time breathes more than a talker does.
            if Date() >= earliest, let voiced = live.lastVoicedAt,
               Date().timeIntervalSince(voiced) >= ShadowDrillView.stillSpeakingSeconds { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return !skipRequested
    }

    /// Grade the take — the one door (`ShadowTranscriber`), the one engine
    /// (`ShadowEngine`). No coach call: a run is twenty lines, and a bullet
    /// per line is twenty Gemini calls for text nobody reads mid-run. The
    /// full drill, coach and all, stays one tap away from the book.
    private func score(step: TeleprompterScript.Step, url: URL?, liveText: String) async {
        let reading = await ShadowTranscriber.read(
            audioURL: url,
            liveText: liveText,
            targetLanguage: source.targetLanguage,
            recognitionHints: ShadowDrillView.recognitionHints(for: step.text))
        // A retry cancels the score task it replaced — but the read it was
        // already inside finishes anyway, and writing its verdict would put
        // the OLD take's number on the NEW one.
        guard !Task.isCancelled else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }
        let heard = reading.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            if let url { try? FileManager.default.removeItem(at: url) }
            takes[step.id] = Take(outcome: .heardNothing)
            return
        }
        let analysis = ShadowEngine.analyze(target: step.text, learner: heard,
                                            language: source.targetLanguage)
        takes[step.id] = Take(outcome: .scored(analysis.score), heard: heard)
        // One take, one rep — the unit `ShadowDrillView` counts.
        PracticeLog.shared.record(.shadow, finished: true)
        HapticEngine.shadowComplete(score: analysis.score)

        // Only a line that IS review material becomes an attempt on file.
        // `attemptId` is the book's own correction id, so a passing read here
        // masters the Drill chapter exactly as a shadow take on that line
        // does. Everything else is practice: its take is counted as a rep and
        // its recording is dropped rather than left in Documents under a
        // filename nothing references.
        guard let attemptId = step.attemptId else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }
        appState.saveShadowAttempt(ShadowAttempt(
            turnId: attemptId,
            targetText: step.text,
            learnerTranscript: heard,
            recordingFilename: url?.lastPathComponent,
            matchScore: analysis.score,
            rhythmScore: nil,
            pronunciation: "",
            pacing: "",
            fix: ""))
    }

    /// Re-read one line. Mid-run it rejoins the script there — the answer
    /// after it plays again, which is the conversation. On the finished
    /// screen it is a single take and the page stays where it is.
    private func retry(_ step: TeleprompterScript.Step) {
        guard let i = steps.firstIndex(where: { $0.id == step.id }) else { return }
        let wasFinished = phase == .finished
        runTask?.cancel()
        player.stop()
        takes[step.id] = nil
        runTask = Task { @MainActor in
            if wasFinished {
                oneOffRetry = true
                await readStep(step)
                guard !Task.isCancelled else { return }
                oneOffRetry = false
                phase = .finished
            } else {
                await run(from: i)
            }
        }
    }

    // MARK: - Mic preference

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

    // MARK: - Capture

    #if DEBUG
    /// Park the screen in one of its running states for a screenshot. The mic
    /// can't be driven from a capture run, so the two states that need one
    /// are seeded instead — the same trick `captureShadow` plays.
    private func seedCaptureStage() {
        guard let stage = DebugCapture.teleprompterStage, !steps.isEmpty else { return }
        let spoken = steps.enumerated().filter { $0.element.isSpoken }
        switch stage {
        case "reading":
            guard let (i, step) = spoken.first else { return }
            index = i
            promptStep = step
            phase = .reading
        case "done":
            for (n, (_, step)) in spoken.enumerated() {
                takes[step.id] = Take(outcome: .scored(n == 0 ? 92 : 61),
                                      heard: "How relaxed I stay, even on hard question.")
            }
            index = steps.count - 1
            phase = .finished
        default: break
        }
    }
    #endif

    // MARK: - Teardown

    private func finishAndDismiss() {
        tearDown()
        dismiss()
    }

    /// Deliberately complete: a run left with the recognizer alive keeps the
    /// mic hot, and a late completion would chain into a step whose screen is
    /// gone (the trap `TalkTranscriptView` and `WatchView` both document).
    private func tearDown() {
        runTask?.cancel()
        runTask = nil
        for task in scoreTasks.values { task.cancel() }
        scoreTasks.removeAll()
        player.stop()
        _ = live.stop()
        _ = recorder.stop()
    }
}
