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
    /// Rebuilding the un-accented voice from the saved recording.
    @State private var removing = false
    @State private var confirmingRemove = false
    @State private var playingId: String?
    @State private var error: String?

    private var options: [VoiceAccent] {
        VoiceAccentCatalog.options(for: appState.targetLanguage)
    }

    /// The accent the live clone was remixed with, if any.
    private var appliedAccent: VoiceAccent? {
        options.first { $0.id == appState.voiceAccentId }
    }

    /// Whether "no accent" is reachable at all.
    ///
    /// Applying an accent REPLACES the clone and deletes the outgoing voice
    /// upstream (`AppState.adoptRemixedVoice`), so there is no id to switch
    /// back to — the only way to un-accent a voice is to build a fresh clone
    /// from the recording. No recording on disk, no way back, so the row
    /// stays hidden rather than offering a dead end.
    private var canRemoveAccent: Bool {
        appState.voiceAccentId != nil && VoiceSampleStore.shared.exists
    }

    var body: some View {
        NavigationStack {
            List {
                accentSection
                if !previews.isEmpty {
                    takesSection
                    applySection
                }
                // LAST, and in a section of its own. It used to sit first in
                // the accent list, where a row reading "no accent" looked like
                // a fourth option to pick rather than the way back — and the
                // way back is the one thing on this screen that can't be
                // undone by tapping something else.
                if canRemoveAccent { removeAccentSection }
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
                // "Cancel", not "Done". Nothing on this screen is committed by
                // leaving it — "Use this voice" applies and dismisses itself,
                // and so does removing — so the only thing this button can
                // mean is "change nothing". Labelled Done, it read as the
                // opposite: after generating takes and tapping one, it looked
                // like the way to confirm the pick, and there was no visible
                // way to back out of an accent at all.
                ToolbarItem(placement: .cancellationAction) {
                    Button(chrome("Cancel")) {
                        player.stop()
                        dismiss()
                    }
                    .disabled(generating || removing)
                }
            }
            // Generating counts too. Remix previews take ~30 s, and for that
            // whole window the sheet used to stay swipe-to-dismissable — on
            // iPad, where it floats and a tap outside closes it, the wait was
            // the easiest moment in the app to throw the work away by accident.
            // Closing mid-generate also loses the request: it is already
            // charged against the daily cap and nothing reattaches to it.
            .interactiveDismissDisabled(generating || saving || removing)
            .alert("Remove the accent?", isPresented: $confirmingRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { removeAccent() }
            } message: {
                Text(explain("Rebuilds your voice from your saved recording, which takes a moment. The accented voice is deleted — audio already made keeps playing."))
            }
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
            if generating {
                Text(explain("Making a few takes — about half a minute. Keep this open."))
            } else {
                Text(explain("Your clone speaks with whatever accent the AI guesses. Pick one instead: same voice, your chosen accent. Takes about half a minute to prepare."))
            }
        }
    }

    /// The way back — its own section so it reads as an action, not an option.
    /// The capability lives here rather than only in Me → Voice because "I
    /// want the accent gone" is decided on this screen; making the learner
    /// leave, hunt through settings and recognize "Regenerate from saved
    /// recording" as the answer was the old, worse version of having it.
    private var removeAccentSection: some View {
        Section {
            Button(role: .destructive) { confirmingRemove = true } label: {
                HStack {
                    Text(chrome("Remove accent"))
                    Spacer()
                    if removing { ProgressView() }
                }
            }
            .disabled(generating || saving || removing)
        } footer: {
            Text(explain("Back to the voice your recording makes on its own."))
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
        .disabled(generating || saving || removing)
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
                // Say it EVERY time. This used to sit behind the same
                // stale-accent guard as the success path, so a remix that
                // failed while the pick had moved on ended with the spinner
                // quietly vanishing and no word about what happened.
                self.error = error.localizedDescription
                // Back to whatever is actually live — dropping to nil would
                // read as "you have no accent" after a failed remix.
                if accent == option { self.accent = appliedAccent }
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

    /// Back to the voice the recording makes on its own. Goes through the
    /// same rebuild Me → Voice uses, which clears `voiceAccentId` as part of
    /// minting an un-remixed clone.
    private func removeAccent() {
        guard let url = VoiceSampleStore.shared.url, !removing else { return }
        player.stop()
        playingId = nil
        removing = true
        Analytics.capture("voice_accent_removed")
        Task {
            defer { removing = false }
            do {
                try await appState.regenerateVoiceClone(fromSampleAt: url)
                HapticEngine.success()
                onApplied?()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
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
