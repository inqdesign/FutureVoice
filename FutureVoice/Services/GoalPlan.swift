import Foundation

/// The road from today to a dated goal, laid on the learner's own routine
/// (2026-11-12, founder: "when there's a deadline, show a rough plan; I say
/// I'll go with it, and it really becomes my daily routine — everything
/// talks by itself, there's no centre"). Founder's pick of three: the GOAL
/// FILLS THE ROUTINE. The routine keeps its times (when), the goal decides
/// what each talk block practises until its day (what), and the tutor says
/// today's one thing. After the day the routine is what it was, by itself.
///
/// Computed in code from what is already on disk — the goal's likely
/// questions (`GoalPrep.cachedQuestions`), where each stands (a lesson that
/// passed its final check = ready) and the routine's talk days — and never
/// stored: a skipped day or a question done early simply moves the rest.
/// The only stored fact is that the learner said "use this plan"
/// (`GoalPlanStore`).
struct GoalPlan: Equatable {
    /// What a day of the plan practises.
    enum Item: Hashable {
        /// Build the answer to one likely question, in a tutor drill.
        case question(String)
        /// Once more on the ones not ready yet — a build day with no new
        /// question left to give it.
        case catchUp
        /// The day itself as a run-through: the questions one after another.
        case rehearse
        /// The day: a short warm-up.
        case theDay
    }

    struct Row: Equatable, Identifiable {
        var id: Date { date }
        var date: Date
        var item: Item
    }

    let goal: UpcomingGoal
    /// One row per practice day, from today to the goal's day.
    let rows: [Row]
    let ready: Int
    let total: Int

    /// Days the routine has a talk on (Gregorian weekdays). Every day when
    /// the routine has none — adopting the plan adds one (`adopt`).
    static func talkWeekdays(_ plan: StudyPlan) -> Set<Int> {
        let days = Set(plan.blocks.filter { $0.kind == .talk }.flatMap(\.weekdays))
            .subtracting(plan.offWeekdays ?? [])
        return days.isEmpty ? Set(1...7).subtracting(plan.offWeekdays ?? []) : days
    }

    /// The questions not ready yet, in the page's order.
    @MainActor
    static func open(_ goal: UpcomingGoal) -> (open: [String], total: Int)? {
        guard let questions = GoalPrep.cachedQuestions(for: goal), !questions.isEmpty else { return nil }
        let lessons = TutorLessonStore.all(language: goal.language)
        let open = questions.map(\.text).filter { GoalPrep.state(of: $0, goal: goal, lessons: lessons) != .ready }
        return (open, questions.count)
    }

    /// Nil without a date, once the day has passed, or before the page has
    /// worked out the questions.
    @MainActor
    static func make(goal: UpcomingGoal, routine: StudyPlan? = nil,
                     now: Date = Date(), calendar: Calendar = .current) -> GoalPlan? {
        guard let left = goal.daysLeft(now: now, calendar: calendar), left >= 0,
              let date = goal.date, let qs = open(goal) else { return nil }
        return make(goal: goal, open: qs.open, total: qs.total, day: date,
                    talkDays: talkWeekdays(routine ?? StudyPlanStore.shared.plan), now: now, calendar: calendar)
    }

    /// The pure half (`GoalPlanTests`).
    static func make(goal: UpcomingGoal, open: [String], total: Int, day: Date,
                     talkDays: Set<Int>, now: Date, calendar: Calendar = .current) -> GoalPlan {
        let today = calendar.startOfDay(for: now)
        let theDay = calendar.startOfDay(for: day)
        var practice: [Date] = []
        var d = today
        while d < theDay {
            if talkDays.contains(calendar.component(.weekday, from: d)) { practice.append(d) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        // The last days before are a run-through, not new answers: two when
        // there's room, one when it's short, none when there's barely time
        // to build an answer per question.
        let rehearsals = practice.count >= open.count + 2 ? 2 : (practice.count >= open.count + 1 ? 1 : 0)
        let build = Array(practice.dropLast(rehearsals))
        var rows: [Row] = []
        // More questions than days: several a day, in order. Fewer: one a
        // day, then the days left go over what's still not ready.
        let perDay = build.isEmpty ? 0 : max(1, Int((Double(open.count) / Double(build.count)).rounded(.up)))
        for (i, date) in build.enumerated() {
            let slice = open.dropFirst(i * perDay).prefix(perDay)
            if slice.isEmpty {
                rows.append(Row(date: date, item: open.isEmpty ? .rehearse : .catchUp))
            } else {
                rows.append(contentsOf: slice.map { Row(date: date, item: .question($0)) })
            }
        }
        rows += practice.suffix(rehearsals).map { Row(date: $0, item: .rehearse) }
        rows.append(Row(date: theDay, item: .theDay))
        return GoalPlan(goal: goal, rows: rows, ready: total - open.count, total: total)
    }

    /// What today's talk practises: today's row, or — on a day the routine
    /// has no talk — the next question still open.
    var today: Item? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        if let row = rows.first(where: { cal.isDate($0.date, inSameDayAs: day) }) { return row.item }
        return rows.first?.item
    }

    func items(on day: Date, calendar: Calendar = .current) -> [Item] {
        rows.filter { calendar.isDate($0.date, inSameDayAs: day) }.map(\.item)
    }
}

extension GoalPlan.Item {
    var isQuestion: Bool { if case .question = self { return true } else { return false } }

    /// One short line for the routine's day list and the tutor's note.
    var label: String {
        switch self {
        case .question(let q): return q
        case .catchUp: return explain("Once more: the ones not ready yet")
        case .rehearse: return explain("Mock run: the questions one after another")
        case .theDay: return explain("The day: a short warm-up")
        }
    }

    var symbol: String {
        switch self {
        case .question: return "graduationcap.fill"
        case .catchUp: return "arrow.counterclockwise"
        case .rehearse: return "stopwatch.fill"
        case .theDay: return "flag.checkered"
        }
    }

    /// The call this item opens, through the tutor's goal door.
    @MainActor
    func call(for goal: UpcomingGoal) -> TutorBot.GoalCall {
        switch self {
        case .question(let q):
            return TutorBot.GoalCall(topic: "\u{201C}\(q)\u{201D} — \(goal.title)", blurb: goal.drillBlurb,
                                     lessonTopicId: GoalPrep.topicId(goal: goal, question: q))
        case .catchUp:
            let open = GoalPlan.open(goal)?.open ?? []
            if let first = open.first {
                return GoalPlan.Item.question(first).call(for: goal)
            }
            return GoalPlan.Item.rehearse.call(for: goal)
        case .rehearse:
            let qs = (GoalPrep.cachedQuestions(for: goal) ?? []).map(\.text)
            var blurb = goal.drillBlurb
            blurb += ". MOCK RUN: play the examiner/interviewer of the day. Ask the likely questions one after "
                + "another, as they will be asked, and let them answer each in full before the next."
            if !qs.isEmpty { blurb += " The questions: " + qs.joined(separator: " | ") }
            return TutorBot.GoalCall(topic: explain("Mock run") + " — \(goal.title)", blurb: blurb, tutor: false)
        case .theDay:
            return TutorBot.GoalCall(topic: explain("Warm-up") + " — \(goal.title)",
                                     blurb: goal.drillBlurb + ". It is the day itself: a short, calm warm-up on "
                                        + "the answer they will surely need. Keep it light and encouraging.",
                                     tutor: false)
        }
    }
}

extension GoalPlan {
    /// The goal whose plan the learner put in their routine, for a target
    /// language — the nearest one when there are several.
    @MainActor
    static func active(language: String, now: Date = Date()) -> GoalPlan? {
        let adopted = GoalPlanStore.shared.adopted
        for goal in UpcomingGoalStore.shared.active(language: language, now: now) where adopted.contains(goal.id) {
            if let plan = make(goal: goal, now: now) { return plan }
        }
        return nil
    }

    /// What a routine talk opens today, when a plan is in the routine.
    @MainActor
    static func todaysCall(language: String) -> TutorBot.GoalCall? {
        guard let plan = active(language: language), let item = plan.today else { return nil }
        return item.call(for: plan.goal)
    }

    /// "Use this plan": remember it, and give a routine with no talk one.
    @MainActor
    static func adopt(_ goal: UpcomingGoal) {
        GoalPlanStore.shared.set(goal.id, adopted: true)
        let store = StudyPlanStore.shared
        if !store.plan.blocks.contains(where: { $0.kind == .talk }) {
            var plan = store.plan
            let days = Set(1...7).subtracting(plan.offWeekdays ?? [])
            plan.blocks.insert(StudyPlan.Block(kind: .talk, weekdays: days, hour: 0, minute: 0,
                                               minutes: max(10, StudyPlanStore.goalMinutes), anytime: true), at: 0)
            store.update(plan, byLearner: true)
        }
        Analytics.capture("goal_plan_adopted", ["kind": goal.kind.rawValue, "days_left": goal.daysLeft() ?? -1])
    }
}

/// Which goals' plans are in the routine. Its own file and sync kind, never a
/// field on `UpcomingGoal`: an older build (or Android) re-saving the goal
/// would drop a field it doesn't know, and the newer stamp would win.
@MainActor
final class GoalPlanStore: ObservableObject {
    static let shared = GoalPlanStore()
    static let filename = "goal_plans.json"

    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID          // the goal's id
        var adoptedAt: Date
        var updatedAt: Date
    }

    @Published private(set) var entries: [Entry] = []
    var adopted: Set<UUID> { Set(entries.map(\.id)) }

    private var url: URL { SyncFiles.url(Self.filename, lang: nil) }
    private init() { reload() }

    func reload() {
        entries = SyncFiles.read([Entry].self, at: url, decoder: SyncFiles.storeDecoder, empty: []) ?? []
    }

    func set(_ goalId: UUID, adopted: Bool) {
        var list = entries.filter { $0.id != goalId }
        if adopted { list.append(Entry(id: goalId, adoptedAt: Date(), updatedAt: Date())) }
        entries = list
        try? SyncFiles.write(list, to: url, encoder: SyncFiles.storeEncoder)
        SyncEngine.noteChanged(.goalPlan)
    }
}
