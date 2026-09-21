import SwiftUI

/// Me → "Continue on your other devices". One toggle, the numbers under it,
/// and the two things a learner might need to do (sync now; use cellular for
/// audio). Off by default: it spends the learner's iCloud storage, so it is
/// their call. Modelled on `MeTab.dailyCallSection`.
struct SyncSection: View {
    @ObservedObject private var engine = SyncEngine.shared
    @EnvironmentObject private var auth: AuthService
    @State private var enabled = SyncEngine.shared.isEnabled
    @State private var cellular = SyncStore.cellularForAudio
    @State private var enabling = false
    @State private var enableError: String?
    @State private var confirmingCloudDelete = false
    @State private var cloudDeleteError: String?

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                MeRow(icon: "icloud",
                      title: explain("Continue on your other devices"),
                      subtitle: explain("Uses your iCloud"))
            }
            .disabled(!auth.isSignedIn || enabling)
            if enabled {
                statusRow
                if let progress = engine.progress {
                    progressRow(progress)
                }
                Button {
                    engine.syncNow()
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(engine.status == .syncing)
                Toggle(isOn: $cellular) {
                    Label("Move audio over cellular too", systemImage: "antenna.radiowaves.left.and.right")
                }
                Button(role: .destructive) {
                    confirmingCloudDelete = true
                } label: {
                    Label("Delete from iCloud", systemImage: "icloud.slash")
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            Text(footer)
        }
        .onChange(of: enabled) { _, on in
            Task { await set(enabled: on) }
        }
        .onChange(of: cellular) { _, on in
            SyncStore.cellularForAudio = on
            (engine.transport as? CloudKitTransport)?.allowsCellularForBlobs = on
        }
        .onChange(of: engine.status) { _, status in
            // The engine can switch itself off (the zone was deleted from
            // another device); the toggle follows.
            if status == .off || status == .paused(.zoneMissing) { enabled = engine.isEnabled }
        }
        .alert("Couldn't turn on sync", isPresented: Binding(get: { enableError != nil },
                                                             set: { if !$0 { enableError = nil } })) {
            Button("OK") { enableError = nil }
        } message: {
            Text(enableError ?? "")
        }
        .confirmationDialog("Delete your practice from iCloud?",
                            isPresented: $confirmingCloudDelete, titleVisibility: .visible) {
            Button("Delete from iCloud", role: .destructive) {
                Task { await deleteFromCloud() }
            }
        } message: {
            Text(explain("Everything synced to iCloud is removed and syncing stops on every device. What's on this device stays."))
        }
        .alert("Couldn't delete", isPresented: Binding(get: { cloudDeleteError != nil },
                                                      set: { if !$0 { cloudDeleteError = nil } })) {
            Button("OK") { cloudDeleteError = nil }
        } message: {
            Text(cloudDeleteError ?? "")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch engine.status {
        case .syncing:
            Label {
                Text("Syncing…")
            } icon: {
                ProgressView()
            }
        case .paused(let pause):
            Label(pauseText(pause), systemImage: "exclamationmark.icloud")
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label {
                Text("Couldn't sync — \(reason)")
            } icon: {
                Image(systemName: "exclamationmark.icloud")
            }
            .foregroundStyle(.secondary)
        case .idle, .off:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    if let at = engine.lastSyncAt {
                        Text("Up to date · \(at.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Waiting for the first sync")
                    }
                    if engine.pendingItems + engine.pendingAudio + engine.wantedAudio > 0 {
                        Text(pendingText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "checkmark.icloud")
            }
        }
    }

    private var pendingText: String {
        var parts: [String] = []
        if engine.pendingItems > 0 { parts.append(explain("\(engine.pendingItems) to send")) }
        if engine.pendingAudio > 0 { parts.append(explain("\(engine.pendingAudio) audio files to upload")) }
        if engine.wantedAudio > 0 { parts.append(explain("\(engine.wantedAudio) audio files to download")) }
        return parts.joined(separator: " · ")
    }

    private func progressRow(_ progress: SyncEngine.Progress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if progress.total > 0 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(progressText(progress))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func progressText(_ p: SyncEngine.Progress) -> String {
        switch p.phase {
        case .indexing: return explain("Looking through your practice…")
        case .pulling: return explain("Getting what your other devices did…")
        case .pushing: return explain("Sending \(p.done) of \(p.total)…")
        case .uploadingAudio: return explain("Uploading audio \(p.done) of \(p.total)…")
        case .downloadingAudio: return explain("Downloading audio \(p.done) of \(p.total)…")
        }
    }

    private func pauseText(_ pause: SyncEngine.Pause) -> String {
        switch pause {
        case .noAccount: return explain("Sign in to iCloud in Settings to sync")
        case .restricted: return explain("iCloud isn't available on this device")
        case .quotaExceeded: return explain("iCloud storage is full — audio isn't syncing")
        case .zoneMissing: return explain("Sync was turned off from another device")
        case .offline: return explain("Offline — will sync when you're back")
        }
    }

    private var footer: String {
        if !auth.isSignedIn {
            return explain("Sign in to sync your practice between your iPhone and iPad.")
        }
        return enabled
            ? explain("Your talks, cards, words and recordings — including the audio — are kept the same on every device signed into this account and your iCloud. Turning this off stops syncing and deletes nothing.")
            : explain("Practise on your iPhone, pick it up on your iPad. Everything is stored in your own iCloud, audio included, so it can use a few gigabytes there.")
    }

    private func set(enabled on: Bool) async {
        guard on else {
            engine.disable()
            return
        }
        guard !engine.isEnabled else { return }
        enabling = true
        defer { enabling = false }
        do {
            try await engine.enable()
        } catch {
            enableError = error.localizedDescription
            enabled = false
        }
    }

    private func deleteFromCloud() async {
        do {
            try await engine.deleteFromCloud()
            enabled = false
        } catch {
            cloudDeleteError = error.localizedDescription
        }
    }
}

/// `MeTab.row` is private to the tab; the same shape, for sections that
/// live in their own file.
struct MeRow: View {
    var icon: String
    var title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
