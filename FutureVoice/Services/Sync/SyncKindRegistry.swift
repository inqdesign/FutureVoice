import Foundation

/// Every kind the sync carries, with its rule. Order matters where one kind
/// writes into another's file (persona before its notes).
///
/// The rules in one place, because they ARE the feature:
/// - a talk is a talk: union by id, the newer edit wins, a deletion wins
///   outright and takes its cards and audio with it;
/// - a card's progress is monotone: box, times seen, "used in a talk" all
///   take the higher side, and a card deleted with its talk stays deleted;
/// - a word's state only ever climbs (used > known), counts take the max;
/// - notebook membership, snoozes and hand-removals are last-writer-wins,
///   because the learner's most recent decision is the decision;
/// - a dismissed expression stays dismissed everywhere;
/// - per-day counters take the max per day, never the sum (both devices
///   saw the same day).
enum SyncKindRegistry {

    /// Computed, not stored: the blob folders resolve against
    /// `SyncFiles.documents`, which the tests point at scratch trees.
    static var all: [any SyncKindHandler] { [
        sessionKind,
        drillKind,
        vocabRecordKind,
        vocabExpressionKind,
        StringListKind(kind: .vocabStudying, filename: "vocab_studying.json", ordered: true,
                       mergeRule: SyncMerge.lww, afterWrite: reloadVocab),
        StringListKind(kind: .vocabStudyingExpression, filename: "vocab_studying_expressions.json",
                       ordered: true, mergeRule: SyncMerge.lww, afterWrite: reloadVocab),
        StringListKind(kind: .vocabRemovedByHand, filename: "vocab_removed_by_hand.json",
                       ordered: false, mergeRule: SyncMerge.lww, afterWrite: reloadVocab),
        StringListKind(kind: .vocabAutoKept, filename: "vocab_auto_kept.json",
                       ordered: false, mergeRule: SyncMerge.lww, afterWrite: reloadVocab),
        StringListKind(kind: .vocabDismissed, filename: "vocab_dismissed_expressions.json",
                       ordered: false, mergeRule: { SyncMerge.union($0, $1) { a, _ in a } },
                       afterWrite: reloadVocab),
        DictKind<Int>(kind: .vocabIngested, filename: "vocab_ingested.json",
                      encoder: SyncFiles.bareEncoder, decoder: SyncFiles.bareDecoder,
                      mergeRule: { SyncMerge.union($0, $1, combine: SyncMerge.typed { (a: Int, b: Int) in max(a, b) }) },
                      afterWrite: reloadVocab),
        VocabExpressionIngestedKind(),
        DictKind<StudyScheduleStore.Entry>(kind: .schedule, filename: "study-schedule.json",
                                           mergeRule: SyncMerge.lww,
                                           afterWrite: { lang in
                                               if isActive(lang) { StudyScheduleStore.shared.languageScopeDidChange() }
                                           }),
        shadowKind,
        ArrayKind<SavedLine>(kind: .savedLine, filename: "saved_lines.json", mergeRule: SyncMerge.lww),
        ArrayKind<WatchDialogue>(kind: .dialogue, filename: "watch-dialogues.json", mergeRule: SyncMerge.lww,
                                 sortForFile: { $0.sorted { $0.createdAt > $1.createdAt } }),
        ArrayKind<WeeklyReport>(kind: .weekly, filename: "weekly-reports.json", mergeRule: SyncMerge.lww,
                                sortForFile: { $0.sorted { $0.generatedAt > $1.generatedAt } }),
        ArrayKind<WeeklyTest>(kind: .weeklyTest, filename: "weekly-tests.json", mergeRule: SyncMerge.lww,
                              sortForFile: { $0.sorted { $0.createdAt > $1.createdAt } }),
        scenarioKind,
        DictKind<PracticeLog.Day>(kind: .practiceDay, filename: "practice-log.json",
                                  encoder: SyncFiles.bareEncoder, decoder: SyncFiles.bareDecoder,
                                  mergeRule: { SyncMerge.union($0, $1, combine: SyncMerge.typed(maxDay)) },
                                  afterWrite: { _ in PracticeLog.shared.reloadFromDisk() }),
        DefaultsCountKind(kind: .talkDay, defaultsKey: "futurevoice.talkSecondsByDay"),
        DefaultsCountKind(kind: .usageDay, defaultsKey: "futurevoice.foregroundSecondsByDay"),
        PersonaKind(),
        PersonaNoteKind(),
        ProfileKind(),
        counterpartKind,
        DefaultsKind(),
        BlobKind(kind: .blobTurn, directory: SyncFiles.documents.appendingPathComponent("TurnAudio", isDirectory: true)),
        BlobKind(kind: .blobRecording, directory: SyncFiles.documents.appendingPathComponent("Recordings", isDirectory: true)),
        BlobKind(kind: .blobVoiceSample,
                 directory: SyncFiles.documents.appendingPathComponent(VoiceSampleStore.syncFolder, isDirectory: true),
                 accepts: { $0.hasSuffix(".wav") }),
    ] }

    static func handler(for kind: SyncKind) -> (any SyncKindHandler)? {
        all.first { $0.kind == kind }
    }

    /// Whether a language-scoped write touched the language the stores are
    /// currently pointed at — only then is there anything in memory to refresh.
    static func isActive(_ lang: String?) -> Bool {
        lang == nil || lang == LanguageScope.active
    }

    @MainActor
    private static func reloadVocab(_ lang: String?) {
        if isActive(lang) { VocabStore.shared.languageScopeDidChange() }
    }

    // MARK: - Sessions

    private static var sessionKind: ArrayKind<Session> {
        ArrayKind<Session>(
            kind: .session, filename: "sessions.json",
            outbound: { session in
                // `audioURL` is an absolute path inside THIS install's
                // sandbox; every reader falls back to `TurnAudioStore`, which
                // is where the synced audio lands.
                var s = session
                for i in s.turns.indices { s.turns[i].audioURL = nil }
                return s
            },
            mergeRule: { local, remote in remote.deleted ? nil : SyncMerge.lww(local, remote) },
            sortForFile: { $0.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) } },
            cascadeRule: { key, lang, previous in
                guard let id = UUID(uuidString: key), let lang else { return [] }
                return [.sessionDeleted(sessionId: id, turnIds: previous?.turns.map(\.id) ?? [], lang: lang)]
            },
            afterWrite: { lang in
                if isActive(lang) { SessionStore.shared.invalidateCache() }
            })
    }

    // MARK: - Drill cards

    private static var drillKind: ArrayKind<DrillCard> {
        ArrayKind<DrillCard>(
            kind: .drill, filename: "drills.json",
            mergeRule: { local, remote in
                SyncMerge.tombstoneWins(local, remote, combine: SyncMerge.typed(mergeCards))
            },
            collapse: DrillStore.deduplicated)
    }

    /// Two copies of one card: progress is monotone, so every counter takes
    /// the higher side, and the schedule follows the box that won.
    static func mergeCards(_ a: DrillCard, _ b: DrillCard) -> DrillCard {
        var out = a.box >= b.box ? a : b
        let other = a.box >= b.box ? b : a
        out.timesSeen = max(a.timesSeen, b.timesSeen)
        out.timesCorrect = max(a.timesCorrect, b.timesCorrect)
        out.lastReviewedAt = laterOf(a.lastReviewedAt, b.lastReviewedAt)
        out.usedInTalkAt = laterOf(a.usedInTalkAt, b.usedInTalkAt)
        if out.enrichment == nil { out.enrichment = other.enrichment }
        if a.box == b.box {
            // Same rung: the more recent review set the return date.
            out.nextReviewAt = (a.lastReviewedAt ?? .distantPast) >= (b.lastReviewedAt ?? .distantPast)
                ? a.nextReviewAt : b.nextReviewAt
        }
        if out.box >= DrillStore.maxBox { out.nextReviewAt = DrillStore.retiredReviewDate }
        return out
    }

    // MARK: - Vocabulary

    private static var vocabRecordKind: DictKind<VocabStore.Record> {
        DictKind<VocabStore.Record>(kind: .vocabRecord, filename: "vocab_pool.json",
                                    encoder: SyncFiles.bareEncoder, decoder: SyncFiles.bareDecoder,
                                    mergeRule: { SyncMerge.combineOrNewerDelete($0, $1, combine: SyncMerge.typed(mergeRecords)) },
                                    afterWrite: reloadVocab)
    }

    private static var vocabExpressionKind: DictKind<VocabStore.Record> {
        DictKind<VocabStore.Record>(kind: .vocabExpression, filename: "vocab_expressions.json",
                                    encoder: SyncFiles.bareEncoder, decoder: SyncFiles.bareDecoder,
                                    mergeRule: { SyncMerge.combineOrNewerDelete($0, $1, combine: SyncMerge.typed(mergeRecords)) },
                                    afterWrite: reloadVocab)
    }

    /// used > known; the count is the max, not the sum — both devices may
    /// have counted the same talk.
    static func mergeRecords(_ a: VocabStore.Record, _ b: VocabStore.Record) -> VocabStore.Record {
        VocabStore.Record(
            state: (a.state == .used || b.state == .used) ? .used : .known,
            firstAt: min(a.firstAt, b.firstAt),
            lastAt: max(a.lastAt, b.lastAt),
            count: max(a.count, b.count),
            fromStudying: (a.fromStudying == true || b.fromStudying == true) ? true : nil)
    }

    // MARK: - Shadow attempts

    private static var shadowKind: ArrayKind<ShadowAttempt> {
        ArrayKind<ShadowAttempt>(
            kind: .shadow, filename: "shadow-attempts.json",
            mergeRule: SyncMerge.lww,
            sortForFile: { $0.sorted { $0.createdAt > $1.createdAt } },
            cascadeRule: { _, _, previous in
                guard let name = previous?.recordingFilename else { return [] }
                return [.deleteFile(kind: .blobRecording, key: name)]
            })
    }

    // MARK: - Scenarios

    private static var scenarioKind: ArrayKind<Scenario> {
        ArrayKind<Scenario>(
            kind: .scenario, filename: "scenarios.json",
            mergeRule: { local, remote in
                // The newer edit is the scenario; the book's study items
                // are the union of both, keeping the earliest mastery.
                guard let local, let lp = local.payload, !local.deleted,
                      !remote.deleted, let rp = remote.payload, lp != rp,
                      let a = try? SyncCanonical.decode(Scenario.self, from: lp),
                      let b = try? SyncCanonical.decode(Scenario.self, from: rp)
                else { return SyncMerge.lww(local, remote) }
                var winner = remote.at >= local.at ? b : a
                let loser = remote.at >= local.at ? a : b
                winner.curriculum = mergeCurricula(winner.curriculum, loser.curriculum)
                winner.lastUsedAt = laterOf(a.lastUsedAt, b.lastUsedAt)
                return (try? SyncCanonical.encode(winner)) ?? rp
            })
    }

    static func mergeCurricula(_ a: ScenarioCurriculum?, _ b: ScenarioCurriculum?) -> ScenarioCurriculum? {
        guard var out = a else { return b }
        guard let b else { return out }
        func merged(_ mine: [ScenarioCurriculum.Item], _ theirs: [ScenarioCurriculum.Item]) -> [ScenarioCurriculum.Item] {
            var result = mine
            for item in theirs {
                if let i = result.firstIndex(where: { $0.text.lowercased() == item.text.lowercased() }) {
                    result[i].masteredAt = earlierOf(result[i].masteredAt, item.masteredAt)
                } else {
                    result.append(item)
                }
            }
            return result
        }
        out.words = merged(out.words, b.words)
        out.expressions = merged(out.expressions, b.expressions)
        out.shadowLines = merged(out.shadowLines, b.shadowLines)
        return out
    }

    // MARK: - Counterparts

    private static var counterpartKind: ArrayKind<Counterpart> {
        ArrayKind<Counterpart>(
            kind: .counterpart, filename: "counterparts.json",
            mergeRule: { local, remote in
                SyncMerge.combineOrNewerDelete(local, remote, combine: SyncMerge.typed { (a: Counterpart, b: Counterpart) in
                    a.updatedAt >= b.updatedAt ? a : b
                })
            },
            sortForFile: { $0.sorted { $0.updatedAt > $1.updatedAt } },
            collapse: { list in
                // One row per Find-people persona, like `CounterpartStore.save`.
                var seen: Set<String> = []
                return list.sorted { $0.updatedAt > $1.updatedAt }.filter { c in
                    guard let rid = c.remoteId else { return true }
                    return seen.insert(rid).inserted
                }
            })
    }

    // MARK: - Practice log

    static func maxDay(_ a: PracticeLog.Day, _ b: PracticeLog.Day) -> PracticeLog.Day {
        var d = PracticeLog.Day()
        d.drillReps = max(a.drillReps, b.drillReps)
        d.shadowReps = max(a.shadowReps, b.shadowReps)
        d.wordReps = max(a.wordReps, b.wordReps)
        d.expressionReps = max(a.expressionReps, b.expressionReps)
        d.drillDone = max(a.drillDone, b.drillDone)
        d.shadowDone = max(a.shadowDone, b.shadowDone)
        d.wordDone = max(a.wordDone, b.wordDone)
        d.expressionDone = max(a.expressionDone, b.expressionDone)
        d.sceneReps = max(a.sceneReps, b.sceneReps)
        return d
    }

    // MARK: - Helpers

    static func laterOf(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }

    static func earlierOf(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return min(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }
}

// MARK: - VocabStore's expression-ingest meta

/// `vocab_expressions_ingested.json`: which expression keys each session has
/// already been counted for. Keyed by session; the merge is a union of keys,
/// and "legacy" (counted before per-key tracking) is sticky.
struct VocabExpressionIngestedKind: SyncKindHandler {
    let kind: SyncKind = .vocabExpressionIngested
    private let filename = "vocab_expressions_ingested.json"

    /// Mirror of VocabStore's private on-disk struct.
    struct Meta: Codable {
        var keysBySession: [String: Set<String>]
        var legacySessions: Set<UUID>
    }
    struct Entry: Codable {
        var keys: [String]
        var legacy: Bool
    }

    private func readMeta(lang: String?) -> Meta? {
        let url = SyncFiles.url(filename, lang: lang)
        guard let data = try? Data(contentsOf: url) else {
            return Meta(keysBySession: [:], legacySessions: [])
        }
        if let meta = try? SyncFiles.bareDecoder.decode(Meta.self, from: data) { return meta }
        if let ids = try? SyncFiles.bareDecoder.decode(Set<UUID>.self, from: data) {
            return Meta(keysBySession: [:], legacySessions: ids)
        }
        return nil
    }

    func read(lang: String?) -> SyncSnapshot? {
        guard let meta = readMeta(lang: lang) else { return nil }
        var entries: [String: Entry] = [:]
        for (session, keys) in meta.keysBySession {
            entries[session] = Entry(keys: keys.sorted(), legacy: false)
        }
        for id in meta.legacySessions {
            entries[id.uuidString, default: Entry(keys: [], legacy: true)].legacy = true
        }
        var out: SyncSnapshot = [:]
        for (session, entry) in entries {
            if let data = try? SyncCanonical.encode(entry) { out[session] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        SyncMerge.union(local, remote, combine: SyncMerge.typed { (a: Entry, b: Entry) in
            Entry(keys: Array(Set(a.keys).union(b.keys)).sorted(), legacy: a.legacy || b.legacy)
        })
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        var meta = Meta(keysBySession: [:], legacySessions: [])
        for (session, item) in items {
            guard let entry = try? SyncCanonical.decode(Entry.self, from: item.payload) else { continue }
            if !entry.keys.isEmpty { meta.keysBySession[session] = Set(entry.keys) }
            if entry.legacy, let id = UUID(uuidString: session) { meta.legacySessions.insert(id) }
        }
        try SyncFiles.write(meta, to: SyncFiles.url(filename, lang: lang), encoder: SyncFiles.bareEncoder)
        if SyncKindRegistry.isActive(lang) { VocabStore.shared.languageScopeDidChange() }
    }
}

// MARK: - Persona (scalars) and its notes

/// The profile the learner typed. One item; the newer `updatedAt` wins.
/// `learnedNotes` are carried separately (`PersonaNoteKind`) so a note added
/// on the tablet and a city edited on the phone both survive.
struct PersonaKind: SyncKindHandler {
    let kind: SyncKind = .persona
    static let key = "persona"

    private var url: URL { SyncFiles.url("persona.json", lang: nil) }

    func read(lang: String?) -> SyncSnapshot? {
        guard let persona = SyncFiles.read(UserPersona?.self, at: url, decoder: SyncFiles.storeDecoder, empty: nil)
        else { return nil }
        guard var p = persona else { return [:] }
        p.learnedNotes = []
        guard let data = try? SyncCanonical.encode(p) else { return nil }
        return [Self.key: data]
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        SyncMerge.combineOrNewerDelete(local, remote, combine: SyncMerge.typed { (a: UserPersona, b: UserPersona) in
            a.updatedAt >= b.updatedAt ? a : b
        })
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        guard let item = items[Self.key],
              var incoming = try? SyncCanonical.decode(UserPersona.self, from: item.payload)
        else {
            // Deleted everywhere — only the debug reset does this.
            if items.isEmpty { try? FileManager.default.removeItem(at: url) }
            return
        }
        let current = SyncFiles.read(UserPersona?.self, at: url, decoder: SyncFiles.storeDecoder, empty: nil) ?? nil
        incoming.learnedNotes = current?.learnedNotes ?? []
        try SyncFiles.write(incoming, to: url, encoder: SyncFiles.storeEncoder)
    }
}

struct PersonaNoteKind: SyncKindHandler {
    let kind: SyncKind = .personaNote

    private var url: URL { SyncFiles.url("persona.json", lang: nil) }

    func read(lang: String?) -> SyncSnapshot? {
        guard let persona = SyncFiles.read(UserPersona?.self, at: url, decoder: SyncFiles.storeDecoder, empty: nil)
        else { return nil }
        var out: SyncSnapshot = [:]
        for note in persona?.learnedNotes ?? [] {
            if let data = try? SyncCanonical.encode(note) { out[note.id.uuidString] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? { SyncMerge.lww(local, remote) }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        var persona = (SyncFiles.read(UserPersona?.self, at: url, decoder: SyncFiles.storeDecoder, empty: nil) ?? nil)
            ?? UserPersona.empty
        var notes: [PersonaNote] = items.values.compactMap { try? SyncCanonical.decode(PersonaNote.self, from: $0.payload) }
        // The model re-tells the same fact in different words; keep one per
        // dedupe key, the most recently learned.
        var byKey: [String: PersonaNote] = [:]
        for note in notes {
            if let existing = byKey[note.dedupeKey], existing.learnedAt >= note.learnedAt { continue }
            byKey[note.dedupeKey] = note
        }
        notes = byKey.values.sorted { $0.learnedAt < $1.learnedAt }
        persona.learnedNotes = notes
        try SyncFiles.write(persona, to: url, encoder: SyncFiles.storeEncoder)
    }
}

// MARK: - Learner profile (one per target language)

struct ProfileKind: SyncKindHandler {
    let kind: SyncKind = .profile
    private var url: URL { SyncFiles.url("profile.json", lang: nil) }

    func read(lang: String?) -> SyncSnapshot? {
        guard let list = SyncFiles.read([LearnerProfile].self, at: url, decoder: SyncFiles.storeDecoder, empty: [])
        else { return nil }
        var out: SyncSnapshot = [:]
        for profile in list {
            if let data = try? SyncCanonical.encode(profile) { out[profile.targetLanguage] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        SyncMerge.combineOrNewerDelete(local, remote, combine: SyncMerge.typed { (a: LearnerProfile, b: LearnerProfile) in
            // The profile that has seen more talks is the fuller memory.
            (a.lastSessionAt ?? .distantPast) >= (b.lastSessionAt ?? .distantPast) ? a : b
        })
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        let list = items.values.compactMap { try? SyncCanonical.decode(LearnerProfile.self, from: $0.payload) }
        try SyncFiles.write(list, to: url, encoder: SyncFiles.storeEncoder)
    }
}

// MARK: - Settings that are part of the practice

/// The handful of `futurevoice.*` defaults that describe HOW the learner
/// practises — languages, level, goals. Account and per-install keys (the
/// voice, consent, the daily call) never go here: see `BackupService`'s
/// exclusion list for the same line.
struct DefaultsKind: SyncKindHandler {
    let kind: SyncKind = .defaults

    static let keys: [String] = [
        "futurevoice.nativeLanguage",
        "futurevoice.targetLanguage",
        "futurevoice.enrolledLanguages",
        "futurevoice.proficiency",
        "futurevoice.dailyGoalMinutes",
        "futurevoice.goal.sentencesPerDay",
        "futurevoice.goal.wordsPerDay",
        "futurevoice.goal.expressionsPerDay",
        "futurevoice.goal.shadowsPerDay",
        "futurevoice.vocab.hideKnown",
    ]

    enum Value: Codable, Equatable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case double(Double)
        case strings([String])

        init?(_ any: Any) {
            switch any {
            case let s as String: self = .string(s)
            case let b as Bool: self = .bool(b)
            case let i as Int: self = .int(i)
            case let d as Double: self = .double(d)
            case let list as [String]: self = .strings(list)
            default: return nil
            }
        }

        var any: Any {
            switch self {
            case .string(let s): return s
            case .int(let i): return i
            case .bool(let b): return b
            case .double(let d): return d
            case .strings(let l): return l
            }
        }
    }

    func read(lang: String?) -> SyncSnapshot? {
        var out: SyncSnapshot = [:]
        for key in Self.keys {
            guard let raw = UserDefaults.standard.object(forKey: key) else { continue }
            // `Bool` bridges as a number; the keys that are booleans are
            // known, so decode them as such rather than as 0/1.
            let value: Value?
            if key == "futurevoice.vocab.hideKnown" {
                value = .bool(UserDefaults.standard.bool(forKey: key))
            } else {
                value = Value(raw)
            }
            if let value, let data = try? SyncCanonical.encode(value) { out[key] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        // Enrolled languages are a union: un-enrolling is rare and the
        // safer failure is a language still listed.
        if let lp = local?.payload, let rp = remote.payload, !remote.deleted,
           case .strings(let a)? = try? SyncCanonical.decode(Value.self, from: lp),
           case .strings(let b)? = try? SyncCanonical.decode(Value.self, from: rp) {
            var merged = a
            for code in b where !merged.contains(code) { merged.append(code) }
            return (try? SyncCanonical.encode(Value.strings(merged))) ?? rp
        }
        return SyncMerge.lww(local, remote)
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        let defaults = UserDefaults.standard
        for key in Self.keys {
            guard let item = items[key],
                  let value = try? SyncCanonical.decode(Value.self, from: item.payload)
            else { continue }
            defaults.set(value.any, forKey: key)
        }
    }
}
