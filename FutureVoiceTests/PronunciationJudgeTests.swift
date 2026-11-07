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

    func testAWordRightAloneIsPracticedWithItsNeighbours() {
        let j = PronunciationJudge.self
        XCTAssertEqual(j.flowText(for: "rather", in: "I'd rather walk than drive."), "I'd rather walk")
        XCTAssertEqual(j.flowText(for: "This", in: "This is my mother."), "This is my")
        XCTAssertEqual(j.flowText(for: "mother", in: "This is my mother."), "is my mother")
        XCTAssertEqual(j.flowText(for: "that", in: "Not that."), "Not that")
    }

    // MARK: - A word on its own: a sound heard as another (2026-11-07)

    private typealias Heard = (String, Int, [(String, Int)])

    private func drillWord(_ w: String, _ ps: [Heard], accuracy: Int) -> PronunciationResult {
        let phonemes = ps.map { p in
            PronunciationResult.Phoneme(phoneme: p.0, accuracy: p.1,
                                        heard: p.2.map { .init(phoneme: $0.0, score: $0.1) })
        }
        return take([.init(word: w, accuracy: accuracy, error: "None", offsetMs: 0,
                           durationMs: 400, phonemes: phonemes)])
    }

    private func drill(_ r: PronunciationResult, _ text: String, lesson: [String] = ["θ"]) -> PronunciationJudge.Verdict {
        PronunciationJudge.verdict(result: r, line: line(text), said: "", phonemes: lesson,
                                   language: "en", wordDrill: true)
    }

    func testSinkReadAsThinkIsNotYet() {
        // Measured: "sink" against "think" — θ 73 (over the lesson bar) with
        // s on top and θ not in the list.
        let r = drillWord("think", [("θ", 73, [("s", 100), ("z", 54), ("ɪ", 45)]),
                                    ("ɪ", 68, [("ɪ", 100), ("æ", 100)]),
                                    ("ŋ", 100, [("ŋ", 100)]), ("k", 93, [("k", 100)])], accuracy: 86)
        guard case .notYet(_, let sound, _, _) = drill(r, "think") else { return XCTFail("sink is not think") }
        XCTAssertEqual(sound, "θ")
        // The same take inside a sentence keeps the sentence rules.
        XCTAssertEqual(PronunciationJudge.verdict(result: r, line: line("think"), said: "", phonemes: th,
                                                  language: "en"), .pass(score: 90))
    }

    func testShipReadAsSheepIsNotYet() {
        // Daniel's "ship" against "sheep": i 50 with ɪ on top, i absent.
        let r = drillWord("sheep", [("ʃ", 72, [("ʃ", 100)]), ("i", 50, [("ɪ", 99), ("eɪ", 92), ("ɛ", 60)]),
                                    ("p", 61, [("t", 100), ("d", 85), ("p", 85)])], accuracy: 71)
        guard case .notYet(_, let sound, _, _) = drill(r, "sheep", lesson: ["i"]) else { return XCTFail() }
        XCTAssertEqual(sound, "i")
        XCTAssertEqual(PronunciationJudge.heardAs(result: r, word: "sheep", sound: "i"), .sound("ɪ"))
    }

    func testANativeWordStillPasses() {
        // Native "thank": s on top of θ, but θ itself at 94 in the list.
        let thank = drillWord("thank", [("θ", 98, [("s", 100), ("θ", 94)]), ("æ", 100, [("æ", 100)]),
                                        ("ŋ", 100, [("ŋ", 100)]), ("k", 85, [("k", 100)])], accuracy: 98)
        XCTAssertEqual(drill(thank, "thank"), .pass(score: 90))
        // Native "bad": m on top of b at 78 — over the swap bar.
        let bad = drillWord("bad", [("b", 78, [("m", 100), ("b", 46)]), ("æ", 99, [("æ", 100)]),
                                    ("d", 100, [("d", 100)])], accuracy: 96)
        XCTAssertEqual(drill(bad, "bad", lesson: []), .pass(score: 90))
        // Native "sheep": its final p heard as g — a final stop never counts.
        let sheep = drillWord("sheep", [("ʃ", 100, [("ʃ", 100)]), ("i", 98, [("i", 100)]),
                                        ("p", 44, [("g", 100), ("k", 93), ("i", 42)])], accuracy: 94)
        XCTAssertEqual(drill(sheep, "sheep", lesson: []), .pass(score: 90))
    }

    func testASchwaSaidAnotherWayIsNotASwap() {
        let r = drillWord("decision", [("d", 92, [("d", 100)]), ("ə", 40, [("ɪ", 100)]),
                                       ("s", 90, [("s", 100)])], accuracy: 85)
        XCTAssertEqual(drill(r, "decision", lesson: []), .pass(score: 90))
    }
}
