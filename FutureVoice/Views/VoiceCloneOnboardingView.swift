import SwiftUI

/// Reads a short script aloud to create the ElevenLabs voice clone.
/// This is the **magic moment** of the app — first time the user hears their
/// own voice speaking fluently in the target language.
struct VoiceCloneOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()

    @State private var status: Status = .idle
    @State private var error: String?

    enum Status: Equatable {
        case idle
        case recording
        case uploading
        case done
    }

    private let cloneScript = """
    Hi. My name is here, and I'm recording this so I can hear myself
    speaking another language with confidence. I'm curious, I'm patient
    with myself, and I want to sound like me — just a more fluent version.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Future Voice")
                    .font(.largeTitle).bold()
                Text("Read this aloud, slowly. About 30 seconds.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(cloneScript)
                    .font(.title3)
                    .lineSpacing(6)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }

            recordButton

            if let error = error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var recordButton: some View {
        Button(action: handleTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 18).fill(tint))
            .foregroundStyle(.white)
        }
        .disabled(status == .uploading)
    }

    private var icon: String {
        switch status {
        case .idle:      return "mic.fill"
        case .recording: return "stop.fill"
        case .uploading: return "arrow.up.circle"
        case .done:      return "checkmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .idle:      return "Start recording"
        case .recording: return "Stop & clone"
        case .uploading: return "Cloning your voice…"
        case .done:      return "Done"
        }
    }

    private var tint: Color {
        switch status {
        case .recording: return .red
        case .uploading: return .gray
        case .done:      return .green
        case .idle:      return .blue
        }
    }

    private func handleTap() {
        Task {
            do {
                switch status {
                case .idle:
                    let granted = await recorder.requestPermission()
                    guard granted else {
                        error = "Microphone access denied. Enable it in Settings."
                        return
                    }
                    error = nil
                    try recorder.start()
                    status = .recording

                case .recording:
                    guard let url = recorder.stop() else { return }
                    status = .uploading
                    let voiceId = try await ElevenLabsClient.shared.cloneVoice(
                        name: "Future Self — \(appState.targetLanguage.uppercased())",
                        sampleAudioURLs: [url]
                    )
                    appState.voiceCloneId = voiceId
                    status = .done

                case .uploading, .done:
                    break
                }
            } catch {
                self.error = error.localizedDescription
                status = .idle
            }
        }
    }
}
