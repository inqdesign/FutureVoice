import XCTest
@testable import FutureVoice

/// The listening reading's marks and the phrase drill's rules (2026-11-13).
final class SpeechListenTests: XCTestCase {
    private func w(_ word: String, _ s: Int, _ e: Int) -> SpeechReference.Word { .init(w: word, s: s, e: e) }

    func testBreathOnlyInsideASentence() {
        let body = "All right, everyone, come a little closer. Don't be shy."
        let words = [w("all", 0, 200), w("right", 210, 400), w("everyone", 410, 900),
                     w("come", 1300, 1500), w("a", 1500, 1560), w("little", 1560, 1800),
                     w("closer", 1800, 2200), w("don't", 2800, 3000), w("be", 3000, 3100), w("shy", 3100, 3400)]
        let text = SpeechListenText(body: body, words: words)
        let tokens = text.paragraphs[0]
        XCTAssertEqual(tokens.map(\.text).count, 10)
        XCTAssertTrue(tokens[2].breath, "a 0.4 s stop after a comma is a breath")
        XCTAssertFalse(tokens[6].breath, "a stop after a full stop is not marked")
        XCTAssertTrue(tokens[3].runsOn, "come‿a")
        XCTAssertFalse(tokens[4].runsOn, "a little: next word starts with a consonant")
    }

    func testUntimedWordTakesThePreviousEnd() {
        let text = SpeechListenText(body: "one two three", words: [w("one", 0, 300), w("three", 600, 900)])
        let t = text.paragraphs[0]
        XCTAssertEqual(t[1].start, 0.3, accuracy: 0.001)
        XCTAssertEqual(text.sentenceEnd(after: 0), nil)
    }

    func testPhraseAroundAStopHoldsTheNextWord() {
        let written = "Then, on a quiet Monday morning in August of nineteen eleven, while".split(separator: " ").map(String.init)
        let stop = SpeechPhraseMark(word: 5, kind: .stop, seconds: 0.6)   // after "morning"
        let r = SpeechPhrase.around(stop, written: written)
        XCTAssertEqual(written[r].first, "on")
        XCTAssertTrue(r.contains(6), "the word after the stop is in the phrase")
        XCTAssertLessThanOrEqual(r.upperBound - stop.word, 4)
    }

    func testJudgeFindsAStopTheFluentReadingDoesNotMake() {
        let phrase = "on a quiet Monday morning in August"
        let fluent = SpeechListenText.display(body: phrase, words: [
            w("on", 0, 80), w("a", 80, 130), w("quiet", 130, 450), w("monday", 450, 830),
            w("morning", 830, 1250), w("in", 1250, 1330), w("august", 1330, 1800)])
        let stopped = SpeechListenText.display(body: phrase, words: [
            w("on", 0, 90), w("a", 90, 140), w("quiet", 140, 470), w("monday", 470, 860),
            w("morning", 860, 1290), w("in", 1900, 1980), w("august", 1980, 2450)])
        let j = SpeechPhrase.judge(said: stopped, fluent: fluent)
        XCTAssertEqual(j.stops, ["morning"])
        XCTAssertFalse(j.matched)

        let same = SpeechPhrase.judge(said: fluent, fluent: fluent)
        XCTAssertTrue(same.matched)
        XCTAssertEqual(same.rhythm ?? 0, 1, accuracy: 0.001)
    }
}

/// Scoring 8's price list (2026-11-13), on the founder's docent take that
/// morning: 4 stops, 3 words, 11 sounds, rhythm 0.77, pace 79% → 76.
final class SpeechPriceListTests: XCTestCase {
    private func score(stops: Int, slips: Int, sounds: Int?, rhythm: Double, speed: Double,
                       coverage: Double = 1, words: Int = 253) -> SpeechReadingScore {
        SpeechReadingScore(
            version: 8, gender: "male",
            parts: .init(speed: 79, rhythm: 77, pauses: 98, accuracy: 99, pronunciation: 96),
            coverage: coverage, speed: speed, rhythm: rhythm, pausesPer100: 0, slipsPer100: 0,
            soundAccuracy: 96, slips: slips,
            extraPauses: (0..<stops).map { .init(after: "w\($0)", seconds: 0.4) },
            held: [], missed: [], weakest: [], weakSounds: sounds, scriptWords: words)
    }

    func testFoundersReceipt() {
        let r = score(stops: 4, slips: 3, sounds: 11, rhythm: 0.77, speed: 0.79)
        XCTAssertEqual(r.deductions.first { $0.part == .pronunciation }!.points, 4.4, accuracy: 0.0001)
        XCTAssertEqual(r.total, 76)
        XCTAssertEqual(r.focus, .rhythm)
    }

    func testNothingLostIsAHundredAndAnythingLostIsUnder() {
        XCTAssertEqual(score(stops: 0, slips: 0, sounds: 0, rhythm: 0.93, speed: 0.95).total, 100)
        XCTAssertEqual(score(stops: 0, slips: 0, sounds: 1, rhythm: 0.93, speed: 0.95).total, 99)
    }

    func testStoppingEarlyCostsEveryWordNotReached() {
        let r = score(stops: 0, slips: 0, sounds: 0, rhythm: 0.93, speed: 0.95, coverage: 0.9, words: 200)
        XCTAssertEqual(r.unreadWords, 20)
        XCTAssertEqual(r.total, 80)
    }

    func testEachAreaIsTwentyAndStopsAtZero() {
        // 30 stops cost 30, but the pauses area holds only 20 of the 100.
        let r = score(stops: 30, slips: 0, sounds: 0, rhythm: 0.93, speed: 0.95)
        XCTAssertEqual(r.areaScore(r.deductions.first { $0.part == .pauses }!), 0)
        XCTAssertEqual(r.total, 80)
        XCTAssertEqual(r.focus, .pauses)
        XCTAssertEqual(r.deductions.map(\.part), [.speed, .rhythm, .pauses, .accuracy, .pronunciation])
    }

    func testFoundersAreas() {
        let r = score(stops: 4, slips: 6, sounds: 35, rhythm: 0.82, speed: 0.79)
        XCTAssertEqual(r.deductions.map { r.areaScore($0) }, [70, 80, 80, 70, 30])
        XCTAssertEqual(r.total, 66)
    }

    func testFasterThanTheNativeReadingCountsLikeSlower() {
        // Pace is the share of the native pace either way (min(s, 1/s)).
        XCTAssertEqual(score(stops: 0, slips: 0, sounds: 0, rhythm: 0.93, speed: 1.25).speedPoint, 80)
    }

    func testNamesAreNeverSlips() {
        let names = SpeechAnalyzer.properNames("The police even questioned a young Pablo Picasso. And here, I said.")
        XCTAssertEqual(names, ["pablo", "picasso"])
    }
}

/// Weak sounds are counted where they were said, once per script word
/// (2026-11-13): pieces overlap by two words, and a word assessed twice used
/// to be charged twice.
final class SpeechWeakSoundTests: XCTestCase {
    private func word(_ w: String, _ sounds: [(String, Int)]) -> PronunciationResult.Word {
        .init(word: w, accuracy: 80, error: "None", offsetMs: 0, durationMs: 200,
              phonemes: sounds.map { .init(phoneme: $0.0, accuracy: $0.1) })
    }
    private func piece(_ words: [PronunciationResult.Word]) -> PronunciationResult {
        .init(score: 80, accuracy: 80, fluency: 80, completeness: 100, prosody: nil, locale: "en-US",
              recognized: "", words: words)
    }

    func testOverlapCountsOnce() {
        let script = "It was a quiet Monday morning."
        let a = piece([word("It", [("ɪ", 90)]), word("was", [("w", 90), ("z", 0)]), word("a", [("ə", 90)])])
        let b = piece([word("was", [("w", 90), ("z", 10)]), word("a", [("ə", 90)]), word("quiet", [("t", 20)]),
                       word("Monday", [("m", 95)]), word("morning", [("ŋ", 99)])])
        let weak = SpeechReading.weakSounds(pieces: [a, b], script: script)
        XCTAssertEqual(weak.values.reduce(0) { $0 + $1.count }, 2)   // z in "was" once, t in "quiet"
        XCTAssertEqual(weak[1]?.first?.score, 0)                       // the first reading of "was"
    }

    func testASoundTheFluentReadingAlsoMissesIsNotCounted() {
        // The founder's "newspapers": the fluent reading says "nyu" too, and
        // the assessment scored the reading 46 there.
        let script = "Newspapers printed her face."
        let mine = piece([word("Newspapers", [("n", 39), ("u", 35), ("s", 100), ("z", 22)]),
                          word("printed", [("t", 20)])])
        var news = SpeechReference.Word(w: "newspapers", s: 0, e: 600)
        news.ph = [.init(p: "n", a: 46), .init(p: "u", a: 46), .init(p: "s", a: 100), .init(p: "z", a: 90)]
        var printed = SpeechReference.Word(w: "printed", s: 600, e: 900)
        printed.ph = [.init(p: "t", a: 95)]
        let weak = SpeechReading.weakSounds(pieces: [mine], script: script, fluent: [news, printed])
        XCTAssertEqual(weak[0]?.map(\.phoneme), ["z"])   // n and u spared, z still counted
        XCTAssertEqual(weak[1]?.map(\.phoneme), ["t"])
        XCTAssertEqual(SpeechReading.weakSounds(pieces: [mine], script: script).values.reduce(0) { $0 + $1.count }, 4)
    }
}
