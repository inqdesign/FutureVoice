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
    /// Saturation knee: samples below this stay linear; above it they're
    /// compressed to tame peaks / crest factor before the makeup-gain stage.
    /// Lower = more compression (peaky clones get denser, so they read as loud
    /// as the preset voices after makeup).
    private static let softLimitKnee: Float = 0.5

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
            // Cap the absolute boost, but DON'T let one transient peak hold the
            // whole phrase down. The old `min(gain, 0.99/peak)` cap was why
            // instant voice clones (quiet RMS, occasional peaks) stayed far
            // below the preset voices — a single peak pinned the gain. Instead
            // we boost to target, then soft-limit so nothing hard-clips.
            gain = min(gain, pow(10, maxBoostDB / 20))

            let gainDB = 20 * log10(gain)
            guard abs(gainDB) > unityToleranceDB else { return nil }

            // Two voices at the SAME RMS still sound unequal when their crest
            // factors differ — a peaky clone reads quieter than a dense preset.
            // So: (1) boost to target, (2) soft-saturate to tame the peaks /
            // crest, (3) makeup-gain back to target with a hard peak ceiling.
            // Stage 2 lets stage 3 actually reach target instead of being held
            // down by one transient, so every phrase lands at a consistent
            // perceived loudness. Sample count is unchanged → timings valid.
            let knee = Self.softLimitKnee
            let kneeRange = 1 - knee
            let intFrames = Int(buffer.frameLength)
            for ch in 0..<channelCount {
                // Stage 1: boost.
                var g = gain
                vDSP_vsmul(channels[ch], 1, &g, channels[ch], 1, frames)
                // Stage 2: soft-saturate everything above the knee.
                let p = channels[ch]
                for n in 0..<intFrames {
                    let x = p[n]
                    let a = abs(x)
                    if a > knee {
                        let comp = knee + kneeRange * tanhf((a - knee) / kneeRange)
                        p[n] = x < 0 ? -comp : comp
                    }
                }
            }

            // Stage 3: re-measure and apply makeup gain back toward target,
            // clamped so the true peak stays just under full scale.
            var rms2Sq: Float = 0
            var peak2: Float = 0
            for ch in 0..<channelCount {
                var r: Float = 0, pk: Float = 0
                vDSP_rmsqv(channels[ch], 1, &r, frames)
                vDSP_maxmgv(channels[ch], 1, &pk, frames)
                rms2Sq += r * r
                peak2 = max(peak2, pk)
            }
            let rms2 = sqrt(rms2Sq / Float(channelCount))
            if rms2 > 1e-6, peak2 > 0 {
                var makeup = min(targetLinear / rms2, 0.985 / peak2)
                if abs(20 * log10(makeup)) > 0.3 {
                    for ch in 0..<channelCount {
                        vDSP_vsmul(channels[ch], 1, &makeup, channels[ch], 1, frames)
                    }
                }
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

    /// Peak-normalizes a recorded voice-clone WAV to near full scale BEFORE it
    /// is uploaded to ElevenLabs. IVC reproduces the loudness of its sample, so
    /// a quiet phone-mic take (often -26 to -34 dBFS) yields a quiet clone that
    /// every playback then has to claw back up. A clean peak-normalize (pure
    /// gain, no compression) raises the source level without coloring the
    /// voice, so the clone comes back loud from ElevenLabs. Only boosts; never
    /// attenuates an already-healthy take. Returns a new WAV URL, or the
    /// original on any failure (callers can always fall back to it).
    static func peakNormalizedWAV(at inURL: URL, targetPeakDBFS: Float = -1) -> URL {
        do {
            let inFile = try AVAudioFile(forReading: inURL)
            let frameCount = AVAudioFrameCount(inFile.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: inFile.processingFormat,
                                                frameCapacity: frameCount)
            else { return inURL }
            try inFile.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return inURL }
            let channelCount = Int(buffer.format.channelCount)
            let frames = vDSP_Length(buffer.frameLength)
            guard frames > 0 else { return inURL }

            var peak: Float = 0
            for ch in 0..<channelCount {
                var p: Float = 0
                vDSP_maxmgv(channels[ch], 1, &p, frames)
                peak = max(peak, p)
            }
            guard peak > 1e-5 else { return inURL }

            let targetLinear = pow(10, targetPeakDBFS / 20)
            var gain = targetLinear / peak
            // Boost-only, capped — a clean recording near full scale is left
            // alone; a very quiet one is lifted up to +30 dB.
            guard gain > 1.01 else { return inURL }
            gain = min(gain, pow(10, 30 / 20))
            for ch in 0..<channelCount {
                var g = gain
                vDSP_vsmul(channels[ch], 1, &g, channels[ch], 1, frames)
            }

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("clonesample-\(UUID().uuidString).wav")
            try autoreleasepool {
                let outFile = try AVAudioFile(forWriting: outURL,
                                              settings: buffer.format.settings,
                                              commonFormat: buffer.format.commonFormat,
                                              interleaved: buffer.format.isInterleaved)
                try outFile.write(from: buffer)
            }
            return outURL
        } catch {
            return inURL
        }
    }
}
