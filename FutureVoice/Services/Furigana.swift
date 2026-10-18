import Foundation

/// Readings over the kanji of a Japanese line (振り仮名), for drawing above
/// it (`FuriganaText`). A learner who can't read 駅 can't say the line out
/// loud, and every surface that hands them a Japanese line is asking them
/// to say it (2026-10-17, learner feedback).
///
/// The readings are the system tokenizer's (`JapaneseMorph.words`), cut so
/// only the kanji carry one: 食べた reads た over 食, nothing over べた.
/// They are a machine's reading and can be wrong — 何 before で is なん, a
/// split compound reads per piece — so the few common misses are fixed by
/// hand below. Nothing here is a grade: a wrong reading is a display slip.
enum Furigana {

    static let key = "futurevoice.furigana"

    /// On for a Japanese target unless the learner turned it off.
    static func isOn(defaults: UserDefaults = .standard) -> Bool {
        LanguageScope.active == "ja" && (defaults.object(forKey: key) as? Bool ?? true)
    }

    /// A stretch of the line: `reading` set only over kanji. The runs cover
    /// the text end to end, in order. Offsets are Character offsets.
    struct Run: Equatable {
        let range: Range<Int>
        let reading: String?
    }

    /// `text` cut into runs. Memoized: the call screen re-renders every
    /// line on each mic tick.
    static func runs(in text: String) -> [Run] {
        lock.lock()
        if let hit = memo[text] { lock.unlock(); return hit }
        lock.unlock()
        let out = compute(text)
        lock.lock()
        if memo.count > 400 { memo.removeAll(keepingCapacity: true) }
        memo[text] = out
        lock.unlock()
        return out
    }

    static func hasRuby(_ text: String) -> Bool {
        runs(in: text).contains { $0.reading != nil }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var memo: [String: [Run]] = [:]

    private static func compute(_ text: String) -> [Run] {
        guard text.contains(where: isKanji) else {
            return text.isEmpty ? [] : [Run(range: 0..<text.count, reading: nil)]
        }
        let tokens = JapaneseMorph.words(in: text)
        var out: [Run] = []
        var cursor = 0
        func plain(to end: Int) {
            if end > cursor { out.append(Run(range: cursor..<end, reading: nil)); cursor = end }
        }
        var i = 0
        while i < tokens.count {
            // A compound the tokenizer cuts in pieces, read as one.
            var surface = tokens[i].surface
            var reading = tokens[i].reading
            var last = i
            for (joined, fixed) in compoundReadings {
                var s = ""
                var j = i
                while j < tokens.count, s.count < joined.count { s += tokens[j].surface; j += 1 }
                if s == joined, j - i > 1 {
                    surface = s; reading = fixed; last = j - 1; break
                }
            }
            if let fixed = wordReadings[surface] { reading = fixed }
            if surface == "何", i + 1 < tokens.count,
               let next = tokens[i + 1].surface.first, "をがもかにへと".contains(next) {
                reading = "なに"
            }
            let start = text.distance(from: text.startIndex, to: tokens[i].range.lowerBound)
            plain(to: start)
            for part in split(surface, reading: reading) {
                let n = part.base.count
                out.append(Run(range: cursor..<(cursor + n), reading: part.reading))
                cursor += n
            }
            i = last + 1
        }
        plain(to: text.count)
        return out
    }

    /// Readings the tokenizer gets wrong in everyday talk.
    private static let wordReadings: [String: String] = [
        "明日": "あした", "今日": "きょう", "昨日": "きのう", "一人": "ひとり",
        "二人": "ふたり", "大人": "おとな", "上手": "じょうず", "下手": "へた",
    ]

    /// Compounds the tokenizer cuts in two or three (一|日|中).
    private static let compoundReadings: [(String, String)] = [
        ("一日中", "いちにちじゅう"), ("今日中", "きょうじゅう"), ("世界中", "せかいじゅう"),
    ]

    // MARK: - Okurigana

    /// `surface` with its reading laid over the kanji only: 食べ/たべ →
    /// [食:た][べ], 晩ご飯/ばんごはん → [晩:ばん][ご][飯:はん]. A word whose
    /// kana can't be found in the reading keeps the whole reading over the
    /// whole word, which is still right, only less precise.
    static func split(_ surface: String, reading: String) -> [(base: String, reading: String?)] {
        guard surface.contains(where: isKanji) else { return [(surface, nil)] }
        var runs: [(text: String, kanji: Bool)] = []
        for ch in surface {
            let k = isKanji(ch)
            if let lastRun = runs.last, lastRun.kanji == k {
                runs[runs.count - 1].text.append(ch)
            } else {
                runs.append((String(ch), k))
            }
        }
        let read = hiragana(reading)
        if let parts = match(runs[...], read[...]) { return parts }
        return read == hiragana(surface) ? [(surface, nil)] : [(surface, read)]
    }

    private static func match(_ runs: ArraySlice<(text: String, kanji: Bool)>,
                              _ read: Substring) -> [(base: String, reading: String?)]? {
        guard let first = runs.first else { return read.isEmpty ? [] : nil }
        let rest = runs.dropFirst()
        if !first.kanji {
            let kana = hiragana(first.text)
            guard read.hasPrefix(kana) else { return nil }
            return match(rest, read.dropFirst(kana.count)).map { [(first.text, nil)] + $0 }
        }
        if rest.isEmpty { return read.isEmpty ? nil : [(first.text, String(read))] }
        // The kanji take at least one sound each; the kana after them must
        // start right where they end.
        for take in stride(from: 1, through: read.count, by: 1) {
            let tail = read.dropFirst(take)
            if let more = match(rest, tail) {
                return [(first.text, String(read.prefix(take)))] + more
            }
        }
        return nil
    }

    static func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 }
    }

    private static func hiragana(_ s: String) -> String {
        JapaneseMorph.soundSpelling(s)
    }
}
