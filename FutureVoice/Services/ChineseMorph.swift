import Foundation

/// Simplified Chinese words for vocab tracking against the graded wordlist
/// (`cefr_words_zh.tsv`, HSK 3.0 headwords: 吃饭, 觉得, 一点儿 …).
///
/// Chinese has no spaces and no inflection, so the job is only segmentation:
/// a word IS its dictionary form, and the analyzer never has to guess a stem
/// the way `JapaneseMorph` and `KoreanMorph` do. `CFStringTokenizer` cuts
/// Simplified text into words the way the HSK list does (我们 · 今天 · 吃饭 ·
/// 觉得 · 怎么样, measured 2026-11-13) and hands back pinyin with tones.
///
/// Script: the app teaches Simplified, but a transcriber or a learner may
/// write Traditional (說 for 说). The tokenizer reads Traditional one
/// character at a time, so the text is folded to Simplified first
/// (`simplified(_:)`, ICU's Hant-Hans) and the ranges are mapped back onto the
/// original — the screen keeps what was written, the lookups see Simplified.
///
/// Same contract as the other analyzers: only the lexicon confirms a word, so
/// a wrong cut costs recall, never precision.
enum ChineseMorph {

    /// One word: `surface` as written, `key` its Simplified spelling (what
    /// the lexicon is keyed by), `pinyin` with tone marks.
    struct Token: Equatable {
        let surface: String
        let key: String
        let range: Range<String.Index>
        let pinyin: String
    }

    // MARK: - Script

    /// `text` in Simplified characters. Han characters only change; the
    /// conversion is one UTF-16 unit for one, which is what lets a range found
    /// in the folded text land on the same characters of the original.
    static func simplified(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isHan) else { return text }
        return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    // MARK: - Segmentation

    /// Words in `text`, in order, punctuation and whitespace skipped.
    static func words(in text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let folded = simplified(text)
        let original = text as NSString
        let ns = folded as NSString
        // A conversion that changed the length can't share ranges; read the
        // original as written then (Traditional cut per character is still
        // better than nothing).
        let source = ns.length == original.length ? folded : text
        let sourceNS = source as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, source as CFString, CFRangeMake(0, sourceNS.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "zh-Hans") as CFLocale)
        var out: [Token] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: r.location, length: r.length)
            guard let range = Range(nsRange, in: text) else { continue }
            let surface = String(text[range])
            guard surface.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
            else { continue }
            let key = sourceNS.substring(with: nsRange)
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            out.append(Token(surface: surface, key: key, range: range, pinyin: latin ?? key))
        }
        return out
    }

    /// Surface words only — the drop-in for `split(separator: " ")`.
    static func segments(in text: String) -> [String] {
        words(in: text).map(\.surface)
    }

    /// The whole text as words and the gaps between them (，。「」 …), so a
    /// view can style words and still draw the punctuation around them.
    static func displayPieces(in text: String) -> [JapaneseMorph.Piece] {
        var out: [JapaneseMorph.Piece] = []
        var cursor = text.startIndex
        for token in words(in: text) {
            if token.range.lowerBound > cursor {
                out.append(.init(text: String(text[cursor..<token.range.lowerBound]), isWord: false))
            }
            out.append(.init(text: token.surface, isWord: true))
            cursor = token.range.upperBound
        }
        if cursor < text.endIndex {
            out.append(.init(text: String(text[cursor...]), isWord: false))
        }
        return out
    }

    // MARK: - Headwords

    /// Every headword spoken in `text`, with the range it was said over.
    ///
    /// Adjacent tokens are tried joined first (up to three, longest first),
    /// because the tokenizer cuts some listed words in two (打 | 电话 for
    /// 打电话). A join never reaches into a particle — 了 + 解 is not 了解
    /// unless the tokenizer itself kept it together.
    static func headwords(in text: String,
                          lexicon: Set<String>,
                          forms: [String: String] = bundledForms)
        -> [(headword: String, range: Range<String.Index>)] {
        let tokens = words(in: text)
        var out: [(String, Range<String.Index>)] = []
        var i = 0
        while i < tokens.count {
            if let (head, width) = compound(at: i, in: tokens, lexicon: lexicon, forms: forms) {
                out.append((head, tokens[i].range.lowerBound..<tokens[i + width - 1].range.upperBound))
                i += width
                continue
            }
            if let head = headword(of: tokens[i].key, lexicon: lexicon, forms: forms) {
                out.append((head, tokens[i].range))
            }
            i += 1
        }
        return out
    }

    /// The notebook key for every piece of `displayPieces(in:)`, in the same
    /// order — "" for punctuation and for a word the pool doesn't know.
    static func pieceKeys(in text: String,
                          lexicon: Set<String>,
                          forms: [String: String] = bundledForms) -> [String] {
        let tokens = words(in: text)
        var keyByToken = [String](repeating: "", count: tokens.count)
        var i = 0
        while i < tokens.count {
            if let (head, width) = compound(at: i, in: tokens, lexicon: lexicon, forms: forms) {
                for k in i..<(i + width) { keyByToken[k] = head }
                i += width
                continue
            }
            keyByToken[i] = headword(of: tokens[i].key, lexicon: lexicon, forms: forms) ?? ""
            i += 1
        }
        var out: [String] = []
        var next = 0
        for piece in displayPieces(in: text) {
            if piece.isWord { out.append(keyByToken[next]); next += 1 } else { out.append("") }
        }
        return out
    }

    /// The headword a single word is, if the list carries it.
    static func headword(of word: String,
                         lexicon: Set<String>,
                         forms: [String: String] = bundledForms) -> String? {
        let key = simplified(word)
        if lexicon.contains(key) { return key }
        if let head = forms[key], lexicon.contains(head) { return head }
        return nil
    }

    private static func compound(at i: Int, in tokens: [Token],
                                 lexicon: Set<String>,
                                 forms: [String: String]) -> (String, Int)? {
        guard tokens.count - i >= 2 else { return nil }
        for width in stride(from: min(3, tokens.count - i), through: 2, by: -1) {
            let slice = tokens[i..<(i + width)]
            guard !slice.contains(where: { isFunctionToken($0.key) }) else { continue }
            let joined = slice.map(\.key).joined()
            if lexicon.contains(joined) { return (joined, width) }
            if let head = forms[joined], lexicon.contains(head) { return (head, width) }
        }
        return nil
    }

    // MARK: - Function words

    /// Particles and fillers — grammar or hesitation, never a word to study
    /// or credit (的 了 吗 …, 嗯 啊 那个 when it's a filler).
    private static let functionTokens: Set<String> = [
        "的", "了", "着", "过", "地", "得", "吗", "吧", "呢", "啊", "呀", "嘛",
        "哦", "嗯", "哈", "啦", "喔", "噢", "诶", "欸", "呃", "额", "哎",
    ]

    static func isFunctionToken(_ s: String) -> Bool { functionTokens.contains(simplified(s)) }

    // MARK: - Sound

    /// What the line SOUNDS like: pinyin with tones, joined, lowercased.
    /// Whatever script the transcriber wrote (說 / 说), however it cut the
    /// words, and whichever of two homophones it picked (在 / 再, both zài),
    /// the same sentence reads the same — none of those is the learner's.
    /// Tones are KEPT: 买 mǎi and 卖 mài are different words a mouth makes.
    static func reading(of text: String) -> String {
        words(in: text).map(\.pinyin).joined().lowercased()
    }

    /// How a headword is read, for display beside it — the HSK list's pinyin
    /// (both readings for a word that has two: 还 hái・huán), the system
    /// tokenizer's for a word off the list.
    static func reading(ofHeadword word: String) -> String? {
        let key = simplified(word)
        guard key.unicodeScalars.contains(where: isHan) else { return nil }
        if let listed = bundledReadings[key] { return listed }
        let guess = words(in: key).map(\.pinyin).joined()
        return guess.isEmpty || guess == key ? nil : guess
    }

    /// The list's pinyin for a headword as written there (two readings
    /// joined by ・), nil off the list. For `ChinesePinyin`.
    static func listedReading(_ key: String) -> String? { bundledReadings[key] }

    // MARK: - Bundled data

    /// headword → pinyin, the third column of `cefr_words_zh.tsv`.
    private static let bundledReadings: [String: String] = {
        guard let url = Bundle.main.url(forResource: "cefr_words_zh", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 3 { out[String(parts[0])] = String(parts[2]) }
        }
        return out
    }()

    /// Other spelling → headword (一点 → 一点儿), from `zh_forms.tsv`.
    static let bundledForms: [String: String] = {
        guard let url = Bundle.main.url(forResource: "zh_forms", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }()

    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }
}
