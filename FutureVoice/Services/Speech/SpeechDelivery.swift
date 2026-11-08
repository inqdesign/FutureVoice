import AVFoundation
import Foundation

/// How a take was DELIVERED, beyond the words and the sounds: Azure's
/// prosody and fluency, the weakest sounds, where the reader paused, how
/// fast they read and how much their pitch moved.
///
/// Recorded on `speech_take` only (2026-11-07). Season 2's scoring makes 100
/// an announcer's read (founder), and the calibration that day placed
/// professionals, ordinary natives and learners on these measures from
/// public recordings. Where the app's own readers fall is the missing column,
/// and these numbers are it: no audio leaves the phone, only the figures.
/// Nothing here changes a score.
struct SpeechDelivery: Equatable {
    /// Azure prosody (en-US only) and fluency, weighted by judged words.
    var prosody: Int?
    var fluency: Int?
    /// The 5th percentile of every judged sound's score: how bad the worst
    /// few sounds were. A professional read sits near 80, a learner's at 40.
    var weakSounds: Int?
    /// Pauses of `pauseSeconds` or more between two words with no
    /// punctuation between them — a phrase broken in the middle — and how
    /// many such word boundaries were measured. nil when the words couldn't
    /// be lined up with the script (a language without spaces, or a piece
    /// whose words don't find their place in it). 0.25 s until 2026-11-07
    /// evening, 0.15 s since.
    var midPauses: Int?
    var midBoundaries: Int?
    /// Words per minute of reading, sentence-end pauses left out.
    var wordsPerMinute: Int?
    /// Words Azure flagged as monotone (en-US only).
    var monotoneWords: Int
    /// Pitch movement, semitones (`PitchTracker`).
    var pitchRange: Double?
    var pitchSD: Double?
    /// The voice's median pitch, Hz.
    var pitchMedianHz: Double? = nil
    /// Azure's sound accuracy, weighted by judged words (the take's
    /// `soundScore`).
    var soundAccuracy: Int? = nil
    /// Where the mid-phrase pauses were, as the two words around each
    /// ("this / problem"), in reading order, with their length.
    var breaks: [Break] = []
    /// Mid-phrase pauses of a second or more: the reader lost the line.
    var stalls: Int = 0
    /// The weakest sounds, worst first, each with the word it was in.
    var weakest: [Sound] = []
    /// Words heard between script words that the script doesn't have —
    /// repeats, false starts, a word slipped in — in reading order.
    var stumbles: [String] = []
    /// A word said again, or started and said again whole ("with with",
    /// "quiet quietly"), seen in what was HEARD — so it shows even when a
    /// piece was judged against the read-back instead of the script.
    var repeats: [String] = []
    /// Pauses at punctuation longer than a narrator takes there: over
    /// `commaPauseMax` at a comma, `sentencePauseMax` at a sentence end,
    /// `paragraphPauseMax` at a paragraph end.
    var longPauses: [Break] = []
    /// Words heard and timed, for rates.
    var spokenWords: Int = 0

    /// Everything that broke the flow, per 100 words heard: mid-phrase
    /// pauses, long pauses at punctuation, stumbles and repeats (fillers are
    /// the transcript's and are added by the score).
    var irregularities: Int { breaks.count + longPauses.count + stumbles.count + repeats.count }

    struct Break: Equatable, Codable, Hashable {
        var before: String
        var after: String
        var seconds: Double
    }
    struct Sound: Equatable, Codable, Hashable {
        /// IPA (en-US); empty where Azure names no phonemes.
        var phoneme: String
        var word: String
        var score: Int
    }

    /// One assessed piece and the text it was judged against.
    struct Piece {
        let reference: String
        let result: PronunciationResult
        /// Where this piece begins in the whole take: its words are timed
        /// from the piece's own start.
        var startMs = 0
    }

    /// Calibrated 2026-11-07 on 36 un-joined narrator clips and the joined
    /// set: narrators stop 0.15 s or more inside a phrase at 1–2% of word
    /// boundaries, learners at 9%; narrators never paused longer than 0.38 s
    /// at a comma; at a sentence end the longest was 0.75 s (only 5 seen, so
    /// that limit is generous, and a paragraph's more so).
    static let pauseSeconds = 0.15
    static let stallSeconds = 1.0
    static let commaPauseMax = 0.45
    static let sentencePauseMax = 1.0
    static let paragraphPauseMax = 1.6

    static func measure(_ pieces: [Piece], language: String, audioURL: URL) -> SpeechDelivery {
        var d = timing(pieces, language: language)
        if let pitch = pitch(of: audioURL) {
            d.pitchRange = (pitch.rangeSemitones * 10).rounded() / 10
            d.pitchSD = (pitch.sdSemitones * 10).rounded() / 10
            d.pitchMedianHz = pitch.medianHz.rounded()
        }
        return d
    }

    /// The part that reads only the assessments — what the tests drive.
    static func timing(_ pieces: [Piece], language: String) -> SpeechDelivery {
        func weighted(_ value: (PronunciationResult) -> Int?) -> Int? {
            var sum = 0, total = 0
            for p in pieces {
                guard let v = value(p.result) else { continue }
                let w = max(1, p.result.judgedWords.count)
                sum += v * w
                total += w
            }
            return total > 0 ? sum / total : nil
        }
        var sounds: [Int] = []
        for p in pieces {
            for word in p.result.judgedWords {
                for phoneme in word.phonemes { if let a = phoneme.accuracy { sounds.append(a) } }
            }
        }
        sounds.sort()
        let weak: Int? = sounds.isEmpty ? nil : sounds[Int(Double(sounds.count - 1) * 0.05)]

        var mid = 0, boundaries = 0, aligned = false
        var breaks: [Break] = [], stalls = 0
        var repeats: [String] = [], longPauses: [Break] = [], spoken = 0
        var weakest: [Sound] = []
        for p in pieces {
            for word in p.result.judgedWords {
                for ph in word.phonemes {
                    if let a = ph.accuracy { weakest.append(Sound(phoneme: ph.phoneme, word: word.word, score: a)) }
                }
            }
        }
        weakest.sort { $0.score < $1.score }
        var words = 0, seconds = 0.0
        var stumbles: [String] = []
        let spaced = LanguageCatalog.writesSpaces(language)
        for piece in pieces {
            let all = piece.result.words
            // A stumble: a word Azure heard that the script doesn't have
            // (a repeat, a false start, a word slipped in), BETWEEN two
            // script words. At a piece's edges an Insertion is the prompter's
            // cut landing a word early or late, not the reader.
            let firstSaid = all.firstIndex { !$0.isInsertion && !$0.isOmission && $0.durationMs > 0 }
            let lastSaid = all.lastIndex { !$0.isInsertion && !$0.isOmission && $0.durationMs > 0 }
            // A run of Insertions that comes WITH an Omission is one word
            // heard differently, not a stumble: the script's "five-minute"
            // read as "five minutes", or "I'll" heard as "are we" (both on
            // the founder's take of 2026-11-07). That is accuracy's and the
            // sounds' business. Only a run with nothing left out of the
            // script is a word added — a repeat, a false start.
            if let f = firstSaid, let l = lastSaid, f < l {
                var i = f + 1
                while i < l {
                    guard all[i].isInsertion || all[i].isOmission else { i += 1; continue }
                    var j = i
                    while j < l && (all[j].isInsertion || all[j].isOmission) { j += 1 }
                    let run = all[i..<j]
                    if !run.contains(where: \.isOmission) {
                        for w in run where !Self.fillers.contains(core(w.word)) { stumbles.append(w.word) }
                    }
                    i = j
                }
            }

            // Repeats and restarts, in what was heard (Insertions included,
            // Omissions are words nobody said). A word said twice counts
            // unless the script itself says it twice there; a restart is a
            // word of four letters or more followed by a longer word that
            // begins with it ("quiet quietly"), so "the there" never is.
            let heard = all.filter { !$0.isOmission && $0.durationMs > 0 }
            let scriptPairs = Set(zip(referenceTokens(piece.reference), referenceTokens(piece.reference).dropFirst())
                .map { "\($0.core) \($1.core)" })
            for (a, b) in zip(heard, heard.dropFirst()) {
                let ca = core(a.word), cb = core(b.word)
                guard !ca.isEmpty, !Self.fillers.contains(ca) else { continue }
                // An Insertion is the stumble rule's: counted there, or one
                // word heard differently. Only words judged as the
                // reference's own are looked at here — which is where a
                // repeat hides when a piece was judged against its
                // read-back ("with with" in the reference itself).
                if a.isInsertion || b.isInsertion { continue }
                if ca == cb, !scriptPairs.contains("\(ca) \(cb)") {
                    repeats.append(b.word)
                } else if ca.count >= 4, cb.count > ca.count, cb.hasPrefix(ca) {
                    repeats.append(a.word)
                }
            }

            // With miscue on, Azure returns the reference's words in order
            // (Omissions included) plus Insertions. The script's own tokens
            // don't always split the way Azure's words do ("—", hyphens,
            // numbers), so the two are lined up by content, not by count: a
            // boundary is judged only where its word found its script token.
            let saidAt = all.indices.filter { !all[$0].isInsertion }
            let said = saidAt.map { all[$0] }
            let ref = spaced ? referenceTokens(piece.reference) : []
            let match = align(said.map { core($0.word) }, ref.map(\.core))
            let matched = match.compactMap { $0 }.count
            let lined = spaced && !said.isEmpty && Double(matched) >= 0.6 * Double(said.count)
            let timed = said.enumerated().filter { !$0.element.isOmission && $0.element.durationMs > 0 }
            guard let first = timed.first?.element, let last = timed.last?.element else { continue }
            var sentenceGaps = 0.0
            for (a, b) in zip(timed, timed.dropFirst()) {
                let gap = Double(b.element.offsetMs - (a.element.offsetMs + a.element.durationMs)) / 1000
                guard lined, let r = match[a.offset] else { continue }
                // Something was said or left out between the two (an added
                // word, a word heard differently): the silence between them
                // is not one pause, so it isn't judged as one.
                let between = (saidAt[a.offset] + 1)..<saidAt[b.offset]
                if between.contains(where: { all[$0].isInsertion || all[$0].isOmission }) { continue }
                switch ref[r].stop {
                case .sentence, .paragraph:
                    sentenceGaps += max(0, gap)
                    let limit = ref[r].stop == .paragraph ? paragraphPauseMax : sentencePauseMax
                    if gap > limit {
                        longPauses.append(Break(before: a.element.word, after: b.element.word,
                                                seconds: (gap * 10).rounded() / 10))
                    }
                case .clause:
                    if gap > commaPauseMax {
                        longPauses.append(Break(before: a.element.word, after: b.element.word,
                                                seconds: (gap * 10).rounded() / 10))
                    }
                case .none:
                    boundaries += 1
                    if gap >= pauseSeconds {
                        mid += 1
                        breaks.append(Break(before: a.element.word, after: b.element.word,
                                            seconds: (gap * 10).rounded() / 10))
                        if gap >= stallSeconds { stalls += 1 }
                    }
                }
            }
            if lined { aligned = true }
            let span = Double(last.offsetMs + last.durationMs - first.offsetMs) / 1000
            words += timed.count
            spoken += timed.count
            seconds += max(0, span - sentenceGaps)
        }
        var monotone = 0
        for p in pieces { monotone += p.result.words.filter { $0.error == "Monotone" }.count }
        let prosody = weighted { (r: PronunciationResult) -> Int? in r.prosody }
        let fluency = weighted { (r: PronunciationResult) -> Int? in r.fluency }
        let wpm: Int? = seconds > 3 ? Int((Double(words) / seconds * 60).rounded()) : nil
        return SpeechDelivery(
            prosody: prosody, fluency: fluency, weakSounds: weak,
            midPauses: aligned ? mid : nil, midBoundaries: aligned ? boundaries : nil,
            wordsPerMinute: wpm, monotoneWords: monotone, pitchRange: nil, pitchSD: nil,
            soundAccuracy: weighted { (r: PronunciationResult) -> Int? in r.soundScore },
            breaks: breaks, stalls: stalls, weakest: Array(weakest.prefix(12)), stumbles: stumbles,
            repeats: repeats, longPauses: longPauses, spokenWords: spoken)
    }

    // MARK: - Lining Azure's words up with the script

    /// What the boundary after a script token is.
    enum Stop { case none, clause, sentence, paragraph }
    struct RefToken: Equatable {
        let core: String
        var stop: Stop
    }

    /// Spoken fillers Azure files as Insertions; the take's filler count
    /// already has them.
    static let fillers: Set<String> = ["um", "uh", "er", "erm", "ah", "uhm", "hmm", "mm", "eh"]

    /// A word as both sides can compare it: lower case, letters, digits and
    /// apostrophes only.
    static func core(_ word: String) -> String {
        let kept = word.lowercased().replacingOccurrences(of: "’", with: "'")
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
        return kept.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    /// The script cut into words with what follows each: a sentence end, a
    /// clause break (comma, colon, dash), or nothing. A hyphenated word is
    /// two words; a token that is only punctuation ("—") marks the word
    /// before it.
    static func referenceTokens(_ text: String) -> [RefToken] {
        var out: [RefToken] = []
        // A line break after a token ends a paragraph (the take session
        // joins a piece's script across paragraphs with one).
        var tokens: [(String, Bool)] = []
        var current = "", sawNewline = false
        for ch in text {
            if ch.isWhitespace {
                if ch.isNewline { sawNewline = true }
                if !current.isEmpty { tokens.append((current, false)); current = "" }
                if sawNewline, let last = tokens.indices.last { tokens[last].1 = true }
                sawNewline = false
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append((current, false)) }
        for (token, endsParagraph) in tokens {
            let tail = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]»"))
            let stop: Stop
            if let c = tail.last, ".!?。！？…".contains(c) {
                stop = .sentence
            } else if let c = tail.last, ",;:—–-、，".contains(c) {
                stop = .clause
            } else {
                stop = .none
            }
            let parts = token.lowercased().replacingOccurrences(of: "’", with: "'")
                .split { !($0.isLetter || $0.isNumber || $0 == "'") }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                .filter { !$0.isEmpty }
            if parts.isEmpty {
                if var previous = out.popLast() {
                    if previous.stop == .none { previous.stop = stop == .sentence ? .sentence : .clause }
                    if endsParagraph, previous.stop == .sentence { previous.stop = .paragraph }
                    out.append(previous)
                }
                continue
            }
            for (i, part) in parts.enumerated() {
                let last = i == parts.count - 1
                out.append(RefToken(core: part, stop: last ? (endsParagraph && stop != .none ? .paragraph : stop) : .none))
            }
        }
        return out
    }

    /// For each of `said`, the index in `ref` it lines up with (longest
    /// common subsequence of equal words), or nil.
    static func align(_ said: [String], _ ref: [String]) -> [Int?] {
        let n = said.count, m = ref.count
        guard n > 0, m > 0 else { return Array(repeating: nil, count: n) }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = !said[i].isEmpty && said[i] == ref[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out = [Int?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n && j < m {
            if !said[i].isEmpty && said[i] == ref[j] {
                out[i] = j; i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return out
    }

    nonisolated static func pitch(of url: URL) -> PitchTracker.Stats? {
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let x = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return PitchTracker.stats(x, rate: buffer.format.sampleRate)
    }
}
