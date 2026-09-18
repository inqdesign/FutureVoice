import Foundation

/// Deterministic Japanese surface-form → dictionary-form matching, for vocab
/// tracking against the graded wordlist (`cefr_words_ja.tsv`, JLPT headwords
/// in dictionary form: 行く, 疲れる, 多い, 家事 …).
///
/// Japanese needs this for two reasons Korean doesn't. There are no spaces,
/// so every `split(separator: " ")` in the app read a whole sentence as one
/// word — `words(in:)` is the segmenter `WordSplitter` routes to. And
/// NLTagger has no lemma or lexical-class scheme for Japanese at all
/// (measured on iOS 26: every token comes back `OtherWord`, lemma nil), so
/// there is nothing to fall back on.
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

    /// A run of the original text: a word, or the punctuation/whitespace
    /// between two words. Concatenating every piece gives the text back.
    struct Piece: Equatable {
        let text: String
        let isWord: Bool
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
            // Digits are words too (3時 is 3 + 時): only a token with no
            // letter or digit at all is punctuation.
            guard surface.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
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

    /// The whole text as words and the gaps between them, for a view that
    /// styles words and must still draw the 、。「」 around them. The
    /// tokenizer never emits punctuation, so the gaps are read off the ranges.
    static func displayPieces(in text: String) -> [Piece] {
        var out: [Piece] = []
        var cursor = text.startIndex
        for token in words(in: text) {
            if token.range.lowerBound > cursor {
                out.append(Piece(text: String(text[cursor..<token.range.lowerBound]), isWord: false))
            }
            out.append(Piece(text: token.surface, isWord: true))
            cursor = token.range.upperBound
        }
        if cursor < text.endIndex {
            out.append(Piece(text: String(text[cursor...]), isWord: false))
        }
        return out
    }

    // MARK: - Headwords

    /// Every headword spoken in `text`, with the range it was said over.
    ///
    /// Adjacent tokens are tried joined first (up to three, EXACT headword
    /// only), because the tokenizer cuts some listed compounds in two
    /// (面倒|くさい, お|疲れ|様). The join never reaches into a function
    /// token — し + た would otherwise spell した and read back as 下.
    static func headwords(in text: String,
                          lexicon: Set<String>,
                          forms: [String: String]) -> [(headword: String, range: Range<String.Index>)] {
        let tokens = words(in: text)
        var out: [(String, Range<String.Index>)] = []
        var i = 0
        while i < tokens.count {
            if let (head, width) = compound(at: i, in: tokens, lexicon: lexicon, forms: forms) {
                out.append((head, tokens[i].range.lowerBound..<tokens[i + width - 1].range.upperBound))
                i += width
                continue
            }
            let token = tokens[i]
            let inflected = i + 1 < tokens.count && inflections.contains(tokens[i + 1].surface)
            if let head = dictionaryForm(of: token.surface, reading: token.reading,
                                         inflected: inflected, in: lexicon, forms: forms) {
                out.append((head, token.range))
            }
            i += 1
        }
        return out
    }

    /// The notebook key for every piece of `displayPieces(in:)`, in the same
    /// order — "" for punctuation and for a word the pool doesn't know. A
    /// compound headword puts its key on each of the tokens it spans, so the
    /// whole word lights up and any of it can be tapped.
    static func pieceKeys(in text: String,
                          lexicon: Set<String>,
                          forms: [String: String]) -> [String] {
        let tokens = words(in: text)
        var keyByToken = [String](repeating: "", count: tokens.count)
        var i = 0
        while i < tokens.count {
            if let (head, width) = compound(at: i, in: tokens, lexicon: lexicon, forms: forms) {
                for k in i..<(i + width) { keyByToken[k] = head }
                i += width
                continue
            }
            let inflected = i + 1 < tokens.count && inflections.contains(tokens[i + 1].surface)
            keyByToken[i] = dictionaryForm(of: tokens[i].surface, reading: tokens[i].reading,
                                           inflected: inflected, in: lexicon, forms: forms) ?? ""
            i += 1
        }
        var out: [String] = []
        var next = 0
        for piece in displayPieces(in: text) {
            if piece.isWord { out.append(keyByToken[next]); next += 1 } else { out.append("") }
        }
        return out
    }

    private static func compound(at i: Int, in tokens: [Token],
                                 lexicon: Set<String>,
                                 forms: [String: String]) -> (String, Int)? {
        guard tokens.count - i >= 2 else { return nil }
        for width in stride(from: min(3, tokens.count - i), through: 2, by: -1) {
            let slice = tokens[i..<(i + width)]
            guard !slice.contains(where: { isFunctionToken($0.surface) }) else { continue }
            let joined = slice.map(\.surface).joined()
            if lexicon.contains(joined) { return (joined, width) }
            if let head = forms[joined], lexicon.contains(head) { return (head, width) }
        }
        return nil
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
                               forms: [String: String]) -> String? {
        guard !isFunctionToken(surface) else { return nil }
        func resolve(_ c: String) -> String? {
            let head = lexicon.contains(c) ? c : forms[c].flatMap { lexicon.contains($0) ? $0 : nil }
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
        "ます", "ない", "たい", "です",
        "て", "た", "で", "だ", "う",
    ].sorted { $0.count > $1.count }

    /// Particles, auxiliaries and copulas: tokens that are grammar, never a
    /// word to track. Without this ない reads back as 無い and まし as 増し.
    /// `CarryoverDetector` reads it as the filler list too: a phrase made of
    /// nothing but these has taught nobody anything.
    private static let functionTokens: Set<String> = [
        "は", "が", "を", "に", "へ", "と", "も", "や", "か", "ね", "よ", "な",
        "の", "ん", "で", "て", "た", "だ", "う", "ぞ", "さ", "わ",
        "から", "まで", "より", "けど", "けれど", "って", "ので", "のに", "でも",
        "ます", "まし", "ませ", "です", "でし", "だっ", "でしょ", "だろ",
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "ば", "たい", "たく", "たかっ",
        "れる", "られ", "られる", "せる", "させ", "させる", "ちゃ", "じゃ",
        "いる", "い", "ある", "あっ", "おり", "ござい",
        // Spoken contractions and the passive/potential れ on its own —
        // 追わ|れ|てる. てる is what ている sounds like; it is not 照る.
        "れ", "てる", "てた", "てて", "てれ", "とく", "とい", "とる",
        "ちゃう", "ちゃっ", "ちゃい", "じゃう", "じゃっ",
        "たり", "ながら", "ず", "ぬ", "まい", "じゃん", "かな", "かしら", "っけ",
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

    // MARK: - Readings

    /// The whole line as kana, punctuation and spacing dropped — what it
    /// SOUNDS like, whatever script the transcriber chose. 分かった and
    /// わかった read the same; 分かった and 分かりました don't.
    static func reading(of text: String) -> String {
        words(in: text).map(\.reading).joined()
    }

    /// How a headword is read, for display beside it — nil when it has no
    /// kanji (the word already spells its sound). The JLPT list's readings
    /// first, all of them for a word that has several (からい・つらい);
    /// the system tokenizer's guess for anything off the list.
    static func reading(ofHeadword word: String) -> String? {
        guard word.contains(where: { ch in
            ch.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 }
        }) else { return nil }
        if let listed = bundledReadings[word] { return listed }
        let guess = reading(of: word)
        return guess.isEmpty || guess == word ? nil : guess
    }

    /// headword → reading(s), the third column of `cefr_words_ja.tsv`.
    private static let bundledReadings: [String: String] = {
        guard let url = Bundle.main.url(forResource: "cefr_words_ja", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 3 { out[String(parts[0])] = String(parts[2]) }
        }
        return out
    }()

    // MARK: - Bundled forms

    /// Any other spelling → headword, from `ja_forms.tsv`: kana readings
    /// (わかる → 分かる), other kanji (判る → 分かる), okurigana variants. See
    /// `scripts/build-ja-wordlist.py` for what is and isn't kept. Loaded
    /// once; empty when the resource is absent, which only costs recall.
    static let bundledForms: [String: String] = {
        guard let url = Bundle.main.url(forResource: "ja_forms", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }()
}
