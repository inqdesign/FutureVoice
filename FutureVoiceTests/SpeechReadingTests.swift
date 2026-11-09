import XCTest
@testable import FutureVoice

final class SpeechReadingTests: XCTestCase {
    private struct Row: Decodable {
        let g: String, sp: Double, rh: Double, ep: Double, sl: Double
        let so: Double?, h: Double?, t: Int
    }

    private func total(_ r: Row) -> Int {
        let p = SpeechReading.parts(speed: r.sp, rhythm: r.rh, pausesPer100: r.ep, slipsPer100: r.sl, soundAccuracy: r.so)
        return SpeechReadingScore(version: 5, gender: "male", parts: p, coverage: 1, speed: r.sp, rhythm: r.rh,
                                  pausesPer100: r.ep, slipsPer100: r.sl, soundAccuracy: r.so.map { Int($0) }, slips: 0,
                                  extraPauses: [], held: [], missed: [], weakest: []).total
    }

    /// The validation readings under the plain scale: narrators and natives
    /// on top, learners below them, and the learners still in the experts'
    /// order.
    func testValidationShape() throws {
        let rows = try JSONDecoder().decode([Row].self, from: Data(speechReadingValidation20261108.utf8))
        XCTAssertEqual(rows.count, 138)
        func totals(_ g: String) -> [Int] { rows.filter { $0.g == g }.map(total).sorted() }
        func median(_ g: String) -> Int { let t = totals(g); return t[t.count / 2] }
        XCTAssertTrue((95...99).contains(median("narrator")), "\(median("narrator"))")
        XCTAssertTrue((94...98).contains(median("native")), "\(median("native"))")
        XCTAssertTrue((82...92).contains(median("learner")), "\(median("learner"))")
        XCTAssertFalse(totals("learner").contains(100))

        let learners = rows.filter { $0.g == "learner" }
        XCTAssertGreaterThanOrEqual(spearman(learners.map { Double(total($0)) }, learners.compactMap(\.h)), 0.8)
    }

    /// Each part is the measurement; the total is their average.
    func testPartsAreTheMeasurements() {
        let p = SpeechReading.parts(speed: 0.82, rhythm: 0.78, pausesPer100: 0.6, slipsPer100: 6.9, soundAccuracy: 86)
        XCTAssertEqual(p.speed, 82); XCTAssertEqual(p.rhythm, 78); XCTAssertEqual(p.pauses, 99)
        XCTAssertEqual(p.accuracy, 93); XCTAssertEqual(p.pronunciation, 86)
        // Faster than the native reading counts the same as slower.
        XCTAssertEqual(SpeechReading.parts(speed: 1.25, rhythm: 1, pausesPer100: 0, slipsPer100: 0, soundAccuracy: 100).speed, 80)
    }

    func testTotalIsThePlainAverage() {
        func total(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Int {
            SpeechReadingScore(version: 7, gender: "male",
                               parts: .init(speed: a, rhythm: b, pauses: c, accuracy: d, pronunciation: e),
                               coverage: 1, speed: 1, rhythm: 1, pausesPer100: 0, slipsPer100: 0, soundAccuracy: e,
                               slips: 0, extraPauses: [], held: [], missed: [], weakest: []).total
        }
        XCTAssertEqual(total(96, 96, 96, 96, 96), 96)
        XCTAssertEqual(total(100, 100, 100, 100, 100), 100)
        XCTAssertEqual(total(100, 100, 100, 100, 99), 99)   // 99.8, and not 100 in everything
    }

    /// A take compared with a reference: the pause the native reading
    /// doesn't make is found, and the word held far longer than the native
    /// holds it is named.
    func testExtraPausesAndHeldWords() {
        let script = (1...30).map { "w\($0)" }
        var stops = [SpeechDelivery.Stop](repeating: .none, count: 30)
        stops[5] = .sentence                         // a stop after w6 is the script's
        var ref: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)] = []
        var take: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)] = []
        var t = 0, u = 0
        for (i, w) in script.enumerated() {
            ref.append((w, t, t + 250, false)); t += 270
            let held = i == 10 ? 900 : 300           // w11 held 3x
            take.append((w, u, u + held, false)); u += held + (i == 20 || i == 5 ? 600 : 20)   // stops after w21 and w6
        }
        let r = SpeechReading.score(
            take: SpeechReading.timeline(words: take, script: script),
            reference: SpeechReading.timeline(words: ref, script: script),
            script: script, stops: stops, slips: 0, scriptTokens: 30, missed: [], soundAccuracy: 97, weakest: [],
            coverage: 1, gender: "male")!
        XCTAssertEqual(r.extraPauses.map(\.after), ["w21"])
        XCTAssertEqual(r.held.first?.word, "w11")
        XCTAssertGreaterThan(r.held.first?.times ?? 0, 2.5)
        XCTAssertFalse(r.isPerfect)
    }

    private func spearman(_ x: [Double], _ y: [Double]) -> Double {
        func ranks(_ v: [Double]) -> [Double] {
            let order = v.indices.sorted { v[$0] < v[$1] }
            var r = [Double](repeating: 0, count: v.count)
            var i = 0
            while i < order.count {
                var j = i
                while j + 1 < order.count && v[order[j + 1]] == v[order[i]] { j += 1 }
                for k in i...j { r[order[k]] = Double(i + j) / 2 }
                i = j + 1
            }
            return r
        }
        return SpeechReading.pearson(ranks(x), ranks(y)) ?? 0
    }
}
