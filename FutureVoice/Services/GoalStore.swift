import Foundation
import Combine

/// Daily challenge targets — how many word judgments / expression judgments /
/// shadow takes count as "done for today". Targets only; the reps themselves
/// come from `PracticeLog`. A target of 0 turns that challenge off.
///
/// UserDefaults-backed and global across languages: the habit is one habit,
/// whichever target language is active (PracticeLog is global for the same
/// reason).
@MainActor
final class GoalStore: ObservableObject {
    static let shared = GoalStore()

    @Published var sentencesPerDay: Int {
        didSet { defaults.set(sentencesPerDay, forKey: Keys.sentences); SyncEngine.noteChanged(.defaults) }
    }
    @Published var wordsPerDay: Int {
        didSet { defaults.set(wordsPerDay, forKey: Keys.words); SyncEngine.noteChanged(.defaults) }
    }
    @Published var expressionsPerDay: Int {
        didSet { defaults.set(expressionsPerDay, forKey: Keys.expressions); SyncEngine.noteChanged(.defaults) }
    }
    @Published var shadowsPerDay: Int {
        didSet { defaults.set(shadowsPerDay, forKey: Keys.shadows); SyncEngine.noteChanged(.defaults) }
    }

    private enum Keys {
        static let sentences   = "futurevoice.goal.sentencesPerDay"
        static let words       = "futurevoice.goal.wordsPerDay"
        static let expressions = "futurevoice.goal.expressionsPerDay"
        static let shadows     = "futurevoice.goal.shadowsPerDay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 20 = one deck (`DrillView.defaultSessionCap`), which is what the
        // tile asked for before this was settable. The deck now deals THIS
        // number, so the hand and the target can't disagree.
        sentencesPerDay   = defaults.object(forKey: Keys.sentences) as? Int ?? 20
        wordsPerDay       = defaults.object(forKey: Keys.words) as? Int ?? 10
        expressionsPerDay = defaults.object(forKey: Keys.expressions) as? Int ?? 3
        shadowsPerDay     = defaults.object(forKey: Keys.shadows) as? Int ?? 2
    }

    /// The sync wrote new goals into defaults underneath the published copies.
    func reloadFromDefaults() {
        let s = defaults.object(forKey: Keys.sentences) as? Int ?? 20
        let w = defaults.object(forKey: Keys.words) as? Int ?? 10
        let e = defaults.object(forKey: Keys.expressions) as? Int ?? 3
        let sh = defaults.object(forKey: Keys.shadows) as? Int ?? 2
        if sentencesPerDay != s { sentencesPerDay = s }
        if wordsPerDay != w { wordsPerDay = w }
        if expressionsPerDay != e { expressionsPerDay = e }
        if shadowsPerDay != sh { shadowsPerDay = sh }
    }

    // MARK: - The routine sets the day (2026-10-02)
    //
    // What a day ASKS for is the routine's (founder: one place to set it).
    // The per-day numbers above are no longer a goal anyone edits; they are
    // only the hand a deck deals on a day the routine says nothing about.

    /// How much of `kind` the routine asks for on `date` — nil when it asks
    /// for none (a rest day, or a day without that block).
    func target(_ kind: StudyPlan.Kind, on date: Date = Date()) -> Int? {
        let total = StudyPlanStore.shared.plan
            .occurrences(on: date, test: WeeklyTestSettings.shared.schedule)
            .filter { $0.kind == kind }
            .reduce(0) { $0 + $1.amount }
        return total > 0 ? total : nil
    }

    /// How many a deck deals today: the routine's number when it has one,
    /// else the standing default.
    func handSize(_ kind: StudyPlan.Kind) -> Int {
        if let t = target(kind) { return t }
        switch kind {
        case .review: return max(sentencesPerDay, 1)
        case .words: return max(wordsPerDay, 1)
        case .expressions: return max(expressionsPerDay, 1)
        case .shadow: return max(shadowsPerDay, 1)
        default: return 1
        }
    }

    var anyEnabled: Bool {
        sentencesPerDay > 0 || wordsPerDay > 0 || expressionsPerDay > 0 || shadowsPerDay > 0
    }

    /// Every enabled challenge met on `date`. False when nothing is enabled —
    /// a day with no goals can't be "met", or the streak would be infinite.
    func met(on date: Date, log: PracticeLog = .shared) -> Bool {
        guard anyEnabled else { return false }
        // FINISHED work only. Reps count every time an item was handled, so
        // reading those let a day complete itself by postponing cards.
        let day = log.day(date) ?? PracticeLog.Day()
        if sentencesPerDay > 0, day.drillDone < sentencesPerDay { return false }
        if wordsPerDay > 0, day.wordDone < wordsPerDay { return false }
        if expressionsPerDay > 0, day.expressionDone < expressionsPerDay { return false }
        if shadowsPerDay > 0, day.shadowDone < shadowsPerDay { return false }
        return true
    }

    /// Consecutive goal-met days ending today — or ending yesterday when today
    /// isn't done yet, so an unfinished morning doesn't read as a broken run.
    func streak(now: Date = Date(), calendar: Calendar = .current,
                log: PracticeLog = .shared) -> Int {
        guard anyEnabled else { return 0 }
        var day = now
        if !met(on: day, log: log) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while met(on: day, log: log) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}
