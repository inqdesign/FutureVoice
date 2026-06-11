import AVFoundation
import Accelerate
import Foundation

/// Loudness normalization for TTS playback.
///
/// ElevenLabs premade voices (counterpart presets) ship professionally
/// mastered around -16 dBFS RMS. Instant voice clones instead reproduce the
/// loudness of the user's sample recording — typically a phone-mic capture
/// 10+ dB quieter — so in Watch/Conversation the clone voice sounds tiny next
/// to the preset voice. The TTS API exposes no output-gain knob, so we fix it
/// at playback: decode, measure RMS, apply gain toward a single target.
enum AudioLoudness {
    /// Target RMS for all TTS playback, matching ElevenLabs premade mastering.
    static let targetRMSdBFS: Float = -16
    /// Never boost more than this — keeps near-silent or pathological inputs
    /// from being amplified into pure noise.
    static let maxBoostDB: Float = 24
    /// Gains within ±1 dB of unity aren't audible; skip the re-render.
    private static let unityToleranceDB: Float = 1

    /// Decodes `data` (MP3 from ElevenLabs), applies gain so its RMS hits the
    /// target, and returns the result as CAF data ready for `AVAudioPlayer`.
    /// Sample count is unchanged, so karaoke word timings stay valid.
    /// Returns nil when decoding fails or the audio is already at target —
    /// callers should fall back to playing the original data.
    static func normalized(_ data: Data) -> Data? {
        let tmpDir = FileManager.default.temporaryDirectory
        let inURL = tmpDir.appendingPathComponent("loudnorm-in-\(UUID().uuidString).mp3")
        let outURL = tmpDir.appendingPathComponent("loudnorm-out-\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        do {
            try data.write(to: inURL)
            let inFile = try AVAudioFile(forReading: inURL)
            let frameCount = AVAudioFrameCount(inFile.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: inFile.processingFormat,
                                                frameCapacity: frameCount)
            else { return nil }
            try inFile.read(into: buffer)

            guard let channels = buffer.floatChannelData else { return nil }
            let channelCount = Int(buffer.format.channelCount)
            let frames = vDSP_Length(buffer.frameLength)
            guard frames > 0 else { return nil }

            // RMS and peak across all channels.
            var sumSquares: Float = 0
            var peak: Float = 0
            for ch in 0..<channelCount {
                var rms: Float = 0
                var chPeak: Float = 0
                vDSP_rmsqv(channels[ch], 1, &rms, frames)
                vDSP_maxmgv(channels[ch], 1, &chPeak, frames)
                sumSquares += rms * rms
                peak = max(peak, chPeak)
            }
            let rms = sqrt(sumSquares / Float(channelCount))
            guard rms > 1e-6, peak > 0 else { return nil }

            let targetLinear = pow(10, targetRMSdBFS / 20)
            var gain = targetLinear / rms
            gain = min(gain, pow(10, maxBoostDB / 20))
            // Don't clip: cap gain so the peak stays just under full scale.
            gain = min(gain, 0.99 / peak)

            let gainDB = 20 * log10(gain)
            guard abs(gainDB) > unityToleranceDB else { return nil }

            for ch in 0..<channelCount {
                var g = gain
                vDSP_vsmul(channels[ch], 1, &g, channels[ch], 1, frames)
            }

            // Scope the writer so the file is flushed/closed before we read
            // it back (AVAudioFile flushes on deinit).
            try autoreleasepool {
                let outFile = try AVAudioFile(forWriting: outURL,
                                              settings: buffer.format.settings,
                                              commonFormat: buffer.format.commonFormat,
                                              interleaved: buffer.format.isInterleaved)
                try outFile.write(from: buffer)
            }
            return try Data(contentsOf: outURL)
        } catch {
            return nil
        }
    }
}
