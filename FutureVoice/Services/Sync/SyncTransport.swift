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

    /// Several full records in one round trip, keyed by record name; a name
    /// the server doesn't have is simply absent.
    func fetch(recordNames: [String], in zone: String) async throws -> [String: SyncRecord]

    /// Asks the server to wake this app whenever anything in the zone
    /// changes, so the other device's talk arrives without waiting for this
    /// one to be opened. Idempotent: the id is stable, so saving it again
    /// replaces the subscription rather than adding a second one.
    func subscribeToZoneChanges(_ zone: String, subscriptionID: String) async throws

    /// Stops those wakes for the whole ACCOUNT — every device of it. Only
    /// "Delete from iCloud" may call this; a single device turning sync off
    /// unregisters itself instead (`SyncPush.deactivate`), because the
    /// subscription is the account's and the other device may still want it.
    /// A subscription the server hasn't got is not an error.
    func unsubscribeFromZoneChanges(subscriptionID: String) async throws
}

extension SyncTransport {
    /// A transport with no push of its own — the tests' in-memory one — has
    /// nothing to subscribe to, and the engine must not care which it holds.
    func subscribeToZoneChanges(_ zone: String, subscriptionID: String) async throws {}
    func unsubscribeFromZoneChanges(subscriptionID: String) async throws {}

    func fetch(recordNames: [String], in zone: String) async throws -> [String: SyncRecord] {
        var out: [String: SyncRecord] = [:]
        for name in recordNames {
            if let r = try await fetch(recordName: name, in: zone) { out[name] = r }
        }
        return out
    }
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
