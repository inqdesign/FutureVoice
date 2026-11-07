import Foundation

/// Season 2's speech score (scoring 4), English only for now: five parts,
/// each one skill a reader can work on, and 100 only when every part is at a
/// skilled native narrator's level (founder, 2026-11-07: "100 is an
/// announcer's read, perfect in every part").
///
/// Every anchor comes from the calibration of 2026-11-07 (227 public
/// recordings, `SpeechDelivery` measures): learners (speechocean762, with
/// expert scores), ordinary native readers (LibriSpeech) and skilled
/// narrators (LJSpeech + the ten Hi-Fi TTS narrators). Each curve runs
/// through four points — the learners' 10th percentile and median at 20 and
/// 50, the narrators' 10th percentile at 90 and their median at 100 — so a
/// part's number says where the reader stands between a typical learner and
/// a narrator. On those recordings the total put 0% of learners at 100,
/// 17% of ordinary natives and 30–78% of narrators, and it ranked the
/// learners as the experts did (Spearman 0.83).
///
/// Off by default (`isEnabled`): the challenge server only checks the
/// scoring 2/3 weightings, so a scoring 4 take never goes on a board until
/// Season 2 opens with a migration that knows it.
enum SpeechScoreV4 {
    static let version = 4
    static let defaultsKey = "speech.scoring4"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static func applies(to language: String) -> Bool { language.hasPrefix("en") }

    enum Part: String, Codable, CaseIterable {
        case accuracy, sounds, phrasing, expression, pace
    }

    /// Of the total, out of 100.
    static let weights: [Part: Double] = [
        .accuracy: 25, .sounds: 25, .phrasing: 20, .expression: 20, .pace: 10,
    ]
    /// A part's narrator bar. Every part at or above its bar is a 100.
    static let bars: [Part: Int] = [
        .accuracy: 98, .sounds: 95, .phrasing: 100, .expression: 95, .pace: 100,
    ]
    /// The professional reading range, words per minute without the
    /// sentence-end pauses (the ten narrators read 142–213; ordinary natives
    /// 141–204).
    static let paceBand = 130...220

    // Calibration anchors: (raw value, part score).
    static let soundAccuracyCurve: [(Double, Double)] = [(71, 20), (90, 50), (95.5, 90), (97.5, 100)]
    static let weakSoundsCurve: [(Double, Double)] = [(8, 20), (40, 50), (72, 90), (80, 100)]
    static let prosodyCurve: [(Double, Double)] = [(41, 20), (73, 50), (88.6, 90), (89.4, 100)]
    static let pitchCurve: [(Double, Double)] = [(3.2, 20), (5.2, 50), (6.6, 90), (8.6, 100)]

    static let breakCost = 12.0
    static let stallCost = 10.0
    static let fillerCost = 8.0

    /// Piecewise-linear through the anchors, flat beyond them, 0…100.
    static func curve(_ x: Double, _ anchors: [(Double, Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if x <= first.0 { return max(0, first.1 * x / max(first.0, 1e-9)) }
        if x >= last.0 { return min(100, last.1) }
        for (a, b) in zip(anchors, anchors.dropFirst()) where x <= b.0 {
            return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    /// nil when the take can't be scored this way: not English, or a
    /// measure is missing (the assessment failed, no prosody, too little
    /// voiced audio for a pitch). The take then keeps scoring 3.
    static func score(accuracy: Int, coverage: Double, fillers: Int, missed: [String],
                      delivery d: SpeechDelivery, language: String) -> SpeechParts? {
        guard applies(to: language),
              let soundAccuracy = d.soundAccuracy, let weak = d.weakSounds,
              let prosody = d.prosody, let pitch = d.pitchRange, let wpm = d.wordsPerMinute
        else { return nil }

        let sounds = 0.6 * curve(Double(soundAccuracy), soundAccuracyCurve)
            + 0.4 * curve(Double(weak), weakSoundsCurve)
        let phrasing = max(0, 100 - breakCost * Double(d.breaks.count)
            - stallCost * Double(d.stalls) - fillerCost * Double(fillers))
        let expression = 0.7 * curve(Double(prosody), prosodyCurve) + 0.3 * curve(pitch, pitchCurve)
        let pace: Double
        if paceBand.contains(wpm) {
            pace = 100
        } else if wpm < paceBand.lowerBound {
            let lo = Double(paceBand.lowerBound)
            pace = max(0, 100 - 3 * (lo - Double(wpm)) / lo * 100)
        } else {
            let hi = Double(paceBand.upperBound)
            pace = max(0, 100 - 2 * (Double(wpm) - hi) / hi * 100)
        }
        let scores: [Part: Int] = [
            .accuracy: accuracy,
            .sounds: Int(sounds.rounded(.down)),
            .phrasing: Int(phrasing.rounded(.down)),
            .expression: Int(expression.rounded(.down)),
            .pace: Int(pace.rounded(.down)),
        ]
        return SpeechParts(scores: scores, coverage: coverage, wpm: wpm, prosody: prosody,
                           pitchRange: pitch, soundAccuracy: soundAccuracy,
                           weakest: Array(d.weakest.filter { $0.score < 80 }.prefix(3)),
                           breaks: Array(d.breaks.prefix(3)), stalls: d.stalls, fillers: fillers,
                           missed: Array(missed.prefix(3)))
    }
}

/// A scoring 4 take's parts, stored on its metrics, with what the result
/// screen needs to say what to work on next.
struct SpeechParts: Codable, Hashable {
    var accuracy: Int
    var sounds: Int
    var phrasing: Int
    var expression: Int
    var pace: Int
    /// How far into the script the take got; everything but accuracy is
    /// scaled by it, and a take that stopped early is never a 100.
    var coverage: Double
    // The raw measures behind the parts.
    var wpm: Int
    var prosody: Int
    var pitchRange: Double
    var soundAccuracy: Int
    /// The weakest sounds under 80, worst first (at most 3).
    var weakest: [SpeechDelivery.Sound]
    /// The first mid-phrase pauses (at most 3).
    var breaks: [SpeechDelivery.Break]
    var stalls: Int
    var fillers: Int
    /// The first script words skipped or changed (at most 3).
    var missed: [String]

    init(scores: [SpeechScoreV4.Part: Int], coverage: Double, wpm: Int, prosody: Int,
         pitchRange: Double, soundAccuracy: Int, weakest: [SpeechDelivery.Sound],
         breaks: [SpeechDelivery.Break], stalls: Int, fillers: Int, missed: [String]) {
        accuracy = scores[.accuracy] ?? 0
        sounds = scores[.sounds] ?? 0
        phrasing = scores[.phrasing] ?? 0
        expression = scores[.expression] ?? 0
        pace = scores[.pace] ?? 0
        self.coverage = coverage
        self.wpm = wpm
        self.prosody = prosody
        self.pitchRange = pitchRange
        self.soundAccuracy = soundAccuracy
        self.weakest = weakest
        self.breaks = breaks
        self.stalls = stalls
        self.fillers = fillers
        self.missed = missed
    }

    func score(_ part: SpeechScoreV4.Part) -> Int {
        switch part {
        case .accuracy: return accuracy
        case .sounds: return sounds
        case .phrasing: return phrasing
        case .expression: return expression
        case .pace: return pace
        }
    }

    func clears(_ part: SpeechScoreV4.Part) -> Bool { score(part) >= (SpeechScoreV4.bars[part] ?? 100) }

    /// Parts at a narrator's level, out of five.
    var barsCleared: Int { SpeechScoreV4.Part.allCases.filter(clears).count }

    /// Every part at its bar, read to the end.
    var isPerfect: Bool { barsCleared == SpeechScoreV4.Part.allCases.count && coverage >= 0.999 }

    /// Accuracy at its weight, the rest at theirs scaled by coverage; 99 at
    /// most unless perfect.
    var total: Int {
        if isPerfect { return 100 }
        let w = SpeechScoreV4.weights
        let said = SpeechScoreV4.Part.allCases.filter { $0 != .accuracy }
            .reduce(0.0) { $0 + (w[$1] ?? 0) * Double(score($1)) }
        let raw = ((w[.accuracy] ?? 0) * Double(accuracy) + coverage * said) / 100
        return min(99, max(0, Int(raw.rounded())))
    }

    /// The part that cost the most points: what to work on next. nil on a
    /// perfect take.
    var focus: SpeechScoreV4.Part? {
        guard !isPerfect else { return nil }
        let w = SpeechScoreV4.weights
        return SpeechScoreV4.Part.allCases.max { a, b in
            let la = (w[a] ?? 0) * Double(100 - score(a)) + (clears(a) ? 0 : 0.001)
            let lb = (w[b] ?? 0) * Double(100 - score(b)) + (clears(b) ? 0 : 0.001)
            return la < lb
        }
    }
}
