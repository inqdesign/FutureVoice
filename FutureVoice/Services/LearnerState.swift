import Foundation

/// One learner's "student file" (docs/personal-report-plan.md, part 2): where
/// they stand on every item of the level map, built from what they actually
/// said. Founder, 2026-10-30: one file every part of the app can read — the
/// tutor chat answers from it, the planner (step 4) will build the week from
/// it. Behind the scenes only: no screen draws it.
///
/// **Stored per TALK, read per ITEM.** What is on disk is each tagged talk's
/// verified verdicts (`SessionTag`), keyed by session id; the per-item counts,
/// dates, quotes and status are computed on read (`items`). That makes
/// tagging idempotent by construction — a talk tagged twice replaces its own
/// entry instead of counting twice — and a talk that grew (resumed, or a line
/// marked misheard) is re-tagged and replaces its old contribution.
struct LearnerState: Codable {
    var version: Int = 1
    /// Tagged talks, keyed by `Session.id.uuidString`.
    var sessions: [String: SessionTag] = [:]
    /// Failed tagging attempts per talk. A talk that fails `maxFailures`
    /// times is not tried again — a decode that always fails would otherwise
    /// be one paid call per launch, forever.
    var failures: [String: Int] = [:]
    /// Which `failuresEpoch` the counts above belong to. Nil on a file from
    /// before the epochs.
    var failuresEpoch: Int?

    static let maxFailures = 2
    /// Bump when a fix makes old failures meaningless. 1 (2026-11-09): talks
    /// given up on because of the 4096 ceiling and the refused retries.
    static let failuresEpoch = 1

    /// The same state with failure counts from an older epoch dropped, so
    /// those talks are tried again.
    func clearingOldFailures() -> LearnerState {
        guard failuresEpoch != Self.failuresEpoch else { return self }
        var copy = self
        copy.failures = [:]
        copy.failuresEpoch = Self.failuresEpoch
        return copy
    }

    struct SessionTag: Codable, Equatable {
        /// When the talk happened (its last line) — the dates on an item.
        var talkDate: Date
        var taggedAt: Date
        /// `LevelTagger.fingerprint` of the learner lines it was tagged from.
        var fingerprint: String
        /// The map version it was tagged against. A new map re-tags.
        var mapVersion: Int
        var items: [ItemTag]
    }

    enum Kind: String, Codable { case grammar, function }

    /// One item's verdict in one talk. Quotes are the learner's own words,
    /// checked in code (`LevelTagger.isTheirs`).
    struct ItemTag: Codable, Equatable {
        var id: String
        var kind: Kind
        var right: Int
        var wrong: Int
        var quotes: [Quote]
    }

    struct Quote: Codable, Equatable {
        var text: String
        /// A right use or the error.
        var right: Bool
        /// Filled from the talk's date when the item is read.
        var date: Date? = nil
    }

    /// Where a learner stands on one item. Decided by `status(…)` from the
    /// counts, never by a model.
    enum Status: String, Codable, Comparable {
        case unseen, tried, shaky, solid

        /// Order of WORK: the closest to done first (shaky, then tried), then
        /// what has never come up; solid is done.
        var workRank: Int {
            switch self {
            case .shaky: return 0
            case .tried: return 1
            case .unseen: return 2
            case .solid: return 3
            }
        }
        static func < (a: Status, b: Status) -> Bool { a.workRank < b.workRank }
    }

    /// SOLID takes three right uses spread over at least two talks, with at
    /// most one error in five. One good talk is not command of a structure
    /// (it may have been one lucky sentence), and a structure that keeps
    /// breaking is not command either, however often it is reached for.
    static let solidRightUses = 3
    static let solidTalks = 2
    static let solidAccuracy = 0.8

    /// The status rule, all of it:
    /// - **unseen** — never produced.
    /// - **solid** — `solidRightUses`+ right uses in `solidTalks`+ talks, and
    ///   right in at least `solidAccuracy` of all tries.
    /// - **shaky** — not solid, and at least one error on file.
    /// - **tried** — produced right, never wrong, not yet enough to be solid.
    /// Counts are ALL-TIME on purpose for now: an early error is outweighed
    /// by right uses as they pile up. Weighting recent talks is the planner's
    /// question (step 4), not the file's.
    static func status(right: Int, wrong: Int, rightTalks: Int) -> Status {
        let total = right + wrong
        if total == 0 { return .unseen }
        if right >= solidRightUses, rightTalks >= solidTalks,
           Double(right) >= solidAccuracy * Double(total) {
            return .solid
        }
        return wrong > 0 ? .shaky : .tried
    }

    /// One map item as the learner stands on it.
    struct ItemState: Equatable {
        var id: String
        var kind: Kind
        var level: CEFRLevel
        var name: String
        var requires: [String]
        var right: Int = 0
        var wrong: Int = 0
        /// Talks in which it came up at all, and in which it came up right.
        var talks: Int = 0
        var rightTalks: Int = 0
        var firstSeen: Date? = nil
        var lastSeen: Date? = nil
        /// Up to three of the learner's own lines, newest first.
        var quotes: [Quote] = []

        var status: Status { LearnerState.status(right: right, wrong: wrong, rightTalks: rightTalks) }
    }

    static let maxQuotesPerItem = 3

    /// Every map item, in map order, with this learner's counts folded in.
    func items(map: LevelMap) -> [ItemState] {
        var states: [String: ItemState] = [:]
        for g in map.grammar {
            states[g.id] = ItemState(id: g.id, kind: .grammar, level: g.level,
                                     name: g.name, requires: g.requires)
        }
        for f in map.functions {
            states[f.id] = ItemState(id: f.id, kind: .function, level: f.level,
                                     name: f.name, requires: [])
        }
        var quotes: [String: [Quote]] = [:]
        for tag in sessions.values {
            for item in tag.items {
                guard var s = states[item.id] else { continue }
                s.right += item.right
                s.wrong += item.wrong
                s.talks += 1
                if item.right > 0 { s.rightTalks += 1 }
                s.firstSeen = min(s.firstSeen ?? tag.talkDate, tag.talkDate)
                s.lastSeen = max(s.lastSeen ?? tag.talkDate, tag.talkDate)
                states[item.id] = s
                quotes[item.id, default: []] += item.quotes.map {
                    var q = $0; q.date = tag.talkDate; return q
                }
            }
        }
        for (id, qs) in quotes {
            // Newest talk first; within a talk the error before the right use,
            // which is the order the tagger wrote them in.
            let ordered = qs.enumerated().sorted {
                let (a, b) = ($0.element.date ?? .distantPast, $1.element.date ?? .distantPast)
                return a != b ? a > b : $0.offset < $1.offset
            }.map(\.element)
            states[id]?.quotes = Array(ordered.prefix(Self.maxQuotesPerItem))
        }
        return (map.grammar.map(\.id) + map.functions.map(\.id)).compactMap { states[$0] }
    }
}

/// `Documents/lang/<code>/learner_state.json`, one file per target language.
///
/// Not a `LanguageScopedStore`: every call names its language, so a switch
/// has nothing to repoint. Synced (`SyncKind.learnerState`) so the other
/// device doesn't pay to tag the same talks again.
final class LearnerStateStore {
    static let shared = LearnerStateStore()
    static let filename = "learner_state.json"

    private let directory: (String) -> URL
    private let lock = NSLock()
    private var cache: [String: LearnerState] = [:]
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `directory` is injected by tests; the app writes under `LanguageScope`.
    init(directory: @escaping (String) -> URL = { LanguageScope.directory(for: $0) }) {
        self.directory = directory
    }

    private func key(_ language: String) -> String { LanguageCatalog.base(language) }

    private func url(_ language: String) -> URL {
        directory(key(language)).appendingPathComponent(Self.filename)
    }

    func state(language: String) -> LearnerState {
        lock.lock(); defer { lock.unlock() }
        return loadLocked(language)
    }

    private func loadLocked(_ language: String) -> LearnerState {
        if let hit = cache[key(language)] { return hit }
        let state = (try? Data(contentsOf: url(language)))
            .flatMap { try? decoder.decode(LearnerState.self, from: $0) }?
            .clearingOldFailures() ?? LearnerState().clearingOldFailures()
        cache[key(language)] = state
        return state
    }

    private func update(_ language: String, _ edit: (inout LearnerState) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var state = loadLocked(language)
        edit(&state)
        cache[key(language)] = state
        if let data = try? encoder.encode(state) {
            try? data.write(to: url(language), options: .atomic)
        }
        SyncEngine.noteChanged(.learnerState)
    }

    /// Another device's verdicts were merged into the file.
    func invalidate(language: String) {
        lock.lock(); cache[key(language)] = nil; lock.unlock()
    }

    /// Whether this talk still needs a tagging call: never tagged, tagged
    /// from different lines or an older map, and not given up on.
    func needsTagging(sessionId: UUID, fingerprint: String, mapVersion: Int,
                      language: String) -> Bool {
        let state = state(language: language)
        let id = sessionId.uuidString
        if (state.failures[id] ?? 0) >= LearnerState.maxFailures { return false }
        guard let tag = state.sessions[id] else { return true }
        return tag.fingerprint != fingerprint || tag.mapVersion != mapVersion
    }

    /// Files (or REPLACES) one talk's verdicts.
    func record(_ tag: LearnerState.SessionTag, sessionId: UUID, language: String) {
        update(language) {
            $0.sessions[sessionId.uuidString] = tag
            $0.failures[sessionId.uuidString] = nil
        }
    }

    func recordFailure(sessionId: UUID, language: String) {
        update(language) { $0.failures[sessionId.uuidString, default: 0] += 1 }
    }

    /// Drops the verdicts of talks that no longer exist (deleted by the
    /// learner): what they said there is no longer on file anywhere else.
    func forgetSessions(notIn ids: Set<UUID>, language: String) {
        let keep = Set(ids.map(\.uuidString))
        let stale = state(language: language).sessions.keys.filter { !keep.contains($0) }
        guard !stale.isEmpty else { return }
        update(language) { state in
            for id in stale {
                state.sessions[id] = nil
                state.failures[id] = nil
            }
        }
    }

    /// Every map item with this learner's standing; empty for a language
    /// with no map.
    func items(language: String) -> [LearnerState.ItemState] {
        guard let map = LevelMap.load(language) else { return [] }
        return state(language: language).items(map: map)
    }

    // MARK: - The block a prompt reads

    /// The most lines `promptLines` returns, header included.
    static let maxPromptLines = 25

    /// A short plain-text block for a prompt (the tutor chat first): the path
    /// to the step after the learner's level, as the plan orders it.
    ///
    /// - one line of what is SOLID up to that step;
    /// - then every gap up to that step, in WORK order: an item never comes
    ///   before an item it requires that is also a gap (past simple before
    ///   present perfect), and among those that are free, shaky before tried
    ///   before unseen, lower level first. Shaky and tried items carry one of
    ///   the learner's own lines (an error, for shaky); unseen items are named
    ///   only at the current and next level — a gap two levels down that never
    ///   came up is more likely unheard than unknown;
    /// - the functions, done and not yet, one line each.
    ///
    /// Empty when the language has no map or no talk has been tagged yet: a
    /// file with nothing in it would read as "knows nothing", which is
    /// untrue. Machine text, English; the quotes are the learner's words.
    ///
    /// `level` defaults to the learner's current level setting.
    func promptLines(language: String, level: CEFRLevel? = nil) -> String {
        guard let map = LevelMap.load(language) else { return "" }
        let state = state(language: language)
        guard !state.sessions.isEmpty else { return "" }
        let current = level
            ?? UserDefaults.standard.string(forKey: AppState.proficiencyKey).flatMap(CEFRLevel.init)
            ?? .b1
        return Self.promptLines(items: state.items(map: map), level: current,
                                talks: state.sessions.count,
                                language: LanguageCatalog.englishName(language))
    }

    /// The pure half of `promptLines`, for tests.
    static func promptLines(items: [LearnerState.ItemState], level: CEFRLevel,
                            talks: Int, language: String) -> String {
        let order = CEFRLevel.allCases
        func rank(_ l: CEFRLevel) -> Int { order.firstIndex(of: l) ?? 0 }
        // The map stops at its top step; a learner above it is read against it.
        let top = items.map(\.level).max { rank($0) < rank($1) } ?? .b2
        let currentRank = min(rank(level), rank(top))
        let nextRank = min(currentRank + 1, rank(top))
        let next = order[nextRank]

        let grammar = items.filter { $0.kind == .grammar && rank($0.level) <= nextRank }
        let functions = items.filter { $0.kind == .function && rank($0.level) <= nextRank }

        var lines = ["LEARNER STATE — \(language) level map, from \(talks) tagged talk\(talks == 1 ? "" : "s"); level \(order[currentRank].rawValue.uppercased()), next \(next.rawValue.uppercased())."]

        let solid = grammar.filter { $0.status == .solid }
        lines.append("Solid: " + (solid.isEmpty ? "none yet" : solid.map(\.name).joined(separator: "; ")))

        // Gaps to name: anything begun, plus never-seen items at the current
        // and next level.
        let gaps = grammar.filter {
            switch $0.status {
            case .solid: return false
            case .shaky, .tried: return true
            case .unseen: return rank($0.level) >= currentRank
            }
        }
        let ordered = workOrder(gaps, rank: rank)

        let functionLines = 2
        let budget = maxPromptLines - lines.count - 1 - functionLines
        if !ordered.isEmpty { lines.append("Next to work on, in order:") }
        for item in ordered.prefix(max(0, budget)) {
            let tag = "\(item.name) (\(item.id), \(item.level.rawValue.uppercased()))"
            switch item.status {
            case .shaky:
                let q = item.quotes.first { !$0.right } ?? item.quotes.first
                lines.append("- \(tag): shaky, \(item.right) right / \(item.wrong) wrong" + quoted(q))
            case .tried:
                lines.append("- \(tag): tried, \(item.right) right in \(item.rightTalks) talk\(item.rightTalks == 1 ? "" : "s")" + quoted(item.quotes.first))
            case .unseen:
                lines.append("- \(tag): not heard yet")
            case .solid:
                break
            }
        }

        let done = functions.filter { $0.status != .unseen }
        let notYet = functions.filter { $0.status == .unseen }
        lines.append("Can do: " + (done.isEmpty ? "nothing tagged yet" : done.map(\.name).joined(separator: "; ")))
        if !notYet.isEmpty {
            lines.append("Not done yet: " + notYet.map(\.name).joined(separator: "; "))
        }
        return lines.prefix(maxPromptLines).joined(separator: "\n")
    }

    private static func quoted(_ q: LearnerState.Quote?) -> String {
        guard let q, !q.text.isEmpty else { return "" }
        return "; they said: \"\(q.text)\""
    }

    /// Kahn's order over the gaps: an item waits for every gap it requires;
    /// among the free ones, shaky → tried → unseen, then lower level, then
    /// map order.
    static func workOrder(_ gaps: [LearnerState.ItemState],
                          rank: (CEFRLevel) -> Int) -> [LearnerState.ItemState] {
        let ids = Set(gaps.map(\.id))
        let index = Dictionary(uniqueKeysWithValues: gaps.enumerated().map { ($1.id, $0) })
        var waiting = gaps
        var emitted = Set<String>()
        var out: [LearnerState.ItemState] = []
        while !waiting.isEmpty {
            let free = waiting.filter { item in
                item.requires.allSatisfy { !ids.contains($0) || emitted.contains($0) }
            }
            // A cycle in the map would stall here; take everything left then.
            let pool = free.isEmpty ? waiting : free
            let best = pool.min { a, b in
                if a.status.workRank != b.status.workRank { return a.status.workRank < b.status.workRank }
                if rank(a.level) != rank(b.level) { return rank(a.level) < rank(b.level) }
                return (index[a.id] ?? 0) < (index[b.id] ?? 0)
            }!
            out.append(best)
            emitted.insert(best.id)
            waiting.removeAll { $0.id == best.id }
        }
        return out
    }
}
