import XCTest
@testable import FutureVoice

/// `RealtimeTalkClient.fluencyStats` is the realtime path's only source of
/// articulation rate — the number Progress bands fluency from and the level
/// assessment reads as hard evidence.
final class RealtimeFluencyTests: XCTestCase {

    private let rate = 16_000.0

    /// Spans of (seconds, amplitude) as 16-bit PCM; amplitude 0 is silence.
    private func pcm(_ spans: [(Double, Double)]) -> Data {
        var data = Data()
        for (seconds, amplitude) in spans {
            for i in 0..<Int(seconds * rate) {
                let v = Int16(amplitude * 32_000 * sin(2 * .pi * 220 * Double(i) / rate))
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    func testVoicedTimeAndOnePause() throws {
        let take = pcm([(1.0, 0.5), (0.6, 0), (1.0, 0.5)])
        let stats = try XCTUnwrap(RealtimeTalkClient.fluencyStats(pcm: take, sampleRate: rate))
        XCTAssertEqual(stats.speakingSeconds, 2.0, accuracy: 0.05)
        XCTAssertEqual(stats.pauseCount, 1)
        XCTAssertEqual(stats.pauseSeconds, 0.6, accuracy: 0.05)
    }

    /// A breath between words is not a pause.
    func testShortGapIsNotAPause() throws {
        let take = pcm([(1.0, 0.5), (0.2, 0), (1.0, 0.5)])
        let stats = try XCTUnwrap(RealtimeTalkClient.fluencyStats(pcm: take, sampleRate: rate))
        XCTAssertEqual(stats.pauseCount, 0)
    }

    /// A room 20 dB under the voice is not speech, in the gap or around it.
    func testRoomNoiseUnderTheVoiceIsNotVoiced() throws {
        let take = pcm([(0.5, 0.05), (1.0, 0.5), (0.8, 0.05), (1.0, 0.5), (0.5, 0.05)])
        let stats = try XCTUnwrap(RealtimeTalkClient.fluencyStats(pcm: take, sampleRate: rate))
        XCTAssertEqual(stats.speakingSeconds, 2.0, accuracy: 0.05)
        XCTAssertEqual(stats.pauseCount, 1)
    }

    func testSilenceHasNoStats() {
        XCTAssertNil(RealtimeTalkClient.fluencyStats(pcm: pcm([(1.0, 0)]), sampleRate: rate))
    }
}
