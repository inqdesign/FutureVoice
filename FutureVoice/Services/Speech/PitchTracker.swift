import Accelerate
import Foundation

/// How much the voice's pitch MOVES over a take, in semitones: the one
/// measure of expressiveness that needs no model and works in every language.
///
/// Calibrated 2026-11-07 (Season 2 scoring, founder: 100 = an announcer's
/// read): professional reads span ~11 semitones between their 10th and 90th
/// percentile, ordinary native reads ~9, learners ~6 — the clearest line
/// between a professional and an ordinary native of everything measured
/// (Azure's own scores put the two at the same number). The calibration used
/// Praat's pitch tracker; this one is checked against it on the same files.
///
/// Normalized autocorrelation per 40 ms frame (10 ms hop), 75–500 Hz, a
/// frame voiced when it is loud enough and its best peak is ≥ 0.45 (Praat's
/// voicing threshold). The first peak within 85% of the best is taken, so a
/// period's double (the classic octave-down error) never wins over it.
enum PitchTracker {
    struct Stats: Equatable {
        /// 90th minus 10th percentile of the voiced frames, semitones from
        /// the median.
        var rangeSemitones: Double
        /// Standard deviation, same scale.
        var sdSemitones: Double
        var voicedFrames: Int
    }

    static let floorHz = 75.0
    static let ceilingHz = 500.0
    static let voicingThreshold: Float = 0.45

    /// Per-frame F0 in Hz (0 = unvoiced).
    static func track(_ x: [Float], rate: Double) -> [Double] {
        let frame = Int(0.04 * rate)
        let hop = Int(0.01 * rate)
        let minLag = Int(rate / ceilingHz)
        let maxLag = Int(rate / floorHz)
        guard x.count > frame + maxLag + 1, frame > 0, hop > 0 else { return [] }

        // Loudness gate, relative to the take's loudest frame.
        var peak: Float = 0
        vDSP_maxmgv(x, 1, &peak, vDSP_Length(x.count))
        guard peak > 1e-5 else { return [] }
        // Prefix sums of squares, for each lag's window energy.
        var squares = [Float](repeating: 0, count: x.count)
        vDSP_vsq(x, 1, &squares, 1, vDSP_Length(x.count))
        var prefix = [Double](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + Double(squares[i]) }
        func energy(_ start: Int, _ length: Int) -> Double { prefix[start + length] - prefix[start] }

        let gate = Double(peak * AudioLoudness.speechGateRatio)
        let lags = maxLag - minLag + 1
        var corr = [Float](repeating: 0, count: lags)
        var out: [Double] = []
        var start = 0
        x.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            while start + frame + maxLag < x.count {
                let e0 = energy(start, frame)
                let rms = (e0 / Double(frame)).squareRoot()
                guard rms > gate * 0.5 else { out.append(0); start += hop; continue }
                // corr[k] = Σ x[start+t] · x[start+minLag+k+t], t < frame
                vDSP_conv(base + start + minLag, 1, base + start, 1, &corr, 1,
                          vDSP_Length(lags), vDSP_Length(frame))
                var norm = [Float](repeating: 0, count: lags)
                var best: Float = 0
                for k in 0..<lags {
                    let el = energy(start + minLag + k, frame)
                    let d = (e0 * el).squareRoot()
                    norm[k] = d > 0 ? Float(Double(corr[k]) / d) : 0
                    best = max(best, norm[k])
                }
                guard best >= voicingThreshold else { out.append(0); start += hop; continue }
                // First local maximum within 85% of the best.
                var pick = -1
                for k in 1..<(lags - 1) where norm[k] >= 0.85 * best
                    && norm[k] >= norm[k - 1] && norm[k] >= norm[k + 1] {
                    pick = k; break
                }
                if pick < 0 { out.append(0); start += hop; continue }
                // Parabolic interpolation around the peak.
                let a = norm[pick - 1], b = norm[pick], c = norm[pick + 1]
                let denom = a - 2 * b + c
                let shift = denom != 0 ? Double(0.5 * (a - c) / denom) : 0
                let lag = Double(minLag + pick) + shift
                out.append(lag > 0 ? rate / lag : 0)
                start += hop
            }
        }
        return out
    }

    /// Cleans a track the way a listener hears it: a voiced run shorter than
    /// 30 ms is a click, not a pitch; a frame an octave or more from the
    /// take's median is folded back by octaves (the tracker's octave slips,
    /// which Praat removes with a path search); what is left is smoothed by a
    /// 5-frame median within each run.
    static func cleaned(_ raw: [Double]) -> [Double] {
        var f = raw
        let voiced = f.filter { $0 > 0 }.sorted()
        guard !voiced.isEmpty else { return f }
        let median = voiced[voiced.count / 2]
        for k in f.indices where f[k] > 0 {
            var st = 12 * log2(f[k] / median)
            while st > 9 { st -= 12 }
            while st < -9 { st += 12 }
            f[k] = median * pow(2, st / 12)
        }
        var i = 0
        while i < f.count {
            guard f[i] > 0 else { i += 1; continue }
            var j = i
            while j < f.count && f[j] > 0 { j += 1 }
            if j - i < 3 {
                for k in i..<j { f[k] = 0 }
            } else {
                let run = Array(f[i..<j])
                for k in 0..<run.count {
                    let window = run[max(0, k - 2)..<min(run.count, k + 3)].sorted()
                    f[i + k] = window[window.count / 2]
                }
            }
            i = j
        }
        return f
    }

    /// The take's pitch movement; nil under half a second of voiced frames.
    static func stats(_ x: [Float], rate: Double) -> Stats? {
        let f0 = cleaned(track(x, rate: rate)).filter { $0 > 0 }
        guard f0.count >= 50 else { return nil }
        let sorted = f0.sorted()
        let median = sorted[sorted.count / 2]
        let st = sorted.map { 12 * log2($0 / median) }
        func pct(_ p: Double) -> Double {
            let pos = p * Double(st.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(st.count - 1, lo + 1)
            return st[lo] + (st[hi] - st[lo]) * (pos - Double(lo))
        }
        let mean = st.reduce(0, +) / Double(st.count)
        let sd = (st.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(st.count)).squareRoot()
        return Stats(rangeSemitones: pct(0.9) - pct(0.1), sdSemitones: sd, voicedFrames: f0.count)
    }
}
