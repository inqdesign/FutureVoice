import SwiftUI

/// One-time question, the first time a mic surface starts with Bluetooth
/// earphones connected: which mic should record you?
///
/// Framed by SITUATION, not by hardware, and honest in both directions: the
/// phone's mic really is the better microphone (wideband, multi-mic
/// beamforming) and the earphone's really does sound like a phone call. What
/// the earphone buys is POSITION — it is at the mouth no matter where the
/// phone ends up. Which of those matters more is decided entirely by a fact
/// the app cannot see, so the copy asks about that fact and nothing else.
///
/// Shown ONCE (`MicPreferenceStore.hasChosen`) and changeable forever after in
/// Me → Voice. Not repeated per session — see `MicPreferenceStore`.
struct MicChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with the choice; the caller resumes whatever it was starting.
    var onChoose: (MicPreference) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            Image(systemName: "mic.and.signal.meter")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("Which mic?")
                    .font(.title2.weight(.semibold))

                Text(explain("Your phone's mic actually captures more detail — but only if the phone is near you. Your earphone's mic sounds narrower, like a phone call, yet it sits at your mouth wherever you put the phone. Change this any time in Me → Voice."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button {
                    choose(.earphone)
                } label: {
                    Label("Earphone mic", systemImage: "earbuds")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    choose(.phone)
                } label: {
                    Label("Phone mic", systemImage: "iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .presentationDetents([.medium])
        // No interactive dismiss: the caller is waiting on an answer, and a
        // swipe-away would have to invent one. Both buttons are answers.
        .interactiveDismissDisabled()
    }

    private func choose(_ preference: MicPreference) {
        MicPreferenceStore.choose(preference)
        onChoose(preference)
        dismiss()
    }
}
