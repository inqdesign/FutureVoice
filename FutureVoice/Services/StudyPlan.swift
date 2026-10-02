import Foundation
import Combine

/// The learner's study timetable: what they mean to do, on which weekdays, at
/// what time. It is shown in Activity's Week view, laid over what actually
/// happened, and it DRIVES the daily call — a talk block is a call time.
///
/// What is stored is a weekly TEMPLATE plus two kinds of per-date edits:
/// a rest day (nothing planned, nothing rings) and an exception (that date's
/// blocks replaced, from "just this once" on a drag). Two block kinds are
/// not stored at all but derived from the settings that already own them, so
/// there is never a second copy to drift: the weekly test (`WeeklyTestSettings`)
/// and the review slot (`autoReview` + its time). "Say it again" is an
/// ordinary block since the founder asked to place it like any other.
///
/// Device-local, like the daily call it schedules: two synced devices must not
/// both ring.
struct StudyPlan: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case talk, review, sayItAgain, words, expressions, shadow, test
        var id: String { rawValue }

        /// Only a talk is measured in MINUTES (the talk meter). Every other
        /// kind is a COUNT the app actually keeps — words judged, cards
        /// reviewed, lines shadowed, runs finished — because a "10 minutes of
        /// words" promise had nothing to check it against (founder: "why is
        /// everything but Talk in minutes?").
        var isTimed: Bool { self == .talk }

        /// How much a new block of this kind asks for — the daily goals'
        /// own defaults (`GoalStore`), so the two never disagree.
        var defaultAmount: Int {
            switch self {
            case .talk: return 10
            case .words: return 10
            case .expressions: return 3
            case .review: return 20
            case .shadow: return 2
            case .sayItAgain, .test: return 1
            }
        }

        /// How tall the block is drawn in the weekly editor, in minutes —
        /// a count has no length, so it gets a fixed one.
        func drawnMinutes(amount: Int) -> Int { isTimed ? amount : 15 }

        /// Kinds the learner can place by hand. Review, say it again and the
        /// test come from toggles and their own settings.
        static let placeable: [Kind] = [.talk, .sayItAgain, .words, .expressions, .shadow]
    }

    struct Block: Codable, Equatable, Hashable, Identifiable {
        var id: UUID = UUID()
        var kind: Kind
        /// Gregorian weekdays, 1 = Sunday … 7 = Saturday (`Calendar.weekday`).
        var weekdays: Set<Int>
        var hour: Int
        var minute: Int
        /// The AMOUNT promised: minutes for a talk, a count for everything
        /// else (see `Kind.isTimed`). The key stays `minutes` so plans on
        /// disk decode.
        var minutes: Int
        var amount: Int { minutes }
        /// A local reminder at the block's time. Talk blocks ignore it — they
        /// ring as the daily call when that is on (Me → Call).
        var remind: Bool = true

        var startMinute: Int { hour * 60 + minute }
    }

    var blocks: [Block] = []
    /// A review slot every planned day at `reviewHour:reviewMinute`. When on,
    /// the review reminder fires at that slot only (`DrillReminder`).
    var autoReview: Bool = false
    var reviewHour: Int = 21
    var reviewMinute: Int = 0
    /// The review slot's AMOUNT: sentence cards (named for when it was minutes).
    var reviewMinutes: Int = 20
    /// nil = saved while every block was measured in minutes; converted to
    /// counts on load (`convertingToCounts`). 1 = counts.
    var unitsVersion: Int? = 1
    /// LEGACY: "say it again" used to be derived, right after the day's
    /// first talk. Plans saved then are converted into ordinary blocks on
    /// load (`convertingLegacySayItAgain`); nothing reads it otherwise.
    var autoSayItAgain: Bool = false
    /// `yyyy-MM-dd` days with nothing planned and nothing ringing.
    var restDays: Set<String> = []
    /// The day the learner made this plan their PROMISE (founder, 2026-10-02:
    /// "it's a promise I kept to myself"). From that day the streak counts a
    /// day only when everything planned for it was done, and a day with
    /// nothing planned is a rest day that neither counts nor breaks it.
    /// nil = no promise made: the streak is the plain "studied today" rule.
    /// Never set by seeding — a first-time learner keeps the easy rule until
    /// they raise the bar themselves.
    var streakSince: Date? = nil
    /// `yyyy-MM-dd` → that date's own blocks, replacing the template's.
    var exceptions: [String: [Block]] = [:]

    /// At most this many distinct call times across the week — the same
    /// ceiling as `DailyCallStore.maxTimes`, so the call list in Me can show
    /// exactly what the timetable rings.
    static let maxCallTimes = 4
    static let sayItAgainMinutes = 5

    // MARK: - A day

    /// One block placed on one date.
    struct Occurrence: Identifiable, Equatable {
        enum Source: Equatable {
            case template(UUID)
            case exception(UUID)
            case review, test
        }
        var kind: Kind
        var start: Date
        /// The amount promised (minutes for a talk, else a count).
        var amount: Int
        var source: Source
        var remind: Bool
        /// How long it is drawn — a talk's own minutes, a fixed slot otherwise.
        var minutes: Int { kind.drawnMinutes(amount: amount) }

        var id: String { "\(start.timeIntervalSinceReferenceDate)-\(kind.rawValue)-\(sourceKey)" }
        var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
        var blockId: UUID? {
            switch source {
            case .template(let id), .exception(let id): return id
            default: return nil
            }
        }
        private var sourceKey: String {
            switch source {
            case .template(let id): return "t\(id.uuidString)"
            case .exception(let id): return "x\(id.uuidString)"
            case .review: return "review"
            case .test: return "test"
            }
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func isRestDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        restDays.contains(Self.dayKey(day, calendar: calendar))
    }

    /// The stored (draggable) blocks for a date: its exception if it has one,
    /// else the template's blocks for that weekday.
    func storedBlocks(on day: Date, calendar: Calendar = .current) -> [Block] {
        if let own = exceptions[Self.dayKey(day, calendar: calendar)] { return own }
        let weekday = calendar.component(.weekday, from: day)
        return blocks.filter { $0.weekdays.contains(weekday) }
    }

    /// Everything planned for a date, soonest first.
    func occurrences(on day: Date,
                     test: WeeklyTestSchedule? = nil,
                     calendar: Calendar = .current) -> [Occurrence] {
        guard !isRestDay(day, calendar: calendar) else { return [] }
        let key = Self.dayKey(day, calendar: calendar)
        let isException = exceptions[key] != nil
        func at(_ hour: Int, _ minute: Int) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        var out: [Occurrence] = storedBlocks(on: day, calendar: calendar).compactMap { b in
            guard let start = at(b.hour, b.minute) else { return nil }
            return Occurrence(kind: b.kind, start: start, amount: b.minutes,
                              source: isException ? .exception(b.id) : .template(b.id),
                              remind: b.remind)
        }
        // The review slot belongs to PLANNED days: a weekday with no block
        // at all is the learner's day off, not a review day.
        let plannedDay = !out.isEmpty
        if autoReview, plannedDay, let start = at(reviewHour, reviewMinute) {
            out.append(Occurrence(kind: .review, start: start, amount: reviewMinutes,
                                  source: .review, remind: true))
        }
        if let test, calendar.component(.weekday, from: day) == test.weekday,
           let start = at(test.hour, test.minute) {
            out.append(Occurrence(kind: .test, start: start, amount: 1, source: .test, remind: false))
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: - The call

    /// Every daily-call ring to arm, soonest first: the rest of today's talk
    /// blocks, else the first talk block of the next day that has one. The
    /// same shape `DailyCallScheduler.fireDates` always had — today's
    /// remaining slots, or tomorrow's first — with weekdays, rest days and
    /// exceptions honoured. Empty when nothing is planned in the next two
    /// weeks.
    func callDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        func talks(on day: Date) -> [Date] {
            occurrences(on: day, calendar: calendar)
                .filter { $0.kind == .talk }.map(\.start)
        }
        let remaining = Array(Set(talks(on: today).filter { $0 > now })).sorted()
        if !remaining.isEmpty { return Array(remaining.prefix(Self.maxCallTimes)) }
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let first = talks(on: day).min() { return [first] }
        }
        return []
    }

    /// The distinct times of day talk blocks ring at, across the template and
    /// every exception still ahead — what `DailyCallStore.times` mirrors.
    var callTimes: [DailyCallStore.CallTime] {
        let all = blocks.filter { $0.kind == .talk }
            + exceptions.values.flatMap { $0 }.filter { $0.kind == .talk }
        return Array(Set(all.map { DailyCallStore.CallTime(hour: $0.hour, minute: $0.minute) })).sorted()
    }

    /// Whether the plan stays within what the call can ring.
    var isCallable: Bool { callTimes.count <= Self.maxCallTimes }

    // MARK: - Review slots

    /// The review slots from `now` on, across `days` days, soonest first.
    func reviewSlots(from now: Date, days: Int = 14, calendar: Calendar = .current) -> [Date] {
        guard autoReview else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return occurrences(on: day, calendar: calendar)
                .filter { $0.kind == .review && $0.start > now }.map(\.start)
        }.sorted()
    }

    /// How many review items each upcoming slot will find waiting, assuming
    /// the learner clears every slot: the first slot gets everything due by
    /// then (overdue included), each later one what comes due after the slot
    /// before it.
    static func reviewLoad(slots: [Date], dueDates: [Date]) -> [Date: Int] {
        var out: [Date: Int] = [:]
        var previous: Date? = nil
        for slot in slots.sorted() {
            out[slot] = dueDates.filter { d in d <= slot && (previous.map { d > $0 } ?? true) }.count
            previous = slot
        }
        return out
    }

    // MARK: - Editing

    /// What a drag changes: this date only, this weekday every week, or the
    /// block's time on every weekday it runs.
    enum Scope { case thisDay, everyWeek, allDays }

    /// Move a stored block. `day` is the date it was dragged on; `to` is the
    /// new start (any date — a drag can cross into another weekday). Returns
    /// nil when the result would ring at more call times than the call can.
    func moving(blockId: UUID, on day: Date, to newStart: Date, scope: Scope,
                calendar: Calendar = .current) -> StudyPlan? {
        var plan = self
        let comps = calendar.dateComponents([.hour, .minute], from: newStart)
        let hour = comps.hour ?? 0, minute = comps.minute ?? 0
        let fromKey = Self.dayKey(day, calendar: calendar)
        let toDay = calendar.startOfDay(for: newStart)
        let toKey = Self.dayKey(toDay, calendar: calendar)
        let fromWeekday = calendar.component(.weekday, from: day)
        let toWeekday = calendar.component(.weekday, from: toDay)

        switch scope {
        case .everyWeek, .allDays:
            guard let idx = plan.blocks.firstIndex(where: { $0.id == blockId }) else {
                // An exception block has no weekly self; "every week" from it
                // means the same move, just this once.
                return moving(blockId: blockId, on: day, to: newStart, scope: .thisDay, calendar: calendar)
            }
            let block = plan.blocks[idx]
            if scope == .allDays && fromWeekday == toWeekday {
                plan.blocks[idx].hour = hour
                plan.blocks[idx].minute = minute
            } else if block.weekdays.count == 1 {
                plan.blocks[idx].weekdays = [toWeekday]
                plan.blocks[idx].hour = hour
                plan.blocks[idx].minute = minute
            } else {
                // The block also runs on other days: split this weekday off.
                plan.blocks[idx].weekdays.remove(fromWeekday)
                var moved = block
                moved.id = UUID()
                moved.weekdays = [toWeekday]
                moved.hour = hour; moved.minute = minute
                plan.blocks.append(moved)
            }
            // A template move overrides any one-off edit of the same day.
            plan.exceptions[fromKey] = nil
            plan.mergeTwins()
        case .thisDay:
            var fromBlocks = storedBlocks(on: day, calendar: calendar)
            guard let idx = fromBlocks.firstIndex(where: { $0.id == blockId }) else { return nil }
            var block = fromBlocks.remove(at: idx)
            block.hour = hour; block.minute = minute
            if fromKey == toKey {
                fromBlocks.append(block)
                plan.exceptions[fromKey] = fromBlocks
            } else {
                plan.exceptions[fromKey] = fromBlocks
                var toBlocks = plan.storedBlocks(on: toDay, calendar: calendar)
                block.id = UUID()
                toBlocks.append(block)
                plan.exceptions[toKey] = toBlocks
            }
        }
        return plan.isCallable ? plan : nil
    }

    /// After one weekday of a block was dragged to a new time, take the rest
    /// of its weekdays there too ("every day it runs"). The two halves become
    /// one block again. Nil if that would need more call times than the call
    /// can ring.
    func following(blockId: UUID, toHour hour: Int, minute: Int) -> StudyPlan? {
        var plan = self
        guard let i = plan.blocks.firstIndex(where: { $0.id == blockId }) else { return nil }
        plan.blocks[i].hour = hour
        plan.blocks[i].minute = minute
        plan.mergeTwins()
        return plan.isCallable ? plan : nil
    }

    /// Two template blocks of the same kind, time and length are one block on
    /// more weekdays.
    mutating func mergeTwins() {
        var merged: [Block] = []
        for b in blocks {
            if let i = merged.firstIndex(where: {
                $0.kind == b.kind && $0.hour == b.hour && $0.minute == b.minute
                    && $0.minutes == b.minutes && $0.remind == b.remind
            }) {
                merged[i].weekdays.formUnion(b.weekdays)
            } else {
                merged.append(b)
            }
        }
        blocks = merged.filter { !$0.weekdays.isEmpty }
    }

    /// Forget exceptions and rest days that are already in the past.
    mutating func pruneBefore(_ now: Date, calendar: Calendar = .current) {
        let todayKey = Self.dayKey(now, calendar: calendar)
        exceptions = exceptions.filter { $0.key >= todayKey }
        restDays = restDays.filter { $0 >= todayKey }
    }

    /// Bring the template's talk blocks in line with a call-time list edited
    /// elsewhere (Me → Call, onboarding). A time that stays keeps its
    /// weekdays; a new time runs every day; a removed one goes.
    mutating func adoptCallTimes(_ times: [DailyCallStore.CallTime], defaultMinutes: Int) {
        let wanted = Set(times)
        let current = Set(callTimes)
        guard wanted != current else { return }
        blocks.removeAll { $0.kind == .talk
            && !wanted.contains(DailyCallStore.CallTime(hour: $0.hour, minute: $0.minute)) }
        for key in exceptions.keys {
            exceptions[key]?.removeAll { $0.kind == .talk
                && !wanted.contains(DailyCallStore.CallTime(hour: $0.hour, minute: $0.minute)) }
        }
        let have = Set(blocks.filter { $0.kind == .talk }
            .map { DailyCallStore.CallTime(hour: $0.hour, minute: $0.minute) })
        for t in wanted.subtracting(have).sorted() {
            blocks.append(Block(kind: .talk, weekdays: Set(1...7), hour: t.hour, minute: t.minute,
                                minutes: defaultMinutes))
        }
    }

    /// The first timetable: what the learner already told the app. A talk
    /// block every day at each daily-call time, as long as the daily goal.
    static func seeded(callTimes: [DailyCallStore.CallTime], goalMinutes: Int) -> StudyPlan {
        var plan = StudyPlan()
        let minutes = max(5, goalMinutes)
        plan.blocks = callTimes.map {
            Block(kind: .talk, weekdays: Set(1...7), hour: $0.hour, minute: $0.minute, minutes: minutes)
        }
        // And a say-it-again right after the first talk.
        if let first = callTimes.min() {
            let end = first.hour * 60 + first.minute + minutes
            if end + sayItAgainMinutes <= 24 * 60 {
                plan.blocks.append(Block(kind: .sayItAgain, weekdays: Set(1...7), hour: end / 60,
                                         minute: end % 60, minutes: 1))
            }
        }
        return plan
    }

    /// A plan saved while every block was measured in minutes: a talk keeps
    /// its minutes, everything else takes its kind's default COUNT (the old
    /// number was a duration and means nothing as a count).
    func convertingToCounts() -> StudyPlan {
        guard unitsVersion == nil else { return self }
        var plan = self
        func convert(_ b: Block) -> Block {
            var b = b
            if !b.kind.isTimed { b.minutes = b.kind.defaultAmount }
            return b
        }
        plan.blocks = plan.blocks.map(convert)
        plan.exceptions = plan.exceptions.mapValues { $0.map(convert) }
        plan.reviewMinutes = Kind.review.defaultAmount
        plan.unitsVersion = 1
        plan.mergeTwins()
        return plan
    }

    /// A plan saved while say-it-again was derived: the same slots, as
    /// ordinary blocks — after each weekday's first talk, and after each
    /// one-off day's first talk — so nothing moves on screen.
    func convertingLegacySayItAgain() -> StudyPlan {
        guard autoSayItAgain else { return self }
        var plan = self
        plan.autoSayItAgain = false
        func after(_ list: [Block]) -> Block? {
            guard let first = list.filter({ $0.kind == .talk }).min(by: { $0.startMinute < $1.startMinute })
            else { return nil }
            let end = first.startMinute + first.minutes
            guard end + Self.sayItAgainMinutes <= 24 * 60 else { return nil }
            return Block(kind: .sayItAgain, weekdays: [], hour: end / 60, minute: end % 60,
                         minutes: 1)
        }
        for weekday in 1...7 {
            if var b = after(blocks.filter { $0.weekdays.contains(weekday) }) {
                b.weekdays = [weekday]
                plan.blocks.append(b)
            }
        }
        for (key, list) in exceptions {
            if let b = after(list) { plan.exceptions[key]?.append(b) }
        }
        plan.mergeTwins()
        return plan
    }
}

/// Disk + the published copy. `Documents/study_plan.json`.
@MainActor
final class StudyPlanStore: ObservableObject {
    static let shared = StudyPlanStore()

    @Published private(set) var plan: StudyPlan

    private let url: URL
    /// Set while the plan itself writes `DailyCallStore.times`, so the
    /// store's setter doesn't bounce the same list back in.
    private var mirroring = false

    init(filename: String = "study_plan.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(StudyPlan.self, from: data) {
            plan = decoded.convertingLegacySayItAgain().convertingToCounts()
            if decoded.autoSayItAgain || decoded.unitsVersion == nil { write(plan) }
        } else {
            plan = StudyPlan.seeded(callTimes: DailyCallStore.shared.times,
                                    goalMinutes: Self.goalMinutes)
            write(plan)
        }
    }

    // MARK: - Off the main actor

    private nonisolated(unsafe) static var cached: StudyPlan?
    private static let cacheLock = NSLock()

    /// The plan, readable from anywhere — the streak is computed off the main
    /// actor (widget refresh, day cards). Read from disk once, then kept in
    /// step by every write.
    nonisolated static var current: StudyPlan {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached { return cached }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("study_plan.json")
        let plan = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(StudyPlan.self, from: $0) } ?? StudyPlan()
        cached = plan
        return plan
    }

    private nonisolated static func setCurrent(_ plan: StudyPlan) {
        cacheLock.lock(); cached = plan; cacheLock.unlock()
    }

    static var goalMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: "futurevoice.dailyGoalMinutes")
        return v > 0 ? v : 10
    }

    /// Replace the plan. Returns false (and changes nothing) when it would
    /// need more call times than the call can ring.
    @discardableResult
    func update(_ new: StudyPlan) -> Bool {
        var new = new
        new.pruneBefore(Date())
        guard new.isCallable else { return false }
        let callsChanged = new.callTimes != plan.callTimes
            || new.blocks.filter({ $0.kind == .talk }) != plan.blocks.filter({ $0.kind == .talk })
            || new.exceptions != plan.exceptions || new.restDays != plan.restDays
        let reviewChanged = new.autoReview != plan.autoReview
            || new.reviewHour != plan.reviewHour || new.reviewMinute != plan.reviewMinute
            || new.restDays != plan.restDays || new.blocks != plan.blocks
        plan = new
        write(new)
        // The day's promise standing follows the plan it is judged by.
        PromiseJudge.refresh()
        if callsChanged {
            mirroring = true
            if !new.callTimes.isEmpty { DailyCallStore.shared.times = new.callTimes }
            mirroring = false
            DailyCallScheduler.rearmFromStoredPlan()
        }
        Task {
            if reviewChanged { await DrillReminder.reschedule() }
            await PlanReminder.reschedule()
        }
        return true
    }

    /// `DailyCallStore.times` was set from somewhere other than the plan.
    func callTimesChanged(_ times: [DailyCallStore.CallTime]) {
        guard !mirroring else { return }
        var new = plan
        new.adoptCallTimes(times, defaultMinutes: Self.goalMinutes)
        guard new != plan else { return }
        plan = new
        write(new)
    }

    private func write(_ plan: StudyPlan) {
        Self.setCurrent(plan)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(plan) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
