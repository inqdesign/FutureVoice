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
/// Shown on every open while the live voice is an ElevenLabs one
/// (`VoiceMove.isDue`), with no Later: the move is required (2026-10-13).
struct VoiceMoveSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()

    @State private var accentId: String?
    @State private var phase: Phase = .ready
    @State private var error: String?
    /// The voice moved but its accent didn't go on (2026-10-13): the move is
    /// done, so the sheet closes like any done move and says where to pick it.
    @State private var accentMissed = false
    /// Neither this phone nor the server holds the recording (an accent
    /// remix keeps none upstream): only a new recording can move the voice.
    @State private var needsRecording = false
    @State private var rerecording = false
    @EnvironmentObject private var auth: AuthService

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
                            if accentMissed {
                                Text(explain("Pick your accent again in Me → Voice. It didn't go on this time."))
                                    .foregroundStyle(.secondary)
                            }
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
                        Button { rerecording = true } label: {
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
            // Not optional (2026-10-13, founder): every voice moves, so the
            // sheet has no Later and can't be swiped away until it is done.
            .interactiveDismissDisabled(phase != .done)
        }
        .fullScreenCover(isPresented: $rerecording) {
            VoiceCloneOnboardingView(fromSettings: true) {
                rerecording = false
                // A new voice: give it the accent picked above, then let them hear it.
                if VoiceMove.isCartesia(appState.voiceCloneId ?? "") {
                    phase = .working
                    Task {
                        do { try await applyPickedAccent() } catch { accentMissed = true }
                        phase = .done
                        playSample()
                    }
                }
            }
            .environmentObject(appState)
            .environmentObject(auth)
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
                // A retry after the voice already moved must not make a
                // second one: only the accent is left to do.
                if !VoiceMove.isCartesia(appState.voiceCloneId ?? "") {
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
                }
            } catch {
                Analytics.capture("voice_move_failed",
                                  ["reason": String(error.localizedDescription.prefix(200))])
                self.error = explain("Tap it once more. Your voice didn't move this time.")
                phase = .ready
                return
            }
            // The voice has moved. An accent that won't go on is not a failed
            // move: it can be picked again in Me → Voice.
            do {
                try await applyPickedAccent()
            } catch {
                Analytics.capture("voice_move_accent_failed",
                                  ["reason": String(error.localizedDescription.prefix(200))])
                accentMissed = true
            }
            Analytics.capture("voice_move_done", ["accent": accentMissed ? "original" : (accent?.id ?? "original")])
            HapticEngine.success()
            phase = .done
            playSample()
        }
    }

    /// On Cartesia an accent is a setting on the same voice, so saving
    /// "<uuid>:<accent>" is the whole of applying it.
    private func applyPickedAccent() async throws {
        guard let accent = options.first(where: { $0.id == accentId }),
              let newId = appState.voiceCloneId,
              let cartesiaAccent = VoiceMove.cartesiaAccent(accent.id) else { return }
        let accented = try await ElevenLabsClient.shared.saveRemixedVoice(
            generatedVoiceId: "\(newId):\(cartesiaAccent)",
            name: appState.voiceDisplayName,
            voiceDescription: accent.prompt)
        await appState.adoptRemixedVoice(accented, accentId: accent.id, source: "move")
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
        // Every open until the voice has moved: the move is not optional.
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
