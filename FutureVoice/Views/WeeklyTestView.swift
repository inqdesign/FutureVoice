import SwiftUI

/// The weekly test — one sheet, three states: building, playing, result.
///
/// Playing is one item at a time: a caption saying what to do, the prompt,
/// the answer area, and a bottom bar that grades and moves on. Every answer
/// gets a sound (`SoundEffects`) and a haptic (`HapticEngine`) the moment it
/// lands, a run of right answers shows as a flame, and the whole thing stays
/// on system controls — buttons, a progress bar, a gauge. No invented chrome.
///
/// Answers are saved as they happen, so closing the sheet mid-test resumes
/// where it stopped; a finished test writes itself into the review loop
/// once (`WeeklyTestEngine.apply`).
struct WeeklyTestView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = WeeklyTestSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @StateObject private var recorder = AudioRecorder()

    /// The speak item's own little machine.
    private enum SpeakPhase: Equatable { case idle, recording, reading, heardNothing, micOff }
    @State private var speakPhase: SpeakPhase = .idle
    @State private var speakTranscript: String?
    @State private var speakScore: Int?
    @State private var recordingURL: URL?
    @State private var autoStopTask: Task<Void, Never>?
    /// "Hear it" is fetching the line in the learner's voice.
    @State private var loadingLineAudio = false
    /// Longest a take may run before it stops itself.
    static let maxRecordSeconds: Double = 12
    /// A second go at this test's misses, played here and never saved: it is
    /// practice on the spot, not a second result.
    @State private var retry: WeeklyTest?

    private enum Phase {
        case loading
        case thin
        case playing(WeeklyTest)
        case result(WeeklyTest)
    }
    @State private var phase: Phase = .loading
    /// The item on screen. Separate from `test.nextItem`, which already
    /// points past it once the answer is saved.
    @State private var current: WeeklyTestItem?
    @State private var chosen: String?
    /// build: indices into `item.options`, in the order laid.
    @State private var laid: [Int] = []
    /// Where the next tile goes: an insertion index into `laid`, 0…count.
    /// Tapping a placed tile puts the cursor right after it, so a word can be
    /// slipped into the middle without unlaying everything behind it (user,
    /// 2026-09-24); tapping that same tile again removes it.
    @State private var cursor = 0
    /// nil until graded.
    @State private var outcome: Bool?
    @State private var streak = 0
    /// Wrong answers in a row — the second one makes the host pout.
    @State private var wrongRun = 0
    /// When the host's mood last changed — its bounce and blink run from here.
    @State private var moodSince = Date()

    private var mood: WeeklyTestCharacter.Mood {
        switch outcome {
        case .none: .waiting
        case .some(true): .happy
        case .some(false): wrongRun >= 2 ? .angry : .sad
        }
    }


    var body: some View {
        bodyContent
            // A parked voice (see `VoiceParking`) can't make new audio;
            // the answer to the tap is the paywall, not a dead button.
            .sheet(isPresented: $parkedPaywall) { PaywallView(source: "weekly_test_audio") }
    }

    @State private var parkedPaywall = false

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 16) {
                        WeeklyTestCharacter(mood: .thinking, since: moodSince)
                        Text("Making your test…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .thin:
                    thinState
                case let .playing(test):
                    if let item = current {
                        playing(test, item: item)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case let .result(test):
                    WeeklyTestResultView(test: test, isRetry: retry != nil, onRetry: { startRetry(from: test) })
                }
            }
            .navigationTitle(Text("Weekly test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(outcome == nil && current != nil && (!laid.isEmpty || speakPhase == .recording))
        .task { await start() }
        .onDisappear {
            player.stop()
            autoStopTask?.cancel()
            if recorder.isRecording { _ = recorder.stop() }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var thinState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("A talk or two first", systemImage: "calendar.badge.clock")
            } description: {
                Text(explain("The test is made from your week's talks. After the next one, it writes itself."))
            }
            Button {
                Task { await buildNew() }
            } label: {
                Text("Try again")
            }
            .buttonStyle(.bordered)
        }
    }

    private func playing(_ test: WeeklyTest, item: WeeklyTestItem) -> some View {
        VStack(spacing: 0) {
            // The host alone at the top; the count and the run ride on the
            // question's own line below, so nothing sits above the face.
            WeeklyTestCharacter(mood: mood, since: moodSince)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .onChange(of: mood) { _, _ in moodSince = Date() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        caption(for: item.kind)
                        if item.isRetake == true {
                            // Came back from an earlier miss.
                            Text("Again")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        progressLabel(test)
                    }
                    prompt(item)
                    answerArea(item)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            bottomBar(test, item: item)
        }
    }

    /// "3/12" on the question's caption line. A bar above the host was tried
    /// and pulled (it read as a frame over the face); a run-of-right-answers
    /// flame was tried and pulled too (user, 2026-09-23: a combo is a game
    /// scoreboard, and this is a look back at the week).
    private func progressLabel(_ test: WeeklyTest) -> some View {
        Text("\(min(test.answers.count + 1, test.total))/\(test.total)")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .accessibilityIdentifier("weeklyTest.progress")
    }

    @ViewBuilder
    private func caption(for kind: WeeklyTestItem.Kind) -> some View {
        Group {
            switch kind {
            case .meaning: Label("Which word means this?", systemImage: "text.book.closed.fill")
            case .gap:     Label("Fill the blank", systemImage: "quote.bubble.fill")
            case .build:   Label("Fix the sentence", systemImage: "rectangle.stack")
            case .listen:  Label("Listen and build it", systemImage: "ear")
            case .speak:   Label("Say it out loud", systemImage: "waveform.badge.mic")
            case .grammar: Label("A mistake you keep making", systemImage: "arrow.triangle.2.circlepath")
            case .upgrade: Label("A better word", systemImage: "arrow.up.circle")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    // MARK: - Prompt

    @ViewBuilder
    private func prompt(_ item: WeeklyTestItem) -> some View {
        switch item.kind {
        case .meaning:
            Text(item.prompt)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        case .gap:
            gapSentence(item)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
        case .build:
            VStack(alignment: .leading, spacing: 6) {
                Text("You said")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\u{201C}\(item.prompt)\u{201D}")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .grammar:
            VStack(alignment: .leading, spacing: 12) {
                if let rule = item.rule, !rule.isEmpty {
                    Text(rule)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("You said")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    (Text("\u{201C}") + marked(item.prompt, focus: item.focus) + Text("\u{201D}"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .upgrade:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You said")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    (Text("\u{201C}") + marked(item.prompt, focus: item.focus) + Text("\u{201D}"))
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let focus = item.focus {
                    Text("A more natural choice than \u{201C}\(focus)\u{201D}?")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Once answered: the same line with the better word, and why.
                if outcome != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let example = item.example, !example.isEmpty {
                            Text(example)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity)
                }
            }
        case .listen:
            HStack {
                Spacer()
                Button {
                    play(item)
                } label: {
                    Image(systemName: player.isPlaying ? "speaker.wave.3.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 76, height: 76)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityLabel(Text("Play the line"))
                Spacer()
            }
            .padding(.vertical, 8)
        case .speak:
            VStack(alignment: .leading, spacing: 10) {
                Text(item.answer)
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if outcome == nil, appState.voiceCloneId != nil {
                    Button {
                        Task { await hearLine(item) }
                    } label: {
                        HStack(spacing: 6) {
                            if loadingLineAudio { ProgressView().controlSize(.mini) }
                            Label("Hear it", systemImage: player.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(speakPhase == .recording || speakPhase == .reading || loadingLineAudio)
                }
            }
        }
    }

    /// `text` with the first occurrence of `focus` bold and underlined — the
    /// word or span the item is about.
    private func marked(_ text: String, focus: String?) -> Text {
        guard let focus, !focus.isEmpty,
              let range = text.range(of: focus, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text)
        }
        return Text(text[..<range.lowerBound])
            + Text(text[range]).bold().underline()
            + Text(text[range.upperBound...])
    }

    /// The gap sentence with the blank filled by the chosen phrase once one
    /// is picked, so the learner reads their answer in place.
    private func gapSentence(_ item: WeeklyTestItem) -> Text {
        let parts = item.prompt.components(separatedBy: WeeklyTestEngine.blankMark)
        guard parts.count == 2 else { return Text(item.prompt) }
        let fill: Text
        if let chosen {
            let color: Color = outcome == nil ? .accentColor : (outcome == true ? .green : .red)
            fill = Text(chosen).bold().foregroundStyle(color)
        } else {
            fill = Text(WeeklyTestEngine.blankMark).foregroundStyle(.tertiary)
        }
        return Text(parts[0]) + fill + Text(parts[1])
    }

    // MARK: - Answer area

    @ViewBuilder
    private func answerArea(_ item: WeeklyTestItem) -> some View {
        switch item.kind {
        case .meaning, .gap, .upgrade:
            VStack(spacing: 10) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                    optionButton(option, index: index, item: item)
                }
            }
        case .build, .listen, .grammar:
            buildArea(item)
        case .speak:
            speakArea(item)
        }
    }

    // MARK: - Speak

    /// One big mic button. Tap to start, tap to stop (or it stops itself at
    /// `maxRecordSeconds`); the take is read by the same door every shadow
    /// score goes through and graded against the line in code.
    private func speakArea(_ item: WeeklyTestItem) -> some View {
        VStack(spacing: 14) {
            Button {
                Task { await toggleRecording(item) }
            } label: {
                ZStack {
                    if speakPhase == .reading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: speakPhase == .recording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(.borderedProminent)
            .tint(speakPhase == .recording ? .red : .accentColor)
            .clipShape(Circle())
            .scaleEffect(speakPhase == .recording ? 1 + CGFloat(recorder.levels) * 0.12 : 1)
            .animation(.easeOut(duration: 0.08), value: recorder.levels)
            .disabled(speakPhase == .reading || outcome != nil)
            .accessibilityLabel(Text(speakPhase == .recording ? "Stop" : "Record"))

            Group {
                switch speakPhase {
                case .idle:
                    if outcome == nil { Text(explain("Tap, say the line, tap again")) }
                case .recording: Text("Tap when done")
                case .reading: Text("Listening back…")
                case .heardNothing: Text(explain("Didn't catch that. Try again."))
                case .micOff: Text(explain("Microphone is off for this app in Settings."))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let speakTranscript, outcome != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You said")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(speakTranscript)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let speakScore {
                            Text("\(speakScore)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(outcome == true ? .green : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if outcome == nil, speakPhase == .idle || speakPhase == .heardNothing || speakPhase == .micOff {
                Button {
                    skipSpeak(item)
                } label: {
                    Text("Skip").font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func toggleRecording(_ item: WeeklyTestItem) async {
        guard outcome == nil, case let .playing(test) = phase else { return }
        switch speakPhase {
        case .recording:
            await finishRecording(item, test: test)
        case .idle, .heardNothing, .micOff:
            guard await recorder.requestPermission() else { speakPhase = .micOff; return }
            player.stop()
            do {
                recordingURL = try recorder.start()
            } catch {
                speakPhase = .micOff
                return
            }
            speakPhase = .recording
            HapticEngine.countdownGo()
            autoStopTask?.cancel()
            autoStopTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.maxRecordSeconds * 1_000_000_000))
                guard !Task.isCancelled, speakPhase == .recording else { return }
                await finishRecording(item, test: test)
            }
        case .reading:
            break
        }
    }

    private func finishRecording(_ item: WeeklyTestItem, test: WeeklyTest) async {
        autoStopTask?.cancel()
        // The same tail grace the shadow screen gives: a stop tap lands
        // mid-syllable, and a clipped tail reads as a dropped word.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let url = recorder.stop() ?? recordingURL
        speakPhase = .reading
        let reading = await ShadowTranscriber.read(
            audioURL: url, liveText: "", targetLanguage: appState.targetLanguage,
            recognitionHints: ShadowDrillView.recognitionHints(for: item.answer))
        let heard = reading.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            if let url { try? FileManager.default.removeItem(at: url) }
            recordingURL = nil
            speakPhase = .heardNothing
            return
        }
        let score = ShadowEngine.analyze(target: item.answer, learner: heard,
                                         language: appState.targetLanguage).score
        speakTranscript = heard
        speakScore = score
        speakPhase = .idle
        // The take is a real shadow attempt of that line: saved, so the talk
        // book's Shadow chapter and the browser see it like any other.
        if let turnId = item.turnId {
            appState.saveShadowAttempt(ShadowAttempt(
                turnId: turnId, targetText: item.answer, learnerTranscript: heard,
                recordingFilename: url?.lastPathComponent, matchScore: score, rhythmScore: nil,
                pronunciation: "", pacing: "", fix: ""))
        }
        settle(correct: score >= WeeklyTestEngine.speakPassScore, given: heard, test: test, item: item,
               score: score)
    }

    private func skipSpeak(_ item: WeeklyTestItem) {
        guard outcome == nil, case let .playing(test) = phase else { return }
        settle(correct: false, given: "", test: test, item: item)
    }

    private func optionButton(_ option: String, index: Int, item: WeeklyTestItem) -> some View {
        let isAnswer = WeeklyTestEngine.isCorrect(item, chosen: option)
        let isChosen = chosen == option
        let graded = outcome != nil
        return Button {
            choose(option, item: item)
        } label: {
            HStack(spacing: 10) {
                Text(option)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // The verdict slot is ALWAYS laid out, so the text wraps the
                // same way before and after grading — an icon that appears
                // used to push a long option onto a second line.
                Image(systemName: graded && isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(graded && isAnswer ? .green : .red)
                    .opacity(graded && (isAnswer || isChosen) ? 1 : 0)
                    .frame(width: 22)
                    .accessibilityHidden(!(graded && (isAnswer || isChosen)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        // Not `.disabled` once graded — that greys every row, the green
        // included; `choose` already refuses a second answer.
        .tint(graded ? (isAnswer ? .green : (isChosen ? .red : .gray)) : .accentColor)
        .accessibilityIdentifier("weeklyTest.option.\(index)")
    }

    private func buildArea(_ item: WeeklyTestItem) -> some View {
        // Graded and wrong: which tiles were actually misplaced. Painting all
        // of them red says nothing when eight of nine were right.
        let check: WeeklyTestEngine.TileCheck? = outcome == false
            ? WeeklyTestEngine.tileCheck(tiles: laid.map { item.options[$0] }, answer: item.answer)
            : nil
        // A build item may carry decoys (the words the correction replaced),
        // so some tiles are meant to be left over — said up front, or a
        // leftover tile reads as a mistake or a bug (user, 2026-10-03).
        let fixes = item.kind == .build || item.kind == .grammar
        let decoys = fixes ? WeeklyTestEngine.decoyTiles(of: item) : []
        return VStack(alignment: .leading, spacing: 16) {
            if fixes, outcome == nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Write it as a correct sentence.")
                        .font(.subheadline.weight(.semibold))
                    if !decoys.isEmpty {
                        Text("Some words are traps — you don't have to use them all.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // The sentence being laid.
            FlowLayout(spacing: 8, lineSpacing: 10) {
                if outcome == nil, cursor == 0, !laid.isEmpty { caret }
                ForEach(Array(laid.enumerated()), id: \.element) { position, index in
                    tile(item.options[index], filled: true,
                         verdict: check.map { $0.correct[position] },
                         selected: outcome == nil && cursor == position + 1 && cursor < laid.count) {
                        tapPlaced(at: position)
                    }
                    if outcome == nil, cursor == position + 1, cursor < laid.count { caret }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { if outcome == nil { cursor = laid.count } }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .foregroundStyle(.tertiary)
            )
            .overlay(alignment: .topLeading) {
                if laid.isEmpty, item.kind == .listen {
                    Text("Tap the words in order")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(20)
                }
            }
            .animation(.easeOut(duration: 0.18), value: laid)

            // The tiles still on the table.
            FlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { index, word in
                    if !laid.contains(index) {
                        tile(word, filled: false, verdict: nil) { lay(index) }
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: laid)

            if outcome == nil, !laid.isEmpty {
                Text(explain("Tap a placed word to add after it. Tap it again to take it out."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Once graded, the leftover traps are named for what they are:
            // the learner's own words from before the fix.
            if outcome != nil, !decoys.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trap words — what you said before the fix")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // Right: the leftover tiles above ARE the traps, so the
                    // label is enough. Wrong: leftovers may mix in answer
                    // words, so the traps are spelled out.
                    if outcome == false {
                        Text(decoys.joined(separator: " · "))
                            .font(.footnote)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            if let outcome, !outcome {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        (item.kind == .listen ? Text("What was said") : Text("Fluent version"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        fluentAnswer(item, check: check)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The card's own reason, labelled for what it is: why this
                    // sentence was corrected in the first place, not a verdict
                    // on the order just laid.
                    if let note = item.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            (item.kind == .grammar ? Text("Tip") : Text("Why it was corrected"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// The answer, with the words the learner never placed carried in bold —
    /// the one word missing from an otherwise right sentence is the lesson.
    private func fluentAnswer(_ item: WeeklyTestItem, check: WeeklyTestEngine.TileCheck?) -> Text {
        let words = WordSplitter.words(item.answer)
        guard let check, check.answerMatched.count == words.count else {
            return Text(item.answer).foregroundStyle(.green)
        }
        let gap = WordSplitter.spaced ? " " : ""
        var out = Text("")
        for (i, word) in words.enumerated() {
            if i > 0 { out = out + Text(gap) }
            let piece = Text(word).foregroundStyle(.green)
            out = out + (check.answerMatched[i] ? piece : piece.bold().underline())
        }
        return out
    }

    /// `verdict` nil = not graded (or graded right, where the whole row is
    /// green); true = this tile sits where the answer wants it.
    private func tile(_ word: String, filled: Bool, verdict: Bool?, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.body.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(filled ? tileTint(verdict) : (outcome == nil ? .accentColor : .gray))
        // The tile the cursor follows wears a ring; a style can't be
        // switched in a ternary, and a ring reads as "selected" either way.
        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
    }

    /// The insertion point, drawn between placed tiles when it isn't at the end.
    private var caret: some View {
        // A hidden tile sets the height, so the bar sits at the tiles' own
        // centre whatever the button style pads them to; the flow layout
        // aligns its rows to the top, not the middle.
        ZStack {
            tile("I", filled: true, verdict: nil) {}
                .opacity(0)
                .allowsHitTesting(false)
            BlinkingCaret()
        }
        .frame(width: 2)
        .accessibilityHidden(true)
    }

    private func tileTint(_ verdict: Bool?) -> Color {
        switch outcome {
        case .none: return .accentColor
        case .some(true): return .green
        case .some(false): return verdict == true ? .green : .red
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private func bottomBar(_ test: WeeklyTest, item: WeeklyTestItem) -> some View {
        VStack(spacing: 12) {
            if let outcome {
                HStack(spacing: 10) {
                    Image(systemName: outcome ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(outcome ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome ? "Right" : "Not this time")
                            .font(.subheadline.weight(.semibold))
                        if !outcome, item.kind != .build, item.kind != .listen, item.kind != .grammar {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .bottom).combined(with: .opacity))

                Button {
                    advance(test)
                } label: {
                    Text(test.nextItem == nil ? "See result" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(outcome ? .green : .accentColor)
                .accessibilityIdentifier("weeklyTest.continue")
            } else if item.kind == .build || item.kind == .listen || item.kind == .grammar {
                Button {
                    checkBuild(item, test: test)
                } label: {
                    Text("Check").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(laid.isEmpty)
                .accessibilityIdentifier("weeklyTest.check")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .animation(.easeOut(duration: 0.22), value: outcome)
    }

    // MARK: - Flow

    private func start() async {
        let tests = WeeklyTestStore.shared.load()
        #if DEBUG
        // A capture run asks for a specific kind: always deal a fresh paper.
        if DebugCapture.weeklyTestKind != nil { await buildNew(); return }
        #endif
        switch settings.schedule.state(tests: tests, settings: settings) {
        case let .inProgress(test):
            // A paper built under older rules may carry an item today's
            // rules refuse; drop what hasn't been answered yet.
            if let cleaned = WeeklyTestEngine.pruned(test) {
                WeeklyTestStore.shared.save(cleaned)
                resume(cleaned)
            } else {
                resume(test)
            }
        case let .done(test, _):
            phase = .result(test)
        case .ready, .thin:
            await buildNew()
        }
    }

    private func buildNew() async {
        phase = .loading
        let tests = WeeklyTestStore.shared.load()
        let opening = settings.schedule.currentOpening()
        guard var test = await WeeklyTestEngine.build(lastTest: WeeklyTestStore.latestWeekly(tests),
                                                      recentTests: tests,
                                                      appState: appState) else {
            settings.markThin(opening: opening)
            phase = .thin
            return
        }
        settings.clearThin()
        #if DEBUG
        if let kind = DebugCapture.weeklyTestKind,
           let first = test.items.firstIndex(where: { $0.kind == kind }) {
            test.items.swapAt(0, first)
        }
        #endif
        test.startedAt = Date()
        WeeklyTestStore.shared.save(test)
        Analytics.capture("weekly_test_started", ["items": test.total])
        resume(test)
        #if DEBUG
        if let right = DebugCapture.weeklyTestAnswer, let item = current {
            streak = 2   // so the flame is in the shot too
            if item.kind == .build || item.kind == .grammar {
                let answer = WordSplitter.words(item.answer).map(WeeklyTestEngine.tileKey)
                var order = answer.compactMap { key in
                    item.options.indices.first { WeeklyTestEngine.tileKey(item.options[$0]) == key && !laid.contains($0) }
                        .map { i in laid.append(i); return i }
                }
                if !right { order.swapAt(0, order.count - 1); laid = order }
                checkBuild(item, test: test)
            } else {
                let pick = right ? item.answer : (item.options.first { !WeeklyTestEngine.isCorrect(item, chosen: $0) } ?? item.answer)
                choose(pick, item: item)
            }
        }
        #endif
    }

    private func resume(_ test: WeeklyTest) {
        // The run the learner left off on, so the flame doesn't reset for
        // having closed the sheet.
        var run = 0
        for answer in test.answers.reversed() {
            guard answer.correct else { break }
            run += 1
        }
        streak = run
        current = test.nextItem
        chosen = nil
        laid = []
        cursor = 0
        outcome = nil
        phase = .playing(test)
        if current == nil { finish(test) }
    }

    private func choose(_ option: String, item: WeeklyTestItem) {
        guard outcome == nil, case let .playing(test) = phase else { return }
        chosen = option
        SoundEffects.play(.tap)
        settle(correct: WeeklyTestEngine.isCorrect(item, chosen: option), given: option,
               test: test, item: item)
    }

    private func lay(_ index: Int) {
        guard outcome == nil else { return }
        let at = min(max(cursor, 0), laid.count)
        laid.insert(index, at: at)
        cursor = at + 1
        SoundEffects.play(.tap)
        HapticEngine.selection()
    }

    /// First tap on a placed tile moves the cursor after it; a second tap on
    /// the tile the cursor already follows takes it out.
    private func tapPlaced(at position: Int) {
        guard outcome == nil, laid.indices.contains(position) else { return }
        if cursor == position + 1 && cursor < laid.count {
            laid.remove(at: position)
            cursor = position
        } else if cursor == position + 1 {
            // Cursor at the end sits after the last tile; tapping the last
            // tile there is a removal too.
            laid.remove(at: position)
            cursor = laid.count
        } else {
            cursor = position + 1
        }
        SoundEffects.play(.tap)
        HapticEngine.selection()
    }

    private func checkBuild(_ item: WeeklyTestItem, test: WeeklyTest) {
        let tiles = laid.map { item.options[$0] }
        settle(correct: WeeklyTestEngine.isCorrect(item, tiles: tiles),
               given: WeeklyTestEngine.sentence(fromTiles: tiles), test: test, item: item)
    }

    private func settle(correct: Bool, given: String, test: WeeklyTest, item: WeeklyTestItem,
                        score: Int? = nil) {
        outcome = correct
        var t = test
        t.answers.append(WeeklyTestAnswer(itemId: item.id, given: given, correct: correct, at: Date(),
                                          score: score))
        streak = correct ? streak + 1 : 0
        wrongRun = correct ? 0 : wrongRun + 1
        t.bestStreak = max(t.bestStreak, streak)
        if retry != nil { retry = t } else { WeeklyTestStore.shared.save(t) }
        phase = .playing(t)
        if correct {
            SoundEffects.play(.right)
            HapticEngine.drillCorrect()
        } else {
            SoundEffects.play(.wrong)
            HapticEngine.drillIncorrect()
        }
    }

    private func advance(_ test: WeeklyTest) {
        player.stop()
        chosen = nil
        laid = []
        cursor = 0
        outcome = nil
        speakPhase = .idle
        speakTranscript = nil
        speakScore = nil
        recordingURL = nil
        if let next = test.nextItem {
            current = next
        } else {
            finish(test)
        }
    }

    private func finish(_ test: WeeklyTest) {
        var t = test
        if retry != nil {
            // Practice only: nothing saved, nothing written to the loop.
            t.finishedAt = Date()
            retry = t
            current = nil
            phase = .result(t)
            SoundEffects.play(.done)
            HapticEngine.success()
            return
        }
        if t.finishedAt == nil { t.finishedAt = Date() }
        if t.appliedAt == nil {
            WeeklyTestEngine.apply(t)
            t.appliedAt = Date()
            Analytics.capture("weekly_test_finished", [
                "score": t.score, "total": t.total, "best_streak": t.bestStreak,
            ])
            SoundEffects.play(.done)
            HapticEngine.success()
        }
        WeeklyTestStore.shared.save(t)
        current = nil
        phase = .result(t)
        Task { await DrillReminder.reschedule() }
    }

    /// Deal this test's misses again, right now.
    private func startRetry(from test: WeeklyTest) {
        guard let paper = WeeklyTestEngine.retryPaper(from: test) else { return }
        retry = paper
        wrongRun = 0
        resume(paper)
    }

    /// The transcript of the turn with this id, if a talk still has it.
    private static func turnText(_ turnId: UUID) -> String? {
        for session in SessionStore.shared.load() {
            if let turn = session.turns.first(where: { $0.id == turnId }) { return turn.transcript }
        }
        return nil
    }

    /// A listen item plays the turn's own recording: the text IS the turn.
    private func play(_ item: WeeklyTestItem) {
        guard let turnId = item.turnId, let data = TurnAudioStore.shared.data(for: turnId) else { return }
        if player.isPlaying { player.stop(); return }
        try? player.play(data, source: "weekly_test", forceSessionReset: true)
    }

    /// A speak item's line, exactly and only that line, in the learner's own
    /// voice — resolved the way the shadow screen does: the line's own saved
    /// audio, else the phrase cache, else one synthesis that both caches
    /// keep. A sentence cut from a longer turn never plays the turn's file:
    /// its audio has the neighbouring sentences in it.
    private func hearLine(_ item: WeeklyTestItem) async {
        if player.isPlaying { player.stop(); return }
        guard let voiceId = appState.voiceCloneId else { return }
        // The saved file is only the line when the turn IS the line. Items
        // minted before sentence ids existed carry the whole turn's id, and
        // its file has the neighbouring sentences in it — so the text is
        // checked, never trusted by id alone.
        if let turnId = item.turnId, let data = TurnAudioStore.shared.data(for: turnId),
           Self.turnText(turnId).map({ CarryoverDetector.normalized($0) }) == CarryoverDetector.normalized(item.answer) {
            try? player.play(data, source: "weekly_test", forceSessionReset: true)
            return
        }
        if let data = PhraseAudioStore.shared.data(text: item.answer, voiceId: voiceId) {
            try? player.play(data, source: "weekly_test", forceSessionReset: true)
            return
        }
        loadingLineAudio = true
        defer { loadingLineAudio = false }
        do {
            let (data, timings) = try await ElevenLabsClient.shared
                .synthesizeWithTimestamps(voiceId: voiceId, text: item.answer, purpose: "shadow")
            PhraseAudioStore.shared.save(data, text: item.answer, voiceId: voiceId, timings: timings)
            if let turnId = item.turnId {
                TurnAudioStore.shared.save(data, turnId: turnId, timings: timings)
            }
            try? player.play(data, source: "weekly_test", forceSessionReset: true)
        } catch {
            // Offline or out of allowance: the line is still on screen to read.
            if error.isOutOfCredits { parkedPaywall = true }
        }
    }
}

// MARK: - Result

/// The finished test: the host, one line of praise, the score against last
/// week's, then what was missed — which is the only list worth reading,
/// because it is what comes back in review. A per-question list and per-kind
/// rows were shipped and pulled (user, 2026-09-23). Two exits: try the
/// misses again on the spot, or leave them to the decks.
struct WeeklyTestResultView: View {
    let test: WeeklyTest
    /// A second go at the misses: practice, not a result — no praise
    /// comparison, no "back in review" claims.
    var isRetry: Bool = false
    var onRetry: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var shownAt = Date()

    private var ratio: Double { test.total == 0 ? 0 : Double(test.score) / Double(test.total) }

    private var weeks: Int {
        WeeklyTestStore.weekStreak(tests: WeeklyTestStore.shared.load(),
                                   schedule: WeeklyTestSettings.shared.schedule)
    }

    private var missed: [WeeklyTestItem] {
        let wrong = Set(test.answers.filter { !$0.correct }.map(\.itemId))
        return test.items.filter { wrong.contains($0.id) }
    }

    /// The weekly test before this one, for the one line of comparison.
    private var previous: WeeklyTest? {
        guard !test.isMonthly, !isRetry else { return nil }
        return WeeklyTestStore.shared.load()
            .first { !$0.isMonthly && $0.isFinished && $0.id != test.id && $0.createdAt < test.createdAt }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    WeeklyTestCharacter(mood: ratio >= 0.8 ? .happy : .waiting, since: shownAt,
                                        tile: Color(.secondarySystemGroupedBackground))
                    VStack(spacing: 4) {
                        headline
                            .font(.title2.weight(.semibold))
                        Text("\(test.score) of \(test.total)")
                            .foregroundStyle(.secondary)
                        if let previous {
                            Text("Last week \(previous.score)/\(previous.total)")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        if !isRetry, weeks >= 2 {
                            Label("\(weeks) weeks running", systemImage: "calendar")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if missed.isEmpty {
                Section {
                    Label(isRetry ? "All of them, this time" : "Nothing missed", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } footer: {
                    if !isRetry { Text(explain("Everything here waits three days before it comes back.")) }
                }
            } else {
                Section {
                    ForEach(missed) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            kindIcon(item.kind)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.answer)
                                    .fixedSize(horizontal: false, vertical: true)
                                if [.meaning, .build, .grammar, .upgrade].contains(item.kind), !item.prompt.isEmpty {
                                    // Two `Text`s, not a String ternary — a String never localizes.
                                    (item.kind == .meaning ? Text(item.prompt) : Text("You said: \(item.prompt)"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } header: {
                    Text(isRetry ? "Still missed" : "Missed")
                } footer: {
                    if !isRetry { Text(explain("These are back in your review, due now.")) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !missed.isEmpty, let onRetry {
                Button(action: onRetry) {
                    Text("Try the missed ones again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private var headline: Text {
        if isRetry {
            return missed.isEmpty ? Text("Got them all") : Text("Closer")
        }
        switch ratio {
        case 0.9...: return Text("A strong week")
        case 0.6..<0.9: return Text("A good week")
        default: return Text("The week is in the book")
        }
    }

    private func kindIcon(_ kind: WeeklyTestItem.Kind) -> Image {
        switch kind {
        case .meaning: Image(systemName: "text.book.closed.fill")
        case .gap:     Image(systemName: "quote.bubble.fill")
        case .build:   Image(systemName: "rectangle.stack")
        case .listen:  Image(systemName: "ear")
        case .speak:   Image(systemName: "waveform.badge.mic")
        case .grammar: Image(systemName: "arrow.triangle.2.circlepath")
        case .upgrade: Image(systemName: "arrow.up.circle")
        }
    }
}


/// A text cursor: a thin bar that blinks, the way every insertion point does.
private struct BlinkingCaret: View {
    @State private var on = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 24)
            .opacity(on ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
    }
}
