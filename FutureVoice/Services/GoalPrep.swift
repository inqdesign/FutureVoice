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
