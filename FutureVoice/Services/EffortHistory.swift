import SwiftUI

/// What the learner put in, per day and per kind — the Growth tab's effort
/// card and the page behind it (`EffortDetailView`). Nothing here is counted
/// for this page alone: talk is the meter's minutes (`TalkTimeLog`, the
/// ring's number), every other kind is the count the routine already reads
/// (`PracticeLog`'s STUDIED reps, `ActivityEventLog` for say-it-again runs
/// and Speech takes), so the effort page, the routine and the ring can never
/// tell one day two ways.
enum EffortCategory: String, CaseIterable, Identifiable {
    case talk, words, expressions, sentences, shadowing, sayItAgain, speech, scenes
    var id: String { rawValue }

    /// Only talk is measured in time; the rest are things done.
    var isTimed: Bool { self == .talk }

    var label: String {
        switch self {
        case .talk: return explain("Talk")
        case .words: return explain("Words")
        case .expressions: return explain("Expressions")
        case .sentences: return explain("Sentences")
        case .shadowing: return explain("Shadowing")
        case .sayItAgain: return explain("Say it again")
        case .speech: return explain("Speech")
        case .scenes: return explain("Scenes")
        }
    }

    var symbol: String {
        switch self {
        case .talk: return "phone.fill"
        case .words: return "textformat"
        case .expressions: return "quote.bubble.fill"
        case .sentences: return "rectangle.stack.fill"
        case .shadowing: return "waveform"
        case .sayItAgain: return "arrow.counterclockwise"
        case .speech: return "music.mic"
        case .scenes: return "play.rectangle.fill"
        }
    }

    /// The routine's colours where the routine has the kind (talk blue,
    /// say it again teal, words purple, expressions pink, shadowing yellow,
    /// review green for sentence cards); the two it has no block for take
    /// colours nothing else here uses. Never indigo — that is the Core's.
    var color: Color {
        switch self {
        case .talk: return .blue
        case .words: return .purple
        case .expressions: return .pink
        case .sentences: return .green
        case .shadowing: return .yellow
        case .sayItAgain: return .teal
        case .speech: return .brown
        case .scenes: return .gray
        }
    }

    /// "47 min", "32 cards".
    func amountText(_ value: Double) -> String {
        let n = Int(value.rounded(.down))
        switch self {
        case .talk: return explain("\(n) min")
        case .words: return n == 1 ? explain("1 word") : explain("\(n) words")
        case .expressions: return n == 1 ? explain("1 expression") : explain("\(n) expressions")
        case .sentences: return n == 1 ? explain("1 card") : explain("\(n) cards")
        case .shadowing: return n == 1 ? explain("1 take") : explain("\(n) takes")
        case .sayItAgain, .speech: return n == 1 ? explain("1 run") : explain("\(n) runs")
        case .scenes: return n == 1 ? explain("1 scene") : explain("\(n) scenes")
        }
    }
}

struct EffortDay: Identifiable, Equatable {
    let day: Date
    /// Time in the app that day, never less than the talk in it (a call in
    /// a pocket is metered but not foregrounded) — the day card's "Study".
    var studySeconds = 0
    var talkSeconds = 0
    var talks = 0
    var words = 0
    var expressions = 0
    var sentences = 0
    var shadowing = 0
    var sayItAgain = 0
    var speech = 0
    var scenes = 0
    var id: Date { day }

    /// In the category's own unit — minutes for talk, a count otherwise.
    func amount(_ c: EffortCategory) -> Double {
        switch c {
        case .talk: return Double(talkSeconds) / 60
        case .words: return Double(words)
        case .expressions: return Double(expressions)
        case .sentences: return Double(sentences)
        case .shadowing: return Double(shadowing)
        case .sayItAgain: return Double(sayItAgain)
        case .speech: return Double(speech)
        case .scenes: return Double(scenes)
        }
    }

    /// Study time that wasn't talking — words, cards, shadowing, scenes…
    var otherSeconds: Int { max(0, studySeconds - talkSeconds) }

    /// Something was DONE — opening the app alone is not a day of practice.
    var isActive: Bool { EffortCategory.allCases.contains { amount($0) > 0 } }
}

enum EffortHistory {
    /// How far back talk minutes reach — `TalkTimeLog` keeps 45 days, so a
    /// comparison window that starts earlier would read missing days as 0.
    static let talkReachDays = 45

    static func studyMinutes(in days: some Collection<EffortDay>) -> Int {
        days.reduce(0) { $0 + $1.studySeconds } / 60
    }
    static func otherMinutes(in days: some Collection<EffortDay>) -> Int {
        days.reduce(0) { $0 + $1.otherSeconds } / 60
    }

    /// `count` days ending today, oldest first.
    @MainActor
    static func days(_ count: Int, now: Date = Date(),
                     sessions: [Session], shadowAttempts: [ShadowAttempt],
                     drillCards: [DrillCard]) -> [EffortDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(count - 1), to: today),
              let end = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
        let events = ActivityEventLog.shared.events(from: start, to: end)
        let ended = sessions.filter { $0.endedAt != nil }

        return (0..<count).compactMap { offset -> EffortDay? in
            guard let d = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let log = PracticeLog.shared.day(d) ?? PracticeLog.Day()
            // The log only exists from the day it shipped; shadow attempts and
            // card review dates are the floor for the days before it — the
            // same backfill Growth's charts always used.
            let shadowed = shadowAttempts.filter { cal.isDate($0.createdAt, inSameDayAs: d) }.count
            let reviewed = drillCards.filter { c in
                c.lastReviewedAt.map { cal.isDate($0, inSameDayAs: d) } ?? false
            }.count
            let dayEvents = events.filter { cal.isDate($0.at, inSameDayAs: d) }
            let talkSeconds = TalkTimeLog.seconds(on: d)
            return EffortDay(
                day: d,
                studySeconds: max(AppUsageLog.seconds(on: d, now: now), talkSeconds),
                talkSeconds: talkSeconds,
                talks: ended.filter { cal.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: d)
                                      && $0.turns.contains { $0.role == .user } }.count,
                words: log.wordReps,
                expressions: log.expressionReps,
                sentences: max(log.drillReps, reviewed),
                shadowing: max(log.shadowReps, shadowed),
                sayItAgain: dayEvents.filter { $0.kind == .sayItAgain }.count,
                speech: dayEvents.filter { $0.kind == .speech }.count,
                scenes: log.sceneReps)
        }
    }

    static func total(_ c: EffortCategory, in days: some Collection<EffortDay>) -> Double {
        days.reduce(0) { $0 + $1.amount(c) }
    }
}
