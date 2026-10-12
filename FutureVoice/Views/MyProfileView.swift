import SwiftUI

/// The ONE "me" page (2026-10-12, founder: "my avatar and my public profile
/// being two places is odd"). Three doors used to lead to two screens — the
/// Watch map's own face and Me's profile header opened the persona editor,
/// Find people's "You" row and Me → Find people opened the public intro — and
/// the intro is not a separate thing: `PublicIntroComposer` writes it FROM
/// the profile. So both halves sit on one page, profile on top, what other
/// learners see under it, and a profile edit shows its effect on the intro
/// on the way back.
///
/// The consent rule is untouched: nothing goes into the pool from here
/// without the paragraph being on screen first — Publish lands in
/// `PublicIntroView`, seeded with the text shown here.
struct MyProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    /// Watch presents this as its own sheet and needs a way out; pushed from
    /// Me or Find people it has a back button.
    var showsDone = false
    /// Find people redraws its "You" row from this.
    var onPublicChange: (() -> Void)? = nil

    @State private var mine: PublicPersonaService.PublicPersona?
    @State private var loaded = false
    @State private var editingProfile = false
    @State private var confirmingWithdraw = false
    @State private var isWorking = false
    @State private var errorText: String?

    private var persona: UserPersona? { appState.persona }

    private var languageName: String {
        LanguageCatalog.englishName(appState.targetLanguage)
    }

    var body: some View {
        Form {
            profileSection
            publicSection
        }
        .navigationTitle(chrome("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadMine() }
        .sheet(isPresented: $editingProfile, onDismiss: {
            // A saved profile re-syncs an auto-approved row in the
            // background; read it again so the paragraph below follows.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await loadMine()
            }
        }) {
            PersonaOnboardingView(initialPersona: appState.persona)
                .environmentObject(appState)
        }
        .confirmationDialog(
            explain("Take your intro out of the pool? Learners who already met your persona keep their own past talks."),
            isPresented: $confirmingWithdraw, titleVisibility: .visible
        ) {
            Button("Take down", role: .destructive) {
                Task { await withdraw() }
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            Button {
                editingProfile = true
            } label: {
                HStack(spacing: 14) {
                    ProfileAvatar(initials: persona?.displayName ?? "", size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(persona?.displayName.isEmpty == false
                             ? persona!.displayName
                             : explain("Set up your profile"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !profileLine.isEmpty {
                            Text(profileLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Edit")
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            // Plain, or the button's tint paints the name and the line under
            // it blue; only "Edit" says it's tappable.
            .buttonStyle(.plain)
        } header: {
            Text("What your fluent self knows about you")
        }
    }

    /// "Berlin · Solo founder" — what the editor's first pages hold, in one
    /// line. The learner's own words, so nothing here is localized.
    private var profileLine: String {
        guard let p = persona else { return "" }
        return [p.city, p.occupation]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    @ViewBuilder private var publicSection: some View {
        Section {
            if !loaded {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let mine {
                Text(mine.intro)
                    .font(.body)
                if let greeting = mine.greeting, !greeting.isEmpty {
                    LabeledContent("Greeting") {
                        Text(greeting)
                            .multilineTextAlignment(.trailing)
                    }
                }
                NavigationLink {
                    introEditor
                } label: {
                    Text("Edit")
                }
                Button(role: .destructive) {
                    confirmingWithdraw = true
                } label: {
                    Text("Take down")
                }
                .disabled(isWorking)
            } else {
                if let persona {
                    ComposedIntroLoader(persona: persona, language: appState.targetLanguage)
                }
                NavigationLink {
                    introEditor
                } label: {
                    Text("Publish")
                }
            }
        } header: {
            HStack {
                Text("What strangers can see")
                Spacer()
                if loaded {
                    if mine != nil {
                        Label("Published", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not published", systemImage: "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else if mine != nil {
                Text(explain("You're in the pool — other \(languageName) learners can find and talk with your persona."))
            } else if loaded {
                Text("Other learners can't find you yet.")
            }
        }
    }

    private var introEditor: some View {
        PublicIntroView(onDecided: {
            Task { await loadMine() }
            onPublicChange?()
        })
        .environmentObject(appState)
    }

    // MARK: - Actions

    private func loadMine() async {
        mine = try? await PublicPersonaService.fetchMine(language: appState.targetLanguage)
        loaded = true
    }

    private func withdraw() async {
        isWorking = true
        errorText = nil
        do {
            try await PublicPersonaService.withdrawMine(language: appState.targetLanguage)
            // Same as the editor's Take down: a deliberate choice the
            // launch-time mirror must not quietly undo.
            UserDefaults.standard.set(true, forKey: PublicPersonaService.manualIntroKey)
            mine = nil
            onPublicChange?()
        } catch {
            errorText = explain("Couldn't take it down — check your connection and try again.")
        }
        isWorking = false
    }
}
