import NaturalLanguage
import XCTest
@testable import FutureVoice

/// The vocabulary level reads the MEAN LEVEL of the content words said, not
/// a count of advanced words. Reported 2026-10-29: a few C2 words made the
/// level C2, and the old count rose with the amount of talk alone (NICT JLE:
/// six ≈A2 interviews pooled read B2). These pin the rule and its calibration.
final class VocabSophisticationTests: XCTestCase {

    private let en = VocabSophistication.profiles["en"]!

    /// A read whose mean is `mean` (A1 = 0 … C2 = 5).
    private func read(_ mean: Double, graded: Int = 1000) -> VocabSophistication.Read {
        .init(graded: graded, levelSum: Int((mean * Double(graded)).rounded()), talks: 3)
    }

    private func band(_ mean: Double, graded: Int = 1000, precision: CEFRLevel? = nil)
        -> (level: CEFRLevel, ceiling: VocabSophistication.Ceiling?)? {
        VocabSophistication.level(read(mean, graded: graded), profile: en, precision: precision)
    }

    func testTooLittleSpeechReadsNoLevel() {
        XCTAssertNil(band(0.5, graded: 299, precision: .c2))
    }

    /// NICT JLE medians, one interview: SST 3 ≈0.23, SST 4–5 ≈0.27–0.29,
    /// SST 6–9 ≈0.32–0.34, natives 0.38.
    func testBandsFollowTheCalibration() {
        XCTAssertEqual(band(0.23)?.level, .a1)
        XCTAssertEqual(band(0.28)?.level, .a2)
        XCTAssertEqual(band(0.33)?.level, .b1)
        XCTAssertEqual(band(0.38)?.level, .b2)
        XCTAssertNil(band(0.28)?.ceiling)
    }

    /// Above B1 the words alone don't separate levels: without a precision
    /// read the band says so instead of guessing.
    func testAboveB1WithoutPrecisionSaysSo() {
        XCTAssertEqual(band(0.33)?.ceiling, .needsPrecision)
        XCTAssertEqual(band(0.38)?.ceiling, .needsPrecision)
    }

    /// The precision read decides above B1 — it can raise B1 to B2 …
    func testPrecisionDecidesAboveB1() {
        XCTAssertEqual(band(0.33, precision: .b2)?.level, .b2)
        XCTAssertEqual(band(0.33, precision: .b2)?.ceiling, .precision(.b2))
    }

    /// … but C1/C2 also need a native speaker's range of words.
    func testC1NeedsTheNativeLikeRange() {
        XCTAssertEqual(band(0.33, precision: .c1)?.level, .b2)
        XCTAssertEqual(band(0.38, precision: .c1)?.level, .c1)
        XCTAssertEqual(band(0.38, precision: .c2)?.level, .c2)
    }

    /// Precision never takes a measured B1 below B1, and never touches A1/A2.
    func testPrecisionNeverGoesBelowWhatIsMeasured() {
        XCTAssertEqual(band(0.33, precision: .a2)?.level, .b1)
        XCTAssertEqual(band(0.28, precision: .c2)?.level, .a2)
    }

    private let toy: [String: CEFRLevel] = [
        "buy": .a1, "bread": .a1, "price": .a1, "negotiate": .b2, "fine": .a1,
        "that": .b2, "will": .b2,
    ]

    /// Only content words count: the pool grades `that` and auxiliary
    /// `will` B2, and counting them made half of a native's score the word
    /// `that`.
    func testFunctionWordsDoNotCount() {
        let r = VocabSophistication.read(talksNewestFirst: [["That will be fine."]], profile: en,
                                         level: { self.toy[$0] })
        XCTAssertEqual(r.graded, 1)
        XCTAssertEqual(r.levelSum, 0)
    }

    /// Repeats count (a token mean), and talking more about the same thing
    /// doesn't move it — the property the old count lacked.
    func testMeanIsStableAsTalkGrows() {
        let talk = ["I buy bread.", "I negotiate the price."]
        let once = VocabSophistication.read(talksNewestFirst: [talk], profile: en, level: { self.toy[$0] })
        let tenTimes = VocabSophistication.read(talksNewestFirst: Array(repeating: talk, count: 10),
                                                profile: en, level: { self.toy[$0] })
        XCTAssertEqual(once.graded, 4)
        XCTAssertEqual(once.levelSum, 3)
        XCTAssertEqual(once.mean, tenTimes.mean, accuracy: 0.001)
        XCTAssertEqual(tenTimes.talks, 10)
    }

    /// The window reads the newest talks only, until it has enough.
    func testWindowStopsOnceFull() {
        let talk = Array(repeating: "I buy bread.", count: 400)   // 800 graded
        let r = VocabSophistication.read(talksNewestFirst: Array(repeating: talk, count: 5),
                                         profile: en, level: { self.toy[$0] })
        XCTAssertEqual(r.talks, 2)
        XCTAssertEqual(r.graded, 1600)
    }

    /// German's cuts sit higher (its list grades more words B1) and closer.
    func testGermanHasItsOwnCuts() {
        let de = VocabSophistication.profiles["de"]!
        XCTAssertEqual(VocabSophistication.level(read(0.56), profile: de, precision: nil)?.level, .a2)
        XCTAssertEqual(VocabSophistication.level(read(0.59), profile: de, precision: nil)?.level, .b1)
        XCTAssertTrue(VocabSophistication.isCalibrated("de"))
        XCTAssertTrue(VocabSophistication.isCalibrated("fr"))
        XCTAssertFalse(VocabSophistication.isCalibrated("it"))
    }

    /// Korean, Japanese and Spanish carry the English cuts over through
    /// Tatoeba pairs (`scripts/vocab-calibration/parallel_cuts_more.py`).
    func testKoreanJapaneseSpanishHaveTheirOwnCuts() {
        let cases: [(String, [(Double, CEFRLevel)])] = [
            ("ko", [(0.55, .a1), (0.58, .a2), (0.61, .b1), (0.63, .b2)]),
            ("ja", [(0.85, .a1), (0.88, .a2), (0.91, .b1), (0.94, .b2)]),
            ("es", [(0.29, .a1), (0.31, .a2), (0.34, .b1), (0.37, .b2)]),
        ]
        for (code, bands) in cases {
            let profile = VocabSophistication.profiles[code]!
            XCTAssertTrue(VocabSophistication.isCalibrated(code))
            for (mean, level) in bands {
                XCTAssertEqual(VocabSophistication.level(read(mean), profile: profile, precision: nil)?.level,
                               level, "\(code) \(mean)")
            }
        }
    }

    // MARK: - The readers, against the real bundled pools

    private func contentWords(_ text: String, _ code: String) -> [String] {
        let saved = UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        UserDefaults.standard.set(code, forKey: LanguageCatalog.targetLanguageDefaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: LanguageCatalog.targetLanguageDefaultsKey) }
        return VocabSophistication.contentLemmas(text, profile: VocabSophistication.profiles[code]!,
                                                 tagger: NLTagger(tagSchemes: [.lemma, .lexicalClass]),
                                                 lexicon: CoreVocabulary.set)
    }

    /// Korean: `KoreanMorph` headwords, minus pronouns, light verbs and
    /// postposition verbs (그녀 and 위하다 are B1 on the list).
    func testKoreanCountsContentHeadwords() {
        XCTAssertEqual(contentWords("나는 어제 친구를 만났어요.", "ko"), ["어제", "친구", "만나다"])
        XCTAssertEqual(contentWords("그녀가 나를 위해 노래를 했어요.", "ko"), ["노래"])
    }

    /// Japanese: `JapaneseMorph` headwords, content classes only, and never
    /// a reading match onto another word's kanji (船 is not 舟, 的 not まと).
    func testJapaneseCountsOnlyWordsSaid() {
        XCTAssertEqual(contentWords("私は昨日友達に会いました。", "ja"), ["昨日", "友達", "会う"])
        XCTAssertEqual(contentWords("船に乗りました。", "ja"), ["乗る"])
        XCTAssertEqual(contentWords("理論的には正しい。", "ja"), ["理論", "正しい"])
        XCTAssertEqual(contentWords("彼女は本を読んでしまった。", "ja"), ["本", "読む"])
    }

    /// Spanish: the form table, with a participle after haber read as its
    /// verb (the table grades "comprado" C2 as its own headword).
    func testSpanishReadsThePerfectAsItsVerb() {
        XCTAssertEqual(contentWords("He comprado un libro.", "es"), ["comprar", "libro"])
        XCTAssertEqual(contentWords("Ella ha leído dos cartas.", "es"), ["leer", "carta"])
        XCTAssertEqual(contentWords("El libro comprado es caro.", "es"), ["libro", "comprado", "caro"])
        XCTAssertEqual(VocabSophistication.spanishParticipleVerb("dicho"), "decir")
        XCTAssertEqual(VocabSophistication.spanishParticipleVerb("oído"), "oír")
    }
}
