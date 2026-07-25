import Foundation
import Speech

/// Free, on-device word-timing extraction for audio we already have on disk.
///
/// Shadow needs a word → time map for karaoke and word-tap looping. The paid
/// path gets it from ElevenLabs' with-timestamps synthesis; but for lines
/// whose audio is already cached (every conversation turn — the streaming
/// TTS returns no timestamps) we can recover the same map locally by running
/// Apple's speech recognizer over the file and reading per-word segment
/// timestamps. Zero credits, and on-device where the hardware supports it.
///
/// Accuracy guard: we only trust the result when the recognizer found the
/// SAME number of words as the target text — then we keep the recognized
/// times but display the target's own words (punctuation intact). On any
/// mismatch we return [] and the caller falls back to time-based looping,
/// which never shows wrong words to the learner.
enum LocalAlignment {

    static func wordTimings(
        audioURL: URL,
        languageCode: String,
        expectedText: String
    ) async -> [WordTiming] {
        guard await SpeechTranscriber.requestPermission() else { return [] }
        let locale = Locale(identifier: languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else { return [] }

        let expected = tokens(of: expectedText)
        guard !expected.isEmpty else { return [] }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // Bias recognition toward the words we KNOW are in the audio.
        request.contextualStrings = expected

        let segments = await recognize(recognizer: recognizer, request: request)
        guard let segments, segments.count == expected.count else { return [] }

        return zip(expected, segments).map { word, seg in
            WordTiming(
                word: word,
                startMs: Int(seg.timestamp * 1000),
                endMs: Int((seg.timestamp + seg.duration) * 1000)
            )
        }
    }

    /// One-shot recognition with a hard timeout AND cooperative cancellation —
    /// a recognizer that never reports final/error must not hang, and when the
    /// caller's Task is cancelled (e.g. the learner starts a live mic session,
    /// which must not run a SECOND speech recognizer concurrently) the
    /// underlying `SFSpeechRecognitionTask` is actually stopped, not just
    /// abandoned mid-flight.
    private static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        timeout: TimeInterval = 15
    ) async -> [SFTranscriptionSegment]? {
        final class Holder: @unchecked Sendable {
            let lock = NSLock()
            private var done = false
            var task: SFSpeechRecognitionTask?
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let holder = Holder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<[SFTranscriptionSegment]?, Never>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if error != nil {
                        if holder.claim() { cont.resume(returning: nil) }
                        return
                    }
                    if let result, result.isFinal, holder.claim() {
                        cont.resume(returning: result.bestTranscription.segments)
                    }
                }
                holder.lock.lock(); holder.task = task; holder.lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if holder.claim() {
                        task.cancel()
                        cont.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            // Stop the file recognizer so it can't collide with a live mic
            // session. Its error callback then resumes the continuation.
            holder.lock.lock(); let t = holder.task; holder.lock.unlock()
            t?.cancel()
        }
    }

    private static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}
