import SwiftUI

/// Retroactive age check for installs that cloned a voice before the consent
/// step existed — they never pass back through onboarding, so the declaration
/// has to come to them.
///
/// It asks for the AGE and nothing else. The voice consent stays where it
/// belongs, on the clone flow's `.consent` step: someone who already has a
/// working clone would be agreeing to something that already happened, which
/// is a worse kind of consent than none. The age, by contrast, is a fact about
/// the person that is just as true today.
///
/// A sheet, not a full-screen gate, and swipeable away — it re-presents on the
/// next launch instead. An undismissable sheet with no "no" would trap anyone
/// it's meant to stop, and this exists to record a declaration, not to lock a
/// door on a handful of existing beta accounts.
struct AgeCheckSheet: View {
    @ObservedObject private var consent = ConsentStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Starts OFF, always. A pre-ticked age box confirms nothing.
    @State private var declared = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 32)

            Text(explain("One quick thing"))
                .font(.title2.weight(.semibold))

            Text(explain("Your voice model counts as biometric data, so there are rules about who may use the app. We store your answer and nothing else — no birthday, and it's never shown to anyone."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $declared) {
                Text(explain("I'm \(ConsentStore.minimumAge) or older."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                    consent.confirmAge()
                    dismiss()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!declared)

                Link(explain("Privacy Policy"), destination: ConsentStore.privacyURL)
                    .font(.footnote)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
