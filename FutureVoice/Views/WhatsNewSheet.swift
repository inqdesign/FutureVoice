import SwiftUI

/// "What's new" — shown once, on the first open after an update, to someone
/// who used the app before it (2026-10-13, founder). A fresh install has just
/// been through onboarding, where all of it was already new.
///
/// The goal row carries a button because an existing learner never sees the
/// onboarding step that asks why they're learning: this card is the only
/// place they would find out the Talk tab can follow it.
enum WhatsNew {
    /// Bump with each release that has something to say; the card shows once
    /// per value.
    static let release = "1.1.8"
    private static let shownKey = "futurevoice.whatsNew.shown"

    @MainActor
    static func isDue(_ appState: AppState) -> Bool {
        guard appState.setupComplete,
              UserDefaults.standard.string(forKey: shownKey) != release else { return false }
        // Someone who has talked before is someone this is news to.
        return !SessionStore.shared.loadAcrossLanguages().isEmpty
    }

    static func markShown() {
        UserDefaults.standard.set(release, forKey: shownKey)
    }
}

struct WhatsNewSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingGoals = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    item("music.mic", "Speech challenges",
                         "In the Speech tab, everyone reads the same script. Read it with the camera on and you land on the leaderboard.")
                    item("person.2.wave.2.fill", "A new Watch",
                         "Your people now sit around you on a map. Bring someone to the middle and they greet you in their own voice, then start a scene or a call right from their card.")
                    VStack(alignment: .leading, spacing: 10) {
                        item("target", "Topics for why you're learning",
                             "Tell us what you're learning for, like an exam, work or travel, and the Talk tab fills with topics for it.")
                        Button {
                            showingGoals = true
                        } label: {
                            Text("Choose my goal").fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        .padding(.leading, 44)
                    }
                    item("chart.bar.fill", "Your effort",
                         "In the Progress tab, see what you practised and how much, over a week or a month.")
                }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingGoals) {
            DiscoverSettingsSheet().environmentObject(appState)
        }
        .onAppear {
            WhatsNew.markShown()
            Analytics.capture("whats_new_shown", ["release": WhatsNew.release])
        }
    }

    private func item(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
