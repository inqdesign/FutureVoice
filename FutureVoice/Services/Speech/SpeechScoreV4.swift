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
        .accuracy: 98, .sounds: 95, .phrasing: 95, .expression: 95, .pace: 100,
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

    /// Phrasing is a RATE: everything that broke the flow (a pause inside
    /// a phrase, a long pause at punctuation, a stumble, a repeat, a filler;
    /// a stall counts twice) per 100 words heard, so a long script isn't
    /// punished for being long. Per speaker (2026-11-08): the ten Hi-Fi
    /// narrators read at 1.2 per 100 words (90th percentile 2.4, LJSpeech
    /// 1.8); learners pooled 9.6, their 90th percentile 42. The founder's
    /// take of 2026-11-07 read 4.1.
    static let phrasingCurve: [(Double, Double)] = [(0, 100), (2.4, 95), (9.6, 50), (42, 20), (80, 0)]
    /// Accuracy is SLIPS per 100 script words (a word changed, left out or
    /// added within the reading), never above the share of the script read
    /// as written. Narrators: none in 92-96% of pieces (95th percentile
    /// 2.5); learners' 75th percentile 8, 90th 21 (2026-11-08).
    static let slipCurve: [(Double, Double)] = [(0, 100), (2.5, 90), (8, 50), (21, 20), (40, 0)]

    /// Piecewise-linear through the anchors, 0…100. Below the first anchor
    /// a rising curve falls to 0 at 0 (a raw value under every learner's is
    /// worse than their 10th percentile); a falling one stays at its top.
    static func curve(_ x: Double, _ anchors: [(Double, Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if x <= first.0 {
            let rising = last.1 >= first.1
            return rising ? max(0, first.1 * x / max(first.0, 1e-9)) : min(100, first.1)
        }
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
                      slips: Int? = nil, scriptTokens: Int? = nil,
                      delivery d: SpeechDelivery, language: String) -> SpeechParts? {
        guard applies(to: language),
              let soundAccuracy = d.soundAccuracy, let weak = d.weakSounds,
              let prosody = d.prosody, let pitch = d.pitchRange, let wpm = d.wordsPerMinute
        else { return nil }

        let sounds = 0.6 * curve(Double(soundAccuracy), soundAccuracyCurve)
            + 0.4 * curve(Double(weak), weakSoundsCurve)
        let irregular = Double(d.irregularities + d.stalls + fillers)
        let rate = 100 * irregular / Double(max(d.spokenWords, 1))
        let phrasing = d.spokenWords > 0 ? curve(rate, phrasingCurve) : 100
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
        var accuracyPart = Double(accuracy)
        if let slips, let tokens = scriptTokens, tokens > 0 {
            accuracyPart = min(accuracyPart, curve(100 * Double(slips) / Double(tokens), slipCurve))
        }
        let scores: [Part: Int] = [
            .accuracy: Int(accuracyPart.rounded(.down)),
            .sounds: Int(sounds.rounded(.down)),
            .phrasing: Int(phrasing.rounded(.down)),
            .expression: Int(expression.rounded(.down)),
            .pace: Int(pace.rounded(.down)),
        ]
        return SpeechParts(scores: scores, coverage: coverage, wpm: wpm, prosody: prosody,
                           pitchRange: pitch, soundAccuracy: soundAccuracy,
                           weakest: Array(d.weakest.filter { $0.score < 80 }.prefix(3)),
                           breaks: Array(d.breaks.prefix(3)), stalls: d.stalls, fillers: fillers,
                           missed: Array(missed.prefix(3)), stumbles: Array(d.stumbles.prefix(5)),
                           repeats: Array(d.repeats.prefix(5)), longPauses: Array(d.longPauses.prefix(3)),
                           slips: slips)
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
    /// Words heard between script words that the script doesn't have (at
    /// most 5). Optional: takes scored by build 134 have none on file.
    var stumbles: [String]? = nil
    /// A word said again or restarted ("with with", "quiet quietly").
    var repeats: [String]? = nil
    /// Pauses at punctuation longer than a narrator's (at most 3).
    var longPauses: [SpeechDelivery.Break]? = nil
    /// Words changed, left out or added within the reading.
    var slips: Int? = nil

    init(scores: [SpeechScoreV4.Part: Int], coverage: Double, wpm: Int, prosody: Int,
         pitchRange: Double, soundAccuracy: Int, weakest: [SpeechDelivery.Sound],
         breaks: [SpeechDelivery.Break], stalls: Int, fillers: Int, missed: [String],
         stumbles: [String] = [], repeats: [String] = [], longPauses: [SpeechDelivery.Break] = [],
         slips: Int? = nil) {
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
        self.stumbles = stumbles
        self.repeats = repeats
        self.longPauses = longPauses
        self.slips = slips
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
