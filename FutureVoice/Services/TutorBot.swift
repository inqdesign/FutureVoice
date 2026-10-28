import Foundation
import SwiftUI

/// The tutor bot (2026-10-28, founder): the face at the Talk tab's bottom
/// right. Its ONE job is that the learner always knows what to do next, and
/// why. It speaks in three ways, each quieter than the last:
///
/// - **A note, once a day** — on the first open of the day, today's plan
///   rises out of the face. No dim, nothing blocked; a tap elsewhere folds
///   it back. The very first one introduces the bot.
/// - **A bubble, only when there is something to say** — a step just
///   finished and the next is ready, a planned time arrived, the day is
///   done. Never the same thing twice a day, never more than `maxBubbles`.
/// - **A chat, when tapped** — today's plan as the first message, then any
///   question about the learner's own practice (`TutorChat`).
///
/// Everything the note and the bubble say is computed in code from the
/// routine and the logs Activity already reads (`PlannerSnapshot`), so it
/// is instant, free and cannot disagree with My routine. Only the chat asks
/// a model. It replaced the quick quiz's door; the quiz is now one of the
/// things the bot can hand you.
@MainActor
final class TutorBot: ObservableObject {
    static let shared = TutorBot()

    /// One thing to do today.
    struct Item: Identifiable, Equatable {
        var id: String
        var kind: StudyPlan.Kind
        var title: String
        var start: Date
        var anytime: Bool
        var progress: Double
        var done: Bool { progress >= 1 }
        var end: Date
        func isNow(_ now: Date) -> Bool { !done && !anytime && start <= now && now < end }
    }

    struct Today: Equatable {
        var day: Date = .distantPast
        var items: [Item] = []
        /// No routine for today: the items are the bot's own suggestion.
        var suggested = false
        /// The learner has blocks on other days — today rests.
        var restDay = false
        var dueCards = 0
        var streak = 0
        var focusLabel: String?
        var focusTalks = 0
        var talkedToday = 0

        var left: [Item] { items.filter { !$0.done } }
        var allDone: Bool { !items.isEmpty && left.isEmpty }
        var minutesLeft: Int { left.reduce(0) { $0 + max(1, Int(($1.end.timeIntervalSince($1.start) / 60).rounded())) } }

        /// The one thing to do now: a block whose time is on, then an
        /// anytime one, then the next timed one, then anything undone.
        func next(at now: Date = Date()) -> Item? {
            items.first { $0.isNow(now) }
                ?? items.first { !$0.done && $0.anytime }
                ?? items.first { !$0.done && $0.start > now }
                ?? items.first { !$0.done }
        }
    }

    struct Bubble: Identifiable, Equatable {
        var id: String          // the "said today" key
        var text: String
        var kind: StudyPlan.Kind?
        var action: String?     // button title; nil = just OK
    }

    @Published private(set) var today = Today()
    @Published var noteShown = false
    @Published var introShown = false
    @Published private(set) var bubble: Bubble? {
        didSet { if bubble != nil { bubbleSince = Date() } }
    }
    /// When the face last had something to say — its happy blink runs from here.
    @Published private(set) var bubbleSince = Date.distantPast
    @Published var chatOpen = false
    @Published var quizOpen = false

    static let maxBubbles = 3
    /// Quiet after the note closes — the note just said everything.
    static let quietAfterNote: TimeInterval = 60

    private let defaults = UserDefaults.standard
    private enum Key {
        static let introSeen = "futurevoice.tutorBot.introSeen"
        static let noteDay = "futurevoice.tutorBot.noteDay"
        static let saidDay = "futurevoice.tutorBot.saidDay"
        static let said = "futurevoice.tutorBot.said"
        static let doneIds = "futurevoice.tutorBot.doneIds"
    }
    private var noteClosedAt: Date?

    private init() {
        #if DEBUG
        if defaults.bool(forKey: "tutorReset") { Self.resetForTesting() }
        // `-tutorShow plan|chat|bubble`: the screen to capture.
        switch defaults.string(forKey: "tutorShow") {
        case "plan":
            Self.resetForTesting()
            defaults.set(true, forKey: Key.introSeen)
        case "chat":
            defaults.set(StudyPlan.dayKey(Date()), forKey: Key.noteDay)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.chatOpen = true
            }
        case "bubble":
            defaults.set(StudyPlan.dayKey(Date()), forKey: Key.noteDay)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.say(Bubble(id: "debug-\(UUID())", text: explain("Nice, \(StudyPlan.Kind.review.label.lowercased()) done. Next up: \(StudyPlan.Kind.shadow.titled(2))."),
                                kind: .shadow, action: explain("Start")))
            }
        default: break
        }
        #endif
    }

    // MARK: - Today

    /// Today's plan, judged by Activity's own rule. With no routine at all,
    /// the bot suggests a day from what is waiting.
    static func makeToday(appState: AppState, now: Date = Date()) -> Today {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let plan = StudyPlanStore.shared.plan
        let snap = PlannerSnapshot.make(weekStart: day, plan: plan, now: now)
        let progress = snap.progress[day] ?? [:]
        var out = Today(day: day)
        out.items = (snap.planned[day] ?? []).map { occ in
            Item(id: occ.id, kind: occ.kind,
                 title: occ.kind == .review ? occ.kind.label : occ.kind.titled(occ.amount),
                 start: occ.start, anytime: occ.anytime, progress: progress[occ.id] ?? 0, end: occ.end)
        }
        out.dueCards = DrillStore.shared.dueCount(now: now) + ReviewQueue.dueItems(now: now).count
        out.streak = PracticeStats.snapshot(now: now).streakDays
        out.talkedToday = PracticeStats.todayTalkSeconds(now: now) / 60
        if out.items.isEmpty {
            if plan.blocks.isEmpty {
                out.suggested = true
                out.items = suggestedDay(day: day, now: now, dueCards: out.dueCards)
            } else {
                out.restDay = true
            }
        }
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }
        if let top = GrammarFocus.candidates(from: appState.learnerProfile, sessions: sessions, now: now).first {
            out.focusTalks = top.talks
            out.focusLabel = cachedFocusLabel(top.pattern, native: appState.nativeLanguage)
                ?? "\u{201C}\(top.pattern.mistake)\u{201D} → \u{201C}\(top.pattern.correction)\u{201D}"
        }
        return out
    }

    /// No routine: a talk, and review when something is waiting. Judged
    /// done by the same totals a planned block would be.
    private static func suggestedDay(day: Date, now: Date, dueCards: Int) -> [Item] {
        let events = ActivityEventLog.shared.events(from: day, to: day.addingTimeInterval(86_400))
        let totals = PlannerDay.totals(on: day, events: events, testFinished: false)
        var items: [Item] = []
        if dueCards > 0 {
            let n = min(10, dueCards)
            items.append(Item(id: "suggested-review", kind: .review, title: StudyPlan.Kind.review.label,
                              start: day, anytime: true,
                              progress: min(1, totals.amount(for: .review) / Double(n)),
                              end: day.addingTimeInterval(Double(StudyPlan.Kind.review.drawnMinutes(amount: n)) * 60)))
        }
        items.append(Item(id: "suggested-talk", kind: .talk, title: StudyPlan.Kind.talk.titled(10),
                          start: day, anytime: true,
                          progress: min(1, totals.talkMinutes / 10), end: day.addingTimeInterval(600)))
        return items
    }

    /// The grammar focus's name as the call strip shows it — read from
    /// `GrammarFocus.describe`'s cache only, never asked for here.
    private static func cachedFocusLabel(_ p: LearnerPattern, native: String) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: "futurevoice.coach.focusDescriptions.v2")
            as? [String: [String: String]]
        guard let hit = cache?["\(LearnerProfile.patternKey(p))|\(native)"], hit["grammar"] != "false" else { return nil }
        return hit["label"]
    }

    // MARK: - Refresh

    /// Re-reads the day and decides whether there is anything to say.
    /// `visible` is the Talk home on screen with nothing over it.
    func refresh(appState: AppState, visible: Bool, now: Date = Date()) {
        let fresh = Self.makeToday(appState: appState, now: now)
        let dayKey = StudyPlan.dayKey(now)
        if defaults.string(forKey: Key.saidDay) != dayKey {
            defaults.set(dayKey, forKey: Key.saidDay)
            defaults.set([String](), forKey: Key.said)
            defaults.set(fresh.items.filter(\.done).map(\.id), forKey: Key.doneIds)
        }
        let before = Set(defaults.stringArray(forKey: Key.doneIds) ?? [])
        let doneNow = Set(fresh.items.filter(\.done).map(\.id))
        defaults.set(Array(doneNow), forKey: Key.doneIds)
        today = fresh
        guard visible else { return }

        // Once a day, the note — the first open of the day.
        if defaults.string(forKey: Key.noteDay) != dayKey {
            defaults.set(dayKey, forKey: Key.noteDay)
            bubble = nil
            introShown = !defaults.bool(forKey: Key.introSeen)
            bubbleSince = now
            Analytics.capture("tutor_bot_note", ["intro": introShown, "items": fresh.items.count,
                                                 "suggested": fresh.suggested])
            withAnimation(.easeOut(duration: 0.5)) { noteShown = true }
            return
        }
        guard !noteShown, !chatOpen else { return }
        if let closed = noteClosedAt, now.timeIntervalSince(closed) < Self.quietAfterNote { return }
        if let b = nextBubble(today: fresh, newlyDone: doneNow.subtracting(before), now: now) {
            say(b)
        }
    }

    /// The one thing worth saying now, or nil — the usual answer.
    private func nextBubble(today: Today, newlyDone: Set<String>, now: Date) -> Bubble? {
        let next = today.next(at: now)
        // The day just finished.
        if !newlyDone.isEmpty, today.allDone {
            return Bubble(id: "done", text: explain("That's everything for today. Nicely done."),
                          kind: nil, action: nil)
        }
        // A step just finished and the next one is ready.
        if let justDone = today.items.first(where: { newlyDone.contains($0.id) }), let next {
            return Bubble(id: "after-\(justDone.id)",
                          text: explain("Nice, \(justDone.kind.label.lowercased()) done. Next up: \(next.title)."),
                          kind: next.kind, action: explain("Start"))
        }
        // A planned time has come.
        if let now = today.items.first(where: { $0.isNow(now) }) {
            return Bubble(id: "now-\(now.id)", text: PlanReminder.nowLine(for: now.kind) + " · " + now.title,
                          kind: now.kind, action: explain("Start"))
        }
        return nil
    }

    private func say(_ b: Bubble) {
        var said = defaults.stringArray(forKey: Key.said) ?? []
        guard !said.contains(b.id), said.count < Self.maxBubbles else { return }
        said.append(b.id)
        defaults.set(said, forKey: Key.said)
        Analytics.capture("tutor_bot_bubble", ["kind": b.id.components(separatedBy: "-").first ?? b.id])
        withAnimation(.easeOut(duration: 0.35)) { bubble = b }
    }

    // MARK: - Actions

    func closeNote() {
        if introShown { defaults.set(true, forKey: Key.introSeen) }
        noteClosedAt = Date()
        withAnimation(.easeInOut(duration: 0.35)) { noteShown = false }
    }

    /// The note, again — the face's long-press.
    func showNote(intro: Bool = false) {
        bubble = nil
        introShown = intro
        bubbleSince = Date()
        withAnimation(.easeOut(duration: 0.5)) { noteShown = true }
    }

    func dismissBubble() {
        withAnimation(.easeOut(duration: 0.25)) { bubble = nil }
    }

    func openChat() {
        dismissBubble()
        if noteShown { closeNote() }
        chatOpen = true
    }

    /// Opens the practice a kind names, through the door its reminder and
    /// widget already use. nil = the quick quiz.
    func start(_ kind: StudyPlan.Kind?, appState: AppState) {
        dismissBubble()
        if noteShown { closeNote() }
        chatOpen = false
        Analytics.capture("tutor_bot_start", ["kind": kind?.rawValue ?? "quiz"])
        guard let kind else { quizOpen = true; return }
        if kind == .talk {
            appState.requestFreeTalk(from: .tutorBot)
            return
        }
        DailyCallInbox.shared.pendingURL = URL(string: "futurevoice://routine?kind=\(kind.rawValue)")
    }

    #if DEBUG
    /// `-tutorReset 1`: meet the bot again, today's note unseen.
    static func resetForTesting() {
        let d = UserDefaults.standard
        for k in [Key.introSeen, Key.noteDay, Key.saidDay, Key.said, Key.doneIds] { d.removeObject(forKey: k) }
    }
    #endif
}

// MARK: - Chat

/// "Ask me anything": a short thread whose first message is today's plan.
/// Each answer is grounded in the learner's own numbers (`context`) and ends
/// in something to start. Kept in memory for the day, never written to disk.
@MainActor
final class TutorChat: ObservableObject {
    static let shared = TutorChat()

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromLearner: Bool
        var text: String
        var action: StudyPlan.Kind?
        var quiz = false
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var thinking = false
    private var day = ""

    func resetIfNewDay() {
        let key = StudyPlan.dayKey(Date())
        if key != day { day = key; messages = [] }
    }

    private struct Reply: Decodable { let reply: String; let action: String? }

    func ask(_ question: String, appState: AppState) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        messages.append(Message(fromLearner: true, text: q))
        thinking = true
        defer { thinking = false }
        let history = messages.suffix(12).map {
            GeminiClient.Message(role: $0.fromLearner ? .user : .model, content: $0.text)
        }
        do {
            let r: Reply = try await GeminiClient.shared.sendJSON(
                system: Self.system(appState: appState),
                messages: Array(history),
                model: .flash36, maxTokens: 900, purpose: "tutor-bot",
                idempotencyKey: "tutor-bot:\(UUID().uuidString)", requestTimeout: 30)
            let action = r.action.flatMap { $0 == "quiz" ? nil : StudyPlan.Kind(rawValue: $0) }
            messages.append(Message(fromLearner: false,
                                    text: r.reply.trimmingCharacters(in: .whitespacesAndNewlines),
                                    action: action, quiz: r.action == "quiz"))
            Analytics.capture("tutor_bot_asked", ["action": r.action ?? "none"])
        } catch {
            messages.append(Message(fromLearner: false,
                                    text: explain("I couldn't answer that just now. Try again in a moment.")))
        }
    }

    // MARK: Prompt

    static func system(appState: AppState) -> String {
        let native = LanguageCatalog.englishName(appState.nativeLanguage)
        let target = LanguageCatalog.englishName(appState.targetLanguage)
        let korean = appState.nativeLanguage == "ko"
            ? "\nIn Korean, write in polite 해요체. Never use 당신; address them by nothing at all." : ""
        return """
            You are the learner's TUTOR inside nawana, an app where they practise \(target) by \
            talking with their own cloned voice (their "fluent self"). You are NOT the fluent \
            self and not a conversation partner. You know their routine, their talks, their \
            mistakes and their review cards — the data below. Your one job: they always know \
            what to do next, and why.

            HOW YOU ANSWER
            - 2 to 4 short sentences. Plain, warm, direct. No lists, no headings, no emoji.
            - Use THEIR numbers and THEIR own sentences from the data. Never invent a number, \
              a talk or a mistake that is not in the data. If the data can't answer, say so.
            - Be honest. If something they do is holding them back (e.g. talking every day but \
              never reviewing), say it plainly WITH the reason. Never scold, never guilt.
            - End with ONE concrete next step they can start now, and set "action" to it.
            - Explanations in \(native). Any example sentence to SAY goes in \(target), quoted.\(korean)
            - If they ask about something outside their learning (news, coding…), answer in one \
              line that you're here for their \(target), then suggest a step.

            WHAT YOU CAN HAND THEM ("action", exactly one of):
            talk (a call with the fluent self), review (cards from their own mistakes and saved \
            words), shadow (repeat lines from their talks), sayItAgain (redo a past talk the right \
            way), listen (podcast and their scenes), speech (record a speech), quiz (one-minute \
            quiz), none.

            Return JSON: {"reply": "...", "action": "..."}

            THE LEARNER, AS OF NOW
            \(context(appState: appState))
            """
    }

    /// Everything the tutor may say about the learner, in plain lines.
    static func context(appState: AppState, now: Date = Date()) -> String {
        let cal = Calendar.current
        let t = TutorBot.makeToday(appState: appState, now: now)
        var lines: [String] = []
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        lines.append("Now: \(f.string(from: now))")
        lines.append("Learning \(LanguageCatalog.englishName(appState.targetLanguage)), level \(appState.proficiency.rawValue.uppercased()); native \(LanguageCatalog.englishName(appState.nativeLanguage)).")
        if let p = appState.persona {
            if !p.displayName.isEmpty { lines.append("Name: \(p.displayName)") }
            let about = [p.occupation, p.city, p.interests.joined(separator: ", ")].filter { !$0.isEmpty }
            if !about.isEmpty { lines.append("They told setup: " + about.joined(separator: " · ")) }
        }
        lines.append("Streak: \(t.streak) days. Talked today: \(t.talkedToday) min. Review cards waiting: \(t.dueCards).")

        if t.restDay {
            lines.append("Today: a rest day in their routine.")
        } else if !t.items.isEmpty {
            lines.append(t.suggested ? "Today (no routine set; your suggestion):" : "Today's routine:")
            for i in t.items {
                let when = i.anytime ? "anytime" : String(format: "%02d:%02d", cal.component(.hour, from: i.start), cal.component(.minute, from: i.start))
                lines.append("- \(i.kind.rawValue) \(when): \(Int(i.progress * 100))% done")
            }
        }

        // The last seven days, from the same logs Activity reads.
        var week: [String] = []
        for back in (0..<7).reversed() {
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            let log = PracticeLog.shared.day(d) ?? PracticeLog.Day()
            let talk = TalkTimeLog.seconds(on: d) / 60
            let review = log.wordReps + log.expressionReps + log.drillReps
            week.append("\(f.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1]): talk \(talk)m, review \(review), shadow \(log.shadowDone)")
        }
        lines.append("Last 7 days: " + week.joined(separator: "; "))

        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil && $0.archivedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
        lines.append("Talks in total: \(sessions.count).")
        for s in sessions.prefix(5) {
            let said = s.turns.filter(\.isEvidence)
            lines.append("- Talk \(f.string(from: s.startedAt)): \"\(s.displayTitle)\", they spoke \(said.count) times"
                         + (said.last.map { ". Their last line: \"\(String($0.transcript.prefix(140)))\"" } ?? ""))
        }

        let mistakes = GrammarFocus.candidates(from: appState.learnerProfile, sessions: sessions, now: now)
        if mistakes.isEmpty {
            let any = appState.learnerProfile.recurringMistakes.sorted { $0.lastSeenAt > $1.lastSeenAt }.prefix(3)
            for m in any { lines.append("Mistake seen: \"\(m.mistake)\" → \"\(m.correction)\" (\(m.context))") }
        } else {
            for m in mistakes.prefix(3) {
                lines.append("Recurring mistake, said in \(m.talks) talks: \"\(m.pattern.mistake)\" → \"\(m.pattern.correction)\" (\(m.pattern.context))")
            }
        }
        if !appState.learnerProfile.weakVocabAreas.isEmpty {
            lines.append("Weak vocabulary areas: " + appState.learnerProfile.weakVocabAreas.prefix(5).joined(separator: ", "))
        }
        if !appState.learnerProfile.strongPatterns.isEmpty {
            lines.append("Already strong at: " + appState.learnerProfile.strongPatterns.prefix(5).joined(separator: ", "))
        }
        let vocab = VocabStore.shared
        lines.append("Notebook: \(vocab.studying.count) words, \(vocab.studyingExpressions.count) expressions being studied.")
        if let notes = appState.persona?.currentNotes(at: now).suffix(6), !notes.isEmpty {
            lines.append("About their life: " + notes.map(\.text).joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}
