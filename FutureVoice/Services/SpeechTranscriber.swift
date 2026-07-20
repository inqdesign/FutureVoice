import Foundation
import Speech

/// On-device speech-to-text.
///
/// Phase 1: uses `SFSpeechRecognizer` (iOS 13+) running on-device when supported.
/// iOS 26 `SpeechAnalyzer` (WWDC25) lowers latency further — wire it in as a
/// preferred backend once we're testing on iOS 26 devices. For now this is the
/// portable baseline. A `Whisper API` fallback is intentionally NOT included
/// in the spike — keep one path until we know we need a second.
final class SpeechTranscriber {

    enum TranscribeError: Error, LocalizedError {
        case permissionDenied
        case recognizerUnavailable
        case noResult
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Speech recognition permission denied"
            case .recognizerUnavailable: return "Speech recognizer unavailable for this locale"
            case .noResult: return "No transcription result"
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    /// Requests speech permission. Returns true if authorized.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// Text + per-word timestamps from the recognizer's FINAL pass over a
    /// file. Unlike streaming partials, file-based final segments carry
    /// timestamps solid enough to grade rhythm against — the same property
    /// `LocalAlignment` relies on for the target audio.
    struct ScoringResult {
        let text: String
        let wordTimings: [WordTiming]
    }

    /// Final-quality transcription of a recorded attempt, for SCORING.
    ///
    /// Differs from `transcribe` in exactly the ways scoring accuracy needs:
    ///   - waits for the recognizer's FINAL pass (language-model re-scored),
    ///     never a partial hypothesis
    ///   - does NOT force on-device recognition — Apple's server model is
    ///     markedly better for accented, non-native speech
    ///   - biases recognition toward `contextualStrings` (we know the exact
    ///     sentence the learner tried to say)
    ///   - hard timeout instead of a hangable continuation
    /// Returns nil on any failure — the caller keeps its live transcript.
    static func transcribeForScoring(
        audioURL: URL,
        languageCode: String,
        contextualStrings: [String],
        timeout: TimeInterval = 15
    ) async -> ScoringResult? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: LanguageCatalog.sttLocale(languageCode))),
              recognizer.isAvailable else { return nil }
        recognizer.defaultTaskHint = .dictation

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if !contextualStrings.isEmpty {
            request.contextualStrings = Array(contextualStrings.prefix(100))
        }

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
                    let timings = result.bestTranscription.segments.map { seg in
                        WordTiming(
                            word: seg.substring,
                            startMs: Int(seg.timestamp * 1000),
                            endMs: Int((seg.timestamp + seg.duration) * 1000)
                        )
                    }
                    cont.resume(returning: ScoringResult(
                        text: result.bestTranscription.formattedString,
                        wordTimings: timings
                    ))
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

    /// Transcribes a recorded audio file in the given BCP-47 locale.
    /// - Parameters:
    ///   - audioURL: local file (16kHz mono WAV from `AudioRecorder` works well)
    ///   - languageCode: e.g. "en", "ko", "de"
    func transcribe(audioURL: URL, languageCode: String) async throws -> String {
        let locale = Locale(identifier: LanguageCatalog.sttLocale(languageCode))
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw TranscribeError.recognizerUnavailable
        }
        recognizer.defaultTaskHint = .dictation

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    cont.resume(throwing: TranscribeError.underlying(error))
                    return
                }
                guard let result = result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
