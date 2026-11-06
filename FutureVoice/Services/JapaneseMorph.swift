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
            if let head = headword(ofTokenAt: i, in: tokens, lexicon: lexicon, forms: forms) {
                out.append((head, tokens[i].range))
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
            keyByToken[i] = headword(ofTokenAt: i, in: tokens, lexicon: lexicon, forms: forms) ?? ""
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

    /// The headword token `i` stands for, or nil — `dictionaryForm` with the
    /// tokens around it, which decide most of what the token can be.
    private static func headword(ofTokenAt i: Int, in tokens: [Token],
                                 lexicon: Set<String>,
                                 forms: [String: String]) -> String? {
        let token = tokens[i]
        if isCompoundParticle(at: i, in: tokens) { return nil }
        // て|しまう is grammar ("ended up"), not 閉まる or 始末.
        if i > 0, ["て", "で"].contains(tokens[i - 1].surface),
           ["しまう", "しまっ", "しまい", "しまわ", "しまえ", "しまお"].contains(token.surface) {
            return nil
        }
        // The token after this one, if nothing stands between them — in
        // はい、そう, はい is not a stem before そう.
        let next = i + 1 < tokens.count && tokens[i + 1].range.lowerBound == token.range.upperBound
            ? tokens[i + 1].surface : nil
        // A lone し with no inflection after it is する's stem after a noun
        // or an object (運動|し, 耳に|し, 買い物を|し|に) and the particle
        // after anything that inflects (おいしい|し, 話せる|し, ない|し).
        if token.surface == "し", next.map({ stemSlot(after: $0, stem: "し") }) ?? Slot.none == .none {
            guard i > 0, let before = tokens[i - 1].surface.last,
                  isKanji(before) || ("ァ"..."ヶ").contains(before)
                    || ["を", "に"].contains(tokens[i - 1].surface),
                  lexicon.contains("する") else { return nil }
            return "する"
        }
        // One kanji glued to a kanji word before it is a suffix or a counter
        // (理論|的, 三|回, 二|枚, 一日|中), read on'yomi; glued to the kanji
        // word after it, a prefix (同|意見). Only the exact headword may
        // stand for it: the tokenizer reads 的 here as まと and 枚 has a
        // JMdict spelling of びら, neither of which was said. A verb stem
        // keeps its rules (三回|見|た, 二人|来|た).
        if isSingleKanji(token.surface),
           next.map({ stemSlot(after: $0, stem: token.surface) }) ?? Slot.none == .none,
           oneKanjiIchidan[token.surface] == nil, irregulars[token.surface] == nil {
            let suffix = i > 0 && tokens[i - 1].range.upperBound == token.range.lowerBound
                && tokens[i - 1].surface.last.map(isKanji) == true
            let prefix = i + 1 < tokens.count && tokens[i + 1].range.lowerBound == token.range.upperBound
                && tokens[i + 1].surface.first.map(isKanji) == true
            if suffix || prefix {
                return lexicon.contains(token.surface) && !isFunctionToken(token.surface) ? token.surface : nil
            }
        }
        return dictionaryForm(of: token.surface, reading: token.reading, next: next,
                              in: lexicon, forms: forms)
    }

    /// に|つい|て, に|おい|て …: one particle the tokenizer cut in three, not
    /// 点く or 老いる. Kana only — 置いて and 付いて are the verbs.
    private static func isCompoundParticle(at i: Int, in tokens: [Token]) -> Bool {
        guard i > 0, tokens[i - 1].surface == "に",
              tokens[i - 1].range.upperBound == tokens[i].range.lowerBound else { return false }
        let s = tokens[i].surface
        if ["ついて", "おいて", "とって", "よって", "わたって"].contains(s) { return true }
        guard ["つい", "おい", "とっ", "よっ", "わたっ"].contains(s), i + 1 < tokens.count else { return false }
        return tokens[i + 1].surface == "て" && tokens[i + 1].range.lowerBound == tokens[i].range.upperBound
    }

    /// The headword one token stands for, or nil. Tries the surface's
    /// candidates, then the same candidates spelled in kana (a kanji spelling
    /// the list doesn't carry, 解る, still reads わかる).
    ///
    /// `next` — the token after this one. Inflection there (ます, ない, て,
    /// ば …) marks this token as a stem, and WHICH inflection says which stem:
    /// 行き before ました is 行く, not the noun 行き; すれ before ば is する,
    /// not 擦れる; 中 before で is the noun with a particle, not 中る.
    /// `inflected` is the older, context-free switch — a stem of any shape.
    static func dictionaryForm(of surface: String,
                               reading: String? = nil,
                               inflected: Bool = false,
                               next: String? = nil,
                               in lexicon: Set<String>,
                               forms: [String: String]) -> String? {
        guard !isFunctionToken(surface) else { return nil }
        let slot: Slot = next.map { stemSlot(after: $0, stem: surface) } ?? (inflected ? .loose : .none)
        let isStem = slot != .none
        enum Hit { case found(String), stop, miss }
        func resolve(_ c: String, _ need: Need) -> Hit {
            // An irregular that is grammar ends the ladder: あれ before ば is
            // ある, and the pronoun あれ further down is not what was said.
            // A rule's guess that is grammar is only a miss (しかし|ながら
            // guesses しか on the way to しかし).
            if isFunctionToken(c) { return need == .irregular ? .stop : .miss }
            var head: String?
            if lexicon.contains(c) {
                head = c
            } else if let h = forms[c], lexicon.contains(h), formIsSpelling(c, of: h, reading: reading) {
                head = h
            }
            guard let head else { return .miss }
            if isFunctionToken(head) { return need == .irregular ? .stop : .miss }
            return fits(head, need) ? .found(head) : .miss
        }
        func ordered(_ s: String) -> [(String, Need)] {
            let all = ladder(for: s, slot: slot)
            return isStem ? Array(all.dropFirst()) + all.prefix(1) : all
        }
        for (c, need) in ordered(surface) {
            switch resolve(c, need) {
            case .found(let head): return head
            case .stop: return nil
            case .miss: continue
            }
        }
        if let reading, reading != surface, !isFunctionToken(reading) {
            // A kanji noun's reading is kana, so the stem rules would happily
            // run on it — 箸 reads はし, and はし + る is 走る. The reading may
            // only stand in for the surface, never grow a verb the kanji
            // didn't have.
            let kanjiNoun = !isStem && !surface.contains(where: isKana)
            // And a kanji surface may only be read onto a headword that shares
            // a kanji with it (分った → 分かる), or onto a word the list writes
            // in kana, spelled exactly as read — a kanji word (鞄 → かばん), a
            // stem's rule (出来|た → できる, 溢れ|て → あふれる) or a verb in
            // its dictionary form (出来る → できる). Anything
            // else is a homophone: 週間 is not 習慣, 曲 is not 局, 回 (かい)
            // is not さじ, which JMdict also spells かい, and 言い is not いい.
            // A spelling that really is another word's (解る → 分かる) is in
            // `forms`.
            let kanji = Set(surface.filter(isKanji))
            let allKanji = !surface.contains(where: isKana)
            for (c, need) in kanjiNoun ? [(reading, Need.any)] : ordered(reading) {
                switch resolve(c, need) {
                case .found(let head):
                    let dictionaryVerb = surface.last.map(uRowKana.contains) == true
                        && bundledClasses[head]?.split(separator: ",").contains("verb") == true
                    let kanaAsRead = head == c && head.allSatisfy(isKana)
                        && (allKanji || need != .any || dictionaryVerb)
                    if !kanji.isEmpty, !head.contains(where: kanji.contains), !kanaAsRead { continue }
                    return head
                case .stop: return nil
                case .miss: continue
                }
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
        ladder(for: raw, slot: inflected ? .loose : .none).map(\.0)
    }

    /// What kind of headword a rule's guess has to be: the stem rules make
    /// verbs and adjectives, and a guess that lands on a noun is a homophone
    /// of the stem (やっ + つ is the noun やつ, not やる).
    private enum Need: String { case any, irregular, verb, adjective, noun }

    /// Which stem the token after this one asks for.
    private enum Slot {
        /// Not a stem.
        case none
        /// A stem of unknown shape — every rule (a chunk left whole, or a
        /// caller that only said "inflected").
        case loose
        case masu       // ます, たい, ながら — i-row (書き), ichidan (食べ)
        case nai        // ない, れる, せる — a-row (書か), ichidan
        case te         // て, た — onbin っ/い, し (話し), ichidan
        case de         // で, だ — onbin ん/い (読ん, 泳い) only
        case ba         // ば — e-row (書け, すれ, 食べれ)
        case volitional // う — o-row (書こ)
        case yoo        // よう — ichidan (食べ)
        case imperative // ろ — ichidan (見)
    }

    private static func stemSlot(after next: String, stem: String) -> Slot {
        switch next {
        case "ます", "まし", "ませ", "ましょ", "ましょう", "ません", "たい", "たく", "たかっ",
             "たけれ", "ながら", "なさい", "なさっ", "そう", "つつ":
            return .masu
        case "ない", "なかっ", "なく", "なけれ", "なきゃ", "なけりゃ", "なくちゃ", "なさ", "ず", "ぬ",
             "れ", "れる", "られ", "られる", "せ", "せる", "させ", "させる":
            return .nai
        case "て", "た", "ちゃ", "ちゃう", "ちゃっ", "ちゃい", "たり", "たら", "たろ",
             "てる", "てた", "てて", "てれ", "とく", "とい":
            return .te
        case "で", "だ", "じゃ", "だり", "だら", "じゃう", "じゃっ",
             "でる", "でた", "でて", "どく", "どい":
            // After anything but 読ん / 泳い this is the particle で or the
            // copula だ — 中で, それで, どこで, つもりだ — not inflection.
            return stem.hasSuffix("ん") || stem.hasSuffix("い") ? .de : .none
        case "ば": return .ba
        case "う": return .volitional
        case "よう": return .yoo
        case "ろ": return .imperative
        default: return .none
        }
    }

    private static func ladder(for raw: String, slot: Slot) -> [(String, Need)] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.allSatisfy(isJapanese) else { return [] }
        var bases: [(String, Slot)] = [(token, slot)]
        // A chunk the tokenizer left whole (食べました) — strip inflection
        // down to the stem the rules below expect.
        if let stem = strippingSuffix(token) { bases.append((stem, .loose)) }

        var out: [(String, Need)] = []
        for (n, (base, slot)) in bases.enumerated() {
            // A kana chunk's stripped stem is only a stem: そこない is not そこ.
            if n == 0 || !token.allSatisfy(isKana) { out.append((base, .any)) }
            let chars = Array(base)
            let isStem = slot != .none
            let loneKana = chars.count == 1 && isKana(chars[0])
            // Irregulars first, where a single kana would otherwise guess
            // wild — and a lone し, き, こ is one only as a stem (on its own,
            // 雨も降るし, し is the particle).
            if let irregular = irregulars[base], isStem || !loneKana {
                out.append(contentsOf: irregular.map { ($0, .irregular) })
            }
            if let verb = oneKanjiIchidan[base] { out.append((verb, .verb)) }
            let hasKana = chars.contains(where: isKana)
            guard isStem || hasKana else { continue }
            // A lone kana stem is almost always inflection; only the
            // irregulars above may speak for it.
            guard !loneKana else { continue }
            let last = chars.last!
            let head = String(chars.dropLast())

            // i-adjective: 多く / 高かっ / 高けれ → 多い / 高い.
            if base.hasSuffix("かっ") || base.hasSuffix("けれ") {
                out.append((String(chars.dropLast(2)) + "い", .adjective))
            }
            if last == "く", !head.isEmpty { out.append((head + "い", .adjective)) }

            // A word written in kana with no inflection after it is a word,
            // not a stem: とき is not 解く, しか is not 叱る, ほう is not 放る.
            // Kanji with okurigana keeps every rule (休み, 疲れ).
            let rules: Slot
            if isStem { rules = slot } else if chars.allSatisfy(isKana) { continue } else { rules = .loose }

            // Ichidan: the stem IS the dictionary form minus る (疲れ, 食べ,
            // 起き) — and an ichidan stem ends in an i- or e-row kana, so
            // しか + ない is never しかる. A kanji-final stem (得|られる,
            // 観|たい) only before real inflection — 中|で is not 中る.
            if [.loose, .masu, .nai, .te, .yoo, .imperative].contains(rules),
               iRowKana.contains(last) || eRowKana.contains(last)
                || (isKanji(last) && rules != .loose) {
                out.append((base + "る", .verb))
            }

            // Godan: the stem's last kana moves to the u-row (行き → 行く,
            // 行か → 行く), in the row the next token asks for. Onbin stems
            // (行っ, 読ん, 書い) have several possible sources; the lexicon
            // picks.
            if !head.isEmpty, let endings = godanEndings(for: rules)[String(last)] {
                out.append(contentsOf: endings.map { (head + $0, .verb) })
            }

            // Suru-noun: 勉強し / 勉強さ / 勉強せ → 勉強 (the list carries the noun).
            if ["し", "さ", "せ"].contains(last), !head.isEmpty, rules != .de {
                out.append((head, .noun))
                out.append((head + "する", .verb))
            }
        }
        var seen = Set<String>()
        return out.filter { !$0.0.isEmpty && seen.insert($0.0).inserted }
    }

    /// A rule's guess must be the kind of word the rule makes. A headword the
    /// class table doesn't know passes.
    private static func fits(_ head: String, _ need: Need) -> Bool {
        guard need != .any, need != .irregular, let classes = bundledClasses[head] else { return true }
        return classes.split(separator: ",").contains { $0 == need.rawValue }
    }

    /// A `forms` entry keyed by ONE kanji is a rare spelling far more often
    /// than the word said: 船 → 舟, 枚 → びら, 的 → まと, 具 → 妻. Kept only
    /// when the headword is written with that kanji, or is the kana word the
    /// tokenizer read it as (事 → こと, 所 → ところ).
    private static func formIsSpelling(_ key: String, of head: String, reading: String?) -> Bool {
        guard isSingleKanji(key), head != key, !head.contains(key) else { return true }
        return head.allSatisfy(isKana) && head == reading
    }

    // MARK: - Tables

    /// 行っ reads 行く, never 行う — the one onbin collision common enough to
    /// matter, and the only godan verb whose te-form is irregular.
    private static let irregulars: [String: [String]] = [
        "し": ["する"], "さ": ["する"], "せ": ["する"],
        "き": ["来る", "くる"], "こ": ["来る", "くる"], "来": ["来る"],
        "行っ": ["行く"], "いっ": ["行く", "いく"],
        // する and ある before ば: すれ is not 擦れる, あれ is not 荒れる (or
        // the pronoun) — ある is grammar, so the ladder stops there.
        "すれ": ["する"], "あれ": ["ある"],
        // いき before ます in kana is 行く far more often than 生きる.
        "いき": ["行く", "いく"],
    ]

    private static let oneKanjiIchidan: [String: String] = [
        "見": "見る", "出": "出る", "寝": "寝る", "着": "着る", "居": "居る", "似": "似る",
    ]

    /// Every godan rule at once, for a stem of unknown shape.
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

    private static let iRow: [String: [String]] = [
        "い": ["う"], "き": ["く"], "ぎ": ["ぐ"], "し": ["す"], "ち": ["つ"],
        "に": ["ぬ"], "び": ["ぶ"], "み": ["む"], "り": ["る"],
    ]
    private static let aRow: [String: [String]] = [
        "わ": ["う"], "か": ["く"], "が": ["ぐ"], "さ": ["す"], "た": ["つ"],
        "な": ["ぬ"], "ば": ["ぶ"], "ま": ["む"], "ら": ["る"],
    ]
    /// Also the potential stem (書け|ます, 読め|ない), which inflects like
    /// an ichidan verb.
    private static let eRow: [String: [String]] = [
        "え": ["う"], "け": ["く"], "げ": ["ぐ"], "せ": ["す"], "て": ["つ"],
        "ね": ["ぬ"], "べ": ["ぶ"], "め": ["む"], "れ": ["る"],
    ]
    private static let oRow: [String: [String]] = [
        "お": ["う"], "こ": ["く"], "ご": ["ぐ"], "そ": ["す"], "と": ["つ"],
        "の": ["ぬ"], "ぼ": ["ぶ"], "も": ["む"], "ろ": ["る"],
    ]

    private static func godanEndings(for slot: Slot) -> [String: [String]] {
        func merge(_ a: [String: [String]], _ b: [String: [String]]) -> [String: [String]] {
            a.merging(b) { $0 + $1 }
        }
        switch slot {
        case .none, .imperative: return [:]
        case .loose: return godanEndings
        case .masu: return merge(iRow, eRow)
        case .nai: return merge(aRow, eRow)
        case .te: return merge(["っ": ["う", "つ", "る"], "い": ["く"], "し": ["す"]], eRow)
        case .de: return ["ん": ["む", "ぶ", "ぬ"], "い": ["ぐ"]]
        case .ba, .yoo: return eRow
        case .volitional: return oRow
        }
    }

    private static let iRowKana: Set<Character> = Set("いきぎしじちぢにひびぴみり")
    private static let eRowKana: Set<Character> = Set("えけげせぜてでねへべぺめれ")
    private static let uRowKana: Set<Character> = Set("うくぐすずつづぬふぶぷむゆる")

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
        // Particles and formal nouns the stem rules would otherwise grow into
        // verbs (しか → 叱る, さえ → 冴える, わけ → 分ける), and the sentence
        // particle かい, which JMdict spells as さじ.
        "しか", "さえ", "すら", "こそ", "わけ", "かい",
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

    /// `text` with every run of Latin letters written in katakana
    /// (nawana → ナワナ), everything else untouched. What a shadow diff
    /// DISPLAYS for a romaji name, since it has to be cut into kana to be
    /// compared at all.
    static func katakana(fromLatinIn text: String) -> String {
        mapLatinRuns(text) { run in
            let m = NSMutableString(string: run)
            CFStringTransform(m, nil, kCFStringTransformLatinKatakana, false)
            return m as String
        }
    }

    /// One spelling per SOUND, for comparing what was said — never shown.
    /// A Latin-spelled word inside Japanese (the app's own name, "nawana")
    /// comes back from a ja-JP transcriber as ナワナ, from Gemini as ナワナ
    /// or なわな, and sits in the target as nawana: the same three morae in
    /// three scripts, and a letter-by-letter comparison scored every one of
    /// them as a word the learner never said. Latin runs and katakana both
    /// land on hiragana (width folded first, so ﾅﾜﾅ and ｎａｗａｎａ do too);
    /// kanji passes through — its reading depends on the words around it,
    /// which a per-character key can't see. ー is kept: it is the long vowel
    /// in either kana.
    static func soundSpelling(_ text: String) -> String {
        let folded = mapLatinRuns(text.precomposedStringWithCompatibilityMapping.lowercased(),
                                  hiragana(fromLatin:))
        var out = String.UnicodeScalarView()
        for s in folded.unicodeScalars {
            if (0x30A1...0x30F6).contains(s.value), let h = Unicode.Scalar(s.value - 0x60) {
                out.append(h)
            } else {
                out.append(s)
            }
        }
        return String(out)
    }

    /// Applies `transform` to each maximal run of ASCII letters in `text`.
    private static func mapLatinRuns(_ text: String, _ transform: (String) -> String) -> String {
        var out = ""
        var run = ""
        for ch in text {
            if ch.isASCII && ch.isLetter { run.append(ch); continue }
            if !run.isEmpty { out += transform(run); run = "" }
            out.append(ch)
        }
        if !run.isEmpty { out += transform(run) }
        return out
    }

    private static func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 }
    }

    private static func isSingleKanji(_ s: String) -> Bool {
        s.count == 1 && s.first.map(isKanji) == true
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

    /// headword → class(es), from `word_classes_ja.tsv` (noun, verb,
    /// adjective, na-adjective …). Read only to check that a stem rule landed
    /// on a verb or an adjective; empty when absent, which turns the check off.
    private static let bundledClasses: [String: String] = {
        guard let url = Bundle.main.url(forResource: "word_classes_ja", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }()

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
