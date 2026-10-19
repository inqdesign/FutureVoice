import ActivityKit
import AVFoundation
import Foundation
import MediaPlayer

/// Plays a playlist of fluent-self lines, one after another, with the screen
/// on or off (2026-10-18).
///
/// One app-wide instance, because the Talk tab's button shows what is playing
/// and the player sheet can be closed while the list keeps going. Built on
/// the app's own `AudioPlayer`, so a line is levelled and routed exactly as
/// everywhere else, and its `currentTime` drives the caption's karaoke.
///
/// **It yields to everything.** Any other surface that starts audio
/// (`AudioPlayer.play` / a stream / a duet) pauses it, and a call takes the
/// lock screen from it (`CallNowPlaying.begin`). It never resumes on its own
/// afterwards — it keeps its place and waits for a tap.
@MainActor
final class PlaylistPlayer: ObservableObject {
    static let shared = PlaylistPlayer()

    enum RepeatMode: String, CaseIterable { case off, all, one }

    /// What happens between two lines.
    enum Gap: String, CaseIterable {
        /// Straight on.
        case none
        /// A beat to let the line land (one second — two read as slow).
        case short
        /// As long as the line itself — time to say it back out loud.
        case echo

        func seconds(after duration: TimeInterval) -> TimeInterval {
            switch self {
            case .none: return 0
            case .short: return 1
            case .echo: return min(max(duration, 1.5), 20)
            }
        }
    }

    /// The `AudioPlayer` that speaks. Views observe it for the playhead.
    let audio = AudioPlayer()

    @Published private(set) var title = ""
    /// The list in its ORIGINAL order; `order` is the play order.
    @Published private(set) var lines: [PlaylistLine] = []
    @Published private(set) var order: [Int] = []
    @Published private(set) var position = 0
    @Published private(set) var isPlaying = false
    /// In the pause between two lines (the caption keeps the last line).
    @Published private(set) var isInGap = false
    /// The playing line's word timings — measured when the take kept them,
    /// otherwise spread over the audio by character count, so the caption
    /// always moves with the voice (the product rule: karaoke always works).
    @Published private(set) var timings: [WordTiming] = []

    @Published var repeatMode: RepeatMode {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.repeatKey) }
    }
    @Published private(set) var shuffle: Bool
    @Published var gap: Gap {
        didSet { UserDefaults.standard.set(gap.rawValue, forKey: Self.gapKey) }
    }
    /// Playback speed. Time-stretched (`AVAudioPlayer.rate`), so the voice
    /// keeps its pitch and the caption follows the audio as it plays.
    @Published var speed: Float {
        didSet {
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
            audio.setRate(speed)
        }
    }
    static let speeds: [Float] = [0.75, 0.9, 1.0]

    private static let repeatKey = "futurevoice.playlist.repeat"
    private static let shuffleKey = "futurevoice.playlist.shuffle"
    private static let gapKey = "futurevoice.playlist.gap"
    private static let speedKey = "futurevoice.playlist.speed"

    /// Bumped on every jump, so a line that finishes after the learner has
    /// already moved on can't advance the list a second time.
    private var generation = 0
    private var gapTask: Task<Void, Never>?
    private var skipStreak = 0
    private var interruptionObserver: NSObjectProtocol?
    private var commandObserver: NSObjectProtocol?

    private init() {
        let d = UserDefaults.standard
        repeatMode = RepeatMode(rawValue: d.string(forKey: Self.repeatKey) ?? "") ?? .all
        shuffle = d.bool(forKey: Self.shuffleKey)
        gap = Gap(rawValue: d.string(forKey: Self.gapKey) ?? "") ?? .none
        let saved = d.float(forKey: Self.speedKey)
        speed = Self.speeds.contains(saved) ? saved : 1.0
        audio.setRate(speed)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.pause() }
        }
        // The Live Activity's buttons (their intents run in this process).
        commandObserver = NotificationCenter.default.addObserver(
            forName: ScenePlaybackCommand.notification, object: nil, queue: .main
        ) { note in
            let command = (note.object as? String).flatMap(ScenePlaybackCommand.init(rawValue:))
            Task { @MainActor in
                switch command {
                case .toggle: PlaylistPlayer.shared.togglePlayPause()
                case .next: PlaylistPlayer.shared.next()
                case nil: break
                }
            }
        }
        // An island left by a run the system ended (the app was killed)
        // describes nothing that is playing.
        for stale in Activity<SceneListeningAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - State

    var hasQueue: Bool { !lines.isEmpty }

    var current: PlaylistLine? {
        guard order.indices.contains(position) else { return nil }
        let i = order[position]
        return lines.indices.contains(i) ? lines[i] : nil
    }

    /// How far through the list, 0…1 — the Talk button's ring.
    var progress: Double {
        guard !order.isEmpty else { return 0 }
        let lineShare = audio.duration > 0 ? min(audio.currentTime / audio.duration, 1) : 0
        return (Double(position) + (isInGap ? 1 : lineShare)) / Double(order.count)
    }

    // MARK: - Control

    /// Load a list and start it. `startAt` is an index into `lines`.
    func play(_ lines: [PlaylistLine], title: String, startAt: Int = 0) {
        let playable = lines.filter(\.hasAudio)
        guard !playable.isEmpty else { return }
        let start = lines.indices.contains(startAt)
            ? playable.firstIndex { $0.id == lines[startAt].id } ?? 0
            : 0
        flushListening(finished: false)
        startedEpisodes = []
        self.title = title
        self.lines = playable
        order = Self.makeOrder(lines: playable, shuffled: shuffle, first: start)
        position = 0
        Analytics.capture("playlist_started", ["lines": playable.count,
                                               "shuffle": shuffle,
                                               "gap": gap.rawValue])
        startCurrent()
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func resume() {
        guard hasQueue else { return }
        if isInGap || audio.duration == 0 || audio.currentTime >= audio.duration - 0.05 {
            if isInGap { position = min(position + 1, order.count - 1) }
            startCurrent()
        } else {
            startCurrent(from: audio.currentTime)
        }
    }

    func pause() {
        guard isPlaying || isInGap else { return }
        flushListening(finished: false)
        generation += 1
        gapTask?.cancel()
        isInGap = false
        isPlaying = false
        audio.pause()
        publishNowPlaying()
    }

    func next() {
        guard hasQueue else { return }
        if position + 1 < order.count {
            position += 1
        } else {
            position = 0
            if shuffle { order = Self.makeOrder(lines: lines, shuffled: true, first: nil) }
        }
        startCurrent()
    }

    /// Back to the start of this line if it has been playing a while, else
    /// the line before — the music-player convention.
    func previous() {
        guard hasQueue else { return }
        if audio.currentTime > 2.5 || position == 0 {
            startCurrent()
        } else {
            position -= 1
            startCurrent()
        }
    }

    /// Jump to a line of the list (index into `lines`).
    func jump(toLine index: Int) {
        guard let p = order.firstIndex(of: index) else { return }
        position = p
        startCurrent()
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        UserDefaults.standard.set(on, forKey: Self.shuffleKey)
        guard hasQueue else { return }
        // Keep the line that is playing; reorder everything around it.
        let playing = order.indices.contains(position) ? order[position] : 0
        order = Self.makeOrder(lines: lines, shuffled: on, first: playing)
        position = order.firstIndex(of: playing) ?? 0
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }

    /// Stop and forget the list.
    func close() {
        pause()
        flushListening(finished: false)
        lines = []
        order = []
        position = 0
        title = ""
        audio.stop()
        releaseLockScreen()
        endLiveActivity()
    }

    /// Another surface is about to make sound. Pause and keep the place.
    func yieldToOtherAudio() {
        guard isPlaying || isInGap else { return }
        pause()
    }

    /// A call takes the lock screen; `CallNowPlaying.begin` calls this first.
    func yieldToCall() {
        yieldToOtherAudio()
        releaseLockScreen()
    }

    // MARK: - Playback

    private func startCurrent(from offset: TimeInterval = 0) {
        generation += 1
        let mine = generation
        gapTask?.cancel()
        isInGap = false
        guard let line = current else { isPlaying = false; return }
        guard let url = line.audioURL, let data = try? Data(contentsOf: url) else {
            // Gone since the list was loaded (a re-clone outside the lineage,
            // a deleted talk) — skip, never synthesize.
            advance(after: 0, generation: mine, skipping: true)
            return
        }
        Self.isStartingOwnAudio = true
        defer { Self.isStartingOwnAudio = false }
        do {
            try audio.play(data, source: "playlist") { [weak self] in
                guard let self, self.generation == mine else { return }
                self.advance(after: self.audio.duration, generation: mine, skipping: false)
            }
            if offset > 0 { audio.seek(to: offset) }
            let stored = (line.storedTimings ?? []).filter { $0.endMs > $0.startMs }
            timings = stored.isEmpty
                ? ShadowDrillView.estimatedTimings(for: line.text,
                                                   durationMs: Int(audio.duration * 1000))
                : stored
            isPlaying = true
            claimLockScreen()
            publishNowPlaying()
        } catch {
            advance(after: 0, generation: mine, skipping: true)
        }
    }

    private func advance(after duration: TimeInterval, generation mine: Int, skipping: Bool) {
        guard generation == mine else { return }
        if !skipping, let line = current { heard(line, seconds: duration) }
        // A whole lap of lines with no audio must end, not spin.
        skipStreak = skipping ? skipStreak + 1 : 0
        let wait = skipping ? 0 : pause(after: duration)
        let move: () -> Void = { [weak self] in
            guard let self, self.generation == mine else { return }
            self.isInGap = false
            if !skipping, self.repeatMode == .one {
                self.startCurrent()
            } else if self.position + 1 < self.order.count {
                self.position += 1
                self.startCurrent()
            } else if self.repeatMode != .off, self.skipStreak < self.order.count {
                self.position = 0
                if self.shuffle {
                    self.order = Self.makeOrder(lines: self.lines, shuffled: true, first: nil)
                }
                self.startCurrent()
            } else {
                // The end of the list: stay on the last line, stopped.
                self.flushListening(finished: true)
                self.isPlaying = false
                self.publishNowPlaying()
            }
        }
        guard wait > 0 else { move(); return }
        isInGap = true
        // Silence is PLAYED, not slept: an app in the background with nothing
        // coming out of it is suspended within seconds, and the next line
        // would never start with the screen off.
        Self.isStartingOwnAudio = true
        defer { Self.isStartingOwnAudio = false }
        do {
            try audio.play(Self.silence(seconds: wait), source: "playlist") { [weak self] in
                guard self?.generation == mine else { return }
                move()
            }
        } catch {
            gapTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                move()
            }
        }
    }

    /// The gap after the line that just played. "Time to say it back" is for
    /// the learner's own lines — the other person's line in a scene is
    /// answered by the next one, not repeated. Between two scenes a short
    /// breath, so one conversation doesn't run straight into the next.
    private func pause(after duration: TimeInterval) -> TimeInterval {
        guard let line = current else { return 0 }
        // The pause to say a line back is as long as the line SOUNDED, so
        // at a slower speed it is longer.
        let heard = duration / Double(max(speed, 0.5))
        var wait = gap == .echo && !line.isToSayBack ? 0 : gap.seconds(after: heard)
        let nextPosition = position + 1
        if order.indices.contains(nextPosition), repeatMode != .one,
           lines[order[nextPosition]].bookId != line.bookId {
            wait = max(wait, 1.2)
        }
        return wait
    }

    /// True while this player is the one calling `AudioPlayer.play`, so the
    /// "someone else wants the speaker" hook doesn't pause us for our own line.
    static var isStartingOwnAudio = false

    /// Play order. Shuffling a list that holds whole conversations shuffles
    /// the SCENES and keeps every scene's lines in order — a dialogue out of
    /// order is noise.
    private static func makeOrder(lines: [PlaylistLine], shuffled: Bool, first: Int?) -> [Int] {
        let count = lines.count
        guard shuffled else {
            guard let first, first > 0, first < count else { return Array(0..<count) }
            return Array(first..<count) + Array(0..<first)
        }
        guard lines.contains(where: { !$0.isFluentSelf }) else {
            var order = Array(0..<count)
            order.shuffle()
            if let first, let i = order.firstIndex(of: first) { order.swapAt(0, i) }
            return order
        }
        var groups: [[Int]] = []
        for i in 0..<count {
            if let last = groups.last?.last, lines[last].bookId == lines[i].bookId {
                groups[groups.count - 1].append(i)
            } else {
                groups.append([i])
            }
        }
        groups.shuffle()
        if let first, let g = groups.firstIndex(where: { $0.contains(first) }) {
            groups.swapAt(0, g)
        }
        return groups.flatMap { $0 }
    }

    /// A silent 16 kHz mono WAV.
    private static func silence(seconds: TimeInterval) -> Data {
        let rate = 16_000
        let samples = Int(Double(rate) * seconds)
        let dataBytes = samples * 2
        var d = Data()
        func le32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); le32(36 + dataBytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); le32(16); le16(1); le16(1)
        le32(rate); le32(rate * 2); le16(2); le16(16)
        d.append(contentsOf: Array("data".utf8)); le32(dataBytes)
        d.append(Data(count: dataBytes))
        return d
    }

    // MARK: - Listening record (nawana Podcast)

    /// What has been heard of the episode playing now, sent as ONE
    /// `podcast_listened` row when the listener leaves it (another episode,
    /// pause, stop, the list's end). Pausing and coming back makes a second
    /// row for the same episode; analysis sums them per learner + episode.
    private struct Listening {
        let bookId: UUID
        let number: Int
        let category: String
        var seconds: Double = 0
        var lines: Set<UUID> = []
        var lastLineHeard = false
    }
    private var listening: Listening?
    /// Episodes already reported as started in this list, so a pause and a
    /// resume isn't a second start.
    private var startedEpisodes: Set<UUID> = []

    private func heard(_ line: PlaylistLine, seconds: TimeInterval) {
        guard let number = line.episodeNumber else { return }
        if listening?.bookId != line.bookId {
            flushListening(finished: false)
            listening = Listening(bookId: line.bookId, number: number,
                                  category: line.episodeCategory ?? "")
            if startedEpisodes.insert(line.bookId).inserted {
                Analytics.capture("podcast_started", ["episode": number,
                                                      "category": line.episodeCategory ?? ""])
            }
        }
        listening?.seconds += seconds
        listening?.lines.insert(line.id)
        if lines.last(where: { $0.bookId == line.bookId })?.id == line.id {
            listening?.lastLineHeard = true
        }
    }

    private func flushListening(finished: Bool) {
        guard let l = listening, !l.lines.isEmpty else { listening = nil; return }
        listening = nil
        let total = lines.filter { $0.bookId == l.bookId }.count
        let d = UserDefaults.standard
        Analytics.capture("podcast_listened", [
            "episode": l.number,
            "category": l.category,
            "seconds": Int(l.seconds.rounded()),
            "lines_heard": l.lines.count,
            "lines_total": total,
            "completed": l.lastLineHeard,
            "speed": Double(speed),
            "gap": gap.rawValue,
            "translation": d.bool(forKey: "futurevoice.playlist.translation"),
            "captions": d.object(forKey: "futurevoice.playlist.captions") as? Bool ?? true,
        ])
    }

    // MARK: - Lock screen

    private var ownsLockScreen = false

    private func claimLockScreen() {
        guard !ownsLockScreen else { return }
        ownsLockScreen = true
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
            command.isEnabled = true
        }
        // MediaPlayer promises no thread for a remote command; hop to main.
        center.playCommand.addTarget { _ in Task { @MainActor in PlaylistPlayer.shared.resume() }; return .success }
        center.pauseCommand.addTarget { _ in Task { @MainActor in PlaylistPlayer.shared.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlaylistPlayer.shared.togglePlayPause() }; return .success
        }
        center.nextTrackCommand.addTarget { _ in Task { @MainActor in PlaylistPlayer.shared.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlaylistPlayer.shared.previous() }; return .success
        }
        for unused in [center.seekForwardCommand, center.seekBackwardCommand,
                       center.changePlaybackPositionCommand, center.stopCommand] {
            unused.isEnabled = false
        }
    }

    private func releaseLockScreen() {
        guard ownsLockScreen else { return }
        ownsLockScreen = false
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Live Activity

    private var activity: Activity<SceneListeningAttributes>?

    /// The line being said, in the Dynamic Island and on the lock screen.
    /// Started from the foreground (the tap that starts a list), updated from
    /// wherever the list is when a line changes, ended on Stop.
    private func publishLiveActivity() {
        guard let line = current else { return }
        let state = SceneListeningAttributes.ContentState(
            speaker: line.speaker,
            line: String(line.text.prefix(300)),
            isFluentSelf: line.isFluentSelf,
            sceneTitle: line.bookTitle,
            position: position + 1,
            total: order.count,
            isPlaying: isPlaying || isInGap)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(
                attributes: SceneListeningAttributes(title: title), content: content)
        }
    }

    private func endLiveActivity() {
        guard let ending = activity else { return }
        activity = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }

    private func publishNowPlaying() {
        publishLiveActivity()
        guard ownsLockScreen, let line = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: line.text,
            MPMediaItemPropertyArtist: line.bookTitle,
            MPMediaItemPropertyAlbumTitle: title,
            MPMediaItemPropertyPlaybackDuration: audio.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
