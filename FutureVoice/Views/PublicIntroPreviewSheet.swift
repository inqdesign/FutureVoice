import SwiftUI

/// "Other learners could meet you" — the one look at the mirrored intro
/// before anything about this learner reaches the Find-people pool.
///
/// The onboarding profile was written for the learner's OWN fluent self, and
/// until 2026-09-15 it was published as-is on first launch, family line and
/// free notes included, without the author ever seeing the paragraph. Now the
/// paragraph is shown first, exactly as a stranger's phone would speak it,
/// and one of three things happens: publish it (the mirror then follows
/// profile edits), edit it first (`PublicIntroView`, from then on hand-managed),
/// or not now (nothing is published; Me → Find people is still there).
///
/// Raised from the Watch tab — the place where the pool is met — never on the
/// first landing after setup, which already stacks two introductions.
struct PublicIntroPreviewSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isPublishing = false
    @State private var failed = false

    private var persona: UserPersona { appState.persona ?? .empty }
    private var intro: String { PublicPersonaService.composedIntro(persona) }
    private var languageName: String { LanguageCatalog.name(appState.targetLanguage, in: appState.nativeLanguage) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ProfileAvatar(initials: persona.displayName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(persona.displayName)
                                .font(.headline)
                            let place = [persona.city, persona.country].filter { !$0.isEmpty }.joined(separator: ", ")
                            if !place.isEmpty {
                                Text(place).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Text(intro)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Text("What they'd hear")
                } footer: {
                    Text(explain("Other \(languageName) learners could practice with an AI playing this, in a stock voice — never yours. Their talks never reach you. Locked lines from your talks are never included."))
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("Publish").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPublishing)
                    .listRowSeparator(.hidden)

                    NavigationLink {
                        PublicIntroView(onDecided: { dismiss() }).environmentObject(appState)
                    } label: {
                        Text("Edit first").frame(maxWidth: .infinity)
                    }
                    .disabled(isPublishing)

                    Button(role: .cancel) {
                        decline()
                    } label: {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .disabled(isPublishing)
                } footer: {
                    if failed {
                        Text(explain("Couldn't publish — check your connection and try again."))
                            .foregroundStyle(.red)
                    } else {
                        Text(explain("You can change or take this down any time in Me → Find people."))
                    }
                }
            }
            .navigationTitle("Meet other learners")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isPublishing)
        }
        .onAppear { Analytics.capture("public_intro_preview_shown") }
    }

    private func publish() async {
        isPublishing = true
        failed = false
        let ok = await PublicPersonaService.publishMirror(persona, language: appState.targetLanguage)
        isPublishing = false
        guard ok else { failed = true; return }
        // From here on the mirror follows profile edits — that is what was
        // approved. A hand edit in Me → Find people takes over as before.
        UserDefaults.standard.set(true, forKey: PublicPersonaService.autoApprovedKey)
        Analytics.capture("public_intro_preview_published")
        dismiss()
    }

    private func decline() {
        // An explicit no, so the mirror never publishes on its own — and a
        // row an earlier build put up unasked comes down with it.
        UserDefaults.standard.set(true, forKey: PublicPersonaService.manualIntroKey)
        Analytics.capture("public_intro_preview_declined")
        let language = appState.targetLanguage
        Task { try? await PublicPersonaService.withdrawMine(language: language) }
        dismiss()
    }
}
