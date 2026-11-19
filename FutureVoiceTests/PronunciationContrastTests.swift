import XCTest
@testable import FutureVoice

/// Judging a sound by comparison (`PronunciationContrast`, 2026-11-19): a
/// native Korean speaker was drilled on "예쁜" at 37, because a score was
/// held to a bar set on English.
final class PronunciationContrastTests: XCTestCase {
    private func word(_ w: String, _ accuracy: Int, error: String = "None") -> PronunciationResult.Word {
        .init(word: w, accuracy: accuracy, error: error, offsetMs: 0, durationMs: 300, phonemes: [])
    }

    private func take(_ words: [PronunciationResult.Word],
                      alternate: [(String, Int)]?) -> PronunciationResult {
        var r = PronunciationResult(score: 60, accuracy: 60, fluency: 60, completeness: 100, prosody: nil,
                                    locale: "ko-KR", recognized: "", words: words)
        if let alternate {
            r.alternates = [.init(reference: alternate.map(\.0).joined(separator: " "),
                                  words: alternate.map { .init(word: $0.0, accuracy: $0.1, error: "None") })]
        }
        return r
    }

    private func verdict(_ r: PronunciationResult) -> PronunciationJudge.Verdict {
        PronunciationJudge.verdict(result: r, line: .init(id: UUID(), text: "", focus: []), said: "",
                                   phonemes: [], language: "ko")
    }

    // MARK: The alternates

    func testTheTenseConsonantIsSwappedForThePlainOne() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "예쁜 카페에서 빵을 샀어요.", topicId: "ko.tense"),
                       ["예븐 카페에서 방을 샀어요.", "예픈 카페에서 팡을 샀어요."])
    }

    func testAfinalConsonantBeforeItLeavesNothingToCompare() {
        // "짝궁" is said "짝꿍" anyway: only the first syllable is swapped.
        XCTAssertEqual(PronunciationContrast.alternates(for: "짝꿍이랑", topicId: "ko.tense"), ["작꿍이랑", "착꿍이랑"])
        // The same across two words: "먹을 때" after ㄹ.
        XCTAssertEqual(PronunciationContrast.alternates(for: "먹을 때", topicId: "ko.tense"), [])
    }

    func testAFinalSsangsiotIsNotTheLessonSound() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "있어요", topicId: "ko.tense"), [])
    }

    func testOtherTopicsAreNotJudgedThisWay() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "빵을 먹어요", topicId: "ko.batchim"), [])
        XCTAssertEqual(PronunciationContrast.alternates(for: "think", topicId: "en.th"), [])
    }

    func testEachMeasuredSoundHasItsSwap() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "커피 포도", topicId: "ko.asp"), ["거비 보도", "꺼삐 뽀도"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "거기 고기", topicId: "ko.eoo"), ["고기 거기"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "그림", topicId: "ko.eu"), ["구림"])
        // The three-way topic: each of the three against both others.
        XCTAssertEqual(PronunciationContrast.alternates(for: "가 까 카 사 싸", topicId: "ko.three"),
                       ["까 카 가 싸 사", "카 가 까 싸 사"])
    }

    func testSpanishFrenchGermanSwapInsideTheWord() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "Mi perro es caro.", topicId: "es.rr"), ["Mi pero es caro."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Mi perro es caro.", topicId: "es.r"), ["Mi perro es carro."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "El niño come jamón.", topicId: "es.ny"), ["El nino come jamón."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "La gente come jamón.", topicId: "es.j"), ["La yente come yamón."])
        // Short words were not measured: "tu" and "sur" are left alone.
        XCTAssertEqual(PronunciationContrast.alternates(for: "Tu es sur la voiture.", topicId: "fr.u"),
                       ["Tu es sur la voitoure."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Le professeur est seul.", topicId: "fr.eu"),
                       ["Le professour est soul."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Pendant la chanson", topicId: "fr.nasal"),
                       ["Pendont la chonson", "Pendant la chansan"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Ich bin müde für heute.", topicId: "de.ue"),
                       ["Ich bin mude für heute."])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Mein Wein in Wien", topicId: "de.eiie"),
                       ["Mien Wien in Wien", "Mein Wein in Wein"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "Ich mag die Kirche nicht, auch.", topicId: "de.ich"),
                       ["Ich mag die Kirsche nischt, auch."])
    }

    func testJapaneseTakesOneBeatOutPerAlternate() {
        XCTAssertEqual(PronunciationContrast.alternates(for: "ビールとコーヒーをください。", topicId: "ja.long"),
                       ["ビルとコーヒーをください。", "ビールとコヒーをください。"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "切手を買って待っています。", topicId: "ja.tsu"),
                       ["切手を買て待っています。", "切手を買って待ています。"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "おばあさんが来ました。", topicId: "ja.long"), [])
    }

    func testChineseSwapsOneCharacterForAnotherTone() {
        // 想 xiǎng → 像 xiàng, 买 mǎi → 埋 mái: the second tone first, where the list has one.
        XCTAssertEqual(PronunciationContrast.alternates(for: "我想买东西。", topicId: "zh.t3"),
                       ["我像买东西。", "我想埋东西。"])
        XCTAssertEqual(PronunciationContrast.alternates(for: "我想买东西。", topicId: "zh.sandhi"), [])
    }

    func testChineseIsComparedCharacterByCharacter() {
        func zh(_ words: [(String, [(String, Int)])], alt: [(String, [Int])]) -> PronunciationResult {
            var r = PronunciationResult(
                score: 80, accuracy: 80, fluency: 80, completeness: 100, prosody: nil, locale: "zh-CN",
                recognized: "", words: words.map { w in
                    .init(word: w.0, accuracy: w.1.map(\.1).min(), error: "None", offsetMs: 0, durationMs: 300,
                          phonemes: w.1.map { .init(phoneme: $0.0, accuracy: $0.1, heard: nil) })
                })
            r.alternates = [.init(reference: "", words: alt.map {
                .init(word: $0.0, accuracy: $0.1.min(), error: "None", phonemes: $0.1)
            })]
            return r
        }
        func v(_ r: PronunciationResult) -> PronunciationJudge.Verdict {
            PronunciationJudge.verdict(result: r, line: .init(id: UUID(), text: "", focus: []), said: "",
                                       phonemes: [], language: "zh")
        }
        // 买 said as 卖: the fourth tone fits better.
        XCTAssertEqual(v(zh([("我", [("wo 3", 95)]), ("想买", [("xiang 3", 90), ("mai 3", 55)])],
                            alt: [("我", [95]), ("想卖", [90, 96])])),
                       .notYet(word: "想买", sound: nil, score: 80, heard: "卖"))
        // A native 买.
        XCTAssertEqual(v(zh([("我", [("wo 3", 95)]), ("想买", [("xiang 3", 90), ("mai 3", 94)])],
                            alt: [("我", [95]), ("想卖", [90, 60])])), .pass(score: 80))
        // Azure read the character with another tone than the table's: not compared.
        XCTAssertEqual(v(zh([("不", [("bu 2", 60)]), ("是", [("shi 4", 95)])],
                            alt: [("布", [99]), ("是", [95])])), .pass(score: 80))
    }

    func testJapaneseIsLinedUpByLetter() {
        func ja(_ words: [(String, Int)], alt: [(String, Int)]) -> PronunciationResult {
            var r = PronunciationResult(score: 80, accuracy: 80, fluency: 80, completeness: 100, prosody: nil,
                                        locale: "ja-JP", recognized: "", words: words.map { word($0.0, $0.1) })
            r.alternates = [.init(reference: "", words: alt.map { .init(word: $0.0, accuracy: $0.1, error: "None") })]
            return r
        }
        func v(_ r: PronunciationResult) -> PronunciationJudge.Verdict {
            PronunciationJudge.verdict(result: r, line: .init(id: UUID(), text: "", focus: []), said: "",
                                       phonemes: [], language: "ja")
        }
        // A native "立って": the other spelling fits far worse.
        XCTAssertEqual(v(ja([("先頭", 85), ("に", 97), ("立っ", 94), ("て", 94), ("歌い", 82)],
                            alt: [("先頭", 85), ("に", 94), ("立て", 8), ("歌い", 82)])), .pass(score: 80))
        // The beat left out: "立て" fits better by more than the margin.
        XCTAssertEqual(v(ja([("先頭", 85), ("に", 97), ("立っ", 40), ("て", 90), ("歌い", 82)],
                            alt: [("先頭", 85), ("に", 94), ("立て", 92), ("歌い", 82)])),
                       .notYet(word: "立っ", sound: nil, score: 80, heard: "立て"))
        // Within the margin of 15: too close to call.
        XCTAssertEqual(v(ja([("ビール", 78), ("を", 97)], alt: [("ビル", 90), ("を", 97)])), .pass(score: 80))
    }

    // MARK: The verdict

    func testALowScoreAloneNeverStopsANativeReading() {
        // The founder's take: "예쁜" at 37, and no better as "예븐".
        let r = take([word("예쁜", 37), word("카페에서", 96)], alternate: [("예븐", 30), ("카페에서", 96)])
        XCTAssertEqual(verdict(r), .pass(score: 60))
    }

    func testThePlainConsonantIsNotYet() {
        let r = take([word("빵을", 52), word("먹었어요", 95)], alternate: [("방을", 97), ("먹었어요", 95)])
        XCTAssertEqual(verdict(r), .notYet(word: "빵을", sound: nil, score: 60, heard: "방을"))
    }

    func testTooCloseToCallPasses() {
        let r = take([word("빵을", 80), word("먹었어요", 95)], alternate: [("방을", 85), ("먹었어요", 95)])
        XCTAssertEqual(verdict(r), .pass(score: 60))
    }

    func testAWordOutsideTheLessonIsNeverCompared() {
        // The same word under both spellings: a different score is noise.
        let r = take([word("빵을", 90), word("먹었어요", 40)], alternate: [("방을", 60), ("먹었어요", 95)])
        XCTAssertEqual(verdict(r), .pass(score: 60))
    }

    func testAWordLeftOutIsNotYet() {
        let r = take([word("빵을", 90), word("먹었어요", 0, error: "Omission")], alternate: [("방을", 60), ("먹었어요", 0)])
        XCTAssertEqual(verdict(r), .notYet(word: "먹었어요", sound: nil, score: 60, heard: nil))
    }

    func testNoAlternateBackMeansNothingIsFailed() {
        let r = take([word("예쁜", 37), word("카페에서", 96)], alternate: nil)
        XCTAssertEqual(verdict(r), .pass(score: 60))
    }

    func testAReadingAfterAMissIsJudgedOnTheWordsThatMissed() {
        let r = take([word("빵을", 52), word("딸기를", 50)], alternate: [("방을", 97), ("달기를", 90)])
        let l = PronunciationRound.Line(id: UUID(), text: "", focus: [])
        XCTAssertEqual(PronunciationJudge.missedWords(result: r, line: l, said: "", phonemes: [], language: "ko"),
                       ["빵을", "딸기를"])
        let only = PronunciationJudge.verdict(result: r, line: l, said: "", phonemes: [], language: "ko",
                                              only: ["딸기를"])
        XCTAssertEqual(only, .notYet(word: "딸기를", sound: nil, score: 60, heard: "달기를"))
    }

    // MARK: What is offered

    func testOnlyMeasuredSoundsAreOffered() {
        XCTAssertTrue(PronunciationCall.isOffered(for: "en"))
        XCTAssertTrue(PronunciationCall.isOffered(for: "ko"))
        for other in ["ja", "de", "es", "fr"] {
            XCTAssertTrue(PronunciationCall.isOffered(for: other), other)
        }
        XCTAssertTrue(PronunciationCall.isOffered(for: "zh"))
        XCTAssertEqual(PronunciationCourse.topics(for: "es").map(\.id), ["es.rr", "es.r", "es.j", "es.ny"])
        XCTAssertEqual(PronunciationCourse.topics(for: "fr").map(\.id), ["fr.u", "fr.nasal", "fr.eu"])
        XCTAssertEqual(PronunciationCourse.topics(for: "de").map(\.id).sorted(),
                       ["de.eiie", "de.ich", "de.oe", "de.ue"])
        XCTAssertEqual(PronunciationCourse.topics(for: "ja").map(\.id), ["ja.long", "ja.tsu"])
        XCTAssertEqual(PronunciationCourse.topics(for: "zh").map(\.id), ["zh.t1", "zh.t2", "zh.t3", "zh.t4"])
        XCTAssertEqual(PronunciationCourse.topics(for: "ko").map(\.id),
                       ["ko.tense", "ko.asp", "ko.three", "ko.eoo", "ko.eu"])
        XCTAssertFalse(PronunciationCourse.topics(for: "en").isEmpty)
    }
}
