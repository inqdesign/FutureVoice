import SwiftUI
import UIKit

/// A PARKED voice (see `VoiceParking`) comes back at the tap that needs it.
///
/// Founder's call, 2026-10-01, after a returning learner met nothing but
/// paywalls and a silent ring: there is no "your voice is resting" notice
/// anywhere. The two cases a parked voice can be in are answered by what the
/// tap does, not by a sentence explaining it:
/// - **Nothing left to spend** → the paywall, exactly as before (`BillingGate`
///   answers that before this is ever asked).
/// - **Allowed to spend** (free minutes left, or a plan bought since) → the
///   voice is rebuilt from the recording on the phone in front of them
///   ("Recreating your voice"), then the speed and accent are set again —
///   the accent remix died with the old voice — and the call starts the
///   moment they tap Start.
///
/// No recording on the phone (a reinstall, another device) can't be rebuilt
/// here, so that one goes to the "let's make your voice again" screen.
@MainActor
enum VoiceRevival {
    enum Purpose: String { case call, scene }

    private static var showing = false

    /// True when whatever was tapped may start now. Called by `BillingGate`
    /// only after it has decided the account may spend.
    static func ensureVoice(for purpose: Purpose) async -> Bool {
        guard let app = AppState.live, let voiceId = app.voiceCloneId,
              VoiceParking.isParked(voiceId) else { return true }
        guard !showing else { return false }
        // No recording here: one in the learner's iCloud is fetched on the
        // screen itself (`VoiceSampleStore` syncs it); with sync off there is
        // nowhere to fetch from, so straight to recording again.
        let sample = VoiceSampleStore.shared.url
        guard sample != nil || SyncEngine.shared.isEnabled else {
            app.parkedVoiceNeedsRecording()
            return false
        }
        // Presented from UIKit, on top of whatever is up: a launcher can sit
        // in a sheet, and SwiftUI silently drops a cover asked for from
        // underneath one (the same trap `BillingGate.start` documents for the
        // paywall). A full-screen cover, not a sheet — the call follows it.
        guard let top = TopPresenter.top() else { return false }
        showing = true
        defer { showing = false }
        Analytics.capture("voice_revival_shown", ["purpose": purpose.rawValue])
        return await withCheckedContinuation { continuation in
            var host: UIViewController?
            let view = VoiceRevivalView(sample: sample, purpose: purpose) { go in
                Analytics.capture("voice_revival_closed", ["purpose": purpose.rawValue,
                                                            "started": go])
                host?.dismiss(animated: true) { continuation.resume(returning: go) }
            }
            .environmentObject(app)
            .environment(\.locale, Locale(identifier: UILanguage.chromeLanguage))
            let controller = UIHostingController(rootView: view)
            controller.modalPresentationStyle = .fullScreen
            host = controller
            top.present(controller, animated: true)
        }
    }
}

struct VoiceRevivalView: View {
    /// Nil = not on this phone; fetched from iCloud first.
    let sample: URL?
    let purpose: VoiceRevival.Purpose
    /// true = start what was tapped; false = closed.
    let onFinish: (Bool) -> Void

    @EnvironmentObject private var appState: AppState
    @AppStorage(SpeechSpeed.key) private var speechSpeed = SpeechSpeed.default.rawValue
    @StateObject private var player = AudioPlayer()

    private enum Stage: Equatable { case rebuilding, failed(String), tune }
    @State private var stage: Stage = .rebuilding
    @State private var paceTakes: [SpeechSpeed: Data] = [:]
    @State private var paceLoading: SpeechSpeed?
    @State private var accentToPick: VoiceAccent?
    @State private var removingAccent = false
    /// The recording the voice was rebuilt from (fetched, if `sample` was nil).
    @State private var resolvedSample: URL?

    private var paceLine: String {
        VoiceCloneScript.paceSample(for: appState.targetLanguage)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    player.stop()
                    onFinish(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch stage {
            case .rebuilding: rebuilding
            case .failed(let message): failed(message)
            case .tune: tune
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await rebuild() }
        .onChange(of: appState.voiceCloneId) { _, _ in
            // An accent applied from the picker is a new voice: the takes
            // already heard belong to the old one.
            paceTakes = [:]
        }
        .sheet(item: $accentToPick) { accent in
            VoiceAccentSheet(initialAccent: accent)
                .environmentObject(appState)
        }
    }

    // MARK: - Stages

    private var rebuilding: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Recreating your voice")
                .font(.title2.weight(.bold))
            Text("This takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Couldn't make your voice")
                .font(.title2.weight(.bold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                stage = .rebuilding
                Task { await rebuild() }
            } label: {
                Text("Try again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var tune: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your voice is back")
                            .font(.largeTitle.weight(.bold))
                        Text("Set the speed and accent again, then start.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    speedSection
                    accentSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            Button {
                player.stop()
                // The openers were baked for the voice that was parked; make
                // them in this one for the calls after this.
                appState.warmFreeTalkOpeners()
                onFinish(true)
            } label: {
                Text(purpose == .call ? "Start the call" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    /// Same control as the meet act's: a pill selects the rung AND speaks
    /// at it, so the pick is made by ear.
    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speaking speed")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(SpeechSpeed.allCases, id: \.rawValue) { speed in
                    let selected = speechSpeed == speed.rawValue
                    let button = Button { audition(speed) } label: {
                        HStack(spacing: 4) {
                            if paceLoading == speed {
                                ProgressView().controlSize(.mini)
                            } else if selected, player.isPlaying {
                                Image(systemName: "speaker.wave.2.fill").font(.caption2)
                            }
                            Text(speed.label).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    if selected {
                        button.buttonStyle(.borderedProminent)
                    } else {
                        button.buttonStyle(.bordered)
                    }
                }
            }
            // What they are about to hear. Material, so the target language.
            Text(paceLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accentSection: some View {
        let options = VoiceAccentCatalog.options(for: appState.targetLanguage)
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent")
                    .font(.headline)
                HStack(spacing: 6) {
                    // "Original" is a choice on the row again (2026-10-08,
                    // founder: the pills read clearer with the plain voice
                    // among them) — but no longer the default: every clone
                    // arrives remixed, so it is selected only once picked.
                    accentPill(label: "accent.original",
                               selected: appState.voiceAccentId == nil,
                               loading: removingAccent,
                               action: removeAccent)
                    ForEach(options) { option in
                        accentPill(label: LocalizedStringKey(option.label),
                                   selected: appState.voiceAccentId == option.id,
                                   loading: false) {
                            player.stop()
                            accentToPick = option
                        }
                    }
                }
                .disabled(removingAccent)
            }
        }
    }

    @ViewBuilder
    private func accentPill(label: LocalizedStringKey, selected: Bool, loading: Bool,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Group {
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(label)
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        if selected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    // MARK: - Work

    private func rebuild() async {
        #if DEBUG
        // Capture harness: no session, no network — hold the stage asked for.
        if let capture = UserDefaults.standard.string(forKey: "capture"),
           capture.hasPrefix("voice-revival") {
            if capture == "voice-revival-tune" { stage = .tune }
            return
        }
        #endif
        var recording = sample
        if recording == nil { recording = await SyncEngine.shared.fetchVoiceSample() }
        guard let recording else {
            // Nothing in iCloud either: record again.
            onFinish(false)
            appState.parkedVoiceNeedsRecording()
            return
        }
        resolvedSample = recording
        do {
            try await appState.reviveParkedVoice(from: recording)
            HapticEngine.success()
            stage = .tune
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Back to the voice as recorded, after picking an accent here.
    private func removeAccent() {
        guard appState.voiceAccentId != nil, !removingAccent else { return }
        player.stop()
        removingAccent = true
        Task {
            defer { removingAccent = false }
            guard let recording = resolvedSample ?? sample else { return }
            try? await appState.regenerateVoiceClone(fromSampleAt: recording)
        }
    }

    private func audition(_ speed: SpeechSpeed) {
        speechSpeed = speed.rawValue
        HapticEngine.light()
        if let data = paceTakes[speed] {
            player.stop()
            try? player.play(data, forceSessionReset: true)
            return
        }
        guard let voiceId = appState.voiceCloneId else { return }
        paceLoading = speed
        let line = paceLine
        Task {
            let data = try? await ElevenLabsClient.shared.synthesize(
                voiceId: voiceId, text: line,
                modelId: ElevenLabsClient.cloneModelId, purpose: "greeting",
                speed: speed)
            if paceLoading == speed { paceLoading = nil }
            guard let data else { return }
            paceTakes[speed] = data
            guard speechSpeed == speed.rawValue else { return }
            player.stop()
            try? player.play(data, forceSessionReset: true)
        }
    }
}
