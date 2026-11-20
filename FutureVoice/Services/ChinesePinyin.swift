import Foundation

/// Pinyin over each character of a Chinese line, for drawing above it
/// (`FuriganaText`, through `Furigana.runs`). A learner who can't read 银行
/// can't say the line, and every surface that hands them a Chinese line is
/// asking them to say it (2026-11-20, learner feedback).
///
/// The word's reading comes from the HSK list when the list has the word
/// (the tokenizer reads 钱 as a toneless "qian" and 这个 as "zhègè"), else
/// from the system tokenizer, which reads by WORD and so gets most
/// polyphones right (银行 yínháng). It is then cut into one syllable per
/// character, guided by each character read on its own. 一 and 不 take the
/// tone they are SAID with (bú qù, yí gè), as textbooks print them. A wrong
/// reading is a display slip, never a grade.
enum ChinesePinyin {

    /// Runs over `text`, Character offsets, one per Han character with its
    /// syllable; everything else plain.
    static func runs(in text: String) -> [Furigana.Run] {
        let chars = Array(text)
        var readings = [String?](repeating: nil, count: chars.count)
        let tokens = ChineseMorph.words(in: text)
        for (t, token) in tokens.enumerated() {
            let start = text.distance(from: text.startIndex, to: token.range.lowerBound)
            let surface = Array(token.surface)
            guard surface.contains(where: isHan) else { continue }
            let next = t + 1 < tokens.count ? tokens[t + 1].key : nil
            let word = reading(of: token, next: next)
            if let parts = split(word, over: surface) {
                for (i, part) in parts.enumerated() where isHan(surface[i]) {
                    readings[start + i] = part
                }
            } else if surface.allSatisfy(isHan) {
                // Couldn't cut it: the whole reading over the first character
                // would misplace it, so each character is read on its own.
                for (i, ch) in surface.enumerated() { readings[start + i] = solo(ch) }
            }
        }
        applySandhi(chars, &readings)
        return chars.indices.map { Furigana.Run(range: $0..<($0 + 1), reading: readings[$0]) }
            .reduce(into: [Furigana.Run]()) { out, run in
                // Merge neighbouring plain characters so a Latin word stays one unit.
                if run.reading == nil, let last = out.last, last.reading == nil {
                    out[out.count - 1] = Furigana.Run(range: last.range.lowerBound..<run.range.upperBound, reading: nil)
                } else {
                    out.append(run)
                }
            }
    }

    static func hasHan(_ text: String) -> Bool { text.contains(where: isHan) }

    // MARK: - The word's reading

    /// Words the tokenizer and the list both read wrong in everyday talk.
    private static let fixed: [String: String] = [
        "这个": "zhège", "那个": "nàge", "哪个": "nǎge", "什么": "shénme",
        "怎么": "zěnme", "东西": "dōngxi", "地方": "dìfang", "知道": "zhīdao",
        "谢谢": "xièxie", "朋友": "péngyou", "时候": "shíhou", "喜欢": "xǐhuan",
        "一点儿": "yīdiǎnr", "女儿": "nǚ'ér",
    ]

    private static func reading(of token: ChineseMorph.Token, next: String?) -> String {
        let key = token.key
        if key == "还" {
            // 还 is hái (still, also) unless something is being given back.
            let back: Set<String> = ["钱", "书", "给", "款", "债", "回", "清"]
            return back.contains(where: { next?.hasPrefix($0) == true }) ? "huán" : "hái"
        }
        if let f = fixed[key] { return f }
        if let listed = ChineseMorph.listedReading(key) {
            let alts = listed.split(separator: "・").map(String.init)
            let tok = token.pinyin.lowercased()
            return alts.first(where: { $0.lowercased() == tok }) ?? alts[0]
        }
        return erhua(key, token.pinyin)
    }

    /// 儿 closing a word off the list is the r on the syllable before it
    /// (点儿 diǎnr); the tokenizer writes it as a syllable of its own.
    /// Listed words keep the list's reading (女儿 nǚ'ér).
    static func erhua(_ key: String, _ pinyin: String) -> String {
        guard key.count > 1, key.hasSuffix("儿") else { return pinyin }
        for tail in ["ér", "er"] where pinyin.hasSuffix(tail) {
            return String(pinyin.dropLast(tail.count)) + "r"
        }
        return pinyin
    }

    // MARK: - One syllable per character

    /// `word` cut into one piece per character of `surface`. Each character
    /// read on its own says how long its piece probably is; the cut that
    /// agrees with the most of them wins. nil when no cut fits.
    static func split(_ word: String, over surface: [Character]) -> [String]? {
        let w = word.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " ", with: "")
        let letters = Array(w)
        let n = surface.count
        if n == 1 { return [w] }
        // 儿 after a syllable is the r on the end of it.
        if surface.last == "儿", n > 1, w.hasSuffix("r"), !bare(String(letters.suffix(2))).hasSuffix("er") {
            guard let head = split(String(letters.dropLast()), over: Array(surface.dropLast())) else { return nil }
            return head + ["r"]
        }
        let hints = surface.map { bare(solo($0) ?? "") }
        var best: (score: Int, parts: [String])? = nil
        func walk(_ i: Int, _ at: Int, _ parts: [String], _ score: Int) {
            if i == n {
                if at == letters.count, best == nil || score > best!.score { best = (score, parts) }
                return
            }
            let left = n - i - 1
            guard at < letters.count else { return }
            for len in 1...min(6, letters.count - at) {
                let rest = letters.count - at - len
                if rest < left || (left == 0 && rest != 0) { continue }
                let piece = String(letters[at..<(at + len)])
                guard isSyllableShape(piece) else { continue }
                var s = score
                if bare(piece) == hints[i] { s += 10 }
                if marks(piece) > 1 { continue }
                walk(i + 1, at + len, parts + [piece], s)
            }
        }
        walk(0, 0, [], 0)
        return best?.parts
    }

    /// A piece that could be one syllable: at least one vowel, and not a
    /// lone consonant cluster.
    private static func isSyllableShape(_ s: String) -> Bool {
        let b = bare(s)
        guard b.contains(where: { "aeiouv".contains($0) }) || b == "m" || b == "n" || b == "ng" else { return false }
        return true
    }

    // MARK: - Tone change

    /// 不 is bú before a fourth tone; 一 is yí before a fourth, yì before the
    /// others, and stays yī counted or at the end (第一, 十一, 一月).
    private static func applySandhi(_ chars: [Character], _ r: inout [String?]) {
        for i in chars.indices {
            guard chars[i] == "不" || chars[i] == "一" else { continue }
            let nextTone = i + 1 < chars.count ? r[i + 1].map(tone) : nil
            if chars[i] == "不" {
                guard let t = nextTone else { r[i] = "bù"; continue }
                r[i] = t == 4 ? "bú" : "bù"
            } else {
                let prev = i > 0 ? chars[i - 1] : nil
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                let counted = "第十百千万零〇一二三四五六七八九两".contains(prev ?? " ")
                    || "月号十百千万一二三四五六七八九两".contains(next ?? " ")
                    || next?.isNumber == true
                guard let t = nextTone, !counted else { r[i] = "yī"; continue }
                r[i] = t == 4 || t == 5 ? "yí" : "yì"
                // 一个 reads yí ge: 个 is said light but was fourth.
                if next == "个" { r[i] = "yí" }
            }
        }
    }

    static func tone(_ syllable: String) -> Int {
        for ch in syllable {
            if "āēīōūǖ".contains(ch) { return 1 }
            if "áéíóúǘ".contains(ch) { return 2 }
            if "ǎěǐǒǔǚ".contains(ch) { return 3 }
            if "àèìòùǜ".contains(ch) { return 4 }
        }
        return 5
    }

    private static func marks(_ s: String) -> Int {
        s.filter { "āēīōūǖáéíóúǘǎěǐǒǔǚàèìòùǜ".contains($0) }.count
    }

    /// Without tone marks, ü as v, lowercased.
    static func bare(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ü", with: "v")
            .applyingTransform(.stripDiacritics, reverse: false)?
            .replacingOccurrences(of: "ü", with: "v") ?? s
    }

    // MARK: - A character on its own

    nonisolated(unsafe) private static var soloMemo: [Character: String] = [:]
    private static let lock = NSLock()

    static func solo(_ ch: Character) -> String? {
        lock.lock(); if let hit = soloMemo[ch] { lock.unlock(); return hit }; lock.unlock()
        let s = String(ch)
        let out = s.applyingTransform(.mandarinToLatin, reverse: false)
        guard let out, out != s else { return nil }
        lock.lock(); soloMemo[ch] = out; lock.unlock()
        return out
    }

    static func isHan(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
}
