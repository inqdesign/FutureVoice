import Foundation

/// How the learner actually USES the app — when, how often, what — read
/// from the logs, and the coaching that follows from it (2026-10-27,
/// founder: "it's all about how the user actually uses the app … a coach
/// gives harsh advice too, with a good reason, and then constructive
/// feedback").
///
/// Everything here is counted in code. `HabitAdvisor` turns the counts into
/// findings by fixed rules, so the same week always gets the same advice and
/// every finding carries the numbers it rests on; a model only words it
/// (`HabitAdvice.phrase`). The routine the report recommends is built from
/// these findings — never from a template the learner's week had no say in.
struct StudyHabits: Equatable {
    enum Activity: String, Codable, CaseIterable {
        case talk, review, shadow, sayItAgain, listen, speech, scene
    }

    /// One thing done, at a time. A talk carries its minutes; every other
    /// sitting is one rep.
    struct Sitting: Equatable {
        var activity: Activity
        var at: Date
        var minutes: Double = 0
    }

    /// What the learner's own routine asked of a kind, and what happened.
    struct PlanKept: Equatable {
        var kind: StudyPlan.Kind
        /// Days in the window the routine had this kind.
        var plannedDays: Int
        /// Of those, days it happened at all.
        var keptDays: Int
        /// The block's own hour, for "planned at 21:30".
        var hour: Int
        var minute: Int
        var anytime: Bool
    }

    var dayCount: Int
    var activeDays: Int
    /// The longest run of days with nothing, inside the window.
    var longestGapDays: Int
    var talkMinutes: Int
    var talkDays: Int
    var talks: Int
    var reviewReps: Int
    var reviewDays: Int
    var shadowTakes: Int
    var sayItAgainRuns: Int
    var listens: Int
    var scenes: Int = 0
    var speeches: Int = 0
    /// Share of all effort that fell on the busiest day (0…1).
    var busiestDayShare: Double
    var busiestDay: Date?
    /// The hour most sittings start around, and how many of them do.
    var habitHour: Int?
    var habitShare: Double
    /// Review cards the talks made from corrections, and the corrections
    /// that came back more than once (`was → now`, times).
    var correctionsMade: Int
    var repeatedFixes: [WeekRecap.Stumble]
    var plan: [PlanKept]

    var sittingsCount: Int
}

// MARK: - Counting

extension StudyHabits {
    /// Pure: everything it reads is passed in.
    static func compute(start: Date, end: Date,
                        sittings raw: [Sitting],
                        correctionsMade: Int,
                        repeatedFixes: [WeekRecap.Stumble],
                        planBlocks: [StudyPlan.Block],
                        calendar: Calendar = .current) -> StudyHabits {
        let sittings = raw.filter { $0.at >= start && $0.at < end }.sorted { $0.at < $1.at }
        var days: [Date] = []
        var d = calendar.startOfDay(for: start)
        while d < end, let next = calendar.date(byAdding: .day, value: 1, to: d) {
            days.append(d); d = next
        }
        let byDay = Dictionary(grouping: sittings) { calendar.startOfDay(for: $0.at) }

        // Effort per day: talk minutes, and half a minute per rep — a rough
        // common unit, used only to see whether the work was spread out.
        func effort(_ s: Sitting) -> Double { s.activity == .talk ? max(1, s.minutes) : 0.5 }
        let effortByDay = byDay.mapValues { $0.reduce(0) { $0 + effort($1) } }
        let total = effortByDay.values.reduce(0, +)
        let busiest = effortByDay.max { $0.value < $1.value }

        var longest = 0, run = 0
        for day in days {
            if byDay[day] == nil { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        // A gap that is still running at the window's end counts too; a
        // leading one before the first sitting does not (they hadn't started).
        if let first = sittings.first {
            let firstDay = calendar.startOfDay(for: first.at)
            longest = 0; run = 0
            for day in days where day >= firstDay {
                if byDay[day] == nil { run += 1; longest = max(longest, run) } else { run = 0 }
            }
        }

        // The habit hour: the hour with the most sitting STARTS within ±1 h.
        // A talk is one sitting; reps within 20 min of each other are one too.
        var starts: [Date] = []
        for s in sittings {
            if let last = starts.last, s.at.timeIntervalSince(last) < 20 * 60 { continue }
            starts.append(s.at)
        }
        let hours = starts.map { calendar.component(.hour, from: $0) }
        var habitHour: Int?
        var habitShare = 0.0
        if !hours.isEmpty {
            func near(_ h: Int, _ c: Int) -> Bool { let diff = abs(h - c); return min(diff, 24 - diff) <= 1 }
            // Ties within the window go to the hour most sittings start IN.
            func score(_ h: Int) -> Int { hours.filter { near($0, h) }.count * 100 + hours.filter { $0 == h }.count }
            let best = (0..<24).max { score($0) < score($1) }!
            habitHour = best
            habitShare = Double(hours.filter { near($0, best) }.count) / Double(hours.count)
        }

        func count(_ a: Activity) -> Int { sittings.filter { $0.activity == a }.count }
        func daysWith(_ a: Activity) -> Int { Set(sittings.filter { $0.activity == a }.map { calendar.startOfDay(for: $0.at) }).count }

        let kept: [PlanKept] = planBlocks.compactMap { block in
            let activity: Activity? = switch block.kind {
            case .talk: .talk
            case .review, .words, .expressions: .review
            case .shadow: .shadow
            case .sayItAgain: .sayItAgain
            case .listen: .listen
            case .speech: .speech
            case .test: nil
            }
            guard let activity else { return nil }
            let planned = days.filter { block.weekdays.contains(calendar.component(.weekday, from: $0)) }
            guard !planned.isEmpty else { return nil }
            let keptDays = planned.filter { day in byDay[day]?.contains { $0.activity == activity } == true }.count
            return PlanKept(kind: block.kind, plannedDays: planned.count, keptDays: keptDays,
                            hour: block.hour, minute: block.minute, anytime: block.isAnytime)
        }

        return StudyHabits(
            dayCount: days.count,
            activeDays: byDay.count,
            longestGapDays: longest,
            talkMinutes: Int(sittings.filter { $0.activity == .talk }.reduce(0) { $0 + $1.minutes }.rounded()),
            talkDays: daysWith(.talk),
            talks: count(.talk),
            reviewReps: count(.review),
            reviewDays: daysWith(.review),
            shadowTakes: count(.shadow),
            sayItAgainRuns: count(.sayItAgain),
            listens: count(.listen),
            scenes: count(.scene),
            speeches: count(.speech),
            busiestDayShare: total > 0 ? (busiest?.value ?? 0) / total : 0,
            busiestDay: busiest?.key,
            habitHour: habitHour,
            habitShare: habitShare,
            correctionsMade: correctionsMade,
            repeatedFixes: repeatedFixes,
            plan: kept,
            sittingsCount: starts.count)
    }

    /// From the app's own logs, for `[start, end)`.
    @MainActor
    static func read(start: Date, end: Date, recap: WeekRecap) -> StudyHabits {
        var sittings: [Sitting] = []
        // Corrections are counted in the talks themselves — every fix the
        // learner was given — not by the cards minted from them, which a
        // talk summarized offline may not have made yet.
        var corrections = 0
        for s in SessionStore.shared.loadAcrossLanguages() {
            guard let ended = s.endedAt, s.turns.contains(where: { $0.role == .user }) else { continue }
            let began = s.turns.first?.timestamp ?? s.startedAt
            sittings.append(Sitting(activity: .talk, at: began,
                                    minutes: max(0, ended.timeIntervalSince(began)) / 60))
            guard began >= start, began < end else { continue }
            for turn in s.turns where turn.isEvidence {
                corrections += turn.suggestion?.fixes?.count ?? 0
            }
        }
        for e in ActivityEventLog.shared.events(from: start, to: end) {
            let activity: Activity
            switch e.kind {
            case .drill, .word, .expression: activity = .review
            case .shadow: activity = .shadow
            case .sayItAgain: activity = .sayItAgain
            case .listen: activity = .listen
            case .speech: activity = .speech
            case .scene: activity = .scene
            case .read: continue    // not a habit the report reads yet
            }
            sittings.append(Sitting(activity: activity, at: e.at))
        }
        return compute(start: start, end: end, sittings: sittings,
                       correctionsMade: max(corrections, recap.newCards), repeatedFixes: recap.stumbles,
                       planBlocks: StudyPlanStore.shared.plan.blocks)
    }
}

// MARK: - Which parts of the app were used

/// Every practice feature, and how much of it the learner used (2026-10-28,
/// founder: the trial report shows ALL the features, which ones were used
/// and how much, and says plainly when only one part was). Counted in code
/// from `StudyHabits`; the advice is picked by rule, never written by a model.
struct FeatureUse: Equatable, Identifiable {
    enum Feature: String, CaseIterable {
        case talk, sayItAgain, review, shadow, scene, listen, speech
    }
    var feature: Feature
    /// Talks, runs, reps, takes, scenes, pieces heard.
    var count: Int
    /// A talk's minutes; zero for everything else.
    var minutes: Int = 0
    var id: Feature { feature }
    var used: Bool { count > 0 || minutes > 0 }

    /// What the card says under the list.
    enum Advice: Equatable {
        /// Nothing but talking.
        case onlyTalk
        /// Talked and more; the one thing to add next.
        case next(Feature)
        /// Most of it — keep the mix.
        case wideMix
        /// Never talked: the rest is built from talks.
        case noTalk
    }

    static func list(_ h: StudyHabits) -> [FeatureUse] {
        [FeatureUse(feature: .talk, count: h.talks, minutes: h.talkMinutes),
         FeatureUse(feature: .sayItAgain, count: h.sayItAgainRuns),
         FeatureUse(feature: .review, count: h.reviewReps),
         FeatureUse(feature: .shadow, count: h.shadowTakes),
         FeatureUse(feature: .scene, count: h.scenes),
         FeatureUse(feature: .listen, count: h.listens),
         FeatureUse(feature: .speech, count: h.speeches)]
    }

    /// The order a missing feature is suggested in: what makes a talk's
    /// corrections stick first, then what trains the ear and the rhythm.
    static let suggestionOrder: [Feature] = [.sayItAgain, .review, .shadow, .scene, .listen, .speech]

    static func advice(_ uses: [FeatureUse]) -> Advice {
        let used = Set(uses.filter(\.used).map(\.feature))
        guard used.contains(.talk) else { return .noTalk }
        if used == [.talk] { return .onlyTalk }
        if used.count >= 5 { return .wideMix }
        return suggestionOrder.first { !used.contains($0) }.map(Advice.next) ?? .wideMix
    }
}

// MARK: - The rules

/// One thing the coach saw. Decided in code; `facts` are what a model is
/// handed to word it, and nothing else.
struct HabitFinding: Codable, Equatable, Hashable {
    enum Tone: String, Codable { case good, nudge, firm }
    /// A stable name for the rule ("cramming", "no-review", …).
    var rule: String
    var tone: Tone
    /// The evidence, in English, numbers included — the model's only input.
    var facts: [String]
    /// What the routine changes because of it, in English.
    var change: String?
}

enum HabitAdvisor {
    /// At most this many findings reach the learner: a coach says the few
    /// things that matter, not everything that's true.
    static let maxFindings = 4
    /// The review block the no-review finding adds — the size it names.
    static let shortReviewCards = 10

    static func findings(_ h: StudyHabits) -> [HabitFinding] {
        var out: [HabitFinding] = []
        let habit = h.habitHour.map { String(format: "%02d:00", $0) }

        // 1. Everything in one sitting.
        if h.dayCount >= 4, h.activeDays <= 2, h.sittingsCount >= 1, h.busiestDayShare >= 0.6 {
            let share = Int((h.busiestDayShare * 100).rounded())
            out.append(.init(rule: "cramming", tone: .firm, facts: [
                "\(share)% of everything they did in \(h.dayCount) days happened on ONE day.",
                "They practised on \(h.activeDays) of \(h.dayCount) days.",
                "Why it matters: what is practised once a week fades within days; short practice on most days is what makes it stick."
            ], change: "Talk on five weekdays instead, shorter" + (habit.map { ", around \($0) when they already practise" } ?? "") + "."))
        }

        // 2. A long gap.
        if h.dayCount >= 7, h.longestGapDays >= 4, !out.contains(where: { $0.rule == "cramming" }) {
            out.append(.init(rule: "gap", tone: h.longestGapDays >= 6 ? .firm : .nudge, facts: [
                "They went \(h.longestGapDays) days in a row without practising.",
                "They practised on \(h.activeDays) of \(h.dayCount) days.",
                "Why it matters: after a few days off, the first talk back starts from further behind."
            ], change: "A short talk every day, even five minutes, so no gap gets that long."))
        }

        // 3. Talking, never reviewing what the talks corrected.
        if h.correctionsMade >= 5, h.reviewReps == 0 {
            var facts = [
                "Their talks corrected \(h.correctionsMade) things they said, each saved as a review card. They reviewed none of them.",
                "They talked \(h.talkMinutes) min in \(h.talks) talk(s)."
            ]
            if let top = h.repeatedFixes.first {
                facts.append("The same correction came back \(top.count) times: \"\(top.was)\" → \"\(top.now)\".")
            }
            facts.append("Why it matters: talking without reviewing means making the same mistakes again; the review is where a correction becomes theirs.")
            out.append(.init(rule: "no-review", tone: .firm, facts: facts,
                             change: "Add a short review (\(shortReviewCards) cards) right after the talk."
                                 + (h.repeatedFixes.isEmpty ? "" : " Add say it again after the talk.")))
        } else if !h.repeatedFixes.isEmpty, h.sayItAgainRuns == 0, let top = h.repeatedFixes.first {
            // 4. The same fix twice, never practised in context.
            out.append(.init(rule: "repeated-fix", tone: .nudge, facts: [
                "The same correction came back \(top.count) times: \"\(top.was)\" → \"\(top.now)\".",
                "They haven't used say it again (re-doing a talk the corrected way) yet.",
                "Why it matters: a fix that keeps coming back needs saying out loud the right way, not just reading."
            ], change: "Add say it again right after the talk."))
        }

        // 4b. Corrected often, never re-said the right way (no fix came
        // back word for word yet, but the corrections are there).
        if h.correctionsMade >= 5, h.sayItAgainRuns == 0, h.talks >= 2,
           !out.contains(where: { $0.rule == "repeated-fix" || $0.rule == "no-review" }) {
            out.append(.init(rule: "no-say-again", tone: .nudge, facts: [
                "Their talks corrected \(h.correctionsMade) things they said.",
                "They haven't used say it again (re-doing a talk, saying their own lines the corrected way) yet.",
                "Why it matters: reading a correction is not the same as saying it; saying the right version in the same conversation is what makes it come out next time."
            ], change: "Add say it again right after the talk."))
        }

        // 5. A planned kind that never happened.
        for p in h.plan where p.plannedDays >= 3 && p.keptDays == 0 && p.kind != .talk {
            let when = p.anytime ? "" : String(format: " at %02d:%02d", p.hour, p.minute)
            var facts = ["Their own routine has \(p.kind.rawValue)\(when) on \(p.plannedDays) day(s) so far. It happened on none of them."]
            var change = "Make it smaller so it fits: one short \(p.kind.rawValue) block a day."
            if let habit, !p.anytime, let hh = h.habitHour, abs(hh - p.hour) >= 2 {
                facts.append("They usually practise around \(habit), not\(when).")
                change = "Move \(p.kind.rawValue) to around \(habit), when they already practise."
            }
            facts.append("Why it matters: a plan that never happens teaches that plans don't count; a smaller one that happens beats a big one that doesn't.")
            out.append(.init(rule: "plan-missed-\(p.kind.rawValue)", tone: .nudge, facts: facts, change: change))
        }

        // 6. Only reviewing, barely talking.
        if h.talkMinutes < 10, h.reviewReps >= 20 {
            out.append(.init(rule: "little-talk", tone: .nudge, facts: [
                "They reviewed \(h.reviewReps) cards but talked only \(h.talkMinutes) min.",
                "Why it matters: review keeps what they know; only talking makes new mistakes to learn from and makes the words come out under pressure."
            ], change: "A ten-minute talk on the days they review."))
        }

        // 7. What is working — said as plainly as what isn't.
        if h.dayCount >= 2, h.dayCount < 4, h.activeDays == h.dayCount {
            out.append(.init(rule: "came-back", tone: .good, facts: [
                "They practised on every one of the \(h.dayCount) days since they started.",
                "Why it matters: coming back the next day is what most people never do; it is the start of a habit."
            ], change: nil))
        }
        if h.reviewReps > 0, h.correctionsMade > 0 {
            out.append(.init(rule: "reviewed", tone: .good, facts: [
                "Their talks corrected \(h.correctionsMade) things; they reviewed \(h.reviewReps) card(s) on \(h.reviewDays) day(s).",
                "Why it matters: reviewing what a talk corrected is where the correction becomes theirs."
            ], change: nil))
        }
        if h.dayCount >= 4, Double(h.activeDays) / Double(h.dayCount) >= 0.7 {
            out.append(.init(rule: "consistent", tone: .good, facts: [
                "They practised on \(h.activeDays) of \(h.dayCount) days.",
                "Why it matters: this regularity is the part most learners never manage."
            ], change: nil))
        } else if let habit, h.sittingsCount >= 3, h.habitShare >= 0.6 {
            out.append(.init(rule: "habit-time", tone: .good, facts: [
                "\(Int((h.habitShare * 100).rounded()))% of their sittings start around \(habit).",
                "Why it matters: a fixed time is what turns practice into a habit; the routine is placed there."
            ], change: nil))
        }
        if h.talks >= 3, !out.contains(where: { $0.tone == .good }) {
            out.append(.init(rule: "talking", tone: .good, facts: [
                "They talked \(h.talkMinutes) min in \(h.talks) talks.",
                "Why it matters: speaking is the hard part, and they are doing it."
            ], change: nil))
        }

        // Firm first, then nudges, the good news last — but always one good
        // thing when there is one, so the list is never only criticism.
        let order: [HabitFinding.Tone: Int] = [.firm: 0, .nudge: 1, .good: 2]
        let sorted = out.sorted { order[$0.tone]! < order[$1.tone]! }
        var picked = Array(sorted.filter { $0.tone != .good }.prefix(maxFindings - 1))
        if let good = sorted.first(where: { $0.tone == .good }) { picked.append(good) }
        if picked.count < maxFindings {
            picked += sorted.filter { $0.tone != .good && !picked.contains($0) }.prefix(maxFindings - picked.count)
        }
        return picked
    }

    /// The routine the findings call for: the learner's own routine (or the
    /// starting one) with what each finding changes, every touched block
    /// carrying the rule that touched it.
    static func routine(base: [StudyPlan.Block], habits h: StudyHabits,
                        findings: [HabitFinding], goalMinutes: Int) -> [(block: StudyPlan.Block, rule: String?)] {
        var lines: [(block: StudyPlan.Block, rule: String?)] = base.map { ($0, nil) }
        let hour = h.habitHour
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let rules = Set(findings.map(\.rule))

        func talkIndex() -> Int? { lines.firstIndex { $0.block.kind == .talk } }

        if rules.contains("cramming") || rules.contains("gap") {
            let minutes = max(5, min(goalMinutes, h.talks > 0 ? h.talkMinutes / max(1, 5) : goalMinutes))
            let days: Set<Int> = rules.contains("gap") ? Set(1...7) : weekdays
            if let i = talkIndex() {
                lines[i].block.weekdays = days
                lines[i].block.minutes = max(5, minutes)
                if let hour, !lines[i].block.isAnytime { lines[i].block.hour = hour; lines[i].block.minute = 0 }
                lines[i].rule = rules.contains("cramming") ? "cramming" : "gap"
            } else {
                lines.insert((StudyPlan.Block(kind: .talk, weekdays: days, hour: hour ?? 20, minute: 0,
                                              minutes: max(5, minutes), anytime: hour == nil ? true : nil),
                              rules.contains("cramming") ? "cramming" : "gap"), at: 0)
            }
        }
        let talk = talkIndex().map { lines[$0].block }
        let after = talk.map { $0.isAnytime ? (hour ?? 20) * 60 + 30 : $0.startMinute + $0.minutes } ?? ((hour ?? 20) * 60 + 30)
        let talkDays = talk?.weekdays ?? Set(1...7)

        if rules.contains("no-review"), !lines.contains(where: { $0.block.kind == .review }) {
            lines.append((StudyPlan.Block(kind: .review, weekdays: talkDays, hour: (after + 5) / 60 % 24,
                                          minute: (after + 5) % 60, minutes: HabitAdvisor.shortReviewCards),
                          "no-review"))
        }
        if rules.contains("repeated-fix") || rules.contains("no-say-again")
            || (rules.contains("no-review") && !h.repeatedFixes.isEmpty),
           !lines.contains(where: { $0.block.kind == .sayItAgain }) {
            lines.append((StudyPlan.Block(kind: .sayItAgain, weekdays: talkDays, hour: after / 60 % 24,
                                          minute: after % 60, minutes: 1),
                          rules.contains("repeated-fix") ? "repeated-fix"
                              : rules.contains("no-say-again") ? "no-say-again" : "no-review"))
        }
        for f in findings where f.rule.hasPrefix("plan-missed-") {
            let kind = String(f.rule.dropFirst("plan-missed-".count))
            guard let i = lines.firstIndex(where: { $0.block.kind.rawValue == kind }) else { continue }
            if let hour, !lines[i].block.isAnytime, abs(hour - lines[i].block.hour) >= 2 {
                lines[i].block.hour = hour
                lines[i].block.minute = 30
            } else if !lines[i].block.kind.isTimed {
                lines[i].block.minutes = max(1, lines[i].block.minutes / 2)
            }
            lines[i].rule = f.rule
        }
        if rules.contains("little-talk"), talkIndex() == nil {
            let days = Set(lines.filter { $0.block.kind == .review }.flatMap(\.block.weekdays))
            lines.insert((StudyPlan.Block(kind: .talk, weekdays: days.isEmpty ? weekdays : days,
                                          hour: hour ?? 20, minute: 0, minutes: 10), "little-talk"), at: 0)
        }
        return lines.sorted { $0.block.startMinute < $1.block.startMinute }
    }
}

// MARK: - Wording

/// The findings, worded for the learner in their native language. The rules
/// chose them and their numbers; this only says them the way a good coach
/// would — straight when it's firm, specific when it's good.
struct HabitAdvice: Codable, Equatable {
    struct Line: Codable, Equatable, Hashable {
        var rule: String
        var tone: HabitFinding.Tone
        /// A short headline (native).
        var title: String
        /// What we saw and why it matters (native), numbers as given.
        var body: String
        /// What the routine does about it (native), when anything.
        var change: String?
    }
    var lines: [Line]

    static func phrase(_ findings: [HabitFinding],
                       firstTalks: Bool,
                       nativeLanguage: String = LanguageCatalog.currentNative) async throws -> HabitAdvice {
        guard !findings.isEmpty else { return HabitAdvice(lines: []) }
        let native = LanguageCatalog.englishName(nativeLanguage)
        let system = """
        You are a language learner's coach. Below are findings about HOW \
        they have been using their practice app — decided already, with the \
        numbers that prove them. Word each one for the learner, in \
        \(native). You add no finding, drop none, change no number.

        For each finding write:
        - "title": the point in at most ~8 words.
        - "body": 1–2 sentences: what you saw (with its numbers, exactly as \
        given) and why it matters.
        - "change": one sentence on what their routine does about it, from \
        the given change; null when none is given.

        TONE, by the finding's tone:
        - firm: say it straight, like a coach who wants them to succeed. No \
        softening ("maybe", "a little", "it seems"), no "unfortunately", \
        no apology. Never shame, never call them lazy, never exaggerate — \
        the numbers carry the weight. The reason makes it fair; the change \
        makes it constructive.
        - nudge: direct and friendly.
        - good: specific praise of what they actually did. No "great job!", \
        no exclamation marks anywhere.

        LANGUAGE: natural \(native), written, not translated. Korean: 해요체 \
        in every sentence, never 합니다/습니다, never 당신. Japanese: \
        です・ます. German/French/Spanish: informal you. Activity names: \
        talk, review, say it again (re-doing a talk the corrected way), \
        shadowing, listening — use the app's ordinary words for them in \
        \(native). \(firstTalks ? "These are their first days with the app; never say \"this week\"." : "")

        JSON only: {"lines": [{"rule": "...", "title": "...", "body": "...", "change": null}]}, \
        one per finding, same order, rule copied exactly.
        """
        let user = findings.map { f in
            "FINDING \(f.rule) (tone: \(f.tone.rawValue))\n" + f.facts.map { "- \($0)" }.joined(separator: "\n")
                + (f.change.map { "\nCHANGE: \($0)" } ?? "")
        }.joined(separator: "\n\n")
        struct Payload: Decodable {
            struct Raw: Decodable { var rule: String; var title: String; var body: String; var change: String? }
            var lines: [Raw]
        }
        let response: Payload = try await GeminiClient.shared.sendJSON(
            system: system, messages: [.init(role: .user, content: user)],
            maxTokens: 2048, purpose: "week-recap", requestTimeout: 45)
        let tones = Dictionary(findings.map { ($0.rule, $0.tone) }, uniquingKeysWith: { a, _ in a })
        return HabitAdvice(lines: response.lines.compactMap { raw in
            guard let tone = tones[raw.rule], !raw.title.isEmpty else { return nil }
            let change = raw.change?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Line(rule: raw.rule, tone: tone, title: raw.title, body: raw.body,
                        change: (change?.isEmpty ?? true) ? nil : change)
        })
    }
}
