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

    /// The validation of 2026-11-08, held: the app scores every reading as
    /// the prototype did (within a point of rounding), narrators sit at the
    /// top, ordinary natives around 90, learners in the middle, no learner
    /// reaches 100, and the learners come out in the experts' order.
    func testValidationShape() throws {
        let rows = try JSONDecoder().decode([Row].self, from: Data(speechReadingValidation20261108.utf8))
        XCTAssertEqual(rows.count, 139)
        for r in rows {
            XCTAssertLessThanOrEqual(abs(total(r) - r.t), 1, "\(r.g) \(r.sp) \(r.rh) \(r.ep)")
        }
        func totals(_ g: String) -> [Int] { rows.filter { $0.g == g }.map(total).sorted() }
        func median(_ g: String) -> Int { let t = totals(g); return t[t.count / 2] }
        XCTAssertTrue((95...99).contains(median("narrator")), "\(median("narrator"))")
        XCTAssertTrue((88...94).contains(median("native")), "\(median("native"))")
        XCTAssertTrue((60...75).contains(median("learner")), "\(median("learner"))")
        XCTAssertFalse(totals("learner").contains(100))
        XCTAssertTrue(totals("founder").allSatisfy { (60...77).contains($0) }, "\(totals("founder"))")

        let learners = rows.filter { $0.g == "learner" }
        XCTAssertGreaterThanOrEqual(spearman(learners.map { Double(total($0)) }, learners.compactMap(\.h)), 0.8)
    }

    /// A take compared with a reference: the pause the native reading
    /// doesn't make is found, and the word held far longer than the native
    /// holds it is named.
    func testExtraPausesAndHeldWords() {
        let script = (1...30).map { "w\($0)" }
        var ref: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)] = []
        var take: [(word: String, startMs: Int, endMs: Int, breakAfter: Bool)] = []
        var t = 0, u = 0
        for (i, w) in script.enumerated() {
            ref.append((w, t, t + 250, false)); t += 270
            let held = i == 10 ? 900 : 300           // w11 held 3x
            take.append((w, u, u + held, false)); u += held + (i == 20 ? 600 : 20)   // a stop after w21
        }
        let r = SpeechReading.score(
            take: SpeechReading.timeline(words: take, script: script),
            reference: SpeechReading.timeline(words: ref, script: script),
            script: script, slips: 0, scriptTokens: 30, missed: [], soundAccuracy: 97, weakest: [],
            coverage: 1, gender: "male")!
        XCTAssertEqual(r.extraPauses.map(\.after), ["w21"])
        XCTAssertEqual(r.held.first?.word, "w11")
        XCTAssertGreaterThan(r.held.first?.times ?? 0, 2.5)
        XCTAssertFalse(r.isPerfect)
    }

    func testLevels() {
        XCTAssertEqual(SpeechReadingLevel(total: 100), .announcer)
        XCTAssertEqual(SpeechReadingLevel(total: 97), .narrator)
        XCTAssertEqual(SpeechReadingLevel(total: 89), .native)
        XCTAssertEqual(SpeechReadingLevel(total: 80), .nearNative)
        XCTAssertEqual(SpeechReadingLevel(total: 69), .intermediate)
        XCTAssertEqual(SpeechReadingLevel(total: 40), .practicing)
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
