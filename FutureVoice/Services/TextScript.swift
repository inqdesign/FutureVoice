import Foundation

/// Whether a line is written in a language's script. One question, asked by
/// everything that turns a learner's material into something to study: a
/// talk where the learner slipped into their own language still produces
/// transcripts and correction cards, and a card or test item built on one of
/// those asks nonsense ("한번 나올게 해줘 시계" → "Show me the clock once",
/// seen on device 2026-09-23).
enum TextScript {
    static func isInTargetScript(_ text: String, language: String) -> Bool {
        if LanguageCatalog.writesSpaces(language) {
            // Word by word: a word is in the script when most of its letters
            // are, and the line when three words in four are. That keeps a
            // name in Latin letters inside a Korean line ("nawana 앱을 만들고
            // 있어요") and still refuses a half-and-half line.
            let words = text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
            guard !words.isEmpty else { return false }
            let native = words.filter { word in
                let letters = word.unicodeScalars.filter { $0.properties.isAlphabetic }
                let hits = letters.filter { matches($0, language: language) }.count
                return hits * 2 > letters.count
            }.count
            return Double(native) / Double(words.count) >= 0.75
        }
        // No spaces to cut on: letter by letter, and a romaji name is a few
        // letters against a line of kana, so a plain majority is the bar.
        var letters = 0, matching = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if matches(scalar, language: language) { matching += 1 }
        }
        guard letters > 0 else { return false }
        return Double(matching) / Double(letters) > 0.5
    }

    private static func matches(_ scalar: Unicode.Scalar, language: String) -> Bool {
        let v = scalar.value
        let hangul = (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
        let kana = (0x3040...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v)
        let han = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x20000...0x2A6DF).contains(v)
        let latin = v < 0x0250 || (0x1E00...0x1EFF).contains(v)
        switch LanguageCatalog.base(language) {
        case "ko": return hangul
        case "ja": return kana || han
        case "zh": return han
        default: return latin
        }
    }
}
