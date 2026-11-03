import Foundation

// MARK: - The ledger

/// Every assessed take, per target language, written through ONE door by
/// every surface that measures pronunciation (shadow, say it again, the
/// weekly test's speak item, the speech take) — so pronunciation can be read
/// as a TENDENCY across takes (2026-11-03).
///
/// Why a ledger and not the takes themselves: a single take's word marks are
/// noise. Measured on the founder's own 86 s speech take: the same audio
/// scored twice gives the same numbers, but a piece boundary moved by half a
/// second changes WHICH words are marked (a cut that clips the "k" of
/// "clean" scores it 11), and Azure's en-US model wants /hw/ in "while", so
/// anyone saying /w/ is marked there. What holds across takes is the SOUND:
/// a learner whose /θ/ averages 55 over twelve words has a /θ/ problem; a
/// learner whose "some" scored 40 once has nothing. So the take screen says
/// what this take's sounds were, the Progress axis is the mean over a month,
/// and the week's coach is told the sounds that stay low — all read from
/// here.
///
/// Device-local (`Documents/lang/<code>/pronunciation.json`), never synced:
/// the same takes are on both devices through their own kinds, and a
/// rebuild from them is the next step, not a second record to merge.
struct PronunciationEntry: Codable, Identifiable, Hashable {
    /// The take's own id (`SpeechTake.id` / `ShadowAttempt.id`).
    var id: UUID
    var date: Date
    /// "shadow" · "speech" (say it again and the test save as shadow attempts).
    var surface: String
    var locale: String
    /// `PronunciationResult.soundScore` — Azure's accuracy, the sounds.
    var accuracy: Int
    /// Azure's PronScore, for the record.
    var score: Int
    var prosody: Int?
    /// Every JUDGED word (omissions and insertions left out) with its score.
    var words: [WordScore]
    /// Every NAMED phoneme occurrence (en-US only; empty elsewhere).
    var phonemes: [PhonemeScore]

    struct WordScore: Codable, Hashable {
        var w: String
        var a: Int
    }
    struct PhonemeScore: Codable, Hashable {
        var p: String
        var a: Int
    }

    /// One entry from one or more results (a speech take is several pieces).
    init?(id: UUID, date: Date, surface: String, results: [PronunciationResult]) {
        guard let first = results.first else { return nil }
        let judged = results.flatMap(\.judgedWords)
        let weight = results.map { max(1, $0.judgedWords.count) }
        let total = weight.reduce(0, +)
        self.id = id
        self.date = date
        self.surface = surface
        self.locale = first.locale
        self.accuracy = zip(results, weight).reduce(0) { $0 + $1.0.soundScore * $1.1 } / total
        self.score = zip(results, weight).reduce(0) { $0 + $1.0.score * $1.1 } / total
        let prosodies = results.compactMap(\.prosody)
        self.prosody = prosodies.isEmpty ? nil : prosodies.reduce(0, +) / prosodies.count
        self.words = judged.compactMap { w in
            w.accuracy.map { WordScore(w: w.word.lowercased(), a: $0) }
        }
        self.phonemes = results.flatMap(\.namedPhonemes).compactMap { p in
            p.accuracy.map { PhonemeScore(p: p.phoneme, a: $0) }
        }
    }
}

@MainActor
final class PronunciationLedger {
    static let shared = PronunciationLedger()

    static let keepDays = 90
    static let maxEntries = 400

    private var cache: [String: [PronunciationEntry]] = [:]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func url(for language: String) -> URL {
        LanguageScope.directory(for: language).appendingPathComponent("pronunciation.json")
    }

    func entries(language: String = LanguageScope.active) -> [PronunciationEntry] {
        if let cached = cache[language] { return cached }
        let loaded = (try? Data(contentsOf: Self.url(for: language)))
            .flatMap { try? decoder.decode([PronunciationEntry].self, from: $0) } ?? []
        cache[language] = loaded
        return loaded
    }

    func entry(id: UUID, language: String = LanguageScope.active) -> PronunciationEntry? {
        entries(language: language).first { $0.id == id }
    }

    /// Records one take. Nothing is written for a take with no result, and a
    /// take recorded twice (the coach bullets landing after the score)
    /// replaces its own row.
    @discardableResult
    func record(_ results: [PronunciationResult], id: UUID, surface: String,
                language: String = LanguageScope.active, date: Date = Date()) -> PronunciationEntry? {
        guard let entry = PronunciationEntry(id: id, date: date, surface: surface, results: results) else {
            return nil
        }
        var all = entries(language: language).filter { $0.id != id }
        all.append(entry)
        let cutoff = date.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        all = all.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        cache[language] = all
        if let data = try? encoder.encode(all) {
            try? data.write(to: Self.url(for: language), options: .atomic)
        }
        SyncEngine.noteChanged(.pronunciation)
        return entry
    }

    /// Another device's takes were merged into the file.
    func invalidate(language: String) {
        cache[language] = nil
    }

    /// Test hook.
    func reset(language: String) {
        cache[language] = nil
        try? FileManager.default.removeItem(at: Self.url(for: language))
    }
}

// MARK: - The learner's standing

/// What the ledger says about a learner's pronunciation over a window: the
/// mean, the sounds (en-US) with how they average, and the words that keep
/// coming back low (every language). Pure over entries, so it is testable.
struct PronunciationProfile {
    struct Sound: Hashable {
        let phoneme: String
        let mean: Int
        let count: Int
    }
    struct WordTrend: Hashable {
        let word: String
        let mean: Int
        /// Distinct takes the word was judged in.
        let takes: Int
    }

    let takes: Int
    let meanAccuracy: Int?
    /// Every sound heard `minSamples` or more times, worst first.
    let sounds: [Sound]
    /// Words judged in `minWordTakes`+ takes, worst first.
    let words: [WordTrend]

    /// A sound under this, on average, is one to work on — the same bar the
    /// word marks use for "shaky".
    static let weakBar = 70
    /// Fewer occurrences than this and one word decides the sound.
    static let minSamples = 4
    static let minWordTakes = 2
    static let windowDays = 30

    var weakSounds: [Sound] { sounds.filter { $0.mean < Self.weakBar } }
    var weakWords: [WordTrend] { words.filter { $0.mean < Self.weakBar } }

    @MainActor
    static func current(language: String = LanguageScope.active, now: Date = Date()) -> PronunciationProfile {
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        return build(PronunciationLedger.shared.entries(language: language).filter { $0.date >= since })
    }

    static func build(_ entries: [PronunciationEntry]) -> PronunciationProfile {
        var sounds: [String: [Int]] = [:]
        var words: [String: (sum: Int, n: Int, takes: Set<UUID>)] = [:]
        for e in entries {
            for p in e.phonemes { sounds[p.p, default: []].append(p.a) }
            for w in e.words {
                var t = words[w.w] ?? (0, 0, [])
                t.sum += w.a; t.n += 1; t.takes.insert(e.id)
                words[w.w] = t
            }
        }
        let soundRows = sounds.compactMap { (p, v) -> Sound? in
            guard v.count >= minSamples else { return nil }
            return Sound(phoneme: p, mean: v.reduce(0, +) / v.count, count: v.count)
        }.sorted { $0.mean == $1.mean ? $0.phoneme < $1.phoneme : $0.mean < $1.mean }
        let wordRows = words.compactMap { (w, t) -> WordTrend? in
            guard t.takes.count >= minWordTakes else { return nil }
            return WordTrend(word: w, mean: t.sum / t.n, takes: t.takes.count)
        }.sorted { $0.mean == $1.mean ? $0.word < $1.word : $0.mean < $1.mean }
        let mean = entries.isEmpty ? nil : entries.map(\.accuracy).reduce(0, +) / entries.count
        return PronunciationProfile(takes: entries.count, meanAccuracy: mean,
                                    sounds: soundRows, words: wordRows)
    }

    // MARK: What to say about ONE take

    /// This take's own low sounds (en-US): each phoneme's mean within the
    /// take, under `weakBar`, heard at least twice in it (once is a word),
    /// worst first. Empty when the locale names no phonemes.
    static func lowSounds(in entry: PronunciationEntry, limit: Int = 3) -> [Sound] {
        var by: [String: [Int]] = [:]
        for p in entry.phonemes { by[p.p, default: []].append(p.a) }
        return by.compactMap { (p, v) -> Sound? in
            guard v.count >= 2 else { return nil }
            let mean = v.reduce(0, +) / v.count
            return mean < weakBar ? Sound(phoneme: p, mean: mean, count: v.count) : nil
        }
        .sorted { $0.mean == $1.mean ? $0.phoneme < $1.phoneme : $0.mean < $1.mean }
        .prefix(limit).map { $0 }
    }

    /// Words low in this take that were ALSO low across the profile — the
    /// only word-level claim worth making where no sound is named. A word
    /// low once is a cut, a reference a word off, or a model quirk.
    func repeatedLowWords(in entry: PronunciationEntry, limit: Int = 3) -> [WordTrend] {
        let lowHere = Set(entry.words.filter { $0.a < Self.weakBar }.map(\.w))
        return weakWords.filter { lowHere.contains($0.word) }.prefix(limit).map { $0 }
    }

    /// One line for a take's row: sounds (en-US) or repeated words, or nil
    /// when nothing stood out.
    func noteLine(for entry: PronunciationEntry) -> String? {
        let sounds = Self.lowSounds(in: entry)
        if !sounds.isEmpty {
            return explain("Sounds to work on: \(sounds.map { "\($0.phoneme) \($0.mean)" }.joined(separator: " · "))")
        }
        guard entry.phonemes.isEmpty else { return nil }
        let words = repeatedLowWords(in: entry)
        guard !words.isEmpty else { return nil }
        return explain("Keeps coming out low: \(words.map(\.word).joined(separator: " · "))")
    }

    /// The profile for a prompt ("n/a" when thin), in English, numbers only.
    var promptLine: String? {
        guard takes >= 3, let meanAccuracy else { return nil }
        var parts = ["mean accuracy \(meanAccuracy) over \(takes) takes"]
        if !weakSounds.isEmpty {
            parts.append("weak sounds: " + weakSounds.prefix(4).map { "\($0.phoneme) \($0.mean) (×\($0.count))" }.joined(separator: ", "))
        } else if !sounds.isEmpty {
            parts.append("no sound under \(Self.weakBar)")
        }
        if !weakWords.isEmpty {
            parts.append("words low in several takes: " + weakWords.prefix(4).map { "\($0.word) \($0.mean)" }.joined(separator: ", "))
        }
        return parts.joined(separator: "; ")
    }
}
