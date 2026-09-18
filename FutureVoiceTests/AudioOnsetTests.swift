import AVFoundation
import XCTest
@testable import FutureVoice

/// `firstVoiceOnset` is what lines the two takes up in shadow's "both at
/// once", so a wrong answer is audible as a gap in front of one voice.
final class AudioOnsetTests: XCTestCase {

    /// 16 kHz mono WAV: `silence` seconds of digital silence, then a tone.
    private func makeWAV(silence: Double, tone: Double, amplitude: Double = 0.5) throws -> URL {
        let rate = 16_000.0
        var pcm = Data()
        func append(_ sample: Double) {
            let v = Int16(max(-1, min(1, sample)) * 32_000)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        for _ in 0..<Int(silence * rate) { append(0) }
        for i in 0..<Int(tone * rate) {
            append(amplitude * sin(2 * .pi * 220 * Double(i) / rate))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onset-\(UUID().uuidString).wav")
        try AudioLoudness.wavData(fromPCM16: pcm, sampleRate: Int(rate)).write(to: url)
        return url
    }

    func testFindsOnsetAfterLeadingSilence() throws {
        let url = try makeWAV(silence: 0.8, tone: 0.6)
        defer { try? FileManager.default.removeItem(at: url) }
        let onset = try XCTUnwrap(AudioLoudness.firstVoiceOnset(at: url))
        // Reported onset is pulled back slightly so the attack isn't clipped,
        // and must never precede the file.
        XCTAssertEqual(onset, 0.8, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(onset, 0)
    }

    func testQuietTakeIsMeasuredTheSameAsALoudOne() throws {
        let loud = try makeWAV(silence: 0.5, tone: 0.5, amplitude: 0.9)
        let quiet = try makeWAV(silence: 0.5, tone: 0.5, amplitude: 0.05)
        defer {
            try? FileManager.default.removeItem(at: loud)
            try? FileManager.default.removeItem(at: quiet)
        }
        let a = try XCTUnwrap(AudioLoudness.firstVoiceOnset(at: loud))
        let b = try XCTUnwrap(AudioLoudness.firstVoiceOnset(at: quiet))
        XCTAssertEqual(a, b, accuracy: 0.02)
    }

    func testSpeechFromTheFirstSampleReportsZero() throws {
        let url = try makeWAV(silence: 0, tone: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try XCTUnwrap(AudioLoudness.firstVoiceOnset(at: url)), 0, accuracy: 0.01)
    }

    func testSilentFileHasNoOnset() throws {
        let url = try makeWAV(silence: 1.0, tone: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(AudioLoudness.firstVoiceOnset(at: url))
    }
}
