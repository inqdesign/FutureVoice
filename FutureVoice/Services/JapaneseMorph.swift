import Foundation

/// Deterministic Japanese surface-form → dictionary-form matching, for vocab
/// tracking against the graded wordlist (`cefr_words_ja.tsv`, JLPT headwords
/// in dictionary form: 行く, 疲れる, 多い, 家事 …).
///
/// Japanese needs this for two reasons Korean doesn't. There are no spaces,
/// so every `split(separator: " ")` in the app reads a whole sentence as one
/// word — `words(in:)` is the segmenter that replaces it. And NLTagger has
/// no lemma or lexical-class scheme for Japanese at all (measured on iOS 26:
/// every token comes back `OtherWord`, lemma nil), so there is nothing to
/// fall back on.
///
/// Same contract as `KoreanMorph`: a HEURISTIC that generates candidate
/// dictionary forms and keeps only what the lexicon confirms. A wrong guess
/// costs recall, never precision — nothing maps to a word the learner didn't
/// use.
enum JapaneseMorph {

    /// One segmented word. `reading` is hiragana, from the system tokenizer —
    /// the reading of the SURFACE (行き → いき), not of the dictionary form.
    struct Token: Equatable {
        let surface: String
        let range: Range<String.Index>
        let reading: String
    }

    // MARK: - Segmentation

    /// Words in `text`, in order, punctuation and whitespace skipped.
    ///
    /// `CFStringTokenizer` rather than `NLTokenizer`: the two cut Japanese
    /// identically, and only this one hands back a reading, which is what lets
    /// a kana spelling (わかる) meet a kanji headword (分かる). It splits
    /// inflection off the stem — 行きました → 行き / まし / た — which is the
    /// grain `candidates(for:)` is written for.
    static func words(in text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRangeMake(0, ns.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var out: [Token] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: r.location, length: r.length)
            guard let range = Range(nsRange, in: text) else { continue }
            let surface = String(text[range])
            guard surface.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            else { continue }
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            out.append(Token(surface: surface, range: range,
                             reading: latin.map(hiragana(fromLatin:)) ?? surface))
        }
        return out
    }

    /// Surface words only — the drop-in for `split(separator: " ")`.
    static func segments(in text: String) -> [String] {
        words(in: text).map(\.surface)
    }

    // MARK: - Headwords

    /// Every headword spoken in `text`, with the range it was said over.
    ///
    /// Adjacent tokens are tried joined first (up to three, EXACT headword
    /// only), because the tokenizer occasionally cuts a listed compound in
    /// two. The join never reaches into a function token — し + た would
    /// otherwise spell した and read back as 下.
    static func headwords(in text: String,
                          lexicon: Set<String>,
                          readings: [String: String]) -> [(headword: String, range: Range<String.Index>)] {
        let tokens = words(in: text)
        var out: [(String, Range<String.Index>)] = []
        var i = 0
        while i < tokens.count {
            var matched = false
            for width in stride(from: min(3, tokens.count - i), through: 2, by: -1) {
                let slice = tokens[i..<(i + width)]
                guard !slice.contains(where: { isFunctionToken($0.surface) }) else { continue }
                let joined = slice.map(\.surface).joined()
                if lexicon.contains(joined) {
                    out.append((joined, slice.first!.range.lowerBound..<slice.last!.range.upperBound))
                    i += width
                    matched = true
                    break
                }
            }
            if matched { continue }
            let token = tokens[i]
            let inflected = i + 1 < tokens.count && inflections.contains(tokens[i + 1].surface)
            if let head = dictionaryForm(of: token.surface, reading: token.reading,
                                         inflected: inflected,
                                         in: lexicon, readings: readings) {
                out.append((head, token.range))
            }
            i += 1
        }
        return out
    }

    /// The headword one token stands for, or nil. Tries the surface's
    /// candidates, then the same candidates spelled in kana (a kanji spelling
    /// the list doesn't carry, 解る, still reads わかる).
    ///
    /// `inflected` — the next token is inflection (ます, たい, て …), so this
    /// token is a verb or adjective stem. That flips the order: 行き before
    /// ました is 行く, not the noun 行き, and 来 before ます is 来る, not 来.
    static func dictionaryForm(of surface: String,
                               reading: String? = nil,
                               inflected: Bool = false,
                               in lexicon: Set<String>,
                               readings: [String: String]) -> String? {
        guard !isFunctionToken(surface) else { return nil }
        func resolve(_ c: String) -> String? {
            let head = lexicon.contains(c) ? c : readings[c].flatMap { lexicon.contains($0) ? $0 : nil }
            return head.flatMap { isFunctionToken($0) ? nil : $0 }
        }
        func ordered(_ s: String) -> [String] {
            let all = candidates(for: s, inflected: inflected)
            return inflected ? Array(all.dropFirst()) + all.prefix(1) : all
        }
        for c in ordered(surface) {
            if let head = resolve(c) { return head }
        }
        if let reading, reading != surface, !isFunctionToken(reading) {
            // A kanji noun's reading is kana, so the stem rules would happily
            // run on it — 箸 reads はし, and はし + る is 走る. The reading may
            // only stand in for the surface, never grow a verb the kanji
            // didn't have.
            let kanjiNoun = !inflected && !surface.contains(where: isKana)
            for c in kanjiNoun ? [reading] : ordered(reading) {
                if let head = resolve(c) { return head }
            }
        }
        return nil
    }

    /// Ordered dictionary-form candidates for one token, most likely first.
    /// The token itself leads — nouns, adverbs and a dictionary-form verb are
    /// their own surface.
    ///
    /// A surface written entirely in kanji is a noun unless `inflected` says
    /// otherwise — 語 must not become 語る, 日本 must not become 日本る. The
    /// handful of one-kanji ichidan verbs (見, 出, 寝 …) are listed, because
    /// 見に行く puts a particle, not inflection, after the stem.
    static func candidates(for raw: String, inflected: Bool = true) -> [String] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.allSatisfy(isJapanese) else { return [] }
        var bases = [token]
        // A chunk the tokenizer left whole (食べました) — strip inflection
        // down to the stem the rules below expect.
        if let stem = strippingSuffix(token) { bases.append(stem) }

        var out: [String] = []
        for base in bases {
            out.append(base)
            // Irregulars first, where a single kana would otherwise guess wild.
            if let irregular = irregulars[base] { out.append(contentsOf: irregular) }
            if let verb = oneKanjiIchidan[base] { out.append(verb) }
            let chars = Array(base)
            guard inflected || chars.contains(where: isKana) else { continue }
            // A lone kana stem is almost always inflection; only the
            // irregulars above may speak for it.
            guard chars.count >= 2 || !isKana(chars[0]) else { continue }
            let last = String(chars.last!)
            let head = String(chars.dropLast())

            // i-adjective: 多く / 高かっ / 高けれ → 多い / 高い.
            if base.hasSuffix("かっ") || base.hasSuffix("けれ") {
                out.append(String(chars.dropLast(2)) + "い")
            }
            if last == "く", !head.isEmpty { out.append(head + "い") }

            // Ichidan: the stem IS the dictionary form minus る (疲れ, 見, 食べ).
            out.append(base + "る")

            // Godan: the stem's last kana moves to the u-row (行き → 行く,
            // 行か → 行く). Onbin stems (行っ, 読ん, 書い) have several
            // possible sources; the lexicon picks.
            if !head.isEmpty, let endings = godanEndings[last] {
                out.append(contentsOf: endings.map { head + $0 })
            }

            // Suru-noun: 勉強し / 勉強さ / 勉強せ → 勉強 (the list carries the noun).
            if ["し", "さ", "せ"].contains(last), !head.isEmpty {
                out.append(head)
                out.append(head + "する")
            }
        }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Tables

    /// 行っ reads 行く, never 行う — the one onbin collision common enough to
    /// matter, and the only godan verb whose te-form is irregular.
    private static let irregulars: [String: [String]] = [
        "し": ["する"], "さ": ["する"], "せ": ["する"],
        "き": ["来る", "くる"], "こ": ["来る", "くる"], "来": ["来る"],
        "行っ": ["行く"], "いっ": ["行く", "いく"],
    ]

    private static let oneKanjiIchidan: [String: String] = [
        "見": "見る", "出": "出る", "寝": "寝る", "着": "着る", "居": "居る", "似": "似る",
    ]

    /// Tokens that mark the one before them as a stem.
    private static let inflections: Set<String> = [
        "ます", "まし", "ませ", "たい", "たく", "たかっ", "て", "た", "で", "だ",
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "れる", "られ", "られる",
        "せる", "させ", "させる", "ちゃ", "じゃ", "ば", "う", "よう", "ろ",
    ]

    private static let godanEndings: [String: [String]] = [
        // i-row (masu stem)
        "い": ["う", "く", "ぐ"], "き": ["く"], "ぎ": ["ぐ"], "し": ["す"], "ち": ["つ"],
        "に": ["ぬ"], "び": ["ぶ"], "み": ["む"], "り": ["る"],
        // a-row (negative, passive, causative)
        "わ": ["う"], "か": ["く"], "が": ["ぐ"], "さ": ["す"], "た": ["つ"],
        "な": ["ぬ"], "ば": ["ぶ"], "ま": ["む"], "ら": ["る"],
        // e-row (potential, conditional, imperative)
        "え": ["う"], "け": ["く"], "げ": ["ぐ"], "せ": ["す"], "て": ["つ"],
        "ね": ["ぬ"], "べ": ["ぶ"], "め": ["む"], "れ": ["る"],
        // o-row (volitional)
        "お": ["う"], "こ": ["く"], "ご": ["ぐ"], "そ": ["す"], "と": ["つ"],
        "の": ["ぬ"], "ぼ": ["ぶ"], "も": ["む"], "ろ": ["る"],
        // onbin (te/ta stems) — い also covers 書い → 書く / 泳い → 泳ぐ
        "っ": ["う", "つ", "る"], "ん": ["む", "ぶ", "ぬ"],
    ]

    /// Inflection a tokenizer may leave attached, longest first.
    private static let suffixes = [
        "ませんでした", "なかった", "ました", "ません", "ている", "ていた",
        "でした", "たかった", "られる", "させる",
        "ます", "ない", "たい", "ます", "です", "ている",
        "て", "た", "で", "だ", "う",
    ].sorted { $0.count > $1.count }

    /// Particles, auxiliaries and copulas: tokens that are grammar, never a
    /// word to track. Without this ない reads back as 無い and まし as 増し.
    private static let functionTokens: Set<String> = [
        "は", "が", "を", "に", "へ", "と", "も", "や", "か", "ね", "よ", "な",
        "の", "ん", "で", "て", "た", "だ", "う", "ぞ", "さ", "わ",
        "から", "まで", "より", "けど", "けれど", "って", "ので", "のに", "でも",
        "ます", "まし", "ませ", "です", "でし", "だっ", "でしょ", "だろ",
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "ば", "たい", "たく", "たかっ",
        "れる", "られ", "られる", "せる", "させ", "させる", "ちゃ", "じゃ",
        "いる", "い", "ある", "あっ", "おり", "ござい",
    ]

    static func isFunctionToken(_ s: String) -> Bool { functionTokens.contains(s) }

    private static func strippingSuffix(_ word: String) -> String? {
        for s in suffixes where word.count > s.count && word.hasSuffix(s) {
            return String(word.dropLast(s.count))
        }
        return nil
    }

    // MARK: - Script helpers

    static func hiragana(fromLatin latin: String) -> String {
        let m = NSMutableString(string: latin)
        CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)
        return m as String
    }

    private static func isKana(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { (0x3041...0x30FF).contains($0.value) }
    }

    private static func isJapanese(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy {
            (0x3041...0x30FF).contains($0.value)       // kana, ー
                || (0x4E00...0x9FFF).contains($0.value) // CJK unified
                || $0.value == 0x3005                   // 々
        }
    }

    // MARK: - Bundled readings

    /// kana spelling → headword, from `ja_readings.tsv` (see
    /// `scripts/build-ja-wordlist.py` for what is and isn't kept). Loaded
    /// once; empty when the resource is absent, which only costs recall.
    static let bundledReadings: [String: String] = {
        guard let url = Bundle.main.url(forResource: "ja_readings", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }()
}
