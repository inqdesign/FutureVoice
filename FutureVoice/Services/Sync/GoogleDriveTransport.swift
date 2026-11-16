import Foundation

/// The Google Drive side of `SyncTransport` — the one Android has always
/// used (`DriveTransport.kt`), so an Android phone and a Mac or iPhone that
/// sign into the same Google account read and write ONE folder. Every byte
/// of the layout below is Android's; change it on both sides or not at all.
///
/// Shape on Drive: inside the app's hidden `appDataFolder`, one folder per
/// app account (`nawana-<userId>`), one FILE per record named by the record
/// name. Kind, language, schema and the two clocks ride in `appProperties`
/// (`k` `l` `s` `m` `d` `z`; the clocks as epoch MILLISECONDS, which is what
/// Android's `Long` writes); the item's own key rides in `description`; the
/// file's content is the canonical payload (UTF-8 JSON), the audio bytes for
/// a blob, or empty for a tombstone.
///
/// Three Drive facts the engine is built around (Android's note, verbatim
/// in meaning):
/// - **No conditional write.** A save just replaces, so there is never a
///   `.conflict`. Safe because every pass pulls before it pushes and every
///   merge rule is commutative or newest-wins.
/// - **The change feed is per SPACE**, so changes outside this account's
///   folder are skipped.
/// - **A removed file arrives as an id only**; ids this transport has seen
///   are mapped back to record names, the rest are dropped (the engine only
///   uses deletions to forget a change tag).
///
/// The change tag the engine carries (`systemFields`) is the Drive FILE ID,
/// as UTF-8 — a save with one updates that file, a save without creates.
final class GoogleDriveTransport: SyncTransport, BlobCellularControl {
    /// Kinds kept OFF Drive for now, both ways. Drive is where the Android
    /// app syncs, and for these the two apps don't yet agree (audited
    /// 2026-11-05):
    /// - `drill`: Android writes a retired card's date as `Long.MAX_VALUE`,
    ///   which iOS can't decode — the card would be skipped, then
    ///   tombstoned, and every "Got it" card deleted on every device.
    /// - `shadow`: `phraseRange` vs `phraseFirst`/`phraseLast`, so a phrase
    ///   take would come back as a whole-line take; Android's 500 cap also
    ///   drops the NEWEST on a synced file.
    /// - `savedLine`: language-scoped here, global on Android.
    /// - `defaults`: two payload shapes neither side reads, and Android
    ///   tombstones every iOS-only setting.
    /// - `blobTurn` / `blobVoiceSample` / `blobRecording`: Android downloads
    ///   files its own reader filters out (`.mp3`, `.m4a`, `sample-*.wav`),
    ///   tombstones them, and the iOS audio is deleted.
    /// A kind leaves this list once both apps are fixed and the fix is on
    /// every Android build in use. Excluded kinds are reported as saved
    /// without a request (so they never queue) and never read from Drive.
    ///
    /// Where that stands: Android `fc7953ab` (2026-11-05) writes the retired
    /// date as 4001-01-01, writes `phraseRange` beside its own fields with no
    /// cap, never fetches a file it doesn't read, and freezes an item its
    /// store can't decode instead of writing it. So `drill`, `shadow` and
    /// `blobRecording` wait only on that build reaching every Android
    /// device. `blobTurn` and `blobVoiceSample` are SAFE then but useless:
    /// the two apps still don't play each other's turn audio (`.wav` there,
    /// `.mp3`/`.m4a` here) or read each other's voice-sample name. `defaults`
    /// and `savedLine` still disagree in shape and scope.
    static let excludedKinds: Set<SyncKind> = [
        .drill, .shadow, .savedLine, .defaults, .blobTurn, .blobVoiceSample, .blobRecording,
        // Android has no goal plans yet; a kind it can't read it tombstones.
        .goalPlan,
    ]

    private let userId: String
    private let session: URLSession
    private let api = "https://www.googleapis.com/drive/v3"
    private let upload = "https://www.googleapis.com/upload/drive/v3"
    private let folderMime = "application/vnd.google-apps.folder"
    private let fileFields = "id,name,description,appProperties,parents,trashed,size,modifiedTime,md5Checksum"
    /// Drive's own guidance is a handful of parallel requests per user.
    private static let parallel = 6
    /// Simple/multipart upload is for files up to 5 MB.
    private static let resumableFrom = 4 * 1024 * 1024

    var allowsCellularForBlobs = SyncStore.cellularForAudio

    private let lock = NSLock()
    private var zoneIds: [String: String] = [:]
    /// Record name ↔ Drive file id, learnt from listings and saves.
    private var idByName: [String: String] = [:]
    private var nameById: [String: String] = [:]
    /// What THIS device last wrote to each file: Drive file id → the md5
    /// Drive reported for it (2026-11-16). The change feed lists this
    /// device's own writes too, and every item in it was downloaded again —
    /// a learner's call pushed ~150 word records and the next pass pulled
    /// all ~150 back. A file whose md5 still matches holds exactly what this
    /// device pushed and already has, so the pull leaves it out. Memory
    /// only: after a relaunch an echo is downloaded once, as before.
    private var ownWrites: [String: String] = [:]
    private static let maxOwnWrites = 20_000

    init(userId: String) {
        self.userId = userId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    func isFor(_ userId: String) -> Bool { self.userId == userId }

    // MARK: - Account & zone

    func accountAvailable() async -> SyncAccountState {
        switch await GoogleDriveAuth.accessToken(userId: userId) {
        case .token: return .available
        case .needsSignIn: return .noAccount
        case .offline: return .unknown
        }
    }

    private func cachedZone(_ zone: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return zoneIds[zone]
    }

    private func findZone(_ zone: String) async throws -> String? {
        if let id = cachedZone(zone) { return id }
        var c = URLComponents(string: "\(api)/files")!
        c.queryItems = [
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "q", value: "name = '\(zone)' and mimeType = '\(folderMime)' and trashed = false"),
            .init(name: "fields", value: "files(id)"),
        ]
        let body = try await json(URLRequest(url: c.url!))
        let id = (body["files"] as? [[String: Any]])?.first?["id"] as? String
        if let id { lock.lock(); zoneIds[zone] = id; lock.unlock() }
        return id
    }

    private func zoneId(_ zone: String) async throws -> String {
        guard let id = try await findZone(zone) else { throw SyncTransportError.zoneMissing }
        return id
    }

    func ensureZone(_ zone: String) async throws {
        if try await findZone(zone) != nil { return }
        var request = URLRequest(url: URL(string: "\(api)/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": zone, "mimeType": folderMime, "parents": ["appDataFolder"],
        ])
        let created = try await json(request)
        guard let id = created["id"] as? String else { throw SyncTransportError.other("drive: no folder id") }
        lock.lock(); zoneIds[zone] = id; lock.unlock()
    }

    func zoneExists(_ zone: String) async throws -> Bool {
        try await findZone(zone) != nil
    }

    func deleteZone(_ zone: String) async throws {
        guard let id = try await findZone(zone) else { return }
        var request = URLRequest(url: URL(string: "\(api)/files/\(id)")!)
        request.httpMethod = "DELETE"
        do { _ = try await send(request) } catch DriveError.notFound {}
        lock.lock(); zoneIds[zone] = nil; lock.unlock()
    }

    // MARK: - Save

    func save(_ records: [SyncRecord], in zone: String) async throws -> [String: SyncSaveOutcome] {
        guard !records.isEmpty else { return [:] }
        let parent = try await zoneId(zone)
        var outcomes: [String: SyncSaveOutcome] = [:]
        for r in records where Self.excludedKinds.contains(r.kind) {
            outcomes[r.recordName] = .saved(systemFields: Data())
        }
        let records = records.filter { !Self.excludedKinds.contains($0.kind) }
        for start in stride(from: 0, to: records.count, by: Self.parallel) {
            let slice = records[start..<min(start + Self.parallel, records.count)]
            try await withThrowingTaskGroup(of: (String, SyncSaveOutcome).self) { group in
                for record in slice {
                    group.addTask {
                        do {
                            let id = try await self.saveOne(record, parent: parent)
                            return (record.recordName, .saved(systemFields: Data(id.utf8)))
                        } catch let e as SyncTransportError {
                            switch e {
                            // The whole pass can't go on; let the engine stop.
                            case .zoneMissing, .notSignedIn, .network: throw e
                            default: return (record.recordName, .failed(e))
                            }
                        } catch {
                            return (record.recordName, .failed(.other(error.localizedDescription)))
                        }
                    }
                }
                for try await (name, outcome) in group { outcomes[name] = outcome }
            }
        }
        return outcomes
    }

    private func saveOne(_ r: SyncRecord, parent: String) async throws -> String {
        let knownId = r.systemFields.map { String(decoding: $0, as: UTF8.self) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? remembered(name: r.recordName)
        var meta: [String: Any] = [
            "name": r.recordName,
            "description": r.key,
            "appProperties": Self.properties(for: r),
        ]
        if knownId == nil { meta["parents"] = [parent] }

        let media: Data
        let mediaType: String
        if r.isTombstone {
            media = Data(); mediaType = "application/octet-stream"
        } else if r.kind.isBlob, let url = r.assetURL {
            media = try Data(contentsOf: url, options: .mappedIfSafe)
            mediaType = "application/octet-stream"
        } else {
            media = r.payload ?? Data(); mediaType = "application/json; charset=UTF-8"
        }
        let cellular = !r.kind.isBlob || allowsCellularForBlobs
        let id: String
        do {
            id = media.count > Self.resumableFrom
                ? try await resumable(meta: meta, media: media, id: knownId, cellular: cellular)
                : try await multipart(meta: meta, media: media, type: mediaType, id: knownId, cellular: cellular)
        } catch DriveError.notFound where knownId != nil {
            // The file this device remembered is gone (deleted elsewhere):
            // write it fresh rather than failing the record forever.
            meta["parents"] = [parent]
            id = media.count > Self.resumableFrom
                ? try await resumable(meta: meta, media: media, id: nil, cellular: cellular)
                : try await multipart(meta: meta, media: media, type: mediaType, id: nil, cellular: cellular)
        } catch DriveError.notFound {
            throw SyncTransportError.zoneMissing
        }
        remember(name: r.recordName, id: id)
        return id
    }

    private func multipart(meta: [String: Any], media: Data, type: String, id: String?,
                           cellular: Bool) async throws -> String {
        let boundary = "fv-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONSerialization.data(withJSONObject: meta))
        body.append("\r\n--\(boundary)\r\nContent-Type: \(type)\r\n\r\n".data(using: .utf8)!)
        body.append(media)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let path = id.map { "\(upload)/files/\($0)" } ?? "\(upload)/files"
        var request = URLRequest(url: URL(string: "\(path)?uploadType=multipart&fields=id,md5Checksum")!)
        request.httpMethod = id == nil ? "POST" : "PATCH"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.allowsCellularAccess = cellular
        return try noteOwnWrite(try await json(request))
    }

    private func resumable(meta: [String: Any], media: Data, id: String?, cellular: Bool) async throws -> String {
        let path = id.map { "\(upload)/files/\($0)" } ?? "\(upload)/files"
        var start = URLRequest(url: URL(string: "\(path)?uploadType=resumable&fields=id,md5Checksum")!)
        start.httpMethod = id == nil ? "POST" : "PATCH"
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: meta)
        start.allowsCellularAccess = cellular
        let (_, response) = try await send(start)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location) else { throw SyncTransportError.other("drive: no upload location") }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.httpBody = media
        put.allowsCellularAccess = cellular
        put.timeoutInterval = 600
        return try noteOwnWrite(try await json(put))
    }

    // MARK: - Changes

    func changes(in zone: String, since token: Data?) async throws -> SyncChangeBatch {
        let parent = try await zoneId(zone)
        if let token, let page = String(data: token, encoding: .utf8), !page.isEmpty {
            return try await changeFeed(parent: parent, token: page)
        }
        return try await fullListing(parent: parent)
    }

    /// First pull: the token is taken FIRST, so nothing written while the
    /// listing runs can fall between the two.
    private func fullListing(parent: String) async throws -> SyncChangeBatch {
        let start = try await retrying { try await self.json(URLRequest(url: URL(string: "\(self.api)/changes/startPageToken")!)) }
        guard let startToken = start["startPageToken"] as? String else {
            throw SyncTransportError.other("drive: no start token")
        }
        var files: [[String: Any]] = []
        var page: String?
        repeat {
            var c = URLComponents(string: "\(api)/files")!
            c.queryItems = [
                .init(name: "spaces", value: "appDataFolder"),
                .init(name: "q", value: "'\(parent)' in parents and trashed = false"),
                .init(name: "pageSize", value: "1000"),
                .init(name: "fields", value: "nextPageToken,files(\(fileFields))"),
            ] + (page.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let url = c.url!
            let body = try await retrying { try await self.json(URLRequest(url: url)) }
            files += (body["files"] as? [[String: Any]]) ?? []
            page = body["nextPageToken"] as? String
        } while page != nil
        var batch = SyncChangeBatch()
        batch.changed = try await materialize(try await dedupe(files))
        batch.token = Data(startToken.utf8)
        return batch
    }

    private func changeFeed(parent: String, token: String) async throws -> SyncChangeBatch {
        var files: [[String: Any]] = []
        var removedIds: [String] = []
        var page: String? = token
        var next: String?
        while let current = page {
            var c = URLComponents(string: "\(api)/changes")!
            c.queryItems = [
                .init(name: "pageToken", value: current),
                .init(name: "spaces", value: "appDataFolder"),
                .init(name: "pageSize", value: "1000"),
                .init(name: "fields", value: "nextPageToken,newStartPageToken,changes(fileId,removed,file(\(fileFields)))"),
            ]
            let body: [String: Any]
            let url = c.url!
            do { body = try await retrying { try await self.json(URLRequest(url: url)) } } catch DriveError.notFound {
                throw SyncTransportError.tokenExpired
            }
            for change in (body["changes"] as? [[String: Any]]) ?? [] {
                let file = change["file"] as? [String: Any]
                let gone = (change["removed"] as? Bool) == true || (file?["trashed"] as? Bool) == true
                if gone {
                    if let id = change["fileId"] as? String { removedIds.append(id) }
                    continue
                }
                guard let file else { continue }
                if ((file["parents"] as? [String]) ?? []).contains(parent) { files.append(file) }
            }
            page = body["nextPageToken"] as? String
            next = (body["newStartPageToken"] as? String) ?? next
        }
        var batch = SyncChangeBatch()
        batch.changed = try await materialize(try await dedupe(files))
        batch.deleted = removedIds.compactMap { forget(id: $0) }
        batch.token = Data((next ?? token).utf8)
        return batch
    }

    /// Two devices that both created the same record before either pulled
    /// leave two files with one name. Keep the newest; remove the rest.
    private func dedupe(_ files: [[String: Any]]) async throws -> [[String: Any]] {
        let groups = Dictionary(grouping: files) { ($0["name"] as? String) ?? "" }
        var keep: [[String: Any]] = []
        for (_, group) in groups {
            let sorted = group.sorted { (Self.prop($0, "m").flatMap(Int64.init) ?? 0) > (Self.prop($1, "m").flatMap(Int64.init) ?? 0) }
            keep.append(sorted[0])
            for extra in sorted.dropFirst() {
                guard let id = extra["id"] as? String else { continue }
                var request = URLRequest(url: URL(string: "\(api)/files/\(id)")!)
                request.httpMethod = "DELETE"
                _ = try? await send(request)
            }
        }
        return keep
    }

    /// File metadata → records, downloading item payloads (small) and
    /// leaving blobs' bytes on the server. A file deleted while the listing
    /// ran is simply gone; any other failure aborts the pull, so the change
    /// token never moves past an item that was not applied.
    ///
    /// A first pull is one request PER ITEM, thousands for a learner who has
    /// used the app for weeks, so two things keep "any failure aborts" from
    /// meaning "never": each request is retried (`retrying`), and every
    /// payload that did arrive is parked in `pullCache` under its id and
    /// modified time, so the next attempt fetches only what is still
    /// missing. Reported on Android 2026-11-15: a reinstall with ~4,000
    /// records on Drive failed its first pull twice, each time from zero.
    private func materialize(_ files: [[String: Any]]) async throws -> [SyncRecord] {
        var shells: [(id: String, stamp: String, record: SyncRecord)] = []
        for file in files {
            guard let id = file["id"] as? String, let shell = Self.shell(file) else { continue }
            remember(name: shell.recordName, id: id)
            if isOwnEcho(file) { continue }
            let stamp = ((file["modifiedTime"] as? String) ?? "").filter { $0.isLetter || $0.isNumber }
            shells.append((id, stamp, shell))
        }
        var out: [SyncRecord] = []
        for start in stride(from: 0, to: shells.count, by: Self.parallel) {
            let slice = shells[start..<min(start + Self.parallel, shells.count)]
            try await withThrowingTaskGroup(of: SyncRecord?.self) { group in
                for (id, stamp, shell) in slice {
                    group.addTask {
                        if shell.kind.isBlob || shell.isTombstone { return shell }
                        do {
                            var record = shell
                            record.payload = try await self.payload(id: id, stamp: stamp)
                            return record
                        } catch DriveError.notFound {
                            return nil
                        }
                    }
                }
                for try await record in group { if let record { out.append(record) } }
            }
        }
        // Everything arrived; a file edited later gets a new modified time,
        // so nothing parked here could be reused anyway.
        try? FileManager.default.removeItem(at: Self.pullCache)
        return out
    }

    /// Payloads fetched by a pull that has not finished yet. A cache, not
    /// data: losing it costs only the downloads again.
    private static var pullCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sync-pull", isDirectory: true)
    }

    private func payload(id: String, stamp: String) async throws -> Data {
        let parked = Self.pullCache.appendingPathComponent("\(id)-\(stamp)")
        if let data = try? Data(contentsOf: parked) { return data }
        let data = try await retrying { try await self.download(id: id, cellular: true) }
        try? FileManager.default.createDirectory(at: Self.pullCache, withIntermediateDirectories: true)
        try? data.write(to: parked, options: .atomic)
        return data
    }

    /// Another go at a request that failed on the NETWORK (no connection, a
    /// 5xx, a token that couldn't be fetched) or was rate limited: out of
    /// thousands, one of those is ordinary and no reason to throw the rest
    /// away. Anything else (404, no permission, a full Drive) is an answer.
    private func retrying<T>(_ body: () async throws -> T) async throws -> T {
        var wait: TimeInterval = 1
        for _ in 0..<Self.retries {
            do {
                return try await body()
            } catch SyncTransportError.network {
            } catch SyncTransportError.rateLimited(let seconds) {
                wait = max(wait, min(seconds, 30))
            }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            wait = min(wait * 2, 16)
        }
        return try await body()
    }

    /// Extra attempts per request: 1 + 2 + 4 + 8 s of waiting at most.
    private static let retries = 4

    // MARK: - Fetch

    func fetch(recordName: String, in zone: String) async throws -> SyncRecord? {
        try await fetch(recordNames: [recordName], in: zone)[recordName]
    }

    func fetch(recordNames: [String], in zone: String) async throws -> [String: SyncRecord] {
        guard !recordNames.isEmpty else { return [:] }
        let parent = try await zoneId(zone)
        var out: [String: SyncRecord] = [:]
        for start in stride(from: 0, to: recordNames.count, by: Self.parallel) {
            let slice = recordNames[start..<min(start + Self.parallel, recordNames.count)]
            try await withThrowingTaskGroup(of: (String, SyncRecord)?.self) { group in
                for name in slice {
                    group.addTask { try await self.fetchOne(name: name, parent: parent).map { (name, $0) } }
                }
                for try await pair in group { if let (name, record) = pair { out[name] = record } }
            }
        }
        return out
    }

    private func fetchOne(name: String, parent: String) async throws -> SyncRecord? {
        do {
            let file: [String: Any]
            if let id = remembered(name: name) {
                file = try await json(URLRequest(url: URL(string: "\(api)/files/\(id)?fields=\(fileFields)")!))
            } else {
                var c = URLComponents(string: "\(api)/files")!
                c.queryItems = [
                    .init(name: "spaces", value: "appDataFolder"),
                    .init(name: "q", value: "name = '\(name)' and '\(parent)' in parents and trashed = false"),
                    .init(name: "fields", value: "files(\(fileFields))"),
                ]
                guard let found = (try await json(URLRequest(url: c.url!))["files"] as? [[String: Any]])?.first
                else { return nil }
                file = found
            }
            guard let id = file["id"] as? String, var record = Self.shell(file) else { return nil }
            remember(name: name, id: id)
            if record.isTombstone { return record }
            let cellular = !record.kind.isBlob || allowsCellularForBlobs
            if record.kind.isBlob {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drive-\(UUID().uuidString).blob")
                try await download(id: id, cellular: cellular).write(to: url, options: .atomic)
                record.assetURL = url
            } else {
                record.payload = try await download(id: id, cellular: cellular)
            }
            return record
        } catch DriveError.notFound {
            return nil
        }
    }

    /// The engine hands over the change tags it already holds before asking
    /// for blobs by name, so a fetch needs no lookup per file.
    func noteServerTags(_ tags: [String: Data]) {
        for (name, data) in tags {
            let id = String(decoding: data, as: UTF8.self)
            if !id.isEmpty { remember(name: name, id: id) }
        }
    }

    // MARK: - Mapping

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// Android's `appProperties`, key for key (`DriveTransport.saveOne`).
    static func properties(for r: SyncRecord) -> [String: String] {
        [
            "k": r.kind.rawValue,
            "l": r.lang ?? "",
            "s": String(r.schema),
            "m": String(millis(r.modifiedAt)),
            "d": r.deletedAt.map { String(millis($0)) } ?? "",
            "z": String(r.size),
        ]
    }

    private static func prop(_ file: [String: Any], _ key: String) -> String? {
        (file["appProperties"] as? [String: Any])?[key] as? String
    }

    static func shell(_ file: [String: Any]) -> SyncRecord? {
        guard let raw = prop(file, "k"), let kind = SyncKind(rawValue: raw),
              !excludedKinds.contains(kind),
              let key = file["description"] as? String else { return nil }
        let modified = prop(file, "m").flatMap(Int64.init).map { Date(timeIntervalSince1970: Double($0) / 1000) }
            ?? .distantPast
        let deleted = prop(file, "d").flatMap { $0.isEmpty ? nil : Int64($0) }
            .map { Date(timeIntervalSince1970: Double($0) / 1000) }
        return SyncRecord(
            kind: kind, key: key,
            lang: prop(file, "l").flatMap { $0.isEmpty ? nil : $0 },
            size: prop(file, "z").flatMap(Int.init) ?? 0,
            schema: prop(file, "s").flatMap(Int.init) ?? SyncSchema.version,
            modifiedAt: modified, deletedAt: deleted,
            systemFields: (file["id"] as? String).map { Data($0.utf8) })
    }

    /// A save's answer: its id, with the md5 noted for `isOwnEcho`.
    private func noteOwnWrite(_ file: [String: Any]) throws -> String {
        guard let fileId = file["id"] as? String else { throw SyncTransportError.other("drive: no file id") }
        lock.lock(); defer { lock.unlock() }
        if let md5 = file["md5Checksum"] as? String {
            if ownWrites.count >= Self.maxOwnWrites { ownWrites.removeAll() }
            ownWrites[fileId] = md5
        } else {
            ownWrites[fileId] = nil
        }
        return fileId
    }

    /// The file still holds exactly what this device last wrote to it.
    private func isOwnEcho(_ file: [String: Any]) -> Bool {
        guard let id = file["id"] as? String, let md5 = file["md5Checksum"] as? String else { return false }
        lock.lock(); defer { lock.unlock() }
        return ownWrites[id] == md5
    }

    private func remember(name: String, id: String) {
        lock.lock(); defer { lock.unlock() }
        idByName[name] = id
        nameById[id] = name
    }

    private func remembered(name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return idByName[name]
    }

    private func forget(id: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let name = nameById.removeValue(forKey: id) else { return nil }
        // A duplicate removed by `dedupe` (here or on Android) shares its
        // name with the file that stays; only the surviving id is current.
        if idByName[name] == id { idByName[name] = nil } else { return nil }
        return name
    }

    // MARK: - HTTP

    private enum DriveError: Error { case notFound }

    private func download(id: String, cellular: Bool) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(api)/files/\(id)?alt=media")!)
        request.allowsCellularAccess = cellular
        return try await send(request).0
    }

    private func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await send(request)
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// One request with the current token; a 401 refreshes once.
    private func send(_ base: URLRequest, retried: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let token: String
        switch await GoogleDriveAuth.accessToken(userId: userId, force: retried) {
        case .token(let t): token = t
        case .needsSignIn: throw SyncTransportError.notSignedIn
        case .offline: throw SyncTransportError.network
        }
        var request = base
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncTransportError.network
        }
        guard let http = response as? HTTPURLResponse else { throw SyncTransportError.network }
        if (200..<300).contains(http.statusCode) { return (data, http) }
        let text = String(decoding: data, as: UTF8.self)
        switch http.statusCode {
        case 401:
            if retried { throw SyncTransportError.notSignedIn }
            return try await send(base, retried: true)
        case 404: throw DriveError.notFound
        case 410: throw SyncTransportError.tokenExpired
        case 429:
            throw SyncTransportError.rateLimited(
                http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 30)
        case 403:
            if text.contains("storageQuotaExceeded") || (text.contains("quotaExceeded") && text.contains("storage")) {
                throw SyncTransportError.quotaExceeded
            }
            if text.contains("ateLimitExceeded") { throw SyncTransportError.rateLimited(30) }
            if text.contains("insufficientPermissions") || text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") {
                throw SyncTransportError.notSignedIn
            }
            throw SyncTransportError.other("drive 403")
        case 500...599: throw SyncTransportError.network
        default: throw SyncTransportError.other("drive \(http.statusCode)")
        }
    }
}
