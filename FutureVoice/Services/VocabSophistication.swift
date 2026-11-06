import Foundation
import NaturalLanguage

/// The vocabulary level, read from WHICH words a learner reaches for rather
/// than how many advanced words they have ever said.
///
/// The count it replaced (C2 at 15 distinct words over 90 days) rose with
/// the amount of talk alone: measured on the NICT JLE corpus (1,277 learners
/// of English in the same 15-minute SST interview at nine levels, plus 20
/// natives doing the same task), six pooled ≈A2 interviews read B2 197 times
/// in 200. Advanced words are rare in conversation for everyone.
///
/// The measure is the MEAN LEVEL (A1 = 0 … C2 = 5) of the graded CONTENT
/// words said (nouns, verbs, adjectives, adverbs), repeats counted. Two
/// things were learned the hard way (2026-10-30):
/// - Function words have to go. A first cut counted every graded token, and
///   the list grades `that` B2 and auxiliary `will` as the noun — so half of
///   a native's "B2+ share" was the word `that`, and the measure was mostly
///   counting relative clauses. Content words only, minus `stopWords`.
/// - Above B1 vocabulary in speech stops separating learners. Medians by
///   SST level, one interview: 3 → 0.23, 4 → 0.27, 5 → 0.29, 6 → 0.33,
///   7–9 → 0.32–0.34, natives 0.38. So the measure reads A1 / A2 / B1 and
///   "native-like range"; B2–C2 come from the weekly assessment's read of
///   word PRECISION (`WeeklyReport.lexicalPrecision`), and C1/C2 also need
///   the native-like range.
///
/// German's cuts were carried over from English through 240k held-out
/// Tatoeba en–de sentence pairs (pooled means correlate 0.88): PROVISIONAL —
/// no German learner speech with levels was available to check them on.
/// Korean, Japanese and Spanish the same way (2026-11-06), each read by the
/// app's own analyzer (`Reader`), all PROVISIONAL and weaker than German:
/// - Spanish (126k pairs, r 0.89): as good as German. Its levels are
///   frequency bands, so this reads how common the words are.
/// - Japanese (112k pairs, r 0.85): noisier. JLPT has no C2 and grades 2,600
///   words N1 (C1), and `JapaneseMorph` still reads some kana as other words.
/// - Korean (5k pairs, r 0.86): the cuts move ±0.01 between halves of the
///   data, so the native-like edge (0.02 above B1) is barely resolved.
/// `scripts/vocab-calibration/` reruns all of it.
enum VocabSophistication {

    struct Profile {
        /// Lower edges of A2, B1 and the native-like range (B2 without a
        /// precision read; the floor for C1/C2 with one).
        let a2: Double, b1: Double, nativeLike: Double
        let reader: Reader
        /// Auxiliaries, modals and homographs the pool grades by a rare
        /// sense (`will` the noun, `found` = establish).
        let stopWords: Set<String>
    }

    /// How a language's words are cut, lemmatized and classed — the same
    /// way `VocabStore` reads that language everywhere else, so the level and
    /// the notebook can't disagree about what a word is.
    enum Reader {
        /// `NLTagger` lemma + lexical class (English, German).
        case tagger(NLLanguage)
        /// `KoreanMorph` headwords; the tagger has no Korean classes and the
        /// list's own classes are only predicate / other, so every headword
        /// counts unless `stopWords` names it.
        case korean
        /// `JapaneseMorph` headwords, classed by `word_classes_ja.tsv`.
        case japanese
        /// `SpanishMorph`'s table (lemma + class); iOS has no Spanish lemma.
        case spanish
    }

    static let profiles: [String: Profile] = [
        "en": Profile(a2: 0.25, b1: 0.31, nativeLike: 0.36, reader: .tagger(.english),
                      stopWords: ["be", "have", "do", "will", "would", "can", "could", "may", "might",
                                  "shall", "should", "must", "ought", "that", "found", "mine", "plus"]),
        "de": Profile(a2: 0.55, b1: 0.58, nativeLike: 0.61, reader: .tagger(.german),
                      stopWords: ["sein", "haben", "werden", "tun", "können", "müssen", "sollen",
                                  "dürfen", "mögen", "wollen", "möchten"]),
        "ko": Profile(a2: 0.56, b1: 0.60, nativeLike: 0.62, reader: .korean,
                      stopWords: [
                        // Light and auxiliary verbs, pro-verbs (be / have / do).
                        "있다", "없다", "하다", "되다", "이다", "아니다", "않다", "싶다",
                        "말다", "못하다", "그러다", "그렇다", "이렇다", "저렇다", "어떻다",
                        // Pronouns, question words, determiners.
                        "나", "내", "너", "네", "저", "제", "우리", "저희", "그", "그녀",
                        "그들", "당신", "자기", "자신", "걔", "얘", "쟤", "누구", "누가",
                        "뭐", "무엇", "뭘", "무슨", "어디", "언제", "왜", "이것", "그것",
                        "저것", "이거", "그거", "저거", "이게", "그게", "아무", "모든", "이",
                        "어느", "어떤", "몇",
                        // Bound nouns (건 and 게 are 것 contracted, read as
                        // 'case' C1 and 'crab' B2), postposition verbs.
                        "것", "거", "건", "게", "수", "줄", "데", "적", "때문", "뿐",
                        "지", "듯", "만큼", "대로", "채", "대하다", "위하다", "통하다",
                        "관하다", "의하다",
                        // Interjections, numerals; 해 is 하다 read as 'sun', 수도 is -ㄹ 수도.
                        "예", "응", "아니", "아니요", "아니야", "어", "아", "음", "하나",
                        "둘", "셋", "넷", "일", "삼", "사", "오", "육", "칠", "팔",
                        "구", "십", "백", "천", "만", "해", "수도"
                      ]),
        "ja": Profile(a2: 0.86, b1: 0.90, nativeLike: 0.93, reader: .japanese,
                      stopWords: [
                        // Light verbs and benefactives, formal nouns.
                        "する", "なる", "いる", "ある", "できる", "やる", "くれる", "もらう",
                        "あげる", "こと", "事", "もの", "物", "よう", "ため", "ところ", "方",
                        "はず", "わけ", "つもり",
                        // Pronouns (nouns in JMdict), question words, determiners, numerals.
                        "私", "僕", "俺", "あなた", "君", "彼", "彼女", "彼ら", "我々",
                        "お前", "自分", "わたし", "あたし", "これ", "それ", "あれ", "どれ",
                        "ここ", "そこ", "あそこ", "どこ", "こちら", "そちら", "あちら", "どちら",
                        "誰", "何", "なに", "いつ", "どう", "どうして", "なぜ", "この",
                        "その", "あの", "どの", "こう", "そう", "ああ", "これら", "それら",
                        "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                        "百", "千", "万", "一つ", "二つ", "三つ",
                        // Grammar and affixes (ほど, に対して, に関する, 様々).
                        "ほど", "大", "対", "関する", "様",
                        // Grammar `JapaneseMorph` reads as a word: てしまう
                        // → 始末, とき → 解く, について → 点く, において → 老いる, すれば →
                        // 擦れる, ほう → 放る, さえ → 冴える, わけ → 分ける, あれば → 荒れる,
                        // しか → 叱る, つもり → 積もる, それ → それる, どこ → どく, やって →
                        // やつ, 的 → まと, 回 → さじ.
                        "始末", "解く", "点く", "老いる", "擦れる", "放る", "冴える", "分ける",
                        "荒れる", "尽きる", "叱る", "積もる", "姉妹", "係わる", "憎い", "何か",
                        "揉む", "毛糸", "まじる", "詰まる", "それる", "どく", "やつ", "まと",
                        "さじ"
                      ]),
        "es": Profile(a2: 0.30, b1: 0.33, nativeLike: 0.36, reader: .spanish,
                      stopWords: [
                        // Auxiliaries and modals (the English list's be / have / do / can / must).
                        "ser", "estar", "haber", "tener", "hacer", "poder",
                        "deber", "soler",
                        // Question adverbs (the tagger calls how / where
                        // / when pronouns), numerals, possessive
                        // pronouns.
                        "como", "donde", "cuando", "uno", "dos", "tres",
                        "cuatro", "cinco", "seis", "siete", "ocho", "nueve",
                        "diez", "cien", "mil", "mío", "mía", "tuyo", "tuya",
                        "suyo", "suya", "nuestro", "nuestra"
                      ]),
    ]

    static func isCalibrated(_ languageCode: String) -> Bool { profiles[languageCode] != nil }

    /// Graded content words needed before a band is read — about an hour of
    /// a learner's own speech (an SST interview carries 200–480).
    static let minGradedTokens = 300
    /// The newest talks are read until this many: three or four interviews'
    /// worth, where one level's spread narrows to ±0.03.
    static let windowGradedTokens = 1200

    struct Read: Equatable {
        /// Graded content words in the window.
        var graded: Int
        /// The sum of their levels (A1 = 0 … C2 = 5).
        var levelSum: Int
        /// Talks the window reached back over.
        var talks: Int
        var mean: Double { graded > 0 ? Double(levelSum) / Double(graded) : 0 }
    }

    enum Ceiling: Equatable {
        /// B1 or the native-like range is measured; above it needs the
        /// assessment's precision read, which isn't there yet.
        case needsPrecision
        /// The precision read set the band.
        case precision(CEFRLevel)
    }

    /// The band, or nil while the sample is too small.
    static func level(_ read: Read, profile: Profile, precision: CEFRLevel?)
        -> (level: CEFRLevel, ceiling: Ceiling?)? {
        guard read.graded >= minGradedTokens else { return nil }
        let m = read.mean
        if m < profile.a2 { return (.a1, nil) }
        if m < profile.b1 { return (.a2, nil) }
        let measured: CEFRLevel = m >= profile.nativeLike ? .b2 : .b1
        guard let precision else { return (measured, .needsPrecision) }
        // Precision decides above B1, never below it (B1 is measured), and
        // C1/C2 also need the range a native speaker's words have.
        var set = rank(precision) < rank(.b1) ? CEFRLevel.b1 : precision
        if rank(set) > rank(.b2), m < profile.nativeLike { set = .b2 }
        return (set, .precision(precision))
    }

    /// Walks talks NEWEST FIRST (`texts` per talk, the learner's own evidence
    /// lines) until `windowGradedTokens`. `lexicon` is the pool the Korean
    /// and Japanese readers confirm headwords against.
    static func read(talksNewestFirst: [[String]], profile: Profile,
                     lexicon: Set<String> = CoreVocabulary.set,
                     level gradeOf: (String) -> CEFRLevel?) -> Read {
        var out = Read(graded: 0, levelSum: 0, talks: 0)
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        for texts in talksNewestFirst {
            guard out.graded < windowGradedTokens else { break }
            let before = out.graded
            for text in texts {
                for lemma in contentLemmas(text, profile: profile, tagger: tagger, lexicon: lexicon) {
                    guard let lv = gradeOf(lemma) else { continue }
                    out.graded += 1
                    out.levelSum += rank(lv)
                }
            }
            if out.graded > before { out.talks += 1 }
        }
        return out
    }

    private static let contentClasses: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
    private static let japaneseContent: Set<WordClass> = [.noun, .verb, .adjective, .naAdjective, .adverb]

    /// Every content word's lemma, in order — repeats counted, because a
    /// token mean is what was calibrated.
    static func contentLemmas(_ text: String, profile: Profile, tagger: NLTagger,
                              lexicon: Set<String> = CoreVocabulary.set) -> [String] {
        let lemmas: [String]
        switch profile.reader {
        case .tagger(let language):
            var found: [String] = []
            tagger.string = text
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                                 options: [.omitPunctuation, .omitWhitespace, .omitOther]) { cls, range in
                guard let cls, contentClasses.contains(cls) else { return true }
                let lemma = (tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
                             ?? String(text[range])).lowercased()
                if lemma.count > 1 { found.append(lemma) }
                return true
            }
            lemmas = found
        case .korean:
            // The tokens `VocabStore.koreanLemmas` reads, in order. A
            // one-syllable headword is a word here (집, 눈, 말).
            lemmas = text.components(separatedBy: CharacterSet.alphanumerics.inverted).compactMap {
                $0.isEmpty ? nil : KoreanMorph.dictionaryForm(of: $0, in: lexicon, rank: CoreVocabulary.koreanRank)
            }
        case .japanese:
            // Pronouns are nouns in JMdict, so `stopWords` names them. A hit
            // whose said kanji aren't in the headword is a reading match onto
            // another word (船 → 舟, 曲 → 局, 回 → さじ, 的 → まと), not a word
            // the learner said, and it is never counted.
            lemmas = JapaneseMorph.headwords(in: text, lexicon: lexicon, forms: JapaneseMorph.bundledForms)
                .filter { hit in
                    let head = Set(hit.headword.unicodeScalars)
                    return text[hit.range].unicodeScalars.allSatisfy { !isKanji($0) || head.contains($0) }
                        && !WordClass.classes(of: hit.headword, language: "ja").isDisjoint(with: japaneseContent)
                }
                .map(\.headword)
        case .spanish:
            // The table holds content words only (noun/verb/adjective/adverb).
            // One repair: the table keeps a masculine participle as its own
            // adjective headword, graded by ITS frequency (comprado C2,
            // dejado C1, dicho B1), so every perfect tense read as a rare
            // word. After a form of haber it is the verb.
            var found: [String] = []
            var afterHaber = false
            for (word, _) in SpanishMorph.words(in: text) {
                let entry = SpanishMorph.entry(for: word)
                var lemma = entry?.lemma
                if afterHaber, let verb = spanishParticipleVerb(word.lowercased()) { lemma = verb }
                afterHaber = entry?.lemma == "haber"
                if let lemma, lemma.count > 1 { found.append(lemma) }
            }
            lemmas = found
        }
        return lemmas.filter { !profile.stopWords.contains($0) }
    }

    private static let spanishIrregularParticiples: [String: String] = [
        "dicho": "decir", "hecho": "hacer", "puesto": "poner", "visto": "ver", "escrito": "escribir",
        "vuelto": "volver", "devuelto": "devolver", "resuelto": "resolver", "abierto": "abrir",
        "cubierto": "cubrir", "descubierto": "descubrir", "muerto": "morir", "roto": "romper",
        "supuesto": "suponer", "propuesto": "proponer", "compuesto": "componer", "impuesto": "imponer",
        "satisfecho": "satisfacer", "deshecho": "deshacer", "frito": "freír", "impreso": "imprimir",
    ]

    /// The infinitive a participle after haber belongs to, when the table
    /// knows that infinitive as a verb (comprado → comprar, leído → leer).
    static func spanishParticipleVerb(_ form: String) -> String? {
        if let v = spanishIrregularParticiples[form] { return v }
        func isVerb(_ w: String) -> Bool { SpanishMorph.entry(for: w)?.wordClass == "verb" }
        let stem: String, endings: [String]
        if form.hasSuffix("ado") { stem = String(form.dropLast(3)); endings = ["ar"] }
        else if form.hasSuffix("ído") { stem = String(form.dropLast(3)); endings = ["er", "ír"] }
        else if form.hasSuffix("ido") { stem = String(form.dropLast(3)); endings = ["er", "ir"] }
        else { return nil }
        guard !stem.isEmpty else { return nil }
        return endings.map { stem + $0 }.first(where: isVerb)
    }

    private static func isKanji(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) || s == "々"
    }

    private static func rank(_ l: CEFRLevel) -> Int { CoreVocabulary.levelRank(l) }
}
