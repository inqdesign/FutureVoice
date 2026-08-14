import SwiftUI

/// Accent picker for the cloned voice — pick an accent, audition a few remix
/// takes of your OWN clone speaking with it, keep the one that sounds most
/// like you. Presented from onboarding's meet act (native-language takes,
/// which carry no target-language accent at all) and from Me → Voice.
///
/// Applying replaces the live voice id through the same staged-delete
/// machinery as a re-record; the recorded sample survives on disk, so the
/// original voice is always rebuildable from Me → Voice.
struct VoiceAccentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()

    /// Called after a preview is adopted as the live voice (the presenter may
    /// want to re-speak its greeting in the new voice).
    var onApplied: (() -> Void)? = nil

    @State private var accent: VoiceAccent?
    @State private var previews: [ElevenLabsClient.RemixPreview] = []
    @State private var pickedPreviewId: String?
    @State private var generating = false
    @State private var saving = false
    @State private var playingId: String?
    @State private var error: String?

    private var options: [VoiceAccent] {
        VoiceAccentCatalog.options(for: appState.targetLanguage)
    }

    /// The accent the live clone was remixed with, if any.
    private var appliedAccent: VoiceAccent? {
        options.first { $0.id == appState.voiceAccentId }
    }

    var body: some View {
        NavigationStack {
            List {
                accentSection
                if !previews.isEmpty {
                    takesSection
                    applySection
                }
            }
            .onAppear {
                // Show what's already live. `accent` doubles as "whose takes
                // are on screen", but previews are empty here, so this only
                // checkmarks the applied one.
                if accent == nil { accent = appliedAccent }
            }
            .navigationTitle("Accent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        player.stop()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn't remix your voice", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var accentSection: some View {
        Section {
            ForEach(options) { option in
                accentRow(option)
            }
        } footer: {
            Text(explain("Your clone speaks with whatever accent the AI guesses. Pick one instead: same voice, your chosen accent. Takes about half a minute to prepare."))
        }
    }

    private func accentRow(_ option: VoiceAccent) -> some View {
        Button { choose(option) } label: {
            HStack {
                Text(option.label)
                    .foregroundStyle(.primary)
                Spacer()
                if generating && accent == option {
                    ProgressView()
                } else if accent == option {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(generating || saving)
    }

    private var takesSection: some View {
        Section {
            ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                takeRow(index: index, preview: preview)
            }
        } header: {
            Text("Takes")
        } footer: {
            Text(explain("Listen to each take and keep the one that sounds most like you."))
        }
    }

    private func takeRow(index: Int, preview: ElevenLabsClient.RemixPreview) -> some View {
        let isCurrent = playingId == preview.id && player.isPlaying
        return Button { audition(preview) } label: {
            HStack(spacing: 12) {
                Image(systemName: isCurrent ? "pause.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text("Take \(index + 1)")
                    .foregroundStyle(.primary)
                Spacer()
                if pickedPreviewId == preview.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(saving)
    }

    private var applySection: some View {
        Section {
            Button { apply() } label: {
                HStack {
                    Text("Use this voice")
                    if saving {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(pickedPreviewId == nil || saving)
        } footer: {
            Text(explain("Replaces your current voice. Your recording is kept, so you can rebuild the original anytime from Me → Voice."))
        }
    }

    /// Pick an accent → generate fresh takes for it. Re-tapping the same
    /// accent regenerates: "none of these sound like me" needs a way forward.
    private func choose(_ option: VoiceAccent) {
        guard let voiceId = appState.voiceCloneId else { return }
        player.stop()
        playingId = nil
        accent = option
        previews = []
        pickedPreviewId = nil
        generating = true
        Analytics.capture("voice_accent_previews_requested", ["accent": option.id])
        Task {
            defer { generating = false }
            do {
                let takes = try await ElevenLabsClient.shared.remixVoicePreviews(
                    voiceId: voiceId,
                    voiceDescription: option.prompt,
                    text: VoiceAccentCatalog.sampleText(for: appState.targetLanguage))
                // The user may have tapped another accent while this ran.
                guard accent == option else { return }
                previews = takes
                if takes.isEmpty {
                    error = explain("No takes came back. Please try again.")
                }
            } catch {
                guard accent == option else { return }
                self.error = error.localizedDescription
                // Back to whatever is actually live — dropping to nil would
                // read as "you have no accent" after a failed remix.
                self.accent = appliedAccent
            }
        }
    }

    /// Listening IS selecting — tapping a take plays it and marks it as the
    /// one to keep; the explicit "Use this voice" button does the committing.
    private func audition(_ preview: ElevenLabsClient.RemixPreview) {
        pickedPreviewId = preview.id
        if playingId == preview.id && player.isPlaying {
            player.stop()
            playingId = nil
            return
        }
        player.stop()
        playingId = preview.id
        try? player.play(preview.audio, source: "accent_preview")
    }

    private func apply() {
        guard let accent, let pickedPreviewId else { return }
        player.stop()
        saving = true
        Task {
            defer { saving = false }
            do {
                let newId = try await ElevenLabsClient.shared.saveRemixedVoice(
                    generatedVoiceId: pickedPreviewId,
                    name: appState.voiceDisplayName,
                    voiceDescription: accent.prompt)
                await appState.adoptRemixedVoice(newId, accentId: accent.id)
                HapticEngine.success()
                onApplied?()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
