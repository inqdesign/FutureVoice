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
