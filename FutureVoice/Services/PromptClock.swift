import Foundation

/// What the model is told about WHEN it is — the only clock any prompt has.
///
/// Until 2026-09-28 no conversation prompt carried a date, a time or a talk
/// history, and the model, told elsewhere never to say "I don't know", filled
/// the gap with guesses. Reported by a learner as three symptoms of one cause:
/// "long time no see" on a second call the same day, "this afternoon" at
/// eight in the morning, and "our third call" on the first call of the day.
/// So a call now opens with one block that states the facts, and a guard that
/// makes them the only source: anything the block doesn't say about time, the
/// model does not know.
///
/// The clock is PINNED when the call starts (`ConversationView.pinPromptClock`),
/// never re-read per turn: the system prompt is rebuilt on every turn and the
/// realtime gateway is handed it once, and both must describe the same call.
/// "This call started at 08:14" stays true for the whole call; "it is 08:14"
/// would not.
///
/// Every distance in days is a CALENDAR distance (`calendarDays`), never
/// elapsed seconds over 86,400: a talk at 23:00 is "yesterday" at 08:00 the
/// next morning, though only nine hours have passed. The prompts' two older
/// clocks — `ConversationEngine.age` and the daily call's
/// `daysSinceLastTalk` — measured elapsed time and said "today" for it.
struct PromptClock: Equatable {
    /// When this call started.
    var now: Date
    var timeZone: TimeZone
    /// Talks the learner SPOKE in earlier today (their local day), in any
    /// language or mode, not counting this one.
    var talksEarlierToday: Int
    /// When the latest of those ended (its last line).
    var lastTalkToday: Date?
    /// The last talk before today, when there is one.
    var lastTalkBeforeToday: Date?
    /// This call picks up a saved talk: when that talk's last line was said.
    var resumedFrom: Date?

    /// Build the snapshot from the saved talks. Pass every language's
    /// sessions — the fluent self is one person, and "our first talk today"
    /// after a morning in the other language is a lie the learner hears.
    ///
    /// A talk counts only if the learner said something in it: a call opened
    /// and closed in silence is not a talk anyone remembers having. A talk is
    /// dated by its LAST line, so one that ran past midnight belongs to the
    /// day it ended. Anything dated after `now` (another device's clock) is
    /// ignored rather than counted as today.
    static func make(now: Date = Date(),
                     sessions: [Session],
                     excluding currentSessionId: UUID? = nil,
                     resumedFrom: Date? = nil,
                     calendar: Calendar = .current) -> PromptClock {
        let startOfToday = calendar.startOfDay(for: now)
        let talkTimes: [Date] = sessions.compactMap { s in
            guard s.id != currentSessionId,
                  s.turns.contains(where: { $0.role == .user }) else { return nil }
            let at = s.turns.map(\.timestamp).max() ?? s.endedAt ?? s.startedAt
            return at <= now ? at : nil
        }
        let today = talkTimes.filter { $0 >= startOfToday }
        let before = talkTimes.filter { $0 < startOfToday }
        return PromptClock(now: now,
                         timeZone: calendar.timeZone,
                         talksEarlierToday: today.count,
                         lastTalkToday: today.max(),
                         lastTalkBeforeToday: before.max(),
                         resumedFrom: resumedFrom.map { min($0, now) })
    }

    // MARK: - Calendar arithmetic (the one implementation)

    /// Whole calendar days from `from` to `to` in `calendar`'s time zone:
    /// 0 = same day, 1 = `from` was yesterday. Never negative.
    static func calendarDays(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: from),
                                           to: calendar.startOfDay(for: to)).day ?? 0
        return max(0, days)
    }

    /// "morning" · "afternoon" · "evening" · "night" for an hour 0–23.
    /// Before 5 is still the night before in anyone's head.
    static func partOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }

    /// "a few minutes ago" · "about 3 hours ago" · "yesterday (Sunday)" ·
    /// "5 days ago (Wednesday)" · "3 weeks ago" — for a gap in the prompt.
    /// Hours within the same day (the second call of a day is what "long time
    /// no see" got wrong), calendar days beyond it, and the weekday while it
    /// still means something.
    static func gap(from date: Date, to now: Date, calendar: Calendar = .current) -> String {
        let days = calendarDays(from: date, to: now, calendar: calendar)
        if days == 0 {
            let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
            if minutes < 10 { return "a few minutes ago" }
            if minutes < 60 { return "about \(minutes) minutes ago" }
            let hours = minutes / 60
            return hours == 1 ? "about an hour ago" : "about \(hours) hours ago"
        }
        let weekday = " (\(weekdayName(date, calendar: calendar)))"
        switch days {
        case 1: return "yesterday" + weekday
        case 2..<7: return "\(days) days ago" + weekday
        case 7..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEE", calendar: calendar).string(from: date)
    }

    /// English, Gregorian, in the learner's zone: the prompt is English and
    /// the model must never have to convert a calendar or a zone.
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// "Monday, 28 September 2026" — a date line for prompts that need only
    /// the day (the summary).
    static func dayLine(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("EEEE, d MMMM yyyy", calendar: calendar).string(from: date)
    }

    // MARK: - The prompt block

    /// The block the conversation prompt carries.
    ///
    /// - Parameter includeHistory: whether the learner's talk history belongs
    ///   in THIS call. False for a cast stranger (new acquaintances, no
    ///   shared past — that block says so) and for the first meeting (whose
    ///   own block already says what the relationship is). A scene
    ///   counterpart is decided by the model, not here, so the guard tells a
    ///   character the history is not theirs.
    func promptBlock(includeHistory: Bool, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.timeZone = timeZone
        let day = Self.dayLine(now, calendar: cal)
        let time = Self.formatter("HH:mm", calendar: cal).string(from: now)
        let part = Self.partOfDay(hour: cal.component(.hour, from: now))

        var lines = ["- This call started on \(day), at \(time) — \(part) where the user is."]
        if includeHistory {
            if talksEarlierToday == 0 {
                lines.append("- This is their FIRST talk today.")
            } else {
                let latest = lastTalkToday.map { ", the latest ended \(Self.gap(from: $0, to: now, calendar: cal))" } ?? ""
                let count = talksEarlierToday == 1 ? "1 talk" : "\(talksEarlierToday) talks"
                lines.append("- They already had \(count) earlier today\(latest).")
            }
            if let before = lastTalkBeforeToday {
                lines.append("- Before today, their last talk was \(Self.gap(from: before, to: now, calendar: cal)).")
            } else if talksEarlierToday == 0 {
                lines.append("- They have never had a talk here before this one.")
            }
        }
        if let resumed = resumedFrom {
            lines.append("- This call RESUMES a saved talk that paused \(Self.gap(from: resumed, to: now, calendar: cal)). The lines already in the conversation were said then, not just now — pick it back up the way you would after that much time.")
        }

        return """


        WHEN THIS IS — the user's own clock, and your ONLY source for time:
        \(lines.joined(separator: "\n"))
        Use this to get time RIGHT, not to talk about it. Greet for the part of \
        the day it actually is, or don't mention it at all. Never announce the \
        date, a count of talks, or how long it has been unless it comes up \
        naturally. A talk earlier today means you spoke recently — never greet \
        them as if after a long absence. Anything about time that is not \
        written here — the hour later in the call, a count, a gap — you do NOT \
        know: never guess it, and never invent how many times you have talked. \
        If you are playing a character in a scene rather than their future \
        self, their talk history is not yours; leave it out.
        """
    }
}
