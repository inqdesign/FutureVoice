import XCTest
@testable import FutureVoice

/// A long take read as one file is cut into windows the assessment endpoint
/// can take (≤30 s), at a pause, with nothing lost and no stub at the end.
final class PronunciationWindowTests: XCTestCase {

    /// `seconds` of a 220 Hz tone with a 300 ms silence every 4 s.
    private func wav(seconds: Double) -> Data {
        let rate = 16_000
        let count = Int(seconds * Double(rate))
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let silent = t.truncatingRemainder(dividingBy: 4) > 3.7
            let v: Int16 = silent ? 0 : Int16(8000 * sin(2 * .pi * 220 * t))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        return AudioLoudness.wavData(fromPCM16: pcm, sampleRate: rate)
    }

    private func seconds(_ w: Data) -> Double { Double(w.count - 44) / 32_000 }

    func testLongTakeIsCutIntoAssessableWindowsAtPauses() {
        let take = wav(seconds: 67)
        let windows = PronunciationAssessor.windows(ofWAV: take)
        XCTAssertGreaterThan(windows.count, 2)
        for w in windows {
            XCTAssertLessThanOrEqual(seconds(w), 28.01)
            XCTAssertGreaterThan(seconds(w), 5)
        }
        // Nothing dropped or doubled.
        XCTAssertEqual(windows.map { $0.count - 44 }.reduce(0, +), take.count - 44)
        // Every cut but the last lands in a silence.
        for w in windows.dropLast() {
            let last = w.subdata(in: (w.count - 2)..<w.count)
            let v = last.withUnsafeBytes { $0.load(as: Int16.self) }
            XCTAssertEqual(v, 0)
        }
    }

    func testShortRemainderStaysWhole() {
        XCTAssertEqual(PronunciationAssessor.windows(ofWAV: wav(seconds: 25)).count, 1)
    }
}
