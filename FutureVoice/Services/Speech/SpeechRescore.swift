import Foundation

/// Scores a stored take again, from its own recording (2026-11-17).
///
/// Until that day a piece of a take was judged against the script the
/// prompter's cursor had walked, and a cursor off the voice left the take
/// with words it never said ("fifty-one to ninety" marked as "2025") and a
/// pronunciation score taken against the wrong sentences. The recording is
/// still on the phone, so the take can be read the way a new one is: cut
/// where it was cut, each piece placed in the script by its own words
/// (`SpeechTakeSession.judge`), and the numbers computed again by the same
/// code a fresh take runs through. Asked for by hand, one take at a time:
/// every piece is a new read and a new assessment.
enum SpeechRescore {
    /// The take as scored again, saved; nil when the recording is gone or a
    /// piece could not be read (the take is left as it was).
    @MainActor
    static func run(_ take: SpeechTake, script: SpeechScript) async -> SpeechTake? {
        let language = script.language, body = script.body
        let audioURL = SpeechStore.mediaURL(take.audioFilename)
        guard let wav = await Task.detached(operation: { AudioLoudness.wav16kMono(fromFileAt: audioURL) }).value
        else { return nil }
        let cuts = cuts(ofWAV: wav, startsMs: take.assessmentStartsMs)
        guard !cuts.isEmpty else { return nil }
        let track = SpeechPrompterTrack(script: body, language: language)

        let judged: [SpeechTakeSession.Piece?] = await withTaskGroup(of: (Int, SpeechTakeSession.Piece?).self) { group in
            for (index, cut) in cuts.enumerated() {
                group.addTask {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("rescore-\(UUID().uuidString).wav")
                    guard (try? cut.wav.write(to: url)) != nil else { return (index, nil) }
                    defer { try? FileManager.default.removeItem(at: url) }
                    return (index, await SpeechTakeSession.judge(url, track: track, language: language,
                                                                 startMs: cut.startMs))
                }
            }
            var got = [SpeechTakeSession.Piece?](repeating: nil, count: cuts.count)
            for await (index, piece) in group { got[index] = piece }
            return got
        }
        let pieces = judged.compactMap { $0 }
        guard pieces.count == cuts.count else { return nil }

        let joiner = LanguageCatalog.writesSpaces(language) ? " " : ""
        let transcript = pieces.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: joiner)
        guard !transcript.isEmpty else { return nil }
        var prons: [PronunciationResult] = []
        var assessed: [SpeechDelivery.Piece] = []
        for piece in pieces {
            guard let pron = piece.pron else { continue }
            prons.append(pron)
            assessed.append(.init(reference: piece.reference, result: pron, startMs: piece.startMs))
        }
        let pronunciation = SpeechTakeSession.pronunciation(of: prons)
        let pronScore = pronunciation?.score
        let envelope = await Task.detached { SpeechAnalyzer.envelope(of: audioURL) }.value
        var metrics = await Task.detached {
            SpeechAnalyzer.analyze(script: body, transcript: transcript, language: language,
                                   envelope: envelope, pronunciation: pronScore)
        }.value

        // Season 2's score, when the take had one or would get one today.
        if take.metrics.reading != nil || SpeechReading.isActive(for: language) {
            let deliveryPieces = assessed
            let delivered = await Task.detached {
                SpeechDelivery.measure(deliveryPieces, language: language, audioURL: audioURL)
            }.value
            let fluent = SpeechListenService.available(for: script) ? await SpeechListenService.reading(script) : nil
            let single = fluent.map { SpeechReference(version: 2, male: $0.words, female: $0.words) }
            let paired = single == nil ? await SpeechReferenceService.fetch(text: body, language: language) : nil
            if let reference = single ?? paired,
               var reading = SpeechTakeSession.reading(pieces: assessed, reference: reference, script: body,
                                                       metrics: metrics, delivery: delivered, fluent: fluent?.words) {
                if let fluent {
                    reading.gender = fluent.gender
                    reading.reference = "listen"
                }
                metrics.reading = reading
                metrics.overall = reading.total
                metrics.scoring = SpeechReading.version
            } else if take.metrics.reading != nil {
                // Its scoring can't be made again right now (offline, no
                // reference): better the old take than one scored another way.
                return nil
            }
        }

        guard var current = SpeechStore.shared.takes.first(where: { $0.id == take.id }) else { return nil }
        let before = current.metrics
        current.transcript = transcript
        current.metrics = metrics
        current.pronunciationWords = pronunciation?.weakWords
        current.assessments = prons.isEmpty ? nil : prons
        current.assessmentStartsMs = assessed.count == prons.count && !prons.isEmpty ? assessed.map(\.startMs) : nil
        SpeechStore.shared.save(current)
        PronunciationLedger.shared.record(prons, id: take.id, surface: "speech", language: language,
                                          date: take.createdAt)
        Analytics.capture("speech_take_rescored", [
            "overall_before": before.overall, "overall": metrics.overall,
            "accuracy_before": before.accuracy, "accuracy": metrics.accuracy,
            "pron_before": before.pronunciation ?? -1, "pron": metrics.pronunciation ?? -1,
            "pieces": pieces.count, "placed_pieces": pieces.filter(\.placed).count,
        ])
        return current
    }

    /// The recording cut where the take was cut (`assessmentStartsMs`: every
    /// cut was at a pause), or into windows when the take kept no cuts or
    /// one of them is longer than the assessment takes.
    nonisolated static func cuts(ofWAV wav: Data, startsMs: [Int]?) -> [(startMs: Int, wav: Data)] {
        let header = 44, rate = 16_000
        guard wav.count > header + 2 else { return [] }
        let pcm = wav.subdata(in: header..<wav.count)
        let total = pcm.count / 2
        var bounds = (startsMs ?? []).map { max(0, $0) * rate / 1000 }.filter { $0 < total }
        bounds = Array(Set(bounds)).sorted()
        if bounds.first != 0 { bounds.insert(0, at: 0) }
        var out: [(startMs: Int, wav: Data)] = []
        for (i, lo) in bounds.enumerated() {
            let hi = i + 1 < bounds.count ? bounds[i + 1] : total
            // A sliver (the countdown's tail) holds no words.
            guard hi - lo >= rate * 3 / 10 else { continue }
            out.append((lo * 1000 / rate,
                        AudioLoudness.wavData(fromPCM16: pcm.subdata(in: (lo * 2)..<(hi * 2)), sampleRate: rate)))
        }
        let longest = out.map { ($0.wav.count - header) / 2 }.max() ?? 0
        guard (startsMs ?? []).count > 1, Double(longest) / Double(rate) <= PronunciationAssessor.maxSeconds else {
            var windows: [(startMs: Int, wav: Data)] = [], bytes = 0
            for window in PronunciationAssessor.windows(ofWAV: wav) {
                windows.append((bytes / 32, window))
                bytes += max(0, window.count - header)
            }
            return windows
        }
        return out
    }
}
