import Foundation

/// Tutor mode's lesson (2026-10-24, founder: "not friendly talk — the goal
/// of the call is that they can SAY it, properly, and they keep at it until
/// they nail it").
///
/// A topic ("introducing yourself to someone new") becomes a short
/// CURRICULUM of 3–4 challenges, each one thing the learner must be able to
/// say ("say your name and where you're from"), the last one usually the
/// whole thing in one go. The tutor walks them in order and stays on a
/// challenge until it comes out clean. Three pieces, all here:
///
/// - `TutorPlanner.plan` writes the curriculum from the topic, or from what
///   the learner said when asked what to practice (it answers nil when that
///   names no topic). One call, default model.
/// - `TutorJudge.didIt` decides, after each learner turn, whether the line
///   DID the current challenge. "Clean" is two witnesses, never the tutor's
///   mood: the per-turn correction call found no fixes, AND this judge says
///   the challenge was actually done (a clean line about something else is
///   not a tick). The count and the order are code.
/// - `TutorLessonStore` keeps lessons per target language, so a lesson left
///   halfway is picked up by the next tutor call.
///
/// The tutor itself reads the curriculum from the system prompt
/// (`ConversationEngine.tutorBlock(lesson:)`), which the app resends
/// whenever a challenge is ticked — so the reply model never decides alone
/// that a challenge is done; it moves on when the block says so.
struct TutorLesson: Codable, Identifiable, Equatable {
    let id: UUID
    /// The topic as the learner would name it — native language (chrome).
    var title: String
    /// The same topic in the target language, for the tutor's own lines.
    var titleTarget: String
    var language: String
    var challenges: [Challenge]
    var createdAt: Date
    var finishedAt: Date?
    /// The learner asked for another topic (by voice or the strip's menu):
    /// never offered again as "pick up where we left off".
    var droppedAt: Date? = nil
    /// Every talk the lesson ran in.
    var sessionIds: [UUID] = []
    /// The curriculum topic this lesson is for (`TutorCurriculum`), when it
    /// came from the map. Nil for a topic the learner made up.
    var topicId: String? = nil
    /// The final check, once every challenge is done (founder, 2026-10-28):
    /// the screen goes blank and they say it all in their own words, in one
    /// go. Passing it is what finishes the lesson and ticks the topic.
    var check: FinalCheck? = nil

    struct FinalCheck: Codable, Equatable {
        var startedAt: Date
        /// Whole attempts judged.
        var tries: Int = 0
        /// "Say it once more" was asked for this attempt — only once.
        var onceMoreUsed: Bool = false
        var passedAt: Date?
        /// The answer that passed, and the slips named with it.
        var line: String?
        var slips: [String] = []
    }

    struct Challenge: Codable, Identifiable, Equatable {
        let id: UUID
        /// What to be able to say, short, native language — the checklist row.
        var goal: String
        /// The same, in English, precise enough for the judge and the tutor.
        var task: String
        /// One example of a line that does it, target language, at the
        /// learner's level. The tutor offers it; the learner's own words count.
        var example: String
        var doneAt: Date?
        /// The learner's line that cleared it — what the summary shows.
        var line: String?
    }

    var current: Int? { challenges.firstIndex { $0.doneAt == nil } }
    var doneCount: Int { challenges.filter { $0.doneAt != nil }.count }
    var challengesDone: Bool { !challenges.isEmpty && current == nil }
    /// Finished = the final check passed. Lessons from before the check had
    /// `finishedAt` stamped with their last tick, so they still read done.
    var isFinished: Bool { finishedAt != nil }
    /// Every challenge ticked, the check not passed yet.
    var inFinalCheck: Bool { challengesDone && finishedAt == nil }

    var record: TutorLessonRecord {
        TutorLessonRecord(lessonId: id, title: title,
                          done: challenges.compactMap { c in
                              c.line.map { TutorLessonRecord.Done(goal: c.goal, line: $0) }
                          },
                          total: challenges.count, finished: isFinished)
    }
}

/// What a talk keeps of its lesson (`Session.tutorLesson`): the lines that
/// cleared each challenge. Optional on the session, so old rows decode.
struct TutorLessonRecord: Codable, Equatable {
    var lessonId: UUID
    var title: String
    var done: [Done]
    var total: Int
    var finished: Bool

    struct Done: Codable, Equatable {
        var goal: String
        var line: String
    }
}

// MARK: - Store

/// `Documents/lang/<code>/tutor_lessons.json`. Device-local, like the daily
/// call: the talks a lesson ran in sync; the checklist is this phone's.
enum TutorLessonStore {
    /// An unfinished lesson older than this is not offered again.
    static let resumeDays = 21
    private static let keep = 30

    private static func url(_ language: String) -> URL {
        LanguageScope.directory(for: LanguageCatalog.base(language))
            .appendingPathComponent("tutor_lessons.json")
    }

    static func all(language: String) -> [TutorLesson] {
        guard let data = try? Data(contentsOf: url(language)) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([TutorLesson].self, from: data)) ?? []
    }

    static func save(_ lesson: TutorLesson) {
        var list = all(language: lesson.language).filter { $0.id != lesson.id }
        list.insert(lesson, at: 0)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(Array(list.prefix(keep))) else { return }
        try? data.write(to: url(lesson.language), options: .atomic)
    }

    /// The newest unfinished lesson, if it is recent enough to pick up.
    static func resumable(language: String, now: Date = Date()) -> TutorLesson? {
        let since = now.addingTimeInterval(-Double(resumeDays) * 86_400)
        return all(language: language).first {
            !$0.isFinished && $0.droppedAt == nil && $0.createdAt >= since
        }
    }
}

// MARK: - Planner

enum TutorPlanner {
    private struct Plan: Decodable {
        let topic: Bool
        let title: String?
        let title_target: String?
        let challenges: [Item]?
        struct Item: Decodable {
            let goal: String
            let task: String
            let example: String
        }
    }

    /// A curriculum for `request` — a topic the learner picked, or what they
    /// said when asked what to practice. Nil when it names no topic ("I
    /// don't know") or the call failed; the tutor then asks again.
    /// `askedWith`: the tutor's line the words answered, when they were
    /// SAID — without it a "yes" to a proposed topic names nothing, and a
    /// sentence gets read for its content instead of as an answer (device,
    /// 2026-10-24: "I'd like to practice introducing myself", misheard as
    /// "I don't like to practice on introducing myself", became a lesson on
    /// "saying what you don't like").
    static func plan(request: String, askedWith: String? = nil,
                     targetLanguage: String, nativeLanguage: String,
                     level: CEFRLevel, persona: UserPersona?,
                     miss: ((String) -> Void)? = nil) async -> TutorLesson? {
        let target = LanguageCatalog.englishName(targetLanguage)
        let native = LanguageCatalog.englishName(nativeLanguage)
        let about = [persona?.occupation, persona?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let system = """
        You plan ONE short speaking lesson for a \(target) learner at CEFR \
        \(level.rawValue.uppercased()). The goal of the lesson: by its end \
        they can SAY one practical thing properly, out loud, with no mistakes.

        You get what they want to practice — a topic they picked on \
        screen, or what they SAID when the tutor asked (with the tutor's \
        line). Read their words as an ANSWER: which situation or thing do \
        they want to be able to say? The lesson is about THAT — never about \
        the grammar or the content of their sentence ("I'd like to practice \
        introducing myself" is a lesson on introducing yourself, not on \
        saying what you'd like). If they agree to a topic the tutor \
        proposed ("yes", "sure", "the second one"), it's that topic.
        Return {"topic": false} when it names no topic ("I don't know", \
        "anything", a greeting), when they turn something down, and when \
        it reads like a refusal of the very thing it names ("I don't like \
        to practice introducing myself") — it was transcribed from speech, \
        and "I'd like" is often misheard as "I don't like"; the tutor will \
        check with them.

        \(levelLadder(level))

        Otherwise write 3 or 4 CHALLENGES that build to the goal in order, \
        each ONE part of it they must be able to say, small enough to nail \
        in a few tries at their level. No challenge that puts it all \
        together: after the challenges the app runs a final check where \
        they say the whole thing in one go. Practical and concrete, the way \
        the situation really goes — not grammar topics, not quizzes.

        Fields:
        - "title": the lesson's name, 2–6 words, in \(native).
        - "title_target": the same name in \(target).
        - "goal": what to be able to say, 2–7 words, in \(native) — shown \
          as a checklist row ("이름과 사는 곳 말하기").
        - "task": the same in English, precise enough that someone reading \
          one line the learner said can tell whether they did it.
        - "example": ONE natural line in \(target) that does it, at their \
          level, as they would say it about THEMSELVES — what is known \
          about them, otherwise a simple made-up fact. It is read aloud, so \
          no brackets, no blanks, no placeholders. Spoken, so ALWAYS \
          contracted the way people talk ("I'm", "it's", "I'll", "that's", \
          "don't") — "I will" or "it is" where a speaker would contract is \
          written English, and they'd be practicing it wrong.
        \(about.isEmpty ? "" : "\nWhat is known about them: \(about). Context only.")
        Return STRICT JSON only:
        {"topic": true, "title": "...", "title_target": "...", \
        "challenges": [{"goal": "...", "task": "...", "example": "..."}]}
        """
        let content = askedWith.map {
            "The tutor asked: \"\($0)\"\nThey answered: \"\(request)\""
        } ?? "They picked on screen: \"\(request)\""
        // One retry: now and then the reply is the challenge list alone
        // instead of the object, which decodes to nothing.
        var plan: Plan?
        for _ in 0..<2 where plan == nil {
            plan = try? await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: content)],
                maxTokens: 2000, purpose: "tutor",
                idempotencyKey: "tutor-plan:\(UUID().uuidString)", requestTimeout: 20)
        }
        // `miss` says why there is no lesson: "no_topic" is the ordinary
        // answer to "hi" or "I don't know", the other two are failures.
        guard let plan else { miss?("request_failed"); return nil }
        guard plan.topic else { miss?("no_topic"); return nil }
        guard let title = plan.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let items = plan.challenges, !items.isEmpty
        else { miss?("too_few"); return nil }
        let challenges = items.prefix(4).compactMap { i -> TutorLesson.Challenge? in
            let goal = i.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            let task = i.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty, !task.isEmpty else { return nil }
            return .init(id: UUID(), goal: goal, task: task,
                         example: i.example.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard challenges.count >= 2 else { miss?("too_few"); return nil }
        let titleTarget = plan.title_target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TutorLesson(id: UUID(), title: title,
                           titleTarget: titleTarget.isEmpty ? title : titleTarget,
                           language: targetLanguage, challenges: Array(challenges),
                           createdAt: Date())
    }
}

// MARK: - After a lesson

/// What the learner wants once a lesson is done (2026-10-24, founder:
/// "don't hang up — ask. Keep going and the session goes on; another topic
/// and the book is made in the background while it asks what's next").
enum TutorNext {
    /// `again`: say the passed lesson once more, for practice (the tutor
    /// offers it after a pass with slips).
    enum Choice: String, Decodable { case more, again, new, stop, unclear }
    struct Answer: Decodable {
        let choice: Choice
        /// The next topic, when they named one.
        var topic: String? = nil
    }

    static func read(_ line: String, askedWith: String, lesson: String,
                     targetLanguage: String, suggested: String? = nil) async -> Answer? {
        let offer = suggested.map { """

        The tutor may have suggested a next topic from their curriculum: \
        "\($0)". If they accept THAT one ("yes, let's do that", "that one", \
        "sure, the next one"), the choice is "new" and "topic" is exactly \
        "\($0)".
        """ } ?? ""
        let system = """
        A language learner just finished a short speaking lesson ("\(lesson)") \
        and was asked whether to keep practicing it, move on to another \
        topic, or stop for today. Read their answer (transcribed from speech, \
        any language):
        - "more": they clearly want to keep practicing this same topic \
          ("more", "let's keep going with this", "go deeper"), or said yes \
          when the tutor's line asked ONLY about doing more of it.
        - "again": they want to say it (the whole thing) once more first, \
          or said yes when the tutor's line asked ONLY about trying it once \
          more.
        - "new": another topic. If they named a SPECIFIC one ("ordering at \
          a cafe"), put it in "topic" in their own words; "another topic" / \
          "something else" is not a topic — leave "topic" out.
        - "stop": they're done for today.
        - "unclear": anything else — small talk, a reaction ("nice", "that \
          was fun", "sounds good", "cool"), a question, noise, a "yes" to a \
          line that offered both, or a tutor line that wasn't asking about \
          this at all. When in doubt, "unclear": the tutor will ask them.\(offer)
        Return STRICT JSON only: {"choice": "more|again|new|stop|unclear", "topic": "..."}
        """
        return try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content:
                "The tutor asked: \"\(askedWith)\"\nThey answered: \"\(line)\"")],
            model: .flashLite31, maxTokens: 120, purpose: "tutor",
            idempotencyKey: "tutor-next:\(UUID().uuidString)", requestTimeout: 10,
            fastThinking: true)
    }
}

extension TutorPlanner {
    /// What a lesson asks for at each band (2026-10-24, founder, of a
    /// B1 and a C1 plan for "meeting someone new": "these are all A1–A2").
    /// Told only the band's letter, the planner wrote the same lesson for
    /// everyone — name, job, nice to meet you — a little longer at the top.
    /// The level has to change WHAT is practiced, not the sentence length:
    /// at B a situation means reasons and a follow-up, at C it means
    /// managing the conversation itself.
    static func levelLadder(_ level: CEFRLevel) -> String {
        let band: String
        switch level {
        case .a1:
            band = """
            A1 — single facts in short set sentences. Each challenge is one \
            thing (name, where from, one like), one sentence. Everyday words only.
            """
        case .a2:
            band = """
            A2 — simple sentences joined with and / but / because, about \
            routine and plain needs. A challenge may be two facts in one turn, \
            or one fact with a short reason.
            """
        case .b1:
            band = """
            B1 — connected speech, not facts. Challenges are: give a reason \
            or a short story (how you ended up doing what you do), describe \
            an experience or a plan, and handle what the other person asks \
            next (answer a follow-up, ask one back that fits). Never a \
            challenge that is just a name, a job title or "nice to meet you" \
            — they can already say those.
            """
        case .b2:
            band = """
            B2 — real conversation work. Challenges are: explain or defend a \
            view with reasons, compare options, talk about what you'd do if \
            things were different, disagree politely, adjust how casual or \
            formal you sound to the person, keep a conversation going when \
            it stalls. Basics (name, job, greetings) are assumed, never a \
            challenge.
            """
        case .c1, .c2:
            band = """
            \(level.rawValue.uppercased()) — managing the conversation itself, \
            the way a socially skilled native speaker does. Challenges are: \
            tell something about yourself as a story with a hook rather than \
            a list, ask a follow-up that shows you listened, steer the \
            conversation, soften or hedge (tact, diplomacy), use humor or an \
            idiom naturally, change register mid-way, leave or redirect a \
            conversation gracefully. Examples sound like a fluent native \
            speaker, idiomatic. Basics are assumed and never a challenge.
            """
        }
        let beyond = [.a1, .a2].contains(level) ? "" : """

        An everyday transaction (ordering, buying, booking, asking the way) \
        done plainly is A-level, whatever details are added. At this level \
        the lesson is what goes beyond it or goes wrong: the order comes out \
        wrong and has to be fixed politely, something is sold out and you \
        choose instead, a special need explained (an allergy, a change), a \
        complaint, a bit of real small talk with the person serving you.
        """
        return "WHAT THIS LEVEL PRACTICES — the challenges must fit this, not a level below:\n" + band + beyond
    }
}

// MARK: - Judge

enum TutorJudge {
    struct Verdict: Decodable {
        let done: Bool
        /// They asked to change the topic or stop this lesson (device,
        /// 2026-10-24: "can I change the topic?" was answered "let's finish
        /// this one first", with no way out).
        var other_topic: Bool? = nil
        var wantsOtherTopic: Bool { other_topic == true }
        /// The tutor's last line had already left this challenge — it moves
        /// on by its own judgment (founder, 2026-10-25), and the checklist
        /// follows it.
        var tutor_moved_on: Bool? = nil
        var tutorMovedOn: Bool { tutor_moved_on == true }
    }

    /// Did `line` do `challenge`? Content only — whether it was said
    /// without mistakes is the correction call's answer, not this one's.
    /// Also asked on every try: do they want out of this lesson?
    static func read(_ line: String, challenge: TutorLesson.Challenge,
                     targetLanguage: String, askedWith: String) async -> Verdict? {
        let target = LanguageCatalog.englishName(targetLanguage)
        let system = """
        A \(target) learner is working on one speaking challenge. Decide \
        whether the line they just said DOES it: it says, in \(target), what \
        the challenge asks for — all of it, as a full answer, not a fragment \
        of it or a different thing. Their own words and their own facts are \
        fine; it doesn't have to match the example. Ignore grammar and \
        spelling (someone else checks those) and ignore anything extra they \
        added. It was transcribed from speech.
        Also decide "other_topic": true ONLY when they ask to change the \
        topic, stop or skip this lesson, or practice something else instead \
        (in any language) — not for a mistake, a question about the \
        challenge, or "I don't know".
        Also decide "tutor_moved_on": true ONLY when the tutor's line had \
        already finished this challenge — said they got it AND asked for \
        something different from this challenge. False while the tutor is \
        still on this challenge: asking for it, for it again, or to say it \
        again with more in it ("say that whole thing once more, including \
        …" is still this challenge).
        Return STRICT JSON only: {"done": true|false, "other_topic": true|false, "tutor_moved_on": true|false}
        """
        let content = """
        Challenge: \(challenge.task)
        Example of a line that does it: \(challenge.example)
        The tutor had just said: \(askedWith)
        The learner said: \(line)
        """
        let verdict: Verdict? = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content)],
            model: .flashLite31, maxTokens: 120, purpose: "tutor",
            idempotencyKey: "tutor-judge:\(UUID().uuidString)", requestTimeout: 10,
            fastThinking: true)
        return verdict
    }
}

// MARK: - Final check

/// The lesson's final check (founder, 2026-10-28): every challenge said in
/// one answer, with nothing on screen to lean on. The bar is CONFIDENCE, not
/// perfection — every part said and understood passes, small slips and a
/// little hesitation included — but every slip is named, pass or not, and
/// praise is for a clean answer only. The judge reads content and delivery;
/// the slips are the per-turn correction call's, as for every tick; the
/// outcome is code.
enum TutorFinalCheck {
    enum Outcome: String { case pass, onceMore, notYet, notAnAttempt }

    struct Verdict: Decodable {
        /// They tried to say the whole thing (not one part, a question, a chat).
        let attempt: Bool
        /// 1-based challenge numbers their answer left out.
        var missing: [Int]? = nil
        /// What was missing or unclear, in English, for the tutor.
        var missing_note: String? = nil
        /// A listener would understand what they mean.
        var understood: Bool? = nil
        /// Very shaky: long stalls, restarts, many broken bits.
        var shaky: Bool? = nil
    }

    /// Not perfect the first time → once more, always (founder, 2026-10-28:
    /// "if it wasn't perfect, we at least should ask one more time"). The
    /// second try passes when every part is there and understood; the tutor
    /// then offers one more go or moving on.
    static func outcome(_ v: Verdict, slips: Int, onceMoreUsed: Bool) -> Outcome {
        guard v.attempt else { return .notAnAttempt }
        if v.understood == false || !(v.missing ?? []).isEmpty { return .notYet }
        if (v.shaky == true || slips > 0) && !onceMoreUsed { return .onceMore }
        return .pass
    }

    static func read(_ line: String, lesson: TutorLesson, askedWith: String,
                     targetLanguage: String) async -> Verdict? {
        let target = LanguageCatalog.englishName(targetLanguage)
        let parts = lesson.challenges.enumerated()
            .map { "\($0.offset + 1). \($0.element.task)" }.joined(separator: "\n")
        let system = """
        A \(target) learner finished a short speaking lesson ("\(lesson.titleTarget)") \
        and is now asked to say the whole thing in one go, in their own \
        words, with no help. Judge the line they just said (transcribed from \
        speech). Their own words and facts are fine; it doesn't have to match \
        any example.
        - "attempt": true when they are trying to say the whole thing (or \
          most of it) — false for a question, a request for help, small \
          talk, or practicing just one part the tutor asked for.
        - "missing": the numbers of the parts below that their answer does \
          NOT say at all. A part said simply, or with mistakes, is said.
        - "missing_note": if anything is missing or can't be understood, \
          what, in a few English words ("didn't ask to pay by card").
        - "understood": would a patient native listener understand what they \
          mean? Grammar slips and an accent don't matter here.
        - "shaky": true only if it was VERY halting — long stalls, several \
          restarts, most sentences broken off. A little hesitation is fine.
        Ignore spelling, punctuation and anything the transcriber chose.
        Return STRICT JSON only: {"attempt": true|false, "missing": [n], \
        "missing_note": "...", "understood": true|false, "shaky": true|false}
        """
        let content = """
        The parts of the lesson:
        \(parts)
        The tutor had just said: \(askedWith)
        The learner said: \(line)
        """
        return try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content)],
            maxTokens: 400, purpose: "tutor",
            idempotencyKey: "tutor-check:\(UUID().uuidString)", requestTimeout: 15,
            fastThinking: true)
    }
}
