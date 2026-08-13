import Foundation

/// A store whose records belong to (user, lang) — see docs/multi-language-plan.md.
/// On a language switch the store re-resolves its file URL(s) against
/// `LanguageScope.activeDirectory` and drops any in-memory cache. Stores with
/// background readers (SessionStore) must do this under their own lock.
protocol LanguageScopedStore: AnyObject {
    func languageScopeDidChange()
}

/// The multi-language contract (docs/multi-language-plan.md): every learning
/// record belongs to (user, lang); identity and assets — voice clone, avatar,
/// personas, counterparts, credits, cached TTS audio, shadow recordings —
/// belong to the user alone. Locally the contract materializes as one
/// subdirectory per enrolled target language, `Documents/lang/<code>/`,
/// holding that language's JSON stores; global stores keep writing to the
/// Documents root.
///
/// Stores are process-lifetime singletons, several with in-memory caches, so
/// switching languages is a store-level event, not a view-level one:
/// `repointStores()` walks every scoped store. View state resets separately
/// via `.id(appState.targetLanguage)` in RootView.
enum LanguageScope {

    static let enrolledDefaultsKey = "futurevoice.enrolledLanguages"

    /// The active target language code. Single source of truth is the same
    /// UserDefaults key AppState's `targetLanguage` persists to — store path
    /// resolution and non-UI services (CoreVocabulary, VocabStore's
    /// lemmatizer route) read it from here without touching UI state.
    static var active: String {
        UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en"
    }

    /// Enrolled target languages in enrollment order. Never empty — an
    /// install that predates multi-language reads as enrolled in its active
    /// language.
    static var enrolled: [String] {
        let stored = UserDefaults.standard.stringArray(forKey: enrolledDefaultsKey) ?? []
        return stored.isEmpty ? [active] : stored
    }

    /// `Documents/lang/<code>/`, created on demand so store inits and
    /// post-wipe writes always get a writable location.
    static func directory(for code: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("lang", isDirectory: true)
            .appendingPathComponent(code, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var activeDirectory: URL { directory(for: active) }

    /// Every language-scoped store singleton, walked after the active pointer
    /// moves. A NEW scoped store MUST be added here — one that isn't keeps
    /// serving the previous language's data until relaunch, silently.
    @MainActor
    static func repointStores() {
        let stores: [any LanguageScopedStore] = [
            SessionStore.shared,
            DrillStore.shared,
            ScenarioStore.shared,
            WatchDialogueStore.shared,
            ShadowAttemptStore.shared,
            StudyScheduleStore.shared,
            SavedLineStore.shared,
            TopicStore.shared,
            NewsTopicStore.shared,
            WeeklyReportStore.shared,
        ]
        for store in stores { store.languageScopeDidChange() }
        // Main-actor-isolated store — same contract, called directly rather
        // than through the nonisolated protocol.
        VocabStore.shared.languageScopeDidChange()
    }

    // MARK: - One-time layout migration

    private static let migratedKey = "futurevoice.langScopeMigrated"

    /// Files that belong to (user, lang). Everything else in Documents —
    /// profile.json (keyed by language in-file), persona.json,
    /// counterparts.json, avatar, PhraseAudio/, TurnAudio/, Recordings/ —
    /// is global and stays at the root.
    private static let scopedFilenames = [
        "sessions.json", "drills.json", "scenarios.json",
        "watch-dialogues.json", "shadow-attempts.json", "saved_lines.json",
        "topics.json", "news_topics.json", "weekly-reports.json",
        "vocab_pool.json", "vocab_ingested.json", "vocab_studying.json",
        "vocab_expressions.json", "vocab_expressions_ingested.json",
        "vocab_studying_expressions.json",
    ]

    /// Mirrors the pre-multi-language flat layout into `lang/<active>/`. MUST
    /// run before any store singleton is touched (FutureVoiceApp.init) —
    /// store inits resolve their paths against the scoped directory.
    ///
    /// **Copies. Never deletes the original.** An older build reads only the
    /// Documents root, so moving the files makes a downgrade — a TestFlight
    /// tester rolling back a build, a developer switching branches — look
    /// exactly like total data loss. Leaving the originals in place lets the
    /// two layouts coexist: the old build still finds everything where it
    /// left it. The cost is one duplicate of a handful of small JSON files.
    ///
    /// Deliberately NOT re-synced afterwards. Once migrated, this build owns
    /// `lang/<code>/` and the root copy freezes as the old build's view. A
    /// "copy whichever side is newer" rule would look smarter and would be a
    /// trap: a week spent on the old build would silently overwrite a month
    /// made on the new one. Frozen means a rollback can hide recent work from
    /// one side, but nothing is ever destroyed.
    ///
    /// Per file: copy → verify size. The done-flag is set only if every file
    /// present at the root copied cleanly, so a crash mid-way retries on the
    /// next launch (a half-written destination is replaced, not appended to).
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = activeDirectory   // pre-existing data belongs to the current target

        var allCopied = true
        for name in scopedFilenames {
            let src = docs.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name)
            try? fm.removeItem(at: dst)   // stale partial copy from a crashed run
            guard (try? fm.copyItem(at: src, to: dst)) != nil,
                  fileSize(src) == fileSize(dst) else {
                allCopied = false
                continue
            }
        }
        if allCopied { defaults.set(true, forKey: migratedKey) }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
