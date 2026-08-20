import SwiftUI

/// The voice clone failed because OUR ElevenLabs plan is out of custom-voice
/// slots (`ElevenLabsError.capacityLimited`) — a ceiling the user neither
/// caused nor can clear. The failure lands at the single moment the whole
/// product is being promised to them, so it must not read as "something went
/// wrong with your voice": it says what actually happened (a rush of new
/// people), that their recording is safe, and that it's already being fixed.
///
/// The owner learns about it in the same instant, from the server side
/// (`supabase/functions/_shared/ops_alert.ts` → Telegram), so "we've been
/// alerted" is a statement of fact, not a comfort line.
///
/// Retry costs the user nothing: the sample was written to
/// `VoiceSampleStore` before the upload, so the caller re-clones from the
/// take they already read.
struct VoiceCapacitySheet: View {
    /// Re-run the clone. Called after the sheet dismisses itself.
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            Image(systemName: "person.2.wave.2")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(spacing: 12) {
                Text(explain("Too many people joined at once"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(explain("Making new voices is full for a moment — nothing you did wrong. We've been alerted and are fixing it right now."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text(explain("Your recording is safely saved. You won't have to read it again."))
                } icon: {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                }
                Label {
                    Text(explain("Try again in a few minutes."))
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Button {
                    dismiss()
                    onRetry()
                } label: {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now") { dismiss() }
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 32)
        .presentationDetents([.medium, .large])
    }
}
