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

    struct Leader: Decodable, Hashable, Identifiable {
        let rank: Int
        let display_name: String
        let avatar: String?
        let score: Int
        let challenges: Int
        let is_me: Bool
        var id: String { "\(rank)-\(display_name)-\(is_me)" }

        /// The same shape the public boards draw, so the podium is shared.
        var row: SpeechChallenges.BoardRow {
            SpeechChallenges.BoardRow(rank: rank, display_name: shownName, score: score,
                                      is_me: is_me, avatar: avatar)
        }
        var shownName: String { display_name.isEmpty ? explain("Member") : display_name }
    }

    struct BoardRow: Decodable, Hashable, Identifiable {
        let rank: Int
        let display_name: String
        let avatar: String?
        let score: Int
        let attempts: Int
        let is_me: Bool
        var id: String { "\(rank)-\(display_name)-\(is_me)" }
        var row: SpeechChallenges.BoardRow {
            SpeechChallenges.BoardRow(rank: rank,
                                      display_name: display_name.isEmpty ? explain("Member") : display_name,
                                      score: score, is_me: is_me, avatar: avatar)
        }
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

    @Published private(set) var groups: [Group] = []
    /// The group the Challenges tab is looking at; nil is everyone.
    @Published private(set) var selectedId: UUID?
    @Published private(set) var leaders: [Leader]?
    @Published private(set) var items: [Item]?

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
        leaders = nil
        items = nil
        UserDefaults.standard.set(id?.uuidString, forKey: Self.selectedKey)
        Task { await refreshSelected() }
    }

    /// The group's own scripts, as the prompter and the take pages look them up.
    func script(id: UUID) -> SpeechScript? {
        guard let item = items?.first(where: { $0.id == id && !$0.isPick }) else { return nil }
        return Self.script(item, language: LanguageScope.active)
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
        struct Params: Encodable { let p_group: UUID }
        async let leaderRows: [Leader]? = try? SupabaseProvider.shared
            .rpc("speech_group_leaders", params: Params(p_group: id))
            .execute()
            .value
        async let itemRows: [Item]? = try? SupabaseProvider.shared
            .rpc("speech_group_challenges", params: Params(p_group: id))
            .execute()
            .value
        let (l, i) = await (leaderRows, itemRows)
        guard selectedId == id else { return }
        if let l { leaders = l }
        if let i { items = i }
    }

    func board(group: UUID, script: UUID) async -> [BoardRow]? {
        struct Params: Encodable { let p_group: UUID; let p_script: UUID }
        return try? await SupabaseProvider.shared
            .rpc("speech_group_board", params: Params(p_group: group, p_script: script))
            .execute()
            .value
    }

    // MARK: - Joining

    enum GroupError: LocalizedError {
        case noSuchGroup, full, tooMany, notSubscribed, other
        var errorDescription: String? {
            switch self {
            case .noSuchGroup: return explain("No group has that code. Check it and try again.")
            case .full: return explain("That group is full.")
            case .tooMany: return explain("You're in as many groups as you can be.")
            case .notSubscribed: return explain("Posting your own script comes with a plan.")
            case .other: return explain("That didn't go through. Try again.")
            }
        }
        static func from(_ error: Error) -> GroupError {
            let text = String(describing: error)
            if text.contains("NO_SUCH_GROUP") { return .noSuchGroup }
            if text.contains("GROUP_FULL") { return .full }
            if text.contains("TOO_MANY_GROUPS") { return .tooMany }
            if text.contains("NOT_SUBSCRIBED") { return .notSubscribed }
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

    func pick(_ challenge: UUID) async throws {
        guard let group = selectedId else { return }
        struct Params: Encodable { let p_group: UUID; let p_challenge: UUID }
        do {
            try await SupabaseProvider.shared
                .rpc("pick_speech_group_challenge", params: Params(p_group: group, p_challenge: challenge))
                .execute()
        } catch { throw GroupError.from(error) }
        Analytics.capture("speech_group_pick", [:])
        await refreshSelected()
    }

    func post(_ script: SpeechScript) async throws {
        guard let group = selectedId else { return }
        struct Params: Encodable {
            let p_group: UUID; let p_title: String; let p_genre: String
            let p_body: String; let p_summary: String; let p_target_seconds: Int
        }
        do {
            try await SupabaseProvider.shared
                .rpc("post_speech_group_script",
                     params: Params(p_group: group, p_title: script.title, p_genre: script.genre.rawValue,
                                    p_body: script.body, p_summary: script.summary,
                                    p_target_seconds: script.targetSeconds))
                .execute()
        } catch { throw GroupError.from(error) }
        Analytics.capture("speech_group_post", [:])
        await refreshSelected()
    }

    func remove(_ item: Item) async {
        guard let group = selectedId else { return }
        struct Params: Encodable { let p_group: UUID; let p_id: UUID }
        _ = try? await SupabaseProvider.shared
            .rpc("remove_speech_group_challenge", params: Params(p_group: group, p_id: item.id))
            .execute()
        await refreshSelected()
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

    func forget() {
        groups = []
        leaders = nil
        items = nil
        selectedId = nil
        UserDefaults.standard.removeObject(forKey: Self.selectedKey)
    }
}
