import Foundation

/// What this device knows about every synced item: its last-seen fingerprint,
/// whether the server has that version, the server's change tag, and the
/// timestamps the LWW rules read. Lives at `Documents/sync/<userId>/`, one
/// index per app account, and is deliberately outside the backup envelope
/// (`BackupService.excludedFolders`) — a restored install must re-derive its
/// own relationship with the cloud.
///
/// The index is what turns whole-file stores into per-item sync without
/// instrumenting every mutation: a pass reads a store, fingerprints each
/// item, and compares against these entries. A key that is here and not in
/// the store was deleted; a fingerprint that moved was edited.
final class SyncIndex {

    struct Entry: Codable, Equatable {
        var kind: SyncKind
        var lang: String?
        var key: String
        /// `SyncCanonical.hash` of the payload, or `blobFingerprint` for a blob.
        var hash: String
        /// When the diff first saw this fingerprint — the LWW clock for kinds
        /// whose items carry no timestamp of their own.
        var observedAt: Date
        /// The server holds exactly this version.
        var pushedAt: Date?
        /// Set by a pull whose merge produced something the server doesn't
        /// have yet. The diff can't see it (the hash already matches), so it
        /// is the one flag that forces a push.
        var needsPush: Bool = false
        var deletedAt: Date?
        /// The server's change tag for this record. Without it a re-save is
        /// refused as a conflict, so it is carried on every entry the server
        /// has acknowledged.
        var systemFields: Data?
        /// The record came from a NEWER build and must never be pushed back
        /// or tombstoned by this one — see `SyncSchema`.
        var frozen: Bool = false
        /// A blob the server has and this device hasn't downloaded yet. Size
        /// is carried so the progress row can count bytes.
        var wanted: Bool = false
        var size: Int = 0

        var isDeleted: Bool { deletedAt != nil }
        var recordName: String { SyncRecord.recordName(kind: kind, lang: lang, key: key) }
    }

    struct State: Codable {
        var changeToken: Data?
        var lastPullAt: Date?
        var lastPushAt: Date?
        /// Bumped when the app's `SyncSchema.version` moves past the one this
        /// index was written under, so frozen entries thaw once.
        var schema: Int = SyncSchema.version
    }

    private(set) var entries: [String: Entry] = [:]
    var state = State()

    private let directory: URL
    private var entriesURL: URL { directory.appendingPathComponent("index.json") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    static func directory(forUser userId: String) -> URL {
        SyncFiles.documents.appendingPathComponent("sync", isDirectory: true)
            .appendingPathComponent(userId, isDirectory: true)
    }

    /// Every write of every index goes through this one serial queue, so
    /// saves land in order and a `removeAll` can't be overtaken by a save
    /// queued before it. Encoding the whole index (thousands of entries,
    /// each with its change tag) ran on the main actor after every batch.
    private static let writer = DispatchQueue(label: "com.roro.futurevoice.sync-index",
                                              qos: .utility)

    init(directory: URL) {
        self.directory = directory
        // A save queued by a previous instance must be on disk before this
        // one reads.
        Self.writer.sync {}
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: entriesURL),
           let decoded = try? SyncCanonical.decode([String: Entry].self, from: data) {
            entries = decoded
        }
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? SyncCanonical.decode(State.self, from: data) {
            state = decoded
        }
        thawIfUpgraded()
    }

    convenience init(userId: String) {
        self.init(directory: Self.directory(forUser: userId))
    }

    /// Entries frozen under an older schema can be read now: thaw them and
    /// drop the change token so their current server copies come through the
    /// merge on the next pull.
    private func thawIfUpgraded() {
        guard state.schema < SyncSchema.version else { return }
        for (name, var entry) in entries where entry.frozen {
            entry.frozen = false
            entries[name] = entry
        }
        state.changeToken = nil
        state.schema = SyncSchema.version
        save()
    }

    // MARK: - Access

    subscript(recordName: String) -> Entry? {
        get { entries[recordName] }
        set { entries[recordName] = newValue }
    }

    func entry(kind: SyncKind, lang: String?, key: String) -> Entry? {
        entries[SyncRecord.recordName(kind: kind, lang: lang, key: key)]
    }

    func set(_ entry: Entry) {
        entries[entry.recordName] = entry
    }

    func entries(kind: SyncKind, lang: String?) -> [Entry] {
        entries.values.filter { $0.kind == kind && $0.lang == lang }
    }

    var pendingPush: [Entry] {
        entries.values.filter { $0.needsPush && !$0.frozen }
    }

    var wantedBlobs: [Entry] {
        entries.values.filter { $0.wanted && !$0.isDeleted }
    }

    /// Every language this index has seen for a scoped kind — the diff has
    /// to visit a language the learner un-enrolled so its tombstones still
    /// go out.
    func languages(for kind: SyncKind) -> Set<String> {
        Set(entries.values.compactMap { $0.kind == kind ? $0.lang : nil })
    }

    // MARK: - Persistence

    func save() {
        let entries = entries, state = state
        let entriesURL = entriesURL, stateURL = stateURL
        Self.writer.async {
            if let data = try? SyncCanonical.encode(entries) {
                try? data.write(to: entriesURL, options: .atomic)
            }
            if let data = try? SyncCanonical.encode(state) {
                try? data.write(to: stateURL, options: .atomic)
            }
        }
    }

    /// Blocks until every queued save is on disk — for a caller about to
    /// be suspended (or a test reading the files back).
    static func flush() {
        writer.sync {}
    }

    /// Forgets the server entirely — change tags and token — while keeping
    /// every fingerprint. What "the zone is gone" needs: the next enable
    /// re-pushes the library from what is on disk.
    func forgetServer() {
        for (name, var entry) in entries {
            entry.systemFields = nil
            entry.pushedAt = nil
            entry.needsPush = !entry.isDeleted
            entry.wanted = false
            entries[name] = entry
        }
        state.changeToken = nil
        state.lastPullAt = nil
        save()
    }

    func removeAll() {
        entries = [:]
        state = State()
        let directory = directory
        Self.writer.async { try? FileManager.default.removeItem(at: directory) }
    }
}
