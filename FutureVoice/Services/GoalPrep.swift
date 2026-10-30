import CryptoKit
import Foundation

/// A day of preparation for an upcoming goal (2026-10-30, founder: "if I'm
/// applying to Lufthansa cabin crew, tomorrow's training, reading, analysis
/// and speech should be about THAT"). One call writes the day's reading and
/// the day's model answer together, and only when the learner taps one of
/// them — never ahead of time, never for a day they don't open the app
/// (founder: "don't make it if they don't even log in"). The tutor drill
/// needs no writing here: the tutor call plans its own lesson from the goal.
///
/// Material (titles, bodies, the question) is in the target language at the
/// learner's level; summaries are notes in the native language. Cached per
/// goal per day in `Documents/goal_prep.json`, device-local like every other
/// generated cache.
struct GoalPrepDay: Codable, Identifiable, Equatable {
    struct Piece: Codable, Equatable {
        var title: String
        var summary: String
        var body: String
        /// The speech's prompt — the question this answer is for.
        var question: String?
    }

    var id: String { "\(goalId.uuidString)|\(day)" }
    var goalId: UUID
    var day: String
    var language: String
    var reading: Piece
    var speech: Piece
    /// The angle of the day in the native language — also the tutor drill's topic.
    var focus: String
    var createdAt = Date()

    func script(_ part: GoalPrep.Part) -> SpeechScript {
        let p = part == .reading ? reading : speech
        let summary = [p.question.map { "\u{201C}\($0)\u{201D}" }, p.summary.isEmpty ? nil : p.summary]
            .compactMap { $0 }.joined(separator: "\n")
        // A stable id per piece, so its study and looked-up words are found again.
        let h = Array(SHA256.hash(data: Data("\(id)|\(part.rawValue)".utf8)))
        let uuid = UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7],
                               h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
        return SpeechScript(id: uuid, title: p.title, genre: part == .reading ? .explainer : .briefing,
                            topic: focus, body: p.body, summary: summary, keyTerms: [], sources: [],
                            language: language, targetSeconds: 0, createdAt: createdAt, isBuiltIn: false)
    }
}

@MainActor
enum GoalPrep {
    enum Part: String { case reading, speech }

    static let filename = "goal_prep.json"
    private static let keep = 60

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    static func all() -> [GoalPrepDay] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? SyncFiles.storeDecoder.decode([GoalPrepDay].self, from: data)) ?? []
    }

    /// Today's set for a goal, if it has been written.
    static func today(for goal: UpcomingGoal, now: Date = Date()) -> GoalPrepDay? {
        let day = StudyPlan.dayKey(now)
        return all().first { $0.goalId == goal.id && $0.day == day && $0.language == goal.language }
    }

    private static func save(_ prep: GoalPrepDay) {
        var list = all().filter { $0.id != prep.id }
        list.append(prep)
        list = Array(list.sorted { $0.createdAt > $1.createdAt }.prefix(keep))
        if let data = try? SyncFiles.storeEncoder.encode(list) { try? data.write(to: url, options: .atomic) }
    }

    /// Today's set, written now if it isn't yet. Throws when the call fails.
    static func load(goal: UpcomingGoal, appState: AppState, now: Date = Date()) async throws -> GoalPrepDay {
        if let done = today(for: goal, now: now) { return done }
        let earlier = all().filter { $0.goalId == goal.id }.sorted { $0.createdAt > $1.createdAt }
        struct Reply: Decodable {
            struct P: Decodable { let title: String; let summary: String?; let body: String; let question: String? }
            let focus: String
            let reading: P
            let speech: P
        }
        let r: Reply = try await GeminiClient.shared.sendJSON(
            system: system(goal: goal, appState: appState, earlier: earlier, now: now),
            messages: [.init(role: .user, content: "Write today's preparation.")],
            model: .flash36, maxTokens: 4096, purpose: "goal-prep",
            idempotencyKey: "goal-prep:\(goal.id.uuidString):\(StudyPlan.dayKey(now))",
            requestTimeout: 60)
        func piece(_ p: Reply.P) -> GoalPrepDay.Piece {
            .init(title: p.title.trimmingCharacters(in: .whitespacesAndNewlines),
                  summary: (p.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                  body: p.body.trimmingCharacters(in: .whitespacesAndNewlines),
                  question: p.question.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                      .flatMap { $0.isEmpty ? nil : $0 })
        }
        let prep = GoalPrepDay(goalId: goal.id, day: StudyPlan.dayKey(now), language: goal.language,
                               reading: piece(r.reading), speech: piece(r.speech),
                               focus: r.focus.trimmingCharacters(in: .whitespacesAndNewlines))
        save(prep)
        Analytics.capture("goal_prep_made", ["kind": goal.kind.rawValue, "day": earlier.count + 1,
                                             "days_left": goal.daysLeft(now: now) ?? -1])
        return prep
    }

    // MARK: Likely questions

    /// What the day itself will most likely ask, with what each one checks.
    /// Written once per goal (again when the goal is edited), when its page
    /// is opened.
    struct Question: Codable, Equatable, Identifiable {
        var id: String { text }
        var text: String
        var looksFor: String
    }
    private struct QuestionSet: Codable {
        var goalId: UUID
        var goalUpdatedAt: Date
        var questions: [Question]
    }
    private static var questionsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("goal_questions.json")
    }
    private static func questionSets() -> [QuestionSet] {
        guard let data = try? Data(contentsOf: questionsURL) else { return [] }
        return (try? SyncFiles.storeDecoder.decode([QuestionSet].self, from: data)) ?? []
    }

    static func cachedQuestions(for goal: UpcomingGoal) -> [Question]? {
        questionSets().first {
            // Whole seconds: the file's ISO dates drop the fraction the
            // goal in memory still has.
            $0.goalId == goal.id && Int($0.goalUpdatedAt.timeIntervalSince1970) == Int(goal.updatedAt.timeIntervalSince1970)
        }?.questions
    }

    static func questions(for goal: UpcomingGoal, appState: AppState) async throws -> [Question] {
        if let cached = cachedQuestions(for: goal) { return cached }
        struct Reply: Decodable {
            /// An object as asked, or now and then a bare string (measured:
            /// one run in two) — kept either way, without its note.
            struct Q: Decodable {
                let question: String
                let looks_for: String
                private enum K: String, CodingKey { case question, looks_for }
                init(from decoder: Decoder) throws {
                    if let text = try? decoder.singleValueContainer().decode(String.self) {
                        question = text; looks_for = ""; return
                    }
                    let c = try decoder.container(keyedBy: K.self)
                    question = try c.decode(String.self, forKey: .question)
                    looks_for = (try? c.decode(String.self, forKey: .looks_for)) ?? ""
                }
            }
            let questions: [Q]
        }
        let target = LanguageCatalog.englishName(goal.language)
        let native = LanguageCatalog.englishName(appState.nativeLanguage)
        let korean = appState.nativeLanguage == "ko" ? " Korean in polite 해요체 (-요), never 합니다체; never 당신." : ""
        let r: Reply = try await GeminiClient.shared.sendJSON(
            system: """
                A \(target) learner (level \(appState.proficiency.rawValue.uppercased())) is preparing for this:
                \(goal.promptLine())
                \(goal.materialLines.isEmpty ? "" : goal.materialLines + "\nLead with what this material says they will be asked or expected to do.")

                List the 6 to 8 questions or tasks they will most likely meet on the day, most likely \
                first — what an interviewer, examiner or the people there really ask or expect, for this \
                kind of goal and, where it is widely known, this organisation or exam. No invented \
                specifics (no figures, no names of people, no dates).
                - "question": as it would be said to them, in \(target).
                - "looks_for": ALWAYS present, in \(native), one short sentence on what it checks and what a strong \
                answer does.\(korean)

                Return JSON: {"questions": [{"question": "...", "looks_for": "..."}]}
                """,
            messages: [.init(role: .user, content: "List the likely questions.")],
            model: .flash36, maxTokens: 2048, purpose: "goal-prep",
            idempotencyKey: "goal-questions:\(goal.id.uuidString):\(Int(goal.updatedAt.timeIntervalSince1970))",
            requestTimeout: 45)
        let list = r.questions.map {
            Question(text: $0.question.trimmingCharacters(in: .whitespacesAndNewlines),
                     looksFor: $0.looks_for.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.text.isEmpty }
        var sets = questionSets().filter { $0.goalId != goal.id }
        sets.append(QuestionSet(goalId: goal.id, goalUpdatedAt: goal.updatedAt, questions: list))
        if let data = try? SyncFiles.storeEncoder.encode(Array(sets.suffix(20))) {
            try? data.write(to: questionsURL, options: .atomic)
        }
        return list
    }

    #if DEBUG
    /// Captures run signed out: a goal's page with its questions and one day
    /// already written.
    static func seedForCapture(_ goal: UpcomingGoal) {
        let qs = [
            Question(text: "Tell us about yourself and why you want to fly with Lufthansa.",
                     looksFor: "자기소개와 지원 동기가 하나로 이어지는지 봐요. 내 경험을 승무원 일과 연결하면 좋아요."),
            Question(text: "Describe a time you dealt with an unhappy customer.",
                     looksFor: "침착함과 공감을 봐요. 상황, 한 일, 결과 순서로 짧게 말해요."),
            Question(text: "How would you handle a passenger who won't fasten their seatbelt?",
                     looksFor: "안전 규칙을 지키면서도 정중하게 설득하는지 확인해요."),
        ]
        if let data = try? SyncFiles.storeEncoder.encode([QuestionSet(goalId: goal.id, goalUpdatedAt: goal.updatedAt, questions: qs)]) {
            try? data.write(to: questionsURL, options: .atomic)
        }
        guard today(for: goal) == nil else { return }
        save(GoalPrepDay(goalId: goal.id, day: StudyPlan.dayKey(Date()), language: goal.language,
                         reading: .init(title: "The First Impression at Lufthansa",
                                        summary: "루프트한자 면접에서 첫인상이 왜 중요한지 다뤄요.",
                                        body: "When you attend your cabin crew interview at Lufthansa in Frankfurt, the recruiter wants to see your passion for hospitality."),
                         speech: .init(title: "My Introduction and Motivation",
                                       summary: "밝은 목소리로, 천천히 말해 보세요.",
                                       body: "Hello! I live in Munich, where I run my own business.",
                                       question: "Could you introduce yourself and tell us why you want to join Lufthansa?"),
                         focus: "자기소개와 지원 동기"))
    }
    #endif

    /// Every day written for a goal, newest first.
    static func days(for goal: UpcomingGoal) -> [GoalPrepDay] {
        all().filter { $0.goalId == goal.id }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Prompt

    /// Where the preparation is: early days build knowledge and words, the
    /// last days rehearse the real thing.
    static func phase(_ goal: UpcomingGoal, now: Date) -> String {
        guard let left = goal.daysLeft(now: now) else {
            return "No date is set: build knowledge and answers steadily, one new angle per day."
        }
        switch left {
        case 0: return "It is TODAY. Keep it short and calming: the one answer they will surely need, and the key words to have ready."
        case 1...3: return "It is \(left) day(s) away: rehearsal. The most likely questions or tasks, said as they will be said on the day."
        case 4...14: return "It is \(left) days away: build the answers. One likely question or task per day, with what makes a strong answer."
        default: return "It is \(left) days away: build the ground first — what they will be expected to know, and the words for it."
        }
    }

    private static func system(goal: UpcomingGoal, appState: AppState, earlier: [GoalPrepDay], now: Date) -> String {
        let target = LanguageCatalog.englishName(goal.language)
        let native = LanguageCatalog.englishName(appState.nativeLanguage)
        let level = appState.proficiency.rawValue.uppercased()
        let words: String
        switch appState.proficiency {
        case .a1: words = "the reading 80–110 words, the answer 40–60 words; short simple sentences, everyday words"
        case .a2: words = "the reading 110–150 words, the answer 60–80 words; simple sentences joined with and/but/because"
        case .b1: words = "the reading 170–230 words, the answer 90–120 words"
        case .b2: words = "the reading 220–300 words, the answer 110–150 words"
        default: words = "the reading 260–340 words, the answer 130–170 words"
        }
        var about: [String] = []
        if let p = appState.persona {
            if !p.occupation.isEmpty { about.append("Work: \(p.occupation)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { about.append("Lives in \(place)") }
            if !p.interests.isEmpty { about.append("Interests: \(p.interests.joined(separator: ", "))") }
            for n in p.currentNotes(at: now).suffix(8) { about.append(n.text) }
        }
        let done = earlier.prefix(10).map { "- \($0.day): \($0.focus) (reading \"\($0.reading.title)\", answer \"\($0.speech.title)\")" }
        let korean = appState.nativeLanguage == "ko" ? " Korean notes end every sentence in polite 해요체 (-요: \"설명해요\", \"전달해 보세요\"), never 합니다체; never 당신." : ""
        return """
            You prepare a \(target) learner (level \(level)) for something real coming up. Every day \
            they get ONE short reading and ONE model answer to say out loud, both about this goal \
            and nothing else.

            THE GOAL
            \(goal.promptLine(now: now))
            \(phase(goal, now: now))
            \(goal.materialLines.isEmpty ? "" : goal.materialLines + "\nBuild today's reading and answer on this material first: it is the real posting / CV / page.")

            WHAT YOU KNOW ABOUT THE LEARNER (their own words; use only this about them)
            \(about.isEmpty ? "Nothing yet." : about.joined(separator: "\n"))

            ALREADY DONE ON EARLIER DAYS (pick a NEW angle today; never repeat one)
            \(done.isEmpty ? "Nothing yet — this is day 1." : done.joined(separator: "\n"))

            TODAY
            - "focus": today's angle in \(native), under 40 characters (e.g. for an airline interview: \
            the airline's service culture, "why this company", a difficult passenger, the group exercise; \
            for an exam: its speaking part 2, describing a graph, opinion questions).
            - "reading": something to read that gives them knowledge and words for today's angle — \
            the organisation, the role, the exam's format, the place, what is expected on the day. \
            Title and body in \(target), at \(level). A short "summary" in \(native): what it covers \
            and why it helps for the goal, one sentence.
            - "speech": a model answer in the first person, in \(target), at \(level), that the \
            learner could really say on the day for today's angle. "question" is the question or \
            task it answers, in \(target). "title" in \(target). "summary" in \(native): one tip on \
            how to deliver it.
            - Lengths: \(words).

            FACTS — this is read as true, so be careful
            - Only stable, widely known facts about any organisation, place or exam. No figures that \
            change (prices, fleet sizes, salaries, scores needed), no current office holders, no dates. \
            If you are not sure about the organisation, write about the role or the exam in general.
            - The model answer may only use the learner's own facts above. Never invent their \
            employer, years, degrees or stories; where a personal detail is needed and missing, keep \
            the line general enough to be true for them.

            OUTPUT LANGUAGE: titles, bodies and questions in \(target); focus and summaries in \(native).\(korean)

            Return JSON:
            {"focus": "...", "reading": {"title": "...", "summary": "...", "body": "..."}, \
            "speech": {"question": "...", "title": "...", "summary": "...", "body": "..."}}
            """
    }
}
