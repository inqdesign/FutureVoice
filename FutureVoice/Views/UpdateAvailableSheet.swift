import SwiftUI

/// A newer build is out. Two temperaments in one sheet, because the two cases
/// are not the same request:
///
///   * OPTIONAL — a notice. It can be closed, and it is shown once per build
///     (`AppUpdateService.markSeen`). Nagging is how a notice stops being read.
///   * REQUIRED — the server has moved somewhere this build misreports it, so
///     there is no dismiss and no swipe. That is not a growth device; it is
///     reserved for the case that actually happened here, when the billing
///     model changed under builds already on phones and an old client kept
///     describing allowances that no longer existed.
struct UpdateAvailableSheet: View {
    let update: AppUpdateService.AppUpdate
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: update.required ? "exclamationmark.arrow.circlepath" : "arrow.down.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(update.required ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))

            VStack(spacing: 10) {
                Text(update.required ? "Update to keep going" : "There's a new version")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text(headline)
                    if let notes = update.notes, !notes.isEmpty {
                        Text(notes)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Without this the detent hands the stack a height budget and
                // silently truncates each line to one.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    openURL(AppUpdateService.appStoreURL)
                } label: {
                    Text("Open the App Store").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // A required update has no way past. Everything else does.
                if !update.required {
                    Button("Later") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(.top, 24)
        .presentationDetents([.medium, .large])
        // Both are set from the same flag so a required sheet can't be escaped
        // by dragging it away — the one gap an `if` around the button leaves.
        .interactiveDismissDisabled(update.required)
        .presentationDragIndicator(update.required ? .hidden : .visible)
    }

    /// Always names the build being offered. "A new version is available" with
    /// no number can't be checked against what the App Store then shows.
    private var headline: String {
        let current = AppUpdateService.currentVersion
        if let latest = update.latestVersion {
            return explain("You're on \(current) (\(AppUpdateService.currentBuild)) · newest is \(latest) (\(update.latestBuild))")
        }
        return explain("You're on build \(AppUpdateService.currentBuild) · newest is \(update.latestBuild)")
    }
}

#Preview("Optional") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 15, latestVersion: "1.0.1",
                                           notes: "초대로 받은 시간을 먼저 쓰도록 고쳤어요.",
                                           required: false), onDismiss: {})
    }
}

#Preview("Required") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 15, latestVersion: "1.0.1",
                                           notes: nil, required: true), onDismiss: {})
    }
}
