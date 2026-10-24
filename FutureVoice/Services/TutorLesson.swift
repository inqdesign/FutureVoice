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
    /// Every talk the lesson ran in.
    var sessionIds: [UUID] = []

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
    var isFinished: Bool { finishedAt != nil || (!challenges.isEmpty && current == nil) }

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
        return all(language: language).first { !$0.isFinished && $0.createdAt >= since }
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
                     level: CEFRLevel, persona: UserPersona?) async -> TutorLesson? {
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

        Otherwise write 3 or 4 CHALLENGES that build to the goal in order, \
        each ONE thing they must be able to say, small enough to nail in a \
        few tries at their level. The last challenge puts it together (the \
        whole introduction in one go, the whole order from greeting to \
        paying, the whole answer). Practical and concrete, the way the \
        situation really goes — not grammar topics, not quizzes.

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
          no brackets, no blanks, no placeholders.
        \(about.isEmpty ? "" : "\nWhat is known about them: \(about). Context only.")
        Return STRICT JSON only:
        {"topic": true, "title": "...", "title_target": "...", \
        "challenges": [{"goal": "...", "task": "...", "example": "..."}]}
        """
        guard let plan: Plan = try? await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: askedWith.map {
                "The tutor asked: \"\($0)\"\nThey answered: \"\(request)\""
            } ?? "They picked on screen: \"\(request)\"")],
            maxTokens: 1500, purpose: "tutor",
            idempotencyKey: "tutor-plan:\(UUID().uuidString)", requestTimeout: 20),
              plan.topic,
              let title = plan.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let items = plan.challenges, !items.isEmpty
        else { return nil }
        let challenges = items.prefix(4).compactMap { i -> TutorLesson.Challenge? in
            let goal = i.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            let task = i.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty, !task.isEmpty else { return nil }
            return .init(id: UUID(), goal: goal, task: task,
                         example: i.example.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard challenges.count >= 2 else { return nil }
        let titleTarget = plan.title_target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TutorLesson(id: UUID(), title: title,
                           titleTarget: titleTarget.isEmpty ? title : titleTarget,
                           language: targetLanguage, challenges: Array(challenges),
                           createdAt: Date())
    }
}

// MARK: - Judge

enum TutorJudge {
    private struct Verdict: Decodable { let done: Bool }

    /// Did `line` do `challenge`? Content only — whether it was said
    /// without mistakes is the correction call's answer, not this one's.
    static func didIt(_ line: String, challenge: TutorLesson.Challenge,
                      targetLanguage: String, askedWith: String) async -> Bool {
        let target = LanguageCatalog.englishName(targetLanguage)
        let system = """
        A \(target) learner is working on one speaking challenge. Decide \
        whether the line they just said DOES it: it says, in \(target), what \
        the challenge asks for — all of it, as a full answer, not a fragment \
        of it or a different thing. Their own words and their own facts are \
        fine; it doesn't have to match the example. Ignore grammar and \
        spelling (someone else checks those) and ignore anything extra they \
        added. It was transcribed from speech.
        Return STRICT JSON only: {"done": true} or {"done": false}
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
        return verdict?.done ?? false
    }
}
