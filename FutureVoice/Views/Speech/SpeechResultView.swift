import AVKit
import Combine
import Photos
import SwiftUI

/// One scored take: the overall score, the coach's notes, the recording, and
/// every measured number with what it was measured against.
struct SpeechResultView: View {
    let takeId: UUID
    /// The take as the prompter just made it — shown while the store catches
    /// up, and updated when the coach's notes land.
    var live: SpeechTake?
    /// Back to the challenge's board (the prompter closes) — from the sheet a
    /// better challenge take raises.
    var onSeeBoard: (() -> Void)? = nil

    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    /// Re-renders as a video copy lands or goes up.
    @ObservedObject private var sync = SyncEngine.shared
    @ObservedObject private var videoSync = SpeechVideoSync.shared
    @StateObject private var audio = AudioPlayer()
    /// The reader on the whole page: a few seconds looping without sound,
    /// the whole take with sound behind the play button.
    @StateObject private var hero = SpeechHeroPlayer()
    /// A take from before the camera was kept: its video has the script in it.
    @State private var watchingScriptVideo: URL?
    /// The script rolling over the camera while the take plays.
    @AppStorage("speech.replayShowsScript") private var showScript = false
    /// How the script sits in a saved video.
    @AppStorage("speech.exportStyle") private var exportStyle: SpeechVideoStyle = .fullScreen
    /// Save, send to iCloud, delete: behind the header's button.
    @State private var showingVideoOptions = false
    @State private var savedToPhotos: Set<URL> = []
    /// The video with the script, made to hand to Instagram. A temporary
    /// file, removed when the share sheet closes.
    @State private var sharedVideo: URL?
    @State private var showingShare = false
    /// A frame of the take, for the layout choices.
    @State private var layoutFrame: UIImage?
    /// How far the video with the script has been made, while it is.
    @State private var exporting: Double?
    @State private var photoError: String?
    @State private var confirmDeleteVideo = false
    /// The script with the take's misreadings marked on it, by take id.
    @State private var scriptMarks: (takeId: UUID, marks: [[SpeechAnalyzer.ScriptMark]]?)?
    /// The assessment sheet — every word and sound of the take.
    @State private var showingPronunciation = false

    private var take: SpeechTake? {
        let stored = store.takes.first { $0.id == takeId }
        if let live, stored?.coaching == nil, live.coaching != nil { return live }
        return stored ?? live
    }

    var body: some View {
        if let take, let script = store.script(id: take.scriptId) {
            page(take, script)
        } else {
            ContentUnavailableView("Take not found", systemImage: "waveform")
        }
    }

    // MARK: - The page: the reader, the score, and a sheet of details

    /// The camera on its own, for a take recorded that way.
    private func cameraVideo(_ take: SpeechTake) -> URL? {
        guard take.videoIsCameraOnly, take.videoFilename != nil else { return nil }
        return SpeechVideoSync.playableURL(take)
    }

    /// What is behind the score: the camera and nothing else (founder,
    /// 2026-11-08). A take whose video has the script burned into it has a
    /// plain ground.
    private func heroVideo(_ take: SpeechTake) -> URL? {
        guard !store.videoPending.contains(take.id) else { return nil }
        return cameraVideo(take)
    }

    private func page(_ take: SpeechTake, _ script: SpeechScript) -> some View {
        let video = heroVideo(take)
        // Playing, everything but the reader steps aside.
        let immersive = hero.isPlaying || audio.isPlaying
        let stored = take.videoFilename != nil ? SpeechVideoSync.playableURL(take) : nil
        return SpeechResultSheetPage(immersive: immersive, onTapWhilePlaying: {
            if hero.isPlaying { hero.toggle() } else { audio.stop() }
        }) {
            heroBackground(take, immersive: immersive)
        } overlay: {
            if showScript, hero.isFull, let record = take.prompter, let player = hero.player {
                // Kept while paused, unseen: drawing the column takes a moment.
                SpeechScriptOverlay(record: record, player: player, rolling: hero.isPlaying)
                    .opacity(hero.isPlaying ? 1 : 0)
            }
        } hero: {
            heroContent(take, hasVideo: video != nil)
        } playing: {
            if take.prompter != nil, hero.isFull { scriptToggle }
        } summary: {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if script.isChallenge {
                            Text("Challenge")
                            Text(verbatim: "·")
                        }
                        Text(take.createdAt, format: .dateTime.month().day().hour().minute())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                scoreStrip(take.metrics)
            }
        } details: {
            // Presented from inside: the page below already has the sheet up,
            // and a page can present only one thing at a time.
            content(take, script)
                .sheet(item: $watchingScriptVideo) { SpeechScriptVideoSheet(url: $0) }
                .sheet(isPresented: $showingVideoOptions) {
                    if let stored { videoOptions(take, url: stored) }
                }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(immersive)
        .toolbar {
            if stored != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingVideoOptions = true
                    } label: {
                        // Its tray is heavy and its arrow thin: centred by the
                        // box, it reads low in the circle. A plain button, or
                        // the bar takes the bare symbol and drops the offset.
                        Image(systemName: "square.and.arrow.down")
                            .offset(y: -2)
                            // The bar adds its own margin: this makes a circle.
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Save to Photos"))
                }
            }
        }
        .task(id: video) { await hero.show(video) }
        .task(id: take.id) { await SpeechReadingRepair.restore(take, script: script) }
        // Here, on the page: the details live in the system sheet, which goes
        // away while the take plays, and this must not stop the take.
        .onDisappear {
            hero.stop()
            audio.stop()
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "captureImmersive") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showScript = true; hero.toggle() }
                if UserDefaults.standard.bool(forKey: "capturePaused") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { hero.toggle() }
                }
            }
            if UserDefaults.standard.bool(forKey: "captureVideoOptions") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showingVideoOptions = true }
            }
        }
        #endif
    }

    private func heroBackground(_ take: SpeechTake, immersive: Bool) -> some View {
        let tint = SpeechScoreColor.color(take.metrics.overall)
        return ZStack {
            Color.black
            if let player = hero.player {
                PlayerLayerView(player: player, fill: true)
            } else {
                LinearGradient(colors: [tint.opacity(0.75), .black], startPoint: .top, endPoint: .bottom)
            }
            // Keeps the white text readable on any picture.
            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                           startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                .opacity(immersive ? 0 : 1)
        }
        .ignoresSafeArea()
    }

    private func heroContent(_ take: SpeechTake, hasVideo: Bool) -> some View {
        let m = take.metrics
        let playing = hero.isPlaying || audio.isPlaying
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(m.overall)")
                    .font(.system(size: 96, weight: .bold).monospacedDigit())
                if let r = m.reading {
                    Text(SpeechVerdict.line(total: r.total, take: take.id))
                        .font(.title2.weight(.semibold))
                    Text("\(Text(levelTitle(r.level))) level")
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            Button {
                if hasVideo {
                    preparePlayback()
                    hero.toggle()
                } else if audio.isPlaying {
                    audio.stop()
                } else {
                    playAudio(take)
                }
            } label: {
                heroPlayGlyph(playing: playing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? Text("Pause") : Text("Play"))
        }
        .foregroundStyle(.white)
    }

    /// The same glass as the sheet and the bar's button, and no drop shadow:
    /// on glass it reads as a smudge around the circle.
    @ViewBuilder
    private func heroPlayGlyph(playing: Bool) -> some View {
        let glyph = Image(systemName: playing ? "pause.fill" : "play.fill")
            .font(.system(size: 26, weight: .semibold))
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        if #available(iOS 26.0, *) {
            glyph
                .glassEffect(.regular.interactive(), in: .circle)
                .environment(\.colorScheme, .dark)
        } else {
            glyph
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
    }

    @ViewBuilder
    private func coachHeadline(_ take: SpeechTake) -> some View {
        if let coaching = take.coaching {
            Text(coaching.headline)
                .font(.body.weight(.medium))
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("Writing feedback…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func content(_ take: SpeechTake, _ script: SpeechScript) -> some View {
        let m = take.metrics
        return ScrollViewReader { proxy in List {
            Section {
                coachHeadline(take)

                if let tips = take.coaching?.tips, !tips.isEmpty {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        Label(tip, systemImage: "arrow.forward.circle")
                            .font(.subheadline)
                    }
                }
            }

            if script.isChallenge {
                SpeechChallengeEntrySection(entry: challenges.entries[take.id],
                                            standing: challenges.standings[script.id])
            }

            playbackSection(take)

            if let reading = m.reading {
                readingSections(reading, take: take, language: script.language)
                    .id("reading")
            } else if let parts = m.parts {
                seasonTwoSection(parts, take: take, language: script.language)
            } else {
                Section("Measured") {
                    metricRow("Accuracy", icon: "text.badge.checkmark",
                              value: "\(m.accuracy)%", score: m.accuracy)
                    // Measured per phoneme; a quarter of the overall since
                    // 2026-11-04 (the board's weighting is checked server-side).
                    if let pron = m.pronunciation {
                        // What stood out: this take's low SOUNDS (English), or a
                        // word low here that is low across recent takes. A word
                        // low once is not said — see `PronunciationLedger`. The
                        // whole assessment is a tap away when the take kept it.
                        let row = metricRow("Pronunciation", icon: "waveform.badge.mic",
                                            value: "\(pron)",
                                            detail: pronunciationDetail(take, language: script.language),
                                            score: pron)
                        if let all = take.assessments, !all.isEmpty {
                            Button { showingPronunciation = true } label: {
                                HStack(spacing: 6) {
                                    row
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showingPronunciation) {
                                PronunciationDetailSheet(results: all, language: script.language)
                            }
                        } else {
                            row
                        }
                    }
                    metricRow("Pace", icon: "speedometer",
                              value: SpeechFormat.rate(m.rate, language: script.language),
                              detail: explain("Comfortable: \(m.rateLow)–\(m.rateHigh)"),
                              // Outside the band is never shown as good, however
                              // close: the band IS the target.
                              score: (m.rateLow...m.rateHigh).contains(m.rate) ? 100 : min(m.paceScore, 80))
                    metricRow("Pauses", icon: "pause.circle",
                              value: explain("\(m.pausesAtBreaks) of \(m.breaks)"),
                              detail: m.hesitations > 0
                                  ? explain("Breaths at sentence ends · long stops: \(m.hesitations)")
                                  : explain("Breaths at sentence ends"),
                              score: m.pauseScore)
                    metricRow("Fillers", icon: "ellipsis.bubble",
                              value: "\(m.fillers)", score: m.fillerScore)
                    metricRow("Steady voice", icon: "waveform.path",
                              value: "\(m.steadiness)",
                              detail: explain("Holding your volume to the end of each sentence"),
                              score: m.steadiness)
                }
            }

            // The mistakes are marked where they are in the script, like a
            // teacher's red pen (2026-10-25, founder) — a list of loose
            // words gave no place to find them.
            if let marks = scriptMarks?.takeId == take.id ? scriptMarks?.marks : nil {
                let timing = m.reading.map { SpeechMarkedScript.timing($0, marks: marks) }
                Section {
                    SpeechMarkedScript(paragraphs: marks, language: script.language,
                                       held: timing?.held ?? [:], pauses: timing?.pauses ?? [:])
                        .padding(.vertical, 4)
                        .id("script")
                } header: {
                    Text("Script")
                } footer: {
                    if m.reading != nil {
                        // One legend for everything the script shows.
                        Text("\(Text("Red").foregroundStyle(.red)): read differently or left out · \(Text("+word").foregroundStyle(.red)): not in the script · \(Text("Orange").foregroundStyle(.orange)): held longer than the native reading · \(Text("⏸︎").foregroundStyle(.orange)): a stop where the native reading has none")
                    } else if !m.missed.isEmpty {
                        Text("Red: skipped or read differently. The small red words are what the mic heard.")
                    }
                }
            } else if !m.missed.isEmpty, scriptMarks?.takeId == take.id {
                Section {
                    Text(m.missed.joined(separator: "  ·  "))
                        .font(.body)
                        .foregroundStyle(.red)
                } header: {
                    Text("Skipped or changed")
                }
            }

            // The marked script IS what the mic heard; the raw transcript is
            // shown only when the marks couldn't be laid on the script.
            if scriptMarks?.takeId == take.id, scriptMarks?.marks == nil {
                Section {
                    DisclosureGroup("What the mic heard") {
                        Text(take.transcript)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        // The first section sits right under the sheet's score strip.
        .contentMargins(.top, 4, for: .scrollContent)
        #if DEBUG
        // `-captureScrollTo reading`: a capture run can't scroll by hand.
        .onAppear {
            if let anchor = UserDefaults.standard.string(forKey: "captureScrollTo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(anchor, anchor: .top) }
            }
        }
        #endif
        }
        .task(id: take.id) {
            // The diff is O(script × transcript), so it runs off the main thread.
            let body = script.body, transcript = take.transcript, language = script.language
            let marks = await Task.detached {
                SpeechAnalyzer.marks(script: body, transcript: transcript, language: language)
            }.value
            scriptMarks = (take.id, marks)
        }
        .sheet(item: Binding(get: { challenges.moments[take.id] },
                             set: { if $0 == nil { challenges.dismissMoment(for: take.id) } })) { moment in
            SpeechChallengeMomentSheet(moment: moment, onSeeBoard: onSeeBoard ?? {})
        }
        .alert("Couldn't save to Photos", isPresented: Binding(
            get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    @ViewBuilder
    private func playbackSection(_ take: SpeechTake) -> some View {
        if take.videoFilename != nil, SpeechVideoSync.playableURL(take) != nil {
            EmptyView()
        } else if store.videoPending.contains(take.id) {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing your video…").foregroundStyle(.secondary)
                }
            }
        } else {
            Section {
                if take.videoFilename != nil {
                    remoteVideoRow(take)
                }
            } footer: {
                if take.videoFilename != nil, remoteVideo(take) == nil {
                    Text("The video is on the device you recorded it on.")
                }
            }
        }
    }

    /// The iCloud copy this device could download for a take it holds no
    /// picture of — the standard one first, since it is the smaller.
    private func remoteVideo(_ take: SpeechTake) -> (name: String, bytes: Int)? {
        for name in [SpeechVideoSync.standardName(take.id), SpeechVideoSync.originalName(take.id)] {
            if let bytes = sync.remoteBlobSize(kind: .blobSpeechVideo, key: name) { return (name, bytes) }
        }
        return nil
    }

    @ViewBuilder
    private func remoteVideoRow(_ take: SpeechTake) -> some View {
        if let remote = remoteVideo(take) {
            downloadButton(name: remote.name, bytes: remote.bytes,
                           title: explain("Download the video"),
                           busy: explain("Downloading the video…"))
        }
    }

    /// What iCloud holds of a video this device is showing.
    @ViewBuilder
    private func cloudRow(_ take: SpeechTake) -> some View {
        let original = SpeechVideoSync.originalName(take.id)
        if SpeechVideoSync.isRecordedHere(take) {
            // Recorded here, on standard: one tap sends this one at full size.
            if sync.isEnabled, videoSync.quality == .standard {
                if SpeechVideoSync.hasOriginalCopy(take) {
                    Label(sync.blobUploaded(kind: .blobSpeechVideo, key: original)
                              ? explain("The original is in iCloud")
                              : explain("Sending the original to iCloud…"),
                          systemImage: "checkmark.icloud")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        videoSync.sendOriginal(take)
                    } label: {
                        Label("Send the original to iCloud", systemImage: "icloud.and.arrow.up")
                    }
                }
            }
        } else if !SpeechVideoSync.hasOriginalCopy(take),
                  let bytes = sync.remoteBlobSize(kind: .blobSpeechVideo, key: original) {
            // Watching the standard copy: the original is a tap away.
            downloadButton(name: original, bytes: bytes,
                           title: explain("Download the original"),
                           busy: explain("Downloading the original…"))
        }
    }

    @ViewBuilder
    private func downloadButton(name: String, bytes: Int, title: String, busy: String) -> some View {
        if sync.blobState(kind: .blobSpeechVideo, key: name) == .queued {
            Label {
                Text(busy)
            } icon: {
                ProgressView()
            }
            .foregroundStyle(.secondary)
        } else {
            Button {
                sync.requestBlob(kind: .blobSpeechVideo, key: name)
            } label: {
                Label {
                    Text("\(title) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                } icon: {
                    Image(systemName: "icloud.and.arrow.down")
                }
            }
        }
    }

    private func videoFooter(_ take: SpeechTake) -> String {
        guard SpeechVideoSync.isRecordedHere(take) else {
            return explain("This video came from your other device.")
        }
        guard sync.isEnabled else {
            return explain("Videos stay on this phone and aren't backed up. Save the ones you want to keep.")
        }
        switch videoSync.quality {
        case .off:
            return explain("Videos stay on this device. Choose a quality in Me → Devices to send them to iCloud.")
        case .standard:
            return SpeechVideoSync.hasOriginalCopy(take)
                ? explain("A standard copy and the original are in your iCloud.")
                : explain("A standard copy goes to your iCloud. The original stays on this device.")
        case .original:
            return explain("The original goes to your iCloud.")
        }
    }

    private func pronunciationDetail(_ take: SpeechTake, language: String) -> String {
        if let entry = PronunciationLedger.shared.entry(id: take.id, language: language) {
            return PronunciationProfile.current(language: language).noteLine(for: entry)
                ?? explain("No sound stood out")
        }
        // A take from before the ledger: its own marked words.
        let weak = (take.pronunciationWords ?? []).filter(\.isJudged).prefix(3).map(\.word)
        return weak.isEmpty ? explain("No sound stood out")
                            : explain("Work on: \(weak.joined(separator: " · "))")
    }

    // MARK: - Season 2: against a native reading (scoring 5)

    private func levelTitle(_ level: SpeechReadingLevel) -> LocalizedStringKey {
        switch level {
        case .newsAnchor: return "Prime-time news anchor"
        case .audiobook: return "Audiobook narrator"
        case .bornAndRaised: return "Born and raised here"
        case .passesAsLocal: return "Could pass for a local"
        case .officeAce: return "Star of the global office"
        case .presenter: return "Trusted with the presentation"
        case .thirdYearAbroad: return "Third year abroad"
        case .firstYearAbroad: return "First year abroad"
        case .languageSchool: return "Month three of language school"
        case .immigration: return "Made it through immigration"
        case .restaurant: return "Ordered at a restaurant"
        case .gestures: return "Getting by with gestures"
        case .warmingUp: return "Warming up"
        }
    }

    /// Every nickname, with the reader's own marked.
    private func levelBands(_ r: SpeechReadingScore) -> some View {
        DisclosureGroup("What the scores mean") {
            ForEach(SpeechReadingLevel.allCases, id: \.self) { level in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: level.range.count == 1 ? "\(level.range.lowerBound)"
                                                           : "\(level.range.lowerBound)–\(level.range.upperBound)")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 56, alignment: .leading)
                    Text(levelTitle(level)).font(.subheadline.weight(level == r.level ? .semibold : .regular))
                    Spacer()
                    if level == r.level {
                        Text("You").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private func readingTitle(_ part: SpeechReadingScore.Part) -> LocalizedStringKey {
        switch part {
        case .speed: return "Speaking speed"
        case .rhythm: return "Rhythm"
        case .pauses: return "Pauses"
        case .accuracy: return "Accuracy"
        case .pronunciation: return "Pronunciation"
        }
    }

    private func readingIcon(_ part: SpeechReadingScore.Part) -> String {
        switch part {
        case .speed: return "speedometer"
        case .rhythm: return "metronome"
        case .pauses: return "pause.circle"
        case .accuracy: return "text.badge.checkmark"
        case .pronunciation: return "waveform.badge.mic"
        }
    }

    private func heldList(_ held: [SpeechReadingScore.Held]) -> String {
        // Seconds, yours beside the native reading's: a ratio meant nothing
        // on screen (founder, 2026-11-08).
        held.prefix(3).map { h in
            guard let mine = h.seconds, let native = h.nativeSeconds else { return "“\(h.word)”" }
            return explain("“\(h.word)” \(String(format: "%.1f", mine))s (native \(String(format: "%.1f", native))s)")
        }.joined(separator: " · ")
    }

    private func extraPauseList(_ pauses: [SpeechReadingScore.Pause]) -> String {
        pauses.prefix(3).map { explain("after “\($0.after)” \(String(format: "%.1f", $0.seconds))s") }.joined(separator: " · ")
    }

    /// What one part measured, in one line, against the native reading.
    private func readingDetail(_ part: SpeechReadingScore.Part, _ r: SpeechReadingScore) -> String {
        switch part {
        case .speed:
            let pct = Int((abs(1 - r.speed) * 100).rounded())
            if r.speed < 0.97 { return explain("\(pct)% slower than the native reading") }
            if r.speed > 1.15 { return explain("\(pct)% faster than the native reading") }
            return explain("The native reading's pace")
        case .rhythm:
            return r.held.isEmpty ? explain("Words held as long as a native holds them")
                                  : explain("Held too long: \(heldList(r.held))")
        case .pauses:
            return r.extraPauses.isEmpty ? explain("No pauses where the native reading has none")
                                         : explain("Stopped: \(extraPauseList(r.extraPauses))")
        case .accuracy:
            if r.slips == 0 { return explain("Every word as written") }
            return r.missed.isEmpty ? explain("Words read differently: \(r.slips)")
                                    : explain("Words read differently: \(r.slips) · \(quoted(r.missed))")
        case .pronunciation:
            return r.weakest.isEmpty ? explain("No clearly wrong sounds") : soundsList(r.weakest)
        }
    }

    /// The one thing to work on next, as an instruction with its place.
    private func readingFocus(_ part: SpeechReadingScore.Part, _ r: SpeechReadingScore) -> String {
        switch part {
        case .speed:
            return explain("Read a little faster: \(Int((abs(1 - r.speed) * 100).rounded()))% slower than the native reading.")
        case .rhythm:
            return r.held.isEmpty ? explain("Keep an even flow from word to word.")
                                  : explain("Don't hold these words: \(heldList(r.held))")
        case .pauses:
            return r.extraPauses.isEmpty ? explain("Read each phrase in one breath.")
                                         : explain("Don't stop here: \(extraPauseList(r.extraPauses))")
        case .accuracy:
            return r.missed.isEmpty ? explain("Read every word as written.")
                                    : explain("Read every word as written: \(quoted(r.missed))")
        case .pronunciation:
            return r.weakest.isEmpty ? explain("Make every sound as clear as the rest.")
                                     : explain("Work on these sounds: \(soundsList(r.weakest))")
        }
    }

    @ViewBuilder
    private func readingSections(_ r: SpeechReadingScore, take: SpeechTake, language: String) -> some View {
        Section {
            if let focus = r.focus {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text("Next: \(Text(readingTitle(focus)))").font(.headline)
                    } icon: {
                        Image(systemName: "scope")
                    }
                    Text(readingFocus(focus, r))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Label("A narrator's read. Nothing left to fix.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(SpeechReadingScore.Part.allCases, id: \.self) { part in
                let score = r.parts.all.first { $0.0 == part }?.1 ?? 0
                partDetailRow(title: readingTitle(part), icon: readingIcon(part),
                              detail: readingDetail(part, r), atBar: score >= SpeechReadingScore.bar)
            }
            levelBands(r)
        } header: {
            Text("Compared with a native reading")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("The names are just for fun.")
                Text("Native speakers average \(SpeechReading.nativeAverage) · 100 is an announcer's read")
                Text("Like a karaoke score: how close this reading came to the reference. It doesn't grade your English.")
                Text("Each word is compared with the same script read by a native voice (\(Text(r.gender == "female" ? "female" : "male"))). Intonation isn't scored yet: nothing measures it reliably.")
            }
        }
    }

    // MARK: - Season 2 (scoring 4)

    private func partTitle(_ part: SpeechScoreV4.Part) -> LocalizedStringKey {
        switch part {
        case .accuracy: return "Accuracy"
        case .sounds: return "Pronunciation"
        case .phrasing: return "Phrasing"
        // Its own key: "Expression" is the vocabulary sense (표현).
        case .expression: return "speech.part.expression"
        case .pace: return "Pace"
        }
    }

    private func partIcon(_ part: SpeechScoreV4.Part) -> String {
        switch part {
        case .accuracy: return "text.badge.checkmark"
        case .sounds: return "waveform.badge.mic"
        case .phrasing: return "text.line.first.and.arrowtriangle.forward"
        case .expression: return "waveform.path.ecg"
        case .pace: return "speedometer"
        }
    }

    private func soundsList(_ sounds: [SpeechDelivery.Sound]) -> String {
        sounds.map { s in s.phoneme.isEmpty ? "“\(s.word)” \(s.score)" : "\(s.phoneme) “\(s.word)” \(s.score)" }
            .joined(separator: " · ")
    }

    private func breaksList(_ breaks: [SpeechDelivery.Break]) -> String {
        breaks.map { "“\($0.before) / \($0.after)”" }.joined(separator: " · ")
    }

    private func pausesList(_ pauses: [SpeechDelivery.Break]) -> String {
        pauses.map { "“\($0.before)” \(String(format: "%.1f", $0.seconds))s" }.joined(separator: " · ")
    }

    private func quoted(_ words: [String]) -> String {
        words.map { "“\($0)”" }.joined(separator: " ")
    }

    /// What one part measured, in a line under its number.
    private func partDetail(_ part: SpeechScoreV4.Part, _ p: SpeechParts) -> String {
        switch part {
        case .accuracy:
            if let slips = p.slips, slips > 0 {
                return p.missed.isEmpty ? explain("Words read differently: \(slips)")
                                        : explain("Words read differently: \(slips) · \(quoted(p.missed))")
            }
            return p.missed.isEmpty ? explain("Every word as written")
                                    : explain("Skipped or changed: \(quoted(p.missed))")
        case .sounds:
            return p.weakest.isEmpty ? explain("Every sound clear") : soundsList(p.weakest)
        case .phrasing:
            var bits: [String] = []
            if !p.breaks.isEmpty { bits.append(breaksList(p.breaks)) }
            if let s = p.stumbles, !s.isEmpty { bits.append(explain("Repeated or added: \(quoted(s))")) }
            if let r = p.repeats, !r.isEmpty { bits.append(explain("Said again: \(quoted(r))")) }
            if let l = p.longPauses, !l.isEmpty { bits.append(explain("Long pauses: \(pausesList(l))")) }
            if p.fillers > 0 { bits.append(explain("Fillers: \(p.fillers)")) }
            return bits.isEmpty ? explain("No breaks inside a phrase") : bits.joined(separator: " · ")
        case .expression:
            return explain("Pitch range \(String(format: "%.1f", p.pitchRange)) semitones · narrators 7–9")
        case .pace:
            return explain("\(p.wpm) words a minute · narrators 130–220")
        }
    }

    /// The one thing to work on next, said as an instruction with its place.
    private func focusLine(_ part: SpeechScoreV4.Part, _ p: SpeechParts) -> String {
        switch part {
        case .accuracy:
            return p.missed.isEmpty ? explain("Read the whole script to the end.")
                                    : explain("Read every word as written: \(quoted(p.missed))")
        case .sounds:
            return p.weakest.isEmpty ? explain("Make every sound as clear as the rest.")
                                     : explain("Work on these sounds: \(soundsList(p.weakest))")
        case .phrasing:
            if !p.breaks.isEmpty {
                return explain("Keep each phrase whole. You stopped at \(breaksList(p.breaks)).")
            }
            let again = (p.repeats ?? []) + (p.stumbles ?? [])
            if !again.isEmpty {
                return explain("Read straight through without going back: \(quoted(again))")
            }
            if let l = p.longPauses, !l.isEmpty {
                return explain("Shorten these pauses: \(pausesList(l))")
            }
            return explain("Leave out the fillers: \(p.fillers) this take.")
        case .expression:
            return explain("Let your voice move more: \(String(format: "%.1f", p.pitchRange)) semitones, where narrators move 7–9.")
        case .pace:
            return p.wpm < SpeechScoreV4.paceBand.lowerBound
                ? explain("Read a little faster: \(p.wpm) words a minute, where narrators read 130–220.")
                : explain("Read a little slower: \(p.wpm) words a minute, where narrators read 130–220.")
        }
    }

    private func partRow(_ part: SpeechScoreV4.Part, _ p: SpeechParts) -> some View {
        partDetailRow(title: partTitle(part), icon: partIcon(part),
                      detail: partDetail(part, p), atBar: p.clears(part))
    }

    /// What one part measured. Its number is in the strip at the top of the
    /// sheet, which stays on screen above this list.
    private func partDetailRow(title: LocalizedStringKey, icon: String, detail: String, atBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if atBar {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("At a narrator's level"))
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The parts of the score, what the sheet shows before it is opened
    /// (founder, 2026-11-09). A take from before either scoring has no parts
    /// of its own, so it shows the sub-scores its old total was made of.
    private func scoreTiles(_ m: SpeechMetrics) -> [(title: LocalizedStringKey, score: Int)] {
        if let r = m.reading {
            return SpeechReadingScore.Part.allCases.map { part in
                (readingTitle(part), r.parts.all.first { $0.0 == part }?.1 ?? 0)
            }
        }
        if let p = m.parts {
            return SpeechScoreV4.Part.allCases.map { (partTitle($0), p.score($0)) }
        }
        var tiles: [(title: LocalizedStringKey, score: Int)] = [("Accuracy", m.accuracy)]
        if let pron = m.pronunciation { tiles.append(("Pronunciation", pron)) }
        tiles += [("Pace", m.paceScore), ("Pauses", m.pauseScore), ("Fillers", m.fillerScore),
                  ("Steady voice", m.steadiness)]
        return tiles
    }

    private func scoreStrip(_ m: SpeechMetrics) -> some View {
        let tiles = scoreTiles(m)
        return HStack(alignment: .top, spacing: 2) {
            ForEach(tiles.indices, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(verbatim: "\(tiles[index].score)")
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(SpeechScoreColor.color(tiles[index].score))
                    ProgressView(value: Double(min(100, max(0, tiles[index].score))), total: 100)
                        .tint(SpeechScoreColor.color(tiles[index].score))
                        .padding(.horizontal, 10)
                        .accessibilityHidden(true)
                    Text(tiles[index].title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    /// Season 2's result: what to work on next, then the five parts, each
    /// with what it measured.
    @ViewBuilder
    private func seasonTwoSection(_ p: SpeechParts, take: SpeechTake, language: String) -> some View {
        Section {
            if let focus = p.focus {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text("Next: \(Text(partTitle(focus)))").font(.headline)
                    } icon: {
                        Image(systemName: "scope")
                    }
                    Text(focusLine(focus, p))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Label("A narrator's read. Nothing left to fix.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(SpeechScoreV4.Part.allCases, id: \.self) { part in
                if part == .sounds, let all = take.assessments, !all.isEmpty {
                    Button { showingPronunciation = true } label: {
                        HStack(spacing: 6) {
                            partRow(part, p)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingPronunciation) {
                        PronunciationDetailSheet(results: all, language: language)
                    }
                } else {
                    partRow(part, p)
                }
            }
        } header: {
            Text("Narrator level: \(p.barsCleared) of 5")
        } footer: {
            Text("100 takes every part at a skilled narrator's level, read to the end.")
        }
    }

    private func metricRow(_ title: LocalizedStringKey, icon: String, value: String,
                           detail: String? = nil, score: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: icon)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(SpeechScoreColor.color(score))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }


    private func saveRow(_ url: URL, title: LocalizedStringKey) -> some View {
        let saved = savedToPhotos.contains(url)
        return Button {
            Task { await saveToPhotos(url) }
        } label: {
            if saved {
                Label("Saved to Photos", systemImage: "checkmark")
            } else {
                Label(title, systemImage: "square.and.arrow.down")
            }
        }
        .disabled(saved)
    }

    /// Shown only while the take plays.
    private var scriptToggle: some View {
        Button {
            showScript.toggle()
        } label: {
            Image(systemName: "text.alignleft")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(showScript ? Color.black : Color.white)
                .frame(width: 48, height: 48)
                .background {
                    if showScript {
                        Circle().fill(.white)
                    } else {
                        Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showScript ? Text("Hide script") : Text("Show script"))
    }

    /// What can be done with the take's video, from the header's button.
    private func videoOptions(_ take: SpeechTake, url: URL) -> some View {
        NavigationStack {
            Group {
                if let record = take.prompter {
                    videoSavePage(take, url: url, record: record)
                } else {
                    burnedInVideoOptions(take, url: url)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingVideoOptions = false }
                }
            }
            .navigationTitle(take.prompter == nil ? Text(verbatim: "") : Text("Save video"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingShare, onDismiss: {
                // Only a video made for this share: the camera's own file is
                // the take.
                if let sharedVideo, sharedVideo != url { try? FileManager.default.removeItem(at: sharedVideo) }
                sharedVideo = nil
            }) {
                if let sharedVideo { ShareSheet(url: sharedVideo) }
            }
            .confirmationDialog("Delete the video? Your voice and score stay.",
                                isPresented: $confirmDeleteVideo, titleVisibility: .visible) {
                Button("Delete video", role: .destructive) {
                    hero.stop()
                    store.deleteVideo(takeId: take.id)
                    showingVideoOptions = false
                }
            } message: {
                // The take record syncs whatever the video setting, so a
                // deletion here reaches the device that recorded it.
                if sync.isEnabled {
                    Text("It's deleted on your other devices too.")
                }
            }
        }
        .presentationDetents(take.prompter == nil ? [.medium, .large] : [.large])
    }

    /// The layout picked on the take's own picture, then one thing to do
    /// with it. What is rarely wanted sits small underneath.
    private func videoSavePage(_ take: SpeechTake, url: URL, record: SpeechPrompterRecord) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 10) {
                    layoutTile(.cameraOnly, title: "Full screen", record: record)
                    layoutTile(.fullScreen, title: "Full screen + captions", record: record)
                    layoutTile(.split, title: "Split", record: record)
                }
                saveActions(url, record: record)
                VStack(alignment: .leading, spacing: 14) {
                    cloudRow(take)
                    Button(role: .destructive) {
                        confirmDeleteVideo = true
                    } label: {
                        Label("Delete video", systemImage: "trash")
                    }
                    Text(videoFooter(take))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .task(id: url) { layoutFrame = await Self.layoutFrame(of: url) }
    }

    private func layoutTile(_ style: SpeechVideoStyle, title: LocalizedStringKey,
                            record: SpeechPrompterRecord) -> some View {
        let selected = exportStyle == style
        return Button {
            exportStyle = style
        } label: {
            VStack(spacing: 8) {
                layoutPreview(style, record: record)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(selected ? Color.accentColor : Color(.separator),
                                          lineWidth: selected ? 3 : 1)
                    }
                Text(title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .disabled(exporting != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func layoutPreview(_ style: SpeechVideoStyle, record: SpeechPrompterRecord) -> some View {
        let script = Text(String(record.text.prefix(90)))
            .font(.system(size: 7, weight: .semibold))
            .lineSpacing(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
        if style == .cameraOnly {
            layoutPicture
        } else if style == .fullScreen {
            ZStack {
                layoutPicture
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                script.foregroundStyle(.white)
            }
        } else {
            VStack(spacing: 4) {
                script.foregroundStyle(.primary)
                layoutPicture
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding([.horizontal, .bottom], 4)
            }
            .background(Color(.systemBackground))
        }
    }

    /// Drawn in a clear box so a picture of any shape fills it and is cut,
    /// never pushing the tile wider. With no frame (still loading, or the
    /// file can't be read) a figure stands in for the speaker, so the three
    /// layouts still read as three layouts and not three grey boxes.
    private var layoutPicture: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let layoutFrame {
                    Image(uiImage: layoutFrame).resizable().scaledToFill()
                } else {
                    GeometryReader { box in
                        Image(systemName: "person.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.tertiary)
                            .frame(width: box.size.width * 0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .clipped()
    }

    /// A frame 3 s in, or from the middle of a take shorter than 6 s: a
    /// time past the end returns no frame at all.
    nonisolated private static func layoutFrame(of url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let length = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let at = length.isFinite && length > 0 ? min(3, length / 2) : 0
        guard let frame = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)) else { return nil }
        return UIImage(cgImage: frame.image)
    }

    /// The video with the script in it, made when it is asked for.
    @ViewBuilder
    private func saveActions(_ url: URL, record: SpeechPrompterRecord) -> some View {
        let style = exportStyle
        let mark = style == .cameraOnly ? url : url.appendingPathExtension("with-script-\(style.rawValue)")
        let saved = savedToPhotos.contains(mark)
        VStack(spacing: 10) {
            if let exporting {
                VStack(spacing: 8) {
                    ProgressView(value: exporting)
                    Text("Preparing your video…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                #if !targetEnvironment(macCatalyst)
                Button {
                    if style == .cameraOnly {
                        sharedVideo = url
                        showingShare = true
                    } else {
                        exportWithScript(url, record: record, style: style, mark: nil, sharing: true)
                    }
                } label: {
                    Text("Post to Instagram").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                #endif
                Button {
                    if style == .cameraOnly {
                        Task { await saveToPhotos(url) }
                    } else {
                        exportWithScript(url, record: record, style: style, mark: mark)
                    }
                } label: {
                    Group {
                        if saved {
                            Label("Saved to Photos", systemImage: "checkmark")
                        } else {
                            Text("Save to Photos")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(saved)
            }
        }
    }

    /// A take from before the camera was kept: the script is in its video.
    private func burnedInVideoOptions(_ take: SpeechTake, url: URL) -> some View {
        List {
            Section {
                Button {
                    preparePlayback()
                    showingVideoOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { watchingScriptVideo = url }
                } label: {
                    Label("Watch script video", systemImage: "play.rectangle")
                }
                saveRow(url, title: "Save to Photos")
                cloudRow(take)
                Button(role: .destructive) {
                    confirmDeleteVideo = true
                } label: {
                    Label("Delete video", systemImage: "trash")
                }
            } footer: {
                Text(videoFooter(take))
            }
        }
    }

    /// Instagram gives an app no way to post by itself: `sharing` hands the
    /// finished video to the system's share sheet, and Instagram's own screen
    /// takes it from there.
    private func exportWithScript(_ url: URL, record: SpeechPrompterRecord, style: SpeechVideoStyle,
                                  mark: URL?, sharing: Bool = false) {
        exporting = 0
        Task {
            let started = Date()
            let made = await SpeechVideoExporter.render(video: url, record: record, style: style) { value in
                Task { @MainActor in if exporting != nil { exporting = value } }
            }
            Analytics.capture("speech_video_export", ["ok": made != nil, "ms": Int(Date().timeIntervalSince(started) * 1000),
                                                      "seconds": Int(record.offsets.count) / 10, "style": style.rawValue,
                                                      "to": sharing ? "instagram" : "photos"])
            exporting = nil
            guard let made else {
                showingVideoOptions = false
                photoError = explain("Couldn't make the video. Try again.")
                return
            }
            if sharing {
                sharedVideo = made
                showingShare = true
                return
            }
            await saveToPhotos(made, mark: mark)
            try? FileManager.default.removeItem(at: made)
        }
    }

    private func preparePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: AudioSessionRouting.playbackOptions)
        try? session.setActive(true)
    }

    private func playAudio(_ take: SpeechTake) {
        guard let data = try? Data(contentsOf: SpeechStore.mediaURL(take.audioFilename)) else { return }
        try? audio.play(data, source: "speech_take")
    }

    private func saveToPhotos(_ url: URL, mark: URL? = nil) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            showingVideoOptions = false
            photoError = explain("Photos access is off. Turn it on in Settings to save videos.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            savedToPhotos.insert(mark ?? url)
        } catch {
            showingVideoOptions = false
            photoError = error.localizedDescription
        }
    }
}

/// The script as one flowing text, each misread word in red: underlined
/// with what the mic heard written small beside it, or struck through when
/// it was skipped.
private struct SpeechMarkedScript: View {
    let paragraphs: [[SpeechAnalyzer.ScriptMark]]
    let language: String
    /// By the script word's index across paragraphs: seconds a word was held
    /// (longer than the native reading) and seconds of a stop after it
    /// (where the native reading has none). Season 2 takes only.
    var held: [Int: Double] = [:]
    var pauses: [Int: Double] = [:]

    /// Season 2's per-token findings laid onto the script's words: a word
    /// owns as many scoring tokens as `SpeechDelivery.referenceTokens` makes
    /// of it (a hyphenated word two, a lone dash none).
    static func timing(_ r: SpeechReadingScore, marks: [[SpeechAnalyzer.ScriptMark]])
    -> (held: [Int: Double], pauses: [Int: Double]) {
        var wordOfToken: [Int: Int] = [:]
        var t = 0
        for (w, mark) in marks.flatMap({ $0 }).enumerated() {
            for _ in SpeechDelivery.referenceTokens(mark.word) { wordOfToken[t] = w; t += 1 }
        }
        var held: [Int: Double] = [:], pauses: [Int: Double] = [:]
        for h in r.held { if let i = h.index, let w = wordOfToken[i], let s = h.seconds { held[w] = s } }
        for p in r.extraPauses { if let i = p.index, let w = wordOfToken[i] { pauses[w] = p.seconds } }
        return (held, pauses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { p, line in
                if !line.isEmpty {
                    Text(attributed(line, first: paragraphs[..<p].reduce(0) { $0 + $1.count }))
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func note(_ text: String, _ color: Color) -> AttributedString {
        var n = AttributedString(text)
        n.foregroundColor = color
        n.font = .caption2.weight(.semibold)
        n.baselineOffset = 6
        return n
    }

    private func attributed(_ line: [SpeechAnalyzer.ScriptMark], first: Int) -> AttributedString {
        let gap = LanguageCatalog.writesSpaces(language) ? " " : ""
        var out = AttributedString()
        for (i, mark) in line.enumerated() {
            if i > 0 { out += AttributedString(gap) }
            var word = AttributedString(mark.word)
            if let s = held[first + i] {
                word.backgroundColor = .orange.opacity(0.25)
                word += note(" " + explain("\(String(format: "%.1f", s))s"), .orange)
            }
            switch mark.op {
            case .match, .ins:
                break
            case .del:
                word.foregroundColor = .red
                word.strikethroughStyle = .single
            case .sub:
                word.foregroundColor = .red
                word.underlineStyle = .single
            }
            out += word
            if mark.op == .sub, let heard = mark.heard, !heard.isEmpty {
                var note = AttributedString(" " + heard)
                note.foregroundColor = .red
                note.font = .caption2.italic()
                note.baselineOffset = 6
                out += note
            }
            for extra in mark.added {
                out += note(" +" + extra, .red)
            }
            if let s = pauses[first + i] {
                out += note(" ⏸︎" + explain("\(String(format: "%.1f", s))s"), .orange)
            }
        }
        return out
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// Fills the view, cropping the picture's edges.
    var fill = false

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// The one line a Season 2 score comes with, the way a karaoke machine says
/// something about yours (founder, 2026-11-08). An overall remark and only
/// that: it reads no part of the take, and the score bands it switches at are
/// chosen for the fun of it, not measured. One byte of the take's id picks
/// the line, so a take keeps its line when it is reopened.
enum SpeechVerdict {
    static func line(total: Int, take: UUID) -> LocalizedStringKey {
        let lines = self.lines(total: total)
        return lines[Int(take.uuid.15) % lines.count]
    }

    private static func lines(total: Int) -> [LocalizedStringKey] {
        switch total {
        case 100...:
            return ["Are you a news anchor?", "Wait, is this the evening news?", "I thought the radio was on.",
                    "Not a thing to fix.", "Perfect. Nothing to add."]
        case 95...:
            return ["Anchors should be worried!", "Do you work in broadcasting?", "You could do voice work.",
                    "Every word lands.", "One hair short of 100."]
        case 88...:
            return ["You could record audiobooks.", "So easy to listen to.", "I'd hand you the presentation.",
                    "Go on, brag a little.", "That just flowed."]
        case 78...:
            return ["Oh, not bad at all!", "You've got my attention.", "You've been hiding this?",
                    "Starting to sound like the real thing.", "A little more and you're on air."]
        case 60...:
            return ["Nice, you've got the feel of it.", "Already sounding good.", "One more go and that's a record.",
                    "It only gets better from here.", "You've got it. Go again."]
        default:
            return ["Nobody nails it on the first try.", "You read it to the end. That counts.", "Consider that a warm-up.",
                    "The next round is the real one.", "Practice pays off."]
        }
    }
}

/// A pull down from the top of the open sheet closes it, as a system sheet
/// does. Needs the scroll position, which iOS 18 gives; before it the handle
/// still closes the sheet.
private struct PullDownCloses: ViewModifier {
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                if isOpen, offset < -70 {
                    withAnimation(.smooth(duration: 0.3)) { isOpen = false }
                }
            }
        } else {
            content
        }
    }
}

/// The picture behind the score: six seconds looping without sound, or the
/// whole take with sound once play is pressed, back to the loop at its end.
@MainActor
final class SpeechHeroPlayer: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    /// The whole take is loaded, playing or paused, not the silent loop.
    @Published private(set) var isFull = false

    private static let loopSeconds = 6.0
    /// Skips the first breath of the take when there is enough of it.
    private static let loopStart = 3.0

    private var url: URL?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var generation = 0

    func show(_ url: URL?) async {
        guard url != self.url else { return }
        // Switching videos while the take plays keeps its place.
        let resume = isFull ? (time: player?.currentTime() ?? .zero, playing: isPlaying) : nil
        self.url = url
        guard let url else { reset(); player = nil; return }
        if let resume {
            startFull(url, at: resume.time, playing: resume.playing)
        } else {
            await startLoop(url)
        }
    }

    func toggle() {
        guard let url else { return }
        if isFull, let player {
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
        } else {
            startFull(url, at: .zero, playing: true)
        }
    }

    func stop() {
        reset()
        player = nil
        url = nil
    }

    private func reset() {
        generation += 1
        player?.pause()
        looper?.disableLooping()
        looper = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        isFull = false
        isPlaying = false
    }

    private func startLoop(_ url: URL) async {
        reset()
        let mine = generation
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        guard mine == generation, duration > 0 else { return }
        let start = duration > Self.loopStart + Self.loopSeconds ? Self.loopStart : 0
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: min(Self.loopSeconds, duration - start), preferredTimescale: 600))
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset), timeRange: range)
        queue.play()
        player = queue
    }

    private func startFull(_ url: URL, at time: CMTime, playing: Bool) {
        reset()
        let item = AVPlayerItem(url: url)
        let full = AVPlayer(playerItem: item)
        full.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let url = self.url else { return }
                await self.startLoop(url)
            }
        }
        isFull = true
        isPlaying = playing
        player = full
        if playing { full.play() }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The script rolling over the camera while a take plays: drawn here, not
/// stored in the video, always white on the picture.
private struct SpeechScriptOverlay: View {
    let record: SpeechPrompterRecord
    let player: AVPlayer
    let rolling: Bool
    @State private var column: SpeechVideoComposer.Column?

    /// The part of the column already said.
    private struct LitArea: Shape {
        let boxes: [CGRect]
        let k: CGFloat

        func path(in _: CGRect) -> Path {
            var path = Path()
            for box in boxes {
                path.addRect(CGRect(x: box.minX * k, y: box.minY * k, width: box.width * k, height: box.height * k))
            }
            return path
        }
    }

    var body: some View {
        let layout = SpeechVideoComposer.Layout.standard(width: CGFloat(record.width), background: .clear)
        GeometryReader { geo in
            let k: CGFloat = geo.size.width / layout.canvas.width
            if let column {
                TimelineView(.animation(minimumInterval: nil, paused: !rolling)) { _ in
                    let seconds = player.currentTime().seconds
                    let reached = column.words.isEmpty ? nil : record.reached(at: seconds)
                    let script = Image(decorative: column.text, scale: column.scale)
                        .resizable()
                        .frame(width: geo.size.width, height: CGFloat(column.text.height) / column.scale * k)
                    ZStack(alignment: .topLeading) {
                        script.opacity(reached == nil ? 1 : SpeechPrompterRecord.unreadOpacity)
                        if let reached {
                            script.clipShape(LitArea(boxes: column.lit(reached), k: k))
                        }
                    }
                    .offset(y: -CGFloat(record.offset(at: seconds)) * k)
                }
                .frame(width: geo.size.width, height: layout.prompter.height * k, alignment: .topLeading)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: layout.topFade),
                                           .init(color: .black, location: 1 - layout.bottomFade),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .task {
            var white = record
            white.dark = true
            column = SpeechVideoExporter.column(for: white)?.column
        }
    }
}

/// The take's video with the script in it, on its own screen.
private struct SpeechScriptVideoSheet: View {
    @State private var player: AVPlayer

    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

/// The sheet's outline, inset from the sides and cut off above the screen's
/// bottom while it floats. Animatable, so a release glides with the offset.
private struct FloatingSheetShape: Shape {
    var inset: CGFloat
    var visibleHeight: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(inset, visibleHeight), radius) }
        set {
            inset = newValue.first.first
            visibleHeight = newValue.first.second
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let card = CGRect(x: rect.minX + inset, y: rect.minY,
                          width: rect.width - inset * 2, height: visibleHeight)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: card)
    }
}

/// The picture with a sheet over it. On a phone it is the system's own sheet
/// (founder, 2026-11-09): on iOS 26 that is glass floating off the edges and
/// opaque edge to edge at full height, drawn by iOS, so nothing here paints
/// its background. An iPad or Mac has no such sheet (detents are ignored and
/// it would be a modal over the picture), so those keep the drawn one, whose
/// drag lives here on purpose: a finger moves it 120 times a second, and held
/// by the result page each move rebuilt the page's whole list of details.
private struct SpeechResultSheetPage<Background: View, Overlay: View, Hero: View, Playing: View, Summary: View, Details: View>: View {
    private let peek: CGFloat = 166
    /// Leaves a strip of the blurred reader above the open sheet.
    private let top: CGFloat = 56
    /// Closed, the sheet floats this far off the edges; open, it fills them.
    private let floatInset: CGFloat = 8

    /// The summary and nothing else; iOS adds the floating card's own margin.
    private static var systemPeek: CGFloat { 136 }
    private static var peekDetent: PresentationDetent { .height(systemPeek) }
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The system sheet: up over the page, except while the take plays.
    @State private var sheetUp = false
    @State private var detent: PresentationDetent = Self.peekDetent

    let immersive: Bool
    let onTapWhilePlaying: () -> Void
    let background: Background
    let overlay: Overlay
    let hero: Hero
    let playing: Playing
    let summary: Summary
    let details: Details

    @State private var open = false
    @State private var drag: CGFloat = 0

    init(immersive: Bool, onTapWhilePlaying: @escaping () -> Void,
         @ViewBuilder background: () -> Background, @ViewBuilder overlay: () -> Overlay,
         @ViewBuilder hero: () -> Hero, @ViewBuilder playing: () -> Playing,
         @ViewBuilder summary: () -> Summary, @ViewBuilder details: () -> Details) {
        self.immersive = immersive
        self.onTapWhilePlaying = onTapWhilePlaying
        self.background = background()
        self.overlay = overlay()
        self.hero = hero()
        self.playing = playing()
        self.summary = summary()
        self.details = details()
    }

    var body: some View {
        if sizeClass == .compact {
            systemSheetPage
        } else {
            drawnSheetPage
        }
    }

    private var systemSheetPage: some View {
        let isOpen = detent == .large
        return GeometryReader { geo in
            ZStack(alignment: .top) {
                background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .opacity(isOpen ? 1 : 0)
                    .ignoresSafeArea()
                overlay
                hero
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height - Self.systemPeek - 20, alignment: .bottom)
                    .opacity(immersive || isOpen ? 0 : 1)
                    .allowsHitTesting(!immersive && !isOpen)
                if immersive {
                    // A tap on the picture pauses it, and everything comes back.
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture(perform: onTapWhilePlaying)
                    playing
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .animation(.easeOut(duration: 0.3), value: immersive)
            .animation(.easeOut(duration: 0.3), value: isOpen)
        }
        .sheet(isPresented: $sheetUp) { systemSheet(isOpen: isOpen) }
        .onChange(of: immersive) { _, playing in sheetUp = !playing }
        .task {
            // After the page has finished arriving: a sheet asked for during
            // a cover's own presentation is dropped.
            try? await Task.sleep(for: .seconds(0.45))
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "capturePanelOpen") { detent = .large }
            #endif
            sheetUp = !immersive
        }
    }

    private func systemSheet(isOpen: Bool) -> some View {
        VStack(spacing: 0) {
            summary
                .padding(.top, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) { detent = isOpen ? Self.peekDetent : .large }
                }
            details
                // Glass at the low detent; the grouped ground only when open.
                .scrollContentBackground(.hidden)
                .opacity(isOpen ? 1 : 0)
        }
        .background(Color(.systemGroupedBackground).opacity(isOpen ? 1 : 0).ignoresSafeArea())
        .animation(.easeOut(duration: 0.25), value: isOpen)
        .presentationDetents([Self.peekDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.peekDetent))
        // The sheet is the page's lower half, not something to close.
        .interactiveDismissDisabled()
    }

    private var drawnSheetPage: some View {
        GeometryReader { geo in
            let closedY: CGFloat = geo.size.height - peek
            let restY: CGFloat = open ? top : closedY
            let y: CGFloat = Swift.min(closedY, Swift.max(top, restY + drag))
            let progress: Double = Double((closedY - y) / Swift.max(1, closedY - top))
            ZStack(alignment: .top) {
                background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .opacity(progress)
                    .ignoresSafeArea()
                overlay
                hero
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    // Measured from the top: the sheet makes this stack taller
                    // than the screen, so its bottom edge is below the sheet's.
                    .frame(height: closedY - 20, alignment: .bottom)
                    .opacity(immersive ? 0 : Swift.max(0, 1 - progress * 1.8))
                    .allowsHitTesting(progress < 0.5 && !immersive)
                sheet(progress: progress,
                      visibleHeight: geo.size.height + geo.safeAreaInsets.bottom - y)
                    .frame(height: geo.size.height - top + geo.safeAreaInsets.bottom, alignment: .top)
                    .offset(y: y)
                    .opacity(immersive ? 0 : 1)
                    .allowsHitTesting(!immersive)
                if immersive {
                    // A tap on the picture pauses it, and everything comes back.
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture(perform: onTapWhilePlaying)
                    playing
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .frame(height: geo.size.height)
                }
            }
            .animation(.easeOut(duration: 0.3), value: immersive)
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "capturePanelOpen") { open = true } }
        #endif
    }

    /// Global coordinates: measured in the sheet's own, the distance changes
    /// as the sheet moves under the finger, and the sheet shakes.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                let moved = value.predictedEndTranslation.height
                withAnimation(.smooth(duration: 0.3)) {
                    if moved < -60 { open = true } else if moved > 60 { open = false }
                    drag = 0
                }
            }
    }

    /// Glass floating off the edges when closed; opaque and edge to edge when
    /// open. The inset is a clip, not padding, for the details: narrowing the
    /// list would lay out every row 120 times a second under the finger.
    private func sheet(progress: Double, visibleHeight: CGFloat) -> some View {
        let inset = floatInset * CGFloat(1 - progress)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 24)
                summary
            }
            .padding(.horizontal, inset)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.smooth(duration: 0.3)) { open.toggle() } }
            .gesture(dragGesture)
            details
                // The sheet's own ground shows through, glass or opaque.
                .scrollContentBackground(.hidden)
                // Closed, the summary is all the sheet shows.
                .opacity(Swift.min(1, progress * 5))
                .scrollDisabled(!open)
                .modifier(PullDownCloses(isOpen: $open))
                // Closed, the whole sheet is the handle.
                .simultaneousGesture(dragGesture, including: open ? .subviews : .all)
        }
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Color(.systemGroupedBackground).opacity(Swift.min(1, progress * 1.5))
            }
        }
        .clipShape(FloatingSheetShape(inset: inset,
                                      // Open, the bottom corners go below the screen.
                                      visibleHeight: visibleHeight - inset + 48 * CGFloat(progress),
                                      radius: 24 + 10 * CGFloat(1 - progress)))
        .ignoresSafeArea(edges: .bottom)
    }
}
