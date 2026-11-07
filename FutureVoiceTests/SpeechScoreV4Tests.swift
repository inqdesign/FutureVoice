import XCTest
@testable import FutureVoice

final class SpeechScoreV4Tests: XCTestCase {
    private struct Row: Decodable {
        let g: String, a: Int, s: Int, w: Int, p: Int, f: Double, r: Int, b: Int, t: Int, i: Int
        let h: Double?
    }

    private func delivery(sound: Int, weak: Int, prosody: Int?, pitch: Double?, wpm: Int?,
                          breaks: Int = 0, stalls: Int = 0, stumbles: Int = 0) -> SpeechDelivery {
        var d = SpeechDelivery(prosody: prosody, fluency: nil, weakSounds: weak, midPauses: breaks,
                       midBoundaries: 20, wordsPerMinute: wpm, monotoneWords: 0,
                       pitchRange: pitch, pitchSD: nil, soundAccuracy: sound,
                       breaks: Array(repeating: .init(before: "a", after: "b", seconds: 0.4), count: breaks),
                       stalls: stalls, weakest: [])
        d.stumbles = Array(repeating: "x", count: stumbles)
        return d
    }

    private func score(_ r: Row) -> SpeechParts? {
        SpeechScoreV4.score(accuracy: r.a, coverage: 1, fillers: 0, missed: [],
                            delivery: delivery(sound: r.s, weak: r.w, prosody: r.p, pitch: r.f,
                                               wpm: r.r, breaks: r.b, stalls: r.t, stumbles: r.i),
                            language: "en")
    }

    /// The calibration of 2026-11-07, held: no learner reaches 100, the
    /// narrators mostly sit at the top, ordinary natives in between, and the
    /// learners come out in the experts' order.
    func testCalibrationShape() throws {
        let rows = try JSONDecoder().decode([Row].self, from: Data(speechCalibration20261107.utf8))
        XCTAssertEqual(rows.count, 227)
        func group(_ g: String) -> [SpeechParts] { rows.filter { $0.g == g }.compactMap(score) }
        func perfectShare(_ g: String) -> Double {
            let parts = group(g)
            return Double(parts.filter(\.isPerfect).count) / Double(parts.count)
        }
        func median(_ g: String) -> Int {
            let totals = group(g).map(\.total).sorted()
            return totals[totals.count / 2]
        }
        XCTAssertEqual(perfectShare("learner"), 0)
        XCTAssertGreaterThanOrEqual(perfectShare("pro"), 0.6)
        XCTAssertGreaterThanOrEqual(perfectShare("pro2"), 0.2)
        XCTAssertTrue((0.05...0.35).contains(perfectShare("native")), "\(perfectShare("native"))")
        XCTAssertGreaterThanOrEqual(median("pro2"), 95)
        XCTAssertTrue((70...88).contains(median("learner")), "\(median("learner"))")

        let learners = rows.filter { $0.g == "learner" }
        let totals = learners.compactMap(score).map { Double($0.total) }
        let experts = learners.compactMap(\.h)
        XCTAssertEqual(totals.count, experts.count)
        XCTAssertGreaterThanOrEqual(spearman(totals, experts), 0.75)
    }

    func testOnlyEnglishWithEveryMeasure() {
        let full = delivery(sound: 97, weak: 80, prosody: 89, pitch: 8, wpm: 170)
        XCTAssertNotNil(SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                            delivery: full, language: "en"))
        XCTAssertNil(SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                         delivery: full, language: "de"))
        let noProsody = delivery(sound: 97, weak: 80, prosody: nil, pitch: 8, wpm: 170)
        XCTAssertNil(SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                         delivery: noProsody, language: "en"))
    }

    /// 100 is every part at its bar AND the script read to the end; anything
    /// short of that is 99 at most.
    func testHundredNeedsEveryPartAndTheWholeScript() {
        let perfect = delivery(sound: 98, weak: 82, prosody: 90, pitch: 9, wpm: 170)
        let p = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                    delivery: perfect, language: "en")!
        XCTAssertTrue(p.isPerfect)
        XCTAssertEqual(p.total, 100)
        XCTAssertNil(p.focus)

        let stopped = SpeechScoreV4.score(accuracy: 100, coverage: 0.9, fillers: 0, missed: [],
                                          delivery: perfect, language: "en")!
        XCTAssertFalse(stopped.isPerfect)
        XCTAssertLessThanOrEqual(stopped.total, 99)

        let oneBreak = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                           delivery: delivery(sound: 98, weak: 82, prosody: 90, pitch: 9,
                                                              wpm: 170, breaks: 1),
                                           language: "en")!
        XCTAssertEqual(oneBreak.total, 98)
        XCTAssertEqual(oneBreak.focus, .phrasing)
        XCTAssertEqual(oneBreak.barsCleared, 4)
    }

    /// A take that went back over its words doesn't keep full phrasing.
    func testStumblesCostPhrasing() {
        var d = delivery(sound: 98, weak: 82, prosody: 90, pitch: 9, wpm: 170)
        d.stumbles = ["the", "quick"]
        let p = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                    delivery: d, language: "en")!
        XCTAssertEqual(p.phrasing, 84)
        XCTAssertFalse(p.isPerfect)
        XCTAssertEqual(p.focus, .phrasing)
        XCTAssertEqual(p.stumbles, ["the", "quick"])
    }

    /// The part to work on is the one that cost the most points.
    func testFocusIsTheCostliestPart() {
        let flat = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                       delivery: delivery(sound: 97, weak: 78, prosody: 70, pitch: 4.5, wpm: 170),
                                       language: "en")!
        XCTAssertEqual(flat.focus, .expression)
        let slow = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 0, missed: [],
                                       delivery: delivery(sound: 98, weak: 82, prosody: 90, pitch: 9, wpm: 90),
                                       language: "en")!
        XCTAssertEqual(slow.focus, .pace)
    }

    /// Metrics stored before scoring 4 decode with no parts; with them, they
    /// round-trip.
    func testMetricsDecodeOldAndNew() throws {
        let old = #"{"accuracy":90,"rate":150,"rateLow":130,"rateHigh":170,"paceScore":100,"pausesAtBreaks":3,"breaks":3,"hesitations":0,"pauseScore":100,"fillers":0,"fillerScore":100,"steadiness":90,"missed":[],"overall":95,"scoring":3,"pronunciation":94}"#
        let decoded = try JSONDecoder().decode(SpeechMetrics.self, from: Data(old.utf8))
        XCTAssertNil(decoded.parts)

        var m = decoded
        m.parts = SpeechScoreV4.score(accuracy: 100, coverage: 1, fillers: 1, missed: ["a"],
                                      delivery: delivery(sound: 96, weak: 75, prosody: 88, pitch: 7, wpm: 160),
                                      language: "en")
        let again = try JSONDecoder().decode(SpeechMetrics.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(again, m)
    }

    private func spearman(_ x: [Double], _ y: [Double]) -> Double {
        func ranks(_ v: [Double]) -> [Double] {
            let order = v.indices.sorted { v[$0] < v[$1] }
            var r = [Double](repeating: 0, count: v.count)
            var i = 0
            while i < order.count {
                var j = i
                while j + 1 < order.count && v[order[j + 1]] == v[order[i]] { j += 1 }
                let avg = Double(i + j) / 2
                for k in i...j { r[order[k]] = avg }
                i = j + 1
            }
            return r
        }
        let rx = ranks(x), ry = ranks(y)
        let mx = rx.reduce(0, +) / Double(rx.count), my = ry.reduce(0, +) / Double(ry.count)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in rx.indices {
            num += (rx[i] - mx) * (ry[i] - my)
            dx += (rx[i] - mx) * (rx[i] - mx)
            dy += (ry[i] - my) * (ry[i] - my)
        }
        return num / (dx * dy).squareRoot()
    }
}
