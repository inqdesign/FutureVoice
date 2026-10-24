import AVFoundation
import Foundation

/// How high a voice sits, and which preset sits closest to it (2026-10-24).
///
/// The meet act offers a preset beside the learner's own clone, and the one
/// offered should be the one most like them — a man shouldn't be handed a
/// woman's voice as "yours, but different". Pitch is the one likeness code
/// can measure honestly and cheaply on the phone: the median fundamental
/// frequency of the recording, against the same number for each preset's
/// bundled preview in the target language. It says nothing about timbre, so
/// the screen calls the pick "closest to your voice", never "sounds like you".
///
/// Gender is the slot's (every language keeps the slots' F/M split), so the
/// pick is made inside the gender the pitch points to, then by distance.
enum VoicePitch {
    /// Below this median F0 a voice reads as male. Adult ranges are roughly
    /// 85–180 Hz and 165–255 Hz; the overlap is decided by the nearest preset
    /// anyway, this only picks which two to compare.
    static let maleBelowHz: Double = 165

    /// Median F0 over voiced frames, or nil when too little was voiced to say.
    /// Reads at most `maxSeconds` of audio — a minute of reading says nothing
    /// a fifth of it doesn't.
    static func medianF0(url: URL, maxSeconds: Double = 12) -> Double? {
        guard let (samples, rate) = monoSamples(url: url, maxSeconds: maxSeconds) else { return nil }
        let frame = Int(rate * 0.04)
        let hop = Int(rate * 0.02)
        let minLag = Int(rate / 400)
        let maxLag = Int(rate / 70)
        guard frame > maxLag, samples.count > frame else { return nil }

        // A frame quieter than a tenth of the loudest one is a pause, and a
        // pause has no pitch.
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0 else { return nil }
        let gate = peak * 0.1

        var pitches: [Double] = []
        var start = 0
        while start + frame <= samples.count {
            samples.withUnsafeBufferPointer { buf in
                let x = UnsafeBufferPointer(rebasing: buf[start..<(start + frame)])
                var energy: Float = 0
                var loud: Float = 0
                for v in x { energy += v * v; loud = max(loud, abs(v)) }
                guard loud >= gate, energy > 0 else { return }
                var bestLag = 0
                var best: Float = 0
                for lag in minLag...maxLag {
                    var sum: Float = 0
                    var e2: Float = 0
                    for i in 0..<(frame - lag) {
                        sum += x[i] * x[i + lag]
                        e2 += x[i + lag] * x[i + lag]
                    }
                    let r = sum / max(1e-9, (energy * e2).squareRoot())
                    if r > best { best = r; bestLag = lag }
                }
                // Clearly periodic only: breath and fricatives score low.
                if best > 0.6, bestLag > 0 { pitches.append(rate / Double(bestLag)) }
            }
            start += hop
        }
        guard pitches.count >= 10 else { return nil }
        pitches.sort()
        return pitches[pitches.count / 2]
    }

    /// The preset to offer beside the clone: same gender as the recording,
    /// nearest in pitch. Falls back to the first preset of that gender when a
    /// preview can't be measured.
    static func closestPreset(toPitch own: Double, language: String) -> VoicePreset? {
        let gender = own < maleBelowHz ? "Male" : "Female"
        let candidates = VoicePreset.catalog.filter { $0.gender == gender }
        let measured = candidates.compactMap { preset -> (VoicePreset, Double)? in
            guard let f0 = presetF0(preset.id, language: language) else { return nil }
            return (preset, f0)
        }
        if let nearest = measured.min(by: { abs(log($0.1 / own)) < abs(log($1.1 / own)) }) {
            return nearest.0
        }
        return candidates.first
    }

    private static var presetCache: [String: Double] = [:]
    private static let lock = NSLock()

    /// A preset's median F0 in a language, from its bundled preview.
    static func presetF0(_ id: String, language: String) -> Double? {
        let lang = language.split(separator: "-").first.map(String.init) ?? language
        let key = "\(lang)|\(id)"
        lock.lock()
        if let hit = presetCache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let url = Bundle.main.url(forResource: "preview-\(lang)-\(id)", withExtension: "mp3"),
              let f0 = medianF0(url: url) else { return nil }
        lock.lock(); presetCache[key] = f0; lock.unlock()
        return f0
    }

    private static func monoSamples(url: URL, maxSeconds: Double) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        let count = AVAudioFrameCount(min(Double(file.length), rate * maxSeconds))
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              (try? file.read(into: buffer, frameCount: count)) != nil,
              let channels = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        let chans = Int(format.channelCount)
        // Down to ~16 kHz by averaging: pitch lives far below 8 kHz, and the
        // autocorrelation costs the square of the rate.
        let step = max(1, Int(rate / 16_000))
        var mono = [Float](repeating: 0, count: n / step)
        let scale = 1 / Float(chans * step)
        for c in 0..<chans {
            let ch = channels[c]
            for j in 0..<mono.count {
                var sum: Float = 0
                for k in 0..<step { sum += ch[j * step + k] }
                mono[j] += sum * scale
            }
        }
        return (mono, rate / Double(step))
    }
}
