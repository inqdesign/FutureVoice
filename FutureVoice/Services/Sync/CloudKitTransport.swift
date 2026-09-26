import CloudKit
import Foundation

/// The iCloud side of `SyncTransport`. `CKRecord` never leaves this file.
///
/// Private database, one custom zone per app account (the zone NAME carries
/// the Supabase user id, so two app accounts on one shared iPad never see
/// each other's practice). The container comes from `FVICloudContainer` in
/// Info.plist, which the build substitutes per config so a dev build syncs
/// into its own container.
final class CloudKitTransport: SyncTransport {

    /// Keys a change fetch asks for — everything BUT the assets. A zone
    /// change fetch downloads every `CKAsset` on every changed record before
    /// handing it over, so listing a library of 3,000 audio blobs would pull
    /// the whole gigabyte before the first session could be shown. Assets are
    /// fetched one record at a time, in the order they're wanted.
    private static let listingKeys: [CKRecord.FieldKey] = [
        "kind", "key", "lang", "payload", "size", "schema", "modifiedAt", "deletedAt",
    ]

    /// A record's fields (assets aside) may not exceed 1 MB. A payload past
    /// this rides in an asset on the same record instead.
    static let inlinePayloadLimit = 900 * 1024

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    /// Whether blob uploads/downloads may use cellular data. Items always
    /// may — they're kilobytes.
    var allowsCellularForBlobs = false

    init(containerIdentifier: String? = nil) {
        let id = containerIdentifier
            ?? Bundle.main.object(forInfoDictionaryKey: "FVICloudContainer") as? String
        if let id, !id.isEmpty, !id.hasPrefix("$(") {
            container = CKContainer(identifier: id)
        } else {
            container = CKContainer.default()
        }
        allowsCellularForBlobs = SyncStore.cellularForAudio
    }

    // MARK: - Account & zone

    func accountAvailable() async -> SyncAccountState {
        guard let status = try? await container.accountStatus() else { return .unknown }
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return .unknown
        }
    }

    private func zoneID(_ zone: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
    }

    func ensureZone(_ zone: String) async throws {
        do {
            let result = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID(zone))], deleting: [])
            for (_, r) in result.saveResults { _ = try r.get() }
        } catch {
            throw Self.mapped(error)
        }
    }

    func zoneExists(_ zone: String) async throws -> Bool {
        do {
            let result = try await database.recordZones(for: [zoneID(zone)])
            guard let r = result[zoneID(zone)] else { return false }
            switch r {
            case .success: return true
            case .failure(let e):
                if let ck = e as? CKError, ck.code == .zoneNotFound { return false }
                throw Self.mapped(e)
            }
        } catch let e as SyncTransportError {
            throw e
        } catch {
            if let ck = error as? CKError, ck.code == .zoneNotFound { return false }
            throw Self.mapped(error)
        }
    }

    func deleteZone(_ zone: String) async throws {
        do {
            let result = try await database.modifyRecordZones(saving: [], deleting: [zoneID(zone)])
            for (_, r) in result.deleteResults {
                if case .failure(let e) = r,
                   let ck = e as? CKError, ck.code == .zoneNotFound { continue }
                _ = try r.get()
            }
        } catch {
            if let ck = error as? CKError, ck.code == .zoneNotFound { return }
            throw Self.mapped(error)
        }
    }

    // MARK: - Push subscription

    /// One zone subscription per account. A private-database subscription
    /// pushes to EVERY device the iCloud account is signed into, so a
    /// per-device id would only mean N pushes for one change; the id carries
    /// the zone instead, which is what keeps two app accounts on one shared
    /// iPad from overwriting each other's subscription.
    func subscribeToZoneChanges(_ zone: String, subscriptionID: String) async throws {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID(zone), subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent, and it must stay silent: no alert, no badge, no sound. The
        // push wakes the app to run a pass and says nothing to the learner —
        // which is also why sync never has to ask for notification
        // permission, since a content-available push needs none.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            let result = try await database.modifySubscriptions(
                saving: [subscription], deleting: [])
            for (_, r) in result.saveResults { _ = try r.get() }
        } catch {
            throw Self.mapped(error)
        }
    }

    func unsubscribeFromZoneChanges(subscriptionID: String) async throws {
        do {
            let result = try await database.modifySubscriptions(
                saving: [], deleting: [subscriptionID])
            for (_, r) in result.deleteResults {
                if case .failure(let e) = r,
                   let ck = e as? CKError, ck.code == .unknownItem { continue }
                _ = try r.get()
            }
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem { return }
            throw Self.mapped(error)
        }
    }

    /// CloudKit defers `.utility` work behind everything else on the device
    /// and the network — measured as a first sync crawling while the
    /// learner watched its progress bar. Every pass here is either watched
    /// or on a background task's clock, so it asks for the foreground lane.
    static let qos: QualityOfService = .userInitiated

    // MARK: - Save

    func save(_ records: [SyncRecord], in zone: String) async throws -> [String: SyncSaveOutcome] {
        guard !records.isEmpty else { return [:] }
        let zid = zoneID(zone)
        var ckRecords: [CKRecord] = []
        var tempFiles: [URL] = []
        var outcomes: [String: SyncSaveOutcome] = [:]
        for record in records {
            do {
                let (ck, temp) = try Self.makeRecord(record, zoneID: zid)
                ckRecords.append(ck)
                if let temp { tempFiles.append(temp) }
            } catch {
                outcomes[record.recordName] = .failed(.other(error.localizedDescription))
            }
        }
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        guard !ckRecords.isEmpty else { return outcomes }
        let cellular = records.contains { !$0.kind.isBlob } || allowsCellularForBlobs
        let results = try await modify(ckRecords, allowsCellular: cellular)
        for (id, result) in results {
            switch result {
            case .success(let saved):
                outcomes[id.recordName] = .saved(systemFields: Self.systemFields(of: saved))
            case .failure(let error):
                if let ck = error as? CKError, ck.code == .serverRecordChanged {
                    outcomes[id.recordName] = .conflict
                } else {
                    outcomes[id.recordName] = .failed(Self.mapped(error))
                }
            }
        }
        return outcomes
    }

    private func modify(_ records: [CKRecord], allowsCellular: Bool) async throws
        -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: [])
            op.savePolicy = .ifServerRecordUnchanged
            op.isAtomic = false
            op.qualityOfService = Self.qos
            op.configuration.allowsCellularAccess = allowsCellular
            var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
            op.perRecordSaveBlock = { id, result in results[id] = result }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: results)
                case .failure(let error):
                    // With `isAtomic = false` a partial failure has already
                    // been reported per record; only a whole-operation
                    // failure is worth throwing.
                    if let ck = error as? CKError, ck.code == .partialFailure {
                        cont.resume(returning: results)
                    } else {
                        cont.resume(throwing: Self.mapped(error))
                    }
                }
            }
            database.add(op)
        }
    }

    // MARK: - Changes

    func changes(in zone: String, since token: Data?) async throws -> SyncChangeBatch {
        var batch = SyncChangeBatch()
        var current = token.flatMap(Self.token(from:))
        var more = true
        while more {
            do {
                let page = try await database.recordZoneChanges(
                    inZoneWith: zoneID(zone), since: current,
                    desiredKeys: Self.listingKeys, resultsLimit: nil)
                for (_, result) in page.modificationResultsByID {
                    guard case .success(let mod) = result,
                          let record = Self.makeSyncRecord(mod.record) else { continue }
                    batch.changed.append(record)
                }
                batch.deleted += page.deletions.map { $0.recordID.recordName }
                current = page.changeToken
                more = page.moreComing
            } catch {
                throw Self.mapped(error)
            }
        }
        batch.token = current.flatMap(Self.data(from:))
        return batch
    }

    func fetch(recordName: String, in zone: String) async throws -> SyncRecord? {
        let found = try await fetch(recordNames: [recordName], in: zone)
        guard let record = found[recordName] else { throw SyncTransportError.other("no record") }
        return record
    }

    func fetch(recordNames: [String], in zone: String) async throws -> [String: SyncRecord] {
        guard !recordNames.isEmpty else { return [:] }
        let zid = zoneID(zone)
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zid) }
        let records: [CKRecord] = try await withCheckedThrowingContinuation { cont in
            let op = CKFetchRecordsOperation(recordIDs: ids)
            op.qualityOfService = Self.qos
            op.configuration.allowsCellularAccess = allowsCellularForBlobs
                || recordNames.contains { !$0.hasPrefix("blob") }
            var fetched: [CKRecord] = []
            op.perRecordResultBlock = { _, result in
                // A missing record is a per-record failure; the caller reads
                // its absence. Only a whole-operation failure is thrown.
                if case .success(let record) = result { fetched.append(record) }
            }
            op.fetchRecordsResultBlock = { result in
                if case .failure(let error) = result,
                   !((error as? CKError)?.code == .partialFailure) {
                    cont.resume(throwing: Self.mapped(error))
                    return
                }
                cont.resume(returning: fetched)
            }
            database.add(op)
        }
        var out: [String: SyncRecord] = [:]
        for ck in records {
            if let r = Self.makeSyncRecord(ck, includingAssets: true) { out[ck.recordID.recordName] = r }
        }
        return out
    }

    // MARK: - Mapping

    private static func makeRecord(_ r: SyncRecord, zoneID: CKRecordZone.ID) throws -> (CKRecord, URL?) {
        let id = CKRecord.ID(recordName: r.recordName, zoneID: zoneID)
        let ck: CKRecord
        if let fields = r.systemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: fields),
           let restored = CKRecord(coder: coder) {
            coder.finishDecoding()
            ck = restored
        } else {
            ck = CKRecord(recordType: r.kind.recordType, recordID: id)
        }
        ck["kind"] = r.kind.rawValue
        ck["key"] = r.key
        ck["lang"] = r.lang
        ck["schema"] = r.schema
        ck["modifiedAt"] = r.modifiedAt
        ck["deletedAt"] = r.deletedAt
        var temp: URL?
        if r.kind.isBlob {
            ck["payload"] = nil
            ck["size"] = r.size
            if let url = r.assetURL, !r.isTombstone {
                ck["asset"] = CKAsset(fileURL: url)
            } else {
                ck["asset"] = nil
            }
        } else if let payload = r.payload {
            ck["size"] = payload.count
            if payload.count > inlinePayloadLimit {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sync-\(UUID().uuidString).json")
                try payload.write(to: url, options: .atomic)
                temp = url
                ck["payload"] = nil
                ck["payloadAsset"] = CKAsset(fileURL: url)
            } else {
                ck["payload"] = payload
                ck["payloadAsset"] = nil
            }
        } else {
            ck["payload"] = nil
            ck["payloadAsset"] = nil
            ck["size"] = 0
        }
        return (ck, temp)
    }

    private static func makeSyncRecord(_ ck: CKRecord, includingAssets: Bool = false) -> SyncRecord? {
        guard let kindRaw = ck["kind"] as? String, let kind = SyncKind(rawValue: kindRaw),
              let key = ck["key"] as? String,
              let modifiedAt = ck["modifiedAt"] as? Date
        else { return nil }
        var payload = ck["payload"] as? Data
        var assetURL: URL?
        if includingAssets {
            if let asset = ck["asset"] as? CKAsset { assetURL = asset.fileURL }
            if payload == nil, let asset = ck["payloadAsset"] as? CKAsset,
               let url = asset.fileURL {
                payload = try? Data(contentsOf: url)
            }
        }
        return SyncRecord(
            kind: kind, key: key, lang: ck["lang"] as? String,
            payload: payload, assetURL: assetURL,
            size: (ck["size"] as? Int) ?? 0,
            schema: (ck["schema"] as? Int) ?? 1,
            modifiedAt: modifiedAt,
            deletedAt: ck["deletedAt"] as? Date,
            systemFields: systemFields(of: ck))
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func token(from data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func data(from token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    // MARK: - Errors

    static func mapped(_ error: Error) -> SyncTransportError {
        if let e = error as? SyncTransportError { return e }
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .changeTokenExpired: return .tokenExpired
        case .zoneNotFound, .userDeletedZone: return .zoneMissing
        case .quotaExceeded: return .quotaExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return .rateLimited(ck.retryAfterSeconds ?? 30)
        case .limitExceeded: return .limitExceeded
        case .networkUnavailable, .networkFailure: return .network
        case .notAuthenticated: return .notSignedIn
        default: return .other("CloudKit \(ck.code.rawValue): \(ck.localizedDescription)")
        }
    }
}
