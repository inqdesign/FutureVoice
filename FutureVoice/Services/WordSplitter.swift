import Foundation

/// Where a transcript's words begin and end, for the ACTIVE target language.
///
/// Every `split(separator: " ")` over learner or fluent-self text used to
/// assume the language writes spaces. Japanese doesn't, so a whole sentence
/// was one "word": nothing could be highlighted, no phrase could be matched
/// and a talk counted as one word a minute. This is the one place that knows
/// which languages need a segmenter (`JapaneseMorph`, `ChineseMorph`) and
/// which just split — and, for an unspaced one, WHICH segmenter: every
/// caller that cuts unspaced text asks here rather than naming one.
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
            : segments(text)
    }

    // MARK: - Unspaced languages

    /// Chinese rather than Japanese — the two unspaced targets.
    static var isChinese: Bool { LanguageCatalog.base(LanguageScope.active) == "zh" }

    /// The segmenter's words of unspaced text, punctuation dropped.
    static func segments(_ text: String) -> [String] {
        isChinese ? ChineseMorph.segments(in: text) : JapaneseMorph.segments(in: text)
    }

    /// Each segment with where it sits in `text`.
    static func segmentRanges(_ text: String) -> [(surface: String, range: Range<String.Index>)] {
        isChinese
            ? ChineseMorph.words(in: text).map { ($0.surface, $0.range) }
            : JapaneseMorph.words(in: text).map { ($0.surface, $0.range) }
    }

    /// Words and the punctuation between them; concatenated, the text back.
    static func displayPieces(_ text: String) -> [JapaneseMorph.Piece] {
        isChinese ? ChineseMorph.displayPieces(in: text) : JapaneseMorph.displayPieces(in: text)
    }

    /// Every wordlist headword said in `text`, with its range.
    static func headwords(in text: String) -> [(headword: String, range: Range<String.Index>)] {
        isChinese
            ? ChineseMorph.headwords(in: text, lexicon: CoreVocabulary.set)
            : JapaneseMorph.headwords(in: text, lexicon: CoreVocabulary.set,
                                      forms: JapaneseMorph.bundledForms)
    }

    /// The notebook key of every `displayPieces` piece ("" for none).
    static func pieceKeys(in text: String) -> [String] {
        isChinese
            ? ChineseMorph.pieceKeys(in: text, lexicon: CoreVocabulary.set)
            : JapaneseMorph.pieceKeys(in: text, lexicon: CoreVocabulary.set,
                                      forms: JapaneseMorph.bundledForms)
    }

    /// A particle or filler — grammar, never a word to hint, study or credit.
    static func isFunctionToken(_ token: String) -> Bool {
        isChinese ? ChineseMorph.isFunctionToken(token) : JapaneseMorph.isFunctionToken(token)
    }

    /// `words(text).count` without building the words: this is asked of
    /// every sentence of every talk on each book build, and the split's
    /// substring allocations were measurable there (2026-09-23).
    static func count(_ text: String) -> Int {
        guard spaced else { return words(text).count }
        var n = 0
        var inWord = false
        for c in text {
            if c.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                n += 1
            }
        }
        return n
    }

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
        for piece in displayPieces(text) {
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
        spaced ? !text.contains(" ") : segments(text).count <= 1
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
