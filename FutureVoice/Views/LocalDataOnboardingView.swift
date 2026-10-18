import SwiftUI

/// Said once, right after the voice exists: every call, recording and thing
/// studied is kept on THIS phone and nowhere else (2026-10-18, founder).
///
/// Safety first, cost second, on purpose: that nothing sits on our servers is
/// the reason to speak freely, and that it goes with the app is the price of
/// it. iOS gives an app no word at deletion time (see `BackupOfferSheet`), so
/// onboarding is the first chance to say it and the iCloud offer after the
/// third talk is the second. New installs only — an existing one has already
/// been asked about iCloud or will be.
struct LocalDataOnboardingView: View {
    /// Set on the one exit, so the screen never appears twice.
    @AppStorage("futurevoice.localData.onboarded") private var onboarded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.iphone")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Your practice stays on your phone")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Calls, recordings and every word you study are saved right here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        row("lock.shield", "Not on our servers",
                            "We don't keep your talks, so speak freely.")
                        row("trash", "It goes with the app",
                            "Delete the app or change phones, and it's gone too.")
                        row("icloud", "Want a copy? Use your own iCloud",
                            "Turn it on any time in Settings → Devices.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .padding(.top, 56)
                .padding(.bottom, 24)
            }

            Button {
                Analytics.capture("local_data_onboarding")
                onboarded = true
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func row(_ icon: String, _ title: LocalizedStringKey,
                     _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
