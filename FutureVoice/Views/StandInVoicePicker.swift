import SwiftUI

/// The four preset voices, to pick the one that speaks while the learner's
/// own voice is queued (the account's monthly voices were spent at signup,
/// 2026-10-10). Inline rows rather than `VoicePresetPickerView`'s List, so it
/// sits under the onboarding copy; the preview line and cache are the same.
struct StandInVoicePicker: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @State private var loadingId: String?
    @State private var playingId: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(VoicePreset.catalog.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { Divider() }
                row(preset)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 32)
        .onDisappear { player.stop() }
        #if DEBUG
        // `-standInPreview <index>`: play that row on arrival, for a capture
        // run that can't tap.
        .task {
            let i = UserDefaults.standard.integer(forKey: "standInPreview")
            guard UserDefaults.standard.object(forKey: "standInPreview") != nil,
                  VoicePreset.catalog.indices.contains(i) else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await preview(VoicePreset.catalog[i], restart: true)
        }
        #endif
    }

    private func row(_ preset: VoicePreset) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await preview(preset) }
            } label: {
                if loadingId == preset.id {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    Image(systemName: playingId == preset.id && player.isPlaying
                          ? "stop.circle.fill" : "play.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playingId == preset.id && player.isPlaying
                                ? "Stop preview" : "Preview \(preset.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.displayName)
                Text(preset.caption(in: appState.targetLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.voiceCloneId == preset.id {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.chooseStandInVoice(preset.id)
            Task { await preview(preset, restart: true) }
        }
    }

    /// Picking a row also plays it — the choice is made by ear.
    private func preview(_ preset: VoicePreset, restart: Bool = false) async {
        if !restart, playingId == preset.id, player.isPlaying {
            player.stop()
            playingId = nil
            return
        }
        player.stop()
        playingId = nil
        error = nil
        loadingId = preset.id
        defer { loadingId = nil }
        do {
            let data = try await VoicePresetPickerView.previewAudio(
                voiceId: preset.id, language: appState.targetLanguage)
            playingId = preset.id
            try player.play(data, source: "voice_preview") {
                playingId = nil
            }
        } catch {
            self.error = explain("Couldn't play the sample. Check your connection.")
            playingId = nil
        }
    }
}
