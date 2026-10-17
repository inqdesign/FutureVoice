import AVFoundation
import FVDenoise

/// Cleans the voice-clone recording on the phone before it is uploaded
/// (2026-10-15).
///
/// The server used to do this with the previous provider's audio isolation,
/// which lowered a clone's noise floor 6–10 dB; Cartesia has no denoiser.
/// The founder compared, by ear on his own take, that isolation, Apple's
/// Sound Isolation (full, 70%, 50%) and DeepFilterNet3 (full, and
/// capped at 30 dB), and picked DeepFilterNet at 30 dB
/// (`Desktop/beta audio/denoise-free-2026-10-15`). The cap leaves a little of
/// the room in and keeps the texture of the voice, which is what the clone is
/// judged on.
///
/// DeepFilterNet (MIT/Apache-2.0) runs from `native/denoise` — a Rust static
/// library with the model built in, `FVDenoise.xcframework`. Android ships
/// the same library. Free, offline, ~1 s for a minute of audio.
///
/// The take ON DISK is never touched: `VoiceSampleStore` keeps the original,
/// and every re-clone cleans it again. Any failure returns nil and the caller
/// uploads the take as it was.
enum VoiceDenoiser {
    /// How far the noise may be pushed down. Chosen by ear, see above.
    static let attenuationLimitDB: Float = 30

    /// A cleaned copy of the WAV at `url` (48 kHz mono 16-bit), or nil.
    static func cleaned(_ url: URL) -> URL? {
        let rate = Double(fv_denoise_sample_rate())
        guard let samples = readMono(url, sampleRate: rate), !samples.isEmpty else { return nil }
        var out = [Float](repeating: 0, count: samples.count)
        let status = samples.withUnsafeBufferPointer { input in
            out.withUnsafeMutableBufferPointer { output in
                fv_denoise_48k(input.baseAddress, samples.count, output.baseAddress, attenuationLimitDB)
            }
        }
        guard status == 0 else { return nil }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("clone-clean-\(UUID().uuidString).wav")
        return write(out, sampleRate: rate, to: dest) ? dest : nil
    }

    /// The file as mono float samples at `sampleRate`.
    private static func readMono(_ url: URL, sampleRate: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return nil }
        let ratio = sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4096
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, let channel = converted.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }

    /// 16-bit mono WAV, the format the clone upload has always sent.
    private static func write(_ samples: [Float], sampleRate: Double, to url: URL) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let file = try? AVAudioFile(forWriting: url, settings: settings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false) else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return (try? file.write(from: buffer)) != nil
    }
}
