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
    /// Level of every enrolled language, read once on open. Only the active
    /// language's level is published on AppState; the rest live on disk, and
    /// a `body` that hit ProfileStore per row per render would read the file
    /// on every keystroke elsewhere in this list.
    @State private var levelCache: [String: CEFRLevel] = [:]
    @State private var showingPersonaEdit = false
    @State private var showingPaywall = false
    @State private var showingAddLanguage = false
    @State private var confirmingVoiceReset = false
    @State private var confirmingVoiceRegenerate = false
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
                        // balanceLabel, not the raw number — an admin account
                        // never spends, so its stored balance is cosmetic and
                        // reads as "Unlimited" (the header chip already does
                        // this; this row was showing the bare figure).
                        row(icon: "bolt.fill",
                            title: "\(account.balanceLabel) credits",
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

                learningLanguagesSection

                Section {
                    NavigationLink {
                        PublicIntroView().environmentObject(appState)
                    } label: {
                        row(icon: "person.2.wave.2",
                            title: "Find people",
                            subtitle: "Publish your intro — others practice with \"you\"")
                    }
                }

                appSection

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
                    Text(explain("Future self is the pixel surface behind every call button — tap a theme to feel it."))
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
                    Text(explain("Deleting your account permanently removes your voice clone, credits, and account data. Practice data on this device is erased too."))
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
                    Text(explain("Debug builds only. Routes back through the first-run setup flow."))
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
            .sheet(isPresented: $showingAddLanguage) {
                AddLanguageSheet().environmentObject(appState)
            }
            .alert("Re-record your voice?", isPresented: $confirmingVoiceReset) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    appState.resetVoiceClone()   // RootView swaps to onboarding
                }
            } message: {
                // Ledger data showed users re-cloning many times without
                // realizing each one bills and destroys the previous voice —
                // all three consequences must be on the confirm, both here
                // and on "Regenerate from saved recording".
                Text(Self.recloneWarning)
            }
            .alert("Sign out?", isPresented: $confirmingSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        // RootView's Welcome gate is "has the journey begun",
                        // not "is there a session" — leaving this set drops a
                        // signed-out user straight back into the tabs (setup,
                        // persona and clone all still read complete), so the
                        // button looked like it did nothing. Same reset
                        // SetupFlowView does on its way back to Welcome.
                        appState.onboardingStarted = false
                    }
                }
            } message: {
                Text(explain("Your practice data stays on this device. Your voice clone and credits stay with your account."))
            }
            .alert("Delete your account?", isPresented: $confirmingAccountDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete forever", role: .destructive) { deleteAccount() }
            } message: {
                Text(explain("This permanently deletes your voice clone, credits, and account. It cannot be undone. An active App Store subscription must be canceled separately in Settings → Apple ID → Subscriptions."))
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
                Text(explain("Clears setup, voice clone and persona, then restarts the first-run flow. You stay signed in."))
            }
            #endif
            .task { account = await AccountStatus.fetch() }
            .task { aiLevel = recentAILevel() }
            .task(id: appState.enrolledLanguages) { refreshLevelCache() }
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

    /// The app-language picker's two groups, in `nativeChoices` order (device
    /// languages first). The active target is dropped from both — you can't
    /// have the app explain a language in itself.
    private var nativeChoiceGroups: (translated: [String], coachingOnly: [String]) {
        let translated = Set(LanguageCatalog.translatedLanguages)
        let choices = LanguageCatalog.nativeChoices.filter { $0 != appState.targetLanguage }
        return (choices.filter { translated.contains($0) },
                choices.filter { !translated.contains($0) })
    }

    private func refreshLevelCache() {
        levelCache = Dictionary(uniqueKeysWithValues:
            appState.enrolledLanguages.map { ($0, appState.level(for: $0)) })
    }

    /// Reads the active language's level straight off AppState so an outside
    /// change (weekly assessment, the AI-read row) shows up immediately;
    /// every other language answers from the cache.
    private func levelBinding(for code: String) -> Binding<CEFRLevel> {
        Binding(
            get: {
                code == appState.targetLanguage
                    ? appState.proficiency
                    : (levelCache[code] ?? .b1)
            },
            set: { level in
                appState.setLevel(level, for: code)
                levelCache[code] = level
            }
        )
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

    // MARK: - Languages

    /// There are exactly two kinds of language in this app: the ones you're
    /// learning, and the one the app talks to you in. They used to be split
    /// across a "Languages" list and a "Learning" section that ALSO held the
    /// level — so the same language appeared twice and the level read as
    /// global when it is per language. One section per kind now, and each
    /// language wears its own level.
    @ViewBuilder
    private var learningLanguagesSection: some View {
        Section {
            ForEach(appState.enrolledLanguages, id: \.self) { code in
                HStack {
                    Button {
                        appState.switchLanguage(to: code)
                    } label: {
                        row(icon: code == appState.targetLanguage ? "checkmark.circle.fill" : "circle",
                            title: LanguageCatalog.endonym(code),
                            subtitle: LanguageCatalog.englishName(code))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    // The level belongs to the language, not to the app — an
                    // inline menu keeps them on one line and lets you fix a
                    // level without switching to it first.
                    Picker(selection: levelBinding(for: code)) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(LanguageCatalog.levelLabel(level, target: code)).tag(level)
                        }
                    } label: {
                        Text("Level")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .deleteDisabled(appState.enrolledLanguages.count == 1)
            }
            .onDelete { indexSet in
                for i in indexSet { appState.removeLanguage(appState.enrolledLanguages[i]) }
            }
            if let ai = aiLevel, ai != appState.proficiency {
                Button {
                    appState.proficiency = ai
                    levelCache[appState.targetLanguage] = ai
                } label: {
                    row(icon: "sparkles",
                        title: "AI read: \(ai.rawValue.uppercased()) — tap to apply",
                        subtitle: "From your recent \(LanguageCatalog.englishName(appState.targetLanguage)) conversations")
                }
            }
            Button {
                showingAddLanguage = true
            } label: {
                row(icon: "plus.circle",
                    title: "Add a language",
                    subtitle: "Same voice, new language")
            }
        } header: {
            Text("Learning")
        } footer: {
            Text(explain("Tap a language to practice it. Its level calibrates every conversation in that language. Your cloned voice speaks all of them — removing one keeps its progress."))
        }
    }

    /// App-wide preferences no single practice language owns.
    @ViewBuilder
    private var appSection: some View {
        Section {
            Picker(selection: $appState.nativeLanguage) {
                // Two groups, because the app can only half-keep the promise
                // its name makes: three languages have a catalog column and
                // are translated end to end; the other 60-odd get LLM coaching
                // text — corrections, notes, word meanings, which is most of
                // what a learner reads — in their language, with the app's
                // own static copy staying English. Splitting the list says
                // that before the choice instead of after it.
                let (translated, coachingOnly) = nativeChoiceGroups
                Section {
                    ForEach(translated, id: \.self) { code in
                        Text(LanguageCatalog.endonym(code)).tag(code)
                    }
                } header: {
                    Text(explain("App is translated"))
                }
                Section {
                    ForEach(coachingOnly, id: \.self) { code in
                        Text(LanguageCatalog.endonym(code)).tag(code)
                    }
                } header: {
                    Text(explain("Corrections and notes only — app stays English"))
                }
            } label: {
                // Names the EFFECT, not the fact. "My language" read as "the
                // language I picked to learn"; what the setting actually
                // decides is which language the app explains itself in.
                row(icon: "globe",
                    title: "App language",
                    subtitle: "Corrections, notes and word meanings")
            }
            // A menu of 60+ languages is a scroll inside a popover; the push
            // style gives the list a whole screen.
            .pickerStyle(.navigationLink)
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
            Text("App")
        } footer: {
            Text(explain("Explanations and word meanings come back in your app language. The daily goal drives the ring on Home."))
        }
    }

    // MARK: - Voice

    /// Every consequence of making a new clone, on one confirm: it bills, it
    /// replaces, and the old voice is unrecoverable (the previous clone is
    /// deleted on ElevenLabs after the new one succeeds — only audio that was
    /// already synthesized keeps playing, via the PhraseAudioStore lineage).
    /// The "5 credits" figure mirrors priceFor("voice_clone") in
    /// supabase/functions/_shared/credits.ts — keep them in sync.
    private static var recloneWarning: String {
        explain("Cloning again uses 5 credits. Your current voice is replaced and deleted on ElevenLabs — you can't go back to it. Audio already generated keeps playing.")
    }

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
                    confirmingVoiceRegenerate = true
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
        .alert("Rebuild your voice?", isPresented: $confirmingVoiceRegenerate) {
            Button("Cancel", role: .cancel) {}
            Button("Rebuild", role: .destructive) { regenerateFromSavedSample() }
        } message: {
            // This path used to bill 5 credits and delete the previous clone
            // with NO confirmation at all — same consequences as a re-record,
            // so it gets the same warning.
            Text(Self.recloneWarning)
        }
        .alert("Voice name", isPresented: $renamingVoice) {
            TextField("Future Self", text: $voiceNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameVoice() }
        } message: {
            Text(explain("Names your clone here and on ElevenLabs. Leave it empty to go back to the default."))
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
