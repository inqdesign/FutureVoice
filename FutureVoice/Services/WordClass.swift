import Foundation
import NaturalLanguage

/// The coarse part of speech of ONE headword, per target language, for
/// grouping words that look like the same kind of thing.
///
/// Its one consumer is the weekly test's meaning item: a verb's gloss must
/// not be answerable by ruling out three nouns, and in Korean a predicate's
/// 다 gives the answer away against nouns before the gloss is even read.
///
/// **The class comes from a TABLE first** (`word_classes_<code>.tsv`, built
/// by `scripts/build-word-classes.py` from the sources the wordlists came
/// from — the CEFR-J/Octanove profiles for English, JMdict for Japanese,
/// orthography plus a hand list for German and Korean). Audited 2026-09-24
/// over all four wordlists before this existed: `NLTagger` on a lone word
/// agreed with the English profiles 72% of the time, had no model at all
/// for Korean and Japanese, and filed German adjectives as adverbs and
/// German verbs as adjectives; the い-shape rule for Japanese was 77% right
/// (違い, 願い are nouns). A headword can carry several classes (run:
/// noun,verb), so the question the engine asks is `sameClass`, never
/// equality.
///
/// **Rules are the fallback** for a word that is not on the list — a
/// notebook word off the graded list, a language without one:
///   - Spaced languages (en, de, es, fr, it, pt) ask `NLTagger` where it has
///     a lexical-class model (`availableTagSchemes`, never assumed), keeping
///     only the four content classes; German first reads its orthography
///     (capital = noun, -en = verb), which is exact for a headword.
///   - Korean and Japanese read the headword's SHAPE: 다 is a predicate; an
///     う-row kana is a verb, い an i-adjective, katakana a loanword.
///
/// Empty means the class is unknown and the word may sit beside anything.
enum WordClass: String, Hashable, CaseIterable {
    case noun, verb, adjective, adverb
    /// Japanese な-adjective (静か): its own shape, neither noun nor い.
    case naAdjective = "na-adjective"
    /// Korean 다-form: verb or adjective, which the headword alone can't
    /// tell apart (가다 / 예쁘다) — and needn't, since both wear the 다.
    case predicate
    /// Placed by a rule as none of the above: Korean nouns and adverbs,
    /// Japanese expressions and numerals, English function words.
    case other

    // MARK: - API

    /// The classes of `word` as a headword of `language` (a target code; a
    /// script-qualified code is read by its base). Empty = unknown.
    nonisolated static func classes(of word: String, language code: String) -> Set<WordClass> {
        let base = baseCode(code)
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let listed = table(for: base)[trimmed.lowercased()] { return listed }
        return memo.value(for: trimmed, language: NLLanguage(rawValue: base)) {
            switch base {
            case "ko": return korean(trimmed)
            case "ja": return japanese(trimmed)
            case "de": return german(trimmed)
            default: return tagged(trimmed, language: base)
            }
        }
    }

    /// Whether `a` and `b` share a class — or `a`'s class is unknown, in
    /// which case anything is allowed beside it.
    nonisolated static func sameClass(_ a: String, _ b: String, language code: String) -> Bool {
        let ca = classes(of: a, language: code)
        guard !ca.isEmpty else { return true }
        return !ca.isDisjoint(with: classes(of: b, language: code))
    }

    // MARK: - Table

    private static let tableLock = NSLock()
    private static var tables: [String: [String: Set<WordClass>]] = [:]

    /// `word_classes_<code>.tsv`: headword TAB class[,class]; a first line
    /// with no tab is the credit. Keys are lowercased (German nouns stay
    /// cased in the file, the lookup doesn't care).
    nonisolated private static func table(for base: String) -> [String: Set<WordClass>] {
        tableLock.lock(); defer { tableLock.unlock() }
        if let cached = tables[base] { return cached }
        var out: [String: Set<WordClass>] = [:]
        if let url = Bundle.main.url(forResource: "word_classes_\(base)", withExtension: "tsv"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "\t")
                guard parts.count == 2 else { continue }
                let classes = Set(parts[1].split(separator: ",").compactMap { WordClass(rawValue: String($0)) })
                if !classes.isEmpty { out[String(parts[0]).lowercased()] = classes }
            }
        }
        tables[base] = out
        return out
    }

    // MARK: - Tagger

    private static let memo = TextMemo<Set<WordClass>>(cap: 20_000)
    private static let taggerLock = NSLock()
    private static let tagger = NLTagger(tagSchemes: [.lexicalClass])
    private static var supportCache: [String: Bool] = [:]

    nonisolated private static func baseCode(_ code: String) -> String {
        LanguageCatalog.language(code)?.code ?? LanguageCatalog.base(code)
    }

    /// Whether `NLTagger` ships a lexical-class model for `language`. Asked of
    /// the framework, not of a list: the answer moves with the OS.
    nonisolated static func taggerSupports(_ code: String) -> Bool {
        let base = baseCode(code)
        taggerLock.lock(); defer { taggerLock.unlock() }
        if let known = supportCache[base] { return known }
        let ok = NLTagger.availableTagSchemes(for: .word, language: NLLanguage(rawValue: base))
            .contains(.lexicalClass)
        supportCache[base] = ok
        return ok
    }

    /// The raw `NLTag` name for `word` ("Noun", "Verb", …) when the tagger
    /// has a model for `language`, else nil. `OtherWord` — the tagger's own
    /// "don't know" — is nil too, so it is never shown as if it were a part
    /// of speech. (The word card's loading-state subtitle reads this.)
    nonisolated static func lexicalTag(_ word: String, language code: String) -> String? {
        guard taggerSupports(code) else { return nil }
        let base = baseCode(code)
        taggerLock.lock(); defer { taggerLock.unlock() }
        tagger.string = word
        tagger.setLanguage(NLLanguage(rawValue: base), range: word.startIndex..<word.endIndex)
        let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
        return tag == NLTag.otherWord.rawValue ? nil : tag
    }

    /// A lone word is a guess for the tagger — measured on 32 English
    /// headwords, ~80% land right and a word it can't place comes back as
    /// "Interjection" (abandon, chore, awkward) — so only the four content
    /// classes count and anything else is unknown.
    nonisolated private static func tagged(_ word: String, language base: String) -> Set<WordClass> {
        switch lexicalTag(word, language: base) {
        case NLTag.noun.rawValue: return [.noun]
        case NLTag.verb.rawValue: return [.verb]
        case NLTag.adjective.rawValue: return [.adjective]
        case NLTag.adverb.rawValue: return [.adverb]
        default: return []
        }
    }

    // MARK: - Shape rules

    /// German orthography, exact for a headword: a capital is a noun, an
    /// infinitive ends in -en/-eln/-ern (or is tun/sein), and the rest is an
    /// adjective — which is also the adverb, so one class for both. The
    /// table carries the -en adjectives (offen, selten); off the list they
    /// read as verbs, the smaller error.
    nonisolated private static func german(_ word: String) -> Set<WordClass> {
        if word.first?.isUppercase == true { return [.noun] }
        // No verb begins with the negating un- (unbeholfen, ungezwungen);
        // only unter- verbs start that way.
        if word.hasPrefix("un"), !word.hasPrefix("unter") { return [.adjective] }
        if word.hasSuffix("en") || word.hasSuffix("eln") || word.hasSuffix("ern")
            || word.hasSuffix("tun") || word.hasSuffix("sein") { return [.verb] }
        return [.adjective]
    }

    /// A dictionary form in 다 is a predicate; everything else (nouns,
    /// adverbs) is not. The table knows the odd 바다; off the list a
    /// 다-noun reads as a predicate.
    nonisolated private static func korean(_ word: String) -> Set<WordClass> {
        let scalars = Array(word.unicodeScalars)
        guard scalars.count >= 2, scalars.last == "\u{B2E4}" else { return [.other] }  // 다
        return [.predicate]
    }

    /// Verbs end on an う-row kana, i-adjectives on い; a katakana word is a
    /// loanword and therefore a noun. Audited against JMdict over the JLPT
    /// list: the misses are polite set phrases (お願いします, お待ちください), numerals and
    /// kana nouns in つ (一つ, おやつ), reduplicated adverbs (ますます) and a
    /// kana-only う after an お-row kana, which is a long vowel (どう,
    /// ありがとう) — each excluded here — and deverbal nouns in い (違い),
    /// which only the table can tell from 高い.
    nonisolated private static func japanese(_ word: String) -> Set<WordClass> {
        let scalars = Array(word.unicodeScalars)
        guard let last = scalars.last else { return [] }
        if scalars.allSatisfy({ isKatakana($0) || $0 == "\u{30FC}" }) { return [.noun] }
        guard scalars.count >= 2 else { return [.other] }
        // Polite forms are set phrases, never a headword's shape.
        for ending in ["ます", "です", "ください", "なさい", "いらっしゃい"] where word.hasSuffix(ending) {
            return [.other]
        }
        // ますます, ぶつぶつ, ちょくちょく — a doubled kana run is an adverb.
        if scalars.count >= 4, scalars.count % 2 == 0,
           Array(scalars[..<(scalars.count / 2)]) == Array(scalars[(scalars.count / 2)...]) { return [.adverb] }
        let uRow: Set<Unicode.Scalar> = ["う", "く", "ぐ", "す", "つ", "ぬ", "ふ", "ぶ", "む", "る"]
        let before = scalars[scalars.count - 2]
        if uRow.contains(last) {
            let numerals: Set<Unicode.Scalar> = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "幾"]
            if last == "つ", numerals.contains(before) || scalars.allSatisfy(isHiragana) { return [.noun] }
            if last == "う", isHiragana(before) {
                let oRow: Set<Unicode.Scalar> = ["お", "こ", "そ", "と", "の", "ほ", "も", "よ", "ろ", "を",
                                                  "ご", "ぞ", "ど", "ぼ", "ぽ", "ょ"]
                if oRow.contains(before) { return [.other] }
            }
            return [.verb]
        }
        if last == "い" { return [.adjective] }
        return [.other]
    }

    private static func isHiragana(_ s: Unicode.Scalar) -> Bool { (0x3041...0x309F).contains(s.value) }
    private static func isKatakana(_ s: Unicode.Scalar) -> Bool { (0x30A0...0x30FF).contains(s.value) }
}
