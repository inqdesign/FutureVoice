import SwiftUI

// MARK: - Talk tab button

/// The listening door on the Talk tab: a glass circle at the bottom-left,
/// the same size as the quiz face on the right. Resting, a pair of
/// headphones; while situations play, a ring of how far through the list it
/// is. A tap brings up the player — the circle is too small to mean two
/// things.
struct PlaylistButton: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var player = PlaylistPlayer.shared
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            PlaylistButtonFace(player: player, audio: player.audio)
                .frame(width: 30, height: 30)
        }
        .modifier(PlaylistGlassCircle())
        .accessibilityLabel(Text("My situations"))
        .sheet(isPresented: $showing) {
            ScenePlayerSheet().environmentObject(appState)
        }
    }
}

private struct PlaylistButtonFace: View {
    @ObservedObject var player: PlaylistPlayer
    @ObservedObject var audio: AudioPlayer

    var body: some View {
        ZStack {
            if player.hasQueue {
                Circle()
                    .trim(from: 0, to: player.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-4)
            }
            if player.isPlaying {
                PlayingBars(isAnimating: true)
                    .frame(width: 18, height: 16)
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "headphones")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(player.hasQueue ? Color.accentColor : .primary)
            }
        }
    }
}

private struct PlaylistGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .background(Circle().fill(.regularMaterial))
        }
    }
}

// MARK: - Playing bars

/// The "this is playing" mark: four bars that rise and fall like a voice
/// (founder, 2026-10-19 — the waveform symbol's colour sweep didn't read as
/// sound). Paused, they rest low; Reduce Motion keeps them still.
struct PlayingBars: View {
    var isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each bar its own speed and phase, so the four never move as one.
    private static let bars: [(speed: Double, phase: Double)] =
        [(7.1, 0.0), (9.3, 1.7), (6.2, 3.1), (8.4, 4.6)]

    var body: some View {
        TimelineView(.animation(paused: !isAnimating || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let gap = geo.size.width * 0.12
                let width = (geo.size.width - gap * Double(Self.bars.count - 1)) / Double(Self.bars.count)
                HStack(alignment: .center, spacing: gap) {
                    ForEach(Self.bars.indices, id: \.self) { i in
                        Capsule()
                            .frame(width: width, height: geo.size.height * level(i, at: t))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func level(_ i: Int, at t: TimeInterval) -> Double {
        guard isAnimating, !reduceMotion else { return [0.35, 0.6, 0.45, 0.3][i] }
        let bar = Self.bars[i]
        let wave = (sin(t * bar.speed + bar.phase) + sin(t * bar.speed * 0.53 + bar.phase * 2)) / 2
        return 0.25 + 0.75 * abs(wave)
    }
}

// MARK: - The player

/// A floating sheet that IS the player. The line being said fills the top,
/// the controls sit at the bottom and never move whatever the line's length
/// (a long line scrolls in its own space), and the situations are one tap
/// away behind the list button, opposite the options. Half height by
/// default, so the page stays visible behind it.
struct ScenePlayerSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var player = PlaylistPlayer.shared
    @State private var tracks: [SceneTrack] = []
    @State private var shows: [NewsShowEpisode] = []
    @State private var loaded = false
    @State private var showingList: Bool

    /// `startOnList` opens straight on the library (the capture harness).
    init(startOnList: Bool = false) {
        _showingList = State(initialValue: startOnList)
    }

    private static var listTitle: String { explain("My situations") }
    private static var showTitle: String { explain("nawana Podcast") }

    private var allLines: [PlaylistLine] { tracks.flatMap(\.lines) }
    private var showLines: [PlaylistLine] { shows.flatMap(\.lines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NowPlayingCaption(isEmpty: loaded && tracks.isEmpty && shows.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                PlayerControls(onPlayAll: playAll, canPlay: !tracks.isEmpty || !shows.isEmpty)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .navigationTitle(Text("Player"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingList = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel(Text("Situations"))
                        .disabled(tracks.isEmpty && shows.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { PlayerOptionsMenu() }
            }
            .navigationDestination(isPresented: $showingList) {
                // Bindings, not values: a destination already on screen is not
                // rebuilt when the sheet's state changes, and the episodes
                // arrive after the download — handed over as values, a list
                // opened early stayed empty.
                PlayerLibrary(tracks: $tracks, shows: $shows, onPick: play(from:),
                              onPickShow: play(show:), onPlayAllShows: playAllShows)
            }
        }
        // On the sheet, not the player page: opened straight on the library
        // the page never appears, and nothing would load.
        .task {
            tracks = SceneLibrary.tracks(scenarios: ScenarioStore.shared.load(),
                                         cloneId: appState.voiceCloneId)
            loaded = true
            shows = await NewsShow.episodes(language: appState.targetLanguage)
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func playAll() {
        if allLines.isEmpty {
            Task { await playAllShows() }
        } else {
            player.play(allLines, title: Self.listTitle)
        }
    }

    /// Every episode, newest first. Files are fetched when asked for.
    private func playAllShows() async {
        await withTaskGroup(of: Void.self) { group in
            for episode in shows where !episode.isReady {
                group.addTask { await NewsShow.prepare(episode) }
            }
        }
        player.play(showLines, title: Self.showTitle)
    }

    /// One episode on its own (founder: the whole show, or just the episode).
    /// Picked again while it is playing, it carries on rather than restarting.
    private func play(show episode: NewsShowEpisode) async {
        if player.title == Self.showTitle, player.current?.bookId == episode.id { return }
        await NewsShow.prepare(episode)
        player.play(episode.lines, title: Self.showTitle)
    }

    /// Every situation plays on from the one picked, so picking a scene
    /// starts listening rather than ending at its last line.
    private func play(from track: SceneTrack) {
        let lines = allLines
        guard let start = lines.firstIndex(where: { $0.bookId == track.id }) else { return }
        if player.title == Self.listTitle, player.lines.map(\.id) == lines.map(\.id),
           let at = player.lines.firstIndex(where: { $0.bookId == track.id }) {
            player.jump(toLine: at)
        } else {
            player.play(lines, title: Self.listTitle, startAt: start)
        }
    }
}

/// What there is to hear, behind two tabs: the nawana Podcast (the
/// platform's daily episodes) and the learner's own situations. Picking one
/// plays it and goes back to the player.
private struct PlayerLibrary: View {
    @Binding var tracks: [SceneTrack]
    @Binding var shows: [NewsShowEpisode]
    let onPick: (SceneTrack) -> Void
    let onPickShow: (NewsShowEpisode) async -> Void
    let onPlayAllShows: () async -> Void
    /// What is being fetched right now: an episode, or `allId` for Play all.
    @State private var fetching: UUID?
    private static let allId = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var player = PlaylistPlayer.shared
    @AppStorage("futurevoice.playlist.tab") private var tab = Tab.podcast

    enum Tab: String { case podcast, situations }

    var body: some View {
        List {
            switch tab {
            case .podcast: podcast
            case .situations: situations
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $tab) {
                    Text("Podcast").tag(Tab.podcast)
                    Text("My situations").tag(Tab.situations)
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var podcast: some View {
        if shows.isEmpty {
            ContentUnavailableView {
                Label("nawana Podcast", systemImage: "newspaper")
            } description: {
                Text("A new episode every day, in English for now.")
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                Button {
                    fetch(Self.allId) { await onPlayAllShows() }
                } label: {
                    HStack {
                        Label("Play all", systemImage: "play.fill")
                        Spacer()
                        if fetching == Self.allId { ProgressView() }
                    }
                }
                ForEach(shows) { episode in
                    Button {
                        fetch(episode.id) { await onPickShow(episode) }
                    } label: { row(episode) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Fetch, play, then back to the player. One fetch at a time.
    private func fetch(_ id: UUID, _ action: @escaping () async -> Void) {
        guard fetching == nil else { return }
        fetching = id
        Task {
            await action()
            fetching = nil
            dismiss()
        }
    }

    @ViewBuilder private var situations: some View {
        if tracks.isEmpty {
            ContentUnavailableView {
                Label("No situations to hear yet", systemImage: "headphones")
            } description: {
                Text("Watch a situation once and it plays here, both voices, whenever you like.")
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(tracks) { track in
                Button {
                    onPick(track)
                    dismiss()
                } label: { row(track) }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ track: SceneTrack) -> some View {
        let playing = player.hasQueue && player.current?.bookId == track.id
        return HStack(spacing: 12) {
            Group {
                if playing {
                    PlayingBars(isAnimating: player.isPlaying || player.isInGap)
                        .frame(width: 16, height: 14)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
            .foregroundStyle(.tint)
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(playing ? Color.accentColor : .primary)
                    .lineLimit(2)
                Text(track.otherName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func episodeLabel(_ episode: NewsShowEpisode) -> String {
        "EP \(episode.number) · "
            + episode.date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }

    private func row(_ episode: NewsShowEpisode) -> some View {
        let playing = player.hasQueue && player.current?.bookId == episode.id
        return HStack(spacing: 12) {
            Group {
                if fetching == episode.id {
                    ProgressView()
                } else if playing {
                    PlayingBars(isAnimating: player.isPlaying || player.isInGap)
                        .frame(width: 16, height: 14)
                } else {
                    Image(systemName: NewsShow.icon(for: episode.category))
                }
            }
            .foregroundStyle(.tint)
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .foregroundStyle(playing ? Color.accentColor : .primary)
                    .lineLimit(2)
                // The hosts are the same on every episode; how long it is helps
                // choose. "%@ · %lld min" is already in every language.
                Text("\(episodeLabel(episode)) · \(episode.minutes) min")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Now playing

/// Who is speaking and the line in karaoke — words already said in full
/// colour, the word being said in the accent, the rest dimmed — with its
/// meaning in the learner's own language when they want it. A long line
/// scrolls here so the controls below it never move.
private struct NowPlayingCaption: View {
    let isEmpty: Bool

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var player = PlaylistPlayer.shared
    @ObservedObject private var audio = PlaylistPlayer.shared.audio
    @AppStorage("futurevoice.playlist.captions") private var showCaptions = true
    @AppStorage("futurevoice.playlist.translation") private var showTranslation = false
    @State private var translation: String?
    @State private var revealed: UUID?

    var body: some View {
        Group {
            if let line = player.current {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.speaker)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(line.isFluentSelf ? Color.accentColor : .secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(player.position + 1) / \(player.order.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            caption(line)
                                .font(.title3.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .blur(radius: showCaptions || revealed == line.id ? 0 : 7)
                                .contentShape(Rectangle())
                                .onTapGesture { if !showCaptions { revealed = line.id } }
                                .accessibilityLabel(Text(line.text))
                            if showTranslation, let translation {
                                Text(translation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    Text(line.bookTitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else if isEmpty {
                ContentUnavailableView {
                    Label("No situations to hear yet", systemImage: "headphones")
                } description: {
                    Text("Watch a situation once and it plays here, both voices, whenever you like.")
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("Press play to hear every situation, or pick one from the list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: TranslationKey(line: player.current?.id, on: showTranslation)) {
            await loadTranslation()
        }
    }

    private struct TranslationKey: Hashable { let line: UUID?; let on: Bool }

    private func loadTranslation() async {
        translation = nil
        guard showTranslation, let line = player.current,
              !LanguageCatalog.sameLanguage(appState.nativeLanguage, appState.targetLanguage)
        else { return }
        // A podcast line is shown only in the translations it shipped with:
        // made once by the publisher and read by everyone. It never asks for
        // a new one per phone (founder, 2026-10-19: API cost).
        if let shipped = line.translations {
            translation = shipped[appState.nativeLanguage]
            return
        }
        if let cached = Translator.cached(line.text, to: appState.nativeLanguage) {
            translation = cached
            return
        }
        let t = await Translator.translate(line.text, to: appState.nativeLanguage)
        if player.current?.id == line.id { translation = t }
    }

    private func caption(_ line: PlaylistLine) -> Text {
        let timings = player.timings
        guard !timings.isEmpty else { return Text(line.text) }
        let nowMs = Int(audio.currentTime * 1000)
        let finished = !player.isPlaying || player.isInGap
        let separator = WordSplitter.spaced ? " " : ""
        var out = AttributedString()
        for (i, t) in timings.enumerated() {
            var word = AttributedString(t.word)
            if finished || nowMs >= t.endMs {
                word.foregroundColor = .primary
            } else if nowMs >= t.startMs {
                word.foregroundColor = .accentColor
            } else {
                word.foregroundColor = .secondary
            }
            out += word
            if i < timings.count - 1 { out += AttributedString(separator) }
        }
        return Text(out)
    }
}

/// Shuffle · previous · play/pause · next · repeat. Always the same row in
/// the same place; before anything is loaded, play starts every situation.
private struct PlayerControls: View {
    var onPlayAll: () -> Void
    var canPlay: Bool
    @ObservedObject private var player = PlaylistPlayer.shared

    var body: some View {
        HStack {
            Button { player.setShuffle(!player.shuffle) } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
            }
            .accessibilityLabel(Text("Shuffle"))
            Spacer()
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .disabled(!player.hasQueue)
                .accessibilityLabel(Text("Previous"))
            Spacer()
            Button {
                player.hasQueue ? player.togglePlayPause() : onPlayAll()
            } label: {
                Image(systemName: player.isPlaying || player.isInGap ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
            }
            .disabled(!player.hasQueue && !canPlay)
            .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
            Spacer()
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .disabled(!player.hasQueue)
                .accessibilityLabel(Text("Next"))
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? .secondary : Color.accentColor)
            }
            .accessibilityLabel(Text("Repeat"))
        }
        .font(.title2)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

/// Captions, translation, the pause between lines, and Stop.
private struct PlayerOptionsMenu: View {
    @ObservedObject private var player = PlaylistPlayer.shared
    @AppStorage("futurevoice.playlist.captions") private var showCaptions = true
    @AppStorage("futurevoice.playlist.translation") private var showTranslation = false

    var body: some View {
        Menu {
            Toggle(isOn: $showCaptions) { Label("Captions", systemImage: "captions.bubble") }
            Toggle(isOn: $showTranslation) { Label("Translation", systemImage: "character.bubble") }
            Picker(selection: $player.gap) {
                Text("No pause").tag(PlaylistPlayer.Gap.none)
                Text("1 second").tag(PlaylistPlayer.Gap.short)
                Text("Time to say it back").tag(PlaylistPlayer.Gap.echo)
            } label: {
                Label("Pause between lines", systemImage: "pause")
            }
            .pickerStyle(.menu)
            Picker(selection: $player.speed) {
                ForEach(PlaylistPlayer.speeds, id: \.self) { s in
                    Text(verbatim: s == 1 ? "1×" : String(format: "%.2g×", s)).tag(s)
                }
            } label: {
                Label("Speed", systemImage: "gauge.with.dots.needle.33percent")
            }
            .pickerStyle(.menu)
            if player.hasQueue {
                Divider()
                Button(role: .destructive) { player.close() } label: {
                    Label("Stop playing", systemImage: "xmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("Options"))
    }
}
