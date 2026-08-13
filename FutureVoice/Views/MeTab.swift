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
    /// Talk-call playback gain (0.25–1.0). Same key `AudioPlayer` reads.
    @AppStorage(AudioPlayer.talkVoiceVolumeKey) private var talkVoiceVolume = 1.0
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
    /// Mirrors of `DailyCallStore`'s defaults so the controls can bind. The
    /// store stays the source of truth — `onChange` writes back — because the
    /// scheduler runs from a notification action with no view in memory.
    @State private var dailyCallEnabled = DailyCallStore.shared.isEnabled
    @State private var callbackMinutes = DailyCallScheduler.defaultCallbackMinutes
    /// Working copy of `DailyCallStore.times`; written back on every edit.
    @State private var callTimes = DailyCallStore.shared.times
    /// Nil while loading or when the learner hasn't qualified — the row still
    /// shows, because a club nobody can see is a club nobody joins.
    @State private var coreMembership: CoreClubService.Membership?
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
    @State private var pickingAccent = false
    @State private var importingBackup = false
    @State private var backupResult: String?
    #if DEBUG
    @State private var confirmingOnboardingReset = false
    @State private var confirmingAudioCacheClear = false
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

                // One row per topic, current state in the subtitle, details
                // behind a push — the flat 25-row list buried what mattered.
                Section {
                    NavigationLink {
                        planPage
                    } label: {
                        row(icon: "bolt.fill",
                            title: "Plan & talk time",
                            subtitle: "\(account.talkTimeLabel) · \(account.planLabel)")
                    }
                }

                // Learning stays expanded — languages, level, goal and app
                // language are the settings people actually return to.
                learningLanguagesSection

                Section {
                    NavigationLink {
                        dailyCallPage
                    } label: {
                        row(icon: "phone.arrow.down.left",
                            title: "Daily call",
                            subtitle: dailyCallSummary)
                    }
                    NavigationLink {
                        voicePage
                    } label: {
                        row(icon: "person.wave.2",
                            title: "Voice",
                            subtitle: appState.voiceDisplayName)
                    }
                    NavigationLink {
                        PublicIntroView().environmentObject(appState)
                    } label: {
                        row(icon: "person.2.wave.2",
                            title: "Find people",
                            subtitle: "Publish your intro — others practice with \"you\"")
                    }
                    NavigationLink {
                        CoreClubView()
                    } label: {
                        row(icon: "seal",
                            title: "The Core",
                            subtitle: coreClubSummary)
                    }
                }

                Section {
                    NavigationLink {
                        appearancePage
                    } label: {
                        row(icon: "paintpalette",
                            title: "Appearance",
                            subtitle: appState.appearance.label)
                    }
                    NavigationLink {
                        dataPage
                    } label: {
                        row(icon: "externaldrive",
                            title: "Practice data",
                            subtitle: "Export or import this device's practice")
                    }
                }

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
                    Text(explain("Deleting your account permanently removes your voice clone, talk time, and account data. Practice data on this device is erased too."))
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
                    // Forces the next play of every line to re-synthesize.
                    // Exists so nobody ever reaches for "delete the app" to
                    // test cached audio: that wipes Documents, and the
                    // learning records in there have no server copy.
                    Button {
                        confirmingAudioCacheClear = true
                    } label: {
                        row(icon: "waveform.slash",
                            title: "Clear voice cache",
                            subtitle: "Re-synthesize every line — learning data untouched")
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
                PaywallView()
            }
            .sheet(isPresented: $showingPersonaEdit) {
                PersonaOnboardingView(initialPersona: appState.persona)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingAddLanguage) {
                AddLanguageSheet().environmentObject(appState)
            }
            // List renders sections lazily, so a .sheet attached inside a
            // Section loses its presentation as soon as it appears — present
            // from the List like every other sheet here.
            .sheet(isPresented: $pickingAccent) {
                VoiceAccentSheet()
                    .environmentObject(appState)
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
                Text(explain("Your practice data stays on this device. Your voice clone and talk time stay with your account."))
            }
            .alert("Delete your account?", isPresented: $confirmingAccountDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete forever", role: .destructive) { deleteAccount() }
            } message: {
                Text(explain("This permanently deletes your voice clone, talk time, and account. It cannot be undone. An active App Store subscription must be canceled separately in Settings → Apple ID → Subscriptions."))
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
            // Extracted into a modifier: inline, these two tipped `body` past
            // what the type-checker will solve in reasonable time.
            .modifier(DeveloperAlerts(
                confirmingOnboardingReset: $confirmingOnboardingReset,
                confirmingAudioCacheClear: $confirmingAudioCacheClear,
                onResetOnboarding: { appState.resetOnboarding() }))
            #endif
            .task { account = await AccountStatus.fetch() }
            .task { coreMembership = await CoreClubService.fetchMine() }
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
    /// languages first). The active target stays IN the list: explaining a
    /// language in itself is full immersion, and some learners want exactly
    /// that.
    private var nativeChoiceGroups: (translated: [String], coachingOnly: [String]) {
        let translated = Set(LanguageCatalog.translatedLanguages)
        let choices = LanguageCatalog.nativeChoices
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
    /// Export/import of everything practiced on THIS device. Exists because
    /// dev and release builds are separate sandboxes — practice done in one
    /// never reaches the other by itself. See `BackupService`.
    private var backupSection: some View {
        Section {
            ShareLink(item: BackupFile(),
                      preview: SharePreview("FutureVoice backup")) {
                Label("Export practice data", systemImage: "square.and.arrow.up")
            }
            Button {
                importingBackup = true
            } label: {
                Label("Import practice data", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Practice data")
        } footer: {
            Text(explain("Everything you've practiced on this device — talks, drills, words, books — as one file. Use it to carry progress into another install. Your voice and minutes already follow your account."))
        }
        .fileImporter(isPresented: $importingBackup,
                      allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                do {
                    let count = try BackupService.restore(from: url)
                    backupResult = explain("Restored \(count) files. Quit the app completely and reopen it — your practice will be there.")
                } catch {
                    backupResult = error.localizedDescription
                }
            case .failure(let error):
                backupResult = error.localizedDescription
            }
        }
        .alert("Import practice data",
               isPresented: Binding(get: { backupResult != nil },
                                    set: { if !$0 { backupResult = nil } })) {
            Button("OK") { backupResult = nil }
        } message: {
            Text(backupResult ?? "")
        }
    }

    /// Lazily builds the backup file the moment the share sheet asks for it.
    private struct BackupFile: Transferable {
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(exportedContentType: .data) { _ in
                SentTransferredFile(try BackupService.export())
            }
        }
    }

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
            // Goal + app language live WITH the languages: they're the other
            // two answers to "how do I learn here", not app chrome.
            Picker(selection: $dailyGoalMinutes) {
                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { m in
                    Text("\(m) min").tag(m)
                }
            } label: {
                row(icon: "target",
                    title: "Daily goal",
                    subtitle: "Minutes of speaking per day")
            }
            // A menu of 60+ languages is a scroll inside a popover, so this
            // wants a whole pushed screen. It is NOT a `.navigationLink`
            // Picker: that style flattens Sections inside it, and the two
            // group headers came out looking like two untappable language
            // rows sitting among the languages. Hand-rolled list, real
            // headers and footers.
            NavigationLink {
                AppLanguagePage(selection: $appState.nativeLanguage,
                                groups: nativeChoiceGroups)
            } label: {
                // Names the EFFECT, not the fact: what this decides is which
                // language the app explains itself in.
                row(icon: "globe",
                    title: "App language",
                    subtitle: LanguageCatalog.endonym(appState.nativeLanguage))
            }
        } header: {
            Text("Learning")
        } footer: {
            Text(explain("Tap a language to practice it. Its level calibrates every conversation. The daily goal drives the ring on Home; explanations come back in your app language."))
        }
    }

    // MARK: - Daily call

    /// Opt-in and the hour. Deliberately two controls and no more: a call you
    /// have to configure is a call you don't get.
    private var dailyCallSection: some View {
        Section {
            Toggle(isOn: $dailyCallEnabled) {
                row(icon: "phone.arrow.down.left",
                    title: "Daily call",
                    subtitle: "Your fluent self phones you")
            }
            if dailyCallEnabled {
                // One row per call. More than one a day is the difference
                // between a reminder and a habit — the learner decides how
                // often somebody checks in on them, up to `maxTimes`.
                // Identity is the POSITION, not the time: CallTime's id is
                // its hour*60+minute, so keying rows on the value tore down
                // the row (and its open picker popover) on every wheel tick —
                // hour, minute and AM/PM each needed a fresh open. Sorting
                // and dedupe wait until the page closes for the same reason.
                ForEach(callTimes.indices, id: \.self) { index in
                    DatePicker(
                        selection: binding(at: index),
                        displayedComponents: .hourAndMinute
                    ) {
                        Label(explain("Call"), systemImage: "phone.arrow.down.left")
                    }
                }
                .onDelete { offsets in
                    // Deleting the last one would silently disable the call —
                    // the toggle above is where that decision belongs.
                    guard callTimes.count > offsets.count else { return }
                    callTimes.remove(atOffsets: offsets)
                    persistTimes()
                }
                if callTimes.count < DailyCallStore.maxTimes {
                    Button {
                        addCallTime()
                    } label: {
                        Label("Add a call", systemImage: "plus")
                    }
                }
                // The ALARM screen has room for one button we control, so it
                // can't offer a choice at ring time — this is that choice,
                // made once. (The notification fallback, which takes an array
                // of actions, does show all of them inline.)
                Picker(selection: $callbackMinutes) {
                    ForEach(DailyCallScheduler.callbackOptions, id: \.self) { m in
                        Text(DailyCallScheduler.callbackLabel(m)).tag(m)
                    }
                } label: {
                    Text("If you can't talk")
                }
            }
        } header: {
            Text("Call")
        } footer: {
            Text(explain(dailyCallEnabled
                ? "Your phone rings at every time you set here, even on silent. Can't talk? They ring back later — and if you never pick up, the message waits for you instead of counting against you."
                : "Instead of a reminder, your fluent self phones you once a day with a question to answer out loud. They remember how the last call went."))
        }
        .onChange(of: dailyCallEnabled) { _, on in
            Task { await setDailyCall(enabled: on) }
        }
        .onChange(of: callbackMinutes) { _, minutes in
            // No reschedule needed: this only decides how far the NEXT decline
            // pushes the callback, and that's read at decline time.
            DailyCallScheduler.defaultCallbackMinutes = minutes
        }
    }

    /// Turning it on is the one contextual moment where the notification
    /// prompt explains itself — the learner just asked to be called. A denial
    /// flips the toggle back rather than leaving it on over a call that can
    /// never ring.
    private func setDailyCall(enabled: Bool) async {
        guard enabled else {
            DailyCallStore.shared.isEnabled = false
            await DailyCallScheduler.cancel()
            return
        }
        guard await DailyCallScheduler.requestPermission() else {
            dailyCallEnabled = false
            DailyCallStore.shared.isEnabled = false
            return
        }
        DailyCallStore.shared.isEnabled = true
        appState.refreshDailyCall(force: true)
    }

    // MARK: - Voice

    /// Every consequence of making a new clone, on one confirm: it bills, it
    /// replaces, and the old voice is unrecoverable (the previous clone is
    /// deleted on ElevenLabs after the new one succeeds — only audio that was
    /// already synthesized keeps playing, via the PhraseAudioStore lineage).
    /// The "5 credits" figure mirrors priceFor("voice_clone") in
    /// supabase/functions/_shared/credits.ts — keep them in sync.
    private static var recloneWarning: String {
        explain("Cloning again uses a few minutes of talk time. Your current voice is replaced and deleted on ElevenLabs — you can't go back to it. Audio already generated keeps playing.")
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
            // On Bluetooth, a Talk call plays through the earphone's CALL
            // chain, which iOS's "Reduce Loud Sounds" headphone-safety cap
            // does NOT limit — so with the cap on, Talk can tower over every
            // listening surface. We can't detect the cap and won't tell
            // anyone to disable a hearing-safety setting; this slider lets
            // the call voice come DOWN to match instead.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Call voice volume", systemImage: "speaker.wave.2")
                    Spacer()
                    Text("\(Int(talkVoiceVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $talkVoiceVolume, in: 0.25...1.0, step: 0.05)
            }
            NavigationLink {
                VoicePresetPickerView(selection: $defaultSceneVoiceId)
                    .environmentObject(appState)
            } label: {
                row(icon: "person.wave.2",
                    title: "Scene partner voice: \(VoicePreset.by(id: defaultSceneVoiceId).displayName)",
                    subtitle: "For Watch scenes without a saved person")
            }
            if appState.voiceCloneId != nil,
               !VoiceAccentCatalog.options(for: appState.targetLanguage).isEmpty {
                let applied = VoiceAccentCatalog.options(for: appState.targetLanguage)
                    .first { $0.id == appState.voiceAccentId }
                Button {
                    pickingAccent = true
                } label: {
                    row(icon: "globe",
                        title: applied.map { "Accent: \($0.label)" } ?? "Accent",
                        subtitle: "Same voice, the accent you choose")
                }
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

    // MARK: - Subpages

    /// "08:00 · 13:00" while enabled, "Off" otherwise — the main list's
    /// one-line read of the call schedule.
    private var dailyCallSummary: String {
        guard dailyCallEnabled else { return "Off" }
        return callTimes
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }
            .joined(separator: " · ")
    }

    /// The row's one line. Someone who hasn't qualified still sees the club
    /// and its bar — the door has to be visible from outside or nobody walks
    /// toward it.
    private var coreClubSummary: String {
        guard let m = coreMembership else { return chrome("100 seats · 28 of 30 days to enter") }
        return m.seated
            ? chrome("Member #\(m.joinNumber) · \(m.daysTotal) days")
            : chrome("Member #\(m.joinNumber) · no seat right now")
    }

    private var planPage: some View {
        List {
            Section {
                // Tapping the balance opens the receipt: what spent minutes,
                // and what didn't. "N of M min" alone is the same opacity
                // that made beta users afraid to tap.
                NavigationLink {
                    UsageDetailView(account: account)
                } label: {
                    row(icon: "bolt.fill",
                        title: account.talkTimeLabel,
                        subtitle: "\(account.planLabel) · see where it went")
                }
                Button {
                    showingPaywall = true
                } label: {
                    row(icon: "sparkles",
                        title: account.planLabel == "Free" ? "See plans" : "Manage plan",
                        subtitle: "Talk time lands automatically every cycle")
                }
                NavigationLink {
                    CreditGuideView()
                } label: {
                    row(icon: "questionmark.circle",
                        title: "What uses talk time?",
                        subtitle: "And what's always free")
                }
                if BetaConfig.invitesAvailable {
                    NavigationLink {
                        InviteView()
                    } label: {
                        row(icon: "gift",
                            title: "Invite & earn talk time",
                            subtitle: "About an hour each, per friend")
                    }
                }
            } footer: {
                Text(BetaConfig.invitesAvailable
                    ? "Minutes buy talk time with your fluent self. Invite friends to earn more — reviewing always stays free."
                    : "Minutes buy talk time with your fluent self. Reviewing your words, drills, and dialogues always stays free.")
            }
        }
        .navigationTitle("Plan & talk time")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dailyCallPage: some View {
        List { dailyCallSection }
            .navigationTitle("Daily call")
            .navigationBarTitleDisplayMode(.inline)
            // Editing persists un-sorted so open pickers keep their row (see
            // persistTimes); pick up the store's sorted, deduped read here.
            .onDisappear { callTimes = DailyCallStore.shared.times }
    }

    private var voicePage: some View {
        List { voiceSection }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var appearancePage: some View {
        List {
            Section {
                Picker("Theme", selection: $appState.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                FutureselfThemePicker()
            } footer: {
                Text(explain("Future self is the pixel surface behind every call button — tap a theme to feel it."))
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dataPage: some View {
        List { backupSection }
            .navigationTitle("Practice data")
            .navigationBarTitleDisplayMode(.inline)
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

extension MeTab {
    /// Bridges one stored `CallTime` to the `Date` a `DatePicker` needs.
    /// Editing writes straight back through to the store so a call the learner
    /// just moved is rescheduled even if they close Me immediately. Index-
    /// addressed so an edit updates the row IN PLACE — resolving by value
    /// broke the moment the value changed under the open picker.
    func binding(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard callTimes.indices.contains(index) else { return Date() }
                let time = callTimes[index]
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                guard callTimes.indices.contains(index) else { return }
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                callTimes[index] = DailyCallStore.CallTime(hour: parts.hour ?? 8,
                                                           minute: parts.minute ?? 0)
                persistTimes()
            })
    }

    /// A new call three hours after the last one — far enough that it reads as
    /// a separate check-in rather than a repeat of the one just missed.
    func addCallTime() {
        let last = callTimes.max() ?? DailyCallStore.CallTime(hour: 8, minute: 0)
        let proposed = (last.hour + 3) % 24
        var candidate = DailyCallStore.CallTime(hour: proposed, minute: last.minute)
        // Never collide: identical times dedupe in the store and the row would
        // silently vanish.
        while callTimes.contains(candidate) {
            candidate = DailyCallStore.CallTime(hour: (candidate.hour + 1) % 24,
                                                minute: candidate.minute)
        }
        callTimes.append(candidate)
        persistTimes()
    }

    /// Persist WITHOUT re-reading: the store sorts and dedupes internally
    /// (the scheduler always sees clean times), but syncing that back into
    /// `callTimes` mid-edit reordered rows under the learner's finger and
    /// closed the open picker. The working copy re-syncs when the page
    /// closes (`dailyCallPage.onDisappear`).
    func persistTimes() {
        DailyCallStore.shared.times = callTimes
        appState.refreshDailyCall()
    }
}

/// The app-language list, split in two because the app can only half-keep the
/// promise its name makes: a handful of languages are translated end to end;
/// the other 60-odd get LLM coaching text — corrections, notes, word meanings
/// — in their language, with the app's own static copy staying English. The
/// split has to say that BEFORE the choice, which is what the group footers
/// are for; a header alone reads as a category name, not a caveat.
private struct AppLanguagePage: View {
    @Binding var selection: String
    let groups: (translated: [String], coachingOnly: [String])
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(groups.translated, id: \.self, content: choice)
            } header: {
                Text(explain("Fully translated"))
            } footer: {
                Text(explain("Everything you read in the app — menus, buttons, corrections, notes — is in this language."))
            }
            Section {
                ForEach(groups.coachingOnly, id: \.self, content: choice)
            } header: {
                Text(explain("Corrections and notes only"))
            } footer: {
                Text(explain("Your corrections, notes and word meanings come back in this language. The app's own menus and buttons stay English."))
            }
        }
        .navigationTitle("App language")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Picking pops back, the way a pushed Settings list does — staying put
    /// after a checkmark moves leaves the learner wondering if it took.
    private func choice(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                Text(LanguageCatalog.endonym(code))
                    .foregroundStyle(.primary)
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#if DEBUG
/// The Developer section's confirmations, kept out of `MeTab.body` — that
/// chain is long enough that adding two more `.alert`s to it made the
/// expression un-type-checkable.
private struct DeveloperAlerts: ViewModifier {
    @Binding var confirmingOnboardingReset: Bool
    @Binding var confirmingAudioCacheClear: Bool
    var onResetOnboarding: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Clear voice cache?", isPresented: $confirmingAudioCacheClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    PhraseAudioStore.shared.clearCachedAudio()
                }
            } message: {
                Text(explain("Deletes cached voice audio only. Your talks, drills, words and books are untouched. Every line synthesizes again the next time it plays."))
            }
            .alert("Replay onboarding?", isPresented: $confirmingOnboardingReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { onResetOnboarding() }
            } message: {
                Text(explain("Clears setup, voice clone and persona, then restarts the first-run flow. You stay signed in."))
            }
    }
}
#endif
