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
/// at playback: decode, measure the level, apply gain toward a single target.
///
/// ## One rule for every piece of TTS audio
///
/// Every voice, on every surface, through either playback path, lands on the
/// SAME number: `speechRMS` at `targetRMSdBFS`. That single sentence is the
/// contract, and it is deliberately the only one — the app used to hold three
/// different ideas of "correct loudness" at once:
///
///   - the buffered path normalized WHOLE-FILE RMS, so how much silence a line
///     happened to carry changed how loud its speech came out;
///   - the streaming path gated voiced samples at an ABSOLUTE 0.02, which a
///     quiet clone barely crosses — so it measured only the loudest peaks,
///     read the voice as louder than it was, and under-boosted;
///   - anything already near target was passed through untouched, which
///     exempted the preset voices from the rule entirely.
///
/// Three rules meant Talk, Watch and the preset counterpart could each sit at
/// a different level, and no amount of tuning one path could line them up.
/// Both paths now measure with `speechRMS` and convert to gain with
/// `gain(forSpeechRMS:)`; nothing is exempt.
enum AudioLoudness {
    /// Target level for all TTS playback, measured on SPEECH (see `speechRMS`)
    /// rather than whole-file average, so silence can't shift it.
    static let targetRMSdBFS: Float = -16
    /// Never boost more than this — keeps near-silent or pathological inputs
    /// from being amplified into pure noise.
    static let maxBoostDB: Float = 24
    /// Nor cut more than this. Attenuation exists so an already-loud voice
    /// joins the same target instead of being exempt from it; a large cut
    /// would mean the measurement is wrong, not the audio.
    static let maxCutDB: Float = 12
    /// Gains within ±1 dB of unity aren't audible; skip the re-render.
    private static let unityToleranceDB: Float = 1
    /// Peak-limiter knee: samples below this stay LINEAR; only what would
    /// otherwise clip is curved back.
    ///
    /// This used to sit at 0.5, which — against a -16 dBFS target, i.e. an RMS
    /// of ~0.16 — put the knee only ~10 dB above the average level, inside the
    /// normal crest of speech. Every plosive, breath and consonant attack was
    /// tanh-compressed on its way through, and tanh compression is harmonic
    /// distortion: it reads as a "pressed", gritty voice. And it only ever hit
    /// the CLONE, because a preset voice arrives at target and returns early
    /// at the unity-tolerance check — so the one voice that has to sound like
    /// the user was the only one being distorted.
    ///
    /// At 0.85 the curve is a true safety limiter: transients keep their shape
    /// up to ~14.5 dB of crest and only genuine overs are tamed. The original
    /// reason for the stage still holds — a single peak must not pin the whole
    /// phrase's gain (see stage 3) — and that works at any knee.
    private static let softLimitKnee: Float = 0.85
    /// Gate for the speech-level measurement, as a fraction of the signal's
    /// own PEAK: anything more than 20 dB below the loudest moment is silence
    /// or room tone, not speech.
    ///
    /// Relative, so it works at any input level — the absolute 0.02 floor the
    /// streaming path used to apply simply stopped working on a clone quieter
    /// than it, measuring only the peaks and reading the voice as louder than
    /// it was. Relative to PEAK rather than to the mean, because peak is a
    /// running maximum: the streaming path can compute the identical number
    /// on a signal it has only partly received, which is what lets both paths
    /// share one rule instead of approximating each other.
    static let speechGateRatio: Float = 0.1

    /// THE gain rule. Both playback paths convert a measured speech level into
    /// a playback gain through this and nothing else, which is what makes a
    /// clone in Talk, the same clone in Watch, and a preset counterpart in the
    /// same scene all come out at one level.
    static func gain(forSpeechRMS speech: Float) -> Float {
        guard speech > 1e-6 else { return 1 }
        let target = pow(10, targetRMSdBFS / 20)
        return min(max(target / speech, pow(10, -maxCutDB / 20)),
                   pow(10, maxBoostDB / 20))
    }

    /// The container `data` is in, as a file extension.
    ///
    /// This matters more than it looks: `AVAudioFile(forReading:)` trusts the
    /// EXTENSION and picks its parser from it, so a WAV handed to a path that
    /// names its temp file `.mp3` fails to open with
    /// `MPEGAudioFile::OpenFromDataSource failed` — silently, since the caller
    /// just falls back to the un-normalized audio. Everything here used to be
    /// ElevenLabs MP3; the daily call's voicemail arrives as PCM wrapped in
    /// WAV (`wavData(fromPCM16:)`), which is how that assumption got found.
    private static func containerExtension(of data: Data) -> String {
        data.count >= 12 && data.prefix(4).elementsEqual("RIFF".utf8) ? "wav" : "mp3"
    }

    /// Decodes `data` (MP3 or WAV), applies gain so its RMS hits the target
    /// (+ `extraGainDB`, see `AudioSessionRouting.playbackBoostDB`), and
    /// returns the result as CAF data ready for `AVAudioPlayer`.
    /// Sample count and sample rate are unchanged, so karaoke word timings
    /// stay valid and playback speed is untouched.
    /// Returns nil when decoding fails or the audio is already at target —
    /// callers should fall back to playing the original data.
    static func normalized(_ data: Data, extraGainDB: Float = 0) -> Data? {
        let tmpDir = FileManager.default.temporaryDirectory
        let inURL = tmpDir.appendingPathComponent(
            "loudnorm-in-\(UUID().uuidString).\(containerExtension(of: data))")
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

            guard normalizeInPlace(buffer, extraGainDB: extraGainDB) else { return nil }

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

    /// The gain staging itself, applied to `buffer` in place. Split out from
    /// `normalized` so it can be exercised directly on synthesized signals —
    /// the container round-trip around it needs a real encoded file and tests
    /// nothing about the levels.
    ///
    /// Returns false when the audio is already at target (or unmeasurable),
    /// meaning the caller should use the ORIGINAL audio untouched.
    @discardableResult
    static func normalizeInPlace(_ buffer: AVAudioPCMBuffer, extraGainDB: Float = 0) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let channelCount = Int(buffer.format.channelCount)
        let frames = vDSP_Length(buffer.frameLength)
        guard frames > 0 else { return false }

        var peak: Float = 0
        for ch in 0..<channelCount {
            var chPeak: Float = 0
            vDSP_maxmgv(channels[ch], 1, &chPeak, frames)
            peak = max(peak, chPeak)
        }
        guard peak > 0 else { return false }

        // The one rule, on the one measurement. Every voice goes through this,
        // including the presets that used to be waved past because their
        // whole-file average happened to sit near target — their SPEECH sits
        // above it, which is why a preset counterpart could jump out of a
        // scene next to the user's own clone.
        let targetLinear = pow(10, (targetRMSdBFS + extraGainDB) / 20)
        let speech = speechRMS(channels, channelCount: channelCount, frames: frames)
        guard speech > 1e-6 else { return false }
        // A transient peak must never pin the phrase's gain — we go to target
        // and let the limiter below catch whatever that sends over.
        let gain = gain(forSpeechRMS: speech) * pow(10, extraGainDB / 20)

        let gainDB = 20 * log10(gain)
        guard abs(gainDB) > unityToleranceDB else { return false }

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
            // Stage 1: to target.
            var g = gain
            vDSP_vsmul(channels[ch], 1, &g, channels[ch], 1, frames)
            // Stage 2: limit only what is heading for clipping.
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

        // Stage 3: recover whatever level stage 2 took off, clamped so the
        // true peak stays just under full scale.
        //
        // Measured on SPEECH, like stage 1 — and it has to be. Re-measuring
        // the whole file here re-derives the boost from a number the
        // silence dragged down, which silently undid the ceiling above and
        // put the line right back at the inflated level (exactly, to the
        // decibel). With both stages on the same measure, a line that lost
        // nothing to the limiter sees a makeup of ~1 and is left alone.
        var peak2: Float = 0
        for ch in 0..<channelCount {
            var pk: Float = 0
            vDSP_maxmgv(channels[ch], 1, &pk, frames)
            peak2 = max(peak2, pk)
        }
        let speech2 = speechRMS(channels, channelCount: channelCount, frames: frames)
        if speech2 > 1e-6, peak2 > 0 {
            var makeup = min(targetLinear / speech2, 0.985 / peak2)
            if abs(20 * log10(makeup)) > 0.3 {
                for ch in 0..<channelCount {
                    vDSP_vsmul(channels[ch], 1, &makeup, channels[ch], 1, frames)
                }
            }
        }

        return true
    }

    /// RMS of the SPEECH in a buffer, ignoring the silence around and between
    /// words. Two files with identical speech but different amounts of lead-in
    /// silence measure the same here, where a whole-file RMS would not.
    ///
    /// Gate is relative to the file's own ungated level (BS.1770's approach),
    /// so it needs no absolute threshold and travels across voices and rates.
    /// Falls back to the ungated level if the gate would leave nothing.
    static func speechRMS(
        _ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frames: vDSP_Length
    ) -> Float {
        var sumSquares: Float = 0
        var peak: Float = 0
        for ch in 0..<channelCount {
            var r: Float = 0
            var pk: Float = 0
            vDSP_rmsqv(channels[ch], 1, &r, frames)
            vDSP_maxmgv(channels[ch], 1, &pk, frames)
            sumSquares += r * r
            peak = max(peak, pk)
        }
        let ungated = sqrt(sumSquares / Float(channelCount))
        guard ungated > 1e-6, peak > 1e-6 else { return ungated }

        let gate = peak * speechGateRatio
        var gatedSum: Double = 0
        var counted = 0
        let n = Int(frames)
        for ch in 0..<channelCount {
            let p = channels[ch]
            for i in 0..<n where abs(p[i]) > gate {
                gatedSum += Double(p[i]) * Double(p[i])
                counted += 1
            }
        }
        guard counted > 0 else { return ungated }
        return Float((gatedSum / Double(counted)).squareRoot())
    }

    /// The same speech-level measurement as `speechRMS`, computed as the
    /// audio arrives — for the streaming playback path, which never holds the
    /// whole signal. Feeding it every sample of a stream and reading
    /// `speechRMS` at the end yields what `AudioLoudness.speechRMS` would have
    /// returned for that signal, so the two playback paths land on one level.
    struct StreamingLevelEstimator {
        private var peak: Float = 0
        private var voicedSumSquares: Double = 0
        private var voicedSamples: Int = 0
        /// The peak the current accumulation was gated against. The gate rises
        /// with the peak, and samples admitted under an earlier, lower gate
        /// were measured against a different rule — so when the peak moves
        /// materially, the estimate starts over rather than averaging two
        /// rules together. Peaks settle within the first word, so in practice
        /// this happens a couple of times at the very start and then never.
        private var gateBasis: Float = 0
        /// ~0.15 s of voice at any rate we stream, before the estimate is
        /// worth acting on.
        private static let minVoicedSamples = 3_000

        init() {}

        mutating func accumulate(_ samples: UnsafePointer<Float>, count: Int) {
            guard count > 0 else { return }
            for i in 0..<count { peak = max(peak, abs(samples[i])) }
            guard peak > 1e-6 else { return }
            if peak > gateBasis * 2 {
                voicedSumSquares = 0
                voicedSamples = 0
                gateBasis = peak
            }
            let gate = peak * AudioLoudness.speechGateRatio
            for i in 0..<count {
                let a = abs(samples[i])
                if a > gate {
                    voicedSumSquares += Double(a) * Double(a)
                    voicedSamples += 1
                }
            }
        }

        /// nil until enough voiced audio has arrived to trust the number.
        var speechRMS: Float? {
            guard voicedSamples > Self.minVoicedSamples else { return nil }
            return Float((voicedSumSquares / Double(voicedSamples)).squareRoot())
        }

        /// How much voiced audio has been measured so far — lets the AGC
        /// know it is still inside the line's first syllable.
        var voicedCount: Int { voicedSamples }
    }

    /// Wraps raw 16-bit LE mono PCM (streaming TTS output) in a standard WAV
    /// container so the existing MP3-oriented plumbing (AVAudioPlayer replay,
    /// PhraseAudioStore / TurnAudioStore caches) can consume it unchanged —
    /// AVAudioPlayer sniffs the container, file extension doesn't matter.
    static func wavData(fromPCM16 pcm: Data, sampleRate: Int, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var header = Data()
        func append(_ s: String) { header.append(contentsOf: Array(s.utf8)) }
        func appendU32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }

        append("RIFF"); appendU32(UInt32(36 + pcm.count)); append("WAVE")
        append("fmt "); appendU32(16)
        appendU16(1)                              // PCM
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(byteRate))
        appendU16(UInt16(blockAlign))
        appendU16(UInt16(bitsPerSample))
        append("data"); appendU32(UInt32(pcm.count))

        return header + pcm
    }

    /// Decode an on-disk audio file (any AVFoundation-readable container — the
    /// conversation mic capture is `.m4a`/AAC) to a 16 kHz mono 16-bit PCM WAV.
    ///
    /// Why: the user's turn audio is sent to Gemini as ground truth so grammar
    /// scoring reflects what they ACTUALLY said, not the error-prone on-device
    /// STT text. But the raw `.m4a` bytes were being labelled `audio/aac` — a
    /// container/MIME mismatch that can make the model quietly ignore the audio
    /// and fall back to the STT guess (so a clipped word reads as the learner's
    /// grammar mistake). WAV is unambiguous; 16 kHz mono keeps a ~1-minute turn
    /// well under the inline-attachment size cap. Returns nil on any failure —
    /// the caller then sends no audio rather than broken audio.
    static func wav16kMono(fromFileAt url: URL) -> Data? {
        guard let inFile = try? AVAudioFile(forReading: url) else { return nil }
        let inFormat = inFile.processingFormat
        let frameCount = AVAudioFrameCount(inFile.length)
        guard frameCount > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount),
              (try? inFile.read(into: inBuffer)) != nil,
              inBuffer.frameLength > 0 else { return nil }

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: 16_000, channels: 1,
                                            interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return nil }

        let ratio = 16_000.0 / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 4096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else { return nil }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, inStatus in
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return inBuffer
        }
        guard status != .error, convError == nil,
              outBuffer.frameLength > 0,
              let channelData = outBuffer.int16ChannelData else { return nil }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let pcm = Data(bytes: channelData[0], count: byteCount)
        return wavData(fromPCM16: pcm, sampleRate: 16_000, channels: 1)
    }

    /// Same source → AAC-LC wrapped in an ADTS stream (`audio/aac`) at
    /// ~32 kbps — 8–13× smaller than the WAV path, which is the difference
    /// between a turn upload that survives a weak cellular uplink and one
    /// that times out. ADTS is what the `audio/aac` MIME actually names (the
    /// old bug was raw `.m4a` bytes under that label), so the model ingests
    /// it instead of quietly falling back to the STT text. Returns nil on
    /// any failure — callers fall back to `wav16kMono`, then to no audio.
    static func aacADTS16kMono(fromFileAt url: URL) -> Data? {
        // Stage 1: decode + resample to 16 kHz mono float PCM.
        guard let inFile = try? AVAudioFile(forReading: url) else { return nil }
        let inFormat = inFile.processingFormat
        let frameCount = AVAudioFrameCount(inFile.length)
        guard frameCount > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount),
              (try? inFile.read(into: inBuffer)) != nil,
              inBuffer.frameLength > 0 else { return nil }

        guard let pcm16k = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000, channels: 1,
                                         interleaved: false),
              let down = AVAudioConverter(from: inFormat, to: pcm16k) else { return nil }
        let ratio = 16_000.0 / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 4096
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcm16k, frameCapacity: capacity) else { return nil }

        var fedDown = false
        var downError: NSError?
        let downStatus = down.convert(to: pcmBuffer, error: &downError) { _, inStatus in
            if fedDown { inStatus.pointee = .noDataNow; return nil }
            fedDown = true
            inStatus.pointee = .haveData
            return inBuffer
        }
        guard downStatus != .error, downError == nil, pcmBuffer.frameLength > 0 else { return nil }

        // Stage 2: encode AAC-LC and frame each packet with an ADTS header.
        var aacDesc = AudioStreamBasicDescription(
            mSampleRate: 16_000, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        guard let aacFormat = AVAudioFormat(streamDescription: &aacDesc),
              let encoder = AVAudioConverter(from: pcm16k, to: aacFormat) else { return nil }
        encoder.bitRate = 32_000

        var fedPCM = false
        var adts = Data()
        let maxPacket = max(encoder.maximumOutputPacketSize, 768)
        while true {
            let outBuf = AVAudioCompressedBuffer(format: aacFormat,
                                                 packetCapacity: 128,
                                                 maximumPacketSize: maxPacket)
            var encError: NSError?
            let status = encoder.convert(to: outBuf, error: &encError) { _, inStatus in
                if fedPCM { inStatus.pointee = .endOfStream; return nil }
                fedPCM = true
                inStatus.pointee = .haveData
                return pcmBuffer
            }
            guard status != .error, encError == nil else { return nil }
            let packets = Int(outBuf.packetCount)
            if packets > 0, let descs = outBuf.packetDescriptions {
                for i in 0..<packets {
                    let d = descs[i]
                    let size = Int(d.mDataByteSize)
                    guard size > 0 else { continue }
                    adts.append(Self.adtsHeader(payloadSize: size))
                    adts.append(Data(bytes: outBuf.data.advanced(by: Int(d.mStartOffset)),
                                     count: size))
                }
            }
            if status == .endOfStream || packets == 0 { break }
        }
        return adts.isEmpty ? nil : adts
    }

    /// 7-byte ADTS header for one AAC-LC packet: 16 kHz (sampling index 8),
    /// mono (channel config 1), no CRC.
    private static func adtsHeader(payloadSize: Int) -> Data {
        let frameLength = payloadSize + 7
        var h = [UInt8](repeating: 0, count: 7)
        h[0] = 0xFF
        h[1] = 0xF1
        h[2] = 0x60                                            // AAC-LC, freq idx 8
        h[3] = UInt8(0x40 | ((frameLength >> 11) & 0x03))      // chan cfg 1 + len hi
        h[4] = UInt8((frameLength >> 3) & 0xFF)
        h[5] = UInt8(((frameLength & 0x07) << 5) | 0x1F)
        h[6] = 0xFC
        return Data(h)
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
            // Write 16-bit PCM (NOT the buffer's 32-bit float processingFormat).
            // AVAudioFile's processingFormat is always float, so writing with
            // `buffer.format.settings` produced a 32-bit float WAV — ~2x the
            // bytes, which pushed ~1 min takes past ElevenLabs' 11 MB limit.
            // 16-bit/44.1k mono is plenty for IVC and stays well under the cap.
            let outSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ]
            try autoreleasepool {
                let outFile = try AVAudioFile(forWriting: outURL, settings: outSettings)
                try outFile.write(from: buffer)
            }
            return outURL
        } catch {
            return inURL
        }
    }
}
