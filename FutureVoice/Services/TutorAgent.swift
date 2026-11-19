import Foundation

/// The tutor chat as an AGENT (2026-10-30, founder: "it really needs to feel
/// like an agent… understand the entire app and guide the learner through
/// it, whatever they ask"). Until this the chat was one call with a fixed
/// snapshot of the learner attached and eight buttons it could hand out, so
/// any question the snapshot didn't cover — a talk from two weeks ago, a
/// book, the notebook, the test — came back as "review your cards".
///
/// Three parts, all on the phone because the practice lives on the phone:
///
/// - **The manual** (`TutorAgent.manual`): what every part of the app is FOR
///   and when to suggest it, so the tutor can guide through features it was
///   never told about before.
/// - **Lookups** (`TutorTools`): the model asks for what it needs ("read the
///   talk of Oct 22", "my notebook") and the app answers from the stores, up
///   to `maxRounds` times, before it writes the reply. A JSON protocol on the
///   ordinary `sendJSON`, not provider function calling — the edge function
///   strips tools from every purpose but two, and this needs no deploy.
/// - **Buttons** (`TutorAction`): up to two under a reply, each one OPENS
///   something (a call on a topic, a book, a goal's model answer, a word's
///   card). Nothing the tutor hands out changes the learner's data: the
///   learner taps, and the screen it opens is the one they already know.
///   That is the founder's "nothing bad happens if I follow it" held in code.
enum TutorAgent {
    /// Lookup rounds before the reply must be written. One is the usual; a
    /// question like "compare my last two interviews" needs a second.
    static let maxRounds = 3

    /// What the app is, feature by feature — for the tutor, not for screens.
    /// Kept in the order a learner's week runs: do → review → measure.
    static let manual = """
        THE APP (what each part is for, and when it is the right thing to suggest)
        - Talk tab: a phone call with their fluent self (their own cloned voice, fluent). \
        Free talk, a topic, a news story, or a scenario. Every call ends in a book of its own \
        (words, expressions, shadow lines, corrected sentences). The single best practice; \
        suggest it when they want to speak more, or to use what they just studied.
        - Tutor mode (a call setting, or a lesson you hand them): a call with ONE goal they \
        repeat until they can say it — 3–4 small challenges on a topic, then a final check. \
        The right thing when they want to be able to SAY something specific (introduce their \
        job, answer an interview question, order, complain politely).
        - Coach mode (a call setting): a "try saying" line under every question, for when \
        calls feel too hard. Easy calls: Call settings make it slower / coach on.
        - Say it again: redo a past talk with their own corrected lines on a prompter, the \
        fluent self's real answers in between. Best right after a talk with many corrections.
        - Review (Review tab): cards made from their own corrections, words and expressions \
        from their talks, on a schedule (10 min / tomorrow / 3 days / got it). A few minutes a \
        day. Words USED in a later talk count as learned for good.
        - Shadowing: they hear one fluent line (the fluent self: their own cloned voice, \
        speaking fluently) and say it after it; scored on words and rhythm. For pronunciation \
        and flow, and to make a sentence they know automatic.
        - Watch tab: simulate a situation BEFORE it happens (an interview, a doctor, a \
        difficult talk with a person they know). The fluent self plays it out as a scene; \
        they watch, then practise it. People row = their own people; Find people = strangers.
        - Books (Review tab shelves): every talk and scene is a book with chapters Words · \
        Expressions · Shadowing · Grammar.
        - Weekly test: once a week, built only from their own week. "Your week": the week's \
        report.
        - Speech tab: read a script aloud on camera, scored; public challenges with a board.
        - Listening: the nawana Podcast (a daily episode) and their own scenes as audio.
        - Why they are learning (set in onboarding; changed in Me → Profile, Talk settings, or \
        your "purposes" button): one answer behind Talk's topic chips, their goals and you. If \
        what they tell you no longer matches it (a new job hunt, an exam they gave up), offer \
        the button so they can change it.
        - Upcoming goals (Me → Profile, or the tutor's "Add a goal"): an interview or exam \
        with a date and material (posting, CV). Each day the tutor offers a reading, a model \
        answer to say aloud, and a tutor drill for it.
        - My routine: their weekly plan (talk at 8:00, review at 21:00…); a day counts \
        toward the streak once ONE planned block is started. Change it in Activity → Edit weekly plan.
        - Progress tab: level estimate and each skill.
        - You (this page): they type, or dictate with the mic in the box, in the language \
        they are learning or their own. A dictated message can carry a misheard word: read \
        past it to what they plainly meant, and never comment on spelling or punctuation. \
        You have no voice here; the fluent self's voice and speed are in Me → Voice and call settings.
        """

    /// The reply format the model must keep. Field order: `lookup` first, so
    /// a model that is going to look something up says so before writing.
    static let protocolBlock = """
        HOW THIS CHAT WORKS
        Every turn you return ONE JSON object and nothing else, even for a one-line answer; \
        never plain text. Paragraph breaks inside "reply" are written \n. Either:
        A) {"lookup": [{"tool": "<name>", "args": {...}}]} — when the data below is not \
        enough to answer well. Ask for everything you need at once (up to 4 tools). The \
        results come back in the next message, then you answer. Never look up what is \
        already below.
        B) {"reply": "...", "translation": "...", "actions": [{"type": "...", ...}]} — your \
        answer, the same answer in their own language, and 0 to 2 buttons under it.

        LOOKUPS (tool names and args)
        \(TutorTools.catalog)

        BUTTONS ("actions"; each opens something, nothing is changed without the learner):
        {"type":"talk"} a free call · {"type":"talk","topic":"…"} a call on a topic \
        (topic in the target language, one short line) · {"type":"lesson","topic":"…"} a \
        tutor-mode lesson on what they want to be able to say · {"type":"book","id":"<talk \
        or scenario id>"} open that book (also the door to Say it again for that talk) · \
        {"type":"goal","id":"<goal id>"} the goal's page · {"type":"goalReading","id":…} / \
        {"type":"goalAnswer","id":…} today's reading / model answer for that goal · \
        {"type":"word","text":"…"} / {"type":"expression","text":"…"} its card · \
        {"type":"review"} the waiting cards · {"type":"shadow"} · {"type":"sayItAgain"} · \
        {"type":"listen"} · {"type":"speech"} · {"type":"test"} the weekly test · \
        {"type":"quiz"} one-minute quiz · {"type":"routine"} their weekly plan · \
        {"type":"settings"} call settings · {"type":"purposes"} why they are learning. Add "label" (2–4 words, native language) when the \
        default wording would be vague. An id is copied EXACTLY as printed after "id" in the \
        data or a lookup (a long code like 8d1c…); never write a name in its place.
        """
}

// MARK: - Buttons

/// One button under a tutor reply. Decoded leniently: an unknown type or an
/// id that isn't on the phone is dropped, never shown as a dead button.
struct TutorAction: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case talk, lesson, book, goal, goalReading, goalAnswer, word, expression,
             review, shadow, sayItAgain, listen, speech, test, quiz, routine, settings, purposes
    }
    var type: Kind
    var topic: String? = nil
    var id: String? = nil
    var text: String? = nil
    var label: String? = nil

    private enum CodingKeys: String, CodingKey { case type, topic, id, text, label }

    init(type: Kind, topic: String? = nil, id: String? = nil, text: String? = nil, label: String? = nil) {
        self.type = type; self.topic = topic; self.id = id; self.text = text; self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown \(raw)")
        }
        type = kind
        func str(_ k: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: k))?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        topic = str(.topic); id = str(.id); text = str(.text); label = str(.label)
    }

    var symbol: String {
        switch type {
        case .talk: return "phone.fill"
        case .lesson: return "graduationcap.fill"
        case .book: return "book.closed.fill"
        case .goal: return "flag.fill"
        case .goalReading: return "text.book.closed.fill"
        case .goalAnswer: return "music.mic"
        case .word, .expression: return "character.book.closed.fill"
        case .review: return StudyPlan.Kind.review.symbol
        case .shadow: return StudyPlan.Kind.shadow.symbol
        case .sayItAgain: return StudyPlan.Kind.sayItAgain.symbol
        case .listen: return StudyPlan.Kind.listen.symbol
        case .speech: return StudyPlan.Kind.speech.symbol
        case .test: return StudyPlan.Kind.test.symbol
        case .quiz: return "questionmark.circle"
        case .routine: return "calendar"
        case .settings: return "slider.horizontal.3"
        case .purposes: return "target"
        }
    }

    /// The button's words: the model's own short label when it gave one.
    var title: String {
        if let label, label.count <= 28 { return label }
        switch type {
        case .talk: return topic == nil ? explain("Start a talk") : explain("Talk about this")
        case .lesson: return explain("Practise it with the tutor")
        case .book: return explain("Open the book")
        case .goal: return explain("Open the goal")
        case .goalReading: return explain("Today's reading")
        case .goalAnswer: return explain("Model answer")
        case .word: return text ?? explain("Open the word")
        case .expression: return text ?? explain("Open the expression")
        case .review: return TutorCopy.startTitle(.review)
        case .shadow: return TutorCopy.startTitle(.shadow)
        case .sayItAgain: return TutorCopy.startTitle(.sayItAgain)
        case .listen: return TutorCopy.startTitle(.listen)
        case .speech: return TutorCopy.startTitle(.speech)
        case .test: return TutorCopy.startTitle(.test)
        case .quiz: return explain("Quick quiz")
        case .routine: return explain("My routine")
        case .settings: return explain("Call settings")
        case .purposes: return explain("Why are you learning?")
        }
    }

    /// Kept only if what it points at exists on this phone.
    @MainActor
    func isValid(appState: AppState) -> Bool {
        switch type {
        case .talk: return true
        case .lesson: return topic != nil
        case .book:
            guard let id = id.flatMap(UUID.init(uuidString:)) else { return false }
            return SessionStore.shared.load().contains { $0.id == id }
                || appState.scenarios.contains { $0.id == id }
        case .goal, .goalReading, .goalAnswer:
            guard let id = id.flatMap(UUID.init(uuidString:)) else { return false }
            return UpcomingGoalStore.shared.goals.contains { $0.id == id }
        // A card the notebook doesn't have opens an empty page.
        case .word:
            guard let text else { return false }
            let key = VocabStore.lookupKey(for: text)
            return VocabStore.shared.isStudying(key) || VocabStore.shared.records[key] != nil
        case .expression:
            guard let text else { return false }
            let v = VocabStore.shared
            return v.isStudyingExpression(text) || v.isKnownExpression(text) || v.hasUsedExpression(text)
        default: return true
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Lookups

/// What the tutor can read, each a short plain-text answer from the stores
/// every screen already reads. Ids are printed so a button can point at them.
@MainActor
enum TutorTools {
    struct Call: Codable, Equatable {
        var tool: String
        var args: [String: Arg]? = nil
        /// Args arrive as strings or numbers; both are read as text.
        enum Arg: Codable, Equatable {
            case s(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .s(s) }
                else if let i = try? c.decode(Int.self) { self = .s(String(i)) }
                else if let d = try? c.decode(Double.self) { self = .s(String(d)) }
                else if let b = try? c.decode(Bool.self) { self = .s(String(b)) }
                else { self = .s("") }
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                if case .s(let s) = self { try c.encode(s) }
            }
            var string: String { if case .s(let s) = self { return s }; return "" }
        }
        func arg(_ k: String) -> String? {
            args?[k]?.string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyTool
        }
    }

    static let catalog = """
        talks {"days": 30} — their talks: id, date, title, kind, how much they spoke, corrections
        talk {"id": "<talk id>"} — one talk: the conversation, their corrections (said → better), \
        what was taught
        search {"text": "…"} — every line THEY said containing this text, with talk id and date
        mistakes {} — recurring mistakes with their own lines, and the recent corrections
        notebook {} — words and expressions they are studying, what they marked known and used
        cards {} — review cards waiting now and put off, with the sentences
        progress {} — level, per-talk scores over time, the last weekly report and test
        goals {} — every upcoming goal in full: material, likely questions, prepared days
        routine {} — their weekly plan, day by day, and this week's done/not done
        scenarios {} — their saved scenarios (Watch) and their people, with ids
        """

    /// The "thinking" line shown while a lookup runs.
    static func progressLine(_ call: Call) -> String {
        switch call.tool {
        case "talks": return explain("Looking through your talks…")
        case "talk": return explain("Reading that talk…")
        case "search": return explain("Searching what you've said…")
        case "mistakes": return explain("Going over your mistakes…")
        case "notebook": return explain("Opening your notebook…")
        case "cards": return explain("Checking your cards…")
        case "progress": return explain("Looking at your progress…")
        case "goals": return explain("Reading your goals…")
        case "routine": return explain("Checking your routine…")
        case "scenarios": return explain("Looking at your scenarios…")
        default: return explain("Thinking…")
        }
    }

    static func run(_ call: Call, appState: AppState, now: Date = Date()) -> String {
        let out: String
        switch call.tool {
        case "talks": out = talks(days: Int(call.arg("days") ?? "") ?? 30, now: now)
        case "talk": out = talk(id: call.arg("id"))
        case "search": out = search(call.arg("text"))
        case "mistakes": out = mistakes(appState: appState, now: now)
        case "notebook": out = notebook()
        case "cards": out = cards(now: now)
        case "progress": out = progress(appState: appState)
        case "goals": out = goals(appState: appState, now: now)
        case "routine": out = routine(now: now)
        case "scenarios": out = scenarios(appState: appState)
        default: out = "Unknown tool \"\(call.tool)\"."
        }
        // A lookup is context for one answer; a runaway one would crowd the
        // question out of the window.
        return "[\(call.tool)]\n" + String(out.prefix(6000))
    }

    // MARK: Tools

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static func finishedTalks() -> [Session] {
        SessionStore.shared.load()
            .filter { $0.endedAt != nil && $0.archivedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private static func kind(_ s: Session) -> String {
        if s.tutorLesson != nil { return "tutor lesson" }
        if s.counterpartId != nil { return "call with a person" }
        switch s.origin ?? .free {
        case .free: return "free talk"
        case .news: return "news talk"
        case .scenario: return "scenario talk"
        }
    }

    private static func fixes(_ s: Session) -> [TurnFix] {
        s.turns.filter(\.isEvidence).flatMap { $0.suggestion?.fixes ?? [] }
    }

    static func talks(days: Int, now: Date) -> String {
        let since = now.addingTimeInterval(-Double(max(1, min(days, 365))) * 86_400)
        let list = finishedTalks().filter { $0.startedAt >= since }
        guard !list.isEmpty else { return "No talks in the last \(days) days." }
        return list.prefix(40).map { s in
            let said = s.turns.filter(\.isEvidence)
            let mins = Int(((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 60).rounded())
            return "- id \(s.id.uuidString) · \(day.string(from: s.startedAt)) · \"\(s.displayTitle)\" · "
                + "\(kind(s)) · \(mins) min · they spoke \(said.count)× · \(fixes(s).count) corrections"
        }.joined(separator: "\n")
    }

    static func talk(id: String?) -> String {
        guard let id = id.flatMap(UUID.init(uuidString:)),
              let s = SessionStore.shared.load().first(where: { $0.id == id })
        else { return "No talk with that id. Use talks to find one." }
        var lines = ["Talk \(day.string(from: s.startedAt)): \"\(s.displayTitle)\" (\(kind(s)))"]
        if let sum = s.summary {
            if !sum.overallNote.isEmpty { lines.append("Note written after it: \(sum.overallNote)") }
            if let sc = sum.scorecard {
                lines.append("Scores: vocabulary \(sc.vocabulary.score), grammar \(sc.grammar.score), "
                             + "expressiveness \(sc.expressiveness.score), fluency \(sc.fluency.score)"
                             + (sc.cefrLevel.map { ", read as \($0.uppercased())" } ?? ""))
            }
            if !sum.expressionsOffered.isEmpty {
                lines.append("Expressions the fluent self used for them to learn: " + sum.expressionsOffered.joined(separator: "; "))
            }
            if !sum.expressionsUsed.isEmpty {
                lines.append("Expressions they used well: " + sum.expressionsUsed.joined(separator: "; "))
            }
        }
        lines.append("The conversation (THEM = the learner, FS = fluent self / the other side):")
        var budget = 3500
        for t in s.turns where !t.transcript.isEmpty {
            let who = t.role == .user ? "THEM" : "FS"
            var line = "\(who): \(t.transcript.prefix(300))"
            if t.role == .user, let fx = t.suggestion?.fixes, !fx.isEmpty {
                line += "\n   corrections: " + fx.map { "\"\($0.was)\" → \"\($0.now)\"" }.joined(separator: "; ")
            }
            budget -= line.count
            if budget < 0 { lines.append("… (rest cut)"); break }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func search(_ text: String?) -> String {
        guard let q = text?.lowercased(), q.count >= 2 else { return "Give a text to search for." }
        var hits: [String] = []
        for s in finishedTalks() {
            for t in s.turns where t.role == .user && t.transcript.lowercased().contains(q) {
                hits.append("- \(day.string(from: s.startedAt)) · talk \(s.id.uuidString): \"\(t.transcript.prefix(200))\"")
                if hits.count >= 20 { break }
            }
            if hits.count >= 20 { break }
        }
        return hits.isEmpty ? "They never said \"\(text ?? "")\" in a talk." : hits.joined(separator: "\n")
    }

    static func mistakes(appState: AppState, now: Date) -> String {
        let sessions = finishedTalks()
        var lines: [String] = []
        let candidates = GrammarFocus.candidates(from: appState.learnerProfile, sessions: sessions, now: now)
        if !candidates.isEmpty {
            lines.append("Recurring, with evidence in several talks:")
            for c in candidates.prefix(6) {
                lines.append("- \"\(c.pattern.mistake)\" → \"\(c.pattern.correction)\" (\(c.pattern.context)), in \(c.talks) talks")
            }
        }
        let others = appState.learnerProfile.recurringMistakes
            .filter { m in !candidates.contains { $0.pattern.mistake == m.mistake } }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }.prefix(6)
        if !others.isEmpty {
            lines.append("Seen before:")
            for m in others { lines.append("- \"\(m.mistake)\" → \"\(m.correction)\" (\(m.context))") }
        }
        let recent = sessions.prefix(10).flatMap { s in fixes(s).map { (s, $0) } }.prefix(25)
        if !recent.isEmpty {
            lines.append("Corrections in their last talks (newest first):")
            for (s, f) in recent {
                lines.append("- \(day.string(from: s.startedAt)): \"\(f.was)\" → \"\(f.now)\"" + (f.why.isEmpty ? "" : " (\(f.why))"))
            }
        }
        return lines.isEmpty ? "No mistakes on file yet." : lines.joined(separator: "\n")
    }

    static func notebook() -> String {
        let v = VocabStore.shared
        var lines = ["Words they are studying (\(v.studying.count)): " + v.studying.prefix(60).joined(separator: ", ")]
        lines.append("Expressions they are studying (\(v.studyingExpressions.count)): "
                     + v.studyingExpressions.prefix(40).joined(separator: "; "))
        let known = v.records.filter { $0.value.state == .known }.map(\.key)
        let used = v.records.filter { $0.value.state == .used }.map(\.key)
        lines.append("Words marked known: \(known.count). Words used in a talk (learned for good): \(used.count).")
        if !used.isEmpty { lines.append("Recently used: " + used.prefix(25).joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    static func cards(now: Date) -> String {
        let waiting = DueReviewView.waitingDeck(now: now)
        var lines = ["Waiting now: \(waiting.count)."]
        let sentences = waiting.filter { $0.cardId != nil }.prefix(15)
        if !sentences.isEmpty {
            lines.append("Sentence cards waiting (their corrected lines):")
            for s in sentences { lines.append("- \"\(s.text)\"" + (s.cardSaid.isEmpty ? "" : " (they said \"\(s.cardSaid)\")")) }
        }
        let words = waiting.filter { $0.cardId == nil }.prefix(20).map(\.text)
        if !words.isEmpty { lines.append("Words/expressions waiting: " + words.joined(separator: "; ")) }
        let putOff = DrillStore.putOffCards()
        lines.append("Sentence cards put off for later: \(putOff.count).")
        let all = DrillStore.shared.load()
        lines.append("All sentence cards: \(all.count), retired as known: \(all.filter { $0.box >= 5 }.count).")
        return lines.joined(separator: "\n")
    }

    static func progress(appState: AppState) -> String {
        var lines = ["Level on file: \(appState.proficiency.rawValue.uppercased())."]
        let scored = finishedTalks().filter { $0.summary?.scorecard != nil }.prefix(10)
        if !scored.isEmpty {
            lines.append("Per-talk scores, newest first (vocabulary/grammar/expressiveness/fluency, level read):")
            for s in scored {
                guard let sc = s.summary?.scorecard else { continue }
                lines.append("- \(day.string(from: s.startedAt)): \(sc.vocabulary.score)/\(sc.grammar.score)/"
                             + "\(sc.expressiveness.score)/\(sc.fluency.score)" + (sc.cefrLevel.map { " \($0.uppercased())" } ?? ""))
            }
        }
        if let r = WeeklyReportStore.shared.latest() {
            lines.append("Last level report (\(day.string(from: r.periodEnd))): \(r.cefrLevel?.uppercased() ?? "no level") — \(r.summary.prefix(400))")
        }
        let recap = WeekRecapStore.shared.lastWeek()
        if let coach = recap.coach {
            lines.append("Last week's coach note: \(coach.headline) \(coach.insight)")
            if !coach.plan.isEmpty { lines.append("Its plan: " + coach.plan.joined(separator: " / ")) }
        }
        lines.append("Last week: \(recap.talkSeconds / 60) min talking, \(recap.cardsCleared) cards cleared, \(recap.shadowTakes) shadow takes.")
        if let t = WeeklyTestStore.shared.latest(), t.isFinished {
            let wrong = t.items.filter { item in t.answers.contains { $0.itemId == item.id && !$0.correct } }
            lines.append("Last weekly test: \(t.score)/\(t.total)."
                         + (wrong.isEmpty ? "" : " Missed: " + wrong.prefix(6).map { "\"\($0.answer)\"" }.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    static func goals(appState: AppState, now: Date) -> String {
        let active = UpcomingGoalStore.shared.active(language: appState.targetLanguage, now: now)
        guard !active.isEmpty else { return "No upcoming goals. They can add one with the tutor's Add a goal." }
        var lines: [String] = []
        for g in active {
            lines.append("Goal id \(g.id.uuidString): " + g.promptLine(now: now))
            if !g.materialLines.isEmpty { lines.append(g.materialLines) }
            if let qs = GoalPrep.cachedQuestions(for: g), !qs.isEmpty {
                lines.append("Likely questions: " + qs.map { "\"\($0.text)\"" }.joined(separator: " | "))
            }
            let days = GoalPrep.days(for: g)
            if !days.isEmpty {
                lines.append("Prepared so far (newest first):")
                for d in days.prefix(6) {
                    lines.append("- \(d.day): focus \(d.focus); reading \"\(d.reading.title)\"; model answer"
                                 + (d.speech.question.map { " to \"\($0)\"" } ?? "") + ": \"\(d.speech.body.prefix(500))\"")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func routine(now: Date) -> String {
        let plan = StudyPlanStore.shared.plan
        guard !plan.blocks.isEmpty else { return "No routine set." }
        let names = Calendar.current.weekdaySymbols
        var lines: [String] = []
        for wd in 1...7 {
            let blocks = plan.blocks.filter { $0.weekdays.contains(wd) }
                .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            guard !blocks.isEmpty else { lines.append("\(names[wd - 1]): rest"); continue }
            lines.append("\(names[wd - 1]): " + blocks.map { b in
                (b.isAnytime ? "anytime" : String(format: "%02d:%02d", b.hour, b.minute)) + " \(b.kind.rawValue) \(b.amount)"
            }.joined(separator: ", "))
        }
        let snap = PracticeStats.snapshot(now: now)
        lines.append("Streak: \(snap.streakDays) days.")
        return lines.joined(separator: "\n")
    }

    static func scenarios(appState: AppState) -> String {
        var lines: [String] = []
        let own = appState.scenarios.filter { $0.archivedAt == nil }.prefix(25)
        if !own.isEmpty {
            lines.append("Scenarios (Watch):")
            for s in own { lines.append("- id \(s.id.uuidString): \(s.displayTitle)") }
        }
        let people = appState.counterparts.filter { $0.remoteId == nil }.prefix(20)
        if !people.isEmpty {
            lines.append("Their people: " + people.map { "\($0.name) (\($0.relationship))" }.joined(separator: ", "))
        }
        return lines.isEmpty ? "No scenarios or people yet." : lines.joined(separator: "\n")
    }
}

extension String {
    fileprivate var nilIfEmptyTool: String? { isEmpty ? nil : self }
}
