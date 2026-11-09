import Foundation
import Supabase

/// One fact about what a learner has learned (docs/learner-record.md). Never
/// the content of a conversation: the server's `learner_events_put` refuses
/// anything outside its list of kinds and value keys.
struct LearnerEvent: Equatable {
    var key: String
    var language: String
    var occurredAt: Date
    var sourceId: String?
    var kind: String
    var subject: String
    var value: [String: AnyJSON]

    /// What decides whether the server already has this fact. The date is left
    /// out on purpose: "studying" has no date of its own, and a fact that has
    /// not changed must not be sent again.
    var fingerprint: String {
        let body = value.keys.sorted().map { "\($0)=\(value[$0].map(String.init(describing:)) ?? "")" }
        return ([kind, subject, sourceId ?? ""] + body).joined(separator: "|")
    }
}

/// Finds what changed by comparing today's facts with what was last sent, the
/// way `SyncEngine` does, so no store's write path has to know about this and
/// the first pass carries the learner's history.
enum LearnerEventDiff {
    struct Sent: Codable, Equatable {
        var fingerprint: String
        var sourceId: String?
    }

    struct Plan: Equatable {
        /// Sources to clear first: something of theirs no longer exists.
        var forget: [String]
        var put: [LearnerEvent]
    }

    /// A fact that vanished clears its whole source, and the source's facts
    /// that still exist are sent again in the same pass. The server can only
    /// forget by source, and a talk tagged again may lose one item.
    static func plan(current: [LearnerEvent], sent: [String: Sent]) -> Plan {
        let keys = Set(current.map(\.key))
        let forget = Set(sent.filter { !keys.contains($0.key) }.compactMap(\.value.sourceId))
        let put = current.filter { event in
            if let source = event.sourceId, forget.contains(source) { return true }
            return sent[event.key]?.fingerprint != event.fingerprint
        }
        return Plan(forget: forget.sorted(), put: put)
    }

    /// What is on file after this plan's forgets, before any put lands.
    static func afterForgetting(_ sources: [String], sent: [String: Sent]) -> [String: Sent] {
        let gone = Set(sources)
        return sent.filter { entry in entry.value.sourceId.map { !gone.contains($0) } ?? true }
    }
}

/// Reads the stores and writes down what they say, for the active language.
@MainActor
enum LearnerEventBuilder {
    static let maxExpressionWords = 6
    static let maxTypedLength = 300
    static let dayWindow = 45

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func build(language: String, now: Date = Date()) async -> [LearnerEvent] {
        var out: [LearnerEvent] = []
        func add(_ key: String, _ when: Date, source: String? = nil, _ kind: String,
                 _ subject: String, _ value: [String: AnyJSON]) {
            out.append(.init(key: key, language: language, occurredAt: when, sourceId: source,
                             kind: kind, subject: subject, value: value))
        }
        func typed(_ field: String, _ text: String) {
            let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTypedLength))
            guard !t.isEmpty else { return }
            add("setup:\(field)", now, source: nil, "setup", field, ["value": .string(t)])
        }

        // Setup.
        typed("native_language", LanguageCatalog.currentNative)
        typed("level", UserDefaults.standard.string(forKey: AppState.proficiencyKey) ?? "")
        typed("purposes", LearningPurposeStore.purposes.map(\.rawValue).joined(separator: ","))
        if let p = PersonaStore.shared.load() {
            typed("occupation", p.occupation)
            typed("city", p.city)
            typed("country", p.country)
            typed("interests", p.interests.joined(separator: ", "))
            typed("situations", p.situations.joined(separator: ", "))
            typed("future_goals", p.goals.joined(separator: ", "))
        }

        // Goals, without any attached material.
        for g in UpcomingGoalStore.shared.goals
        where LanguageCatalog.sameLanguage(g.language, language) {
            var value: [String: AnyJSON] = ["kind": .string(g.kind.rawValue),
                                            "title": .string(String(g.title.prefix(500)))]
            if let d = g.date { value["date"] = .string(dayFormat.string(from: d)) }
            if !g.place.isEmpty { value["place"] = .string(String(g.place.prefix(500))) }
            if !g.notes.isEmpty { value["notes"] = .string(String(g.notes.prefix(500))) }
            add("goal:\(g.id.uuidString)", g.updatedAt, source: g.id.uuidString, "goal",
                g.id.uuidString, value)
        }

        // Talks and their grammar and speaking items.
        for s in SessionStore.shared.load() where s.endedAt != nil && s.summary != nil {
            let id = s.id.uuidString
            let m = ScorecardMetrics.compute(turns: s.turns)
            var value: [String: AnyJSON] = [
                "minutes": .integer(Int((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 60)),
                "mode": .string(s.isPractice ? "practice" : "talk"),
                "learner_words": .integer(m.userWordCount),
                "turns": .integer(m.userTurnCount),
                "wpm": .integer(Int(m.wordsPerMinute.rounded())),
                "pauses": .integer(Int(m.pausesPerMinute.rounded())),
            ]
            if let c = s.summary?.scorecard {
                value["vocabulary"] = .integer(c.vocabulary.score)
                value["grammar"] = .integer(c.grammar.score)
                value["expressiveness"] = .integer(c.expressiveness.score)
                value["fluency"] = .integer(c.fluency.score)
                if let p = c.pronunciation { value["pronunciation"] = .integer(p.score) }
                if let l = c.cefrLevel { value["cefr"] = .string(String(l.prefix(16))) }
                if let r = c.grammarRange { value["grammar_range"] = .string(String(r.prefix(16))) }
            }
            add("talk:\(id)", s.endedAt ?? s.startedAt, source: id, "talk", id, value)
            await Task.yield()
        }
        for (id, tag) in LearnerStateStore.shared.state(language: language).sessions {
            for item in tag.items {
                add("talk:\(id):item:\(item.id)", tag.talkDate, source: id, "item", item.id,
                    ["right": .integer(item.right), "wrong": .integer(item.wrong),
                     "item_kind": .string(item.kind.rawValue)])
            }
        }

        // Words and expressions.
        let vocab = VocabStore.shared
        for word in vocab.studying where vocab.records[word] == nil {
            add("word:\(word)", now, "word", word, ["state": .string("studying"), "count": .integer(0)])
        }
        for (word, r) in vocab.records {
            add("word:\(word)", r.lastAt, "word", word,
                ["state": .string(r.state.rawValue), "count": .integer(r.count)])
        }
        func phrase(_ text: String) -> Bool { WordSplitter.count(text) <= maxExpressionWords }
        for text in vocab.studyingExpressions where vocab.expressionRecords[text] == nil && phrase(text) {
            add("expression:\(text)", now, "expression", text,
                ["state": .string("studying"), "count": .integer(0)])
        }
        for (text, r) in vocab.expressionRecords where phrase(text) {
            add("expression:\(text)", r.lastAt, "expression", text,
                ["state": .string(r.state.rawValue), "count": .integer(r.count)])
        }

        // Cards and takes: numbers only, never their sentences.
        for c in DrillStore.shared.load() {
            var value: [String: AnyJSON] = ["box": .integer(c.box), "seen": .integer(c.timesSeen),
                                            "correct": .integer(c.timesCorrect)]
            if let used = c.usedInTalkAt { value["used_at"] = .string(dayFormat.string(from: used)) }
            add("card:\(c.id.uuidString)", c.lastReviewedAt ?? c.createdAt,
                source: c.sourceSessionId?.uuidString, "card", c.id.uuidString, value)
        }
        for a in ShadowAttemptStore.shared.load() {
            var value: [String: AnyJSON] = ["overall": .integer(a.overallScore),
                                            "match": .integer(a.matchScore),
                                            "partial": .bool(a.isPartial)]
            if let r = a.rhythmScore { value["rhythm"] = .integer(r) }
            add("shadow:\(a.id.uuidString)", a.createdAt, source: a.id.uuidString, "shadow",
                a.turnId.uuidString, value)
        }

        // Sounds, one row per sound per day.
        var sounds: [String: (date: Date, total: Int, samples: Int)] = [:]
        for e in PronunciationLedger.shared.entries(language: language) {
            let day = dayFormat.string(from: e.date)
            for p in e.phonemes where !p.p.isEmpty {
                var row = sounds["\(day):\(p.p)"] ?? (e.date, 0, 0)
                row.total += p.a
                row.samples += 1
                sounds["\(day):\(p.p)"] = row
            }
        }
        for (key, row) in sounds {
            let phoneme = String(key.dropFirst(11))
            add("sound:\(key)", row.date, "sound", phoneme,
                ["score": .integer(row.total / max(row.samples, 1)), "samples": .integer(row.samples)])
        }

        // Lessons and tests.
        for l in TutorLessonStore.all(language: language) {
            var value: [String: AnyJSON] = ["challenges": .integer(l.challenges.count),
                                            "done": .bool(l.finishedAt != nil),
                                            "check_passed": .bool(l.check?.passedAt != nil)]
            if let tries = l.check?.tries { value["tries"] = .integer(tries) }
            add("lesson:\(l.id.uuidString)", l.finishedAt ?? l.createdAt, source: l.id.uuidString,
                "lesson", l.topicId ?? "custom", value)
        }
        for t in WeeklyTestStore.shared.load() where t.isFinished {
            let kinds = Dictionary(uniqueKeysWithValues: t.items.map { ($0.id, $0.kind.rawValue) })
            for a in t.answers {
                guard let kind = kinds[a.itemId] else { continue }
                var value: [String: AnyJSON] = ["right": .bool(a.correct),
                                                "appealed": .bool(a.appealed ?? false)]
                if let s = a.score { value["score"] = .integer(s) }
                add("test:\(t.id.uuidString):\(a.itemId.uuidString)", a.at, source: t.id.uuidString,
                    "test", kind, value)
            }
        }

        // Days and the routine.
        let cal = Calendar.current
        for back in 0..<dayWindow {
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            let log = PracticeLog.shared.day(d) ?? PracticeLog.Day()
            let talk = TalkTimeLog.seconds(on: d, language: language)
            guard talk > 0 || log.showedUp else { continue }
            let day = dayFormat.string(from: d)
            add("day:\(day)", d, "day", day,
                ["talk_seconds": .integer(talk), "word_reps": .integer(log.wordReps),
                 "expression_reps": .integer(log.expressionReps), "drill_reps": .integer(log.drillReps),
                 "shadow_reps": .integer(log.shadowReps), "scene_reps": .integer(log.sceneReps)])
        }
        for b in StudyPlanStore.shared.plan.blocks {
            let time = b.anytime == true ? "anytime" : String(format: "%02d:%02d", b.hour, b.minute)
            for weekday in b.weekdays {
                add("routine:\(b.id.uuidString):\(weekday)", now, source: "routine", "routine", b.kind.rawValue,
                    ["weekday": .integer(weekday), "time": .string(time), "amount": .integer(b.minutes)])
            }
        }
        return out
    }
}

/// Sends what changed, a while after the learner stops doing things. Nothing
/// waits on it, and a pass cut off anywhere picks up where it stopped.
@MainActor
enum LearnerRecordUploader {
    private static let settleSeconds: UInt64 = 20
    private static let batchSize = 400
    private static var pending: Task<Void, Never>?
    private static var running = false

    nonisolated static func schedule() {
        Task { @MainActor in
            guard !isQuietRun else { return }
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: settleSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                pending = nil
                await run()
            }
        }
    }

    private static var isQuietRun: Bool {
        UserDefaults.standard.string(forKey: "capture") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            let client = SupabaseProvider.shared
            let user = try await client.auth.session.user
            guard !user.isAnonymous else { return }
            let enabled: Bool = try await client.rpc("learner_record_enabled").execute().value
            guard enabled else { return }

            let language = LanguageCatalog.base(LanguageScope.active)
            let url = indexURL(userId: user.id.uuidString.lowercased(), language: language)
            var sent = loadIndex(url)
            let current = await LearnerEventBuilder.build(language: language)
            let plan = LearnerEventDiff.plan(current: current, sent: sent)

            for source in plan.forget {
                let _: Int = try await client
                    .rpc("learner_events_forget", params: ["p_source_id": source])
                    .execute().value
            }
            if !plan.forget.isEmpty {
                sent = LearnerEventDiff.afterForgetting(plan.forget, sent: sent)
                saveIndex(sent, url)
            }

            var start = 0
            while start < plan.put.count {
                let batch = Array(plan.put[start..<min(start + batchSize, plan.put.count)])
                let body = AnyJSON.array(batch.map(payload))
                let _: Int = try await client
                    .rpc("learner_events_put", params: ["p_batch": body])
                    .execute().value
                for event in batch {
                    sent[event.key] = .init(fingerprint: event.fingerprint, sourceId: event.sourceId)
                }
                saveIndex(sent, url)
                start += batchSize
            }
        } catch {
            guard !(error is CancellationError) else { return }
            Analytics.capture("learner_record_failed", ["error": String(String(describing: error).prefix(120))])
        }
    }

    private static let isoFormat = ISO8601DateFormatter()

    private static func payload(_ e: LearnerEvent) -> AnyJSON {
        var object: [String: AnyJSON] = [
            "key": .string(e.key),
            "language": .string(e.language),
            "occurred_at": .string(isoFormat.string(from: e.occurredAt)),
            "kind": .string(e.kind),
            "subject": .string(e.subject),
            "value": .object(e.value),
            "platform": .string("ios"),
            "app_version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
        ]
        if let source = e.sourceId { object["source_id"] = .string(source) }
        return .object(object)
    }

    private static func indexURL(userId: String, language: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dir = docs.appendingPathComponent("learner_record/\(userId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir.appendingPathComponent("\(language).json")
    }

    private static func loadIndex(_ url: URL) -> [String: LearnerEventDiff.Sent] {
        (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: LearnerEventDiff.Sent].self, from: $0) } ?? [:]
    }

    private static func saveIndex(_ sent: [String: LearnerEventDiff.Sent], _ url: URL) {
        if let data = try? JSONEncoder().encode(sent) { try? data.write(to: url, options: .atomic) }
    }
}
