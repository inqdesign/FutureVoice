import AVFoundation
import SwiftUI

/// Say it again — the talk, run AGAIN, with the learner's own lines
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
struct SayItAgainView: View {
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
        let steps: [SayItAgainScript.Step]
        /// The talk itself, when some of the learner's turns came back from
        /// the call with no whole-turn rewrite: the screen asks for those
        /// (`SayItAgainRewrites`) and swaps them in before they are read.
        /// Nil for a scene, and for a talk with nothing missing.
        var session: Session? = nil
        /// The other side's line as it was ALREADY recorded. Nil means the
        /// line is read, never synthesized: a talk replays for free and a
        /// scene's lines are claimed by count, so a new synthesis here would
        /// be the one metered thing on a screen that promises none.
        let audio: (SayItAgainScript.Step) -> Data?

        @MainActor
        static func talk(_ session: Session) -> Source {
            Source(kind: "talk",
                   title: session.displayTitle,
                   targetLanguage: session.targetLanguage,
                   otherName: chrome("Future self"),
                   steps: SayItAgainScript.build(session: session,
                                                 rewrites: SayItAgainRewrites.shared.all),
                   session: SayItAgainRewrites.shared.missing(in: session).isEmpty ? nil : session,
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
                          steps: SayItAgainScript.build(scene: curriculum.dialogue ?? [],
                                                          shadowLines: curriculum.shadowLines),
                          audio: { PhraseAudioStore.shared.data(text: $0.text, voiceId: voiceId) })
        }
    }

    let source: Source

    init(source: Source) {
        self.source = source
        let steps = Self.arranged(source.steps, kind: source.kind,
                                  bothSides: UserDefaults.standard.bool(forKey: Self.bothSidesKey))
        _steps = State(initialValue: steps)
        // The opening state is decided HERE, not in `onAppear`. A run that
        // skips the intro used to start one frame late, so the intro was
        // drawn and then taken away — "인트로가 나오다가 자동으로 닫혀" — which
        // is worse than the screen it was meant to remove. The first frame is
        // now already the conversation's first line; `onAppear` only sets it
        // playing. `UserDefaults` directly because `@AppStorage` isn't
        // readable before `self` exists; it is the same store the property
        // wrapper writes.
        let seen = UserDefaults.standard.bool(forKey: Self.introSeenKey)
        guard seen, let first = steps.first,
              steps.contains(where: { $0.isSpoken }) else { return }
        _index = State(initialValue: 0)
        // A first line still being rewritten waits on the prompter's
        // "getting ready" rather than flashing the line as it was said.
        let waits = first.isSpoken && source.session != nil
        _phase = State(initialValue: waits ? .preparing : first.isSpoken ? .reading : .listening)
        if first.isSpoken, !waits { _promptStep = State(initialValue: first) }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var live = LiveTranscriber()

    @State private var steps: [SayItAgainScript.Step] = []
    /// The step the run is on. Everything before it is history.
    @State private var index = 0
    @State private var phase: Phase = .intro
    /// Per step id — filled as each take is graded, in the background.
    @State private var takes: [UUID: Take] = [:]
    @State private var runTask: Task<Void, Never>?
    @State private var scoreTasks: [UUID: Task<Void, Never>] = [:]
    /// What the prompter is showing. Held separately from `index` so the
    /// one-off retry from the finished screen doesn't wind the history back.
    @State private var promptStep: SayItAgainScript.Step?
    /// The line on the prompter as the recognizer can follow it, and how many
    /// of its words have been heard. Drawn as the part of the line already
    /// lit, and it is what tells the take the line has been read to its end.
    @State private var promptTrack: SpeechPrompterTrack?
    @State private var spokenWords = 0
    @State private var oneOffRetry = false
    /// Skip abandons the step unscored. There is no "done" — a take ends on
    /// silence.
    @State private var skipRequested = false
    /// The playing file reached its end (or was stopped).
    @State private var playbackDone = false
    /// The last step held the mic, so the next playback has to put the audio
    /// session back — capture leaves it configured for capture.
    @State private var justRecorded = false
    /// Whether the learner has been told what this screen is. Shown ONCE
    /// and then never again: they arrived by tapping "Say it again" on the
    /// book, so from the second run the same paragraph plus a Start button is
    /// a page between them and the thing they already asked for. The first
    /// run keeps it — the mode is unusual enough to need a sentence, and it
    /// is also where the mic permission prompt belongs, in front of a tap
    /// the learner made rather than on top of a run already going.
    static let introSeenKey = "futurevoice.sayItAgain.introSeen"
    @AppStorage(introSeenKey) private var introSeen = false
    /// Read the other side's lines too (`SayItAgainScript.bothSides`).
    /// Remembered: whoever asked for it once wants it the next time.
    static let bothSidesKey = "futurevoice.sayItAgain.bothSides"
    @AppStorage(bothSidesKey) private var bothSides = false

    static func arranged(_ steps: [SayItAgainScript.Step], kind: String,
                         bothSides: Bool) -> [SayItAgainScript.Step] {
        bothSides ? SayItAgainScript.bothSides(steps, filesOtherSide: kind == "talk") : steps
    }
    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue
    @State private var micError: String?
    @State private var askingMicChoice = false
    @State private var micChoiceContinuation: CheckedContinuation<Void, Never>?
    /// The background request for the learner turns the call left without
    /// a whole-turn rewrite. `rewritesDone` is what a step waits on.
    @State private var fillTask: Task<Void, Never>?
    @State private var rewritesDone = true
    /// Set once a line has waited the full `rewriteWait`: the rest of the
    /// run doesn't wait again, and takes whatever lands when it lands.
    @State private var stoppedWaiting = false
    /// The sheet's own height, read off the NavigationStack (which the
    /// prompter bar can't shrink, so the cap below can't feed back on itself).
    @State private var pageHeight: CGFloat = 0
    /// The prompter line's natural height, measured inside its scroll view.
    @State private var lineHeight: CGFloat = 0
    /// The whole prompter bar's height. When it changes the transcript is
    /// put back on its last line: the bar settles a frame or two AFTER the
    /// phase change that scrolls (the line is measured once it is laid
    /// out), and without a second scroll the newest lines were left under
    /// the card — about one line in three (2026-11-02).
    @State private var barHeight: CGFloat = 0
    @State private var settleScroll: Task<Void, Never>?
    private static let endOfLinesId = "say-again-end-of-lines"
    /// How long one line may wait for its rewrite before it is read as it
    /// was said. A single request lands in ~2–4 s; this only covers a
    /// network that has gone away.
    private static let rewriteWait: TimeInterval = 20

    /// Where a run is. Scoring is deliberately NOT a phase: a take is graded
    /// behind the fluent self's answer, which is the pause a call already has.
    private enum Phase { case intro, listening, preparing, reading, finished }

    /// One read line. `heardNothing` is not a 0 — the same rule
    /// `ShadowDrillView` holds: nothing is saved, counted or coached.
    private struct Take {
        enum Outcome: Equatable { case scored(Int), heardNothing, skipped }
        var outcome: Outcome
        var heard: String = ""
        var score: Int? { if case .scored(let s) = outcome { return s } else { return nil } }
    }

    /// A line's estimated length, per word. Only sizes the ceiling below; no
    /// clock decides that a read is finished.
    private static let readMsPerWord = 380
    /// The only thing that ends a take on a learner still talking: a room
    /// that never falls quiet. At least this, and never less than
    /// `maxReadLineFactor` times the line's own estimate (2026-10-27): a
    /// whole-screen turn of 150+ words is ~57 s by that estimate alone, so a
    /// flat 60 s cut a learner off mid-sentence on exactly those lines.
    private static let maxReadSeconds: TimeInterval = 60
    private static let maxReadLineFactor = 2.5
    /// Reading pace for a fluent-self line whose recording didn't survive.
    /// Only ever sizes a pause; the line is already on screen.
    private static let silentReadMsPerWord = 380
    /// Quiet that ends a take once the script's last word has been heard. The
    /// 1.5 s below exists because nobody can tell a breath from the end of a
    /// line; with the line read to its end, that question is answered.
    private static let lineReadQuiet: TimeInterval = 0.5
    /// The same take in a room that never reads as quiet.
    private static let lineReadCeiling: TimeInterval = 1.2
    /// Quiet that ends a take stopped short of its last word. Nearly through
    /// the line the recognizer probably just missed the end; earlier than
    /// that the learner is looking for the next word (2026-11-09, founder:
    /// a mid-line pause past the line's estimated length ended the take).
    private static let nearEndQuiet: TimeInterval = ShadowDrillView.stillSpeakingSeconds
    private static let midLineQuiet: TimeInterval = 4
    private static let nearEndShare = 0.8
    private static let answerRingSeconds: TimeInterval = 0.35

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if phase == .intro {
                        introHero
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { i, step in
                                // One view: a row with a "Heard" line under it
                                // would otherwise be two views under one id.
                                VStack(alignment: .leading, spacing: 14) {
                                    historyRow(step, isCurrent: phase == .listening && i == index)
                                }
                                .id(step.id)
                            }
                            // What the scroll aims at: the gap above it keeps
                            // the newest line clear of the bar's soft edge.
                            Color.clear.frame(height: 1).id(Self.endOfLinesId)
                        }
                        .padding(20)
                    }
                }
                // The run reads like a call: the newest line sits above the
                // prompter, not at the top of an empty page.
                .defaultScrollAnchor(.bottom)
                .onChange(of: index) { _, _ in scrollToEnd(proxy) }
                .onChange(of: phase) { _, _ in scrollToEnd(proxy) }
                .onChange(of: barHeight) { _, _ in scrollToEnd(proxy) }
                // A score lands a second or two after its line and makes that
                // row taller, which pushes the newest line under the bar.
                .onChange(of: takes.count) { _, _ in scrollToEnd(proxy) }
                // Which lines are the learner's, always in sight and one tap
                // to change (2026-10-23, founder: the person icon behind a
                // menu was unclear and took two taps).
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("Read both sides",
                           selection: Binding(get: { bothSides },
                                              set: { setBothSides($0) })) {
                        Text("My lines").tag(false)
                        Text("Both sides").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .navigationTitle("Say it again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { finishAndDismiss() }
                }
            }
            .fadingBottomBar { prompterPanel }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .onChange(of: live.transcript) { _, heard in followVoice(heard) }
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
            // A capture asked for one state; running would leave it. The
            // opening state itself still comes from `init`, so a capture can
            // photograph either one by flipping `introSeenKey`.
            guard !DebugCapture.isCapturing else { return }
            #endif
            startRewritesIfNeeded()
            // `init` skipped the intro, so the run is already on screen and
            // only needs to start. Guarded so a re-appear can't restart it.
            if phase != .intro, runTask == nil { start(from: 0) }
        }
        .onDisappear(perform: tearDown)
    }

    // MARK: - The conversation so far

    /// Everything already played or read. While the learner is READING, the
    /// current line lives on the prompter and nowhere else — it is the script
    /// in front of them, not a line of the transcript yet. A one-off retry
    /// from the finished screen is the exception: the run is over, so the
    /// history stays whole underneath it.
    private var history: [SayItAgainScript.Step] {
        guard phase != .intro else { return [] }
        let upTo = ((phase == .reading || phase == .preparing) && !oneOffRetry) ? index : index + 1
        return Array(steps.prefix(max(0, min(upTo, steps.count))))
    }

    @ViewBuilder
    private func historyRow(_ step: SayItAgainScript.Step, isCurrent: Bool) -> some View {
        let take = takes[step.id]
        // `DialogueLine.name` is a `String`, so a literal here would be
        // frozen English — see "UI text has ONE language".
        let mine = step.isSpoken && !step.isOtherSide
        DialogueLine(speaker: mine ? .user : .other,
                     name: mine ? chrome("You") : source.otherName,
                     avatar: mine ? nil : source.otherAvatar,
                     isCurrent: isCurrent) {
            FuriganaText(step.isCorrected
                         ? highlightedCorrection(step.text, original: step.said, baseFont: .body)
                         : AttributedString(step.text)) {
                if step.isCorrected {
                    Text(highlightedCorrection(step.text, original: step.said, baseFont: .body))
                } else {
                    Text(step.text)
                }
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
    private func takeAccessory(_ step: SayItAgainScript.Step, take: Take?) -> some View {
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
        case PracticeStats.retryThreshold..<ScenarioCurriculum.shadowMasteryScore: return Color.themeAccent
        default: return .orange
        }
    }

    /// Once the page is full, a scroll made as the prompter grows aims at the
    /// room under the OLD bar: it moves nothing, and the card sits on the
    /// newest lines. The second pass runs once the taller bar is in place
    /// (the call does the same, `ConversationView.scroll`).
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard phase != .intro else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.endOfLinesId, anchor: .bottom) }
        settleScroll?.cancel()
        settleScroll = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, phase != .intro else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.endOfLinesId, anchor: .bottom) }
        }
    }

    // MARK: - The prompter

    @ViewBuilder
    private var prompterPanel: some View {
        VStack(spacing: 12) {
            switch phase {
            case .intro:     introPanel
            case .listening: listeningPanel
            case .preparing: preparingPanel
            case .reading:   readingPanel
            case .finished:  finishedPanel
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
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
            // Says what the run IS before anything else: the whole
            // conversation again, with the learner's part spoken right. It
            // is not a list of fixes — an uncorrected turn is read as said.
            Text(bothSides
                 ? (source.kind == "scene"
                    ? explain("Do this scene again from the start, and say every line out loud, yours and the other side's.")
                    : explain("Do this talk again from the start, and say every line out loud: yours the corrected way, and your fluent self's too."))
                 : source.kind == "scene"
                 ? explain("Do this scene again from the start, and say your part out loud. The other side plays just as it did.")
                 : explain("Do this talk again from the start, and say your part the corrected way. The answers play just as they did."))
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
                    introSeen = true      // shown once; from here it opens straight into the run
                    start(from: 0)
                } label: {
                    Label("Start", systemImage: "text.viewfinder")
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .accentProminent()
                .controlSize(.large)
            }
        }
    }

    /// A line whose rewrite hasn't landed yet. Shown instead of the line as
    /// it was said, which would be read and then replaced.
    private var preparingPanel: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Getting your line ready…").font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
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

    /// The teleprompter. A card washed in the learner's own Futureself colour
    /// with the line in a deep shade of the same hue (tone-on-tone), so it
    /// reads as a script held up in front of them rather than one more row
    /// of the grey transcript above it. There is no "done" button: the take ends on
    /// its own when they go quiet (`waitForReadToEnd`), the same way a call
    /// turn does, so a button would only ask them to confirm what the mic
    /// already knows. Skip stays, small, for a line they don't want to say.
    @ViewBuilder
    private var readingPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                // The dot is the mic: dim while the room is quiet, lit and
                // swelling with the learner's voice, so they can see the
                // line is hearing them (founder, 2026-10-23 — it used to
                // pulse on a timer and said nothing).
                let heard = CGFloat(min(1, max(0, (live.level - 0.05) / 0.35)))
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .opacity(0.3 + 0.7 * heard)
                    .scaleEffect(1 + 0.6 * heard)
                    .animation(.easeOut(duration: 0.12), value: heard)
                Group {
                    if promptStep?.isOtherSide == true {
                        Text("Say \(source.otherName)'s line")
                    } else {
                        Text(promptStep?.isCorrected == true ? "Say it the fixed way" : "Say your line")
                    }
                }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.ink.opacity(0.7))
                Spacer()
                Button("Skip") { skipRequested = true }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink.opacity(0.7))
            }
            if let step = promptStep {
                // A long turn (a minute of talking re-said whole) is taller
                // than the screen, and a bar attached under the page can't
                // scroll — so the line and its note scroll INSIDE the card,
                // capped at a share of the sheet, and the card never grows
                // past it. A short line sizes to itself as before.
                ScrollView {
                    VStack(spacing: 14) {
                        let line = litLine(step)
                        FuriganaText(line, rubyFont: .caption, alignment: .center) {
                            Text(line)
                        }
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(lineInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        if !step.note.isEmpty {
                            Text(step.note).font(.footnote).foregroundStyle(theme.ink.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
                }
                .id(step.id)      // a new line starts at its top
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
                .frame(height: lineHeight > 0 ? min(lineHeight, maxLineHeight) : nil)
            }
            // Says how the take ends, since nothing on the card does it.
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: live.level > 0.05)
                Text("Moves on when you finish")
            }
            .font(.caption)
            .foregroundStyle(theme.ink.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        // The wash sits on a blur, never straight on the transcript: the
        // bar has no background of its own (`fadingBottomBar`), so a bare
        // 14% wash let every line scrolled under it read through the script.
        .background {
            let card = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                card.fill(.regularMaterial)
                card.fill(theme.tint.opacity(washOpacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.tint.opacity(washOpacity * 2), lineWidth: 1)
        }
    }

    /// The prompter's line, coloured the way the shadow screen colours its
    /// karaoke: words already heard solid, the newest one in the accent, the
    /// rest waiting dim. A fixed word keeps the accent throughout, only
    /// dimmed until it is reached. Colour only, so nothing reflows.
    private func litLine(_ step: SayItAgainScript.Step) -> AttributedString {
        typealias Ink = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let line = step.isCorrected
            ? highlightedCorrection(step.text, original: step.said,
                                    baseFont: .title2.weight(.semibold))
            : AttributedString(step.text)
        let plain = String(line.characters)
        let reached = promptTrack?.characterCount(throughWord: spokenWords, in: plain) ?? 0
        let newest = promptTrack?.characterCount(throughWord: max(0, spokenWords - 1), in: plain) ?? 0
        let newestStart = line.characters.index(line.startIndex, offsetBy: newest)
        let end = line.characters.index(line.startIndex, offsetBy: reached)

        let ink = theme.ink
        let heard = AttributedString(line[line.startIndex..<newestStart])
            .transformingAttributes(Ink.self) { if $0.value == nil { $0.value = ink } }
        var current = AttributedString(line[newestStart..<end])
        current.foregroundColor = Color.themeAccent
        let waiting = AttributedString(line[end..<line.endIndex])
            .transformingAttributes(Ink.self) {
                $0.value = ($0.value == nil ? ink : Color.themeAccent).opacity(0.45)
            }
        return heard + current + waiting
    }

    /// Move the lit part on to what the recognizer has heard. Forward only:
    /// its newest words get rewritten a moment later, and a highlight that
    /// steps back reads as the app un-hearing them.
    private func followVoice(_ heard: String) {
        guard phase == .reading, let track = promptTrack else { return }
        var next = min(track.advance(current: spokenWords, heard: heard), track.words.count)
        if next == 0, track.opensWithFirstWord(heard) { next = 1 }
        if next > spokenWords { spokenWords = next }
    }

    private var quietToEndTake: TimeInterval {
        guard let track = promptTrack, !track.words.isEmpty else { return Self.nearEndQuiet }
        let read = Double(spokenWords) / Double(track.words.count)
        return read >= Self.nearEndShare ? Self.nearEndQuiet : Self.midLineQuiet
    }

    private var lineIsRead: Bool {
        guard let track = promptTrack, !track.words.isEmpty else { return false }
        return spokenWords >= track.words.count
    }

    /// One frame for the screen to draw before the mic opens, which holds the
    /// main thread for a moment.
    private func letScreenDraw() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    /// How tall the prompter's line may get before it scrolls: enough for
    /// a few sentences at title size, while the transcript keeps the rest.
    private var maxLineHeight: CGFloat {
        pageHeight > 0 ? max(140, pageHeight * 0.38) : 280
    }

    private var theme: FutureselfTheme { FutureselfTheme(rawValue: storedTheme) ?? .blue }
    /// Mono's accent IS its ink (charcoal / light grey), so the fixed words
    /// — drawn in the accent — would vanish into the line. There the rest of
    /// the line steps back to grey and the fix stays at full strength.
    /// Mono's light accent is near-black charcoal, so the colours' 14% wash
    /// comes out a muddy mid-grey there; it gets a paper-light 5% instead.
    private var washOpacity: Double {
        theme == .mono && colorScheme == .light ? 0.05 : 0.14
    }
    private var lineInk: Color { theme == .mono ? theme.ink.opacity(0.55) : theme.ink }

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
                .accentProminent()
            }
            .buttonRowFitsOneLine()
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
        // One row per run begun, so a start with no `say_again_run` after it
        // is a run left halfway — the only way the console can tell "tried
        // it" from "finished it". Retries don't come through here.
        if i == 0 {
            Telemetry.log("say_again_start", [
                "kind": source.kind,
                "lines": "\(spokenCount)",
                "both": bothSides ? "1" : "0",
            ])
        }
        stopRun()
        runTask = Task { @MainActor in await run(from: i) }
    }

    /// Cancel the run and end its take HERE, synchronously, before anything
    /// new starts — a cancelled read no longer ends it on its own. The mic
    /// itself stays open for whatever starts next.
    private func stopRun() {
        runTask?.cancel()
        player.stop()
        live.finishTake()
        _ = recorder.stop()
    }

    /// One mic for the whole run (2026-11-09, founder: the first sound lost,
    /// and the next line late). Opened per line, the two traded off: the line
    /// shown first cost the first sound, the mic first cost the wait, and
    /// earphones changed profile twice a line. Run-long, like a call, the
    /// answers play over it and a take costs only a new recognition.
    ///
    /// The choices are `ShadowDrillView`'s: the learner's own mic preference
    /// stands, and voice processing is on so a room can't hold a take open.
    private func openMicIfNeeded() throws {
        if live.isRunning, live.isEngineRunning { return }
        // An interruption or a route change stopped the engine under it.
        if live.isRunning { live.stop() }
        try live.start(locale: source.targetLanguage,
                       preferBuiltInMic: MicPreferenceStore.forcesBuiltInMic,
                       measurementMode: false,
                       voiceProcessing: true,
                       keepsOtherAudioLoud: true)
    }

    /// Off the main thread: a full `stop()` spends ~200 ms winding down voice
    /// processing.
    private func closeMic() {
        _ = live.stopAndFinalizeInBackground(timeout: 0.1) { _ in }
    }

    /// Walk the script. Every step awaits its own end, so the loop IS the
    /// pacing — there is no timer anywhere on this screen.
    private func run(from start: Int) async {
        oneOffRetry = false
        // Leave the intro BEFORE the mic question, not after it: on a run
        // that started by itself the learner never asked for that screen,
        // and it would sit behind the sheet as the thing they came to skip.
        if steps.indices.contains(start) {
            index = start
            let waits = steps[start].isSpoken && !rewritesDone && !stoppedWaiting
            if steps[start].isSpoken, !waits { promptStep = steps[start] }
            phase = waits ? .preparing : steps[start].isSpoken ? .reading : .listening
        }
        await askMicChoiceIfNeeded()
        await letScreenDraw()
        guard !Task.isCancelled else { return }
        // A failure here is said by the first line that needs the mic.
        try? openMicIfNeeded()
        var i = start
        while !Task.isCancelled, i < steps.count {
            index = i
            if steps[i].isSpoken { await waitForRewrites() }
            guard !Task.isCancelled else { return }
            let step = steps[i]
            if step.isSpoken { await readStep(step) } else { await listenStep(step) }
            guard !Task.isCancelled else { return }
            i += 1
        }
        guard !Task.isCancelled else { return }
        closeMic()
        index = max(0, steps.count - 1)
        phase = .finished
        ActivityEventLog.shared.record(.sayItAgain)
        Telemetry.log("say_again_run", [
            "kind": source.kind,
            "both": bothSides ? "1" : "0",
            "lines": "\(spokenCount)",
            "read": "\(readCount)",
            "avg": averageScore.map(String.init) ?? "",
        ])
    }

    /// The fluent self's answer — the audio that call already produced, never
    /// a new synthesis. A turn whose recording didn't survive is READ
    /// instead: the line is on screen, so the pause is all that's missing.
    private func listenStep(_ step: SayItAgainScript.Step) async {
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
            // Over the open mic when there is one: nothing about the session
            // changes between a line and its answer.
            try player.play(data, source: "say_again", configureSession: !live.isRunning,
                            forceSessionReset: reset) {
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
    private func readStep(_ step: SayItAgainScript.Step) async {
        spokenWords = 0
        skipRequested = false
        takes[step.id] = nil
        scoreTasks[step.id]?.cancel()
        player.stop()

        do {
            try openMicIfNeeded()
        } catch {
            micError = error.localizedDescription
            takes[step.id] = Take(outcome: .skipped)
            return
        }
        // Bias the recognizer toward the line being read (its text is only
        // the FALLBACK for the score).
        live.beginTake(contextualStrings: ShadowDrillView.recognitionHints(for: step.text))
        let url = try? recorder.startOnOpenSession(quality: .sttOptimal)
        justRecorded = true

        // The line is the signal to start, so it goes up only now, with the
        // recognizer and the file already running.
        promptTrack = SpeechPrompterTrack(script: step.text, language: source.targetLanguage)
        promptStep = step
        phase = .reading

        let spoke = await waitForReadToEnd(text: step.text)

        // A cancelled read leaves the mic alone. Whoever cancelled it
        // (a restart, a retry, "Read both sides", Close) has already
        // stopped it and may have started the NEXT read on the same
        // recognizer by the time this task wakes — stopping here killed
        // that read's mic, and with nothing ever heard the line waited
        // forever ("말을 해도 넘어가질 않네", 2026-10-23).
        guard !Task.isCancelled else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }

        // Tail grace — a clipped tail reads as a deletion in the diff. Not
        // needed once the last word has been heard and the quiet after it.
        if !lineIsRead {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else {
                if let url { try? FileManager.default.removeItem(at: url) }
                return
            }
        }
        let liveText = live.finishTake()
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
    /// word, then for a silence as long as where they are in the line asks.
    private func waitForReadToEnd(text: String) async -> Bool {
        // The line WAITS for them (2026-10-05, founder: "it keeps moving on
        // when I haven't said anything"). It used to give up after 8 s and
        // play the next answer, so a learner who looked away came back to a
        // conversation that had gone on without them. Only Skip (or Close)
        // moves past a line nobody has started to say.
        //
        // A word of the line heard counts as a start too (the level meter
        // alone reads nothing from a phone at arm's length, the same thing
        // that broke the speech take on 2026-11-03).
        //
        // With the mic open through the answer, the first moments can be that
        // answer still ringing in the room, which is not the learner starting.
        let answerRingsUntil = Date().addingTimeInterval(Self.answerRingSeconds)
        while !Task.isCancelled, !skipRequested, spokenWords == 0,
              (live.lastVoicedAt.map { $0 <= answerRingsUntil } ?? true) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled, !skipRequested else { return false }

        let lineMs = max(1200, WordSplitter.count(text) * Self.readMsPerWord)
        let began = Date()
        // Only silence ends a take. The line's length used to be a hard
        // stop too (`attemptCutoffMs`, ~1.5x the estimate), and a whole turn
        // read for the first time runs past 380 ms a word easily, so the take
        // was cut mid-sentence while the learner was still reading. Now a
        // take that is still voiced keeps going, the way a call's listening
        // ceiling does, up to `maxReadSeconds` — a room that never goes quiet
        // must still end.
        let hardStop = began.addingTimeInterval(
            max(Self.maxReadSeconds, Double(lineMs) / 1000 * Self.maxReadLineFactor))
        var lineReadAt: Date?
        while !Task.isCancelled, !skipRequested, Date() < hardStop {
            // The script's last word has been heard: nothing is left to wait
            // for but the end of the sound.
            if lineIsRead {
                let now = Date()
                if lineReadAt == nil { lineReadAt = now }
                let soundEnded = live.lastVoicedAt.map {
                    now.timeIntervalSince($0) >= Self.lineReadQuiet
                } ?? true
                if soundEnded || now.timeIntervalSince(lineReadAt ?? now) >= Self.lineReadCeiling {
                    break
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
                continue
            }
            // Near the end "quiet" is the shadow surface's 1.5 s, not a call's
            // 0.6 s: a mid-sentence breath runs up to 1.5 s, and someone
            // reading a line for the first time breathes more than a talker
            // does. Further back it is longer still (`quietToEndTake`).
            // Two witnesses, and BOTH must say quiet (2026-10-27, learner:
            // "on a long line it moves on while I'm still talking"): loudness
            // alone dips under the bar when a long read trails off or the
            // room is loud, while the recognizer is still writing their words.
            let still = quietToEndTake
            let energyQuiet = live.lastVoicedAt.map {
                Date().timeIntervalSince($0) >= still
            } ?? true
            let wordsQuiet = live.lastLivePartialAt.map {
                Date().timeIntervalSince($0) >= still
            } ?? true
            if energyQuiet, wordsQuiet { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return !skipRequested
    }

    /// Grade the take — the one door (`ShadowTranscriber`), the one engine
    /// (`ShadowEngine`). No coach call: a run is twenty lines, and a bullet
    /// per line is twenty Gemini calls for text nobody reads mid-run. The
    /// full drill, coach and all, stays one tap away from the book.
    private func score(step: SayItAgainScript.Step, url: URL?, liveText: String) async {
        let reading = await ShadowTranscriber.read(
            audioURL: url,
            liveText: liveText,
            targetLanguage: source.targetLanguage,
            recognitionHints: ShadowDrillView.recognitionHints(for: step.text),
            referenceText: step.text)
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
            fix: "",
            assessment: reading.pronunciation))
    }

    /// Flip "Read both sides". The script changes under the run, so a run
    /// under way starts over from the first line; on the intro it only
    /// changes what Start will run.
    private func setBothSides(_ on: Bool) {
        guard on != bothSides else { return }
        bothSides = on
        let base = steps.map { step -> SayItAgainScript.Step in
            guard step.isOtherSide else { return step }
            return SayItAgainScript.Step(id: step.id, isSpoken: false, text: step.text,
                                         said: "", note: "", attemptId: nil)
        }
        stopRun()
        for task in scoreTasks.values { task.cancel() }
        scoreTasks.removeAll()
        takes.removeAll()
        steps = Self.arranged(base, kind: source.kind, bothSides: on)
        if phase != .intro { start(from: 0) }
    }

    /// Re-read one line. Mid-run it rejoins the script there — the answer
    /// after it plays again, which is the conversation. On the finished
    /// screen it is a single take and the page stays where it is.
    private func retry(_ step: SayItAgainScript.Step) {
        guard let i = steps.firstIndex(where: { $0.id == step.id }) else { return }
        let wasFinished = phase == .finished
        stopRun()
        takes[step.id] = nil
        runTask = Task { @MainActor in
            if wasFinished {
                oneOffRetry = true
                await readStep(step)
                guard !Task.isCancelled else { return }
                closeMic()
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
        guard let stage = DebugCapture.sayItAgainStage, !steps.isEmpty else { return }
        let spoken = steps.enumerated().filter { $0.element.isSpoken }
        switch stage {
        case "reading":
            guard let (i, step) = spoken.first else { return }
            index = i
            promptStep = step
            let track = SpeechPrompterTrack(script: step.text, language: source.targetLanguage)
            promptTrack = track
            spokenWords = (track.words.count + 1) / 2
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
    // MARK: - Rewrites the call never made

    /// Ask for the learner turns the call left with no whole-turn rewrite.
    /// Runs while the first answers play; each finished batch is applied to
    /// every line not yet read, so a line is never swapped under the learner.
    private func startRewritesIfNeeded() {
        guard fillTask == nil, let session = source.session else { return }
        rewritesDone = false
        let native = appState.nativeLanguage
        let level = appState.proficiency
        fillTask = Task { @MainActor in
            await SayItAgainRewrites.shared.fill(session: session,
                                                 nativeLanguage: native, level: level)
            applyRewrites(session: session)
            rewritesDone = true
        }
    }

    /// Rebuild the script with the new rewrites and take every line from the
    /// one not yet read onward. The step ids are the turn ids, so the two
    /// scripts line up exactly; if they somehow don't, the run keeps the
    /// one it has.
    private func applyRewrites(session: Session) {
        let rebuilt = Self.arranged(SayItAgainScript.build(session: session,
                                                           rewrites: SayItAgainRewrites.shared.all),
                                    kind: source.kind, bothSides: bothSides)
        guard rebuilt.map(\.id) == steps.map(\.id) else { return }
        let from: Int
        switch phase {
        case .intro, .preparing: from = phase == .intro ? 0 : index
        case .listening:         from = index
        case .reading, .finished: from = index + 1
        }
        guard from < steps.count else { return }
        steps = Array(steps.prefix(from)) + rebuilt.dropFirst(from)
    }

    /// Hold a learner line until the rewrites have landed — or until
    /// `rewriteWait` has passed, after which the line is read as it is.
    private func waitForRewrites() async {
        guard !rewritesDone, !stoppedWaiting else { return }
        phase = .preparing
        let deadline = Date().addingTimeInterval(Self.rewriteWait)
        while !rewritesDone, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if !rewritesDone { stoppedWaiting = true }
    }

    private func tearDown() {
        fillTask?.cancel()
        runTask?.cancel()
        runTask = nil
        for task in scoreTasks.values { task.cancel() }
        scoreTasks.removeAll()
        player.stop()
        _ = live.stop()
        _ = recorder.stop()
    }
}
