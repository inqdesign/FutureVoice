import SwiftUI

/// A challenge's fluent reading, loaded once and played two ways
/// (2026-11-13, founder): as the challenge page's intro (its opening fades
/// in, then out at the end of a sentence) and whole on the script sheet,
/// the words lighting up as it reads.
@MainActor
final class SpeechListenModel: ObservableObject {
    enum Phase { case idle, loading, ready, unavailable }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var text: SpeechListenText?
    let player = AudioPlayer()
    private var data: Data?
    private var introTask: Task<Void, Never>?
    private var introPlayed = false

    func load(_ script: SpeechScript) async {
        guard phase == .idle else { return }
        phase = .loading
        guard let loaded = await SpeechListenService.load(script),
              let data = try? Data(contentsOf: loaded.file) else {
            phase = .unavailable
            return
        }
        self.data = data
        audioWords = loaded.audio.words
        text = SpeechListenText(body: script.body, words: loaded.audio.words)
        phase = .ready
    }

    /// The reading's timed words (ms), for the phrase drill.
    @Published private(set) var audioWords: [SpeechReference.Word]?

    /// One stretch of the reading (the phrase drill's "Fluent").
    func playSegment(from: Double, to: Double) {
        introTask?.cancel()
        guard let data else { return }
        if !player.isLoaded { player.prepare(data) }
        player.playSegment(from: from, to: to, loop: false)
    }

    var isPlaying: Bool { player.isPlaying }

    /// Play or pause the whole reading, from where it was (the start again
    /// once it has played to the end).
    func toggle() {
        introTask?.cancel()
        introTask = nil
        if player.isPlaying {
            player.pause()
        } else if player.isLoaded {
            player.fadeVolume(to: 1, over: 0)
            let atEnd = player.currentTime >= player.duration - 0.25
            player.playSegment(from: atEnd ? 0 : player.currentTime, to: nil, loop: false)
        } else if let data {
            try? player.play(data, source: "speech_listen")
        }
    }

    /// The reading goes on, whole: an intro still fading in keeps playing at
    /// full volume instead of fading away, a paused one resumes where it was.
    func playOn() {
        guard phase == .ready else { return }
        if player.isPlaying {
            introTask?.cancel()
            introTask = nil
            player.fadeVolume(to: 1, over: 0.3)
        } else {
            toggle()
        }
    }

    /// How far along the reading is, 0…1.
    var progress: Double {
        let total = player.duration > 0 ? player.duration : (text?.duration ?? 0)
        return total > 0 ? min(1, player.currentTime / total) : 0
    }

    /// The challenge page's intro: the opening rises over a couple of
    /// seconds and fades away at the end of the first sentence that finishes
    /// after `seconds` (my choice of length: long enough to hear how it goes,
    /// short enough to read the page under it).
    /// It PAUSES at the end, not stops (2026-11-13, founder): the page's
    /// Script button is a mini player, and a tap goes on from there.
    func playIntro(seconds: Double = 9) {
        guard let data, !introPlayed, introTask == nil, !player.isPlaying else { return }
        introPlayed = true
        guard (try? player.play(data, source: "speech_listen_intro")) != nil else { return }
        player.fadeVolume(to: 0, over: 0)
        player.fadeVolume(to: 1, over: 2.5)
        let end = text?.sentenceEnd(after: seconds) ?? seconds + 3
        introTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, end - 1.2)))
            guard !Task.isCancelled, let self else { return }
            self.player.fadeVolume(to: 0, over: 1.6)
            try? await Task.sleep(for: .seconds(1.7))
            guard !Task.isCancelled else { return }
            self.player.pause()
            self.player.fadeVolume(to: 1, over: 0)
            self.introTask = nil
        }
    }

    /// Quietly to a pause, keeping the place (a take or the takes opening
    /// over the page).
    func fadeToPause() {
        introTask?.cancel()
        introTask = nil
        guard player.isPlaying else { return }
        player.fadeVolume(to: 0, over: 0.4)
        Task { [player] in
            try? await Task.sleep(for: .seconds(0.45))
            player.pause()
            player.fadeVolume(to: 1, over: 0)
        }
    }

    /// Quietly, never cut: leaving the page, or starting a take.
    func fadeOut() {
        introTask?.cancel()
        introTask = nil
        guard player.isPlaying else { player.stop(); return }
        player.fadeVolume(to: 0, over: 0.5)
        Task { [player] in
            try? await Task.sleep(for: .seconds(0.55))
            player.stop()
        }
    }

    func stop() {
        introTask?.cancel()
        introTask = nil
        player.stop()
    }
}

/// The play row at the top of the script sheet: a round play button, the
/// time, and how far along the reading is.
struct SpeechListenRow: View {
    @ObservedObject var model: SpeechListenModel
    @ObservedObject var player: AudioPlayer

    init(model: SpeechListenModel) {
        self.model = model
        self.player = model.player
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(model.phase != .ready)
            .accessibilityLabel(Text(player.isPlaying ? "Pause" : "Play"))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Fluent reading").font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.phase == .loading {
                        ProgressView().controlSize(.small)
                    } else if let total = model.text?.duration, total > 0 {
                        Text(verbatim: "\(clock(player.currentTime)) / \(clock(total))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(1, player.currentTime / max(1, model.text?.duration ?? 1)))
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func clock(_ t: Double) -> String {
        let s = Int(t.rounded(.down))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

/// The script as the fluent reader reads it: words already said in full,
/// the one being said in the accent colour, the rest faded until the voice
/// reaches them. "/" where the reader breathes, "‿" where two words run
/// together. Before it plays (or after), every word is in full.
struct SpeechListenTextView: View {
    let text: SpeechListenText
    @ObservedObject var player: AudioPlayer

    var body: some View {
        let reading = player.isPlaying || player.currentTime > 0
        VStack(alignment: .leading, spacing: 12) {
            ForEach(text.paragraphs.indices, id: \.self) { p in
                paragraph(text.paragraphs[p], at: player.currentTime, reading: reading)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.35), value: Int(player.currentTime * 4))
    }

    private func paragraph(_ tokens: [SpeechListenText.Token], at time: Double, reading: Bool) -> Text {
        var out = Text(verbatim: "")
        for t in tokens {
            let word: Text
            if !reading || t.end <= time {
                word = Text(verbatim: t.text).foregroundColor(.primary)
            } else if t.start <= time {
                word = Text(verbatim: t.text).foregroundColor(.accentColor)
            } else {
                word = Text(verbatim: t.text).foregroundColor(.primary.opacity(0.28))
            }
            out = out + word
            if t.runsOn {
                out = out + Text(verbatim: "‿").foregroundColor(.secondary)
            } else {
                out = out + Text(verbatim: " ")
            }
            if t.breath {
                out = out + Text(verbatim: "/ ").fontWeight(.semibold).foregroundColor(.secondary)
            }
        }
        return out
    }
}

/// What the two marks mean, under the script.
struct SpeechListenLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("\(Text(verbatim: "/").fontWeight(.semibold)) breathe")
            Text("\(Text(verbatim: "‿")) run together")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
