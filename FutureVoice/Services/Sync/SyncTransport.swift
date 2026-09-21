import Foundation

/// Everything the engine needs from the cloud, and nothing CloudKit-shaped.
/// `CloudKitTransport` is the only conformer that talks to iCloud; the tests
/// run the whole engine against an in-memory one, which is the only way the
/// merge rules and the index can be tested at all.
protocol SyncTransport: AnyObject {
    /// Whether an iCloud account is usable right now.
    func accountAvailable() async -> SyncAccountState

    /// Creates the account's zone if it doesn't exist. Idempotent.
    func ensureZone(_ zone: String) async throws

    /// True when the zone exists — the "you've practised on another device"
    /// test a fresh install runs before offering to continue.
    func zoneExists(_ zone: String) async throws -> Bool

    /// Deletes the zone and everything in it — "Delete from iCloud".
    func deleteZone(_ zone: String) async throws

    /// Saves records, each with `.ifServerRecordUnchanged` semantics: a record
    /// whose `systemFields` is stale comes back as `.conflict` carrying the
    /// server's copy, never overwritten. Outcomes are keyed by record name.
    func save(_ records: [SyncRecord], in zone: String) async throws -> [String: SyncSaveOutcome]

    /// Everything changed since `token` (nil = from the beginning). Blob
    /// records come back WITHOUT their asset — the caller fetches those one
    /// by one with `fetchAsset` — and an item whose payload lives in an
    /// oversized asset comes back with `payload == nil` and must be fetched
    /// the same way.
    func changes(in zone: String, since token: Data?) async throws -> SyncChangeBatch

    /// The full record including its asset, downloaded to a temporary file
    /// the caller must move or copy before returning.
    func fetch(recordName: String, in zone: String) async throws -> SyncRecord?
}

enum SyncAccountState: Equatable {
    case available
    case noAccount
    case restricted
    case unknown
}

enum SyncSaveOutcome {
    /// Saved; carry the new change tag into the index.
    case saved(systemFields: Data)
    /// The server holds a newer copy. The engine never resolves this inline:
    /// the next pull brings the server's copy through the merge, and the
    /// push after that carries the right tag.
    case conflict
    case failed(SyncTransportError)
}

struct SyncChangeBatch {
    var changed: [SyncRecord] = []
    /// Record names the server deleted outright (never by this app — it only
    /// ever writes tombstones — but a zone can be edited elsewhere).
    var deleted: [String] = []
    var token: Data?
}

enum SyncTransportError: Error, Equatable {
    /// The change token is too old; drop it and fetch from the beginning.
    case tokenExpired
    /// The zone is gone — deleted from another device or from Settings.
    case zoneMissing
    /// The learner's iCloud storage is full.
    case quotaExceeded
    /// Come back after this many seconds.
    case rateLimited(TimeInterval)
    /// Too many records or bytes in one request; halve the batch.
    case limitExceeded
    case network
    case notSignedIn
    case other(String)
}
