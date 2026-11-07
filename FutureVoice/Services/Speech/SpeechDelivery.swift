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
    /// Pauses of 0.25 s or more between two words with no punctuation
    /// between them — a phrase broken in the middle — and how many such word
    /// boundaries were measured. nil when the words couldn't be lined up with
    /// the script (a language without spaces, or a piece whose words don't
    /// match the reference one for one).
    var midPauses: Int?
    var midBoundaries: Int?
    /// Words per minute of reading, sentence-end pauses left out.
    var wordsPerMinute: Int?
    /// Words Azure flagged as monotone (en-US only).
    var monotoneWords: Int
    /// Pitch movement, semitones (`PitchTracker`).
    var pitchRange: Double?
    var pitchSD: Double?
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
    }

    static let pauseSeconds = 0.25
    static let stallSeconds = 1.0

    static func measure(_ pieces: [Piece], language: String, audioURL: URL) -> SpeechDelivery {
        var d = timing(pieces, language: language)
        if let pitch = pitch(of: audioURL) {
            d.pitchRange = (pitch.rangeSemitones * 10).rounded() / 10
            d.pitchSD = (pitch.sdSemitones * 10).rounded() / 10
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
        let spaced = LanguageCatalog.writesSpaces(language)
        for piece in pieces {
            // With miscue on, Azure returns the reference's words in order
            // (Omissions included) plus Insertions: drop the Insertions and
            // the rest lines up with the reference one for one.
            let said = piece.result.words.filter { !$0.isInsertion }
            let ref = piece.reference.split(whereSeparator: \.isWhitespace).map(String.init)
            let timed = said.enumerated().filter { !$0.element.isOmission && $0.element.durationMs > 0 }
            guard let first = timed.first?.element, let last = timed.last?.element else { continue }
            var sentenceGaps = 0.0
            let lined = spaced && ref.count == said.count
            for (a, b) in zip(timed, timed.dropFirst()) {
                let gap = Double(b.element.offsetMs - (a.element.offsetMs + a.element.durationMs)) / 1000
                guard lined else { continue }
                let token = ref[a.offset]
                if token.last.map({ ".!?。！？".contains($0) }) == true {
                    sentenceGaps += max(0, gap)
                } else if token.last.map({ ",;:—–、，".contains($0) }) != true {
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
            breaks: breaks, stalls: stalls, weakest: Array(weakest.prefix(12)))
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
