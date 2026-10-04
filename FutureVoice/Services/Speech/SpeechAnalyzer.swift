import AVFoundation
import Accelerate
import Foundation

/// Every number on a Speech result, computed in code — from the transcript
/// against the script, and from the recording's own loudness envelope. No
/// model decides a score here; `SpeechCoach` only writes notes about them.
enum SpeechAnalyzer {

    /// A silence this long between two sounds counts as a pause — a breath a
    /// listener hears. Gaps between words in connected speech are shorter.
    static let pauseSeconds = 0.25
    /// A silence this long is a stall: the reader lost the line.
    static let hesitationSeconds = 1.5

    /// The voice, as the envelope sees it.
    struct Envelope {
        /// Seconds from the file's start to the first and last voiced block.
        var firstVoice: Double
        var lastVoice: Double
        /// Silences between first and last voice, in seconds.
        var silences: [Double]
        /// Voiced stretches between those silences, as (start dB, end dB):
        /// the mean level of a phrase's opening 60% and closing 25%.
        var phrases: [(head: Float, tail: Float)]
        var speakingSeconds: Double { max(0, lastVoice - firstVoice) }
    }

    // MARK: - Whole take

    static func analyze(script: String, transcript: String, language: String,
                        envelope: Envelope?) -> SpeechMetrics {
        let fillerCount = countFillers(in: transcript, script: script, language: language)
        let spoken = removingFillers(transcript, language: language)

        // Accuracy: the shadow diff, which already handles CJK by syllable,
        // digits and contractions.
        let diff = ShadowEngine.analyze(target: script, learner: spoken, language: language)
        let missed = missedRuns(diff.steps, language: language)

        // Pace.
        let band = SpeechLibrary.rateBand(language)
        let units = SpeechLibrary.units(in: spoken, language: language)
        let minutes = (envelope?.speakingSeconds ?? 0) / 60
        let rate = minutes > 0.05 ? Int((Double(units) / minutes).rounded()) : 0
        let paceScore = Self.paceScore(rate: rate, band: band)

        // Pauses. Without word timings we can't place a silence on a
        // sentence end, so the count is compared, not matched: as many
        // breaths as there are sentence breaks is the target, many more is
        // choppy, and a stall is a stall wherever it falls.
        let breaks = sentenceBreaks(in: script)
        let clauses = clauseBreaks(in: script)
        let silences = envelope?.silences ?? []
        let pauses = silences.filter { $0 >= pauseSeconds }.count
        let hesitations = silences.filter { $0 >= hesitationSeconds }.count
        let pausesAtBreaks = min(pauses, breaks)
        let choppy = max(0, pauses - (breaks + clauses) - 2)
        var pauseScore = breaks > 0 ? 100 * pausesAtBreaks / breaks : 100
        pauseScore -= 5 * choppy + 8 * hesitations
        pauseScore = clamp(pauseScore)

        // Fillers per minute of speaking.
        let perMinute = minutes > 0.05 ? Double(fillerCount) / minutes : Double(fillerCount)
        let fillerScore = clamp(100 - Int((perMinute * 12).rounded()))

        let steadiness = steadinessScore(envelope?.phrases ?? [])

        let overall = clamp(Int((
            0.40 * Double(diff.score)
            + 0.20 * Double(paceScore)
            + 0.15 * Double(pauseScore)
            + 0.10 * Double(fillerScore)
            + 0.15 * Double(steadiness)
        ).rounded()))

        return SpeechMetrics(
            accuracy: diff.score,
            rate: rate, rateLow: band.lowerBound, rateHigh: band.upperBound,
            paceScore: paceScore,
            pausesAtBreaks: pausesAtBreaks, breaks: breaks,
            hesitations: hesitations, pauseScore: pauseScore,
            fillers: fillerCount, fillerScore: fillerScore,
            steadiness: steadiness,
            missed: missed,
            overall: overall
        )
    }

    // MARK: - Pieces (internal for tests)

    /// 100 inside the band; 2 points per percent outside it.
    static func paceScore(rate: Int, band: ClosedRange<Int>) -> Int {
        guard rate > 0 else { return 0 }
        if band.contains(rate) { return 100 }
        let edge = Double(rate < band.lowerBound ? band.lowerBound : band.upperBound)
        let percentOff = abs(Double(rate) - edge) / edge * 100
        return clamp(100 - Int((percentOff * 2).rounded()))
    }

    /// Sentence ends inside the script — the last one is the end of the
    /// speech, not a break.
    static func sentenceBreaks(in script: String) -> Int {
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？"]
        var count = 0
        var previousWasEnder = false
        for ch in script {
            let isEnder = enders.contains(ch)
            if isEnder && !previousWasEnder { count += 1 }
            previousWasEnder = isEnder
        }
        return max(0, count - 1)
    }

    static func clauseBreaks(in script: String) -> Int {
        script.filter { [",", ";", ":", "、", "，", "—"].contains($0) }.count
    }

    /// Filler sounds in the transcript, minus any the script itself contains
    /// (a German script can say "hm" on purpose).
    static func countFillers(in transcript: String, script: String, language: String) -> Int {
        max(0, fillerHits(in: transcript, language: language) - fillerHits(in: script, language: language))
    }

    static func removingFillers(_ text: String, language: String) -> String {
        let fillers = SpeechLibrary.fillers(language)
        if LanguageCatalog.writesSpaces(language) {
            return text.split(whereSeparator: { $0.isWhitespace })
                .filter { !fillers.contains(normalizedToken(String($0))) }
                .joined(separator: " ")
        }
        var out = text
        for f in fillers.sorted(by: { $0.count > $1.count }) {
            out = out.replacingOccurrences(of: f, with: "")
        }
        return out
    }

    private static func fillerHits(in text: String, language: String) -> Int {
        let fillers = SpeechLibrary.fillers(language)
        if LanguageCatalog.writesSpaces(language) {
            return text.split(whereSeparator: { $0.isWhitespace })
                .filter { fillers.contains(normalizedToken(String($0))) }.count
        }
        var rest = text
        var hits = 0
        for f in fillers.sorted(by: { $0.count > $1.count }) {
            let parts = rest.components(separatedBy: f)
            hits += parts.count - 1
            rest = parts.joined(separator: " ")
        }
        return hits
    }

    private static func normalizedToken(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// Runs of script tokens the reader skipped or changed, joined back into
    /// readable pieces, in script order, at most 12.
    static func missedRuns(_ steps: [ShadowEngine.DiffStep], language: String) -> [String] {
        let joiner = LanguageCatalog.tokenStyle(language) == .word ? " " : ""
        var runs: [String] = []
        var current: [String] = []
        for step in steps where step.op != .ins {
            if step.op == .match {
                if !current.isEmpty { runs.append(current.joined(separator: joiner)); current = [] }
            } else if let t = step.target {
                current.append(t)
            }
        }
        if !current.isEmpty { runs.append(current.joined(separator: joiner)) }
        // A lone CJK syllable is noise to show; keep runs a reader can find.
        let readable = joiner.isEmpty ? runs.filter { $0.count >= 2 } : runs
        return Array(readable.prefix(12))
    }

    /// Voice that holds its level: a phrase that fades at its end is the
    /// commonest presentation fault (the listener loses the last word).
    static func steadinessScore(_ phrases: [(head: Float, tail: Float)]) -> Int {
        let usable = phrases.filter { $0.head > -80 && $0.tail > -80 }
        guard usable.count >= 2 else { return 100 }
        let drops = usable.map { $0.head - $0.tail }
        let meanDrop = drops.reduce(0, +) / Float(drops.count)
        let heads = usable.map(\.head)
        let mean = heads.reduce(0, +) / Float(heads.count)
        let spread = (heads.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(heads.count)).squareRoot()
        let score = 100 - 6 * max(0, meanDrop - 3) - 4 * max(0, spread - 4)
        return clamp(Int(score.rounded()))
    }

    static func clamp(_ v: Int) -> Int { max(0, min(100, v)) }

    // MARK: - Envelope

    /// Reads the take's loudness envelope (10 ms block RMS) off the main
    /// thread's time. Nil when the file can't be read or holds no voice.
    nonisolated static func envelope(of url: URL) -> Envelope? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let rate = buffer.format.sampleRate
        let frames = Int(buffer.frameLength)
        let block = max(1, Int(0.01 * rate))
        let count = frames / block
        guard count > 10 else { return nil }
        var levels = [Float](repeating: 0, count: count)
        for b in 0..<count {
            var r: Float = 0
            vDSP_rmsqv(channel + b * block, 1, &r, vDSP_Length(block))
            levels[b] = r
        }
        return envelope(levels: levels, blockSeconds: 0.01)
    }

    /// The pure half, over block RMS levels — what the tests drive.
    static func envelope(levels: [Float], blockSeconds: Double) -> Envelope? {
        guard let peak = levels.max(), peak > 1e-5 else { return nil }
        let gate = peak * AudioLoudness.speechGateRatio
        let voiced = levels.map { $0 > gate }
        guard let first = voiced.firstIndex(of: true), let last = voiced.lastIndex(of: true) else { return nil }

        // Walk first…last, splitting into phrases at every silence.
        let minPauseBlocks = Int(pauseSeconds / blockSeconds)
        var silences: [Double] = []
        var phrases: [(Float, Float)] = []
        var phraseStart = first
        var i = first
        while i <= last {
            if voiced[i] { i += 1; continue }
            var j = i
            while j <= last && !voiced[j] { j += 1 }
            let gap = j - i
            if gap >= minPauseBlocks {
                silences.append(Double(gap) * blockSeconds)
                phrases.append(phraseLevels(levels, phraseStart..<i))
                phraseStart = j
            }
            i = j
        }
        phrases.append(phraseLevels(levels, phraseStart..<(last + 1)))
        return Envelope(
            firstVoice: Double(first) * blockSeconds,
            lastVoice: Double(last + 1) * blockSeconds,
            silences: silences,
            phrases: phrases.map { (head: $0.0, tail: $0.1) }
        )
    }

    private static func phraseLevels(_ levels: [Float], _ range: Range<Int>) -> (Float, Float) {
        guard range.count >= 20 else { return (-100, -100) }   // under 0.2 s: a word, not a phrase
        let headEnd = range.lowerBound + Int(Double(range.count) * 0.6)
        let tailStart = range.upperBound - max(1, Int(Double(range.count) * 0.25))
        func db(_ r: Range<Int>) -> Float {
            let slice = levels[r]
            let mean = slice.map { $0 * $0 }.reduce(0, +) / Float(max(1, slice.count))
            return 10 * log10(max(mean, 1e-12))
        }
        return (db(range.lowerBound..<headEnd), db(tailStart..<range.upperBound))
    }
}
