import Accelerate
import AVFoundation
import XCTest
@testable import FutureVoice

/// Playback loudness matching. The thing these guard is that the CLONE — the
/// only voice that arrives off-target, and therefore the only one this code
/// touches at all — comes out matched to the preset voices without being
/// over-driven on the way.
final class AudioLoudnessTests: XCTestCase {

    private let sampleRate = 44_100

    // MARK: - Signal helpers

    /// A steady tone. Stands in for speech: what matters here is its level and
    /// crest, not its spectrum.
    private func tone(amplitude: Float, seconds: Double, frequency: Double = 200) -> [Float] {
        let n = Int(Double(sampleRate) * seconds)
        return (0..<n).map { i in
            amplitude * sinf(Float(2 * Double.pi * frequency * Double(i) / Double(sampleRate)))
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(Double(sampleRate) * seconds))
    }

    /// Mono float buffer holding `samples`, ready for `normalizeInPlace`.
    private func buffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate),
                                                 channels: 1))
        let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                 frameCapacity: AVAudioFrameCount(samples.count)))
        buf.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(buf.floatChannelData)[0]
        for (i, s) in samples.enumerated() { channel[i] = s }
        return buf
    }

    private func samples(of buf: AVAudioPCMBuffer) throws -> [Float] {
        let channel = try XCTUnwrap(buf.floatChannelData)[0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buf.frameLength)))
    }

    /// Runs the production gain staging and returns the resulting samples,
    /// or nil when it declined to touch the audio.
    private func normalized(_ input: [Float]) throws -> [Float]? {
        let buf = try buffer(input)
        guard AudioLoudness.normalizeInPlace(buf) else { return nil }
        return try samples(of: buf)
    }

    // MARK: - Measurement

    private func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        let sum = s.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float((sum / Double(s.count)).squareRoot())
    }

    private func peak(_ s: [Float]) -> Float { s.map(abs).max() ?? 0 }

    /// Level of the SPEECH only, gated the same way the production code
    /// measures it — silence must not drag the number down.
    private func speechRMS(_ s: [Float]) -> Float {
        let ungated = rms(s)
        let pk = peak(s)
        guard ungated > 1e-6, pk > 1e-6 else { return ungated }
        let gate = pk * AudioLoudness.speechGateRatio
        let voiced = s.filter { abs($0) > gate }
        return voiced.isEmpty ? ungated : rms(voiced)
    }

    private func dB(_ linear: Float) -> Float { 20 * log10(max(linear, 1e-9)) }

    // MARK: - Tests

    /// The measurement the boost ceiling rests on: adding silence must not
    /// change the reported speech level.
    func testSpeechLevelIgnoresSilence() throws {
        let speech = tone(amplitude: 0.05, seconds: 1.0)
        func measure(_ s: [Float]) throws -> Float {
            let buf = try buffer(s)
            let channels = try XCTUnwrap(buf.floatChannelData)
            return AudioLoudness.speechRMS(channels, channelCount: 1,
                                           frames: vDSP_Length(buf.frameLength))
        }
        let bare = try measure(speech)
        let padded = try measure(speech + silence(seconds: 2.0))
        XCTAssertEqual(dB(bare), dB(padded), accuracy: 0.5)
        XCTAssertEqual(dB(padded), dB(speechRMS(speech + silence(seconds: 2.0))), accuracy: 0.5)
        // And it must read HIGHER than the whole-file RMS of the padded
        // signal — that gap is exactly the surplus boost being removed.
        XCTAssertGreaterThan(dB(padded), dB(rms(speech + silence(seconds: 2.0))) + 3)
    }

    /// A preset voice already lands on target. It must come back untouched —
    /// `nil`, meaning "play the original bytes" — so the professionally
    /// mastered voices never get run through this at all.
    func testAudioAlreadyAtTargetIsLeftUntouched() throws {
        let target = pow(10, AudioLoudness.targetRMSdBFS / 20)   // RMS
        let amplitude = target * Float(2.0.squareRoot())          // sine: RMS = A/√2
        XCTAssertNil(try normalized(tone(amplitude: amplitude, seconds: 1.0)))
    }

    /// The clone arrives ~13 dB quiet. It should come back at target, which is
    /// the whole reason this code exists.
    func testQuietAudioIsBroughtUpToTarget() throws {
        let out = try XCTUnwrap(try normalized(tone(amplitude: 0.05, seconds: 1.0)))
        let level = dB(speechRMS(out))
        XCTAssertEqual(level, AudioLoudness.targetRMSdBFS, accuracy: 2.0)
    }

    /// The regression this was written for. TTS output carries a lead-in and
    /// tail of silence, and how much varies line to line. Measured across the
    /// whole file, that silence reads as "quiet" and buys the line a boost its
    /// speech never needed — which is what used to drive the signal into the
    /// limiter and put audible grit on the user's own voice.
    ///
    /// Same speech, very different padding → the SPEECH must land at the same
    /// level. (Measured whole-file, these two legitimately differ; that's not
    /// what's being asserted.)
    func testSilencePaddingDoesNotInflateTheBoost() throws {
        let speech = tone(amplitude: 0.05, seconds: 1.0)
        let a = dB(speechRMS(try XCTUnwrap(try normalized(speech + silence(seconds: 0.2)))))
        let b = dB(speechRMS(try XCTUnwrap(try normalized(speech + silence(seconds: 2.0)))))

        XCTAssertEqual(a, b, accuracy: 1.5,
                       "padding changed the speech level by \(abs(a - b)) dB")
        XCTAssertEqual(a, AudioLoudness.targetRMSdBFS, accuracy: 2.0)
    }

    /// Transients (plosives, consonant attacks) are where a voice's character
    /// lives. They may be kept from clipping, but they must survive as
    /// transients — the limiter is a safety net, not a compressor.
    func testTransientsSurviveWithoutClipping() throws {
        var samples = tone(amplitude: 0.05, seconds: 1.0)
        // Sharp bursts, 8x the body level, every 100 ms.
        for burst in 0..<9 {
            let start = Int(Double(sampleRate) * (0.1 * Double(burst) + 0.05))
            for i in start..<min(start + 100, samples.count) {
                samples[i] = samples[i] * 8
            }
        }
        let inputCrest = peak(samples) / rms(samples)

        let out = try XCTUnwrap(try normalized(samples))
        XCTAssertLessThanOrEqual(peak(out), 1.0, "output must never clip")
        // Most of the crest must remain. The old broadband knee sat inside the
        // normal range of speech and shaved this hard.
        XCTAssertGreaterThan(peak(out) / rms(out), inputCrest * 0.8)
    }

    // MARK: - One rule across both playback paths

    /// The whole point of the unification: a voice must come out at the same
    /// level whether it plays as a decoded file (Watch scenes, drills, replay)
    /// or as a live stream (a Talk turn). Both paths measure the same signal
    /// here and must ask for the same gain.
    func testStreamingAndBufferedPathsAgreeOnGain() throws {
        // A quiet clone, the case the two paths used to disagree most on: the
        // streaming path's old absolute 0.02 floor sat ABOVE most of this
        // signal, so it measured only peaks and barely boosted at all.
        let signal = silence(seconds: 0.3) + tone(amplitude: 0.04, seconds: 1.5)
                     + silence(seconds: 0.4)

        let buffered = try buffer(signal)
        let channels = try XCTUnwrap(buffered.floatChannelData)
        let bufferedSpeech = AudioLoudness.speechRMS(channels, channelCount: 1,
                                                     frames: vDSP_Length(buffered.frameLength))

        var estimator = AudioLoudness.StreamingLevelEstimator()
        // Fed in ~8 KB chunks, the way the network delivers it.
        var offset = 0
        let chunk = 4096
        while offset < signal.count {
            let end = min(offset + chunk, signal.count)
            signal.withUnsafeBufferPointer { buf in
                estimator.accumulate(buf.baseAddress! + offset, count: end - offset)
            }
            offset = end
        }
        let streamedSpeech = try XCTUnwrap(estimator.speechRMS)

        XCTAssertEqual(dB(bufferedSpeech), dB(streamedSpeech), accuracy: 0.5,
                       "the two paths measure the same audio differently")
        XCTAssertEqual(dB(AudioLoudness.gain(forSpeechRMS: bufferedSpeech)),
                       dB(AudioLoudness.gain(forSpeechRMS: streamedSpeech)),
                       accuracy: 0.5)
        // And that shared gain must actually land the speech on target.
        XCTAssertEqual(dB(bufferedSpeech * AudioLoudness.gain(forSpeechRMS: bufferedSpeech)),
                       AudioLoudness.targetRMSdBFS, accuracy: 0.5)
    }

    /// A preset voice is no longer exempt. Its speech sits ABOVE target even
    /// when its whole-file average looks correct, which is what let a preset
    /// counterpart jump out of a scene next to the user's own clone.
    func testLoudVoiceIsBroughtDownToTheSameTarget() throws {
        // Whole-file RMS lands near target, but the speech within it is hot.
        let hot = tone(amplitude: 0.5, seconds: 0.4) + silence(seconds: 1.6)
        let out = try XCTUnwrap(try normalized(hot))
        XCTAssertEqual(dB(speechRMS(out)), AudioLoudness.targetRMSdBFS, accuracy: 2.0)
        XCTAssertLessThan(peak(out), peak(hot), "a hot voice must come down")
    }

    /// Two different voices at very different input levels must converge on
    /// one output level — the clone and the preset in the same scene.
    func testDifferentInputLevelsConvergeOnOneOutputLevel() throws {
        let quiet = try XCTUnwrap(try normalized(tone(amplitude: 0.03, seconds: 1.0)))
        let loud = try XCTUnwrap(try normalized(tone(amplitude: 0.45, seconds: 1.0)))
        XCTAssertEqual(dB(speechRMS(quiet)), dB(speechRMS(loud)), accuracy: 1.0)
    }
}
