import AVFoundation
import Accelerate
import Foundation

/// On-device quality check for a recorded voice-clone sample. Surfaces the few
/// things that actually wreck an ElevenLabs clone: too short, clipping, a noisy
/// room, or a near-silent take. All measured locally — no upload, no API.
struct AudioSampleQuality {
    enum Rating {
        case good, okay, poor

        var label: String {
            switch self {
            case .good: return "Great sample"
            case .okay: return "Usable — could be better"
            case .poor: return "Re-record recommended"
            }
        }
        /// SF Symbol + semantic tint for the summary row.
        var symbol: String {
            switch self {
            case .good: return "checkmark.seal.fill"
            case .okay: return "exclamationmark.circle"
            case .poor: return "exclamationmark.triangle.fill"
            }
        }
    }

    let durationSeconds: Double
    let peakDBFS: Float
    let rmsDBFS: Float
    let clippedPercent: Float
    let estimatedSNRdB: Float
    let issues: [String]
    let rating: Rating

    static func analyze(url: URL) -> AudioSampleQuality? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sr = file.processingFormat.sampleRate
        let total = AVAudioFrameCount(file.length)
        guard total > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: total),
              (try? file.read(into: buf)) != nil,
              let chans = buf.floatChannelData
        else { return nil }

        let n = Int(buf.frameLength)
        guard n > 0 else { return nil }
        let duration = Double(n) / sr
        let x = chans[0]   // recordings are mono; channel 0 is representative

        var peak: Float = 0
        vDSP_maxmgv(x, 1, &peak, vDSP_Length(n))
        var rms: Float = 0
        vDSP_rmsqv(x, 1, &rms, vDSP_Length(n))

        var clipped = 0
        for i in 0..<n where abs(x[i]) >= 0.99 { clipped += 1 }
        let clippedPct = Float(clipped) / Float(n) * 100

        // Frame RMS percentiles → rough noise floor (quiet frames) vs speech
        // (loud frames). Their gap approximates SNR.
        let frameLen = max(1, Int(sr * 0.05))
        var frameDBs: [Float] = []
        var i = 0
        while i + frameLen <= n {
            var r: Float = 0
            vDSP_rmsqv(x + i, 1, &r, vDSP_Length(frameLen))
            frameDBs.append(20 * log10(max(r, 1e-7)))
            i += frameLen
        }
        frameDBs.sort()
        func percentile(_ p: Double) -> Float {
            guard !frameDBs.isEmpty else { return -120 }
            let idx = min(frameDBs.count - 1, max(0, Int(Double(frameDBs.count) * p)))
            return frameDBs[idx]
        }
        let noiseDB = percentile(0.10)
        let signalDB = percentile(0.90)
        let snr = signalDB - noiseDB

        let peakDB = 20 * log10(max(peak, 1e-7))
        let rmsDB = 20 * log10(max(rms, 1e-7))

        var issues: [String] = []
        var rating: Rating = .good
        func demote(to r: Rating) { if r == .poor || rating == .good { rating = r } }

        if duration < 30 {
            issues.append("Too short (\(Int(duration))s) — aim for 60–90s.")
            demote(to: .poor)
        } else if duration < 45 {
            issues.append("A little short — 60–90s clones best.")
            demote(to: .okay)
        }
        if clippedPct > 0.05 || peakDB > -0.3 {
            issues.append("Clipping detected — move a little further from the mic.")
            demote(to: .poor)
        }
        if snr < 14 {
            issues.append("Noisy background — try a quieter spot (a closet works great).")
            demote(to: .poor)
        } else if snr < 22 {
            issues.append("Some background noise — quieter is better.")
            demote(to: .okay)
        }
        if rmsDB < -34 {
            issues.append("Quiet take — we'll boost it, but closer to the mic helps.")
            demote(to: .okay)
        }

        return AudioSampleQuality(
            durationSeconds: duration,
            peakDBFS: peakDB,
            rmsDBFS: rmsDB,
            clippedPercent: clippedPct,
            estimatedSNRdB: snr,
            issues: issues,
            rating: rating
        )
    }
}
