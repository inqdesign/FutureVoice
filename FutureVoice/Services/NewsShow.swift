import CryptoKit
import Foundation

/// The platform's daily news show (2026-10-19, founder).
///
/// Every day the PLATFORM picks a handful of news stories per target
/// language, the same for everyone, and two hosts talk each one through.
/// Nothing here is per learner: the episodes are made once on the server
/// side (`scripts/news-show-probe.py`, then `news-show-publish.sh`) and read
/// by every install from R2 (`shows/<lang>/latest.json` + one mp3 per line),
/// so listening is free and needs no `BillingGate`.
///
/// An episode is played by the situations player, line by line, so it gets
/// the same karaoke caption, translation and lock screen as a scene. Its
/// files are a CACHE (Caches/NewsShow), and only the newest day is kept.
struct NewsShowEpisode: Identifiable, Hashable {
    let id: UUID
    let title: String
    let hosts: String
    let minutes: Int
    let lines: [PlaylistLine]
}

enum NewsShow {
    /// The bucket's public r2.dev address. English and German only for now
    /// (founder: other languages once there are learners for them).
    static let base = URL(string: "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/shows")!
    static let languages: Set<String> = ["en", "de"]

    private struct Manifest: Codable {
        let date: String
        let hosts: [String]
        let episodes: [Episode]

        struct Episode: Codable {
            let id: String
            let title: String
            let seconds: Int?
            let lines: [Line]
        }
        struct Line: Codable {
            let speaker: String
            let text: String
            let audio: String
        }
    }

    /// Today's episodes for `language`, with every line's audio on the phone.
    /// Offline, the last day fetched; never anything that can't play.
    static func episodes(language: String) async -> [NewsShowEpisode] {
        let lang = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        guard languages.contains(lang), let dir = cacheDirectory(lang) else { return [] }
        let manifestFile = dir.appendingPathComponent("latest.json")

        var manifest: Manifest?
        var request = URLRequest(url: base.appendingPathComponent("\(lang)/latest.json"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let fresh = try? JSONDecoder().decode(Manifest.self, from: data) {
            manifest = fresh
            try? data.write(to: manifestFile, options: .atomic)
        } else if let data = try? Data(contentsOf: manifestFile) {
            manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        }
        guard let manifest else { return [] }

        await download(manifest, lang: lang, into: dir)
        prune(dir, keeping: manifest.date)

        let hosts = manifest.hosts.joined(separator: " · ")
        return manifest.episodes.compactMap { episode in
            let id = stableId(episode.id)
            let lines = episode.lines.map { line in
                PlaylistLine(bookId: id, text: line.text, voiceId: "", speaker: line.speaker,
                             isOther: true, bookTitle: episode.title,
                             localFile: dir.appendingPathComponent(line.audio))
            }.filter(\.hasAudio)
            guard !lines.isEmpty else { return nil }
            return NewsShowEpisode(id: id, title: episode.title, hosts: hosts,
                                   minutes: max(1, Int(((Double(episode.seconds ?? 0)) / 60).rounded())),
                                   lines: lines)
        }
    }

    private static func download(_ manifest: Manifest, lang: String, into dir: URL) async {
        let missing = manifest.episodes.flatMap(\.lines).map(\.audio).filter {
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        await withTaskGroup(of: Void.self) { group in
            for path in missing {
                group.addTask {
                    let target = dir.appendingPathComponent(path)
                    guard let (data, response) = try? await URLSession.shared.data(
                            from: base.appendingPathComponent("\(lang)/\(path)")),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                    try? FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: target, options: .atomic)
                }
            }
        }
    }

    /// Only the newest day stays on the phone.
    private static func prune(_ dir: URL, keeping date: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        where name != date && name != "latest.json" {
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
