import Foundation

/// Verbatim transcription of ONE spoken turn from its recorded audio, run as
/// its OWN call so the conversation reply never waits behind it.
///
/// This used to be a `transcript` field on the turn call, with the audio
/// attached to the same request. Measured cost of that arrangement: the reply
/// took 4.1s to start instead of 2.1s — the model has to ingest and transcribe
/// the audio before it can write the reply's first token, and that work sat
/// squarely in the critical path between "learner stops talking" and "fluent
/// self starts talking". Splitting it out makes the two genuinely concurrent:
/// the reply streams to TTS immediately while this call corrects the learner's
/// own line in place a moment later.
///
/// Cheap tier by design — this is dictation, not coaching. It carries no
/// conversation context and no persona, just the audio, the on-device guess,
/// and the rules for when the guess is wrong.
enum UtteranceTranscriber {

    /// - Returns: the verbatim line as heard, or nil when the model declined,
    ///   the call failed, or the result was empty. Callers keep whatever text
    ///   they already had — this is an upgrade, never a requirement.
    static func transcribe(audio: GeminiClient.Message.InlineAudio,
                           asrGuess: String,
                           targetLanguage: String,
                           idempotencyKey: String) async -> String? {
        struct Payload: Decodable { let transcript: String? }
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: prompt(targetLanguage: targetLanguage),
                messages: [.init(role: .user, content: asrGuess, inlineAudio: audio)],
                model: .flashLite31,
                // A turn can run to ~2 minutes (the audio cap) — 300+ words
                // of verbatim dictation, before thinking. At 512 the longest
                // turns truncated, and the failure is SILENT: nil here leaves
                // the raw on-device guess in the bubble, which is then what
                // the summary, drills and profile all learn from.
                maxTokens: 2048,
                purpose: "transcribe",
                idempotencyKey: idempotencyKey
            )
            let text = payload.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        } catch {
            return nil
        }
    }

    /// The audio-vs-ASR rules that used to live in `turnOutputInstruction`.
    /// They moved here with the audio: the turn call no longer hears anything,
    /// so it has no business judging what was said.
    private static func prompt(targetLanguage: String) -> String {
        let target = LanguageCatalog.englishName(targetLanguage)
        return """
        You transcribe one short spoken utterance. Output STRICT JSON only —
        no prose, no code fences: { "transcript": "..." }

        The attached AUDIO is the ground truth. The text in the user message is
        an on-device speech-recognition guess and may contain misheard words —
        it is a hint, nothing more. LISTEN before you write.

        - "transcript": VERBATIM what the speaker actually said, in \(target).
          Keep their exact wording INCLUDING grammar mistakes — this is
          dictation, never correction. Skip filler sounds (uh, um).
        - ASR DROP GUARD: on-device recognition very often clips a short
          function word the speaker clearly said — most of all a
          sentence-initial subject pronoun ("I", "he", "we"). If the audio
          contains a word the guess dropped, put it back.
        - ASR DIGIT GUARD: dictation replaces spoken number words with DIGITS,
          and the digit it picks often READS DIFFERENTLY from what was said.
          Korean has two number systems and the recognizer routinely writes the
          wrong one: the speaker says "한번" and it writes "1번", which reads
          "일번" — a different word, not a spelling of the same one. Same class:
          "한 시" → "1시" ("일시"), "네 명" → "4명" ("사명"). Read EVERY digit
          back aloud in \(target): if that reading is not what the audio says,
          write the words the speaker actually pronounced. Keep a digit only
          when reading it aloud reproduces the audio. The same test applies to
          any homophone substitution.
        - Do not rubber-stamp the guess just because it reads like a plausible
          sentence. A confidently wrong recognition is still wrong: the audio
          decides, every time.
        - If the audio is silent, unintelligible, or not speech, set
          "transcript" to null. Never invent words.
        """
    }
}
