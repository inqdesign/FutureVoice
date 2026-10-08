import Foundation

/// What each day of a PROMISE looked like: how many blocks were planned and
/// how many were done. Kept per day and FROZEN once the day is over, because
/// a day is judged by the plan it had — raise the bar on Thursday and Monday
/// stays kept. Today's entry is provisional and rewritten as the day moves.
///
/// The streak reads only this file and `PracticeStats.activeDays`, so it can
/// be computed off the main actor (widget, day cards). Device-local, like the
/// plan it records.
final class PromiseLedger: @unchecked Sendable {
    static let shared = PromiseLedger()

    struct Entry: Codable, Equatable {
        var planned: Int
        var done: Int
        /// False while the day is still running; a day whose last write was
        /// provisional is judged again once it is over.
        var settled: Bool = true
        /// When the day was first seen with everything done. A kept day stays
        /// kept: adding a block after finishing the day's plan raises the bar
        /// for the days ahead, never takes back the one already kept
        /// (2026-10-07 — a 5-minute talk added at night turned a finished
        /// day grey). Optional, so entries on disk from before decode.
        var keptAt: Date? = nil
        /// Nothing was planned that day: a rest day — it neither counts nor
        /// breaks the streak.
        var isRest: Bool { planned == 0 && keptAt == nil }
        var kept: Bool { keptAt != nil || (planned > 0 && done >= planned) }
    }

    private let lock = NSLock()
    private var entries: [String: Entry]
    private let url: URL

    init(filename: String = "promise_days.json") {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        entries = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func entry(_ day: Date, calendar: Calendar = .current) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[StudyPlan.dayKey(day, calendar: calendar)]
    }

    func set(_ entry: Entry, for day: Date, calendar: Calendar = .current) {
        lock.lock()
        entries[StudyPlan.dayKey(day, calendar: calendar)] = entry
        let snapshot = entries
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return entries.isEmpty
    }

    #if DEBUG
    func replaceAll(_ new: [String: Entry]) {
        lock.lock(); entries = new; lock.unlock()
        if let data = try? JSONEncoder().encode(new) { try? data.write(to: url, options: [.atomic]) }
    }
    #endif
}

/// Judges promise days from the stores and writes them into the ledger.
@MainActor
enum PromiseJudge {
    /// How far back an unsettled stretch is filled in (an app left closed for
    /// a while). Older days can't be judged anyway — the talk meter keeps 45.
    static let maxBackfillDays = 45

    /// Planned and done for one day, by the plan as it stands now.
    static func result(for day: Date, plan: StudyPlan, calendar cal: Calendar = .current) -> PromiseLedger.Entry {
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let occ = plan.occurrences(on: start, test: WeeklyTestSettings.shared.schedule, calendar: cal)
        guard !occ.isEmpty else { return .init(planned: 0, done: 0, settled: true) }
        let events = ActivityEventLog.shared.events(from: start, to: end)
        let talks = SessionStore.shared.loadAcrossLanguages()
            .filter { $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end }
            .map { PlannerDay.Talk(id: $0.id, start: $0.startedAt, end: $0.endedAt ?? $0.startedAt,
                                   title: $0.displayTitle) }
        let tested = WeeklyTestStore.shared.load().compactMap(\.finishedAt)
            .contains { cal.isDate($0, inSameDayAs: start) }
        _ = talks
        let done = PlannerDay.done(planned: occ,
                                   totals: PlannerDay.totals(on: start, events: events, testFinished: tested))
        return .init(planned: occ.count, done: done.count, settled: true)
    }

    /// Settle every promise day not yet frozen (up to yesterday) and rewrite
    /// today's provisional entry. Cheap when nothing is pending: one entry.
    static func refresh(now: Date = Date(), calendar cal: Calendar = .current) {
        let plan = StudyPlanStore.shared.plan
        guard let since = plan.streakSince else { return }
        let ledger = PromiseLedger.shared
        let today = cal.startOfDay(for: now)
        var day = max(cal.startOfDay(for: since),
                      cal.date(byAdding: .day, value: -maxBackfillDays, to: today) ?? today)
        while day < today {
            let old = ledger.entry(day, calendar: cal)
            if old?.settled != true {
                ledger.set(carryingKept(result(for: day, plan: plan, calendar: cal), from: old, now: now),
                           for: day, calendar: cal)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        var live = carryingKept(result(for: today, plan: plan, calendar: cal),
                                from: ledger.entry(today, calendar: cal), now: now)
        live.settled = false
        ledger.set(live, for: today, calendar: cal)
    }

    /// A day judged again keeps the moment it was first kept.
    static func carryingKept(_ new: PromiseLedger.Entry, from old: PromiseLedger.Entry?,
                             now: Date) -> PromiseLedger.Entry {
        var new = new
        if let at = old?.keptAt {
            new.keptAt = at
        } else if old?.kept == true || new.kept {
            new.keptAt = now
        }
        return new
    }
}
