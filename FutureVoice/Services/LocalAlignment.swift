import Foundation
import Speech

/// Free, on-device word-timing extraction for audio we already have on disk.
///
/// Shadow needs a word → time map for karaoke and word-tap looping. The paid
/// path gets it from ElevenLabs' with-timestamps synthesis; but for lines
/// whose audio is already cached (every conversation turn — the streaming
/// TTS returns no timestamps) we can recover the same map locally by running
/// Apple's speech recognizer over the file and reading per-word segment
/// timestamps. Zero credits, and on-device where the hardware supports it.
///
/// Accuracy guard: the recognizer rarely returns EXACTLY the target's words —
/// it merges, splits, or mishears a few, and requiring an exact word-count
/// match meant most lines (Korean especially) fell through to the
/// duration-proportional estimate. Instead we edit-distance-align what it
/// heard against the target's own words, take real times for the words it
/// matched, and interpolate the rest across the gap. If fewer than
/// `minMatchRatio` of the words anchor, the recognition is too unreliable to
/// build on and we return [] so the caller keeps the estimate.
///
/// Displayed words are ALWAYS the target's own (punctuation intact) — the
/// recognizer only ever contributes times.
enum LocalAlignment {

    /// Below this share of anchored words the pass is discarded.
    private static let minMatchRatio = 0.5

    /// - Parameter durationMs: length of the audio, used to bound a trailing
    ///   run of unmatched words. 0 = unknown, in which case the last anchored
    ///   word's end is the bound.
    static func wordTimings(
        audioURL: URL,
        languageCode: String,
        expectedText: String,
        durationMs: Int = 0
    ) async -> [WordTiming] {
        guard await SpeechTranscriber.requestPermission() else { return [] }
        let locale = Locale(identifier: languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else { return [] }

        let expected = tokens(of: expectedText)
        guard !expected.isEmpty else { return [] }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // Bias recognition toward the words we KNOW are in the audio. Capped:
        // Apple documents a ~100-string limit, and this list grows with the
        // line, so a long target used to hand the recognizer an oversized
        // array — which degrades recognition rather than sharpening it.
        request.contextualStrings = Array(
            Set(expected.filter { $0.count > 1 }).prefix(ShadowDrillView.maxRecognitionHints))

        guard let segments = await recognize(recognizer: recognizer, request: request),
              !segments.isEmpty else { return [] }

        let pairing = align(expected: expected.map(normalized),
                            heard: segments.map { normalized($0.substring) })
        let anchored = pairing.compactMap { $0 }.count
        guard Double(anchored) / Double(expected.count) >= minMatchRatio else { return [] }

        return fill(expected: expected, pairing: pairing,
                    heardSpans: segments.map { ($0.timestamp, $0.timestamp + $0.duration) },
                    durationMs: durationMs)
    }

    /// Turn the expected→segment pairing into a gapless, monotonic timeline.
    /// Unmatched words share the span between their anchored neighbours,
    /// split proportionally to how much text each carries.
    ///
    /// Takes plain spans rather than `SFTranscriptionSegment` so the timeline
    /// arithmetic is testable without a live recognizer.
    static func fill(
        expected: [String],
        pairing: [Int?],
        heardSpans: [(start: Double, end: Double)],
        durationMs: Int
    ) -> [WordTiming] {
        var starts = [Double?](repeating: nil, count: expected.count)
        var ends = [Double?](repeating: nil, count: expected.count)
        for (i, segIndex) in pairing.enumerated() {
            guard let segIndex, segIndex < heardSpans.count else { continue }
            starts[i] = heardSpans[segIndex].start
            ends[i] = heardSpans[segIndex].end
        }

        // Bounds for a leading / trailing run with no anchor on one side.
        let audioEnd = durationMs > 0
            ? Double(durationMs) / 1000
            : (ends.compactMap { $0 }.max() ?? 0)

        var i = 0
        while i < expected.count {
            guard starts[i] == nil else { i += 1; continue }
            // The unanchored run [i, j).
            var j = i
            while j < expected.count, starts[j] == nil { j += 1 }
            let spanStart = i > 0 ? (ends[i - 1] ?? 0) : 0
            let spanEnd = j < expected.count ? (starts[j] ?? audioEnd) : audioEnd
            let span = max(0, spanEnd - spanStart)
            let weights = expected[i..<j].map { Double(max($0.count, 1)) }
            let total = weights.reduce(0, +)
            var cursor = spanStart
            for (k, w) in weights.enumerated() {
                let slice = total > 0 ? span * (w / total) : 0
                starts[i + k] = cursor
                cursor += slice
                ends[i + k] = cursor
            }
            i = j
        }

        // Monotonic, non-empty windows — a zero-width highlight never lights.
        var out: [WordTiming] = []
        var previousEnd = 0.0
        for (i, word) in expected.enumerated() {
            let s = max(starts[i] ?? previousEnd, previousEnd)
            let e = max(ends[i] ?? s, s + 0.01)
            previousEnd = e
            out.append(WordTiming(word: word,
                                  startMs: Int(s * 1000),
                                  endMs: Int(e * 1000)))
        }
        return out
    }

    /// Edit-distance alignment: for each expected word, the index of the
    /// recognized segment it corresponds to, or nil when the recognizer
    /// dropped or mangled it.
    static func align(expected: [String], heard: [String]) -> [Int?] {
        let n = expected.count, m = heard.count
        guard n > 0, m > 0 else { return Array(repeating: nil, count: n) }

        // cost[i][j] = edits to turn expected[i...] into heard[j...]
        var cost = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) { cost[i][m] = cost[i + 1][m] + 1 }
        for j in stride(from: m - 1, through: 0, by: -1) { cost[n][j] = cost[n][j + 1] + 1 }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                let sub = cost[i + 1][j + 1] + (expected[i] == heard[j] ? 0 : 1)
                cost[i][j] = min(sub, min(cost[i + 1][j] + 1, cost[i][j + 1] + 1))
            }
        }

        var pairing = [Int?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            let sub = cost[i + 1][j + 1] + (expected[i] == heard[j] ? 0 : 1)
            if cost[i][j] == sub {
                // Only an EXACT hit anchors a time; a substitution means the
                // recognizer heard something else there and its timestamp is
                // not trustworthy for this word.
                if expected[i] == heard[j] { pairing[i] = j }
                i += 1; j += 1
            } else if cost[i][j] == cost[i + 1][j] + 1 {
                i += 1          // expected word the recognizer dropped
            } else {
                j += 1          // recognizer word with no counterpart
            }
        }
        return pairing
    }

    /// Match key: case- and punctuation-insensitive, so "Sure," and "sure"
    /// anchor to each other.
    static func normalized(_ s: String) -> String {
        String(String.UnicodeScalarView(
            s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        ))
    }

    /// One-shot recognition with a hard timeout AND cooperative cancellation —
    /// a recognizer that never reports final/error must not hang, and when the
    /// caller's Task is cancelled (e.g. the learner starts a live mic session,
    /// which must not run a SECOND speech recognizer concurrently) the
    /// underlying `SFSpeechRecognitionTask` is actually stopped, not just
    /// abandoned mid-flight.
    private static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        timeout: TimeInterval = 15
    ) async -> [SFTranscriptionSegment]? {
        final class Holder: @unchecked Sendable {
            let lock = NSLock()
            private var done = false
            var task: SFSpeechRecognitionTask?
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let holder = Holder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<[SFTranscriptionSegment]?, Never>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if error != nil {
                        if holder.claim() { cont.resume(returning: nil) }
                        return
                    }
                    if let result, result.isFinal, holder.claim() {
                        cont.resume(returning: result.bestTranscription.segments)
                    }
                }
                holder.lock.lock(); holder.task = task; holder.lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if holder.claim() {
                        task.cancel()
                        cont.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            // Stop the file recognizer so it can't collide with a live mic
            // session. Its error callback then resumes the continuation.
            holder.lock.lock(); let t = holder.task; holder.lock.unlock()
            t?.cancel()
        }
    }

    private static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}
