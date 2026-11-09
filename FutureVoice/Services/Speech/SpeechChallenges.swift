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
        /// Every take anyone has put up on this board — what the card counts.
        /// nil from a server that doesn't send it yet.
        var attempts: Int? = nil
        /// What kind of challenge it is ("show_host", "famous_speech", …),
        /// a key the card names in the learner's language. nil on older ones.
        var category: String? = nil
        /// What the challenge is and what to keep in mind, per APP language
        /// ("ko", "en", "zh-Hant", …). It is coaching, so it is read in the
        /// learner's language, then English. nil from older servers.
        var intro: [String: String]? = nil
        /// The original (a video of the speech), opened outside the app.
        var link: URL? = nil
        /// Set once the challenge is retired: the board is frozen, nobody can
        /// enter, and it is listed under past challenges.
        var retiredAt: Date? = nil
        /// Which season it belongs to. nil from a server without seasons, or
        /// a cache written before them.
        var season: Int? = nil
    }

    /// One of a language's seasons, as this account sees them.
    struct SeasonStatus: Decodable, Hashable {
        let season: Int
        let min_scoring: Int
        let is_open: Bool
        let ended: Bool
    }

    static func intro(_ standing: Standing?, native: String) -> String? {
        guard let intro = standing?.intro else { return nil }
        let text = intro[native] ?? intro[String(native.prefix(2))] ?? intro["en"]
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    struct BoardRow: Decodable, Hashable, Identifiable {
        let rank: Int
        let display_name: String
        let score: Int
        let is_me: Bool
        /// Base64 JPEG, only when that learner chose to show a photo.
        var avatar: String? = nil
        /// The colour of their cube (theme index) when seated in the Core of
        /// this challenge's language today; nil otherwise, or from a server
        /// that doesn't send it yet.
        var core_theme: Int? = nil
        /// On the overall board: how many challenges the total is made of.
        /// nil on a challenge's own board.
        var challenges: Int? = nil
        var id: String { "\(rank)-\(display_name)-\(is_me)" }
        var face: Face { Face(display_name: display_name, avatar: avatar) }
    }

    /// What became of one take, for its result page.
    enum Entry: Equatable {
        case submitting
        case entered(rank: Int, previousRank: Int?, entrants: Int, best: Int, improved: Bool)
        /// The camera was off — the board only takes camera takes.
        case cameraOff
        /// Under `boardBar`: kept on the phone, never on the board.
        case belowBar
        case failed
        /// Scored by Season 2's rules (`SpeechScoreV4`), which no board
        /// checks yet: kept on the phone.
        case newScoring
        /// On a challenge that has ended: the board is frozen, so this was
        /// practice.
        case practice
    }

    @Published private(set) var scripts: [SpeechScript] = []
    @Published private(set) var standings: [UUID: Standing] = [:]
    /// The overall board's top of the loaded language (and the learner's own
    /// row), for the Speech tab's banner. nil until it loads.
    @Published private(set) var overall: [BoardRow]?
    /// The season `overall` is the board of. nil: a server without seasons.
    @Published private(set) var overallSeason: Int?
    /// The loaded language's seasons; empty from a server without them.
    @Published private(set) var seasons: [SeasonStatus] = []
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

    func season(of id: UUID) -> Int? { standings[id]?.season }
    /// The newest season taking entries.
    var openSeason: Int? { seasons.filter(\.is_open).map(\.season).max() }
    /// The newest season that has ended.
    var lastEndedSeason: Int? { seasons.filter(\.ended).map(\.season).max() }
    /// Seasons with past challenges, newest first.
    var pastSeasons: [Int] { Array(Set(past.compactMap { season(of: $0.id) })).sorted(by: >) }
    /// Every season that has a board, newest first: open and ended.
    var boardSeasons: [Int] { seasons.filter { $0.is_open || $0.ended }.map(\.season).sorted(by: >) }
    func seasonEnded(_ season: Int) -> Bool { seasons.first { $0.season == season }?.ended == true }

    func loadCache(language: String) {
        guard loadedLanguage != language else { return }
        loadedLanguage = language
        overall = nil
        overallSeason = nil
        seasons = []
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
        let attempts: Int?
        let category: String?
        let intro: [String: String]?
        let link: String?
        var season: Int? = nil
    }

    private func seasonStatus(language: String) async -> [SeasonStatus] {
        struct Params: Encodable { let p_language: String }
        return (try? await SupabaseProvider.shared
            .rpc("speech_season_status", params: Params(p_language: language))
            .execute()
            .value) ?? []
    }

    /// The list that knows seasons, or the old one from a server without it.
    private func listRows(language: String) async throws -> [ListRow] {
        struct Params: Encodable { let p_language: String; let p_scoring: Int }
        let seasoned: [ListRow]? = try? await SupabaseProvider.shared
            .rpc("speech_challenge_list_v2",
                 params: Params(p_language: language, p_scoring: SpeechReading.version))
            .execute()
            .value
        if let seasoned { return seasoned }
        return try await SupabaseProvider.shared
            .rpc("speech_challenge_list", params: ["p_language": language])
            .execute()
            .value
    }

    func refresh(language: String) async {
        #if DEBUG
        // A capture run draws its samples; the server must not replace them.
        if !previewBoards.isEmpty { return }
        #endif
        loadCache(language: language)
        async let status = seasonStatus(language: language)
        let rows: [ListRow]
        do {
            rows = try await listRows(language: language)
        } catch {
            return
        }
        let statuses = await status
        guard loadedLanguage == language else { return }
        seasons = statuses
        if !statuses.isEmpty {
            SpeechReading.setSeasonOpen(statuses.contains { $0.is_open && $0.min_scoring >= SpeechScoreV4.version },
                                        language: language)
        }
        scripts = rows.map { row in
            SpeechScript(id: row.id, title: row.title,
                         genre: SpeechGenre(rawValue: row.genre) ?? .explainer,
                         topic: "", body: row.body, summary: row.summary,
                         keyTerms: row.key_terms ?? [], sources: row.sources ?? [],
                         language: language, targetSeconds: row.target_seconds,
                         createdAt: row.published_at, isBuiltIn: false,
                         challengeId: row.id)
        }
        defer {
            Task {
                #if SPEECH_APP
                await adoptBoardIdentity()
                #endif
                await importLocalBests()
            }
        }
        standings = Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.id, Standing(entrants: row.entrants ?? 0, topScore: row.top_score,
                              myBest: row.my_best, myRank: row.my_rank,
                              myAttempts: row.my_attempts, topThree: row.top_three, attempts: row.attempts,
                              category: row.category, intro: row.intro,
                              link: row.link.flatMap { URL(string: $0) }, retiredAt: row.retired_at,
                              season: row.season))
        })
        writeCache(language)
        let boardSeason = openSeason ?? lastEndedSeason
        if let board = await overallBoard(language: language, season: boardSeason),
           loadedLanguage == language {
            overall = board
            overallSeason = boardSeason
        }
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

    /// Every challenge of a language on one board (2026-11-05, founder):
    /// each learner's best score per challenge, added up, so the way to the
    /// top is to take more of them. Past challenges count. Per season when
    /// the server has seasons (`season` nil: it doesn't).
    func overallBoard(language: String, season: Int? = nil, limit: Int = 10) async -> [BoardRow]? {
        #if DEBUG
        if let rows = previewOverall { return rows }
        #endif
        if let season {
            struct SeasonParams: Encodable { let p_language: String; let p_season: Int; let p_limit: Int }
            return try? await SupabaseProvider.shared
                .rpc("speech_overall_board_v2",
                     params: SeasonParams(p_language: language, p_season: season, p_limit: limit))
                .execute()
                .value
        }
        struct Params: Encodable { let p_language: String; let p_limit: Int }
        return try? await SupabaseProvider.shared
            .rpc("speech_overall_board", params: Params(p_language: language, p_limit: limit))
            .execute()
            .value
    }

    /// Below this many people the overall board is not drawn: a board of
    /// two reads as empty, not as a race.
    static let overallMinEntrants = 5

    // MARK: - Entering a take

    /// Called by the take session once a take on a challenge is scored.
    func enter(take: SpeechTake, script: SpeechScript, recordedOnCamera: Bool) {
        guard let challengeId = script.challengeId else { return }
        // An ended challenge can still be practised; its board is frozen.
        guard !isPast(challengeId) else {
            entries[take.id] = .practice
            return
        }
        let seasonTwo = (season(of: challengeId) ?? 1) >= 2
        let scoredByReading = (take.metrics.scoring ?? 0) >= SpeechScoreV4.version
        guard seasonTwo || !scoredByReading else {
            entries[take.id] = .newScoring
            return
        }
        // A Season 2 board only takes a reading score: no reference reading
        // (offline) means no entry.
        guard !seasonTwo || (scoredByReading && take.metrics.reading != nil) else {
            entries[take.id] = .failed
            return
        }
        guard recordedOnCamera else {
            entries[take.id] = .cameraOff
            return
        }
        guard take.metrics.overall >= Self.boardBar(season: season(of: challengeId)) else {
            entries[take.id] = .belowBar
            return
        }
        guard let name = Self.displayName else {
            entries[take.id] = .failed
            return
        }
        entries[take.id] = .submitting
        Task {
            if seasonTwo {
                await submitReading(take: take, challengeId: challengeId, name: name)
            } else {
                await submit(take: take, challengeId: challengeId, name: name)
            }
        }
    }

    /// The lowest score that goes on a board (2026-10-25, founder: a take
    /// made by accident went straight up). High enough that nobody's name
    /// stands beside a score they'd be embarrassed by, low enough that the
    /// board still fills.
    static let boardBar = 80
    /// The same readers as the 60 the founder set on the curved scale
    /// (2026-11-09): 83 on the plain one, where learners average 81.
    static let seasonTwoBoardBar = 83
    static func boardBar(season: Int?) -> Int { (season ?? 1) >= 2 ? seasonTwoBoardBar : boardBar }

    /// Off this board: the score is deleted on the server. The next take
    /// goes on it again like any other; only filing an EARLIER take is
    /// stopped (`importLocalBests`), or the score would be back at the next
    /// refresh.
    func withdraw(_ challengeId: UUID) async throws {
        struct Params: Encodable { let p_challenge: UUID }
        try await SupabaseProvider.shared
            .rpc("withdraw_speech_challenge_entry", params: Params(p_challenge: challengeId))
            .execute()
        var standing = standings[challengeId] ?? Standing(entrants: 0)
        if standing.myBest != nil { standing.entrants = max(0, standing.entrants - 1) }
        standing.myBest = nil
        standing.myRank = nil
        standing.myAttempts = nil
        standings[challengeId] = standing
        var removed = UserDefaults.standard.stringArray(forKey: Self.removedKey) ?? []
        if !removed.contains(challengeId.uuidString) { removed.append(challengeId.uuidString) }
        UserDefaults.standard.set(removed, forKey: Self.removedKey)
        if let language = loadedLanguage { writeCache(language) }
        Analytics.capture("speech_challenge_withdrawn", [:])
    }

    private static let removedKey = "speech.challenge.removedFromBoard"

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
        /// nil = not assessed; sent as null, never left out, so the call
        /// always names the eleven-argument function.
        let p_pronunciation: Int?
        let p_seconds: Int

        enum CodingKeys: String, CodingKey {
            case p_challenge, p_display_name, p_avatar, p_overall, p_accuracy, p_pace,
                 p_pause, p_filler, p_steadiness, p_pronunciation, p_seconds
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_challenge, forKey: .p_challenge)
            try c.encode(p_display_name, forKey: .p_display_name)
            try c.encode(p_avatar, forKey: .p_avatar)
            try c.encode(p_overall, forKey: .p_overall)
            try c.encode(p_accuracy, forKey: .p_accuracy)
            try c.encode(p_pace, forKey: .p_pace)
            try c.encode(p_pause, forKey: .p_pause)
            try c.encode(p_filler, forKey: .p_filler)
            try c.encode(p_steadiness, forKey: .p_steadiness)
            try c.encode(p_pronunciation, forKey: .p_pronunciation)
            try c.encode(p_seconds, forKey: .p_seconds)
        }
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
                                  p_pronunciation: m.pronunciation,
                                  p_seconds: max(1, Int(take.durationSeconds.rounded())))
        do {
            let rows: [SubmitRow] = try await SupabaseProvider.shared
                .rpc("submit_speech_challenge_take", params: params)
                .execute()
                .value
            await apply(rows, take: take, challengeId: challengeId, overall: overall)
        } catch {
            entries[take.id] = .failed
            Analytics.capture("speech_challenge_failed", ["error": String(String(describing: error).prefix(160))])
        }
    }

    /// Season 2: the server rechecks the total from these parts.
    private func submitReading(take: SpeechTake, challengeId: UUID, name: String) async {
        guard let r = take.metrics.reading else { entries[take.id] = .failed; return }
        struct Params: Encodable {
            let p_challenge: UUID
            let p_display_name: String
            let p_avatar: String?
            let p_overall: Int
            let p_speed: Int
            let p_rhythm: Int
            let p_pauses: Int
            let p_accuracy: Int
            let p_pronunciation: Int
            let p_coverage: Double
            let p_seconds: Int
            let p_scoring: Int
        }
        let params = Params(p_challenge: challengeId, p_display_name: name, p_avatar: Self.avatarPayload(),
                            p_overall: r.total, p_speed: r.parts.speed, p_rhythm: r.parts.rhythm,
                            p_pauses: r.parts.pauses, p_accuracy: r.parts.accuracy,
                            p_pronunciation: r.parts.pronunciation, p_coverage: r.coverage,
                            p_seconds: max(1, Int(take.durationSeconds.rounded())),
                            p_scoring: take.metrics.scoring ?? SpeechReading.version)
        do {
            let rows: [SubmitRow] = try await SupabaseProvider.shared
                .rpc("submit_speech_reading_take", params: params)
                .execute()
                .value
            await apply(rows, take: take, challengeId: challengeId, overall: r.total)
        } catch {
            entries[take.id] = .failed
            Analytics.capture("speech_challenge_failed", ["error": String(String(describing: error).prefix(160))])
        }
    }

    private func apply(_ rows: [SubmitRow], take: SpeechTake, challengeId: UUID, overall: Int) async {
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
            standing.attempts = standing.attempts.map { $0 + 1 }
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
    }

    // MARK: - Takes made before the board existed

    private var importing: Set<UUID> = []

    /// Takes already on this phone count too — the bundled sample was read by
    /// many before it became the first challenge. Once the learner has
    /// confirmed their name (that IS the consent to be on a board), their
    /// best earlier CAMERA take of each challenge goes up if it beats what
    /// the board has. A camera take is one whose video is still kept.
    /// Only at `boardBar` or above, like a new take.
    /// A take of an older text under the same id is never entered: its
    /// transcript is re-scored against today's script and must agree with
    /// the accuracy it was given.
    func importLocalBests() async {
        guard Self.displayName != nil else { return }
        for script in scripts {
            // Season 1 takes never go on a Season 2 board.
            guard let challengeId = script.challengeId, !importing.contains(challengeId),
                  !isPast(challengeId), (season(of: challengeId) ?? 1) < 2,
                  !(UserDefaults.standard.stringArray(forKey: Self.removedKey) ?? []).contains(challengeId.uuidString)
            else { continue }
            let onBoard = standings[challengeId]?.myBest ?? -1
            let candidates = SpeechStore.shared.takes(for: script.id)
                .filter { $0.videoFilename != nil && $0.metrics.overall > onBoard
                    && ($0.metrics.scoring ?? 1) >= SpeechAnalyzer.scoringWithoutPronunciation
                    && ($0.metrics.scoring ?? 1) < SpeechScoreV4.version }
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
                guard abs(SpeechAnalyzer.accuracy(diff) - take.metrics.accuracy) <= 5 else { continue }
                let m = take.metrics
                let overall = SpeechAnalyzer.overall(accuracy: m.accuracy, pace: m.paceScore, pause: m.pauseScore,
                                                     filler: m.fillerScore, steadiness: m.steadiness,
                                                     coverage: SpeechAnalyzer.coverage(diff.steps),
                                                     pronunciation: m.pronunciation)
                if overall >= Self.boardBar, overall > onBoard, overall > (best?.overall ?? -1) { best = (take, overall) }
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
        #if SPEECH_APP
        if AvatarStore.shared.image == nil {
            return showsPhoto ? UserDefaults.standard.string(forKey: adoptedAvatarKey) : nil
        }
        #endif
        guard showsPhoto, let image = AvatarStore.shared.image else { return nil }
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    #if SPEECH_APP
    private static let adoptedAvatarKey = "speech.challenge.adoptedAvatar"

    /// A learner who is already on a board (from nawana, usually) keeps the
    /// name and face they have there. Both are per install, and the profile
    /// is rewritten by every take: without this the speech app asks for a
    /// name again and its first take clears the photo on every board.
    private func adoptBoardIdentity() async {
        guard Self.displayName == nil,
              let entered = standings.first(where: { $0.value.myBest != nil })?.key,
              let rows = await board(entered),
              let me = rows.first(where: { $0.is_me }) else { return }
        Self.displayName = me.display_name
        UserDefaults.standard.set(me.avatar, forKey: Self.adoptedAvatarKey)
    }

    /// Signed out: the next account on this phone is someone else.
    static func forgetIdentity() {
        displayName = nil
        UserDefaults.standard.removeObject(forKey: adoptedAvatarKey)
    }
    #endif

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
    private var previewOverall: [BoardRow]?

    func seedPreview(language: String, scripts: [SpeechScript], standings: [UUID: Standing],
                     boards: [UUID: [BoardRow]], entries: [UUID: Entry] = [:],
                     overall: [BoardRow]? = nil, seasons: [SeasonStatus] = []) {
        loadedLanguage = language
        self.seasons = seasons
        overallSeason = seasons.isEmpty ? nil : (seasons.filter(\.is_open).map(\.season).max())
        previewOverall = overall
        self.overall = overall
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
