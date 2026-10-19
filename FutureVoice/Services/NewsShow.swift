import CryptoKit
import Foundation

/// The nawana Podcast (2026-10-19, founder).
///
/// One episode a day, the same for everyone: two hosts talk one news story
/// through, a different category each weekday (Monday tech, Tuesday
/// fashion…). Made once on the platform side (`scripts/news-show-daily.py`)
/// and read by every install from R2 as a FEED — `shows/<lang>/latest.json`,
/// newest first, every episode numbered — plus one mp3 per line. Listening
/// is free and needs no `BillingGate`.
///
/// An episode is played by the situations player, line by line, so it gets
/// the same karaoke caption, translation and lock screen as a scene. Its
/// files are a CACHE (Caches/NewsShow), fetched when the episode is picked,
/// and dropped once the episode leaves the feed.
struct NewsShowEpisode: Identifiable, Hashable {
    let id: UUID
    let title: String
    /// Counted across days by the publisher: EP 1 is the show's first.
    let number: Int
    let date: Date
    let category: String?
    let minutes: Int
    let lines: [PlaylistLine]
    /// The line files, relative to the feed, for `NewsShow.prepare`.
    fileprivate let files: [String]
    fileprivate let language: String

    /// Every line's audio is on the phone.
    var isReady: Bool { lines.allSatisfy(\.hasAudio) }
}

enum NewsShow {
    /// The bucket's public r2.dev address. English only while the show's
    /// reaction is tested (founder, 2026-10-19).
    static let base = URL(string: "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/shows")!
    static let languages: Set<String> = ["en"]

    private struct Feed: Codable {
        /// The first test day's per-day manifest had a top-level date; the
        /// daily feed dates each episode.
        let date: String?
        let episodes: [Episode]

        struct Episode: Codable {
            let id: String
            let number: Int?
            let date: String?
            let category: String?
            let title: String
            let seconds: Int?
            let lines: [Line]
        }
        struct Line: Codable {
            let speaker: String
            let text: String
            let audio: String
            /// Native language → meaning, made by the publisher.
            let translations: [String: String]?
        }
    }

    /// The feed for `language`, newest first. Offline, the last feed fetched.
    /// Nothing is downloaded here; `prepare` fetches an episode when picked.
    static func episodes(language: String) async -> [NewsShowEpisode] {
        let lang = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        guard languages.contains(lang), let dir = cacheDirectory(lang) else { return [] }
        let feedFile = dir.appendingPathComponent("latest.json")

        var feed: Feed?
        let request = URLRequest(url: base.appendingPathComponent("\(lang)/latest.json"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let fresh = try? JSONDecoder().decode(Feed.self, from: data) {
            feed = fresh
            try? data.write(to: feedFile, options: .atomic)
        } else if let data = try? Data(contentsOf: feedFile) {
            feed = try? JSONDecoder().decode(Feed.self, from: data)
        }
        guard let feed else { return [] }

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let episodes = feed.episodes.enumerated().map { index, episode in
            let id = stableId(episode.id)
            let lines = episode.lines.map { line in
                PlaylistLine(bookId: id, text: line.text, voiceId: "", speaker: line.speaker,
                             isOther: true, bookTitle: episode.title,
                             localFile: dir.appendingPathComponent(line.audio),
                             translations: line.translations)
            }
            return NewsShowEpisode(
                id: id, title: episode.title, number: episode.number ?? index + 1,
                date: (episode.date ?? feed.date).flatMap(day.date(from:)) ?? Date(),
                category: episode.category,
                minutes: max(1, Int((Double(episode.seconds ?? 0) / 60).rounded())),
                lines: lines, files: episode.lines.map(\.audio), language: lang)
        }
        prune(dir, keeping: Set(feed.episodes.flatMap(\.lines).compactMap {
            $0.audio.split(separator: "/").first.map(String.init)
        }))
        return episodes
    }

    /// Fetch whatever of `episode` isn't on the phone yet.
    static func prepare(_ episode: NewsShowEpisode) async {
        guard let dir = cacheDirectory(episode.language) else { return }
        let missing = episode.files.filter {
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        await withTaskGroup(of: Void.self) { group in
            for path in missing {
                group.addTask {
                    let target = dir.appendingPathComponent(path)
                    guard let (data, response) = try? await URLSession.shared.data(
                            from: base.appendingPathComponent("\(episode.language)/\(path)")),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                    try? FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: target, options: .atomic)
                }
            }
        }
    }

    /// The glyph for an episode's category — the one the Talk tab's news
    /// cards wear.
    static func icon(for category: String?) -> String {
        DiscoverSection.categoryIcon(category)
    }

    /// Only what the feed still lists stays on the phone.
    private static func prune(_ dir: URL, keeping folders: Set<String>) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        where !folders.contains(name) && name != "latest.json" {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func cacheDirectory(_ lang: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = caches.appendingPathComponent("NewsShow/\(lang)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The same episode is the same UUID on every load, so the player can
    /// tell it is still playing the list the sheet just rebuilt.
    private static func stableId(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
                           bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12],
                           bytes[13], bytes[14], bytes[15]))
    }
}
