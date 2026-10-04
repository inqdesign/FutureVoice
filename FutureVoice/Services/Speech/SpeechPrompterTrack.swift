import Foundation

/// The script as the prompter draws it, and where the reader is in it.
///
/// The prompter FOLLOWS THE VOICE: the live recognizer's text is matched
/// against the script and the cursor moves to the last word both agree on.
/// Matching runs on keys (case, punctuation stripped) — words in a spaced
/// language, syllables/characters in Korean and Japanese, because the
/// recognizer's spacing there is its own. It only moves FORWARD, a little
/// back at most, and never jumps further than a window ahead: a recognizer's
/// guess must not throw the reader three paragraphs down.
struct SpeechPrompterTrack {
    struct Word: Identifiable, Hashable {
        let id: Int
        let text: String
        let paragraph: Int
    }

    let words: [Word]
    let paragraphs: [[Word]]
    /// Key stream over the script, and which display word each key sits in.
    private let keys: [String]
    private let keyWord: [Int]
    private let perChar: Bool

    init(script: String, language: String) {
        perChar = LanguageCatalog.tokenStyle(language) == .syllable
        var words: [Word] = []
        var paragraphs: [[Word]] = []
        let blocks = script.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for (p, block) in blocks.enumerated() {
            var line: [Word] = []
            for piece in Self.displayWords(block, language: language) {
                let w = Word(id: words.count, text: piece, paragraph: p)
                words.append(w)
                line.append(w)
            }
            paragraphs.append(line)
        }
        var keys: [String] = []
        var keyWord: [Int] = []
        for w in words {
            for k in Self.keys(of: w.text, perChar: perChar) {
                keys.append(k)
                keyWord.append(w.id)
            }
        }
        self.words = words
        self.paragraphs = paragraphs
        self.keys = keys
        self.keyWord = keyWord
    }

    /// Display pieces: whitespace words, or for an unspaced language short
    /// runs cut at punctuation so the line can still wrap and highlight.
    static func displayWords(_ text: String, language: String) -> [String] {
        if LanguageCatalog.writesSpaces(language) {
            return text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        var out: [String] = []
        var current = ""
        let breakers: Set<Character> = ["、", "。", "！", "？", "，", ",", ".", "!", "?"]
        for ch in text {
            current.append(ch)
            if breakers.contains(ch) || current.count >= 5 {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        // Glue a lone punctuation piece back onto the one before.
        var glued: [String] = []
        for piece in out {
            if piece.allSatisfy({ $0.isPunctuation }), let last = glued.popLast() {
                glued.append(last + piece)
            } else {
                glued.append(piece)
            }
        }
        return glued
    }

    static func keys(of text: String, perChar: Bool) -> [String] {
        let cleaned = text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        if perChar { return cleaned.filter { !$0.isWhitespace }.map(String.init) }
        return cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The display word the reader has reached (everything before it is
    /// read), given what the recognizer has heard so far and the previous
    /// position. Returns `current` when nothing new agrees.
    func advance(current: Int, heard: String) -> Int {
        let heardKeys = Self.keys(of: heard, perChar: perChar)
        guard !heardKeys.isEmpty, !keys.isEmpty else { return current }
        let tail = Array(heardKeys.suffix(perChar ? 6 : 4))
        let need = perChar ? 4 : 2
        // The key index the current word starts at.
        let currentKey = keyWord.firstIndex(where: { $0 >= current }) ?? keys.count
        let back = perChar ? 8 : 3
        let ahead = perChar ? 60 : 25
        let lo = max(0, currentKey - back)
        let hi = min(keys.count - 1, currentKey + ahead)
        guard lo <= hi else { return current }

        var best: (end: Int, score: Int)?
        for end in lo...hi {
            var score = 0
            for i in 0..<tail.count {
                let k = end - i
                guard k >= 0 else { break }
                if keys[k] == tail[tail.count - 1 - i] { score += 1 }
            }
            // A single long word right where we are is enough on its own.
            let solo = !perChar && score == 1 && keys[end] == tail.last
                && (tail.last?.count ?? 0) >= 5 && end <= currentKey + 3
            guard score >= need || solo else { continue }
            if best == nil || score > best!.score
                || (score == best!.score && abs(end - currentKey) < abs(best!.end - currentKey)) {
                best = (end, score)
            }
        }
        guard let best else { return current }
        let next = keyWord[best.end] + 1
        // Small steps back are allowed (a re-read), big ones are not.
        return next >= current - 2 ? next : current
    }

    /// Words a reader covers in `seconds` at the planned pace — the
    /// fixed-speed mode's step, and the nudge when following stalls.
    func wordsPerSecond(language: String) -> Double {
        let rate = Double(SpeechLibrary.plannedRate(language)) / 60
        guard !words.isEmpty else { return rate }
        let unitsPerWord = Double(max(1, SpeechLibrary.units(in: words.map(\.text).joined(separator: " "), language: language)))
            / Double(words.count)
        return rate / max(0.5, unitsPerWord)
    }
}
