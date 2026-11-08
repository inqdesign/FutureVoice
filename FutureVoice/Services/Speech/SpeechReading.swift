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
/// Each measure is placed by where the groups actually sit — learner median
/// 50, ordinary-native median 90, narrator median 100 — and the five parts
/// count equally: an equal split agreed with the experts (0.85) better than
/// weights fitted to them. 100 needs every part at a narrator's level. On
/// the validation set: narrators median 97 (average 96), ordinary natives
/// median 96 (average 94), learners median 73 (average 63). Those natives
/// are volunteer audiobook readers, and on clips of 24-38 words they read as
/// well as the narrators, so the two are not told apart by this score.
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
    static let version = 6

    /// The calibration's group medians (learner, native, narrator).
    static let speedCurve: [(Double, Double)] = [(0.1131, 0), (0.6517, 50), (0.921, 90), (0.9702, 100)]
    static let rhythmCurve: [(Double, Double)] = [(0.6001, 0), (0.8227, 50), (0.934, 90), (0.9352, 100)]
    /// Mid-sentence stops per 100 words. None at every group's median, so
    /// the 75th percentile places it, the first where any group has some:
    /// natives' 1.6 is 90, learners' 17.4 is 50, learners' 90th 36.8 is 20.
    static let pausesCurve: [(Double, Double)] = [(0, 100), (1.5957, 90), (17.3913, 50), (36.8421, 20), (40, 0)]
    /// Slips are none at every group's median, so their curve is set by the
    /// tails: narrators' 95th percentile 2.5 per 100 words, learners' 75th 8,
    /// 90th 21.
    static let slipsCurve: [(Double, Double)] = [(0, 100), (2.5, 90), (8, 50), (21, 20), (40, 0)]
    /// Pronunciation is judged only where it is clearly off: Azure can't rank
    /// the top, so from the narrators' 10th percentile (95.5) up it is full.
    static let soundCurve: [(Double, Double)] = [(71, 20), (90, 50), (95.5, 100)]

    static let pauseSeconds = 0.15
    /// A take's median pitch above this is read against the female reference.
    static let femaleAboveHz = 165.0

    /// The averages the result page quotes, from the validation set.
    static let nativeAverage = 94
    static let narratorAverage = 96
    static let learnerAverage = 63

    static func applies(to language: String) -> Bool { language.hasPrefix("en") }

    static func curve(_ x: Double, _ pts: [(Double, Double)]) -> Double {
        guard let first = pts.first, let last = pts.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for (a, b) in zip(pts, pts.dropFirst()) where x <= b.0 {
            return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
        }
        return last.1
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
                      coverage: Double, gender: String) -> SpeechReadingScore? {
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
            weakest: parts.pronunciation < 100 ? Array(weakest.filter { $0.score < 80 }.prefix(3)) : [])
    }

    /// The five parts from the five measures — what the calibration fixture
    /// drives (`SpeechReadingTests`).
    static func parts(speed: Double, rhythm: Double, pausesPer100: Double,
                      slipsPer100: Double, soundAccuracy: Double?) -> SpeechReadingScore.Parts {
        SpeechReadingScore.Parts(
            speed: Int(curve(speed, speedCurve).rounded()),
            rhythm: Int(curve(rhythm, rhythmCurve).rounded()),
            pauses: Int(curve(pausesPer100, pausesCurve).rounded()),
            accuracy: Int(curve(slipsPer100, slipsCurve).rounded()),
            pronunciation: soundAccuracy.map { Int(curve($0, soundCurve).rounded()) } ?? 100)
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

    var isPerfect: Bool { parts.all.allSatisfy { $0.1 >= Self.bar } && coverage >= 0.999 }

    var total: Int {
        if isPerfect { return 100 }
        let mean = Double(parts.all.reduce(0) { $0 + $1.1 }) / 5
        // Stopping early scales everything but accuracy (which already
        // counts the words left out) — as the older scoring did.
        let scaled = mean * (0.2 + 0.8 * min(1, coverage))
        return min(99, max(0, Int(scaled.rounded())))
    }

    /// The part that cost the most, to work on next; nil on a perfect take.
    var focus: Part? {
        guard !isPerfect else { return nil }
        return parts.all.min { $0.1 < $1.1 }?.0
    }

}

// MARK: - The reference reading

/// The native reference reading of a script, both genders, word-timed
/// (`speech-reference` edge function). Kept on the phone per script text.
struct SpeechReference: Codable {
    var version: Int
    var male: [Word]
    var female: [Word]
    struct Word: Codable { var w: String; var s: Int; var e: Int }

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
