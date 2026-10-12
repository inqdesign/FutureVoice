import SwiftUI

/// "Your voice is moving to a new engine" — the one-time move from an
/// ElevenLabs clone to a Cartesia one (the sheet names neither — "Learn more" opens the privacy page's processor list) (2026-10-12, founder decision).
///
/// New clones have been made on Cartesia since the same day (the server's
/// `CLONE_PROVIDER`), but a learner who cloned before keeps an ElevenLabs
/// voice until they rebuild it. This sheet is where they agree to the move
/// and do it in one tap: it says the old voice is deleted, lets them keep or
/// pick an accent, then rebuilds from the recording saved on this device —
/// the server clones it on Cartesia — and applies the accent onto the new
/// voice ("<uuid>:<accent>", supabase/functions/_shared/cartesia.ts).
///
/// Shown at most once a day, only while the live voice is an ElevenLabs one
/// (`VoiceMove.isDue`); "Later" just closes it.
struct VoiceMoveSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()

    @State private var accentId: String?
    @State private var phase: Phase = .ready
    @State private var error: String?
    /// Neither this phone nor the server holds the recording (an accent
    /// remix keeps none upstream): only a new recording can move the voice.
    @State private var needsRecording = false
    @State private var confirmingRerecord = false

    private enum Phase { case ready, working, done }

    private var options: [VoiceAccent] {
        VoiceAccentCatalog.options(for: appState.targetLanguage)
    }

    private var hasRecording: Bool { VoiceSampleStore.shared.exists }

    /// The privacy page's "who processes data" section.
    private static var processorsURL: URL {
        URL(string: ConsentStore.privacyURL.absoluteString + "#processors")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tint)
                        Text(phase == .done ? explain("Your new voice is ready")
                                            : explain("Your voice is moving to a new engine"))
                            .font(.title3.weight(.semibold))
                        if phase == .done {
                            Text(explain("From now on your fluent self speaks with your new voice."))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(explain("So you can practice with a voice that sounds more natural and more like you, we're moving your voice to a new voice engine. Replies get faster too."))
                            Text(explain("When it moves, your current voice is deleted and a new one is made from the recording saved on this device. Audio that was already made keeps playing."))
                                .foregroundStyle(.secondary)
                            // Who makes the voice is on the privacy page's
                            // processors list, not named here (founder, 2026-10-12).
                            Link(explain("Learn more"), destination: Self.processorsURL)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if phase != .done, !options.isEmpty {
                    Section("Accent") {
                        accentRow(id: nil, label: "accent.original")
                        ForEach(options) { option in
                            accentRow(id: option.id, label: LocalizedStringKey(option.label))
                        }
                    }
                }

                Section {
                    if phase == .done {
                        Button { playSample() } label: {
                            Label(explain("Hear it"), systemImage: "play.fill")
                        }
                        Button(explain("Done")) { dismiss() }
                    } else if needsRecording {
                        Text(explain("Your original recording isn't kept for this voice. Record for about a minute and your voice moves to the new engine."))
                            .foregroundStyle(.secondary)
                        Button { confirmingRerecord = true } label: {
                            Text(explain("Record again")).fontWeight(.semibold)
                        }
                    } else {
                        Button { move() } label: {
                            HStack {
                                Text(explain("Rebuild with my voice"))
                                    .fontWeight(.semibold)
                                Spacer()
                                if phase == .working { ProgressView() }
                            }
                        }
                        .disabled(phase == .working)
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(explain("Later")) {
                            Analytics.capture("voice_move_later")
                            dismiss()
                        }
                        .disabled(phase == .working)
                    }
                }
            }
            .interactiveDismissDisabled(phase == .working)
            .alert("Re-record your voice?", isPresented: $confirmingRerecord) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    Analytics.capture("voice_move_rerecord")
                    dismiss()
                    appState.resetVoiceClone()   // RootView swaps to the recording
                }
            } message: {
                Text(explain("Your current voice is deleted and you'll record a new one."))
            }
        }
        .onAppear {
            VoiceMove.markShown()
            Analytics.capture("voice_move_shown", ["has_recording": hasRecording])
            // The accent they have; else the one picked in setup (since
            // 2026-10-08 — "as I recorded it" means Original); else the
            // language's default (American / Standard German).
            if let live = appState.voiceAccentId {
                accentId = live
            } else if appState.preferredAccentId == SetupFlowView.noAccent {
                accentId = nil
            } else if let picked = appState.preferredAccentId,
                      options.contains(where: { $0.id == picked }) {
                accentId = picked
            } else {
                accentId = VoiceAccentCatalog.defaultAccent(for: appState.targetLanguage)?.id
            }
        }
    }

    private func accentRow(id: String?, label: LocalizedStringKey) -> some View {
        Button { accentId = id } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if accentId == id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(phase == .working)
    }

    private func move() {
        guard phase != .working else { return }
        phase = .working
        error = nil
        let accent = options.first { $0.id == accentId }
        Analytics.capture("voice_move_started", ["accent": accent?.id ?? "original",
                                                 "from": hasRecording ? "device" : "server"])
        Task {
            do {
                if let url = VoiceSampleStore.shared.url, hasRecording {
                    // The server clones on Cartesia (CLONE_PROVIDER) and the
                    // old voice is staged for deletion like any rebuild.
                    try await appState.regenerateVoiceClone(fromSampleAt: url)
                } else {
                    // No recording here: the server rebuilds from the copy the
                    // old voice was made from — or says there is none.
                    guard let moved = try await ElevenLabsClient.shared.moveVoiceFromServer() else {
                        Analytics.capture("voice_move_no_original")
                        needsRecording = true
                        phase = .ready
                        return
                    }
                    await appState.adoptMovedVoice(moved)
                }
                if let accent, let newId = appState.voiceCloneId,
                   let cartesiaAccent = VoiceMove.cartesiaAccent(accent.id) {
                    // On Cartesia an accent is a setting on the same voice, so
                    // saving "<uuid>:<accent>" is the whole of applying it.
                    let accented = try await ElevenLabsClient.shared.saveRemixedVoice(
                        generatedVoiceId: "\(newId):\(cartesiaAccent)",
                        name: appState.voiceDisplayName,
                        voiceDescription: accent.prompt)
                    await appState.adoptRemixedVoice(accented, accentId: accent.id, source: "move")
                }
                Analytics.capture("voice_move_done", ["accent": accent?.id ?? "original"])
                HapticEngine.success()
                phase = .done
                playSample()
            } catch {
                Analytics.capture("voice_move_failed",
                                  ["reason": String(error.localizedDescription.prefix(200))])
                self.error = error.localizedDescription
                phase = .ready
            }
        }
    }

    private func playSample() {
        guard let voiceId = appState.voiceCloneId else { return }
        let text = VoiceAccentCatalog.sampleText(for: appState.targetLanguage)
        Task {
            guard let data = try? await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId, text: text, purpose: "voice_comparison") else { return }
            try? player.play(data, source: "voice_move", forceSessionReset: true)
        }
    }
}

/// When the move sheet is due, and the accent ids it maps.
enum VoiceMove {
    private static let shownKey = "futurevoice.voiceMove.lastShown"

    /// An ElevenLabs voice (20 alphanumerics), not a Cartesia one (a UUID,
    /// optionally ":accent"), not a stand-in or parked voice, a real account,
    /// and not already shown today.
    @MainActor
    static func isDue(_ appState: AppState, signedIn: Bool) -> Bool {
        guard signedIn, let id = appState.voiceCloneId, !appState.voiceIsStandIn,
              !VoiceParking.isParked(id), !isCartesia(id) else { return false }
        if let last = UserDefaults.standard.object(forKey: shownKey) as? Date,
           Calendar.current.isDateInToday(last) { return false }
        return true
    }

    static func markShown() {
        UserDefaults.standard.set(Date(), forKey: shownKey)
    }

    static func isCartesia(_ id: String) -> Bool {
        id.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(:[a-z-]+)?$"#,
                 options: .regularExpression) != nil
    }

    /// The app's accent ids (`VoiceAccentCatalog`) → Cartesia's.
    static func cartesiaAccent(_ appAccentId: String) -> String? {
        switch appAccentId {
        case "en-US": return "general-american"
        case "en-GB": return "british"
        case "en-AU": return "australian"
        case "de-DE": return "standard-german"
        default: return nil
        }
    }
}
