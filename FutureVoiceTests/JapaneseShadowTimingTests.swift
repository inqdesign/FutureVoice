import XCTest
@testable import FutureVoice

/// A Japanese line has no spaces, so every timeline used to be ONE word:
/// karaoke lit the whole sentence at once, no word could be tapped, and the
/// rhythm grade had a single pair to judge and hid itself. These pin the cut
/// at each source and the rhythm working end to end on a real line.
final class JapaneseShadowTimingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("ja", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private let line = "昨日は、友達と「映画」を見に行きました。"

    /// Words joined back give the line: the screen draws the line FROM them.
    func testTimingWordsKeepEveryCharacter() {
        let words = WordSplitter.timingWords(line)
        XCTAssertEqual(words.joined(), line)
        XCTAssertEqual(words, ["昨日", "は、", "友達", "と", "「映画」", "を", "見", "に", "行き", "まし", "た。"])
        XCTAssertEqual(WordSplitter.timingWords("「はい」"), ["「はい」"])
    }

    /// ElevenLabs times characters; they come back grouped into those words.
    func testElevenLabsCharactersGroupIntoWords() {
        let chars = line.map(String.init)
        let starts = chars.indices.map { Double($0) * 0.1 }
        let ends = starts.map { $0 + 0.1 }
        let timings = ElevenLabsClient.wordTimings(from: chars, starts: starts, ends: ends)
        XCTAssertEqual(timings.map(\.word), WordSplitter.timingWords(line))
        XCTAssertEqual(timings.first?.startMs, 0)
        XCTAssertEqual(timings.last?.endMs, chars.count * 100)
        XCTAssertTrue(timings.allSatisfy(\.isMeasured))
        XCTAssertTrue(ElevenLabsClient.alignmentMatches(text: line, timings: timings))
    }

    /// The recognizer's segments are cut elsewhere; letters still line up,
    /// and only an onset that sits on a real segment start is "measured".
    func testCharacterAlignmentAcrossDifferentCuts() {
        let words = ["昨日", "は", "友達", "と", "映画", "を", "見", "に", "行き", "まし", "た"]
        let heard: [(text: String, start: Double, end: Double)] = [
            ("昨日は", 0.0, 0.6), ("友達と", 0.7, 1.3), ("映画を", 1.4, 2.0), ("見に行きました", 2.1, 3.5),
        ]
        let t = LocalAlignment.alignByCharacters(expected: words, heard: heard, durationMs: 3600)
        XCTAssertEqual(t.map(\.word), words)
        XCTAssertEqual(t[0].startMs, 0)
        XCTAssertEqual(t[2].startMs, 700)       // 友達 opens a segment
        XCTAssertTrue(t[2].isMeasured)
        XCTAssertFalse(t[1].isMeasured)         // は sits inside 昨日は
        XCTAssertTrue(zip(t, t.dropFirst()).allSatisfy { $0.endMs <= $1.startMs })
        // Nothing anchors → nothing returned, never a made-up timeline.
        XCTAssertTrue(LocalAlignment.alignByCharacters(
            expected: words, heard: [("全然違う話", 0, 1)], durationMs: 1000).isEmpty)
    }

    func testEstimateAndStoredCut() {
        let est = ShadowDrillView.estimatedTimings(for: line, durationMs: 3000)
        XCTAssertEqual(est.map(\.word), WordSplitter.timingWords(line))
        XCTAssertTrue(est.allSatisfy { !$0.isMeasured })
        // A timeline saved as one run is refused, so it gets rebuilt.
        let oneRun = [WordTiming(word: line, startMs: 0, endMs: 3000)]
        XCTAssertFalse(ShadowDrillView.cutMatches(oneRun, text: line))
        XCTAssertTrue(ShadowDrillView.cutMatches(est, text: line))
    }

    /// The whole chain on one Japanese line: target from ElevenLabs, learner
    /// from Apple realigned onto the scored words — the rhythm is graded.
    func testRhythmIsGradedOnAJapaneseLine() {
        let target = "友達と映画を見に行きました"
        let chars = target.map(String.init)
        let starts = chars.indices.map { Double($0) * 0.2 }
        let targetTimings = ElevenLabsClient.wordTimings(from: chars, starts: starts,
                                                         ends: starts.map { $0 + 0.2 })
        let learnerText = "友達と映画を見に行きました"
        let device: [WordTiming] = [
            .init(word: "友達", startMs: 0, endMs: 380),
            .init(word: "と", startMs: 400, endMs: 580),
            .init(word: "映画", startMs: 600, endMs: 980),
            .init(word: "を", startMs: 1000, endMs: 1180),
            .init(word: "見", startMs: 1200, endMs: 1380),
            .init(word: "に", startMs: 1400, endMs: 1580),
            .init(word: "行き", startMs: 1600, endMs: 1980),
            .init(word: "ました", startMs: 2000, endMs: 2580),
        ]
        let learnerTimings = ShadowTranscriber.realigned(
            words: ShadowTranscriber.words(of: learnerText), onto: device)
        XCTAssertGreaterThan(learnerTimings.count, 4)
        let analysis = ShadowEngine.analyze(target: target, learner: learnerText, language: "ja")
        let rhythm = ShadowEngine.analyzeRhythm(steps: analysis.steps,
                                                targetTimings: targetTimings,
                                                learnerTimings: learnerTimings,
                                                language: "ja")
        XCTAssertNotNil(rhythm)
        XCTAssertGreaterThanOrEqual(rhythm?.words.filter(\.isMeasured).count ?? 0,
                                    ShadowEngine.minMeasuredPairs)
    }

    /// The drill card's playback trim finds a quoted fragment by words.
    func testDrillFragmentFindsItsSpan() {
        let turn = DrillStore.matchWords(of: "うん、でも洗濯が溜まって、とても面倒くさいでした。")
        let fragment = DrillStore.matchWords(of: "とても面倒くさいでした")
        XCTAssertNotNil(DrillStore.fragmentSpan(of: fragment, in: turn))
    }
}
