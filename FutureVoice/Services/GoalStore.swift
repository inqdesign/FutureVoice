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
        didSet { defaults.set(sentencesPerDay, forKey: Keys.sentences) }
    }
    @Published var wordsPerDay: Int {
        didSet { defaults.set(wordsPerDay, forKey: Keys.words) }
    }
    @Published var expressionsPerDay: Int {
        didSet { defaults.set(expressionsPerDay, forKey: Keys.expressions) }
    }
    @Published var shadowsPerDay: Int {
        didSet { defaults.set(shadowsPerDay, forKey: Keys.shadows) }
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
        // 20 = one deck (`DrillView.sessionCap`), which is what the tile
        // asked for before this was settable.
        sentencesPerDay   = defaults.object(forKey: Keys.sentences) as? Int ?? 20
        wordsPerDay       = defaults.object(forKey: Keys.words) as? Int ?? 10
        expressionsPerDay = defaults.object(forKey: Keys.expressions) as? Int ?? 3
        shadowsPerDay     = defaults.object(forKey: Keys.shadows) as? Int ?? 2
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
