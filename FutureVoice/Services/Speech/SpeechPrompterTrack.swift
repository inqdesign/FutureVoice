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
        // Only the last few keys are matched, so only the tail is read: the
        // transcript grows to the whole take and this runs on every partial.
        let heardKeys = Self.keys(of: String(heard.suffix(160)), perChar: perChar)
        guard !heardKeys.isEmpty, !keys.isEmpty else { return current }
        // The key index the current word starts at.
        let currentKey = keyWord.firstIndex(where: { $0 >= current }) ?? keys.count
        let back = perChar ? 8 : 3
        let ahead = perChar ? 60 : 25
        let lo = max(0, currentKey - back)
        let hi = min(keys.count - 1, currentKey + ahead)
        guard lo <= hi else { return current }

        // A run of the heard tail, looked for as a CONTIGUOUS run of the
        // script near where the reader is. Longest run first; the last key
        // or two may be dropped, because the newest partial is the one the
        // recognizer is least sure of (Korean especially: a syllable it will
        // rewrite a moment later). The first version scored the tail against
        // the script position by position, so one dropped or changed syllable
        // inside it shifted every comparison and NOTHING matched — the
        // prompter sat still under a Korean reader (founder, 2026-10-05).
        let lengths = perChar ? [5, 4, 3] : [3, 2]
        for length in lengths {
            for drop in 0...2 {
                guard heardKeys.count >= length + drop else { continue }
                let needle = Array(heardKeys[(heardKeys.count - drop - length)..<(heardKeys.count - drop)])
                // Short runs are common words; only trust them close by.
                let reach = length >= (perChar ? 4 : 3) ? hi : min(hi, currentKey + (perChar ? 20 : 8))
                guard lo + length - 1 <= reach else { continue }
                var best: Int?
                for end in (lo + length - 1)...reach {
                    var same = true
                    for i in 0..<length where keys[end - length + 1 + i] != needle[i] {
                        same = false
                        break
                    }
                    guard same else { continue }
                    if best == nil || abs(end - currentKey) < abs(best! - currentKey) { best = end }
                }
                if let end = best {
                    let next = keyWord[end] + 1
                    // Small steps back are allowed (a re-read), big ones are not.
                    return next >= current - 2 ? next : current
                }
            }
        }
        // A single long word right where we are is enough on its own.
        if !perChar, let last = heardKeys.last, last.count >= 5 {
            for end in lo...min(hi, currentKey + 3) where keys[end] == last {
                return max(current, keyWord[end] + 1)
            }
        }
        return current
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
