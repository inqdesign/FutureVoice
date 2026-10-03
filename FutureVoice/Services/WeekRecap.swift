import Foundation
import UserNotifications

/// "Your week" — the week that just closed, told as a deck of cards
/// (2026-09-30).
///
/// The week is the WEEKLY TEST's week (`WeeklyTestSchedule`): the deck opens
/// at the same moment the test does, recaps the seven days before it, and its
/// last card IS the test. So the learner meets one ritual a week — look back,
/// then prove it — instead of a report on one day and a test on another.
///
/// Not the same thing as `WeeklyReport`, which is the speaking ASSESSMENT
/// (CEFR read, gated on accumulated talk time, lives on Progress). This is
/// what the learner DID: every number here is counted in code from the logs
/// the app already keeps, and the one model call writes only the coach's
/// note about those numbers — it is handed them, never asked for them.
///
/// A recap is FROZEN once built: the week it describes is over, and the logs
/// it is drawn from are pruned (the talk meter keeps 45 days). Same rule as
/// the day card.
struct WeekRecap: Codable, Identifiable, Equatable {
    /// The week is [start, end); `end` is the opening that closed it.
    let start: Date
    let end: Date
    var id: Date { end }

    /// One per day of the week, oldest first.
    var activeDays: [Bool]
    var streak: Int

    var talkSeconds: Int
    var previousTalkSeconds: Int
    /// Every talk the learner spoke in, oldest first.
    var talks: [TalkLine]

    /// Studied material the learner then SAID in a talk — the week's win.
    var usedCount: Int
    var used: [Evidence]

    var cardsCleared: Int
    var wordsKnown: Int
    var expressionsKnown: Int
    var shadowTakes: Int
    var shadowAverage: Int?
    var previousShadowAverage: Int?
    var scenes: Int
    /// Words and expressions that became known or used this week, by name —
    /// the review card's headline number IS this list's count, so the number
    /// and the chips under it can never disagree.
    var nowYours: [String]
    /// Sentence cards retired this week ("Got it", or said in a talk). Same
    /// rule: the count shown is this list's.
    var sentencesGot: [String]

    /// Phrases the fluent self used that the learner hasn't, each with the
    /// fluent self's own sentence — the context is what makes it usable.
    var newExpressionCount: Int
    var newExpressions: [Evidence]
    /// Review cards minted from this week's corrections.
    var newCards: Int

    /// The same correction, twice or more — what the week kept tripping on.
    var stumbles: [Stumble]
    /// Lines shadowed below the retry bar, lowest first — when nothing recurred.
    var shakyLines: [Stumble]
    /// Last week's test, if one was finished inside this week.
    var testScore: Int?
    var testTotal: Int?

    var coach: Coach?
    var createdAt: Date = Date()

    struct TalkLine: Codable, Equatable, Hashable {
        var title: String
        var day: Date
        var minutes: Int
        /// free · news · scenario · person
        var kind: String
    }

    struct Evidence: Codable, Equatable, Hashable {
        var item: String
        var quote: String
    }

    struct Stumble: Codable, Equatable, Hashable {
        var was: String
        var now: String
        /// Times it came up (a fix), or the take's score (a shaky line).
        var count: Int
    }

    /// The coach's read of the week — what no count can show. Every quoted
    /// example is checked in code against the learner's own lines before it
    /// is kept (`WeekRecapCoach.verified`).
    struct Coach: Codable, Equatable {
        /// One line that names the week, native language.
        var headline: String
        /// One observation about HOW they speak, with the line that shows it.
        var insight: String
        var insightQuote: String
        /// Grammar points that went wrong in DIFFERENT sentences.
        var grammar: [Pattern]
        /// Words they lean on, and the one a band up they could reach for.
        var upgrades: [Upgrade]
        /// Two or three concrete things for the new week.
        var plan: [String]

        struct Pattern: Codable, Equatable, Hashable {
            /// The point in plain native words ("the past tense after 'end up'").
            var rule: String
            var examples: [Pair]
            /// How to catch it next time, native.
            var tip: String
        }

        struct Pair: Codable, Equatable, Hashable {
            var was: String
            var now: String
        }

        struct Upgrade: Codable, Equatable, Hashable {
            /// The word they used — counted in code across their lines.
            var instead: String
            var count: Int
            var better: String
            /// One of their own lines, and the same line with `better`.
            var original: String
            var rewritten: String
            /// When the better word fits, native.
            var note: String
        }
    }

    var talkMinutes: Int { talkSeconds / 60 }
    var daysActive: Int { activeDays.filter { $0 }.count }
    var reviewTotal: Int { cardsCleared + wordsKnown + expressionsKnown }
    /// Anything at all happened — a recap of nothing is not shown unasked.
    var hasActivity: Bool { daysActive > 0 || talkSeconds > 0 }
}

/// The week still running — not a recap yet, only how far it has got. Its
/// deck is built at `readyAt`, when the week is over.
struct WeekInProgress: Equatable {
    let start: Date
    let readyAt: Date
    var daysActive: Int
    var talkSeconds: Int
    var talkMinutes: Int { talkSeconds / 60 }
    var hasActivity: Bool { daysActive > 0 || talkSeconds > 0 }
}

// MARK: - Build

@MainActor
enum WeekRecapBuilder {

    /// The week still running: from the most recent opening to the next.
    /// Counted the same way `build` counts a closed week, so the row that
    /// says "so far" and the deck that arrives at `readyAt` agree.
    static func thisWeek(now: Date = Date(), calendar: Calendar = .current) -> WeekInProgress {
        let schedule = WeeklyTestSettings.shared.schedule
        let start = schedule.currentOpening(now: now, calendar: calendar)
        let readyAt = schedule.nextOpening(after: now, calendar: calendar)
        var talkSeconds = 0
        var day = calendar.startOfDay(for: start)
        while day <= now {
            talkSeconds += TalkTimeLog.seconds(on: day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let daysActive = PracticeStats.activeDays(calendar: calendar)
            .filter { $0 >= calendar.startOfDay(for: start) && $0 < readyAt }.count
        return WeekInProgress(start: start, readyAt: readyAt,
                              daysActive: daysActive, talkSeconds: talkSeconds)
    }

    /// The week that the most recent opening closed.
    static func lastWeek(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = WeeklyTestSettings.shared.schedule.currentOpening(now: now, calendar: calendar)
        return (end.addingTimeInterval(-7 * 86_400), end)
    }

    static func build(start: Date, end: Date, calendar: Calendar = .current) -> WeekRecap {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start)) }
        let active = PracticeStats.activeDays(calendar: calendar)
        let log = days.compactMap { PracticeLog.shared.day($0) }
        func inWeek(_ date: Date?) -> Bool { date.map { $0 >= start && $0 < end } ?? false }

        func talk(from a: Date, to b: Date) -> Int {
            var seconds = 0
            var day = calendar.startOfDay(for: a)
            while day < b {
                seconds += TalkTimeLog.seconds(on: day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return seconds
        }

        // Talks the learner actually spoke in, dated by their last line.
        let sessions = SessionStore.shared.loadAcrossLanguages()
            .filter { inWeek($0.turns.last(where: { $0.role == .user })?.timestamp) }
            .sorted { ($0.turns.first?.timestamp ?? .distantPast) < ($1.turns.first?.timestamp ?? .distantPast) }
        let talkLines = sessions.map(talkLine)

        // Used: deduped by item, strongest source first.
        var usedByItem: [String: (carryover: Carryover, rank: Int)] = [:]
        for session in sessions {
            for c in session.summary?.carryovers ?? [] where inWeek(c.detectedAt) {
                let key = CarryoverDetector.normalized(c.item)
                let rank = sourceRank(c.source)
                if let existing = usedByItem[key], existing.rank <= rank { continue }
                usedByItem[key] = (c, rank)
            }
        }
        let used = usedByItem.values
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.carryover.detectedAt > rhs.carryover.detectedAt
            }
            .map { WeekRecap.Evidence(item: $0.carryover.item, quote: $0.carryover.quote) }

        // Became yours: first known or used this week, newest first.
        let vocab = VocabStore.shared
        let nowYours = (vocab.records.map { ($0.key, $0.value.firstAt) }
                        + vocab.expressionRecords.map { ($0.key, $0.value.firstAt) })
            .filter { inWeek($0.1) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let cards = DrillStore.shared.load()
        let sentencesGot = cards
            .filter { card in
                inWeek(card.usedInTalkAt) || (card.box >= 5 && inWeek(card.lastReviewedAt))
            }
            .sorted { ($0.lastReviewedAt ?? $0.createdAt) > ($1.lastReviewedAt ?? $1.createdAt) }
            .map(\.targetPhrase)
        let newCards = cards.filter { inWeek($0.createdAt) }.count

        // New material from the fluent self, with the line it was said in.
        var offered: [WeekRecap.Evidence] = []
        var seenOffered = Set<String>()
        for session in sessions {
            for phrase in session.summary?.expressionsOffered ?? [] {
                let key = CarryoverDetector.normalized(phrase)
                guard !key.isEmpty, seenOffered.insert(key).inserted else { continue }
                offered.append(.init(item: phrase, quote: sentence(saying: phrase, in: session) ?? ""))
            }
        }

        // Stumbles: the same fix, more than once.
        var fixes: [String: WeekRecap.Stumble] = [:]
        for session in sessions {
            for turn in session.turns where turn.role == .user && !turn.excludedFromScoring {
                for fix in turn.suggestion?.fixes ?? [] {
                    let key = CarryoverDetector.normalized(fix.now)
                    guard !key.isEmpty else { continue }
                    fixes[key, default: .init(was: fix.was, now: fix.now, count: 0)].count += 1
                }
            }
        }
        let stumbles = fixes.values.filter { $0.count >= 2 }.sorted { $0.count > $1.count }

        // Shadowing.
        let attempts = ShadowAttemptStore.shared.load()
        let thisWeek = attempts.filter { inWeek($0.createdAt) }
        let previous = attempts.filter { $0.createdAt >= start.addingTimeInterval(-7 * 86_400) && $0.createdAt < start }
        func average(_ list: [ShadowAttempt]) -> Int? {
            list.isEmpty ? nil : Int((Double(list.reduce(0) { $0 + $1.overallScore }) / Double(list.count)).rounded())
        }
        var bestByLine: [UUID: ShadowAttempt] = [:]
        for attempt in thisWeek where !attempt.isPartial {
            // A line's BEST take this week is its verdict.
            if let kept = bestByLine[attempt.turnId], kept.overallScore >= attempt.overallScore { continue }
            bestByLine[attempt.turnId] = attempt
        }
        let shaky = bestByLine.values
            .filter { $0.overallScore < PracticeStats.retryThreshold }
            .sorted { $0.overallScore < $1.overallScore }
            .map { WeekRecap.Stumble(was: $0.learnerTranscript, now: $0.targetText, count: $0.overallScore) }

        let test = WeeklyTestStore.shared.load().first { !$0.isMonthly && inWeek($0.finishedAt) }

        return WeekRecap(
            start: start,
            end: end,
            activeDays: days.map { active.contains($0) },
            streak: PracticeStats.streakDays(asOf: end.addingTimeInterval(-1), calendar: calendar),
            talkSeconds: talk(from: start, to: end),
            previousTalkSeconds: talk(from: start.addingTimeInterval(-7 * 86_400), to: start),
            talks: talkLines,
            usedCount: used.count,
            used: Array(used.prefix(4)),
            cardsCleared: log.reduce(0) { $0 + $1.drillDone },
            wordsKnown: log.reduce(0) { $0 + $1.wordDone },
            expressionsKnown: log.reduce(0) { $0 + $1.expressionDone },
            shadowTakes: log.reduce(0) { $0 + $1.shadowReps },
            shadowAverage: average(thisWeek),
            previousShadowAverage: average(previous),
            scenes: log.reduce(0) { $0 + $1.sceneReps },
            nowYours: Array(nowYours.prefix(60)),
            sentencesGot: Array(sentencesGot.prefix(30)),
            newExpressionCount: offered.count,
            newExpressions: Array(offered.prefix(4)),
            newCards: newCards,
            stumbles: Array(stumbles.prefix(2)),
            shakyLines: Array(shaky.prefix(2)),
            testScore: test?.score,
            testTotal: test?.total,
            coach: nil
        )
    }

    private static func talkLine(_ session: Session) -> WeekRecap.TalkLine {
        let first = session.turns.first?.timestamp ?? session.startedAt
        let last = session.turns.last?.timestamp ?? first
        let kind = session.counterpartId != nil ? "person"
            : session.origin == .scenario ? "scenario"
            : session.origin == .news ? "news" : "free"
        return .init(title: session.displayTitle,
                     day: first,
                     minutes: max(1, Int((last.timeIntervalSince(first) / 60).rounded())),
                     kind: kind)
    }

    /// The fluent self's sentence that carried `phrase`, if one can be found.
    private static func sentence(saying phrase: String, in session: Session) -> String? {
        let needle = phrase.lowercased()
        for turn in session.turns where turn.role == .fluentSelf {
            if let line = TalkCurriculum.sentences(in: turn.transcript)
                .first(where: { $0.lowercased().contains(needle) }) {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// A card from a past talk took more to produce than a suggestion still
    /// on screen — the same order `Carryover.Source` is declared in.
    private static func sourceRank(_ source: Carryover.Source) -> Int {
        switch source {
        case .drillCard:          return 0
        case .curriculumItem:     return 1
        case .studyingExpression: return 2
        case .studyingWord:       return 3
        case .knownExpression:    return 4
        case .knownWord:          return 5
        case .suggestion:         return 6
        }
    }
}

// MARK: - Store

/// Frozen recaps, one per week, plus which weeks have been shown. Device-local
/// and across languages: a week is the learner's, not a language's.
final class WeekRecapStore {
    static let shared = WeekRecapStore()

    private let fileURL: URL
    private let defaults: UserDefaults
    private static let seenKey = "futurevoice.weekRecap.seenEnd"

    init(filename: String = "week-recaps-v3.json", defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent(filename)
    }

    func load() -> [WeekRecap] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? Self.decoder.decode([WeekRecap].self, from: data) else { return [] }
        return list.sorted { $0.end > $1.end }
    }

    func recap(endingAt end: Date) -> WeekRecap? {
        load().first { abs($0.end.timeIntervalSince(end)) < 1 }
    }

    /// Two week ends closer than this are the SAME week. A week's end is an
    /// absolute moment computed from the test schedule in the phone's time
    /// zone, so moving the test day, or flying between Seoul and Berlin,
    /// yields an end a few hours or days off the one already frozen and
    /// seen — and an exact match called that a new week and slid the same
    /// deck up again. Real weeks are 7 days apart (±1 h of DST).
    static let sameWeekTolerance: TimeInterval = 6 * 86_400

    private func recap(near end: Date) -> WeekRecap? {
        load().first { abs($0.end.timeIntervalSince(end)) < Self.sameWeekTolerance }
    }

    /// Every closed week that had something in it, newest first, one per
    /// week — the archive the Practice row opens.
    func archive() -> [WeekRecap] {
        var kept: [WeekRecap] = []
        for recap in load() where recap.hasActivity {
            guard !kept.contains(where: { abs($0.end.timeIntervalSince(recap.end)) < Self.sameWeekTolerance })
            else { continue }
            kept.append(recap)
        }
        return kept
    }

    func save(_ recap: WeekRecap) {
        var all = load()
        all.removeAll { abs($0.end.timeIntervalSince(recap.end)) < 1 }
        all.append(recap)
        guard let data = try? Self.encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// The last week's recap — frozen on first ask, since the week is over.
    @MainActor
    func lastWeek(now: Date = Date()) -> WeekRecap {
        let week = WeekRecapBuilder.lastWeek(now: now)
        if let kept = recap(near: week.end) { return kept }
        let built = WeekRecapBuilder.build(start: week.start, end: week.end)
        save(built)
        return built
    }

    /// Seen, or a week within `sameWeekTolerance` of the newest one seen.
    func wasShown(_ recap: WeekRecap) -> Bool {
        let seen = defaults.double(forKey: Self.seenKey)
        return seen > 0 && recap.end.timeIntervalSince1970 < seen + Self.sameWeekTolerance
    }

    /// Also clears the week's notice from Notification Center: once the deck
    /// has been seen, a notice still sitting there is a second door to the
    /// same deck, and tapping it later was how a learner met it twice.
    @MainActor
    func markShown(_ recap: WeekRecap) {
        defaults.set(max(defaults.double(forKey: Self.seenKey), recap.end.timeIntervalSince1970),
                     forKey: Self.seenKey)
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [WeeklyTestReminder.requestId])
    }

    func resetShown() { defaults.removeObject(forKey: Self.seenKey) }

    /// Developer: forget the frozen copy so the next ask rebuilds it.
    func remove(endingAt end: Date) {
        let kept = load().filter { abs($0.end.timeIntervalSince(end)) >= 1 }
        guard let data = try? Self.encoder.encode(kept) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Coach

/// The one model call, and the only card that is analysis rather than
/// counting. The other cards already SHOW the week — its numbers, the win,
/// the new phrases, the fix that came back word for word. The coach is handed
/// the raw week (every line the learner said, every correction with its
/// reason, the words they used most with their CEFR grade) and asked for what
/// none of those can show: the grammar point that goes wrong across
/// DIFFERENT sentences, the easy word they lean on and the better one a band
/// up, and one habit in how they speak.
///
/// Nothing it quotes is trusted: an example must be found in the learner's
/// own lines, a leaned-on word is COUNTED here, and a pattern needs two
/// verified sentences to be a pattern. What fails the check is dropped, never
/// shown.
@MainActor
enum WeekRecapCoach {

    static func write(for recap: WeekRecap,
                      targetLanguage: String,
                      level: CEFRLevel,
                      nativeLanguage: String = LanguageCatalog.currentNative) async throws -> WeekRecap.Coach {
        let evidence = Evidence.gather(recap: recap, targetLanguage: targetLanguage, setLevel: level)
        let targetName = LanguageCatalog.englishName(targetLanguage)
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        let system = """
        You are a sharp, warm \(targetName) speaking coach. A learner practices \
        by talking with a fluent version of themselves in their own cloned \
        voice. You receive EVERYTHING they said this week, every correction \
        they got, and the words they used most. Write the coaching part of \
        their weekly recap.

        The cards before yours already showed the counts, what they used \
        from their studies, the new phrases, and any correction repeated word \
        for word (listed under ALREADY SHOWN). Do NOT restate any of that. \
        Your job is what a good tutor sees reading a week of transcripts \
        that no count shows.

        Output strict JSON:
        {
          "headline": "...",
          "insight": "...", "insight_quote": "...",
          "grammar": [{"rule": "...", "examples": [{"was": "...", "now": "..."}], "tip": "..."}],
          "upgrades": [{"instead": "...", "better": "...", "original": "...", "rewritten": "...", "note": "..."}],
          "plan": ["...", "..."]
        }

        grammar — up to 3 RECURRING grammar points: the same point going \
        wrong in DIFFERENT sentences (tense after a certain verb, articles \
        before countable nouns, a particle, word order in questions, \
        agreement). Group the corrections by the underlying point; a point \
        seen once is not a pattern. Each needs 2-3 examples, "was" copied \
        EXACTLY from the learner's lines (a short span, the part that is \
        wrong), "now" the same span fixed. "rule": the point in plain \
        \(nativeName), no jargon a non-linguist wouldn't know. "tip": one \
        concrete way to catch it while speaking. Ignore punctuation, \
        capitalisation, spacing, contractions and spelling — the \
        transcriber chose those, not the learner. If nothing recurs, return [].

        upgrades — up to 4 words or short phrases the learner LEANS ON \
        (pick from FREQUENT WORDS, used 2+ times), each with ONE better \
        choice about one CEFR band above their level (\(evidence.level)): more \
        precise or more natural, never rare or bookish, and it must keep \
        the meaning in their sentence. The best upgrades REPLACE a crutch \
        with a word that carries the meaning alone ("very big" → "huge", \
        "think about it a lot" → "mull it over"). "instead" must itself \
        occur 2+ times in their lines: a word from FREQUENT WORDS, or a \
        short phrase they repeated. Never swap an intensifier for another \
        intensifier (very → extremely/really is not an upgrade), never two \
        upgrades for the same word. "instead" exactly as they wrote it (a \
        short phrase is fine). "original": one of their own lines \
        containing it, copied exactly. "rewritten": that line with the \
        better choice, nothing else changed beyond what grammar requires. \
        "note": when the better word fits, one short \(nativeName) sentence. \
        Skip function words and names.

        insight — ONE observation about HOW they speak that the numbers \
        can't show: structures they avoid (never using past tense, only \
        one-clause sentences), whether they ask back, hedging, register, \
        leaning on one connector. It must be something the grammar and \
        upgrades above do NOT already say. 1-2 \(nativeName) sentences. \
        "insight_quote": one learner line that shows it, copied exactly.

        headline — one short \(nativeName) line (max ~8 words) that states the \
        week's single most useful finding about their speaking, specific \
        enough that it could not describe anyone else's week ("Stories that \
        start in the past and end in the present", not "A week of \
        progress"). No exclamation marks, no slogans.

        plan — 2-3 short imperative \(nativeName) sentences for the new week, \
        each built on the grammar, upgrades or insight above (a named word to \
        use, a named structure to try in a talk).

        LANGUAGE: rule, tip, note, insight, headline, plan in \(nativeName), \
        written naturally, the way a good tutor in that language talks, not \
        translated. Korean: 해요체 in EVERY sentence (~해요, ~예요, ~봐요, \
        ~거든요), never 합니다/습니다, never "~해야 합니다" lecturing, never \
        당신. Japanese: です・ます. German/French/Spanish: informal you. \
        Describe what they do ("과거 이야기가 중간에 현재로 바뀌어요"), \
        don't order them to follow a rule. \
        was, now, instead, better, original, rewritten, insight_quote in \
        \(targetName), quoted material only.

        Use only what is in the evidence. Never invent a line, a count or a \
        level. JSON only.
        """
        var user = evidence.prompt
        if let previous = WeekRecapStore.shared.recap(endingAt: recap.start)?.coach {
            user += "\n\n# LAST WEEK'S COACHING (don't repeat it; if a pattern is STILL there, say so with this week's examples)\n"
            user += previous.grammar.map { "- grammar: \($0.rule)" }.joined(separator: "\n")
            user += "\n" + previous.upgrades.map { "- upgrade: \($0.instead) → \($0.better)" }.joined(separator: "\n")
        }
        let response: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [.init(role: .user, content: user)],
            // Three nested arrays on the app's longest evidence prompt, and
            // gen-3 thinks out of the same ceiling — a truncation loses it all.
            maxTokens: 4096,
            purpose: "week-recap",
            requestTimeout: 60
        )
        let coach = verified(response, lines: evidence.learnerLines)
        guard !coach.headline.isEmpty else { throw URLError(.cannotParseResponse) }
        return coach
    }

    // MARK: Evidence

    struct Evidence {
        var learnerLines: [String]
        var level: String
        var prompt: String

        static func gather(recap: WeekRecap, targetLanguage: String, setLevel: CEFRLevel) -> Evidence {
            let sessions = SessionStore.shared.loadAcrossLanguages().filter { session in
                guard LanguageCatalog.sameLanguage(session.targetLanguage, targetLanguage),
                      let last = session.turns.last(where: { $0.role == .user })?.timestamp else { return false }
                return last >= recap.start && last < recap.end
            }
            var lines: [String] = []
            var seen = Set<String>()
            for session in sessions {
                for turn in session.turns where turn.role == .user && !turn.excludedFromScoring {
                    let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, seen.insert(text).inserted else { continue }
                    lines.append(String(text.prefix(400)))
                }
            }

            var corrections: [String] = []
            var seenFix = Set<String>()
            func addFix(_ was: String, _ now: String, _ why: String) {
                let key = CarryoverDetector.normalized(was) + "→" + CarryoverDetector.normalized(now)
                guard !was.isEmpty, seenFix.insert(key).inserted else { return }
                corrections.append("- \"\(was)\" → \"\(now)\"" + (why.isEmpty ? "" : " (\(why))"))
            }
            for session in sessions {
                for turn in session.turns where turn.role == .user && !turn.excludedFromScoring {
                    for fix in turn.suggestion?.fixes ?? [] { addFix(fix.was, fix.now, fix.why) }
                }
                for issue in session.summary?.grammarIssues ?? [] { addFix(issue.quote, issue.correction, issue.note) }
            }

            // The words they lean on, counted and graded here — the model
            // picks from this list rather than guessing what was frequent.
            var counts: [String: Int] = [:]
            for line in lines {
                let tokens = WordSplitter.spaced
                    ? line.lowercased().components(separatedBy: CharacterSet.letters.inverted)
                    : Array(VocabStore.lemmas(in: [line]))
                for token in tokens where token.count >= 2 { counts[token, default: 0] += 1 }
            }
            let frequent = counts
                .compactMap { word, n -> (String, Int, CEFRLevel)? in
                    guard n >= 2, let level = CoreVocabulary.level(ofSurface: word) else { return nil }
                    return (word, n, level)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(25)
                .map { "\($0.0) ×\($0.1) (\($0.2.rawValue.uppercased()))" }

            let reads = sessions.compactMap { $0.summary?.scorecard?.cefrLevel?.uppercased() }
            // The talks' own reads outrank the level picked at setup.
            let level = reads.isEmpty ? setLevel.rawValue.uppercased() : reads.sorted()[reads.count / 2]

            var shown: [String] = []
            shown += recap.used.map { "used from studies: \"\($0.item)\"" }
            shown += recap.newExpressions.map { "new phrase from the fluent self: \"\($0.item)\"" }
            shown += recap.stumbles.map { "repeated word for word: \"\($0.was)\" → \"\($0.now)\" ×\($0.count)" }

            let prompt = """
            # LEARNER LEVEL (median of this week's per-talk reads, else the level they set)
            \(level)

            # EVERYTHING THE LEARNER SAID THIS WEEK (speech-to-text, one line per turn)
            \(lines.prefix(220).joined(separator: "\n"))

            # CORRECTIONS THEY GOT THIS WEEK (their words → fixed, with the reason)
            \(corrections.isEmpty ? "(none)" : corrections.prefix(90).joined(separator: "\n"))

            # FREQUENT WORDS (counted in code across their lines, with CEFR grade)
            \(frequent.isEmpty ? "(none)" : frequent.joined(separator: ", "))

            # ALREADY SHOWN ON EARLIER CARDS (don't restate)
            \(shown.isEmpty ? "(nothing)" : shown.joined(separator: "\n"))
            """
            return Evidence(learnerLines: lines, level: level, prompt: prompt)
        }
    }

    // MARK: Verification

    /// Keep only what the learner's own lines bear out.
    static func verified(_ r: Payload, lines: [String]) -> WeekRecap.Coach {
        func said(_ quote: String) -> Bool {
            !quote.isEmpty && lines.contains { ConversationEngine.quotes(quote, from: $0) }
        }
        let clean = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        let grammar: [WeekRecap.Coach.Pattern] = (r.grammar ?? []).compactMap { p in
            var seen = Set<String>()
            let examples = (p.examples ?? [])
                .map { WeekRecap.Coach.Pair(was: clean($0.was), now: clean($0.now)) }
                .filter { !$0.now.isEmpty && $0.was != $0.now && said($0.was) }
                .filter { seen.insert(CarryoverDetector.normalized($0.was)).inserted }
            // A point seen once is not a pattern.
            guard examples.count >= 2, !clean(p.rule).isEmpty else { return nil }
            return .init(rule: clean(p.rule), examples: Array(examples.prefix(3)), tip: clean(p.tip))
        }

        let upgrades: [WeekRecap.Coach.Upgrade] = (r.upgrades ?? []).compactMap { u in
            let instead = clean(u.instead), better = clean(u.better)
            guard !instead.isEmpty, !better.isEmpty,
                  CarryoverDetector.normalized(instead) != CarryoverDetector.normalized(better) else { return nil }
            let n = occurrences(of: instead, in: lines)
            guard n >= 2 else { return nil }
            let original = clean(u.original)
            let keepLine = said(original) && !clean(u.rewritten).isEmpty
            return .init(instead: instead, count: n, better: better,
                         original: keepLine ? original : "",
                         rewritten: keepLine ? clean(u.rewritten) : "",
                         note: clean(u.note))
        }

        let quote = clean(r.insight_quote)
        return .init(headline: clean(r.headline),
                     insight: clean(r.insight),
                     insightQuote: said(quote) ? quote : "",
                     grammar: Array(grammar.prefix(3)),
                     upgrades: Array(upgrades.prefix(4)),
                     plan: (r.plan ?? []).map { clean($0) }.filter { !$0.isEmpty }.prefix(3).map { $0 })
    }

    /// How many times a word or short phrase was said — whole words for a
    /// spaced language, plain substrings for one without spaces.
    static func occurrences(of phrase: String, in lines: [String]) -> Int {
        let needle = phrase.lowercased()
        if WordSplitter.spaced {
            let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\p{L}])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
            return lines.reduce(0) { total, line in
                let lower = line.lowercased()
                return total + regex.numberOfMatches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            }
        }
        return lines.reduce(0) { $0 + $1.components(separatedBy: phrase).count - 1 }
    }

    struct Payload: Decodable {
        struct P: Decodable { let rule: String?; let examples: [E]?; let tip: String? }
        struct E: Decodable { let was: String?; let now: String? }
        struct U: Decodable {
            let instead: String?; let better: String?; let original: String?
            let rewritten: String?; let note: String?
        }
        let headline: String?
        let insight: String?
        let insight_quote: String?
        let grammar: [P]?
        let upgrades: [U]?
        let plan: [String]?
    }
}
