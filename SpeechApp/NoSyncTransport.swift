import Foundation

/// The speech app's stand-in for iCloud. It has no container (the
/// entitlement is nawana's), and `CKContainer` traps without one, so the
/// shared `SyncEngine` gets this instead. Sync is never turned on here.
final class NoSyncTransport: SyncTransport {
    func accountAvailable() async -> SyncAccountState { .noAccount }
    func ensureZone(_ zone: String) async throws {}
    func zoneExists(_ zone: String) async throws -> Bool { false }
    func deleteZone(_ zone: String) async throws {}
    func save(_ records: [SyncRecord], in zone: String) async throws -> [String: SyncSaveOutcome] { [:] }
    func changes(in zone: String, since token: Data?) async throws -> SyncChangeBatch { SyncChangeBatch() }
    func fetch(recordName: String, in zone: String) async throws -> SyncRecord? { nil }
}
