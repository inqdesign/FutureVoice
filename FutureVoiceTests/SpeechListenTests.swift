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
/// morning: 4 stops, 3 words, 11 sounds, rhythm 0.77, pace 79% → 75.
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
        XCTAssertEqual(r.deductions.map(\.points), [4, 3, 5.5, 6.5, 6])
        XCTAssertEqual(r.total, 75)
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

    func testFasterThanTheNativeReadingCountsLikeSlower() {
        // Pace is the share of the native pace either way (min(s, 1/s)).
        XCTAssertEqual(score(stops: 0, slips: 0, sounds: 0, rhythm: 0.93, speed: 1.25).speedPoint, 80)
    }

    func testNamesAreNeverSlips() {
        let names = SpeechAnalyzer.properNames("The police even questioned a young Pablo Picasso. And here, I said.")
        XCTAssertEqual(names, ["pablo", "picasso"])
    }
}
