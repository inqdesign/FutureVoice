import SwiftUI

/// What the learner may change WITHOUT leaving a running call.
///
/// Until this existed the call screen had exactly one control — the mic pill,
/// which hangs up — so every question a learner has mid-call ("too fast",
/// "stop correcting me", "I want to just listen") could only be answered by
/// ending the call and walking into Me. A phone call you cannot adjust while
/// it is running is the one shape a phone call never has.
///
/// Three of the four are pure screen state. The fourth, `SpeechSpeed`, is the
/// SAME global setting Me → Voice holds, reached from here as well — not a
/// per-call copy. A learner who slows the voice down in the middle of a call
/// means it, and a second speed that reverts when they hang up would be a
/// setting that lies.
///
/// All of them persist. A preference re-asked on every call is not a
/// preference, and the two that hide things (subtitles, corrections) are
/// exactly the ones a learner turns off once and wants to stay off.
enum CallSettings {
    /// The turn bubbles and the live partial. Off = a screen with no words on
    /// it, which is what a phone call looks like.
    static let showsTranscriptKey  = "futurevoice.call.showsTranscript"
    /// The correction card under the learner's own lines.
    static let showsCorrectionsKey = "futurevoice.call.showsCorrections"
    /// The pinned row of words to spend in this call (`TalkGoalChipsRow`).
    static let showsGoalChipsKey   = "futurevoice.call.showsGoalChips"

    static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// The call's own settings, on a sheet that does not interrupt the call.
///
/// It sits at a `.medium` detent with background interaction ON, so the line
/// stays live underneath and the learner can keep talking with this open —
/// a settings screen that silences the call would be answering "it's too
/// fast" by stopping the thing that is too fast.
struct CallSettingsSheet: View {
    /// Fired when the rung moves. The caller pushes it to the gateway; the
    /// line PLAYING now keeps the speed it was synthesized at, because
    /// ElevenLabs takes `voice_settings` once per context and a context is
    /// one spoken line.
    var onSpeedChange: (SpeechSpeed) -> Void

    @AppStorage(SpeechSpeed.key) private var speechSpeed = SpeechSpeed.default.rawValue
    @AppStorage(CallSettings.showsTranscriptKey) private var showsTranscript = true
    @AppStorage(CallSettings.showsCorrectionsKey) private var showsCorrections = true
    @AppStorage(CallSettings.showsGoalChipsKey) private var showsGoalChips = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The same control as Me → Voice, deliberately: one
                    // setting, two doors. Menu style (not segmented) so the
                    // rung names are never truncated — they are words, and
                    // they are longer in every language but English.
                    Picker(selection: $speechSpeed) {
                        ForEach(SpeechSpeed.allCases, id: \.rawValue) { speed in
                            Text(speed.label).tag(speed.rawValue)
                        }
                    } label: {
                        Label("Speaking speed", systemImage: "speedometer")
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text(explain("Applies from the next thing your future self says."))
                }

                Section {
                    Toggle(isOn: $showsTranscript) {
                        Label("Subtitles", systemImage: "captions.bubble")
                    }
                    // A toggle that does nothing is worse than no toggle, so
                    // with the transcript off this row is replaced by the
                    // reason rather than disabled: the correction card lives
                    // inside the learner's own bubble and goes where it goes.
                    if showsTranscript {
                        Toggle(isOn: $showsCorrections) {
                            Label("Corrections", systemImage: "sparkles")
                        }
                    } else {
                        Text(explain("Corrections sit inside your own lines, so they're hidden too."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Toggle(isOn: $showsGoalChips) {
                        Label("Words to use", systemImage: "text.badge.checkmark")
                    }
                } header: {
                    Text("Screen")
                } footer: {
                    // The one thing that makes hiding SAFE — and it is true:
                    // the summary, the drill cards and the talk's book are
                    // built from the turns, never from what was on screen.
                    Text(explain("Nothing you hide is lost — your talk's book keeps every correction."))
                }
            }
            .navigationTitle("Call settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // The call keeps running and stays tappable underneath — the mic pill
        // included, so this sheet can never be the reason a call can't be
        // hung up.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onChange(of: speechSpeed) { _, new in
            onSpeedChange(SpeechSpeed(rawValue: new) ?? .default)
        }
    }
}
