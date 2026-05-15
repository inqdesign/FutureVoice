import SwiftUI

/// First-run screen. User reads a short script aloud so we can create the
/// ElevenLabs voice clone. Native iOS layout: a navigation title, a quoted
/// script in a List/Form, and a single primary action at the bottom.
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
    Hi. I'm recording this so I can hear myself speak another language with confidence. I'm curious, I'm patient with myself, and I want to sound like me — just a more fluent version.
    """

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(cloneScript)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Text("Read this aloud")
                } footer: {
                    Text("About 30 seconds. Speak naturally — pauses are fine.")
                }

                if let error = error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Future Voice")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: handleTap) {
                Label(label, systemImage: icon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
            .disabled(status == .uploading)

            if status == .uploading {
                ProgressView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
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
        case .done:      return .green
        default:         return .accentColor
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
