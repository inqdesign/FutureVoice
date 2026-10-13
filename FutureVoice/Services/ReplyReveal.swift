import Foundation

/// The fluent self's line is SHOWN as it is HEARD (2026-10-10).
///
/// The gateway announces a line at its first written token and streams the
/// text from there — but most turns adopt a speculative reply, whose text
/// is already complete, so the whole line landed on screen at once and the
/// voice followed ~1 s later (synthesis only starts once the turn is
/// committed). Read as "it writes everything, then thinks again, then
/// talks". So the text is held until the voice is audible and then revealed
/// a WORD at a time, each one when its audio should be starting (2026-10-13,
/// founder: a sentence dropping in whole read as stiff beside other voice
/// chats; it was a sentence at a time until then). Unspaced scripts (ja,
/// zh) go a character at a time.
///
/// Word timing is an estimate: the PCM stream carries no alignment. The
/// rate is the line's own once all of its audio is in (letters ÷ seconds of
/// voice, the gaps between sentences taken out), a per-script default
/// before that; each sentence boundary costs `sentencePause`, the gap the
/// gateway's one-sentence-per-request voice leaves (~0.4 s, measured
/// 2026-09-30). Only complete sentences are ever revealed into while the
/// line is still being written — the voice speaks nothing before its
/// sentence ends either.
enum ReplyReveal {
    /// A word is shown this much before its estimated start, so the eye is
    /// never behind the ear.
    static let lead: TimeInterval = 0.15

    /// The silence between two sentences of one line.
    static let sentencePause: TimeInterval = 0.4

    /// The prefix of `text` to show `elapsed` seconds into the voice.
    /// Only complete sentences are revealed into while the line is still
    /// being written; the unterminated tail joins once `isFinal`.
    static func visible(text: String, isFinal: Bool, elapsed: TimeInterval,
                        charactersPerSecond cps: Double) -> String {
        var ends = sentenceEnds(in: text)
        if isFinal, ends.last != text.endIndex,
           !text[(ends.last ?? text.startIndex)...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ends.append(text.endIndex)
        }
        guard let limit = ends.last, cps > 0 else { return "" }
        var shownEnd = text.startIndex
        var sentence = 0
        for (start, end) in units(in: text[..<limit]) {
            while sentence < ends.count, ends[sentence] <= start { sentence += 1 }
            let startsAt = Double(weight(text[text.startIndex..<start])) / cps
                + Double(sentence) * sentencePause
            guard startsAt <= elapsed + lead else { break }
            shownEnd = end
        }
        return String(text[..<shownEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The line's own letters per second once all of its audio is in: the
    /// sentence gaps are silence, not speech.
    static func charactersPerSecond(text: String, seconds: Double) -> Double? {
        let ends = sentenceEnds(in: text)
        // The last sentence has no space after it, so it isn't in `ends`.
        let tail = text[(ends.last ?? text.startIndex)...]
        let sentences = ends.count + (weight(tail) > 0 ? 1 : 0)
        let gaps = Double(max(0, sentences - 1)) * sentencePause
        let speaking = seconds - gaps
        let w = weight(text)
        guard speaking > 0.5, w > 0 else { return nil }
        return Double(w) / speaking
    }

    /// The pieces revealed one at a time: a word with whatever punctuation
    /// and space trail it, or — in an unspaced script — one character.
    static func units(in text: Substring) -> [(String.Index, String.Index)] {
        var out: [(String.Index, String.Index)] = []
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex else { break }
            let start = i
            if isUnspaced(text[i]) {
                i = text.index(after: i)
            } else {
                while i < text.endIndex, !text[i].isWhitespace, !isUnspaced(text[i]) {
                    i = text.index(after: i)
                }
            }
            // Punctuation that closes the piece rides with it.
            while i < text.endIndex, !text[i].isWhitespace, !text[i].isLetter, !text[i].isNumber {
                i = text.index(after: i)
            }
            out.append((start, i))
        }
        return out
    }

    /// Kana and Han: no spaces between words, so each character is a piece.
    private static func isUnspaced(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value)
        }
    }

    /// End index of every COMPLETE sentence: a Latin terminator followed by
    /// whitespace, or a CJK one (which needs no space after it). Closing
    /// quotes and brackets ride with the sentence they close.
    static func sentenceEnds(in text: String) -> [String.Index] {
        let closers: Set<Character> = [")", "\"", "'", "”", "’", "」", "』"]
        var ends: [String.Index] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let cjk = "。！？".contains(c)
            guard cjk || ".!?…".contains(c) else { i = text.index(after: i); continue }
            var j = text.index(after: i)
            while j < text.endIndex, ".!?…。！？".contains(text[j]) || closers.contains(text[j]) {
                j = text.index(after: j)
            }
            if cjk || (j < text.endIndex && text[j].isWhitespace) { ends.append(j) }
            i = j
        }
        return ends
    }

    /// What takes time to say: letters and digits, not spaces or punctuation.
    static func weight<S: StringProtocol>(_ s: S) -> Int {
        s.reduce(0) { $0 + (($1.isLetter || $1.isNumber) ? 1 : 0) }
    }

    /// Letters per second before the line's own audio has said. Hangul and
    /// kana/kanji carry a syllable each; Latin letters are a fraction of one.
    /// Scaled by the learner's speech speed (0.85–1.0).
    static func defaultCharactersPerSecond(for text: String, speed: Double) -> Double {
        let syllabic = text.unicodeScalars.contains { s in
            (0xAC00...0xD7A3).contains(s.value)      // Hangul
                || (0x3040...0x30FF).contains(s.value)  // kana
                || (0x4E00...0x9FFF).contains(s.value)  // CJK ideographs
        }
        return (syllabic ? 7.0 : 14.0) * speed
    }
}
