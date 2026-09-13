import Foundation

/// What the learner ACTUALLY said in one shadow attempt — the single door
/// every shadow score walks through.
///
/// Shadowing is the one place in the app where a transcript IS a grade. The
/// diff, the score, the coach bullets and the rhythm card are all computed
/// from this text, so a transcriber that drops three words of a five-word line
/// doesn't produce a slightly-off score, it tells the learner they failed at
/// words they said perfectly well. Reported 2026-09-13: "Soak it all in,
/// right?" came back as "So right" — the connected-speech middle
/// (`[soʊkɪɾɔlɪn]`) is exactly what an on-device recognizer collapses, and it
/// happened every attempt.
///
/// Talk left that path long ago (`UtteranceTranscriber`), for the same reason
/// and under the same rule — a correction may never be built on something the
/// TRANSCRIBER chose. Shadow's score was still the last thing in the app
/// resting on Apple's recognizer alone. Three layers now, in order:
///
/// 1. **The audio is levelled first.** A quiet take loses its consonants
///    before any model sees it, and the same normalized file is fed to BOTH
///    readers so they are judging the same thing. Boost-only — a healthy
///    recording is passed through untouched, and the learner's own playback
///    always uses the ORIGINAL file.
/// 2. **The words come from the audio.** Gemini hears the file and writes the
///    line. It is never shown the target sentence — it could only copy it,
///    and a word the model supplies is a mark the learner didn't earn.
/// 3. **The times come from Apple, realigned.** Only the on-device pass
///    produces word timestamps, and `ShadowEngine.analyzeRhythm` demands one
///    timing per word of the SCORED text. So the two passes run concurrently
///    and the recognizer's spans are edit-distance-aligned onto the
///    audio-grounded words (`LocalAlignment`, the same machinery that recovers
///    karaoke timings) — the words a reader sees and the times the rhythm card
///    measures finally describe the same sentence.
enum ShadowTranscriber {

    /// Where the scored text came from. Ranked best → worst; the UI only has
    /// to warn about `rough`.
    enum Source: String {
        /// Gemini read the recorded file. The words are audio-grounded.
        case audioGrounded
        /// Apple's final file pass. A real re-recognition, just a weaker one —
        /// this is what every attempt used to be scored on.
        case onDevice
        /// Nothing read the file: the live recognizer's last PARTIAL
        /// hypothesis, which is systematically worse than either.
        case rough
    }

    struct Reading {
        let text: String
        /// One entry per whitespace-separated word of `text`, in order — the
        /// contract `ShadowEngine.analyzeRhythm` checks. Empty when no timing
        /// could be trusted, which only costs the rhythm card.
        let wordTimings: [WordTiming]
        let source: Source
        /// True when the two readers disagreed about the WORDS. Logged, never
        /// shown: it is the only measure of how often the old path was wrong.
        let readersDisagreed: Bool
    }

    /// - Parameters:
    ///   - audioURL: the attempt's WAV. nil (or unreadable) falls all the way
    ///     back to `liveText`.
    ///   - liveText: the live recognizer's last partial — the floor, never
    ///     preferred over a pass that actually read the file.
    ///   - recognitionHints: `contextualStrings` for the on-device pass only.
    ///     Biasing Apple toward the target is safe because Apple's text is now
    ///     the FALLBACK, and it is what recovers usable timestamps; the
    ///     audio-grounded reader is deliberately kept blind to it.
    static func read(
        audioURL: URL?,
        liveText: String,
        targetLanguage: String,
        recognitionHints: [String]
    ) async -> Reading {
        guard let audioURL, FileManager.default.fileExists(atPath: audioURL.path) else {
            return Reading(text: liveText, wordTimings: [], source: .rough, readersDisagreed: false)
        }

        // Level once, read twice. `peakNormalizedWAV` returns the input URL
        // untouched when the take is already healthy, so the cleanup below
        // must never delete a file it didn't create.
        let levelled = AudioLoudness.peakNormalizedWAV(at: audioURL, targetPeakDBFS: -3)
        defer {
            if levelled != audioURL { try? FileManager.default.removeItem(at: levelled) }
        }

        async let devicePass = SpeechTranscriber.transcribeForScoring(
            audioURL: levelled,
            languageCode: targetLanguage,
            contextualStrings: recognitionHints
        )
        async let audioPass = heard(audioURL: levelled, targetLanguage: targetLanguage)

        let device = await devicePass
        let audio = await audioPass

        let deviceText = device?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let disagreed = !deviceText.isEmpty && audio != nil
            && LocalAlignment.normalized(deviceText) != LocalAlignment.normalized(audio ?? "")

        if let audio {
            let words = Self.words(of: audio)
            return Reading(
                text: audio,
                wordTimings: realigned(words: words, onto: device?.wordTimings ?? []),
                source: .audioGrounded,
                readersDisagreed: disagreed
            )
        }
        if let device, !deviceText.isEmpty {
            return Reading(text: device.text, wordTimings: device.wordTimings,
                           source: .onDevice, readersDisagreed: false)
        }
        return Reading(text: liveText, wordTimings: [], source: .rough, readersDisagreed: false)
    }

    // MARK: - The audio-grounded read

    /// Sends the attempt to Gemini and returns the line it heard, or nil when
    /// the call failed, the model heard no speech, or the file is too big to
    /// send. Every nil leaves the on-device pass in charge — this is an
    /// upgrade, never a requirement.
    private static func heard(audioURL: URL, targetLanguage: String) async -> String? {
        // Raw WAV, not the AAC the talk path uses: a shadow attempt is one
        // short sentence, so the bytes are cheap, and 32 kbps costs exactly
        // the consonant detail this call exists to recover.
        guard let wav = try? Data(contentsOf: audioURL), !wav.isEmpty,
              wav.count <= 3_000_000 else { return nil }

        struct Payload: Decodable { let transcript: String? }
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: prompt(targetLanguage: targetLanguage),
                messages: [.init(role: .user,
                                 content: "Transcribe the attached audio.",
                                 inlineAudio: .init(mimeType: "audio/wav",
                                                    base64Data: wav.base64EncodedString()))],
                // The best brain available, not the cheap tier the live talk
                // path uses. Nobody is waiting to HEAR this one — the learner
                // already waits on scoring and a coach call — and the words it
                // writes are the learner's grade.
                model: .flash36,
                maxTokens: 1024,
                purpose: "transcribe"
            )
            let text = payload.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        } catch {
            return nil
        }
    }

    private static func prompt(targetLanguage: String) -> String {
        let target = LanguageCatalog.englishName(targetLanguage)
        return """
        You transcribe ONE short spoken attempt from a language-learning
        SHADOWING exercise: the speaker listened to a model sentence and said
        it back. Output STRICT JSON only — no prose, no code fences:
        { "transcript": "..." }

        The attached AUDIO is the only source. You are NOT told which sentence
        they were copying, and you must not reconstruct one — write the words
        that are in the audio.

        - "transcript": VERBATIM what the speaker said, in \(target).
          Transcribe as a careful listener who does not know the target
          sentence would: every word you can hear, in the order spoken.
        - The speaker is a LEARNER. Expect a non-native accent, uneven pace, a
          false start, a word held too long, or a sentence that stops
          half-way. Write what is there. Never complete a sentence, never fix
          grammar or word order, never tidy it up.
        - Connected speech swallows short function words — "soak it all in"
          arrives as one run of sound. Those are precisely the words an
          on-device recognizer drops, and the ones you are here to recover.
          Listen through the run and write them.
        - If a word came out as a DIFFERENT word, write the word that was
          actually produced, not the one they were reaching for. This
          transcript is scored, so a word you supply that was never spoken is
          a mark the learner did not earn.
        - Skip filler sounds (uh, um). Add nothing the audio does not contain.
        - If the audio is silent, unintelligible, or not speech, set
          "transcript" to null. Never invent words.
        """
    }

    // MARK: - Times for words they were not measured on

    /// Word timings for `words`, carried over from the on-device pass by
    /// edit-distance alignment: a word the recognizer also heard takes its
    /// real span, and a run it missed shares the gap between its anchored
    /// neighbours. Returns [] when too little anchors to trust — the rhythm
    /// card then stays hidden, which is the existing behavior for an
    /// unreliable pass.
    static func realigned(words: [String], onto device: [WordTiming]) -> [WordTiming] {
        guard !words.isEmpty, !device.isEmpty else { return [] }
        let pairing = LocalAlignment.align(
            expected: words.map(LocalAlignment.normalized),
            heard: device.map { LocalAlignment.normalized($0.word) }
        )
        let anchored = pairing.compactMap { $0 }.count
        guard Double(anchored) / Double(words.count) >= minAnchorRatio else { return [] }
        return LocalAlignment.fill(
            expected: words,
            pairing: pairing,
            heardSpans: device.map { (start: Double($0.startMs) / 1000,
                                      end: Double($0.endMs) / 1000) },
            durationMs: device.last?.endMs ?? 0
        )
    }

    /// Below this share of anchored words the carried-over timeline is mostly
    /// interpolation, and rhythm graded against interpolation is a made-up
    /// number. Same bar `LocalAlignment` holds its own pass to.
    private static let minAnchorRatio = 0.5

    /// The word split `ShadowEngine.tokenSpans` assumes — whitespace only, so
    /// timings and diff tokens index the same stream.
    static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}
