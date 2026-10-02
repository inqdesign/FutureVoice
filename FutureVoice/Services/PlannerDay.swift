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
        enum Kind: String { case talk, review, shadow, scene, sayItAgain }
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

        /// Whether this sitting is the kind of practice a planned block asks for.
        func covers(_ planned: StudyPlan.Kind) -> Bool {
            switch (kind, planned) {
            case (.talk, .talk), (.shadow, .shadow), (.sayItAgain, .sayItAgain): return true
            case (.review, .review), (.review, .words), (.review, .expressions): return true
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
            case .drill, .word, .expression: return .review
            case .shadow: return .shadow
            case .scene: return .scene
            case .sayItAgain: return .sayItAgain
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

    /// Which planned blocks the day's practice covers, by occurrence id.
    /// Talks are matched in order — two planned talks need two talks.
    ///
    /// A talk block asks for MINUTES, so it is measured on the metered talk
    /// time (`talkSeconds`, the ring's number): two 10-minute talk blocks are
    /// both done at 20 minutes of talking that day, the first at 10. With no
    /// meter reading (nil) a block is done by any finished talk, in order.
    static func done(planned: [StudyPlan.Occurrence],
                     actuals: [Actual],
                     events: [ActivityEventLog.Event],
                     testFinished: Bool,
                     talkSeconds: Int? = nil) -> Set<String> {
        var out = Set<String>()
        let plannedTalks = planned.filter { $0.kind == .talk }.sorted { $0.start < $1.start }
        if let talkSeconds {
            var needed = 0
            for occ in plannedTalks {
                needed += occ.minutes * 60
                if talkSeconds >= needed { out.insert(occ.id) }
            }
        } else {
            let talkCount = actuals.filter { $0.kind == .talk }.count
            for (i, occ) in plannedTalks.enumerated() where i < talkCount { out.insert(occ.id) }
        }
        let kinds = Set(events.map(\.kind))
        for occ in planned {
            let hit: Bool
            switch occ.kind {
            case .talk: continue
            case .review: hit = !kinds.isDisjoint(with: [.drill, .word, .expression])
            case .words: hit = kinds.contains(.word)
            case .expressions: hit = kinds.contains(.expression)
            case .shadow: hit = kinds.contains(.shadow)
            case .sayItAgain: hit = kinds.contains(.sayItAgain)
            case .test: hit = testFinished
            }
            if hit { out.insert(occ.id) }
        }
        return out
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

    /// How far along each planned talk block is, 0…1, filling them in order
    /// from the day's metered talk time.
    static func talkProgress(planned: [StudyPlan.Occurrence], talkSeconds: Int) -> [String: Double] {
        var out: [String: Double] = [:]
        var left = Double(talkSeconds)
        for occ in planned.filter({ $0.kind == .talk }).sorted(by: { $0.start < $1.start }) {
            let need = Double(max(1, occ.minutes * 60))
            out[occ.id] = min(1, max(0, left / need))
            left = max(0, left - need)
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
                return plannedKinds.isDisjoint(with: [.review, .words, .expressions])
            case .shadow: return !plannedKinds.contains(.shadow)
            case .sayItAgain: return !plannedKinds.contains(.sayItAgain)
            case .scene: return true
            }
        }
    }
}
