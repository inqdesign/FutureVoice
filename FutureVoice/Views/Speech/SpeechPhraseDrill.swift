import SwiftUI

// Fix one phrase (2026-11-13, founder): a mark on a Season 2 result (a stop
// where the fluent reading runs on, a word held far longer) opens the phrase
// around it. Each word's length is drawn twice, the fluent reading's and the
// learner's; both can be heard; and the phrase is said again until it holds
// together. Nothing here changes the take's score: it is practice.

/// A mark on the result page, by the script's written word.
struct SpeechPhraseMark: Identifiable, Hashable {
    enum Kind: Hashable { case stop, held }
    let word: Int
    let kind: Kind
    /// The stop's length, or how long the word was held.
    let seconds: Double
    var id: String { "\(word)-\(kind)" }
}

enum SpeechPhrase {
    /// The phrase around a mark: back to the last punctuation and forward to
    /// the next, at most four words either side (my choice: enough to be a
    /// phrase, short enough to say in one breath). A stop's phrase always
    /// holds the word after the stop.
    static func around(_ mark: SpeechPhraseMark, written: [String]) -> ClosedRange<Int> {
        let n = written.count
        guard n > 0 else { return 0...0 }
        let i = min(max(0, mark.word), n - 1)
        var start = i
        while start > 0, i - start < 4, !endsPhrase(written[start - 1]) { start -= 1 }
        var end = mark.kind == .stop ? min(n - 1, i + 1) : i
        while end < n - 1, end - i < 4, !endsPhrase(written[end]) { end += 1 }
        return start...end
    }

    static func endsPhrase(_ word: String) -> Bool {
        let tail = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]»"))
        return tail.last.map { ".!?…,;:—–".contains($0) } ?? false
    }

    /// The take's words timed against its own audio file, in ms: each
    /// assessed piece's words moved by where the piece began. nil on takes
    /// that didn't keep where their pieces began.
    static func takeWords(_ take: SpeechTake) -> [SpeechReference.Word]? {
        guard let pieces = take.assessments, let starts = take.assessmentStartsMs,
              starts.count == pieces.count else { return nil }
        var out: [SpeechReference.Word] = []
        for (piece, start) in zip(pieces, starts) {
            for w in piece.words where !w.isOmission && !w.isInsertion && w.durationMs > 0 {
                let s: Int = start + w.offsetMs
                let e: Int = s + w.durationMs
                out.append(SpeechReference.Word(w: w.word, s: s, e: e))
            }
        }
        return out.isEmpty ? nil : out
    }

    /// One try at the phrase against the fluent reading's timing of it.
    struct Judgement: Equatable {
        var missing: Int
        /// Stops inside the phrase where the fluent reader runs on.
        var stops: [String]
        /// Words held more than twice as long as the fluent reader holds
        /// them, once the reader's own pace is taken out (the result page's
        /// rule).
        var held: [String]
        /// How closely the long-and-short pattern follows the fluent one
        /// (Pearson r of log word lengths); nil under four words.
        var rhythm: Double?

        /// 0.8 is my choice for one phrase; the whole-reading figures are
        /// natives ~0.93, learners ~0.82, and a short phrase wobbles more.
        static let rhythmBar = 0.8

        var matched: Bool { missing == 0 && stops.isEmpty && held.isEmpty && (rhythm ?? 1) >= Self.rhythmBar }
    }

    static func judge(said: [SpeechListenText.Display], fluent: [SpeechListenText.Display]) -> Judgement {
        let n = min(said.count, fluent.count)
        var j = Judgement(missing: said.prefix(n).filter { $0.time == nil }.count, stops: [], held: [], rhythm: nil)
        for k in 0..<max(0, n - 1) where !endsPhrase(said[k].text) {
            guard let a = said[k].time, let b = said[k + 1].time else { continue }
            let gap = b.start - a.end
            let fluentGap = (fluent[k + 1].time?.start ?? 0) - (fluent[k].time?.end ?? 0)
            if gap >= SpeechReading.pauseSeconds, fluentGap < SpeechReading.pauseSeconds {
                j.stops.append(said[k].text)
            }
        }
        var pairs: [(String, Double, Double)] = []
        for k in 0..<n {
            if let a = said[k].time, let b = fluent[k].time {
                pairs.append((said[k].text, max(0.02, a.end - a.start), max(0.02, b.end - b.start)))
            }
        }
        if pairs.count >= 4 {
            j.rhythm = SpeechReading.pearson(pairs.map { log($0.2) }, pairs.map { log($0.1) })
        }
        if pairs.count >= 2 {
            let ratios = pairs.map { log($0.1 / $0.2) }
            let tempo = ratios.sorted()[ratios.count / 2]
            for (p, r) in zip(pairs, ratios) where exp(r - tempo) >= 2 && p.1 - p.2 >= 0.15 {
                j.held.append(p.0)
            }
        }
        return j
    }
}

struct SpeechPhraseDrillSheet: View {
    let script: SpeechScript
    let take: SpeechTake
    let mark: SpeechPhraseMark

    @Environment(\.dismiss) private var dismiss
    @StateObject private var listen = SpeechListenModel()
    @StateObject private var yours = AudioPlayer()
    @StateObject private var recorder = AudioRecorder()
    @State private var tries: [SpeechPhrase.Judgement] = []
    @State private var judging = false
    @State private var failed = false

    private var written: [String] {
        script.body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    private var range: ClosedRange<Int> { SpeechPhrase.around(mark, written: written) }
    private var phraseText: String { written[range].joined(separator: " ") }

    private var fluentWords: [SpeechListenText.Display] {
        guard let words = listen.audioWords else { return [] }
        let all = SpeechListenText.display(body: script.body, words: words)
        return all.count == written.count ? Array(all[range]) : []
    }
    private var yourWords: [SpeechListenText.Display] {
        guard let words = SpeechPhrase.takeWords(take) else { return [] }
        let all = SpeechListenText.display(body: script.body, words: words)
        return all.count == written.count ? Array(all[range]) : []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "“\(phraseText)”")
                            .font(.title3.weight(.semibold))
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(mark.kind == .stop ? "A stop" : "A held word")
                }

                if !fluentWords.isEmpty {
                    Section {
                        SpeechPhraseBars(written: Array(written[range]), fluent: fluentWords, yours: yourWords)
                            .padding(.vertical, 4)
                    } header: {
                        Text("How long each word lasts")
                    } footer: {
                        Text("\(Text(verbatim: "■").foregroundStyle(Color.accentColor.opacity(0.5))) the fluent reading · \(Text(verbatim: "■").foregroundStyle(.primary)) yours")
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        Button { playFluent() } label: { Label("Fluent", systemImage: "play.fill") }
                            .disabled(fluentWords.isEmpty)
                        Button { playYours() } label: { Label("Yours", systemImage: "play.fill") }
                            .disabled(yourWords.isEmpty)
                        Button { playBoth() } label: { Text("One after the other") }
                            .disabled(fluentWords.isEmpty || yourWords.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    VStack(spacing: 12) {
                        if !tries.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(tries.enumerated()), id: \.offset) { i, t in
                                    Text(verbatim: "\(i + 1)")
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(t.matched ? Color.green.opacity(0.25) : Color.orange.opacity(0.2)))
                                }
                            }
                        }
                        Button { record() } label: {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Circle().fill(Color.red))
                        }
                        .buttonStyle(.plain)
                        .disabled(judging || fluentWords.isEmpty)
                        .accessibilityLabel(Text(recorder.isRecording ? "Stop" : "Say it again"))
                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Fix this phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await listen.load(script) }
            .onDisappear {
                listen.stop()
                yours.stop()
                _ = recorder.stop()
            }
        }
    }

    private var explanation: String {
        let word = written[min(mark.word, written.count - 1)]
        switch mark.kind {
        case .stop:
            return explain("You stopped \(String(format: "%.1f", mark.seconds))s after “\(word)”. The fluent reading runs straight on.")
        case .held:
            return explain("You held “\(word)” for \(String(format: "%.1f", mark.seconds))s, far longer than the fluent reading.")
        }
    }

    private var status: String {
        if recorder.isRecording { return explain("Say the phrase, then tap stop.") }
        if judging { return explain("Listening…") }
        if failed { return explain("Couldn't check that one. Try again.") }
        guard let last = tries.last else { return explain("Hear the fluent reading, then say it again.") }
        if last.matched { return explain("That holds together. The mark is cleared for this try.") }
        if last.missing > 0 { return explain("Some words didn't come through. Say the whole phrase.") }
        if let s = last.stops.first { return explain("Still a stop after “\(s)”.") }
        if let h = last.held.first { return explain("“\(h)” is still long.") }
        return explain("Closer. Let the small words go faster.")
    }

    private func segment(_ words: [SpeechListenText.Display]) -> (Double, Double)? {
        guard let first = words.compactMap(\.time).first, let last = words.compactMap(\.time).last else { return nil }
        return (max(0, first.start - 0.08), last.end + 0.15)
    }

    private func playFluent(then next: (() -> Void)? = nil) {
        yours.stop()
        guard let seg = segment(fluentWords) else { return }
        listen.playSegment(from: seg.0, to: seg.1)
        if let next {
            Task {
                try? await Task.sleep(for: .seconds(seg.1 - seg.0 + 0.4))
                next()
            }
        }
    }

    private func playYours() {
        listen.player.pause()
        guard let seg = segment(yourWords),
              let data = try? Data(contentsOf: SpeechStore.mediaURL(take.audioFilename)) else { return }
        if !yours.isLoaded { yours.prepare(data) }
        yours.playSegment(from: seg.0, to: seg.1, loop: false)
    }

    private func playBoth() { playFluent { playYours() } }

    private func record() {
        if recorder.isRecording {
            guard let url = recorder.stop() else { return }
            judging = true
            failed = false
            Task {
                defer { judging = false }
                let result = await PronunciationAssessor.assess(
                    audioURL: url, reference: phraseText, language: script.language, surface: "speech_drill")
                try? FileManager.default.removeItem(at: url)
                guard let words = result.result?.words.filter({ !$0.isOmission && !$0.isInsertion && $0.durationMs > 0 }),
                      !words.isEmpty else { failed = true; return }
                let said = SpeechListenText.display(
                    body: phraseText,
                    words: words.map { .init(w: $0.word, s: $0.offsetMs, e: $0.offsetMs + $0.durationMs) })
                let judgement = SpeechPhrase.judge(said: said, fluent: fluentWords)
                tries.append(judgement)
                Analytics.capture("speech_phrase_try", [
                    "kind": mark.kind == .stop ? "stop" : "held",
                    "try": tries.count, "matched": judgement.matched,
                ])
            }
        } else {
            listen.player.pause()
            yours.pause()
            Task {
                guard await recorder.requestPermission() else { failed = true; return }
                _ = try? recorder.start()
            }
        }
    }
}

/// Each word of the phrase with two bars: how long the fluent reader held it
/// and how long you did, on one scale. A stop where the fluent reading runs
/// on is a row of its own.
struct SpeechPhraseBars: View {
    let written: [String]
    let fluent: [SpeechListenText.Display]
    let yours: [SpeechListenText.Display]

    private struct Row: Identifiable {
        let id: Int
        let label: String
        let fluent: Double
        let yours: Double?
        let isStop: Bool
    }

    private var rows: [Row] {
        var out: [Row] = []
        for k in written.indices {
            let f = fluent[k].time.map { $0.end - $0.start } ?? 0
            let y = k < yours.count ? yours[k].time.map { $0.end - $0.start } : nil
            out.append(Row(id: k * 2, label: written[k], fluent: f, yours: y, isStop: false))
            if k + 1 < written.count, !SpeechPhrase.endsPhrase(written[k]), k + 1 < yours.count,
               let a = yours[k].time, let b = yours[k + 1].time, b.start - a.end >= SpeechReading.pauseSeconds {
                let fluentGap = (fluent[k + 1].time?.start ?? 0) - (fluent[k].time?.end ?? 0)
                if fluentGap < SpeechReading.pauseSeconds {
                    out.append(Row(id: k * 2 + 1, label: explain("stop"), fluent: 0, yours: b.start - a.end, isStop: true))
                }
            }
        }
        return out
    }

    var body: some View {
        let scale = max(0.6, rows.map { max($0.fluent, $0.yours ?? 0) }.max() ?? 0.6)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(verbatim: row.label)
                        .font(row.isStop ? .subheadline.italic() : .subheadline.weight(.medium))
                        .foregroundStyle(row.isStop ? .red : .primary)
                        .lineLimit(1)
                        .frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(Color.accentColor.opacity(0.5))
                                .frame(width: max(row.fluent > 0 ? 3 : 0, geo.size.width * row.fluent / scale), height: 7)
                            Capsule().fill(row.isStop ? Color.red : barColor(row))
                                .frame(width: geo.size.width * (row.yours ?? 0) / scale, height: 7)
                        }
                    }
                    .frame(height: 17)
                    Text(verbatim: row.yours.map { String(format: "%.1fs", $0) } ?? "")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    /// Orange when your word ran past twice the fluent length (raw, not
    /// pace-corrected: this is a picture, the judgement is `judge`).
    private func barColor(_ row: Row) -> Color {
        guard let y = row.yours, row.fluent > 0 else { return .primary }
        return y >= row.fluent * 2 && y - row.fluent >= 0.15 ? .orange : .primary
    }
}
