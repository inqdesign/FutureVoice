import AVFoundation
import XCTest
@testable import FutureVoice

/// The on-phone denoiser (DeepFilterNet via FVDenoise.xcframework) actually
/// runs, keeps the take's length, and pushes down noise where nobody speaks.
final class VoiceDenoiserTests: XCTestCase {
    func testCleansNoiseAndKeepsLength() throws {
        let rate = 44_100.0
        // 1 s of hiss, then 1 s of a voiced-ish tone with the same hiss under it.
        var samples = [Float]()
        var seed: UInt64 = 42
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.06
        }
        for i in 0..<Int(rate * 2) {
            let tone: Float = i >= Int(rate) ? 0.3 * sin(Float(i) * 2 * .pi * 220 / Float(rate)) : 0
            samples.append(tone + noise())
        }
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("denoise-in.wav")
        try write(samples, rate: rate, to: input)

        let out = try XCTUnwrap(VoiceDenoiser.cleaned(input), "denoiser returned nil")
        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(Double(file.length) / 48_000, 2.0, accuracy: 0.02)

        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let ch = buf.floatChannelData![0]
        func rms(_ range: Range<Int>) -> Float {
            sqrt(range.reduce(Float(0)) { $0 + ch[$1] * ch[$1] } / Float(range.count))
        }
        let hissBefore = sqrt(samples[4410..<39690].reduce(Float(0)) { $0 + $1 * $1 } / Float(39690 - 4410))
        let hissAfter = rms(4800..<43200)   // the same stretch, at 48 kHz
        XCTAssertLessThan(hissAfter, hissBefore * 0.5, "noise not reduced: \(hissBefore) → \(hissAfter)")
    }

    private func write(_ samples: [Float], rate: Double, to url: URL) throws {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buf)
    }
}
