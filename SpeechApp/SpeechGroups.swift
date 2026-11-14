import Foundation
import SwiftUI

/// Friends, or people studying together, racing on the same scripts
/// (2026-11-10, founder). A group is joined by its invite code only. Its
/// boards are loose: every scored take counts, camera or not, best one
/// stands. The public boards keep their own rules (`SpeechChallenges`).
@MainActor
final class SpeechGroups: ObservableObject {
    static let shared = SpeechGroups()

    struct Group: Decodable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let invite_code: String
        let members: Int
        let is_creator: Bool
    }

    /// One of a group's challenges: a public one hung on it, or a member's own
    /// script posted there.
    struct Item: Decodable, Hashable, Identifiable {
        let kind: String
        let id: UUID
        let title: String
        let genre: String
        let body: String
        let summary: String
        let target_seconds: Int
        let added_at: Date
        let added_by: String
        let added_by_me: Bool
        let tried: Int
        let my_best: Int?
        let top_three: [SpeechChallenges.Face]?

        var isPick: Bool { kind == "pick" }
    }

    /// The group's one challenge (2026-11-14, founder): the round running, or
    /// the last one that ended, with its winner. A round's best score takes
    /// that challenge's card when time is up.
    struct Round: Decodable, Hashable, Identifiable {
        let id: UUID
        let kind: String
        let script_id: UUID
        let title: String
        let genre: String
        let body: String
        let summary: String
        let target_seconds: Int
        let set_by: String
        let set_by_me: Bool
        let started_at: Date
        let ends_at: Date
        let ended: Bool
        let winner_name: String?
        let winner_avatar: String?
        let winner_score: Int?
        let winner_is_me: Bool

        var isGroupScript: Bool { kind == "script" }
        var setByName: String { set_by.isEmpty ? explain("Member") : set_by }
        var winnerFace: SpeechChallenges.Face? {
            guard winner_score != nil else { return nil }
            return .init(display_name: winner_name ?? "?", avatar: winner_avatar)
        }
    }

    /// One member in the running round; `score` nil is "not started".
    struct RoundRow: Decodable, Hashable, Identifiable {
        let rank: Int?
        let display_name: String
        let avatar: String?
        let score: Int?
        let attempts: Int
        let is_me: Bool
        var id: String { "\(display_name)-\(is_me)-\(rank ?? 0)-\(avatar?.count ?? 0)" }
        var shownName: String { display_name.isEmpty ? explain("Member") : display_name }
        var face: SpeechChallenges.Face { .init(display_name: shownName, avatar: avatar) }
    }

    /// The group's ranking: how many cards a member holds, and which.
    struct Holder: Decodable, Hashable, Identifiable {
        struct Won: Decodable, Hashable, Identifiable {
            let round_id: UUID
            let script_id: UUID
            let kind: String
            let title: String
            let score: Int?
            var id: UUID { round_id }
        }
        let rank: Int
        let display_name: String
        let avatar: String?
        let cards: Int
        let won: [Won]
        let is_me: Bool
        var id: String { "\(display_name)-\(is_me)-\(rank)-\(avatar?.count ?? 0)" }
        var shownName: String { display_name.isEmpty ? explain("Member") : display_name }
        var face: SpeechChallenges.Face { .init(display_name: shownName, avatar: avatar) }
    }

    @Published private(set) var groups: [Group] = []
    /// The group the Challenges tab is looking at; nil is everyone.
    @Published private(set) var selectedId: UUID?
    @Published private(set) var items: [Item]?
    @Published private(set) var round: Round?
    /// False until the group's round has been read once (nil round is "none set").
    @Published private(set) var roundLoaded = false
    @Published private(set) var roundBoard: [RoundRow]?
    @Published private(set) var holders: [Holder]?

    /// The round still running, if its script is this one.
    func runningRound(for scriptId: UUID) -> Round? {
        guard let round, !round.ended, round.script_id == scriptId else { return nil }
        return round
    }

    var selected: Group? { groups.first { $0.id == selectedId } }

    private static let selectedKey = "speech.group.selected"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        selectedId = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
    }

    func select(_ id: UUID?) {
        guard selectedId != id else { return }
        selectedId = id
        clearSelected()
        UserDefaults.standard.set(id?.uuidString, forKey: Self.selectedKey)
        Task { await refreshSelected() }
    }

    private func clearSelected() {
        items = nil
        round = nil
        roundLoaded = false
        roundBoard = nil
        holders = nil
    }

    /// The group's own scripts, as the prompter and the take pages look them up.
    func script(id: UUID) -> SpeechScript? {
        if let round, round.isGroupScript, round.script_id == id {
            return Self.script(round, language: LanguageScope.active)
        }
        guard let item = items?.first(where: { $0.id == id && !$0.isPick }) else { return nil }
        return Self.script(item, language: LanguageScope.active)
    }

    static func script(_ round: Round, language: String) -> SpeechScript {
        SpeechScript(id: round.script_id, title: round.title,
                     genre: SpeechGenre(rawValue: round.genre) ?? .explainer,
                     topic: "", body: round.body, summary: round.summary,
                     keyTerms: [], sources: [], language: language,
                     targetSeconds: round.target_seconds, createdAt: round.started_at,
                     isBuiltIn: false)
    }

    static func script(_ item: Item, language: String) -> SpeechScript {
        SpeechScript(id: item.id, title: item.title,
                     genre: SpeechGenre(rawValue: item.genre) ?? .explainer,
                     topic: "", body: item.body, summary: item.summary,
                     keyTerms: [], sources: [], language: language,
                     targetSeconds: item.target_seconds, createdAt: item.added_at,
                     isBuiltIn: false)
    }

    // MARK: - Reading

    func refresh(language: String) async {
        #if DEBUG
        if seedDemo() { return }
        #endif
        struct Params: Encodable { let p_language: String }
        guard let rows: [Group] = try? await SupabaseProvider.shared
            .rpc("my_speech_groups", params: Params(p_language: language))
            .execute()
            .value else { return }
        groups = rows
        if let id = selectedId, !rows.contains(where: { $0.id == id }) {
            select(nil)
        } else {
            await refreshSelected()
        }
        await backfillOnce()
    }

    func refreshSelected() async {
        guard let id = selectedId else { return }
        #if DEBUG
        if UserDefaults.standard.string(forKey: "speechGroupDemo") != nil { return }
        #endif
        struct Params: Encodable { let p_group: UUID }
        async let roundRows: [Round]? = try? SupabaseProvider.shared
            .rpc("speech_group_round", params: Params(p_group: id))
            .execute()
            .value
        async let holderRows: [Holder]? = try? SupabaseProvider.shared
            .rpc("speech_group_cards", params: Params(p_group: id))
            .execute()
            .value
        async let itemRows: [Item]? = try? SupabaseProvider.shared
            .rpc("speech_group_challenges", params: Params(p_group: id))
            .execute()
            .value
        let (r, h, i) = await (roundRows, holderRows, itemRows)
        guard selectedId == id else { return }
        if let r {
            round = r.first
            roundLoaded = true
        }
        if let h { holders = h }
        if let i { items = i }
        if let current = round, !current.ended {
            struct BoardParams: Encodable { let p_round: UUID }
            let rows: [RoundRow]? = try? await SupabaseProvider.shared
                .rpc("speech_group_round_board", params: BoardParams(p_round: current.id))
                .execute()
                .value
            guard selectedId == id, round?.id == current.id else { return }
            if let rows { roundBoard = rows }
        } else {
            roundBoard = nil
        }
    }

    // MARK: - Joining

    enum GroupError: LocalizedError {
        case noSuchGroup, full, tooMany, notSubscribed, roundRunning, other
        var errorDescription: String? {
            switch self {
            case .noSuchGroup: return explain("No group has that code. Check it and try again.")
            case .full: return explain("That group is full.")
            case .tooMany: return explain("You're in as many groups as you can be.")
            case .notSubscribed: return explain("Posting your own script comes with a plan.")
            case .roundRunning: return explain("The group already has a challenge running.")
            case .other: return explain("That didn't go through. Try again.")
            }
        }
        static func from(_ error: Error) -> GroupError {
            let text = String(describing: error)
            if text.contains("NO_SUCH_GROUP") { return .noSuchGroup }
            if text.contains("GROUP_FULL") { return .full }
            if text.contains("TOO_MANY_GROUPS") { return .tooMany }
            if text.contains("NOT_SUBSCRIBED") { return .notSubscribed }
            if text.contains("ROUND_RUNNING") { return .roundRunning }
            return .other
        }
    }

    @discardableResult
    func create(name: String, language: String) async throws -> Group {
        struct Params: Encodable { let p_name: String; let p_language: String }
        do {
            let rows: [Group] = try await SupabaseProvider.shared
                .rpc("create_speech_group", params: Params(p_name: name, p_language: language))
                .execute()
                .value
            guard let group = rows.first else { throw GroupError.other }
            groups.append(group)
            select(group.id)
            Analytics.capture("speech_group_created", [:])
            return group
        } catch let error as GroupError { throw error } catch { throw GroupError.from(error) }
    }

    @discardableResult
    func join(code: String) async throws -> Group {
        struct Params: Encodable { let p_code: String }
        do {
            let rows: [Group] = try await SupabaseProvider.shared
                .rpc("join_speech_group", params: Params(p_code: code))
                .execute()
                .value
            guard let group = rows.first else { throw GroupError.other }
            groups.removeAll { $0.id == group.id }
            groups.append(group)
            select(group.id)
            Analytics.capture("speech_group_joined", [:])
            return group
        } catch let error as GroupError { throw error } catch { throw GroupError.from(error) }
    }

    func leave(_ id: UUID) async {
        struct Params: Encodable { let p_group: UUID }
        _ = try? await SupabaseProvider.shared
            .rpc("leave_speech_group", params: Params(p_group: id))
            .execute()
        groups.removeAll { $0.id == id }
        if selectedId == id { select(nil) }
    }

    // MARK: - Group challenges

    /// Sets the group's next challenge for so many days.
    func start(scriptId: UUID, days: Int) async throws {
        guard let group = selectedId else { return }
        struct Params: Encodable { let p_group: UUID; let p_script: UUID; let p_days: Int }
        do {
            try await SupabaseProvider.shared
                .rpc("start_speech_group_round", params: Params(p_group: group, p_script: scriptId, p_days: days))
                .execute()
        } catch { throw GroupError.from(error) }
        Analytics.capture("speech_group_round_started", ["days": days])
        await refreshSelected()
    }

    /// Ends the running round early, with no card.
    func cancelRound() async {
        guard let group = selectedId else { return }
        struct Params: Encodable { let p_group: UUID }
        _ = try? await SupabaseProvider.shared
            .rpc("cancel_speech_group_round", params: Params(p_group: group))
            .execute()
        Analytics.capture("speech_group_round_cancelled", [:])
        await refreshSelected()
    }

    /// Posts one of my scripts to the group and returns its id there.
    func post(_ script: SpeechScript) async throws -> UUID {
        guard let group = selectedId else { throw GroupError.other }
        struct Params: Encodable {
            let p_group: UUID; let p_title: String; let p_genre: String
            let p_body: String; let p_summary: String; let p_target_seconds: Int
        }
        let id: UUID
        do {
            id = try await SupabaseProvider.shared
                .rpc("post_speech_group_script",
                     params: Params(p_group: group, p_title: script.title, p_genre: script.genre.rawValue,
                                    p_body: script.body, p_summary: script.summary,
                                    p_target_seconds: script.targetSeconds))
                .execute()
                .value
        } catch { throw GroupError.from(error) }
        Analytics.capture("speech_group_post", [:])
        return id
    }

    // MARK: - Scores

    /// Every scored take on a challenge or a group script, camera or not.
    func record(score: Int, scriptId: UUID) {
        Task {
            struct Params: Encodable { let p_script: UUID; let p_score: Int }
            _ = try? await SupabaseProvider.shared
                .rpc("submit_speech_friendly_score",
                     params: Params(p_script: scriptId, p_score: max(0, min(100, score))))
                .execute()
            if selectedId != nil { await refreshSelected() }
        }
    }

    /// The best take already on this phone for every public challenge, sent
    /// once per account, so a group joined today sees what was read before.
    private func backfillOnce() async {
        guard let user = try? await SupabaseProvider.shared.auth.session.user.id else { return }
        let key = "speech.group.backfilled.\(user.uuidString)"
        let challengeIds = Set(SpeechChallenges.shared.scripts.map(\.id))
        guard !UserDefaults.standard.bool(forKey: key), !challengeIds.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: key)
        var best: [UUID: Int] = [:]
        for take in SpeechStore.shared.takes where challengeIds.contains(take.scriptId) {
            best[take.scriptId] = max(best[take.scriptId] ?? 0, take.metrics.overall)
        }
        struct Params: Encodable { let p_script: UUID; let p_score: Int }
        for (id, score) in best {
            _ = try? await SupabaseProvider.shared
                .rpc("submit_speech_friendly_score", params: Params(p_script: id, p_score: score))
                .execute()
        }
    }

    #if DEBUG
    /// `-speechGroupDemo running|ended|empty`: a made-up group, for captures
    /// before the server has rounds.
    private func seedDemo() -> Bool {
        guard let mode = UserDefaults.standard.string(forKey: "speechGroupDemo") else { return false }
        let live = SpeechChallenges.shared.live + SpeechChallenges.shared.past
        guard let first = live.first else { return true }
        let group = Group(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D3E0")!,
                          name: "Morning Readers", invite_code: "K7MPQ2", members: 5, is_creator: true)
        groups = [group]
        selectedId = group.id
        let ended = mode == "ended"
        round = mode == "empty" ? nil : Round(
            id: UUID(), kind: "challenge", script_id: first.id, title: first.title, genre: first.genre.rawValue,
            body: "", summary: first.summary, target_seconds: first.targetSeconds,
            set_by: "Mina", set_by_me: false,
            started_at: Date().addingTimeInterval(-5 * 86_400),
            ends_at: ended ? Date().addingTimeInterval(-86_400) : Date().addingTimeInterval(2 * 86_400 + 3_600),
            ended: ended, winner_name: ended ? "Mina" : nil, winner_avatar: nil,
            winner_score: ended ? 91 : nil, winner_is_me: false)
        roundLoaded = true
        roundBoard = ended ? nil : [
            RoundRow(rank: 1, display_name: "Mina", avatar: nil, score: 91, attempts: 5, is_me: false),
            RoundRow(rank: 2, display_name: "Eunggyu", avatar: nil, score: 88, attempts: 3, is_me: true),
            RoundRow(rank: 3, display_name: "Junho", avatar: nil, score: 74, attempts: 1, is_me: false),
            RoundRow(rank: nil, display_name: "Sara", avatar: nil, score: nil, attempts: 0, is_me: false),
            RoundRow(rank: nil, display_name: "Leo", avatar: nil, score: nil, attempts: 0, is_me: false),
        ]
        func won(_ n: Int) -> [Holder.Won] {
            live.prefix(n).map { Holder.Won(round_id: UUID(), script_id: $0.id, kind: "challenge", title: $0.title, score: 90) }
        }
        holders = [
            Holder(rank: 1, display_name: "Junho", avatar: nil, cards: 3, won: won(3), is_me: false),
            Holder(rank: 2, display_name: "Mina", avatar: nil, cards: ended ? 3 : 2, won: won(ended ? 3 : 2), is_me: false),
            Holder(rank: 3, display_name: "Eunggyu", avatar: nil, cards: 1, won: won(1), is_me: true),
            Holder(rank: 4, display_name: "Sara", avatar: nil, cards: 0, won: [], is_me: false),
        ]
        return true
    }
    #endif

    func forget() {
        groups = []
        clearSelected()
        selectedId = nil
        UserDefaults.standard.removeObject(forKey: Self.selectedKey)
    }
}
