import Foundation

/// Where a transcript's words begin and end, for the ACTIVE target language.
///
/// Every `split(separator: " ")` over learner or fluent-self text used to
/// assume the language writes spaces. Japanese doesn't, so a whole sentence
/// was one "word": nothing could be highlighted, no phrase could be matched
/// and a talk counted as one word a minute. This is the one place that knows
/// which languages need a segmenter (`JapaneseMorph`) and which just split.
///
/// Only for text in the TARGET language — never for chrome or coaching.
enum WordSplitter {

    /// True when words are separated by spaces, so joining them back needs one.
    static var spaced: Bool { LanguageCatalog.writesSpaces(LanguageScope.active) }

    /// The words of `text`, punctuation dropped for an unspaced language
    /// (a spaced one keeps it attached, as it always has).
    static func words(_ text: String) -> [String] {
        spaced
            ? text.split(whereSeparator: \.isWhitespace).map(String.init)
            : JapaneseMorph.segments(in: text)
    }

    static func count(_ text: String) -> Int { words(text).count }

    /// The words a TIMELINE is cut into — what karaoke lights, a tap
    /// selects and the rhythm dots sit under. Unlike `words`, nothing is
    /// dropped: punctuation rides on the word before it (an opening bracket
    /// on the word after), so the words joined back give the line itself,
    /// which is what the shadow screen draws from them. A spaced language
    /// splits on whitespace exactly as the timing code always has.
    static func timingWords(_ text: String) -> [String] {
        guard !spaced else {
            return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        }
        var out: [String] = []
        var leading = ""
        for piece in JapaneseMorph.displayPieces(in: text) {
            let t = piece.text.filter { !$0.isWhitespace }
            guard !t.isEmpty else { continue }
            if piece.isWord {
                out.append(leading + t)
                leading = ""
                continue
            }
            for ch in t {
                if opening.contains(ch) || out.isEmpty { leading.append(ch) }
                else { out[out.count - 1].append(ch) }
            }
        }
        if !leading.isEmpty {
            if out.isEmpty { out = [leading] } else { out[out.count - 1] += leading }
        }
        return out
    }

    /// Brackets that belong to the word AFTER them.
    private static let opening: Set<Character> = ["「", "『", "（", "(", "【", "〈", "《", "［", "[", "“", "‘"]

    /// One notebook entry or several? A spaced language can hold a two-word
    /// chunk the learner tapped; an unspaced one keys by segment.
    static func isSingleWord(_ text: String) -> Bool {
        spaced ? !text.contains(" ") : JapaneseMorph.segments(in: text).count <= 1
    }

    /// Leading snippet for a title — the first few words, or the first
    /// few characters where words aren't delimited.
    static func snippet(_ text: String, words maxWords: Int, characters maxChars: Int) -> String {
        if spaced {
            let ws = text.split(separator: " ")
            let head = ws.prefix(maxWords).joined(separator: " ")
            return ws.count > maxWords ? head + "…" : head
        }
        return text.count > maxChars ? String(text.prefix(maxChars)) + "…" : text
    }
}
