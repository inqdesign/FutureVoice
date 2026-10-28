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
    enum Kind: String { case rankDrop, newEpisode, firstSpeech, readScript, readNews, listen }
    enum Action: Equatable {
        case listen(episodeId: UUID)
        case readScript(episodeId: UUID)
        case readNews(SuggestedTopic)
        case challenge(UUID)
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
        }
    }
    var tag: String? {
        switch kind {
        case .rankDrop: return explain("Rank")
        case .newEpisode: return explain("New episode")
        case .firstSpeech: return explain("First time")
        case .readScript, .readNews: return explain("Reading")
        case .listen: return explain("Listening")
        }
    }
    var buttonTitle: String {
        switch kind {
        case .rankDrop: return explain("Try again")
        case .newEpisode, .listen: return explain("Listen")
        case .firstSpeech: return explain("Start")
        case .readScript, .readNews: return explain("Read")
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
            if let story = await newsStory(appState: appState, day: day) {
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
        return (Array(picks.prefix(maxPicks)), episodes, balance)
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
        var line = pick([explain("New records pushed you from #\(from) to #\(to)."),
                         explain("You slipped from #\(from) to #\(to) on the board."),
                         explain("Others passed you: #\(from) → #\(to).")], day)
        if let best, let top { line += " " + explain("Your best \(best), the top \(top).") }
        return line
    }
    static func newEpisodeWhy(minutes: Int, day: Int) -> String {
        pick([explain("Out today and not heard yet · \(minutes) min"),
              explain("Fresh episode, still unheard · \(minutes) min"),
              explain("Today's episode is waiting · \(minutes) min")], day)
    }
    static func listenWhy(minutes: Int, day: Int) -> String {
        pick([explain("You've hardly listened this week · \(minutes) min"),
              explain("Give your ears a turn today · \(minutes) min")], day)
    }
    static func firstSpeechWhy(day: Int) -> String {
        pick([explain("You haven't tried a speech yet. Read it out loud once."),
              explain("Something new: one script, out loud. A minute is enough to start.")], day)
    }
    static func readScriptWhy(day: Int) -> String {
        pick([explain("Read the script of the latest episode."),
              explain("The episode's script, to read at your own pace.")], day)
    }
    static func readNewsWhy(category: String?, day: Int) -> String {
        let topic = category.map { explain("From your interest \"\($0)\".") } ?? explain("From the news.")
        return topic + " " + pick([explain("Written at your level when you open it."),
                                   explain("A short article, made for your level.")], day)
    }

    /// The plan's first line, from the first pick.
    static func headline(_ pick: TutorPick?, balance: TutorBalance, day: Int) -> String? {
        guard let pick else { return nil }
        switch pick.kind {
        case .rankDrop:
            return Self.pick([explain("Someone beat your score. Want your place back?"),
                              explain("Your place on a challenge moved. One more take?")], day)
        case .newEpisode:
            return Self.pick([explain("A new episode is out. Start with listening today."),
                              explain("Today's episode is here. Listen first.")], day)
        case .firstSpeech:
            return Self.pick([explain("Something new today: a speech, out loud."),
                              explain("Today, try one speech.")], day)
        case .readScript, .readNews:
            return Self.pick([explain("This week was all speaking. Let's read something today."),
                              explain("No reading yet this week. Pick one to read.")], day)
        case .listen:
            return Self.pick([explain("Your ears need a turn. Listen to one episode today."),
                              explain("Not much listening this week. One episode today.")], day)
        }
    }
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
        return SpeechScript(id: UUID(), title: article.title, genre: .news, topic: story.category ?? "",
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
