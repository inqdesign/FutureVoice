import CryptoKit
import Foundation
import Supabase

/// What the tutor picks for today beyond the routine (2026-10-28, founder:
/// "not just the routine: a new episode you haven't heard, a speech if you
/// never tried one, a challenge where you were pushed down, and speaking,
/// listening and reading in turn"). Every line is a fixed sentence in code,
/// in a few wordings that take turns by day, so the plan reads alive
/// without a model call.
struct TutorPick: Identifiable, Equatable {
    enum Kind: String { case rankDrop, newEpisode, firstSpeech, readScript, readNews, listen,
                              goalReading, goalSpeech, goalDrill }
    enum Action: Equatable {
        case listen(episodeId: UUID)
        case readScript(episodeId: UUID)
        case readNews(SuggestedTopic)
        case challenge(UUID)
        /// Today's preparation for an upcoming goal (`GoalPrep`).
        case goal(UUID, GoalPrep.Part?)
    }
    var id: String
    var kind: Kind
    var title: String
    var why: String
    var action: Action

    var symbol: String {
        switch kind {
        case .rankDrop: return "trophy.fill"
        case .newEpisode, .listen: return "headphones"
        case .firstSpeech: return "music.mic"
        case .readScript: return "text.book.closed.fill"
        case .readNews: return "newspaper.fill"
        case .goalReading: return "text.book.closed.fill"
        case .goalSpeech: return "music.mic"
        case .goalDrill: return "graduationcap.fill"
        }
    }
    var tag: String? {
        switch kind {
        case .rankDrop: return explain("Rank")
        case .newEpisode: return explain("New episode")
        case .firstSpeech: return explain("First time")
        case .readScript, .readNews: return explain("Reading")
        case .listen: return explain("Listening")
        case .goalReading: return explain("Reading")
        case .goalSpeech: return explain("Model answer")
        case .goalDrill: return explain("Tutor drill")
        }
    }
    var buttonTitle: String {
        switch kind {
        case .rankDrop: return explain("Try again")
        case .newEpisode, .listen: return explain("Listen")
        case .firstSpeech: return explain("Start")
        case .readScript, .readNews, .goalReading: return explain("Read")
        case .goalSpeech: return explain("Open")
        case .goalDrill: return explain("Start")
        }
    }
}

/// Days this week with each kind of practice — the plan's balance line.
struct TutorBalance: Equatable {
    var speaking = 0
    var listening = 0
    var reading = 0
}

enum TutorPicks {
    static let maxPicks = 4
    /// Listening or reading on this many days or fewer this week is "missing".
    static let missingAt = 1

    private enum Key {
        static let heardEpisodes = "futurevoice.podcast.heardEpisodes"
        static let seenRanks = "futurevoice.tutorBot.seenRanks"
        static let firstSpeechShown = "futurevoice.tutorBot.firstSpeechShown"
    }

    // MARK: Heard episodes

    /// Written by the player the first time a line of an episode is heard.
    static func markHeard(_ episodeId: UUID) {
        var set = UserDefaults.standard.stringArray(forKey: Key.heardEpisodes) ?? []
        guard !set.contains(episodeId.uuidString) else { return }
        set.append(episodeId.uuidString)
        UserDefaults.standard.set(Array(set.suffix(200)), forKey: Key.heardEpisodes)
    }
    static func wasHeard(_ episodeId: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Key.heardEpisodes) ?? []).contains(episodeId.uuidString)
    }

    // MARK: Ranks

    /// The challenge was opened from its pick: today's place is now the one seen.
    static func markRankSeen(_ challengeId: UUID, rank: Int) {
        var seen = UserDefaults.standard.dictionary(forKey: Key.seenRanks) as? [String: Int] ?? [:]
        seen[challengeId.uuidString] = rank
        UserDefaults.standard.set(seen, forKey: Key.seenRanks)
    }

    /// Challenges whose place went DOWN since it was last seen. A first
    /// sight, or a place that went up, quietly becomes the new mark.
    @MainActor
    private static func rankDrops() -> [(script: SpeechScript, from: Int, to: Int, best: Int?, top: Int?)] {
        let ch = SpeechChallenges.shared
        var seen = UserDefaults.standard.dictionary(forKey: Key.seenRanks) as? [String: Int] ?? [:]
        var out: [(SpeechScript, Int, Int, Int?, Int?)] = []
        for script in ch.live {
            guard let s = ch.standings[script.id], let rank = s.myRank else { continue }
            let key = script.id.uuidString
            if let was = seen[key], rank > was {
                out.append((script, was, rank, s.myBest, s.topScore))
            } else {
                seen[key] = rank
            }
        }
        UserDefaults.standard.set(seen, forKey: Key.seenRanks)
        return out
    }

    // MARK: Balance

    static func balance(now: Date = Date()) -> TutorBalance {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let events = ActivityEventLog.shared.events(from: start, to: now.addingTimeInterval(1))
        func days(_ kinds: Set<ActivityEventLog.Kind>) -> Set<Date> {
            Set(events.filter { kinds.contains($0.kind) }.map { cal.startOfDay(for: $0.at) })
        }
        var speak = days([.shadow, .sayItAgain, .speech])
        for s in SessionStore.shared.load() where s.startedAt >= start {
            if s.turns.contains(where: { $0.role == .user }) { speak.insert(cal.startOfDay(for: s.startedAt)) }
        }
        return TutorBalance(speaking: speak.count,
                            listening: days([.listen]).count,
                            reading: days([.read]).count)
    }

    // MARK: Picks

    /// Today's picks, most time-bound first. Needs the network for the
    /// podcast feed, the challenge list and the news pool; any of them
    /// missing just leaves its pick out.
    @MainActor
    static func load(appState: AppState, now: Date = Date()) async
        -> (picks: [TutorPick], episodes: [NewsShowEpisode], balance: TutorBalance) {
        let lang = appState.targetLanguage
        async let feed = NewsShow.episodes(language: lang)
        await SpeechChallenges.shared.refresh(language: lang)
        let episodes = await feed
        let balance = balance(now: now)
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        var picks: [TutorPick] = []

        // 0. The nearest upcoming goal leads: today's reading, model answer
        // and a tutor drill, all about it (`GoalPrep`). Nothing is written
        // until one of them is tapped.
        let goal = UpcomingGoalStore.shared.active(language: lang, now: now).first
        if let goal { picks += goalPicks(goal, now: now) }

        // 1. Pushed down on a challenge.
        for drop in rankDrops().prefix(1) {
            picks.append(TutorPick(
                id: "rank-\(drop.script.id)", kind: .rankDrop, title: drop.script.title,
                why: rankWhy(from: drop.from, to: drop.to, best: drop.best, top: drop.top, day: day),
                action: .challenge(drop.script.id)))
        }

        // 2. A new episode not heard yet (out in the last two days).
        let fresh = episodes.first { now.timeIntervalSince($0.date) < 2 * 86_400 && !wasHeard($0.id) }
        if let ep = fresh {
            picks.append(TutorPick(id: "ep-\(ep.id)", kind: .newEpisode, title: ep.title,
                                   why: newEpisodeWhy(minutes: ep.minutes, day: day),
                                   action: .listen(episodeId: ep.id)))
        }

        // 3. Never tried a speech: once, then a week's rest.
        if SpeechStore.shared.takes.isEmpty, let script = SpeechChallenges.shared.live.first,
           showFirstSpeech(now: now) {
            picks.append(TutorPick(id: "speech-first", kind: .firstSpeech, title: script.title,
                                   why: firstSpeechWhy(day: day), action: .challenge(script.id)))
        }

        // 4. Reading missing this week: the learner picks, a script or the news.
        if balance.reading <= missingAt {
            if let ep = episodes.first {
                picks.append(TutorPick(id: "script-\(ep.id)", kind: .readScript, title: ep.title,
                                       why: readScriptWhy(day: day), action: .readScript(episodeId: ep.id)))
            }
            // With a goal ahead, its own reading stands in for the news.
            if goal == nil, let story = await newsStory(appState: appState, day: day) {
                picks.append(TutorPick(id: "news-\(story.title)", kind: .readNews, title: story.title,
                                       why: readNewsWhy(category: story.category, day: day),
                                       action: .readNews(story)))
            }
        }

        // 5. Listening missing and no new episode: the latest one not heard.
        if fresh == nil, balance.listening <= missingAt,
           let ep = episodes.first(where: { !wasHeard($0.id) }) {
            picks.append(TutorPick(id: "listen-\(ep.id)", kind: .listen, title: ep.title,
                                   why: listenWhy(minutes: ep.minutes, day: day),
                                   action: .listen(episodeId: ep.id)))
        }
        return (Array(picks.prefix(maxPicks + (goal == nil ? 0 : 3))), episodes, balance)
    }

    /// The goal's three for today. Before anything is written the titles are
    /// the goal's own; once it is, the day's.
    @MainActor
    static func goalPicks(_ goal: UpcomingGoal, now: Date = Date()) -> [TutorPick] {
        let prep = GoalPrep.today(for: goal, now: now)
        let countdown = goal.countdown(now: now).map { "\($0) · " } ?? ""
        return [
            TutorPick(id: "goal-read-\(goal.id)", kind: .goalReading,
                      title: prep?.reading.title ?? explain("Today's reading"),
                      why: countdown + (prep?.focus ?? explain("Written for this goal when you open it")),
                      action: .goal(goal.id, .reading)),
            TutorPick(id: "goal-speech-\(goal.id)", kind: .goalSpeech,
                      title: prep?.speech.question ?? prep?.speech.title ?? explain("An answer you can say on the day"),
                      why: "",
                      action: .goal(goal.id, .speech)),
            TutorPick(id: "goal-drill-\(goal.id)", kind: .goalDrill,
                      title: prep?.focus ?? goal.title,
                      why: "",
                      action: .goal(goal.id, nil)),
        ]
    }

    private static func showFirstSpeech(now: Date) -> Bool {
        let d = UserDefaults.standard
        let today = StudyPlan.dayKey(now)
        guard let first = d.object(forKey: Key.firstSpeechShown) as? Date else {
            d.set(now, forKey: Key.firstSpeechShown)
            return true
        }
        if StudyPlan.dayKey(first) == today { return true }
        if now.timeIntervalSince(first) >= 7 * 86_400 {
            d.set(now, forKey: Key.firstSpeechShown)
            return true
        }
        return false
    }

    /// One story from the learner's interests, the same pool the Talk tab
    /// shows: the day's cache first, the network only when there is none.
    @MainActor
    private static func newsStory(appState: AppState, day: Int) async -> SuggestedTopic? {
        let interests = appState.persona?.interests ?? []
        guard !interests.isEmpty else { return nil }
        var pool = NewsTopicStore.shared.valid(for: interests) ?? []
        if pool.isEmpty,
           let fetched = try? await NewsTopicEngine.fetch(interests: interests,
                                                          targetLanguage: appState.targetLanguage) {
            pool = fetched.topics
            if !pool.isEmpty { NewsTopicStore.shared.save(pool, interests: interests) }
        }
        if pool.isEmpty { pool = NewsTopicStore.shared.lastKnown(for: interests) ?? [] }
        guard !pool.isEmpty else { return nil }
        return pool[day % pool.count]
    }

    // MARK: Copy — fixed, a few wordings that take turns by day

    private static func pick(_ lines: [String], _ day: Int) -> String { lines[day % lines.count] }

    static func rankWhy(from: Int, to: Int, best: Int?, top: Int?, day: Int) -> String {
        "#\(from) → #\(to)"
    }
    static func newEpisodeWhy(minutes: Int, day: Int) -> String { explain("\(minutes) min") }
    static func listenWhy(minutes: Int, day: Int) -> String { explain("\(minutes) min") }
    static func firstSpeechWhy(day: Int) -> String { "" }
    static func readScriptWhy(day: Int) -> String { "" }
    static func readNewsWhy(category: String?, day: Int) -> String { category ?? "" }
}

/// A news story as an article to read (`news-article`): written once for
/// everyone the first time it is opened, then kept on this phone too.
enum NewsArticle {
    struct Article: Codable { let title: String; let summary: String; let body: String }

    @MainActor
    static func load(_ story: SuggestedTopic, language: String, level: CEFRLevel) async throws -> SpeechScript {
        let band = level.rawValue.lowercased().first.map(String.init) ?? "b"
        let key = "\(language)|\(band)|\(story.title)"
        let file = cacheURL(key)
        let article: Article
        if let file, let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(Article.self, from: data) {
            article = cached
        } else {
            struct Body: Encodable {
                let title: String; let blurb: String; let facts: [String]
                let category: String; let language: String; let level: String
            }
            article = try await SupabaseProvider.shared.functions.invoke(
                "news-article",
                options: FunctionInvokeOptions(
                    headers: try await SupabaseProvider.authorizedHeaders(),
                    body: Body(title: story.title, blurb: story.blurb, facts: story.facts ?? [],
                               category: story.category ?? "", language: language,
                               level: level.rawValue.lowercased())))
            if let file, let data = try? JSONEncoder().encode(article) { try? data.write(to: file) }
        }
        // A stable id per article, so a second "Say it out loud" lands on the
        // script already in My scripts instead of adding another copy.
        let h = Array(SHA256.hash(data: Data(key.utf8)))
        let id = UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7],
                             h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
        return SpeechScript(id: id, title: article.title, genre: .news, topic: story.category ?? "",
                            body: article.body, summary: article.summary, keyTerms: [], sources: [],
                            language: language, targetSeconds: 0, createdAt: Date(), isBuiltIn: false)
    }

    private static func cacheURL(_ key: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NewsArticles", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(name).json")
    }
}
