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
    private enum CheckResult { case notYet, cannotAsk, notOnDrive }

    @EnvironmentObject private var auth: AuthService
    @State private var checking = false
    @State private var lastCheck: CheckResult?
    @State private var driveError: String?

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
                    .accentProminent()
                    .controlSize(.large)
                    .disabled(checking)
                    // The other device may be an Android phone, which keeps
                    // its practice in Google Drive, not iCloud.
                    if GoogleDriveAuth.isConfigured {
                        Button {
                            Task { await checkDrive() }
                        } label: {
                            Text("My other device is an Android phone")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(checking)
                    }
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
            .alert("Couldn't sign in to Google", isPresented: Binding(get: { driveError != nil },
                                                                     set: { if !$0 { driveError = nil } })) {
                Button("OK") { driveError = nil }
            } message: {
                Text(driveError ?? "")
            }
        }
    }

    private func note(for result: CheckResult) -> String {
        switch result {
        // Said out loud, or the learner goes back to a phone that is already
        // set up correctly and turns the same toggle on twice.
        case .cannotAsk: return explain("Sign in to iCloud in Settings first, then try again.")
        case .notYet:    return explain("Nothing here yet — check that it's on over there, then try again.")
        case .notOnDrive:
            return explain("Nothing in this Google account yet. On the phone, open Me and turn on “Continue on your other devices”, using the same Google account.")
        }
    }

    /// Signs into Google, points this account's sync at Drive and looks for
    /// the phone's folder. Found → the same Continue offer iCloud gets.
    private func checkDrive() async {
        guard let userId = auth.session?.user.id.uuidString else { return }
        checking = true
        defer { checking = false }
        do {
            if !GoogleDriveAuth.isConnected(userId: userId) {
                try await GoogleDriveAuth.signIn(userId: userId)
            }
        } catch GoogleDriveAuth.AuthError.cancelled {
            return
        } catch {
            driveError = error.localizedDescription
            return
        }
        SyncEngine.shared.useBackend(.googleDrive)
        let answer = await SyncEngine.shared.cloudHasData()
        if answer == true { onFound(); return }
        lastCheck = answer == nil ? .cannotAsk : .notOnDrive
    }

    private func check() async {
        checking = true
        let answer = await SyncEngine.shared.cloudHasData()
        checking = false
        if answer == true { onFound(); return }
        lastCheck = answer == nil ? .cannotAsk : .notYet
    }
}
