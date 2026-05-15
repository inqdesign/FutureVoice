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

    /// Transcribes a recorded audio file in the given BCP-47 locale.
    /// - Parameters:
    ///   - audioURL: local file (16kHz mono WAV from `AudioRecorder` works well)
    ///   - languageCode: e.g. "en", "ko", "de"
    func transcribe(audioURL: URL, languageCode: String) async throws -> String {
        let locale = Locale(identifier: languageCode)
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
