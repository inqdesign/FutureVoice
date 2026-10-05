import Foundation

/// One day of the timetable as it HAPPENED, and which planned blocks that
/// covers. Pure, so the week view and the tests read the same answer.
///
/// The rule the whole view rests on: a planned block is done when the same
/// KIND of practice happened that day, at any time. Doing the 8:00 talk at
/// noon is doing it — a planner that marks it missed would be the planner
/// people switch off.
enum PlannerDay {
    /// What actually happened, grouped into blocks.
    struct Actual: Identifiable, Equatable {
        enum Kind: String { case talk, review, shadow, scene, sayItAgain, speech }
        var kind: Kind
        var start: Date
        var end: Date
        /// The talk's title, for a talk.
        var title: String?
        var sessionId: UUID?
        var count: Int
        var id: String {
            sessionId.map { "talk-\($0.uuidString)" }
                ?? "\(kind.rawValue)-\(start.timeIntervalSinceReferenceDate)"
        }

        /// The practice to open for this sitting; nil for a Watch scene.
        var planKind: StudyPlan.Kind? {
            switch kind {
            case .talk: return .talk
            case .review: return .review
            case .shadow: return .shadow
            case .sayItAgain: return .sayItAgain
            case .speech: return .speech
            case .scene: return nil
            }
        }

        /// Whether this sitting is the kind of practice a planned block asks for.
        func covers(_ planned: StudyPlan.Kind) -> Bool {
            switch (kind, planned) {
            case (.talk, .talk), (.shadow, .shadow), (.sayItAgain, .sayItAgain), (.speech, .speech): return true
            case (.review, .review), (.review, .words), (.review, .expressions), (.review, .shadow): return true
            default: return false
            }
        }
    }

    /// Reps closer together than this are one sitting.
    static let clusterGap: TimeInterval = 10 * 60
    /// A sitting of one rep still draws as a block this long.
    static let minimumSpan: TimeInterval = 5 * 60

    struct Talk: Equatable {
        var id: UUID
        var start: Date
        var end: Date
        var title: String
    }

    static func actuals(talks: [Talk],
                        events: [ActivityEventLog.Event]) -> [Actual] {
        var out = talks.map {
            Actual(kind: .talk, start: $0.start, end: max($0.end, $0.start.addingTimeInterval(minimumSpan)),
                   title: $0.title, sessionId: $0.id, count: 1)
        }
        func group(_ kind: ActivityEventLog.Kind) -> Actual.Kind {
            switch kind {
            // Every kind of review is one sitting of review (2026-10-03).
            case .drill, .word, .expression, .shadow: return .review
            case .scene: return .scene
            case .sayItAgain: return .sayItAgain
            case .speech: return .speech
            }
        }
        var byGroup: [Actual.Kind: [Date]] = [:]
        for e in events { byGroup[group(e.kind), default: []].append(e.at) }
        for (kind, dates) in byGroup {
            var current: (start: Date, last: Date, count: Int)?
            for d in dates.sorted() {
                if let c = current, d.timeIntervalSince(c.last) <= clusterGap {
                    current = (c.start, d, c.count + 1)
                } else {
                    if let c = current { out.append(block(kind, c)) }
                    current = (d, d, 1)
                }
            }
            if let c = current { out.append(block(kind, c)) }
        }
        return out.sorted { $0.start < $1.start }
    }

    private static func block(_ kind: Actual.Kind, _ c: (start: Date, last: Date, count: Int)) -> Actual {
        Actual(kind: kind, start: c.start,
               end: max(c.last, c.start.addingTimeInterval(minimumSpan)),
               title: nil, sessionId: nil, count: c.count)
    }

    /// What a day added up to, in the units blocks are promised in.
    struct Totals: Equatable {
        var talkMinutes: Double = 0
        var words: Double = 0
        var expressions: Double = 0
        var cards: Double = 0
        var shadow: Double = 0
        var sayItAgain: Double = 0
        var speech: Double = 0
        var test: Double = 0

        func amount(for kind: StudyPlan.Kind) -> Double {
            switch kind {
            case .talk: return talkMinutes
            case .words: return words
            case .expressions: return expressions
            // Review is every kind of review counted together: words and
            // expressions judged, sentence cards, shadow lines.
            case .review: return words + expressions + cards + shadow
            case .shadow: return shadow
            case .sayItAgain: return sayItAgain
            case .speech: return speech
            case .test: return test
            }
        }
    }

    /// A day's totals from the logs that already count them: the talk meter
    /// (the ring's minutes), the practice log's FINISHED counts — the same
    /// numbers the daily goals are judged by, so postponing a card is not
    /// doing it — and finished say-it-again runs, saved Speech takes and tests.
    static func totals(on day: Date, events: [ActivityEventLog.Event], testFinished: Bool) -> Totals {
        let log = PracticeLog.shared.day(day) ?? PracticeLog.Day()
        return Totals(talkMinutes: Double(TalkTimeLog.seconds(on: day)) / 60,
                      words: Double(log.wordDone),
                      expressions: Double(log.expressionDone),
                      cards: Double(log.drillDone),
                      shadow: Double(log.shadowDone),
                      sayItAgain: Double(events.filter { $0.kind == .sayItAgain }.count),
                      speech: Double(events.filter { $0.kind == .speech }.count),
                      test: testFinished ? 1 : 0)
    }

    /// How far along each planned block is, 0…1. Blocks of the same kind
    /// fill in plan order: two 10-minute talks are half done at 10 minutes,
    /// not both. Done at any time of day counts — doing the 8:00 talk at noon
    /// is doing it.
    static func progress(planned: [StudyPlan.Occurrence], totals: Totals) -> [String: Double] {
        var out: [String: Double] = [:]
        var left: [StudyPlan.Kind: Double] = [:]
        for occ in planned.sorted(by: { $0.start < $1.start }) {
            let have = left[occ.kind] ?? totals.amount(for: occ.kind)
            let need = Double(max(1, occ.amount))
            out[occ.id] = min(1, max(0, have / need))
            left[occ.kind] = max(0, have - need)
        }
        return out
    }

    static func done(planned: [StudyPlan.Occurrence], totals: Totals) -> Set<String> {
        Set(progress(planned: planned, totals: totals).filter { $0.value >= 1 }.map(\.key))
    }

    /// Planned blocks that a real sitting landed ON — same kind, starting
    /// within `absorbWindow` of the plan. The week grid draws such a pair as
    /// ONE filled block instead of an outline with a second block over it.
    /// Keyed by occurrence id, valued by the actual's id.
    static let absorbWindow: TimeInterval = 45 * 60

    static func absorbed(planned: [StudyPlan.Occurrence], actuals: [Actual]) -> [String: String] {
        var out: [String: String] = [:]
        var used = Set<String>()
        for occ in planned.sorted(by: { $0.start < $1.start }) {
            let match = actuals.first { a in
                !used.contains(a.id) && a.covers(occ.kind)
                    && abs(a.start.timeIntervalSince(occ.start)) <= absorbWindow
            }
            if let match {
                out[occ.id] = match.id
                used.insert(match.id)
            }
        }
        return out
    }

    /// Practice that happened outside every planned block of its kind.
    static func unplanned(actuals: [Actual], planned: [StudyPlan.Occurrence]) -> [Actual] {
        let plannedKinds = Set(planned.map(\.kind))
        let talkPlans = planned.filter { $0.kind == .talk }.count
        var talkSeen = 0
        return actuals.filter { a in
            switch a.kind {
            case .talk:
                talkSeen += 1
                return talkSeen > talkPlans
            case .review:
                return plannedKinds.isDisjoint(with: [.review, .words, .expressions, .shadow])
            case .shadow: return !plannedKinds.contains(.shadow)
            case .sayItAgain: return !plannedKinds.contains(.sayItAgain)
            case .speech: return !plannedKinds.contains(.speech)
            case .scene: return true
            }
        }
    }
}
