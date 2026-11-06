import XCTest
@testable import FutureVoice

/// The pronunciation call's verdict (`PronunciationJudge`). Pins the
/// 2026-11-06 rules from a Plus learner's th lesson: 41 of 52 readings
/// scoring 85–97 were "not yet", one sentence was read 11 times with a new
/// word drilled each time, and "decision" was drilled for its /ə/.
final class PronunciationJudgeTests: XCTestCase {
    private let th = ["θ"]

    private func word(_ w: String, _ phonemes: [(String, Int)], accuracy: Int? = nil) -> PronunciationResult.Word {
        let ps = phonemes.map { PronunciationResult.Phoneme(phoneme: $0.0, accuracy: $0.1, heard: nil) }
        return .init(word: w, accuracy: accuracy ?? (ps.compactMap(\.accuracy).min() ?? 100),
                     error: "None", offsetMs: 0, durationMs: 300, phonemes: ps)
    }

    private func take(_ words: [PronunciationResult.Word]) -> PronunciationResult {
        .init(score: 90, accuracy: 90, fluency: 100, completeness: 100, prosody: 89,
              locale: "en-US", recognized: "", words: words)
    }

    private func line(_ text: String, watch: Set<String>? = nil) -> PronunciationRound.Line {
        var l = PronunciationRound.Line(id: UUID(), text: text, focus: [])
        l.watch = watch
        return l
    }

    private func verdict(_ r: PronunciationResult, _ l: PronunciationRound.Line) -> PronunciationJudge.Verdict {
        PronunciationJudge.verdict(result: r, line: l, said: "", phonemes: th, language: "en", only: l.watch)
    }

    func testAVowelOutsideTheLessonNeverStopsTheSentence() {
        let r = take([word("my", [("m", 95), ("aɪ", 90)]),
                      word("decision", [("d", 92), ("ə", 31), ("s", 90), ("ɪ", 88), ("ʒ", 85), ("ə", 80), ("n", 95)],
                           accuracy: 80)])
        XCTAssertEqual(verdict(r, line("my decision")), .pass(score: 90))
    }

    func testTheLessonSoundStillStopsIt() {
        let r = take([word("think", [("θ", 60), ("ɪ", 95), ("ŋ", 95), ("k", 95)], accuracy: 85)])
        guard case .notYet(let w, let sound, _, _) = verdict(r, line("think")) else {
            return XCTFail("θ at 60 must be not yet")
        }
        XCTAssertEqual(w, "think")
        XCTAssertEqual(sound, "θ")
    }

    func testABrokenConsonantStillStopsIt() {
        // "드링크": the f of "flight" heard as p, 38.
        let r = take([word("flight", [("f", 38), ("l", 80), ("aɪ", 90), ("t", 90)], accuracy: 75)])
        guard case .notYet(let w, let sound, _, _) = verdict(r, line("flight")) else {
            return XCTFail("a consonant at 38 must be not yet")
        }
        XCTAssertEqual(w, "flight")
        XCTAssertEqual(sound, "f")
    }

    func testAMildConsonantDipDoesNot() {
        let r = take([word("before", [("b", 60), ("ɪ", 90), ("f", 58), ("ɔɹ", 90)], accuracy: 82)])
        XCTAssertEqual(verdict(r, line("before")), .pass(score: 90))
    }

    func testMissedWordsListsEveryMiss() {
        let r = take([word("think", [("θ", 55)], accuracy: 80),
                      word("three", [("θ", 62), ("ɹ", 90), ("i", 90)], accuracy: 85),
                      word("thank", [("θ", 92)], accuracy: 92)])
        let missed = PronunciationJudge.missedWords(result: r, line: line("think three thank"),
                                                    said: "", phonemes: th, language: "en")
        XCTAssertEqual(missed, ["think", "three"])
    }

    func testARetryIsJudgedOnlyOnWhatMissedBefore() {
        // First reading missed on "think"; now "think" is clean and "thank"
        // has dipped. The sentence passes: "thank" came out the first time.
        let r = take([word("think", [("θ", 90)], accuracy: 90),
                      word("thank", [("θ", 60)], accuracy: 85)])
        XCTAssertEqual(verdict(r, line("think thank", watch: ["think"])), .pass(score: 90))
        // Without the memory it would have failed somewhere new.
        guard case .notYet(let w, _, _, _) = verdict(r, line("think thank")) else {
            return XCTFail("unscoped, thank at 60 is not yet")
        }
        XCTAssertEqual(w, "thank")
    }

    func testAWatchedWordThatStillMissesIsNamedAgain() {
        let r = take([word("think", [("θ", 50)], accuracy: 80),
                      word("thank", [("θ", 90)], accuracy: 90)])
        guard case .notYet(let w, _, _, _) = verdict(r, line("think thank", watch: ["think"])) else {
            return XCTFail("think still at 50")
        }
        XCTAssertEqual(w, "think")
    }
}
