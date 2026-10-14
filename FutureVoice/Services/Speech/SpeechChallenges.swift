import Foundation
import UIKit

/// Speech challenges: scripts the founder publishes for every learner of a
/// target language, each with a leaderboard (`20261010150000_speech_challenges`).
/// A challenge IS a `SpeechScript` whose id is the challenge's id, so the
/// prompter, the takes and the result page need nothing new.
///
/// Rules held here: a take is entered only when the camera recorded it, and
/// nothing but a name and a score ever leaves the phone — the video and the
/// voice stay the learner's.
@MainActor
final class SpeechChallenges: ObservableObject {
    static let shared = SpeechChallenges()

    /// One of the top three on a board, as the list row draws them.
    struct Face: Codable, Hashable {
        let display_name: String
        /// Base64 JPEG (~96 px), only when that learner chose to show a photo.
        let avatar: String?

        var image: UIImage? {
            avatar.flatMap { Data(base64Encoded: $0) }.flatMap(UIImage.init(data:))
        }
    }

    /// Where the learner stands on one board.
    struct Standing: Codable, Hashable {
        var entrants: Int
        var topScore: Int?
        var myBest: Int?
        var myRank: Int?
        var myAttempts: Int?
        var topThree: [Face]? = nil
        /// Set once the challenge is retired: the board is frozen, nobody can
        /// enter, and it is listed under past challenges.
        var retiredAt: Date? = nil
    }

    struct BoardRow: Decodable, Hashable, Identifiable {
        let rank: Int
        let display_name: String
        let score: Int
        let is_me: Bool
        /// Base64 JPEG, only when that learner chose to show a photo.
        var avatar: String? = nil
        var id: String { "\(rank)-\(display_name)-\(is_me)" }
        var face: Face { Face(display_name: display_name, avatar: avatar) }
    }

    /// What became of one take, for its result page.
    enum Entry: Equatable {
        case submitting
        case entered(rank: Int, previousRank: Int?, entrants: Int, best: Int, improved: Bool)
        /// The camera was off — the board only takes camera takes.
        case cameraOff
        case failed
    }

    @Published private(set) var scripts: [SpeechScript] = []
    @Published private(set) var standings: [UUID: Standing] = [:]
    /// By take id. In memory: the page that matters is the one the take
    /// opens on; later visits read the standing instead.
    @Published private(set) var entries: [UUID: Entry] = [:]
    /// By take id: the sheet a better take raises once, over its result.
    @Published private(set) var moments: [UUID: SpeechChallengeMoment] = [:]

    func dismissMoment(for takeId: UUID) { moments[takeId] = nil }
    @Published private(set) var loadedLanguage: String?

    private struct Cache: Codable {
        var scripts: [SpeechScript]
        var standings: [UUID: Standing]
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The last list per language, so a take's result page finds its script
    /// offline and the tab draws before the network answers.
    private func cacheURL(_ language: String) -> URL {
        LanguageScope.directory(for: language).appendingPathComponent("speech_challenges.json")
    }

    func script(id: UUID) -> SpeechScript? { scripts.first { $0.id == id } }

    func isPast(_ id: UUID) -> Bool { standings[id]?.retiredAt != nil }
    /// Open challenges, newest first (the server sorts them ahead of past ones).
    var live: [SpeechScript] { scripts.filter { !isPast($0.id) } }
    /// Retired challenges, newest first — boards frozen.
    var past: [SpeechScript] { scripts.filter { isPast($0.id) } }

    func loadCache(language: String) {
        guard loadedLanguage != language else { return }
        loadedLanguage = language
        let cache = (try? Data(contentsOf: cacheURL(language)))
            .flatMap { try? decoder.decode(Cache.self, from: $0) }
        scripts = cache?.scripts ?? []
        standings = cache?.standings ?? [:]
    }

    // MARK: - Reading

    private struct ListRow: Decodable {
        let id: UUID
        let title: String
        let genre: String
        let body: String
        let summary: String
        let key_terms: [SpeechKeyTerm]?
        let sources: [String]?
        let target_seconds: Int
        let published_at: Date
        let retired_at: Date?
        let entrants: Int?
        let top_score: Int?
        let my_best: Int?
        let my_rank: Int?
        let my_attempts: Int?
        let top_three: [Face]?
    }

    func refresh(language: String) async {
        #if DEBUG
        // A capture run draws its samples; the server must not replace them.
        if !previewBoards.isEmpty { return }
        #endif
        loadCache(language: language)
        let rows: [ListRow]
        do {
            rows = try await SupabaseProvider.shared
                .rpc("speech_challenge_list", params: ["p_language": language])
                .execute()
                .value
        } catch {
            return
        }
        guard loadedLanguage == language else { return }
        scripts = rows.map { row in
            SpeechScript(id: row.id, title: row.title,
                         genre: SpeechGenre(rawValue: row.genre) ?? .explainer,
                         topic: "", body: row.body, summary: row.summary,
                         keyTerms: row.key_terms ?? [], sources: row.sources ?? [],
                         language: language, targetSeconds: row.target_seconds,
                         createdAt: row.published_at, isBuiltIn: false,
                         challengeId: row.id)
        }
        defer { Task { await importLocalBests() } }
        standings = Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.id, Standing(entrants: row.entrants ?? 0, topScore: row.top_score,
                              myBest: row.my_best, myRank: row.my_rank,
                              myAttempts: row.my_attempts, topThree: row.top_three,
                              retiredAt: row.retired_at))
        })
        writeCache(language)
    }

    func board(_ challengeId: UUID, limit: Int = 10) async -> [BoardRow]? {
        #if DEBUG
        if let rows = previewBoards[challengeId] { return rows }
        #endif
        struct Params: Encodable { let p_challenge: UUID; let p_limit: Int }
        return try? await SupabaseProvider.shared
            .rpc("speech_challenge_board", params: Params(p_challenge: challengeId, p_limit: limit))
            .execute()
            .value
    }

    // MARK: - Entering a take

    /// Called by the take session once a take on a challenge is scored.
    func enter(take: SpeechTake, script: SpeechScript, recordedOnCamera: Bool) {
        guard let challengeId = script.challengeId else { return }
        guard recordedOnCamera else {
            entries[take.id] = .cameraOff
            return
        }
        guard let name = Self.displayName else {
            entries[take.id] = .failed
            return
        }
        entries[take.id] = .submitting
        Task { await submit(take: take, challengeId: challengeId, name: name) }
    }

    private struct SubmitParams: Encodable {
        let p_challenge: UUID
        let p_display_name: String
        let p_avatar: String?
        let p_overall: Int
        let p_accuracy: Int
        let p_pace: Int
        let p_pause: Int
        let p_filler: Int
        let p_steadiness: Int
        let p_seconds: Int
    }

    private struct SubmitRow: Decodable {
        let rank: Int
        let previous_rank: Int?
        let entrants: Int
        let best: Int
        let improved: Bool
    }

    /// `overall` is the take's own unless the caller re-scored it.
    private func submit(take: SpeechTake, overall: Int? = nil, challengeId: UUID, name: String) async {
        let m = take.metrics
        let overall = overall ?? m.overall
        let params = SubmitParams(p_challenge: challengeId, p_display_name: name,
                                  p_avatar: Self.avatarPayload(),
                                  p_overall: overall, p_accuracy: m.accuracy,
                                  p_pace: m.paceScore, p_pause: m.pauseScore,
                                  p_filler: m.fillerScore, p_steadiness: m.steadiness,
                                  p_seconds: max(1, Int(take.durationSeconds.rounded())))
        do {
            let rows: [SubmitRow] = try await SupabaseProvider.shared
                .rpc("submit_speech_challenge_take", params: params)
                .execute()
                .value
            guard let row = rows.first else { entries[take.id] = .failed; return }
            entries[take.id] = .entered(rank: row.rank, previousRank: row.previous_rank,
                                        entrants: row.entrants, best: row.best, improved: row.improved)
            if row.improved, let board = await board(challengeId, limit: 50) {
                moments[take.id] = SpeechChallengeMoment.make(
                    rank: row.rank, previousRank: row.previous_rank, entrants: row.entrants,
                    best: row.best, improved: row.improved, board: board)
            }
            var standing = standings[challengeId] ?? Standing(entrants: 0)
            standing.entrants = row.entrants
            standing.myBest = row.best
            standing.myRank = row.rank
            standing.myAttempts = (standing.myAttempts ?? 0) + 1
            standing.topScore = max(standing.topScore ?? 0, row.best)
            standings[challengeId] = standing
            if let language = loadedLanguage { writeCache(language) }
            Analytics.capture("speech_challenge_entered", [
                "overall": overall, "rank": row.rank, "entrants": row.entrants,
                "improved": row.improved,
            ])
        } catch {
            entries[take.id] = .failed
            Analytics.capture("speech_challenge_failed", ["error": String(String(describing: error).prefix(160))])
        }
    }

    // MARK: - Takes made before the board existed

    private var importing: Set<UUID> = []

    /// Takes already on this phone count too — the bundled sample was read by
    /// many before it became the first challenge. Once the learner has
    /// confirmed their name (that IS the consent to be on a board), their
    /// best earlier CAMERA take of each challenge goes up if it beats what
    /// the board has. A camera take is one whose video is still kept.
    /// A take of an older text under the same id is never entered: its
    /// transcript is re-scored against today's script and must agree with
    /// the accuracy it was given.
    func importLocalBests() async {
        guard Self.displayName != nil else { return }
        for script in scripts {
            guard let challengeId = script.challengeId, !importing.contains(challengeId),
                  !isPast(challengeId) else { continue }
            let onBoard = standings[challengeId]?.myBest ?? -1
            let candidates = SpeechStore.shared.takes(for: script.id)
                .filter { $0.videoFilename != nil && $0.metrics.overall > onBoard }
                .sorted { $0.metrics.overall > $1.metrics.overall }
            guard !candidates.isEmpty else { continue }
            importing.insert(challengeId)
            defer { importing.remove(challengeId) }
            // Re-scored against today's script with today's weighting: a take
            // stored before 2026-10-14 that stopped early carries the old,
            // higher overall, and only the number sent changes — the take on
            // the phone stays as it was.
            var best: (take: SpeechTake, overall: Int)?
            for take in candidates {
                let body = script.body, transcript = take.transcript, language = script.language
                let diff = await Task.detached {
                    ShadowEngine.analyze(target: body, learner: SpeechAnalyzer.removingFillers(transcript, language: language, keepingThoseIn: body),
                                         language: language)
                }.value
                guard abs(diff.score - take.metrics.accuracy) <= 5 else { continue }
                let m = take.metrics
                let overall = SpeechAnalyzer.overall(accuracy: m.accuracy, pace: m.paceScore, pause: m.pauseScore,
                                                     filler: m.fillerScore, steadiness: m.steadiness,
                                                     coverage: SpeechAnalyzer.coverage(diff.steps))
                if overall > onBoard, overall > (best?.overall ?? -1) { best = (take, overall) }
            }
            if let best {
                await submit(take: best.take, overall: best.overall, challengeId: challengeId,
                             name: Self.displayName ?? "")
                Analytics.capture("speech_challenge_imported", ["overall": best.overall])
            }
        }
    }

    // MARK: - The name on the boards

    private static let nameKey = "speech.challenge.displayName"
    static let maxNameLength = 24

    /// The one name a learner goes by on every board. Nil until they have
    /// seen and confirmed it — nothing is put on a public board unasked.
    static var displayName: String? {
        get {
            let name = UserDefaults.standard.string(forKey: nameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
        set {
            let clean = String((newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maxNameLength))
            UserDefaults.standard.set(clean.isEmpty ? nil : clean, forKey: nameKey)
        }
    }

    // MARK: - The photo on the boards

    private static let showPhotoKey = "speech.challenge.showPhoto"

    /// Whether the learner's profile photo goes beside their name. Asked in
    /// the name sheet, next to the photo itself; on by default only once
    /// they have seen that sheet.
    static var showsPhoto: Bool {
        get { UserDefaults.standard.object(forKey: showPhotoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showPhotoKey) }
    }

    /// The photo as the board stores it: a ~96 px JPEG, base64. Nil when
    /// there is no photo or the learner chose not to show it.
    static func avatarPayload() -> String? {
        guard showsPhoto, let image = AvatarStore.shared.image else { return nil }
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    /// The name sheet was saved: every board shows the new name (and photo
    /// choice) at once, not only after the next take.
    func saveProfile() async {
        guard let name = Self.displayName else { return }
        struct Params: Encodable { let p_display_name: String; let p_avatar: String? }
        _ = try? await SupabaseProvider.shared
            .rpc("set_speech_challenge_profile",
                 params: Params(p_display_name: name, p_avatar: Self.avatarPayload()))
            .execute()
        if let language = loadedLanguage { await refresh(language: language) }
    }

    // MARK: - Publishing (admin accounts)

    private struct PublishParams: Encodable {
        let p_language: String
        let p_title: String
        let p_genre: String
        let p_body: String
        let p_summary: String
        let p_key_terms: [SpeechKeyTerm]
        let p_sources: [String]
        let p_target_seconds: Int
    }

    /// Puts one of the admin's own scripts on every learner's Speech tab.
    func publish(_ script: SpeechScript) async throws {
        let params = PublishParams(p_language: script.language, p_title: script.title,
                                   p_genre: script.genre.rawValue, p_body: script.body,
                                   p_summary: script.summary, p_key_terms: script.keyTerms,
                                   p_sources: script.sources,
                                   p_target_seconds: script.targetSeconds)
        _ = try await SupabaseProvider.shared
            .rpc("publish_speech_challenge", params: params)
            .execute()
        await refresh(language: script.language)
    }

    func retire(_ challengeId: UUID) async throws {
        _ = try await SupabaseProvider.shared
            .rpc("retire_speech_challenge", params: ["p_challenge": challengeId])
            .execute()
        if let language = loadedLanguage { await refresh(language: language) }
    }

    #if DEBUG
    /// Capture runs: a board drawn from samples, no server.
    private var previewBoards: [UUID: [BoardRow]] = [:]

    func seedPreview(language: String, scripts: [SpeechScript], standings: [UUID: Standing],
                     boards: [UUID: [BoardRow]], entries: [UUID: Entry] = [:]) {
        loadedLanguage = language
        self.scripts = scripts
        self.standings = standings
        previewBoards = boards
        self.entries.merge(entries) { $1 }
    }
    #endif

    private func writeCache(_ language: String) {
        guard let data = try? encoder.encode(Cache(scripts: scripts, standings: standings)) else { return }
        try? data.write(to: cacheURL(language), options: .atomic)
    }
}
