import XCTest
@testable import FutureVoice

/// Japanese has no spaces and no NLTagger lemma, so every word the app tracks
/// in a Japanese talk goes through `JapaneseMorph`. These pin the two halves
/// of its contract against the REAL bundled pool: an inflected verb or
/// adjective finds its headword, and grammar never becomes a word.
final class JapaneseMorphTests: XCTestCase {

    private static let lexicon: Set<String> = {
        guard let url = Bundle.main.url(forResource: "cefr_words_ja", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).compactMap {
            $0.split(separator: "\t").first.map(String.init)
        })
    }()

    private func heads(_ text: String) -> [String] {
        JapaneseMorph.headwords(in: text, lexicon: Self.lexicon,
                                readings: JapaneseMorph.bundledReadings).map(\.headword)
    }

    func testPoolAndReadingsShip() {
        XCTAssertGreaterThan(Self.lexicon.count, 7000)
        XCTAssertEqual(JapaneseMorph.bundledReadings["わかる"], "分かる")
    }

    func testSegmentsWithoutSpaces() {
        XCTAssertEqual(JapaneseMorph.segments(in: "家事が多くて疲れた。"),
                       ["家事", "が", "多く", "て", "疲れ", "た"])
    }

    func testInflectedFormsReachTheirHeadword() {
        XCTAssertEqual(heads("家事が多くて疲れた。"), ["家事", "多い", "疲れる"])
        XCTAssertEqual(heads("駅まで歩いて行って、電車に乗りました。"),
                       ["駅", "歩く", "行く", "電車", "乗る"])
        XCTAssertEqual(heads("本を読んでいます。"), ["本", "読む"])
        XCTAssertEqual(heads("高かったけど、おいしかった。"), ["高い", "美味しい"])
        XCTAssertEqual(heads("泳いだ後でコーヒーを飲もう。"), ["泳ぐ", "後", "コーヒー", "飲む"])
    }

    /// A stem before inflection is the verb, not the noun it also spells.
    func testStemBeforeInflectionIsTheVerb() {
        XCTAssertEqual(heads("映画を見に行きました。"), ["映画", "見る", "行く"])
        XCTAssertEqual(heads("明日は仕事を休みたいです。"), ["明日", "仕事", "休む"])
        XCTAssertEqual(heads("来週また来ます。"), ["来週", "また", "来る"])
    }

    /// Kana spelling of a kanji headword — how a transcriber often writes it.
    func testKanaSpellingFindsKanjiHeadword() {
        XCTAssertEqual(heads("日本語がわかりません。"), ["日本", "分かる"])
    }

    /// Precision: a kanji noun never grows a verb ending, and grammar never
    /// reads back as a listed word (ない as 無い, ば as 場).
    func testNounsAndGrammarStayPut() {
        XCTAssertFalse(heads("日本語").contains("語る"))
        XCTAssertFalse(heads("箸を使う。").contains("走る"))
        let h = heads("勉強しなければならない。")
        XCTAssertTrue(h.contains("勉強"))
        XCTAssertFalse(h.contains("ない"))
        XCTAssertFalse(h.contains("場"))
    }
}
