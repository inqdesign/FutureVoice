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
    @State private var player: AVPlayer?
    /// The video's own width ÷ height, read from the file, so the player is
    /// exactly the picture's shape — no black bars.
    @State private var videoAspect: CGFloat?
    @State private var savedToPhotos = false
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
            content(take, script)
        } else {
            ContentUnavailableView("Take not found", systemImage: "waveform")
        }
    }

    private func content(_ take: SpeechTake, _ script: SpeechScript) -> some View {
        let m = take.metrics
        return ScrollViewReader { proxy in List {
            Section {
                HStack(spacing: 18) {
                    // Drawn, not a Gauge: `.accessoryCircularCapacity` is a
                    // lock-screen style, and on a device it carries the
                    // widget's drop shadow (the 1.3× scale made it heavier).
                    let tint = SpeechScoreColor.color(m.overall)
                    ZStack {
                        Circle().stroke(tint.opacity(0.25), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0, min(100, m.overall))) / 100)
                            .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(m.overall)").font(.title2.monospacedDigit().weight(.bold))
                    }
                    .padding(4)
                    .frame(width: 80, height: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(m.overall)"))

                    VStack(alignment: .leading, spacing: 6) {
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
                }
                .padding(.vertical, 6)

                // Season 2: what the number means, right under it.
                if let r = m.reading {
                    levelRows(r)
                }

                if let tips = take.coaching?.tips, !tips.isEmpty {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        Label(tip, systemImage: "arrow.forward.circle")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text(script.title)
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
        .navigationTitle(Text(take.createdAt, format: .dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.pause()
            audio.stop()
        }
        .sheet(item: Binding(get: { challenges.moments[take.id] },
                             set: { if $0 == nil { challenges.dismissMoment(for: take.id) } })) { moment in
            SpeechChallengeMomentSheet(moment: moment, onSeeBoard: onSeeBoard ?? {})
        }
        .confirmationDialog("Delete the video? Your voice and score stay.",
                            isPresented: $confirmDeleteVideo, titleVisibility: .visible) {
            Button("Delete video", role: .destructive) {
                player?.pause()
                player = nil
                store.deleteVideo(takeId: take.id)
            }
        } message: {
            // The take record syncs whatever the video setting, so a
            // deletion here reaches the device that recorded it.
            if sync.isEnabled {
                Text("It's deleted on your other devices too.")
            }
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
        if take.videoFilename != nil, let url = SpeechVideoSync.playableURL(take) {
            Section {
                SpeechTakeVideo(player: player)
                    .aspectRatio(videoAspect ?? 9 / 19.5, contentMode: .fit)
                    .frame(maxHeight: 520)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    // Keyed on the file: when the original lands in place of
                    // the standard copy, the player moves to it.
                    .task(id: url) {
                        preparePlayback()
                        player?.pause()
                        player = AVPlayer(url: url)
                        videoAspect = await Self.aspect(of: url)
                    }
                Button {
                    saveToPhotos(url)
                } label: {
                    Label(savedToPhotos ? "Saved to Photos" : "Save to Photos",
                          systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                }
                .disabled(savedToPhotos)
                cloudRow(take)
                Button(role: .destructive) {
                    confirmDeleteVideo = true
                } label: {
                    Label("Delete video", systemImage: "trash")
                }
            } footer: {
                Text(videoFooter(take))
            }
        } else if store.videoPending.contains(take.id) {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing your video…").foregroundStyle(.secondary)
                }
            }
        } else {
            Section {
                Button {
                    if audio.isPlaying { audio.stop() } else { playAudio(take) }
                } label: {
                    Label(audio.isPlaying ? "Stop" : "Play your take",
                          systemImage: audio.isPlaying ? "stop.fill" : "play.fill")
                }
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
        case .announcer: return "Announcer level"
        case .narrator: return "Narrator level"
        case .native: return "Native level"
        case .nearNative: return "Close to native"
        case .intermediate: return "Intermediate"
        case .practicing: return "Still practicing"
        }
    }

    private func levelNote(_ level: SpeechReadingLevel) -> LocalizedStringKey {
        switch level {
        case .announcer: return "Every part at a skilled narrator's level"
        case .narrator: return "Skilled narrators average \(SpeechReading.narratorAverage)"
        case .native: return "Native speakers reading average \(SpeechReading.nativeAverage)"
        case .nearNative: return "Where the best learners reach"
        case .intermediate: return "Learners average \(SpeechReading.learnerAverage)"
        case .practicing: return "Below most learners"
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

    /// The level the score lands in, the averages beside it, and every band.
    @ViewBuilder
    private func levelRows(_ r: SpeechReadingScore) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(levelTitle(r.level)).font(.title3.weight(.semibold))
                Text("Native speakers average \(SpeechReading.nativeAverage) · 100 is an announcer's read")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            DisclosureGroup("What the scores mean") {
                ForEach(SpeechReadingLevel.allCases, id: \.self) { level in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: level.range.count == 1 ? "\(level.range.lowerBound)"
                                                               : "\(level.range.lowerBound)–\(level.range.upperBound)")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(levelTitle(level)).font(.subheadline.weight(level == r.level ? .semibold : .regular))
                            Text(levelNote(level)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if level == r.level {
                            Text("You").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                }
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
                HStack(alignment: .firstTextBaseline) {
                    Label(readingTitle(part), systemImage: readingIcon(part))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            if score >= SpeechReadingScore.bar {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .accessibilityLabel(Text("At a narrator's level"))
                            }
                            Text(verbatim: "\(score)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(SpeechScoreColor.color(score))
                        }
                        Text(readingDetail(part, r))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } header: {
            Text("Compared with a native reading")
        } footer: {
            Text("Each word is compared with the same script read by a native voice (\(Text(r.gender == "female" ? "female" : "male"))). Intonation isn't scored yet: nothing measures it reliably.")
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
        HStack(alignment: .firstTextBaseline) {
            Label(partTitle(part), systemImage: partIcon(part))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if p.clears(part) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel(Text("At a narrator's level"))
                    }
                    Text(verbatim: "\(p.score(part))")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(SpeechScoreColor.color(p.score(part)))
                }
                Text(partDetail(part, p))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
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

    private static func aspect(of url: URL) async -> CGFloat? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let shown = size.applying(transform)
        let w = abs(shown.width), h = abs(shown.height)
        return h > 0 ? w / h : nil
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

    private func saveToPhotos(_ url: URL) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                photoError = explain("Photos access is off. Turn it on in Settings to save videos.")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                savedToPhotos = true
            } catch {
                photoError = error.localizedDescription
            }
        }
    }
}

/// The take's video: the picture, and one tap to play or pause — no control
/// bar to bring up first (founder, 2026-10-05: the system player's first tap
/// only showed its controls). A play glyph shows while it is stopped; at the
/// end a tap plays it again from the start.
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

private struct SpeechTakeVideo: View {
    let player: AVPlayer?
    @State private var playing = false

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerLayerView(player: player)
            }
            if !playing {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .animation(.easeOut(duration: 0.15), value: playing)
        // Scrolled out of sight, the take keeps playing (founder, 2026-11-04:
        // play it, then scroll down to read the script along with it). The
        // row's state is read off the player, so a row scrolled back in shows
        // the truth; the page itself pauses when it is left.
        .onReceive(player?.publisher(for: \.timeControlStatus).receive(on: RunLoop.main).eraseToAnyPublisher()
                   ?? Empty().eraseToAnyPublisher()) { status in
            playing = status != .paused
        }
        .accessibilityElement()
        .accessibilityLabel(playing ? Text("Pause") : Text("Play"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private func toggle() {
        guard let player else { return }
        if playing {
            player.pause()
            playing = false
        } else {
            if let item = player.currentItem,
               item.duration.isNumeric,
               player.currentTime().seconds >= item.duration.seconds - 0.1 {
                player.seek(to: .zero)
            }
            player.play()
            playing = true
        }
    }
}

/// An `AVPlayerLayer`, aspect-fit, with no controls of its own.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
