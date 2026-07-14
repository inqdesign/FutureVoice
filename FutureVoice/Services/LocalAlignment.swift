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

    /// One-shot recognition with a hard timeout — a recognizer that never
    /// reports final/error must not hang shadow's prepareAudio forever.
    private static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        timeout: TimeInterval = 15
    ) async -> [SFTranscriptionSegment]? {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let once = Once()

        return await withCheckedContinuation { cont in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if error != nil {
                    if once.claim() { cont.resume(returning: nil) }
                    return
                }
                if let result, result.isFinal, once.claim() {
                    cont.resume(returning: result.bestTranscription.segments)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() {
                    task?.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}
