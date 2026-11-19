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
                       ["예븐 카페에서 방을 샀어요."])
    }

    func testAfinalConsonantBeforeItLeavesNothingToCompare() {
        // "짝궁" is said "짝꿍" anyway: only the first syllable is swapped.
        XCTAssertEqual(PronunciationContrast.alternates(for: "짝꿍이랑", topicId: "ko.tense"), ["작꿍이랑"])
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
        for other in ["ja", "de", "es", "fr", "zh"] {
            XCTAssertFalse(PronunciationCall.isOffered(for: other), other)
        }
        XCTAssertEqual(PronunciationCourse.topics(for: "ko").map(\.id), ["ko.tense"])
        XCTAssertFalse(PronunciationCourse.topics(for: "en").isEmpty)
    }
}
