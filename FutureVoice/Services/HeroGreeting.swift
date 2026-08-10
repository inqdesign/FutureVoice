import Foundation

/// The one line above the Talk tab's goal ring.
///
/// It used to be a pure clock read — four "What's on your mind …?" variants
/// picked by the hour, identical on day 1 and day 300. Two things replace it,
/// in that order:
///
/// 1. **A state line, only when today is actually different** — first run, a
///    call that rang out, a comeback after a gap, the goal already met. These
///    are the moments where a fixed greeting reads as a screen that isn't
///    paying attention.
/// 2. **Otherwise a short opening question**, drawn from a small pool per
///    time of day. The clock still colours the line (morning ≠ midnight); the
///    pool is what keeps day 300 from reading like day 1.
///
/// Everything here is CHROME → target language (see CLAUDE.md "Two
/// languages"), so every line goes through `chrome()`.
///
/// **The line must never change while the learner is looking at it.** The hero
/// re-renders on every scroll frame, and a greeting that swaps mid-scroll (or
/// a frame after launch) reads as a bug. So the rotation index is derived,
/// never animated into place: it comes from the day plus a cursor that only
/// moves when a call ENDS — the one moment the home is covered by the call's
/// backdrop. Same reason `Input.live()` exists: the first painted frame
/// computes the final line straight from the stores instead of showing a
/// placeholder that a later `onAppear` corrects.
enum HeroGreeting {

    // MARK: - Input

    struct Input {
        var now: Date = Date()
        /// A daily call rang out and its voicemail is still unheard.
        var hasMissedCall: Bool = false
        /// Ended sessions, all-time. Zero = the learner has never talked.
        var sessionCount: Int = 0
        var lastSessionEndedAt: Date?
        var todaySpokenSeconds: Int = 0
        var dailyGoalMinutes: Int = 10
        /// Advances once per finished call — see `advanceRotation()`.
        var rotationCursor: Int = 0
        var calendar: Calendar = .current
    }

    /// Everything the line needs, read straight from the stores.
    ///
    /// Cheap enough to call during `body`: `SessionStore.load()` is
    /// memory-cached after its first decode, and the daily-call plan is a
    /// single small file. The Talk view still caches the RESULT in `@State`
    /// so the per-scroll-frame path stays a string read.
    @MainActor
    static func live(now: Date = Date()) -> Input {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        var todaySeconds = 0
        for session in sessions where (session.endedAt ?? session.startedAt) >= todayStart {
            for turn in session.turns where turn.role == .user {
                todaySeconds += turn.durationMs
            }
        }
        let lastEnded = sessions.compactMap(\.endedAt).max()
        let goal = UserDefaults.standard.object(forKey: goalMinutesKey) as? Int

        var missed = false
        if DailyCallStore.shared.isEnabled, let plan = DailyCallStore.shared.load() {
            missed = plan.hasUnheardVoicemail
        }

        return Input(now: now,
                     hasMissedCall: missed,
                     sessionCount: sessions.count,
                     lastSessionEndedAt: lastEnded,
                     todaySpokenSeconds: todaySeconds / 1000,
                     dailyGoalMinutes: goal ?? 10,
                     rotationCursor: UserDefaults.standard.integer(forKey: cursorKey),
                     calendar: cal)
    }

    /// Matches `ConversationHome`'s `@AppStorage`.
    private static let goalMinutesKey = "futurevoice.dailyGoalMinutes"
    private static let cursorKey = "futurevoice.heroLineCursor"

    /// Move to the next line. Called when a CALL ENDS — never on appear: the
    /// home is behind the call's backdrop at that moment, so the swap is
    /// invisible, and a learner sitting on the launcher never sees the text
    /// move under them.
    static func advanceRotation() {
        let next = UserDefaults.standard.integer(forKey: cursorKey) &+ 1
        UserDefaults.standard.set(next, forKey: cursorKey)
    }

    // MARK: - Which line

    enum Kind: Equatable {
        case firstRun
        case missedCall
        /// Back after `comebackGapDays`+ away with nothing spoken today.
        case comeback
        case goalMet
        case question
    }

    /// A comeback needs a real gap: two days away reads as a normal weekend,
    /// three starts to feel like an absence worth naming.
    static let comebackGapDays = 3

    static func kind(for input: Input) -> Kind {
        if input.sessionCount == 0 { return .firstRun }
        if input.hasMissedCall { return .missedCall }
        if isComeback(input) { return .comeback }
        if goalMet(input) { return .goalMet }
        return .question
    }

    private static func isComeback(_ input: Input) -> Bool {
        // Once they've spoken today the gap is history — "it's been a while"
        // next to a moving goal ring is just wrong.
        guard input.todaySpokenSeconds == 0, let last = input.lastSessionEndedAt else { return false }
        let cal = input.calendar
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: last),
                                      to: cal.startOfDay(for: input.now)).day ?? 0
        return days >= comebackGapDays
    }

    private static func goalMet(_ input: Input) -> Bool {
        guard input.dailyGoalMinutes > 0 else { return false }
        return input.todaySpokenSeconds >= input.dailyGoalMinutes * 60
    }

    // MARK: - The line itself

    static func text(for input: Input) -> String {
        switch kind(for: input) {
        case .firstRun:
            return pick([
                chrome("Ready for your first talk?"),
                chrome("Shall we start small?"),
            ], input)
        case .missedCall:
            return pick([
                chrome("I called earlier."),
                chrome("I left you a message."),
            ], input)
        case .comeback:
            return pick([
                chrome("It's been a while."),
                chrome("Good to have you back."),
                chrome("Long time. Where were we?"),
            ], input)
        case .goalMet:
            return pick([
                chrome("Today's done. One more?"),
                chrome("You hit today's goal."),
                chrome("Goal met. How did it feel?"),
            ], input)
        case .question:
            return pick(questions(hour: input.calendar.component(.hour, from: input.now)), input)
        }
    }

    /// Four openings per stretch of the day. Short on purpose — this is set in
    /// a 28pt display face above the ring, and anything past a line and a half
    /// pushes the ring off the fold.
    private static func questions(hour: Int) -> [String] {
        switch hour {
        case 5..<12:
            return [
                chrome("What's on your mind this morning?"),
                chrome("Did you sleep well?"),
                chrome("What's the plan today?"),
                chrome("How does today look?"),
            ]
        case 12..<17:
            return [
                chrome("What's on your mind this afternoon?"),
                chrome("How's your day going?"),
                chrome("Busy today?"),
                chrome("What did you do today?"),
            ]
        case 17..<22:
            return [
                chrome("What's on your mind this evening?"),
                chrome("How was your day?"),
                chrome("Anything good today?"),
                chrome("How did today go?"),
            ]
        default:
            return [
                chrome("What's on your mind tonight?"),
                chrome("Still up?"),
                chrome("How was today?"),
                chrome("Thinking about tomorrow?"),
            ]
        }
    }

    /// Rotation = the day plus the finished-call cursor. Both move the line
    /// forward, neither can move it while it's on screen: the day is fixed for
    /// 24 hours and the cursor only advances behind the call backdrop.
    private static func pick(_ options: [String], _ input: Input) -> String {
        guard !options.isEmpty else { return "" }
        let day = input.calendar.ordinality(of: .day, in: .year, for: input.now) ?? 0
        // &+ / abs: the cursor is a monotonically growing Int the learner can
        // in principle push a long way — never let a negative index in.
        let index = abs((day &+ input.rotationCursor) % options.count)
        return options[index]
    }
}
