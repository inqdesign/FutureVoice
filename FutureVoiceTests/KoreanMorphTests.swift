import XCTest
@testable import FutureVoice

/// Every Korean word the app tracks — the book's Words chapter, the chip that
/// ticks when a studied word is said, used-in-a-talk credit, the vocabulary
/// estimate — goes through `KoreanMorph`. Measured 2026-10-04: the first
/// version mapped 24 of 56 common spoken forms; the casual past (했어, 왔어),
/// the irregulars and the noun modifiers all fell through. These pin it
/// against the REAL bundled pool, in both directions: a spoken form finds its
/// headword, and a word that is a word stays itself.
final class KoreanMorphTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("ko", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private func head(_ token: String) -> String? {
        KoreanMorph.dictionaryForm(of: token, in: CoreVocabulary.set, rank: CoreVocabulary.koreanRank)
    }

    /// `expected` may list alternatives with "|" — 들어 is 들다 or 듣다, and
    /// nothing in a single token can say which.
    private func assertHeads(_ cases: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (token, expected) in cases {
            let got = head(token)
            XCTAssertTrue(expected.split(separator: "|").map(String.init).contains(got ?? "∅"),
                          "\(token) → \(got ?? "nil"), expected \(expected)", file: file, line: line)
        }
    }

    func testPoolShips() {
        XCTAssertGreaterThan(CoreVocabulary.set.count, 5000)
    }

    /// The fluent self talks in 반말, so this is the most common verb shape
    /// in a call — and the one the first version never matched.
    func testCasualPast() {
        assertHeads([("했어", "하다"), ("왔어", "오다"), ("됐어", "되다"), ("줬어", "주다"),
                     ("봤는데", "보다"), ("놀았어", "놀다"), ("공부했어", "공부하다"),
                     ("기다렸어", "기다리다"), ("이야기했어", "이야기하다"), ("없었어", "없다"),
                     ("재밌었어", "재미있다"), ("힘들었어", "힘들다"), ("만났어요", "만나다"),
                     ("배웠어요", "배우다"), ("먹었어요", "먹다"), ("갔어요", "가다")])
    }

    func testPresentAndContracted() {
        assertHeads([("마셔요", "마시다"), ("가르쳐", "가르치다"), ("봐", "보다"), ("봐요", "보다"),
                     ("줘", "주다"), ("돼", "되다"), ("와요", "오다"), ("피곤해", "피곤하다"),
                     ("좋아해", "좋아하다"), ("괜찮아", "괜찮다"), ("같아", "같다"), ("있어", "있다"),
                     ("없어요", "없다"), ("싶어요", "싶다"), ("가요", "가다"), ("간다", "가다"),
                     ("먹는다", "먹다"), ("갑니다", "가다")])
    }

    func testIrregulars() {
        assertHeads([
            // ㅡ
            ("바빠요", "바쁘다"), ("써요", "쓰다"), ("예뻐요", "예쁘다"), ("배고파", "배고프다"),
            ("아파", "아프다"), ("커", "크다"),
            // 르
            ("몰라요", "모르다"), ("빨라", "빠르다"), ("달라", "다르다"), ("불렀어", "부르다"),
            // ㄷ
            ("들어요", "들다|듣다"), ("들었어", "듣다|들다"),
            // ㅂ
            ("추워요", "춥다"), ("더워", "덥다"), ("가까워", "가깝다"), ("고마워", "고맙다"),
            ("어려워", "어렵다"), ("도와요", "돕다"),
            // ㅎ
            ("어때요", "어떻다"), ("어땠어", "어떻다"), ("하얀", "하얗다"),
            // ㄹ dropped
            ("사는", "사다|살다"), ("압니다", "알다"), ("만드는", "만들다"), ("아세요", "알다")
        ])
    }

    func testModifiersAndConnectives() {
        assertHeads([("좋은", "좋다"), ("먹는", "먹다"), ("갈", "가다"), ("먹을", "먹다"),
                     ("자는", "자다"), ("가고", "가다"), ("먹으면", "먹다"), ("가려고", "가다"),
                     ("가세요", "가다"), ("보세요", "보다"), ("하셨어", "하다"), ("먹을게요", "먹다"),
                     ("할게", "하다"), ("갈래", "가다"), ("가자", "가다"), ("모르겠어", "모르다"),
                     ("알", "알다"), ("알아", "알다")])
    }

    func testNounsAndCopula() {
        assertHeads([("학교에서", "학교"), ("학생이에요", "학생"), ("친구예요", "친구"),
                     ("사람들이", "사람"), ("주말에는", "주말"), ("시간이", "시간"),
                     ("커피를", "커피"), ("선생님이", "선생님"), ("나는", "나"), ("저는", "저"),
                     ("공부하고", "공부하다"), ("대화하고", "대화하다")])
    }

    /// The precision half: a token that is itself a word is not re-read as a
    /// shorter noun + particle, a one-syllable word is not an ㅎ-adjective,
    /// a bound noun is not a verb + ㄹ.
    func testWordsStayThemselves() {
        assertHeads([("내", "내"), ("가지", "가지"), ("하나", "하나"), ("거의", "거의"),
                     ("그만", "그만"), ("수도", "수도"), ("속도", "속도"), ("또는", "또는"),
                     ("줄", "줄"), ("수", "수"), ("때", "때"), ("우리", "우리"), ("어제", "어제"),
                     ("같이", "같이"), ("많이", "많이"), ("요즘", "요즘"), ("바다", "바다")])
    }

    func testLemmasReadsAWholeTurn() {
        let lemmas = VocabStore.lemmas(in: ["어제 친구랑 영화 봤는데 진짜 재밌었어. 너는 주말에 뭐 했어?"])
        for word in ["어제", "친구", "영화", "보다", "진짜", "재미있다", "주말", "하다"] {
            XCTAssertTrue(lemmas.contains(word), "missing \(word) in \(lemmas.sorted())")
        }
    }
}
