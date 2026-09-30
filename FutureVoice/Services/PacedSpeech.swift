import Foundation

/// A line of more than one sentence, synthesized so the voice BREATHES
/// between them (2026-09-30).
///
/// Reported: "the fluent self doesn't stop between sentences, especially in
/// Korean". Measured on the founder's clone in ko/en/ja/de: ElevenLabs puts
/// 0.08–0.29 s between sentences it is given in one text (one English take
/// had no gap at all), against the 0.5–0.8 s people leave. The live call was
/// fixed in the gateway by sending one sentence per generation
/// (`CallSession.eachSentence`, ~0.35–0.50 s, picked by ear). This is the
/// same result for the lines the APP synthesizes whole — the call's cached
/// opener and the daily-call voicemail.
///
/// Splitting alone does not reproduce it here: over HTTP, `previous_text` /
/// `next_text` conditioning glues the pieces back together (0.09–0.24 s), and
/// without it every clip carries its own 0–0.43 s of edge silence, so a plain
/// join gaps unevenly. So each sentence is synthesized as PCM, its INNER edges
/// are trimmed to the voice, and one fixed gap goes between — the gateway's
/// median, so the opener and the answers after it breathe alike.
/// `<break>` tags are not an option: measured, they add seconds and noise.
enum PacedSpeech {
    /// Silence between two sentences, voice to voice.
    static let sentenceGapSeconds = 0.42
    /// Kept either side of a trimmed edge so a soft onset or a fading
    /// syllable is never clipped.
    static let edgeMarginSeconds = 0.03

    /// Where a sentence ends — the gateway's rule, kept identical
    /// (`CallSession.sentenceEnd`): a terminator followed by whitespace; the
    /// CJK full stops, which take no space, before the next character; never
    /// after a title abbreviation or inside a quote closed by と/って.
    private static let sentenceEnd = try! NSRegularExpression(
        pattern: #"(?<!\b(?:Mr|Mrs|Ms|Dr|St|Prof|Nr|vs|etc|ca|bzw|e\.g|i\.e|z\.B))[.!?…][)"'”’」』]*\s+|[。！？](?:[)"'”’」』]*\s+|(?=[^)"'”’」』\s])|[)"'”’」』]+(?=[^\sとっ)"'”’」』]))"#)

    /// The sentences of `text`, trimmed, empty ones dropped.
    static func sentences(in text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        var start = 0
        for m in sentenceEnd.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let end = m.range.location + m.range.length
            out.append(ns.substring(with: NSRange(location: start, length: end - start)))
            start = end
        }
        out.append(ns.substring(from: start))
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                  .filter { !$0.isEmpty }
    }

    /// Synthesize `text` sentence by sentence and join the takes with
    /// `sentenceGapSeconds` between them. Returns 16-bit mono PCM, or nil
    /// when the text is a single sentence (the caller's ordinary path is
    /// already right) or the server answered in MP3 (an edge deploy with no
    /// streaming — nothing to join; the caller falls back).
    @MainActor
    static func synthesizePCM(voiceId: String, text: String, modelId: String,
                              purpose: String) async throws -> (pcm: Data, sampleRate: Double)? {
        let parts = sentences(in: text)
        guard parts.count > 1 else { return nil }
        var takes: [Data] = []
        var rate: Double = 0
        for part in parts {
            try Task.checkCancellation()
            let audio = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: part, modelId: modelId, purpose: purpose,
                onPCMChunk: { _, _ in })
            guard case .pcm(let pcm, let sampleRate) = audio,
                  rate == 0 || sampleRate == rate else { return nil }
            rate = sampleRate
            takes.append(pcm)
        }
        return (joined(takes, sampleRate: rate), rate)
    }

    /// Join takes: each INNER edge trimmed to its voice (the line's own
    /// start and end are left as synthesized), one fixed gap between.
    static func joined(_ takes: [Data], sampleRate: Double) -> Data {
        let margin = Int(edgeMarginSeconds * sampleRate)
        let gapSamples = max(0, Int(sentenceGapSeconds * sampleRate) - 2 * margin)
        var out = Data()
        for (i, take) in takes.enumerated() {
            let samples = take.count / 2
            guard samples > 0 else { continue }
            let (on, off) = voicedSpan(take, sampleRate: sampleRate) ?? (0, samples)
            let from = i == 0 ? 0 : max(0, on - margin)
            let to = i == takes.count - 1 ? samples : min(samples, off + margin)
            guard to > from else { continue }
            if !out.isEmpty { out.append(Data(count: gapSamples * 2)) }
            out.append(take.subdata(in: from * 2 ..< to * 2))
        }
        return out
    }

    /// First and last sample of speech, read off a 10 ms RMS envelope
    /// against the take's own loudest block (the envelope, not samples —
    /// see `AudioLoudness.firstVoiceOnset` for why). The gate sits well
    /// under the level gate: this cuts silence, and must never eat a soft
    /// consonant.
    static func voicedSpan(_ pcm: Data, sampleRate: Double) -> (Int, Int)? {
        let count = pcm.count / 2
        let block = max(1, Int(sampleRate / 100))
        guard count >= block else { return nil }
        var rms: [Float] = []
        pcm.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            var i = 0
            while i + block <= count {
                var sum: Float = 0
                for j in i ..< i + block { let v = Float(s[j]) / 32768; sum += v * v }
                rms.append((sum / Float(block)).squareRoot())
                i += block
            }
        }
        guard let loudest = rms.max(), loudest > 0 else { return nil }
        let gate = loudest * 0.03
        guard let first = rms.firstIndex(where: { $0 > gate }),
              let last = rms.lastIndex(where: { $0 > gate }) else { return nil }
        return (first * block, (last + 1) * block)
    }
}
