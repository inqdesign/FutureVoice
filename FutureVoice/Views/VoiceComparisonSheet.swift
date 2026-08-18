import SwiftUI

/// A/B the recording against the clone built from it.
///
/// Exists because "it doesn't sound like me" was, until now, a question the
/// app asked and gave the learner no way to answer. The meet act played the
/// clone once, then offered "record again?" — so the judgement was made
/// against a memory of their own voice, and a memory of your own voice is the
/// one recording everybody finds strange. Put the two side by side on the
/// SAME sentence and the question answers itself in ten seconds.
///
/// Both sides speak the opening of the script they actually read, so the
/// comparison is like for like. The clone's line is synthesized once and
/// cached in `PhraseAudioStore` under (text, voiceId), so reopening this sheet
/// — or opening it again after a re-record — costs nothing the second time.
struct VoiceComparisonSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// The opening of the script the learner read. Passed in rather than
    /// derived here: only the caller knows whether the take was read in the
    /// native or the target language.
    let scriptOpening: String
    /// Called when they decide the clone isn't them. The caller owns what
    /// happens next (the meet act walks back to the script step).
    var onRerecord: () -> Void

    /// How much of the recording to play. The clone's line is the script's
    /// opening ~120 characters, which lands around ten seconds of speech; the
    /// recording is the same words read at the learner's own pace, so a fixed
    /// window lines the two up closely enough to judge. It never has to be
    /// exact — what's being compared is a voice, not a performance.
    private static let sampleWindow: TimeInterval = 12

    private enum Side { case mine, clone }

    @StateObject private var minePlayer = AudioPlayer()
    @StateObject private var clonePlayer = AudioPlayer()

    @State private var cloneAudio: Data?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                compareSection
                verdictSection
            }
            .navigationTitle("Same words, both voices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { stopAll(); dismiss() }
                }
            }
            .task { await loadCloneLine() }
            .onDisappear { stopAll() }
            .alert("Couldn't play the comparison", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - The two voices

    private var compareSection: some View {
        Section {
            HStack(spacing: 12) {
                sideButton(.mine)
                sideButton(.clone)
            }
            .padding(.vertical, 4)
            Text("\u{201C}\(scriptOpening)\u{201D}")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(explain("Tap one, then the other. Listen for the voice, not the words — everyone finds their own recording strange at first."))
                // The comparison speaks whatever the recording holds, which
                // for a native-script take is NOT the language being learned.
                // That looks like a mismatch and is the whole point: most
                // "this isn't me" comes from hearing yourself in a language
                // you don't own yet, not from a bad clone. Matching here
                // separates the two, so say so rather than leaving the learner
                // to wonder why they're being played Korean.
                if let read = readLanguage, read != targetCode {
                    Text(explain("The recording is in \(LanguageCatalog.learnerName(read)), so the comparison is too. If the two match here, then what sounds unlike you in another language is the language, not the voice."))
                }
            }
        }
    }

    private var readLanguage: String? {
        appState.cloneScriptLanguage.flatMap { LanguageCatalog.language($0)?.code ?? $0 }
    }
    private var targetCode: String {
        LanguageCatalog.language(appState.targetLanguage)?.code ?? appState.targetLanguage
    }

    private func sideButton(_ side: Side) -> some View {
        let isPlaying = playing(side)
        let ready = side == .mine ? sampleData != nil : cloneAudio != nil
        return Button {
            toggle(side)
        } label: {
            VStack(spacing: 8) {
                if side == .clone && loading {
                    ProgressView()
                        .frame(height: 30)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .frame(height: 30)
                }
                Text(side == .mine ? chrome("My recording") : chrome("The made voice"))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(isPlaying ? Color.accentColor : nil)
        .disabled(!ready)
    }

    // MARK: - The decision

    private var verdictSection: some View {
        Section {
            Button {
                stopAll()
                dismiss()
            } label: {
                Label("It's me — keep it", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                stopAll()
                // Dismiss first: the caller walks this screen back to the
                // script step, and a sheet still up over that transition
                // leaves the learner tapping through a stale comparison.
                dismiss()
                onRerecord()
            } label: {
                Label("Not me — record again", systemImage: "mic.fill")
            }
        } footer: {
            Text(explain("Recording again during setup is free, and the voice you have now is only replaced if you keep the new one."))
        }
    }

    // MARK: - Playback

    private var sampleData: Data? { VoiceSampleStore.shared.url.flatMap { try? Data(contentsOf: $0) } }

    private func playing(_ side: Side) -> Bool {
        side == .mine ? minePlayer.isPlaying : clonePlayer.isPlaying
    }

    /// One at a time, always — comparing means alternating, and two voices at
    /// once is just noise.
    private func toggle(_ side: Side) {
        if playing(side) { stopAll(); return }
        stopAll()
        do {
            switch side {
            case .mine:
                guard let data = sampleData else { return }
                minePlayer.prepare(data)
                // The take runs 60–90 s; only its opening is the same words
                // the clone is about to say.
                minePlayer.playSegment(from: 0, to: Self.sampleWindow, loop: false)
            case .clone:
                guard let data = cloneAudio else { return }
                try clonePlayer.play(data, source: "voice_comparison")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopAll() {
        minePlayer.stop()
        clonePlayer.stop()
    }

    /// The clone saying the same opening. Cache first — this sheet is opened
    /// exactly when someone is unsure, which is also when they open it twice.
    private func loadCloneLine() async {
        guard cloneAudio == nil, !loading, let voiceId = appState.voiceCloneId else { return }
        if let cached = PhraseAudioStore.shared.data(text: scriptOpening, voiceId: voiceId) {
            cloneAudio = cached
            return
        }
        loading = true
        defer { loading = false }
        do {
            // The same model the meet act's greeting used. A likeness
            // judgement has to hear the clone at its best, and the result is
            // cached per line, so the fidelity model's higher per-character
            // cost is paid once.
            let data = try await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId, text: scriptOpening,
                modelId: ElevenLabsClient.fidelityModelId, purpose: "voice_comparison")
            _ = PhraseAudioStore.shared.save(data, text: scriptOpening, voiceId: voiceId)
            cloneAudio = data
        } catch {
            self.error = error.localizedDescription
        }
    }
}
