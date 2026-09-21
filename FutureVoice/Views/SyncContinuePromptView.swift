import SwiftUI

/// A fresh install, signed into an account whose practice is already in
/// iCloud: the second device's first screen. Asked once, before setup, so a
/// learner who has done a month on their phone isn't walked through
/// choosing a level again on their tablet. Either answer sets the
/// once-flag; "Not now" leaves the toggle in Me for later.
struct SyncContinuePromptView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @ObservedObject private var engine = SyncEngine.shared
    @State private var working = false
    @State private var error: String?
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Continue where you left off?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(explain("Your practice from your other device is in your iCloud — talks, cards, words, recordings. Bring it here and keep both in step from now on."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                if let progress = engine.progress, working {
                    VStack(spacing: 6) {
                        if progress.total > 0 {
                            ProgressView(value: Double(progress.done), total: Double(progress.total))
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                        Text(progressText(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        Task { await continueFromCloud() }
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working)
                    Button {
                        finish()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(working)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .alert("Couldn't bring your practice over", isPresented: Binding(get: { error != nil },
                                                                             set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
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

    private func continueFromCloud() async {
        working = true
        defer { working = false }
        do {
            try await engine.enable()
        } catch {
            self.error = error.localizedDescription
            return
        }
        // The pull laid persona, languages and level down underneath the
        // running app — same situation as a restored backup.
        appState.adoptRestoredData()
        if PersonaStore.shared.exists() {
            // Setup asked for exactly what just arrived.
            appState.setupComplete = true
        }
        finish()
    }

    private func finish() {
        if let uid = auth.session?.user.id.uuidString { SyncStore.setOffered(userId: uid) }
        onDone()
    }
}
