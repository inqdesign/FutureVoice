import SwiftUI

/// The second device, when the FIRST one never turned sync on.
///
/// `SyncContinuePromptView` can only appear once a CloudKit zone exists, and
/// the toggle that creates it lives on the device the learner has been using
/// — so the opt-in sits on device one while the moment anybody needs it
/// happens on device two. Without this screen that install just runs
/// onboarding, which reads as "my account is empty" to someone who has a
/// month of talks on their phone.
///
/// The tell is the account's ACTIVE voice clone: `restoreVoiceCloneFromCloud`
/// has already adopted it from the server, and a fresh install that has one
/// is an account that cloned a voice somewhere else. Nothing here is a wall —
/// "Start fresh" walks straight into setup, and the screen is shown once per
/// account per install.
struct SyncOtherDeviceHintView: View {
    /// The zone appeared on a re-check: hand over to the real offer.
    var onFound: () -> Void
    /// Start setup on this device instead.
    var onSkip: () -> Void

    /// What a re-check found. `cannotAsk` is THIS device's problem (no
    /// iCloud account, offline), not the other one's.
    private enum CheckResult { case notYet, cannotAsk }

    @State private var checking = false
    @State private var lastCheck: CheckResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Bring your practice over")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(explain("Your talks, books and cards are still on it — open Me there, turn on “Continue on your other devices”, then come back here."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                if let lastCheck, !checking {
                    Text(note(for: lastCheck))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        Task { await check() }
                    } label: {
                        Group {
                            if checking { ProgressView() } else { Text("Check again") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(checking)
                    Button {
                        onSkip()
                    } label: {
                        Text("Start fresh on this device")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(checking)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("")
        }
    }

    private func note(for result: CheckResult) -> String {
        switch result {
        // Said out loud, or the learner goes back to a phone that is already
        // set up correctly and turns the same toggle on twice.
        case .cannotAsk: return explain("Sign in to iCloud in Settings first, then try again.")
        case .notYet:    return explain("Nothing here yet — check that it's on over there, then try again.")
        }
    }

    private func check() async {
        checking = true
        let answer = await SyncEngine.shared.cloudHasData()
        checking = false
        if answer == true { onFound(); return }
        lastCheck = answer == nil ? .cannotAsk : .notYet
    }
}
