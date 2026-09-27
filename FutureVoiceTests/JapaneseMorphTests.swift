import XCTest
@testable import FutureVoice

/// Japanese has no spaces and no NLTagger lemma, so every word the app tracks
/// in a Japanese talk goes through `JapaneseMorph`. These pin the two halves
/// of its contract against the REAL bundled pool: an inflected verb or
/// adjective finds its headword, and grammar never becomes a word.
final class JapaneseMorphTests: XCTestCase {

    /// The pool and the splitter route on the ACTIVE target language.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("ja", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private var lexicon: Set<String> { CoreVocabulary.set }

    private func heads(_ text: String) -> [String] {
        JapaneseMorph.headwords(in: text, lexicon: lexicon,
                                forms: JapaneseMorph.bundledForms).map(\.headword)
    }

    func testPoolAndFormsShip() {
        XCTAssertGreaterThan(lexicon.count, 7000)
        XCTAssertEqual(JapaneseMorph.bundledForms["わかる"], "分かる")
        XCTAssertEqual(JapaneseMorph.bundledForms["判る"], "分かる")
        // Spellings nobody writes never became headwords.
        XCTAssertFalse(lexicon.contains("下さい"))
        XCTAssertTrue(lexicon.contains("ください"))
        XCTAssertEqual(JapaneseMorph.bundledForms["下さい"], "ください")
        XCTAssertTrue(lexicon.contains("ご飯"))
        XCTAssertEqual(JapaneseMorph.bundledForms["朝御飯"], "朝ご飯")
        XCTAssertEqual(JapaneseMorph.bundledForms["丁度"], "ちょうど")
        // …while ordinary kanji stayed kanji.
        XCTAssertTrue(lexicon.contains("行く"))
        XCTAssertTrue(lexicon.contains("犬"))
    }

    func testSegmentsWithoutSpaces() {
        XCTAssertEqual(JapaneseMorph.segments(in: "家事が多くて疲れた。"),
                       ["家事", "が", "多く", "て", "疲れ", "た"])
        XCTAssertEqual(WordSplitter.words("家事が多くて疲れた。").count, 6)
        XCTAssertFalse(WordSplitter.spaced)
    }

    /// Punctuation is never a token, but the view still has to draw it.
    func testDisplayPiecesRoundTrip() {
        let line = "昨日は、友達と「映画」を見に行きました。楽しかった！"
        let pieces = JapaneseMorph.displayPieces(in: line)
        XCTAssertEqual(pieces.map(\.text).joined(), line)
        XCTAssertEqual(pieces.filter(\.isWord).count, JapaneseMorph.segments(in: line).count)
        let keys = JapaneseMorph.pieceKeys(in: line, lexicon: lexicon, forms: JapaneseMorph.bundledForms)
        XCTAssertEqual(keys.count, pieces.count)
        // The key sits on the piece it was said in: 行き (before ました) → 行く.
        let idx = pieces.firstIndex { $0.text == "行き" }!
        XCTAssertEqual(keys[idx], "行く")
        XCTAssertEqual(keys[pieces.firstIndex { $0.text == "。" }!], "")
    }

    func testInflectedFormsReachTheirHeadword() {
        XCTAssertEqual(heads("家事が多くて疲れた。"), ["家事", "多い", "疲れる"])
        XCTAssertEqual(heads("駅まで歩いて行って、電車に乗りました。"),
                       ["駅", "歩く", "行く", "電車", "乗る"])
        XCTAssertEqual(heads("本を読んでいます。"), ["本", "読む"])
        XCTAssertEqual(heads("高かったけど、おいしかった。"), ["高い", "おいしい"])
        XCTAssertEqual(heads("泳いだ後でコーヒーを飲もう。"), ["泳ぐ", "後", "コーヒー", "飲む"])
    }

    /// A stem before inflection is the verb, not the noun it also spells.
    func testStemBeforeInflectionIsTheVerb() {
        XCTAssertEqual(heads("映画を見に行きました。"), ["映画", "見る", "行く"])
        XCTAssertEqual(heads("明日は仕事を休みたいです。"), ["明日", "仕事", "休む"])
        XCTAssertEqual(heads("来週また来ます。"), ["来週", "また", "来る"])
    }

    /// Kana spelling of a kanji headword — how a transcriber often writes it
    /// — and a compound the tokenizer cuts in two.
    func testOtherSpellingsFindTheHeadword() {
        XCTAssertEqual(heads("日本語がわかりません。"), ["日本", "分かる"])
        XCTAssertEqual(heads("ちょっと待って下さい。"), ["ちょっと", "待つ", "ください"])
        XCTAssertTrue(heads("面倒くさいなあ。").contains("面倒くさい"))
    }

    /// Precision: a kanji noun never grows a verb ending, and grammar never
    /// reads back as a listed word (ない as 無い, ば as 場).
    func testNounsAndGrammarStayPut() {
        XCTAssertFalse(heads("日本語").contains("語る"))
        XCTAssertFalse(heads("箸を使う。").contains("走る"))
        // Spoken contractions are grammar: てる is ている, never 照る (seen on
        // the first Japanese screenshot), and the passive れ is nothing.
        XCTAssertEqual(heads("家事に追われてる。"), ["家事", "追う"])
        // The deck's older okurigana never reaches the learner.
        XCTAssertEqual(heads("少しは落ち着いた？"), ["少し", "落ち着く"])
        XCTAssertFalse(lexicon.contains("落着く"))
        let h = heads("勉強しなければならない。")
        XCTAssertTrue(h.contains("勉強"))
        XCTAssertFalse(h.contains("ない"))
        XCTAssertFalse(h.contains("場"))
    }

    // MARK: - Through the stores

    func testVocabStoreLemmasAndLookupKeyRouteToJapanese() {
        XCTAssertEqual(VocabStore.lemmas(in: ["家事が多くて疲れた。"]), ["家事", "多い", "疲れる"])
        XCTAssertEqual(VocabStore.lookupKey(for: "疲れた"), "疲れる")
        XCTAssertEqual(VocabStore.lookupKey(for: "わかる"), "分かる")
        XCTAssertEqual(CoreVocabulary.level(ofSurface: "行きました"), .a1)
        XCTAssertEqual(CoreVocabulary.level(ofSurface: "家事"), .b1)
    }

    /// The phrase matcher needs tokens, and Japanese has to be cut first.
    func testCarryoverMatchesAJapanesePhrase() {
        let start = Date()
        func turn(_ t: String) -> Turn {
            Turn(id: UUID(), role: .user, audioURL: nil, transcript: t,
                 durationMs: 1000, timestamp: start, suggestion: nil)
        }
        XCTAssertTrue(CarryoverDetector.isCreditable("気をつけて"))
        XCTAssertTrue(CarryoverDetector.isCreditable("なるほど"))
        XCTAssertNotNil(CarryoverDetector.firstMatch(of: "気をつけて",
                                                     in: [turn("じゃあ、気をつけてね。")]))
        XCTAssertNil(CarryoverDetector.firstMatch(of: "気をつけて",
                                                  in: [turn("気分がいいです。")]))
        XCTAssertNotNil(CarryoverDetector.firstLemmaMatch(of: "疲れる",
                                                          in: [turn("今日はとても疲れました。")]))
    }

    /// A rewrite that only re-spells what was said is the transcriber's
    /// choice, not a mistake — the Japanese twin of "I am" → "I'm".
    func testScriptOnlyRewriteIsNotACorrection() {
        XCTAssertTrue(ConversationEngine.saysTheSameThing("よく分かった。", "よくわかった！"))
        XCTAssertTrue(ConversationEngine.saysTheSameThing("待って下さい", "待ってください"))
        XCTAssertFalse(ConversationEngine.saysTheSameThing("面倒くさいでした", "面倒くさかった"))
        XCTAssertFalse(ConversationEngine.saysTheSameThing("掃除をするつもりです", "掃除するつもり"))
    }

    /// The correction paints the characters that changed, not the segments
    /// around them — くさ[かっ]た.
    func testCorrectionHighlightsChangedCharacters() {
        let attributed = highlightedCorrection("とても面倒くさかった。",
                                               original: "とても面倒くさいでした。",
                                               baseFont: .body)
        let painted = attributed.runs
            .filter { $0.foregroundColor != nil }
            .map { String(attributed[$0.range].characters) }
            .joined()
        XCTAssertEqual(painted, "かっ")
        XCTAssertEqual(String(attributed.characters), "とても面倒くさかった。")
    }

    /// The card shows how a kanji headword is read — every reading the list
    /// has, common one first — and nothing for a word already in kana.
    func testHeadwordReadings() {
        XCTAssertEqual(JapaneseMorph.reading(ofHeadword: "慌てる"), "あわてる")
        XCTAssertEqual(JapaneseMorph.reading(ofHeadword: "日本"), "にほん・にっぽん")
        XCTAssertEqual(JapaneseMorph.reading(ofHeadword: "辛い"), "からい・つらい")
        XCTAssertNil(JapaneseMorph.reading(ofHeadword: "とりあえず"))
        XCTAssertNil(JapaneseMorph.reading(ofHeadword: "ください"))
        // The pool still reads its three-column file.
        XCTAssertEqual(CoreVocabulary.level(of: "慌てる"), .b1)
    }

    /// Chunks of one turn join as written: no space the learner never said,
    /// and an echoed run of segments is dropped once.
    func testStitchJoinsWithoutSpaces() {
        XCTAssertEqual(ConversationView.stitch("昨日は友達と", "映画を見に行きました。").0,
                       "昨日は友達と映画を見に行きました。")
        let (joined, dropped) = ConversationView.stitch(
            "昨日は友達と映画を見に行きました",
            "友達と映画を見に行きました。すごく楽しかった。")
        XCTAssertEqual(joined, "昨日は友達と映画を見に行きましたすごく楽しかった。")
        XCTAssertGreaterThan(dropped, 0)
    }

    func testPromptsSayWhatAChunkIs() {
        XCTAssertFalse(ConversationEngine.scriptGuard("ja").isEmpty)
        XCTAssertTrue(ConversationEngine.scriptGuard("en").isEmpty)
        XCTAssertTrue(ConversationEngine.unspacedExpressionNote("en").isEmpty)
        XCTAssertTrue(ConversationEngine.unspacedExpressionNote("ja").contains("without spaces"))
        let ja = ConversationEngine.correctionOnlyPrompt(targetLanguage: "ja", nativeLanguage: "ko", level: .b1)
        let en = ConversationEngine.correctionOnlyPrompt(targetLanguage: "en", nativeLanguage: "ko", level: .b1)
        XCTAssertTrue(ja.contains("return null.\n- ASR SCRIPT GUARD"))
        // The guards are spliced whole, each at a line end, in this order:
        // script → register (2026-09-25) → the next rule. Built from the
        // functions so a guard's wording can change without this test.
        XCTAssertTrue(ja.contains(ConversationEngine.scriptGuard("ja")
                                  + ConversationEngine.registerGuard("ja")
                                  + "\n- Judge it as SPEECH"))
        XCTAssertFalse(en.contains("SCRIPT GUARD"))
        // Nothing was added to a spaced language's prompt — not even a blank line.
        XCTAssertTrue(en.contains("make, the line was fine: return null.\n- Judge it as SPEECH"))
    }

    func testTitleSnippetAndSentenceCount() {
        XCTAssertEqual(WordSplitter.snippet("今日は友達と映画を見に行きました", words: 6, characters: 8), "今日は友達と映画…")
        XCTAssertEqual(TalkCurriculum.sentences(in: "はい。行きます！本当？"), ["はい。", "行きます！", "本当？"])
        XCTAssertTrue(WordSplitter.isSingleWord("分かる"))
        XCTAssertFalse(WordSplitter.isSingleWord("気をつけて"))
    }
}
