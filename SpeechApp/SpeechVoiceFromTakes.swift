import AVFoundation
import SwiftUI

/// The learner's voice, made from a take they already read (2026-11-14,
/// founder: "we don't need a recording session — the user already has all
/// the speech done"). The first "Make it in my voice" opens this sheet: what
/// happens, the consent, and one button. The source is the best-scoring take
/// long enough to clone from, cleaned on the phone like nawana's recording
/// (`AppState.regenerateVoiceClone`).
///
/// Measured before building it, on the founder's own takes (scratch probe,
/// same denoise and levelling as the app): a 16 kHz take at arm's length
/// clones with the same high-band energy as the 44.1 kHz onboarding
/// recording, because the voice model makes the full band itself. How it
/// sounds was left to the founder's ear.
@MainActor
enum VoiceFromTakes {
    /// Shorter than this is too little of a voice to clone from.
    static let minimumSeconds: Double = 20
    /// nawana's recording stops at 90 s; a take is cut there too.
    static let maximumSeconds: Double = 90

    /// The best take to make the voice from: the highest score, then the
    /// longer one, among takes whose audio is still on this phone.
    static func bestTake(in takes: [SpeechTake]) -> SpeechTake? {
        takes
            .filter { $0.durationSeconds >= minimumSeconds }
            .filter { FileManager.default.fileExists(atPath: SpeechStore.mediaURL($0.audioFilename).path) }
            .max { a, b in
                a.metrics.overall != b.metrics.overall
                    ? a.metrics.overall < b.metrics.overall
                    : a.durationSeconds < b.durationSeconds
            }
    }

    /// The take's first `maximumSeconds`, as a WAV of its own. The take
    /// itself is never touched.
    static func clip(of take: SpeechTake) throws -> URL {
        let source = try AVAudioFile(forReading: SpeechStore.mediaURL(take.audioFilename))
        let format = source.processingFormat
        let frames = AVAudioFrameCount(min(Double(source.length), maximumSeconds * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try source.read(into: buffer, frameCount: frames)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-from-take-\(take.id.uuidString).wav")
        try? FileManager.default.removeItem(at: out)
        let file = try AVAudioFile(forWriting: out, settings: source.fileFormat.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try file.write(from: buffer)
        return out
    }
}

struct SpeechVoiceFromTakesSheet: View {
    /// Called with the new voice once it is made.
    var onMade: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var consent = ConsentStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Never pre-ticked: a consent that arrives already agreed is not one.
    @State private var agreed = false
    @State private var making = false
    @State private var failed: String?

    private var take: SpeechTake? { VoiceFromTakes.bestTake(in: store.takes) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hear it in your own voice")
                            .font(.title2.weight(.semibold))
                        Text(take == nil
                             ? "Your voice is made from one of your takes. Read any script for 20 seconds or more first."
                             : "Your voice is made from your best take, so there's nothing to record.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let take {
                    Section("Made from") {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.script(id: take.scriptId)?.title ?? explain("A take"))
                                    .lineLimit(1)
                                Text(SpeechFormat.length(Int(min(take.durationSeconds, VoiceFromTakes.maximumSeconds))))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let tier = MedalTier(score: take.metrics.overall) {
                                MedalBadge(tier: tier, label: "\(take.metrics.overall)", size: 34)
                            } else {
                                Text(verbatim: "\(take.metrics.overall)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // The same disclosure and the same yes as nawana's
                    // recording step: a voice model is a voiceprint (GDPR
                    // Art. 9, BIPA, PIPA), so the consent is separate,
                    // informed and recorded, whatever door it comes through.
                    Section {
                        Label {
                            Text(explain("Your voice model is built by the most trusted service there is, and used for your language practice only."))
                        } icon: {
                            Image(systemName: "person.fill.viewfinder").foregroundStyle(.tint)
                        }
                        Label {
                            Text(explain("Re-record it or delete it whenever you want, and deleting your account deletes it too."))
                        } icon: {
                            Image(systemName: "trash").foregroundStyle(.tint)
                        }
                        if !consent.hasVoiceConsent || !consent.isAgeVerified {
                            Toggle(isOn: $agreed) {
                                Text(explain("I'm \(ConsentStore.minimumAge) or older, and I agree to my recording being used to build my voice model."))
                                    .font(.subheadline)
                            }
                        }
                    } footer: {
                        Link(explain("Privacy Policy"), destination: ConsentStore.privacyURL)
                    }
                    .font(.subheadline)
                }

                if let failed {
                    Section {
                        Text(failed).foregroundStyle(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton { dismiss() }
                        .disabled(making)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if take != nil {
                    Button(action: make) {
                        HStack(spacing: 8) {
                            if making { ProgressView() }
                            Text(making ? "Making your voice…" : "Make my voice")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(making || !canMake)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(making)
    }

    private var canMake: Bool {
        (consent.hasVoiceConsent && consent.isAgeVerified) || agreed
    }

    private func make() {
        guard let take else { return }
        if agreed {
            ConsentStore.shared.confirmAge()
            ConsentStore.shared.recordVoiceConsent()
        }
        making = true
        failed = nil
        Task {
            defer { making = false }
            do {
                let clip = try VoiceFromTakes.clip(of: take)
                defer { try? FileManager.default.removeItem(at: clip) }
                // Kept as the recording a rebuild reads (and synced to the
                // learner's own iCloud with the rest), like nawana's take.
                VoiceSampleStore.shared.save(from: clip)
                try await appState.regenerateVoiceClone(fromSampleAt: clip, scriptLanguage: appState.targetLanguage)
                Analytics.capture("voice_from_take", ["score": take.metrics.overall,
                                                       "seconds": Int(min(take.durationSeconds, VoiceFromTakes.maximumSeconds)),
                                                       "takes": store.takes.count])
                guard let id = appState.voiceCloneId else { return }
                dismiss()
                onMade(id)
            } catch {
                failed = error.localizedDescription
            }
        }
    }
}
