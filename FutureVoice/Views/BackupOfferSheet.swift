import SwiftUI

/// Asked ONCE, after the third finished talk, while sync is off: keep this
/// practice in iCloud? (2026-10-01, founder decision.)
///
/// iOS never tells an app it is being deleted — the "Delete App" sheet is the
/// system's and carries no words of ours — so the only time to say what a
/// deletion costs is before it happens. A returning learner reinstalled twice
/// and lost every talk and book, plus the recording their voice is made
/// from, without anything having said so. Three talks is when there is
/// enough on the phone to be worth keeping, and once is enough: the same
/// sentence stays in Me → Devices for anyone who said Not now.
struct BackupOfferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = SyncEngine.shared
    @State private var turningOn = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .padding(.top, 28)
                    Text("Keep your practice in iCloud?")
                        .font(.title2.weight(.bold))
                    Text("Your talks, books and recordings are on this phone only. If you delete the app or change phones, they're gone for good.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Kept in your own iCloud, they're waiting on any phone or iPad you sign into — your voice recording too, so your voice comes back without recording again.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            VStack(spacing: 10) {
                Button {
                    Task { await turnOn() }
                } label: {
                    Group {
                        if turningOn {
                            ProgressView()
                        } else {
                            Text("Keep in iCloud")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(turningOn)
                Button("Not now") {
                    Analytics.capture("backup_offer_result", ["result": "later"])
                    dismiss()
                }
                .disabled(turningOn)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(turningOn)
        .onAppear { Analytics.capture("backup_offer_shown") }
    }

    private func turnOn() async {
        turningOn = true
        defer { turningOn = false }
        do {
            try await engine.enable()
            Analytics.capture("backup_offer_result", ["result": "enabled"])
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Analytics.capture("backup_offer_result", ["result": "failed"])
        }
    }
}
