import SwiftUI

/// The voice "you" speak with in other learners' Find people (2026-10-12):
/// voices from the learner's own country first (`ProfileVoice`), two women
/// and two men where there are that many. Rows inside a host's List section,
/// ▶ to hear one in the language being learned, tap to pick. Nothing is
/// picked for them — the app can't tell a voice's gender from a name.
struct ProfileVoiceRows: View {
    @Binding var selection: String?
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @State private var loadingId: String?
    @State private var playingId: String?

    private var options: [ProfileVoice] { ProfileVoice.options(forNative: appState.nativeLanguage) }

    var body: some View {
        ForEach(options) { voice in
            HStack(spacing: 12) {
                Button { Task { await preview(voice) } } label: {
                    if loadingId == voice.id {
                        ProgressView().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: playingId == voice.id && player.isPlaying ? "stop.circle.fill" : "play.circle")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(voice.name)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: voice.name)
                    Text(voice.gender == .female ? explain("Woman") : explain("Man"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == voice.id {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = voice.id }
        }
        .onDisappear { player.stop() }
    }

    private func preview(_ voice: ProfileVoice) async {
        if playingId == voice.id, player.isPlaying {
            player.stop(); playingId = nil; return
        }
        player.stop()
        playingId = nil
        loadingId = voice.id
        defer { loadingId = nil }
        guard let data = try? await VoicePresetPickerView.previewAudio(
            voiceId: voice.id, language: appState.targetLanguage) else { return }
        playingId = voice.id
        try? player.play(data, source: "voice_preview") { playingId = nil }
    }
}
