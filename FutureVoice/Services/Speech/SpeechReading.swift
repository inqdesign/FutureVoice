import CryptoKit
import Foundation

/// Season 2's speech score: a take compared word for word with a NATIVE
/// reading of the same script, in the reader's gender (2026-11-08).
///
/// Why this and not Azure's own numbers: on 137 human readings (narrators,
/// ordinary native readers, speechocean762 learners with expert ratings),
/// Azure's sound and prosody scores put a fluent learner next to a native,
/// and fixed thresholds couldn't tell a narrator's held word from a
/// learner's hesitation. Against a native reading of the same text, these
/// separated the three groups and agreed with the experts (Spearman ~0.8
/// each): speaking SPEED, the word-length pattern (RHYTHM), and PAUSES the
/// native reading doesn't have. Intonation and stress compared the same way
/// did NOT separate humans (narrators matched the reference no better than
/// learners), so they are not in the score.
///
/// Every part is the measurement itself, on a 0-100 scale, and the total is
/// their plain average (2026-11-09, founder: "96 is 96, and 100 is 100 in
/// everything"). Version 6 stretched each measure through a curve so the
/// groups sat at 50/90/100: Azure's 86 read 44, and a rhythm could read 0. The
/// curves added nothing (agreement with the experts 0.850 with them, 0.851
/// without) and multiplied every small wobble, so version 7 has none. On the
/// validation set: narrators average 97, ordinary natives 96, learners 81.
///
/// Version 6 (2026-11-08): a stop after punctuation is not a fault. Version 5
/// counted every pause the reference lacks, and the first real take showed
/// 11 of its 12 "extra" pauses were after a period or comma: the reference
/// pauses at only 14 of that script's 22 sentence ends and none of its 15
/// commas. The calibration had hidden it (narrators' clips hold 0.4 sentence
/// ends per 100 words, the natives' text had no punctuation; that script has
/// 12). With the natives' punctuation restored and their references remade
/// from it, pauses after punctuation say nothing about the reader (Spearman
/// with the experts 0.11) and mid-sentence ones say more than the old count
/// (0.83 against 0.77). Long pauses at a sentence end are NOT scored: the
/// learners' clips join separate recordings (gaps of 1.3-1.5 s every time),
/// and natives and narrators hold only 21 sentence ends between them.
enum SpeechReading {
    static let version = 8

    static let pauseSeconds = 0.15
    /// A take's median pitch above this is read against the female reference.
    static let femaleAboveHz = 165.0

    /// The averages the result page quotes, from the validation set.
    static let nativeAverage = 96
    static let narratorAverage = 97
    static let learnerAverage = 81

    static func applies(to language: String) -> Bool { language.hasPrefix("en") }

    private static func seasonKey(_ language: String) -> String { "speech.readingSeason.\(language.prefix(2))" }

    /// Whether a take in this language is scored this way: the language's
    /// Season 2 is open (the server says, `speech_season_status`), or the
    /// developer switch is on.
    static func isActive(for language: String) -> Bool {
        applies(to: language)
            && (SpeechScoreV4.isEnabled || UserDefaults.standard.bool(forKey: seasonKey(language)))
    }

    static func setSeasonOpen(_ open: Bool, language: String) {
        UserDefaults.standard.set(open, forKey: seasonKey(language))
    }

    // MARK: - Lining words up with the script

    /// A word's duration and the silence after it, in seconds; the silence is
    /// nil where the next word wasn't timed in the same stretch of audio.
    struct Timed {
        var duration: Double
        var gapAfter: Double?
    }

    /// Script token index → its timing, from words in reading order. `breaks`
    /// marks where one stretch of audio ends (a take's piece), so no gap is
    /// measured across it.
    static func timeline(words: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)],
                         script: [String]) -> [Int: Timed] {
        let match = SpeechDelivery.align(words.map { SpeechDelivery.core($0.word) }, script)
        var out: [Int: Timed] = [:]
        for (i, w) in words.enumerated() {
            guard let t = match[i] else { continue }
            var gap: Double? = nil
            if !w.breakAfter, i + 1 < words.count, match[i + 1] == t + 1 {
                gap = Double(words[i + 1].startMs - w.endMs) / 1000
            }
            out[t] = Timed(duration: max(0.02, Double(w.endMs - w.startMs) / 1000), gapAfter: gap)
        }
        return out
    }

    // MARK: - Scoring

    static func score(take: [Int: Timed], reference: [Int: Timed], script: [String],
                      stops: [SpeechDelivery.Stop], slips: Int?, scriptTokens: Int?, missed: [String],
                      soundAccuracy: Int?, weakest: [SpeechDelivery.Sound],
                      coverage: Double, gender: String, weakSounds: Int? = nil) -> SpeechReadingScore? {
        let both = take.keys.filter { reference[$0] != nil }.sorted()
        guard both.count >= 20 else { return nil }
        let refSum = both.reduce(0.0) { $0 + reference[$1]!.duration }
        let takeSum = both.reduce(0.0) { $0 + take[$1]!.duration }
        let speed = refSum / takeSum
        let rhythm = pearson(both.map { log(reference[$0]!.duration) }, both.map { log(take[$0]!.duration) }) ?? 0

        // Stops inside a sentence that the native reading doesn't make. A
        // stop after punctuation is the script asking for one.
        var extra: [SpeechReadingScore.Pause] = []
        for i in both where i < stops.count && stops[i] == .none {
            guard let gap = take[i]!.gapAfter, gap >= pauseSeconds else { continue }
            if let r = reference[i]?.gapAfter, r >= pauseSeconds { continue }
            extra.append(.init(after: script[i], seconds: (gap * 10).rounded() / 10, index: i))
        }
        let pausesPer100 = 100 * Double(extra.count) / Double(both.count)

        // Words held far longer than the native reading holds them, once the
        // reader's own pace is taken out.
        let ratios = both.map { log(take[$0]!.duration / reference[$0]!.duration) }
        let tempo = ratios.sorted()[ratios.count / 2]
        let held = zip(both, ratios)
            .map { (i, r) in
                SpeechReadingScore.Held(word: script[i], times: (exp(r - tempo) * 10).rounded() / 10,
                                        seconds: (take[i]!.duration * 10).rounded() / 10,
                                        nativeSeconds: (reference[i]!.duration * 10).rounded() / 10,
                                        index: i)
            }
            // On screen a held word reads "0.1s (native 0s)" if a tenth of a
            // second is enough to name it. 0.2 s is a choice about what is
            // worth showing, not a measurement; it doesn't touch the score.
            .filter { (h: SpeechReadingScore.Held) -> Bool in
                let over: Double = (h.seconds ?? 0) - (h.nativeSeconds ?? 0)
                return h.times >= 2 && over >= 0.15
            }
            .sorted { $0.times > $1.times }

        let slipsPer100 = (slips != nil && (scriptTokens ?? 0) > 0)
            ? 100 * Double(slips!) / Double(scriptTokens!) : 0

        let parts = Self.parts(speed: speed, rhythm: rhythm, pausesPer100: pausesPer100,
                               slipsPer100: slipsPer100, soundAccuracy: soundAccuracy.map(Double.init))
        return SpeechReadingScore(
            version: version, gender: gender, parts: parts, coverage: coverage,
            speed: (speed * 100).rounded() / 100, rhythm: (rhythm * 100).rounded() / 100,
            pausesPer100: (pausesPer100 * 10).rounded() / 10, slipsPer100: (slipsPer100 * 10).rounded() / 10,
            soundAccuracy: soundAccuracy, slips: slips ?? 0,
            // All of them: the script on the result page marks every one.
            extraPauses: extra.sorted { $0.seconds > $1.seconds },
            held: held, missed: Array(missed.prefix(5)),
            weakest: parts.pronunciation < 100 ? Array(weakest.filter { $0.score < 80 }.prefix(3)) : [],
            weakSounds: weakSounds, scriptWords: scriptTokens)
    }

    /// The five parts from the five measures — what the calibration fixture
    /// drives (`SpeechReadingTests`).
    static func parts(speed: Double, rhythm: Double, pausesPer100: Double,
                      slipsPer100: Double, soundAccuracy: Double?) -> SpeechReadingScore.Parts {
        SpeechReadingScore.Parts(
            // The share of the native reading's pace, too slow or too fast.
            speed: speed > 0 ? percent(100 * min(speed, 1 / speed)) : 0,
            rhythm: percent(100 * rhythm),
            pauses: percent(100 - pausesPer100),
            accuracy: percent(100 - slipsPer100),
            pronunciation: soundAccuracy.map(percent) ?? 100)
    }

    private static func percent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    /// A sound Azure scored under the price list's bar, where it was said.
    struct WeakSound: Hashable {
        var phoneme: String
        var score: Int
    }

    /// Every weak sound, laid on the script token it was said in
    /// (2026-11-13, founder: 35 sounds cost points and none showed on the
    /// script). Pieces overlap by two words at their starts, so a word
    /// assessed twice counts ONCE, its first reading: the count the price
    /// list charges and the marks on the script are the same set.
    static func weakSounds(pieces: [PronunciationResult], script: String,
                           fluent: [SpeechReference.Word]? = nil) -> [Int: [WeakSound]] {
        let bar = SpeechReadingScore.Price.weakSoundBelow
        let spared = fluentLowSounds(fluent, script: script)
        var out: [Int: [WeakSound]] = [:]
        for (t, word) in judgedWords(pieces: pieces, script: script) {
            let weak = word.phonemes.compactMap { p -> WeakSound? in
                guard let a = p.accuracy, a < bar, spared[t]?.contains(p.phoneme) != true else { return nil }
                return WeakSound(phoneme: p.phoneme, score: a)
            }
            if !weak.isEmpty { out[t] = weak }
        }
        return out
    }

    /// The fluent reading's sounds that the same assessment scores under
    /// this, by script token (2026-11-13, founder: the reading says "nyu" in
    /// newspapers, and the dictionary wants "noo"; it scored the reading 46
    /// there). A learner who says such a sound like the reading is never
    /// charged for it. 60 is a choice, not a measurement: the learner's bar
    /// is 40, and a fluent reading this far under the dictionary is saying it
    /// another way. About 1% of a script's sounds (measured on three).
    static let fluentSoundBar = 60

    static func fluentLowSounds(_ fluent: [SpeechReference.Word]?, script: String) -> [Int: Set<String>] {
        guard let fluent, fluent.contains(where: { $0.ph != nil }) else { return [:] }
        let tokens = SpeechDelivery.referenceTokens(script).map(\.core)
        let match = SpeechDelivery.align(fluent.map { SpeechDelivery.core($0.w) }, tokens)
        var out: [Int: Set<String>] = [:]
        for (i, word) in fluent.enumerated() {
            guard let t = match[i], let ph = word.ph else { continue }
            let low = Set(ph.filter { $0.a < fluentSoundBar }.map(\.p))
            if !low.isEmpty { out[t, default: []].formUnion(low) }
        }
        return out
    }

    /// Each script token's assessed word, its FIRST reading where pieces
    /// overlap: what `weakSounds` counts from, and what the sounds sheet
    /// shows a tapped word with.
    static func judgedWords(pieces: [PronunciationResult], script: String) -> [Int: PronunciationResult.Word] {
        let tokens = SpeechDelivery.referenceTokens(script).map(\.core)
        let words = pieces.flatMap { $0.words.filter(\.isJudged) }
        let match = SpeechDelivery.align(words.map { SpeechDelivery.core($0.word) }, tokens)
        var out: [Int: PronunciationResult.Word] = [:]
        for (i, word) in words.enumerated() {
            guard let t = match[i], out[t] == nil else { continue }
            out[t] = word
        }
        return out
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 4 else { return nil }
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in x.indices {
            num += (x[i] - mx) * (y[i] - my)
            dx += (x[i] - mx) * (x[i] - mx)
            dy += (y[i] - my) * (y[i] - my)
        }
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx * dy).squareRoot()
    }
}

/// A Season 2 take's score, stored on its metrics.
struct SpeechReadingScore: Codable, Hashable {
    var version: Int
    /// Which reference it was read against ("male" / "female").
    var gender: String
    var parts: Parts
    var coverage: Double
    // What the parts were made from.
    var speed: Double            // the native reading's time over yours: 1 = same pace
    var rhythm: Double           // word-length pattern vs the native reading, -1…1
    var pausesPer100: Double     // pauses the native reading doesn't have, per 100 words
    var slipsPer100: Double      // words changed, left out or added, per 100 script words
    var soundAccuracy: Int?
    var slips: Int
    var extraPauses: [Pause]
    var held: [Held]
    var missed: [String]
    var weakest: [SpeechDelivery.Sound]
    /// Sounds Azure scored under `Price.weakSoundBelow` (scoring 8). nil on
    /// earlier takes, or when nothing was assessed.
    var weakSounds: Int? = nil
    /// The script's words, for the words left unread (scoring 8).
    var scriptWords: Int? = nil
    /// "listen": measured against the one listening reading (2026-11-13).
    /// nil: the male/female pair, which a challenge take is re-judged off
    /// when its result is opened (`SpeechReadingRejudge`).
    var reference: String? = nil

    struct Parts: Codable, Hashable {
        var speed: Int
        var rhythm: Int
        var pauses: Int
        var accuracy: Int
        var pronunciation: Int
        var all: [(Part, Int)] {
            [(.speed, speed), (.rhythm, rhythm), (.pauses, pauses), (.accuracy, accuracy), (.pronunciation, pronunciation)]
        }
    }
    enum Part: String, CaseIterable { case speed, rhythm, pauses, accuracy, pronunciation }
    /// `index` is the script token it follows (nil on takes scored before
    /// the script showed them, 2026-11-08).
    struct Pause: Codable, Hashable { var after: String; var seconds: Double; var index: Int? = nil }
    /// A word held far longer than the native reading holds it. `times` is
    /// after the reader's own pace is taken out (what picks the word); the
    /// seconds are what the page shows (founder: "4.6x means nothing to me").
    struct Held: Codable, Hashable {
        var word: String
        var times: Double
        var seconds: Double? = nil
        var nativeSeconds: Double? = nil
        var index: Int? = nil
    }

    /// A narrator's level, part by part.
    static let bar = 95

    // MARK: The price list (scoring 8, 2026-11-13)
    //
    // Founder: "start at 100, and every mistake counts". A speech is a
    // competition read in front of people, so nothing is averaged away and
    // nothing is forgiven for a poor microphone. The RELATIVE prices come
    // from 138 human readings (narrators, ordinary natives, rated learners;
    // a stop and a changed word hurt about equally, rhythm and pace matter,
    // a sound weighs about a third of a word); the overall level is the
    // founder's, chosen on his own takes. `submit_speech_reading_take_v8`
    // (and the speech app's) recomputes the same total from the same counts:
    // change a price here and there together.
    enum Price {
        static let stop = 1.0             // a stop inside a sentence the native reading doesn't make
        static let word = 1.0             // a word changed, missed or added, or left unread at the end
        // A sound Azure scores under `weakSoundBelow`: 0.4, the calibration's
        // own ratio to a word (0.37; it was 0.5 for one take, founder moved it
        // to the data the same day).
        static let sound = 0.4
        static let weakSoundBelow = 40
        static let rhythmPerPoint = 0.5   // per 0.01 of rhythm below `rhythmBar`
        static let rhythmBar = 90         // r × 100: natives sit around 93
        static let speedPerPoint = 1.0    // per point of pace below `speedBar`
        static let speedBar = 85          // % of the native reading's pace: natives median 91
    }

    struct Deduction: Hashable {
        let part: Part
        /// How many (stops, words, sounds) or how far below the bar
        /// (rhythm, pace).
        let count: Int
        let points: Double
    }

    /// The rhythm and pace as the price list reads them: whole points.
    var rhythmPoint: Int { Int((rhythm * 100).rounded()) }
    var speedPoint: Int { speed > 0 ? Int((100 * min(speed, 1 / speed)).rounded()) : 0 }
    /// Words the reading never reached (it stopped early).
    var unreadWords: Int {
        guard let w = scriptWords else { return 0 }
        return max(0, Int(((1 - min(1, coverage)) * Double(w)).rounded()))
    }

    /// Every line of the receipt, in the order the page lists them: from the
    /// whole reading down to a single sound (2026-11-13, founder: speed and
    /// rhythm first). Empty before scoring 8.
    var deductions: [Deduction] {
        guard version >= 8 else { return [] }
        let words = slips + unreadWords
        let sounds = weakSounds ?? 0
        let r = max(0, Price.rhythmBar - rhythmPoint)
        let s = max(0, Price.speedBar - speedPoint)
        return [
            Deduction(part: .speed, count: s, points: Double(s) * Price.speedPerPoint),
            Deduction(part: .rhythm, count: r, points: Double(r) * Price.rhythmPerPoint),
            Deduction(part: .pauses, count: extraPauses.count, points: Double(extraPauses.count) * Price.stop),
            Deduction(part: .accuracy, count: words, points: Double(words) * Price.word),
            Deduction(part: .pronunciation, count: sounds, points: Double(sounds) * Price.sound),
        ]
    }

    var lost: Double { deductions.reduce(0) { $0 + $1.points } }

    /// Each area holds 20 of the 100 points (2026-11-13, founder: "each area
    /// scored, so what's weak shows at a glance"). An area's score is what
    /// is left of its 20, out of 100; it stops at 0, so the total is always
    /// the five areas' average, and mistakes past an area's 20 points no
    /// longer count. `submit_speech_reading_take_v8` adds the same shares.
    static let areaShare = 20.0

    func areaLeft(_ d: Deduction) -> Double { max(0, Self.areaShare - d.points) }

    /// An area's score out of 100.
    func areaScore(_ d: Deduction) -> Int {
        Int((areaLeft(d) * 100 / Self.areaShare).rounded())
    }

    var isPerfect: Bool {
        if version >= 8 { return lost == 0 }
        return parts.all.allSatisfy { $0.1 == 100 } && coverage >= 0.999
    }

    var total: Int {
        if isPerfect { return 100 }
        if version >= 8 {
            let left = deductions.reduce(0) { $0 + areaLeft($1) }
            return min(99, max(0, Int(left.rounded())))
        }
        let mean = Double(parts.all.reduce(0) { $0 + $1.1 }) / 5
        // Stopping early scales everything but accuracy (which already
        // counts the words left out) — as the older scoring did.
        let scaled = mean * (0.2 + 0.8 * min(1, coverage))
        return min(99, max(0, Int(scaled.rounded())))
    }

    /// The part that cost the most, to work on next; nil on a perfect take.
    var focus: Part? {
        guard !isPerfect else { return nil }
        if version >= 8 { return deductions.min { areaLeft($0) < areaLeft($1) }?.part }
        return parts.all.min { $0.1 < $1.1 }?.0
    }

    var level: SpeechReadingLevel { SpeechReadingLevel(total: total) }
}

/// The nickname a score earns: a comparison for fun, not a grade, narrow
/// enough that a few more points reach the next one (founder, 2026-11-09).
/// Three edges rest on the validation set (learners average 63, natives 94,
/// narrators 96); the rest are chosen by feel. Highest first.
enum SpeechReadingLevel: CaseIterable {
    case newsAnchor, audiobook, bornAndRaised, passesAsLocal, officeAce, presenter
    case thirdYearAbroad, firstYearAbroad, languageSchool, immigration, restaurant, gestures, warmingUp

    /// The lowest score that earns this one: placed so a reading keeps the
    /// nickname it earned before the curves went (scoring 7, 2026-11-09).
    var floor: Int {
        switch self {
        case .newsAnchor: return 100
        case .audiobook: return 97
        case .bornAndRaised: return 95
        case .passesAsLocal: return 94
        case .officeAce: return 92
        case .presenter: return 90
        case .thirdYearAbroad: return 89
        case .firstYearAbroad: return 86
        case .languageSchool: return 85
        case .immigration: return 83
        case .restaurant: return 80
        case .gestures: return 72
        case .warmingUp: return 0
        }
    }

    init(total: Int) {
        self = Self.allCases.first { total >= $0.floor } ?? .warmingUp
    }

    /// The next one up; nil at the top.
    var next: SpeechReadingLevel? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index > 0 else { return nil }
        return all[index - 1]
    }

    var range: ClosedRange<Int> {
        floor...((next?.floor ?? 101) - 1)
    }
}

// MARK: - The reference reading

/// Puts back the Season 2 result of a take an older build rewrote without it
/// (see `SyncSchema.stamp`). Everything it was computed from survives on the
/// take: the assessments carry every word's timing, and the reference is kept
/// per script. Checked on the founder's take of 2026-11-09: speed 76, rhythm
/// 75, pauses 97, the numbers its board entry was made with. The board is
/// not touched.
enum SpeechReadingRepair {
    static func needsRepair(_ take: SpeechTake) -> Bool {
        take.metrics.reading == nil && (take.metrics.scoring ?? 0) >= 5
            && !(take.assessments ?? []).isEmpty
    }

    @MainActor
    static func restore(_ take: SpeechTake, script: SpeechScript) async {
        guard needsRepair(take), SpeechReading.applies(to: script.language),
              let reference = await SpeechReferenceService.fetch(text: script.body, language: script.language)
        else { return }
        let pieces = (take.assessments ?? []).map { SpeechDelivery.Piece(reference: "", result: $0) }
        let language = script.language, body = script.body, transcript = take.transcript
        let audio = SpeechStore.mediaURL(take.audioFilename)
        var metrics = take.metrics
        let pronunciation = metrics.pronunciation
        let delivered = await Task.detached { SpeechDelivery.measure(pieces, language: language, audioURL: audio) }.value
        let scored = await Task.detached {
            SpeechAnalyzer.analyze(script: body, transcript: transcript, language: language,
                                   envelope: nil, pronunciation: pronunciation)
        }.value
        metrics.slips = scored.slips
        metrics.scriptTokens = scored.scriptTokens
        guard let reading = SpeechTakeSession.reading(pieces: pieces, reference: reference, script: body,
                                                      metrics: metrics, delivery: delivered),
              var current = SpeechStore.shared.takes.first(where: { $0.id == take.id }),
              current.metrics.reading == nil else { return }
        metrics.reading = reading
        metrics.overall = reading.total
        current.metrics = metrics
        SpeechStore.shared.save(current)
    }
}

/// Re-judges a challenge take scored against the old male/female pair
/// against the one listening reading (2026-11-13, founder: "re-judge the
/// earlier attempts if we can"). Everything it needs is on the take: the
/// assessed pieces with their word timings, the transcript, the recording.
enum SpeechReadingRejudge {
    static func needs(_ take: SpeechTake) -> Bool {
        guard let r = take.metrics.reading else { return false }
        return r.version >= 8 && r.reference == nil && !(take.assessments ?? []).isEmpty
    }

    /// The re-judged take, saved; nil when it didn't need it or couldn't be.
    @MainActor
    static func run(_ take: SpeechTake, script: SpeechScript) async -> SpeechTake? {
        guard needs(take), SpeechListenService.available(for: script),
              let fluent = await SpeechListenService.reading(script) else { return nil }
        let starts = take.assessmentStartsMs
        let pieces = (take.assessments ?? []).enumerated().map { i, result in
            SpeechDelivery.Piece(reference: "", result: result,
                                 startMs: starts.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? 0)
        }
        let language = script.language, body = script.body, transcript = take.transcript
        let audio = SpeechStore.mediaURL(take.audioFilename)
        var metrics = take.metrics
        let pronunciation = metrics.pronunciation
        let delivered = await Task.detached { SpeechDelivery.measure(pieces, language: language, audioURL: audio) }.value
        let scored = await Task.detached {
            SpeechAnalyzer.analyze(script: body, transcript: transcript, language: language,
                                   envelope: nil, pronunciation: pronunciation)
        }.value
        metrics.slips = scored.slips
        metrics.scriptTokens = scored.scriptTokens
        let reference = SpeechReference(version: 2, male: fluent.words, female: fluent.words)
        guard var reading = SpeechTakeSession.reading(pieces: pieces, reference: reference, script: body,
                                                      metrics: metrics, delivery: delivered, fluent: fluent.words),
              var current = SpeechStore.shared.takes.first(where: { $0.id == take.id }) else { return nil }
        reading.gender = fluent.gender
        reading.reference = "listen"
        metrics.reading = reading
        metrics.overall = reading.total
        current.metrics = metrics
        SpeechStore.shared.save(current)
        Analytics.capture("speech_take_rejudged", ["overall": reading.total])
        return current
    }
}

extension SpeechTake {
    /// A price-list take shows the total its price list gives TODAY: the
    /// stored `overall` was written with the prices of the day it was read
    /// (a sound cost 0.5 for one take on 2026-11-13). Read-time only.
    var withCurrentPrices: SpeechTake {
        guard let r = metrics.reading, r.version >= 8, metrics.overall != r.total else { return self }
        var t = self
        t.metrics.overall = r.total
        return t
    }

    /// Whether the video is the camera alone, with the script drawn on top
    /// when wanted. `prompter` says so; a take scored 7 or later always was,
    /// even if an older build has since dropped that record.
    var videoIsCameraOnly: Bool { prompter != nil || (metrics.scoring ?? 0) >= 7 }
}

/// The native reference reading of a script, both genders, word-timed
/// (`speech-reference` edge function). Kept on the phone per script text.
struct SpeechReference: Codable {
    var version: Int
    var male: [Word]
    var female: [Word]
    struct Word: Codable {
        var w: String; var s: Int; var e: Int
        /// The fluent reading's own sounds with their scores (the listening
        /// reading only, 2026-11-13). nil on scoring references.
        var ph: [Sound]? = nil
        struct Sound: Codable { var p: String; var a: Int }
    }

    func words(for gender: String) -> [Word] { gender == "female" ? female : male }
}

enum SpeechReferenceService {
    private static func cacheURL(text: String, language: String) -> URL {
        let digest = SHA256.hash(data: Data("\(language)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = LanguageScope.directory(for: language).appendingPathComponent("speech_references", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(digest.prefix(32)).json")
    }

    /// From the phone, else the server (which makes it once per script).
    static func fetch(text: String, language: String) async -> SpeechReference? {
        let url = cacheURL(text: text, language: language)
        if let data = try? Data(contentsOf: url), let ref = try? JSONDecoder().decode(SpeechReference.self, from: data) {
            return ref
        }
        struct Body: Encodable { let text: String; let language: String }
        guard let base = Secrets.string(for: .supabaseURL),
              let endpoint = URL(string: base)?.appendingPathComponent("/functions/v1/speech-reference"),
              let headers = try? await SupabaseProvider.authorizedHeaders(),
              let body = try? JSONEncoder().encode(Body(text: text, language: String(language.prefix(2)))) else { return nil }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, response) = try? await URLSession.edgeFunctionsBackground.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let ref = try? JSONDecoder().decode(SpeechReference.self, from: data),
              !ref.male.isEmpty, !ref.female.isEmpty else { return nil }
        try? data.write(to: url, options: .atomic)
        return ref
    }
}
