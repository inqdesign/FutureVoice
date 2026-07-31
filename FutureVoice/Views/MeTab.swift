import SwiftUI

/// Settings drawer — opened from the Home profile avatar. Everything about
/// "you the account": profile/persona, level, credits + invite, voice,
/// appearance, sign out. Progress lives in its own tab now, not here.
struct MeTab: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("futurevoice.dailyGoalMinutes") private var dailyGoalMinutes = 10
    /// Fallback voice for Watch scenes with no linked persona — same key
    /// `ScenarioDetailView.syntheticCounterpart` reads via `VoicePreset.sceneDefault`.
    @AppStorage(VoicePreset.sceneDefaultKey) private var defaultSceneVoiceId = VoicePreset.catalog[0].id
    @State private var account: AccountStatus = .empty
    /// AI's holistic CEFR read of the last few conversations (mode of the
    /// last 3 scored sessions — same read as ProgressTab). Level changes stay
    /// user-confirmed: this only powers a suggestion row under the picker.
    @State private var aiLevel: CEFRLevel?
    @State private var showingPersonaEdit = false
    @State private var showingPaywall = false
    @State private var confirmingVoiceReset = false
    @State private var confirmingSignOut = false
    @State private var confirmingAccountDelete = false
    @State private var deletingAccount = false
    @State private var accountDeleteError: String?
    @State private var regeneratingVoice = false
    @State private var renamingVoice = false
    @State private var voiceNameDraft = ""
    @State private var voiceRenameWarning: String?
    @State private var voiceRegenerateError: String?
    #if DEBUG
    @State private var confirmingOnboardingReset = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                // Profile at the very top — avatar + name, with the signed-in
                // identity as the subtitle. Tapping it edits the profile
                // (the old "Apple ID" row here did nothing, and the editor was
                // buried under "Learning").
                Section {
                    Button {
                        showingPersonaEdit = true
                    } label: {
                        profileHeader
                    }
                }

                Section {
                    HStack {
                        row(icon: "bolt.fill",
                            title: "\(account.creditBalance) credits",
                            subtitle: account.planLabel)
                        Spacer()
                    }
                    Button {
                        showingPaywall = true
                    } label: {
                        row(icon: "sparkles",
                            title: account.planLabel == "Free" ? "See plans" : "Manage plan",
                            subtitle: "Credits land automatically every cycle")
                    }
                    NavigationLink {
                        CreditGuideView()
                    } label: {
                        row(icon: "questionmark.circle",
                            title: "What uses credits?",
                            subtitle: "And what's always free")
                    }
                    if BetaConfig.invitesAvailable {
                        NavigationLink {
                            InviteView()
                        } label: {
                            row(icon: "gift",
                                title: "Invite & earn credits",
                                subtitle: "You both get 300 per friend")
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(BetaConfig.invitesAvailable
                        ? "Credits power voice synthesis and AI replies. Invite friends to earn more."
                        : "Credits power voice synthesis and AI replies. Reviewing your words, drills, and dialogues always stays free.")
                }

                Section {
                    Picker(selection: $appState.proficiency) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(LanguageCatalog.levelLabel(level, target: appState.targetLanguage))
                                .tag(level)
                        }
                    } label: {
                        row(icon: "chart.bar",
                            title: "Level",
                            subtitle: "Calibrates conversations and feedback")
                    }
                    Picker(selection: $appState.nativeLanguage) {
                        ForEach(LanguageCatalog.nativeLanguages.filter { $0 != appState.targetLanguage },
                                id: \.self) { code in
                            Text(LanguageCatalog.endonym(code)).tag(code)
                        }
                    } label: {
                        row(icon: "globe",
                            title: "My language",
                            subtitle: "Explanations and translations use this")
                    }
                    if let ai = aiLevel, ai != appState.proficiency {
                        Button {
                            appState.proficiency = ai
                        } label: {
                            row(icon: "sparkles",
                                title: "AI read: \(ai.rawValue.uppercased()) — tap to apply",
                                subtitle: "From your recent conversations")
                        }
                    }
                    Picker(selection: $dailyGoalMinutes) {
                        ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    } label: {
                        row(icon: "target",
                            title: "Daily goal",
                            subtitle: "Minutes of speaking per day")
                    }
                } header: {
                    Text("Learning")
                } footer: {
                    Text("Your CEFR level shapes each conversation. The daily goal drives the ring on Home.")
                }

                Section {
                    Picker("Theme", selection: $appState.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    FutureselfThemePicker()
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Future self is the pixel surface behind every call button — tap a theme to feel it.")
                }

                voiceSection

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    // Apple Guideline 5.1.1(v): account creation in-app requires
                    // account deletion in-app.
                    Button(role: .destructive) {
                        confirmingAccountDelete = true
                    } label: {
                        HStack {
                            Label("Delete account", systemImage: "trash")
                            if deletingAccount {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(deletingAccount)
                } footer: {
                    Text("Deleting your account permanently removes your voice clone, credits, and account data. Practice data on this device is erased too.")
                }

                #if DEBUG
                Section {
                    Button {
                        confirmingOnboardingReset = true
                    } label: {
                        row(icon: "arrow.counterclockwise",
                            title: "Replay onboarding",
                            subtitle: "Reset setup, voice & persona — stays signed in")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. Routes back through the first-run setup flow.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                Task { account = await AccountStatus.fetch() }
            }) {
                // Trial pitch only while the free credits last.
                PaywallView(offerTrial: account.creditBalance > 0)
            }
            .sheet(isPresented: $showingPersonaEdit) {
                PersonaOnboardingView(initialPersona: appState.persona)
                    .environmentObject(appState)
            }
            .alert("Re-record your voice?", isPresented: $confirmingVoiceReset) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    appState.resetVoiceClone()   // RootView swaps to onboarding
                }
            } message: {
                Text("Your current clone will be deleted on ElevenLabs after the new one is created.")
            }
            .alert("Sign out?", isPresented: $confirmingSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } message: {
                Text("Your practice data stays on this device. Your voice clone and credits stay with your account.")
            }
            .alert("Delete your account?", isPresented: $confirmingAccountDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete forever", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your voice clone, credits, and account. It cannot be undone. An active App Store subscription must be canceled separately in Settings → Apple ID → Subscriptions.")
            }
            .alert("Couldn't delete account", isPresented: Binding(
                get: { accountDeleteError != nil },
                set: { if !$0 { accountDeleteError = nil } }
            )) {
                Button("OK") { accountDeleteError = nil }
            } message: {
                Text(accountDeleteError ?? "")
            }
            #if DEBUG
            .alert("Replay onboarding?", isPresented: $confirmingOnboardingReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    appState.resetOnboarding()   // RootView swaps to SetupFlowView
                }
            } message: {
                Text("Clears setup, voice clone and persona, then restarts the first-run flow. You stay signed in.")
            }
            #endif
            .task { account = await AccountStatus.fetch() }
            .task { aiLevel = recentAILevel() }
        }
    }

    /// Same source as ProgressTab's "Estimated level": ONLY the weekly
    /// report's pooled CEFR read. Single-session reads are too noisy to
    /// publish anywhere — no report yet means no suggestion, not a guess.
    private func recentAILevel() -> CEFRLevel? {
        appState.weeklyReports
            .sorted(by: { $0.generatedAt > $1.generatedAt })
            .compactMap({ $0.cefrLevel.flatMap { CEFRLevel(rawValue: $0) } })
            .first
    }

    /// Server first, local second: the Edge Function removes the clone,
    /// cancels web billing, and destroys the auth user; only after that
    /// succeeds do we erase the device. On failure nothing local is touched —
    /// the user keeps a working account and sees the error.
    private func deleteAccount() {
        guard !deletingAccount else { return }
        deletingAccount = true
        Task {
            defer { deletingAccount = false }
            do {
                try await auth.deleteAccount()
                appState.wipeLocalData()   // session is nil → RootView shows Welcome
                dismiss()
            } catch {
                accountDeleteError = error.localizedDescription
            }
        }
    }

    private func regenerateFromSavedSample() {
        guard let url = VoiceSampleStore.shared.url, !regeneratingVoice else { return }
        regeneratingVoice = true
        Task {
            defer { regeneratingVoice = false }
            do {
                try await appState.regenerateVoiceClone(fromSampleAt: url)
            } catch {
                // This used to be `try?`: the spinner stopped, nothing changed,
                // and the failure was invisible — the user walked away thinking
                // their voice had been rebuilt.
                voiceRegenerateError = error.localizedDescription
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section("Voice") {
            Button {
                voiceNameDraft = appState.voiceDisplayName
                renamingVoice = true
            } label: {
                row(icon: "textformat",
                    title: "Voice name: \(appState.voiceDisplayName)",
                    subtitle: "What your clone is called, here and on ElevenLabs")
            }
            NavigationLink {
                VoicePresetPickerView(selection: $defaultSceneVoiceId)
                    .environmentObject(appState)
            } label: {
                row(icon: "person.wave.2",
                    title: "Scene partner voice: \(VoicePreset.by(id: defaultSceneVoiceId).displayName)",
                    subtitle: "For Watch scenes without a saved person")
            }
            Button(role: .destructive) {
                confirmingVoiceReset = true
            } label: {
                row(icon: "mic.badge.plus",
                    title: "Re-record voice",
                    subtitle: "Replace your current clone with a new one")
            }
            if VoiceSampleStore.shared.exists {
                Button {
                    regenerateFromSavedSample()
                } label: {
                    HStack {
                        row(icon: "arrow.triangle.2.circlepath",
                            title: "Regenerate from saved recording",
                            subtitle: "Rebuild the clone from your last recording")
                        if regeneratingVoice {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(regeneratingVoice)
            }
        }
        .alert("Voice name", isPresented: $renamingVoice) {
            TextField("Future Self", text: $voiceNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameVoice() }
        } message: {
            Text("Names your clone here and on ElevenLabs. Leave it empty to go back to the default.")
        }
        .alert("Renamed on this device only", isPresented: Binding(
            get: { voiceRenameWarning != nil },
            set: { if !$0 { voiceRenameWarning = nil } }
        )) {
            Button("OK") { voiceRenameWarning = nil }
        } message: {
            Text(voiceRenameWarning ?? "")
        }
        .alert("Couldn't rebuild your voice", isPresented: Binding(
            get: { voiceRegenerateError != nil },
            set: { if !$0 { voiceRegenerateError = nil } }
        )) {
            Button("OK") { voiceRegenerateError = nil }
        } message: {
            Text(voiceRegenerateError ?? "")
        }
    }

    /// Save the new name. The local name is kept either way — if the upstream
    /// rename fails (offline, or the rename function isn't deployed), the app
    /// says so plainly and the name still reaches ElevenLabs on the next clone.
    private func renameVoice() {
        // Typing nothing (or the unchanged default) means "use the default" —
        // storing the derived string would freeze it against a persona rename.
        let draft = voiceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = draft == appState.defaultVoiceName ? "" : draft
        Task {
            do {
                try await appState.renameVoice(to: next)
            } catch {
                voiceRenameWarning = "Saved here, but ElevenLabs didn't accept the new name: \(error.localizedDescription) It'll be applied the next time your voice is cloned."
            }
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The top-of-settings identity block: avatar + name, with the signed-in
    /// account as the subtitle. Tapping the whole row edits the profile.
    private var profileHeader: some View {
        HStack(spacing: 14) {
            ProfileAvatar(initials: appState.persona?.displayName ?? "", size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.persona?.displayName.isEmpty == false
                     ? appState.persona!.displayName
                     : "Set up your profile")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                // Apple often returns no email (private relay, or the email
                // scope only arrives on first sign-in), so account.email can
                // be nil OR an empty string — coalesce both to a label instead
                // of rendering a blank line.
                Text(accountSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var accountSubtitle: String {
        let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Signed in with Apple" : email
    }
}
