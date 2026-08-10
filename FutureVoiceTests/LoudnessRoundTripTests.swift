import AVFoundation
import XCTest
@testable import FutureVoice

/// `AudioLoudness.normalized` sits on the ONE playback path the first
/// fluent-self line of a call takes (a cache hit decoded by AVAudioPlayer);
/// every later turn streams PCM straight into AVAudioEngine and never touches
/// it. So a duration or rate that changes here — and only here — is exactly
/// what "the first line plays slowly, the rest are fine" looks like.
final class LoudnessRoundTripTests: XCTestCase {

    private func quietWAV(seconds: Double, sampleRate: Int) -> Data {
        let n = Int(Double(sampleRate) * seconds)
        var samples = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let v = 0.05 * sinf(Float(2 * Double.pi * 220 * Double(i) / Double(sampleRate)))
            samples[i] = Int16(v * 32767)
        }
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return AudioLoudness.wavData(fromPCM16: pcm, sampleRate: sampleRate)
    }

    private func probe(_ data: Data, label: String) throws -> (rate: Double, seconds: Double) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString).caf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let f = try AVAudioFile(forReading: url)
        let seconds = Double(f.length) / f.processingFormat.sampleRate
        print("[\(label)] fileRate=\(f.fileFormat.sampleRate) procRate=\(f.processingFormat.sampleRate) frames=\(f.length) seconds=\(seconds)")
        return (f.fileFormat.sampleRate, seconds)
    }

    func testNormalizedPreservesDurationAndRate() throws {
        for rate in [22_050, 24_000, 44_100] {
            let wav = quietWAV(seconds: 2.0, sampleRate: rate)
            let before = try probe(wav, label: "in \(rate)")
            XCTAssertEqual(before.rate, Double(rate), accuracy: 1)
            XCTAssertEqual(before.seconds, 2.0, accuracy: 0.02)

            let normalized = try XCTUnwrap(AudioLoudness.normalized(wav),
                                           "quiet input should be lifted at \(rate)")
            let after = try probe(normalized, label: "out \(rate)")

            XCTAssertEqual(after.rate, Double(rate), accuracy: 1,
                           "sample rate changed at \(rate) — playback speed shifts by that ratio")
            XCTAssertEqual(after.seconds, 2.0, accuracy: 0.02,
                           "duration changed at \(rate)")
        }
    }
}
