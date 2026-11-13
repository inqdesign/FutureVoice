import XCTest
@testable import FutureVoice

/// Simplified Chinese as a TARGET language (2026-11-13). The HSK 3.0 list's
/// headwords are what `ChineseMorph` cuts a learner's speech into; these pin
/// that the two meet, that Traditional text folds onto Simplified, and that
/// a transcriber's choice of characters is never a correction.
final class ChineseTargetTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        UserDefaults.standard.set("zh", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    func testChineseIsSelectableAndUnspaced() {
        XCTAssertTrue(LanguageCatalog.selectableTargets.contains { $0.code == "zh" })
        XCTAssertFalse(WordSplitter.spaced)
        XCTAssertTrue(WordSplitter.isChinese)
        XCTAssertEqual(LanguageCatalog.englishName("zh"), "Simplified Chinese")
        XCTAssertEqual(LanguageCatalog.levelLabel(.b1, target: "zh"), "B1 · HSK 4")
    }

    func testPoolLoadsWithHSKBands() {
        XCTAssertGreaterThan(CoreVocabulary.total, 10_000)
        for level in [CEFRLevel.a1, .a2, .b1, .b2, .c1] {
            XCTAssertGreaterThan(CoreVocabulary.total(at: level), 400, "\(level)")
        }
        XCTAssertEqual(CoreVocabulary.level(of: "吃饭"), .a1)
        XCTAssertEqual(CoreVocabulary.level(of: "老师"), .a1)
        // Particles are grammar, not vocabulary.
        XCTAssertNil(CoreVocabulary.level(of: "的"))
        XCTAssertNil(CoreVocabulary.level(of: "吗"))
    }

    func testSpeechLandsOnHeadwords() {
        let said = [
            "我们今天晚上去吃饭吧，你觉得怎么样？",
            "他是我的老师，教汉语教了三年了。",
            "我最近在准备考试，有点紧张。",
        ]
        let lemmas = VocabStore.lemmas(in: said)
        // 有点 is said, 有点儿 is the list's spelling of it.
        for word in ["今天", "晚上", "吃饭", "觉得", "老师", "汉语",
                     "最近", "准备", "考试", "有点儿", "紧张"] {
            XCTAssertTrue(lemmas.contains(word), "headword \(word) not produced")
        }
        // Content words only: particles and pronouns (我们, 怎么样) are left
        // out of the list on purpose, as in every other language's.
        for word in ["的", "我们", "怎么样"] {
            XCTAssertFalse(lemmas.contains(word), "\(word) should not be a headword")
        }
    }

    func testTraditionalFoldsOntoSimplified() {
        XCTAssertEqual(ChineseMorph.simplified("這個問題我們說過了"), "这个问题我们说过了")
        let words = ChineseMorph.words(in: "這個問題我們說過了。")
        // Cut as words (not one character at a time), shown as written.
        XCTAssertTrue(words.contains { $0.surface == "問題" && $0.key == "问题" })
        XCTAssertTrue(words.contains { $0.surface == "我們" && $0.key == "我们" })
        XCTAssertEqual(VocabStore.lookupKey(for: "問題"), "问题")
        XCTAssertEqual(CoreVocabulary.level(ofSurface: "說話"), CoreVocabulary.level(of: "说话"))
    }

    func testErhuaSpellingFindsTheHeadword() {
        XCTAssertNotNil(CoreVocabulary.level(of: "一点儿"))
        XCTAssertEqual(VocabStore.lookupKey(for: "一点"), "一点儿")
    }

    func testDisplayPiecesGiveTheTextBack() {
        let text = "你好！我叫小明，很高兴认识你。"
        let pieces = WordSplitter.displayPieces(text)
        XCTAssertEqual(pieces.map(\.text).joined(), text)
        XCTAssertEqual(WordSplitter.timingWords(text).joined(), text)
        XCTAssertEqual(WordSplitter.pieceKeys(in: text).count, pieces.count)
    }

    /// The recognizer picks the characters; a rewrite that only changes them
    /// corrects nothing the learner said. A change of tone is a real word.
    func testCharacterChoiceIsNotACorrection() {
        XCTAssertTrue(ConversationEngine.saysTheSameThing("我們說過了", "我们说过了"))
        // The probe's one false accusation (2026-11-13): 的 / 得 are both "de".
        XCTAssertTrue(ConversationEngine.saysTheSameThing("他跑的很快。", "他跑得很快。"))
        XCTAssertFalse(ConversationEngine.saysTheSameThing("我想买书", "我想卖书"))
        XCTAssertFalse(ConversationEngine.scriptGuard("zh").isEmpty)
    }

    func testShadowScoresTraditionalAndDigitsAsTheSameLine() {
        let a = ShadowEngine.analyze(target: "我学了三年汉语。", learner: "我學了3年漢語", language: "zh")
        XCTAssertEqual(a.score, 100)
    }

    func testPresetsSpeakMandarinWithChineseNames() {
        let slot = "NDTYOmYEjbDIVCKB35i3"
        XCTAssertEqual(VoicePreset.speaking(slot, in: "zh"), "6eb8965c-e295-47bd-a9e4-3eeebb3abcff")
        XCTAssertEqual(VoicePreset.by(id: slot).name(in: "zh"), "李静")
    }

    func testPinyinOnTheWordCard() {
        XCTAssertEqual(ChineseMorph.reading(ofHeadword: "老师"), "lǎoshī")
        XCTAssertNil(ChineseMorph.reading(ofHeadword: "HSK"))
    }

    func testExamsAndCourse() {
        XCTAssertEqual(ExamKind.options(for: "zh"), [.hskk, .tsc, .opic])
        XCTAssertFalse(ExamTopics.topics(for: .tsc, language: "zh").isEmpty)
        XCTAssertTrue(PronunciationAssessor.supports("zh"))
        XCTAssertNotNil(SpeechLibrary.builtIn(for: "zh"))
    }
}
