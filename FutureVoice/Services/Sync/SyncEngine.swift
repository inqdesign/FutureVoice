import Foundation
import UIKit

/// Keeps this device's practice and the learner's other devices' practice
/// the same, through their iCloud — opt-in, per app account.
///
/// Shape, in one paragraph: the stores stay exactly what they are (JSON
/// files rewritten whole); the engine DIFFS them against `SyncIndex` to find
/// what changed, pushes those items one record each, pulls the other
/// devices' records through one merge rule per kind (`SyncKindRegistry`),
/// and lays the merged set back into the file. Audio rides as assets,
/// items first so a second device is useful within a minute. A deletion is
/// a tombstone record, never a missing one, so the two sides can't
/// resurrect each other's deletions.
///
/// The loop guard is in `apply`: the index is updated to the MERGED result
/// before the file is written, so the next diff sees nothing to push unless
/// the merge produced something the server doesn't have (`needsPush`).
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case off
        case idle
        case syncing
        case paused(Pause)
        case failed(String)
    }

    enum Pause: Equatable {
        case noAccount
        case restricted
        case quotaExceeded
        case zoneMissing
        case offline
    }

    struct Progress: Equatable {
        enum Phase: Equatable { case indexing, pushing, pulling, uploadingAudio, downloadingAudio }
        var phase: Phase
        var done: Int
        var total: Int
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var progress: Progress?
    @Published private(set) var lastSyncAt: Date?
    /// Items still to push and audio still to move — what the settings row
    /// shows so "it's syncing" is a number, not a spinner.
    @Published private(set) var pendingItems = 0
    @Published private(set) var pendingAudio = 0
    @Published private(set) var wantedAudio = 0
    /// A record from a newer build is on file; this build can't carry it.
    @Published private(set) var needsAppUpdate = false

    /// Fired after a pull wrote files, with the kinds it touched — AppState
    /// re-reads its published copies from there.
    var onApplied: ((Set<SyncKind>) -> Void)?

    var transport: SyncTransport
    private(set) var userId: String?
    private var index: SyncIndex?

    /// How much of a pass to run. `.items` is what a screen waits on — the
    /// second device's "Continue", the Me toggle — and it ends the moment the
    /// talks, cards and words are in step; audio then follows in an
    /// `.everything` pass nobody waits on.
    enum Scope { case items, everything }

    private var dirty: Set<SyncKind> = []
    private var debounce: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var rerunRequested = false
    private var rerunScope: Scope = .items
    /// Blobs the UI asked for by name — fetched before everything else.
    private var requestedBlobs: [String] = []

    /// How long after a store write the push waits, so a burst of writes
    /// (a talk ending mints cards, words and a summary in one go) is one
    /// push.
    static let debounceSeconds: TimeInterval = 3

    static let itemBatch = 150
    static let blobBatch = 20

    /// How many records a push needs before it is worth an analytics event.
    /// See the note at the capture in `push`.
    static let reportPushFrom = 20

    init(transport: SyncTransport = CloudKitTransport()) {
        self.transport = transport
    }

    // MARK: - Account

    var isEnabled: Bool {
        guard let userId else { return false }
        return SyncStore.isEnabled(userId: userId)
    }

    /// The signed-in app account, or nil (signed out / anonymous). Sync
    /// follows the account: a different user gets a different index and zone.
    func setUser(_ id: String?) {
        // Remembered for a background launch (`SyncBackground`), where iOS
        // runs the task before any scene — and so before auth — is up.
        UserDefaults.standard.set(id, forKey: Self.lastUserKey)
        guard id != userId else { return }
        running?.cancel()
        running = nil
        userId = id
        index = nil
        dirty = []
        guard let id, SyncStore.isEnabled(userId: id) else {
            status = .off
            return
        }
        index = SyncIndex(userId: id)
        status = .idle
        refreshCounts()
        // Re-registers this install with APNs every launch (the token can be
        // reissued) and re-asks for the zone subscription if it was never
        // confirmed. Both are cheap and neither blocks the pass below.
        if let zone = zoneName {
            SyncPush.activate(zone: zone, userId: id, transport: transport)
        }
        requestSync(kinds: nil)
    }

    var zoneName: String? { userId.map { "nawana-\($0)" } }

    private static let lastUserKey = "futurevoice.sync.lastUserId"

    /// A background launch has no auth observer yet: pick up the account the
    /// app last ran under. Signing out clears it (`setUser(nil)`).
    func restoreLastUserIfNeeded() {
        guard userId == nil, let id = UserDefaults.standard.string(forKey: Self.lastUserKey) else { return }
        setUser(id)
    }

    /// Whether the account already has practice in the cloud — the second
    /// device's question. Nil when it can't be answered (no iCloud, offline).
    func cloudHasData() async -> Bool? {
        guard let zone = zoneName else { return nil }
        guard await transport.accountAvailable() == .available else { return nil }
        return try? await transport.zoneExists(zone)
    }

    // MARK: - Enable / disable

    enum EnableError: LocalizedError {
        case noAccount
        case restricted
        case notSignedIn
        case transport(SyncTransportError)

        var errorDescription: String? {
            switch self {
            case .noAccount: return explain("Sign in to iCloud in Settings first, then try again.")
            case .restricted: return explain("iCloud isn't available on this device.")
            case .notSignedIn: return explain("You're signed out. Sign in again, then try once more.")
            case .transport(let e): return SyncEngine.describe(e)
            }
        }
    }

    /// Turns sync on for the signed-in account: creates the zone, then runs
    /// the first full pass (items, then audio) with progress. Resumable — the
    /// index remembers what went up, so a killed first pass picks up where it
    /// stopped on the next launch.
    func enable() async throws {
        guard let userId, let zone = zoneName else { throw EnableError.notSignedIn }
        switch await transport.accountAvailable() {
        case .available: break
        case .noAccount, .unknown: throw EnableError.noAccount
        case .restricted: throw EnableError.restricted
        }
        do {
            try await transport.ensureZone(zone)
        } catch let e as SyncTransportError {
            throw EnableError.transport(e)
        }
        SyncStore.setEnabled(true, userId: userId)
        index = SyncIndex(userId: userId)
        status = .idle
        // The zone exists as of the line above, which is the earliest a
        // subscription can be attached to it.
        SyncPush.activate(zone: zone, userId: userId, transport: transport)
        Analytics.capture("sync_enabled")
        // Through the one-pass-at-a-time door: calling `runSync` straight
        // let a foreground pass start beside this one on the same index.
        // Items only — the caller's screen is waiting, and a second device
        // is useful the moment the talks are here. Audio follows in a pass
        // nobody waits on, newest talk first.
        await syncAndWait(kinds: nil, scope: .items)
        if hasBackgroundWork { requestSync(kinds: nil) }
    }

    /// Stops syncing. Nothing is deleted anywhere: what's on this device
    /// stays, what's in iCloud stays.
    func disable() {
        guard let userId else { return }
        running?.cancel()
        running = nil
        debounce?.cancel()
        SyncStore.setEnabled(false, userId: userId)
        // Stops this device being woken. The account's subscription stays —
        // the learner turned sync off HERE, and their other device may still
        // be syncing; only "Delete from iCloud" speaks for all of them.
        SyncPush.deactivate(userId: userId)
        index = nil
        status = .off
        progress = nil
        Analytics.capture("sync_disabled")
    }

    /// Removes the account's zone — every synced record and asset. Local
    /// data is untouched. Other devices notice on their next pass
    /// (`zoneMissing`) and switch themselves off.
    func deleteFromCloud() async throws {
        guard let zone = zoneName else { return }
        disable()
        // Before the zone: this is the one caller entitled to speak for every
        // device of the account, and a subscription whose zone is gone would
        // otherwise sit on the server pushing nothing.
        try? await transport.unsubscribeFromZoneChanges(
            subscriptionID: SyncPush.subscriptionID(for: zone))
        do {
            try await transport.deleteZone(zone)
        } catch let e as SyncTransportError {
            throw EnableError.transport(e)
        }
        if let userId { SyncIndex(userId: userId).removeAll() }
        Analytics.capture("sync_deleted_cloud")
    }

    // MARK: - Triggers

    /// Nonisolated so a store's write funnel can call it from anywhere.
    nonisolated static func noteChanged(_ kind: SyncKind) {
        Task { @MainActor in shared.markDirty(kind) }
    }

    func markDirty(_ kind: SyncKind) {
        guard isEnabled else { return }
        dirty.insert(kind)
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let kinds = self.dirty
            self.dirty = []
            self.requestSync(kinds: kinds)
        }
    }

    func foregrounded() {
        guard isEnabled else { return }
        requestSync(kinds: nil)
    }

    func backgrounded() {
        guard isEnabled, !dirty.isEmpty else { return }
        debounce?.cancel()
        let kinds = dirty
        dirty = []
        requestSync(kinds: kinds)
    }

    /// "Sync now" in settings.
    func syncNow() {
        guard isEnabled else { return }
        requestSync(kinds: nil)
    }

    /// One pass at a time; a request during a pass runs once more after it.
    func requestSync(kinds: Set<SyncKind>?, scope: Scope = .everything) {
        guard isEnabled else { return }
        if running != nil {
            rerunRequested = true
            if scope == .everything { rerunScope = .everything }
            if let kinds { dirty.formUnion(kinds) }
            return
        }
        running = Task { [weak self] in
            guard let self else { return }
            // Leaving the app mid-pass would otherwise suspend it within
            // seconds; this buys the ~30 s iOS grants to finish the batch in
            // flight. On expiry the pass is cancelled — every batch saves
            // the index, so the next pass resumes where this one stopped.
            let assertion = BackgroundAssertion.begin { [weak self] in self?.running?.cancel() }
            defer { assertion.end() }
            await self.runSync(kinds: kinds, scope: scope)
            self.running = nil
            if self.rerunRequested {
                self.rerunRequested = false
                let more = self.dirty
                let again = self.rerunScope
                self.dirty = []
                self.rerunScope = .items
                self.requestSync(kinds: more.isEmpty ? nil : more, scope: again)
            }
        }
    }

    /// Requests a pass and returns once it — and any rerun it queued — is
    /// over. Used by `enable` (the settings row waits on it) and by the
    /// background tasks.
    func syncAndWait(kinds: Set<SyncKind>?, scope: Scope = .everything) async {
        requestSync(kinds: kinds, scope: scope)
        await waitUntilIdle()
    }

    /// Returns once no pass is running — including any the last one queued.
    func waitUntilIdle() async {
        while let task = running { await task.value }
    }

    /// A background task's time is up.
    func cancelRunning() {
        running?.cancel()
    }

    /// Anything left that a background pass could finish.
    var hasBackgroundWork: Bool {
        refreshCounts()
        return pendingItems + pendingAudio + wantedAudio > 0
    }

    // MARK: - The pass

    /// pull → push (items) → [conflicts: pull → push] → push audio → fetch
    /// wanted audio. `kinds == nil` diffs everything.
    func runSync(kinds: Set<SyncKind>?, scope: Scope = .everything) async {
        guard let index, let zone = zoneName else { return }
        switch await transport.accountAvailable() {
        case .available: break
        case .noAccount, .unknown: status = .paused(.noAccount); return
        case .restricted: status = .paused(.restricted); return
        }
        status = .syncing
        defer { progress = nil; refreshCounts() }
        do {
            try await pull(index: index, zone: zone)
            let itemKinds = (kinds ?? Set(SyncKind.allCases)).filter { !$0.isBlob }
            var conflicts = try await push(kinds: itemKinds, index: index, zone: zone)
            if conflicts {
                try await pull(index: index, zone: zone)
                conflicts = try await push(kinds: itemKinds, index: index, zone: zone)
            }
            if scope == .everything {
                let blobKinds = (kinds ?? Set(SyncKind.allCases)).filter { $0.isBlob }
                _ = try await push(kinds: blobKinds, index: index, zone: zone)
                try await downloadWanted(index: index, zone: zone)
            }
            index.save()
            lastSyncAt = Date()
            status = .idle
        } catch let e as SyncTransportError {
            index.save()
            handle(e)
        } catch is CancellationError {
            index.save()
            status = .idle
        } catch {
            index.save()
            status = .failed(error.localizedDescription)
            Analytics.capture("sync_error", ["reason": error.localizedDescription])
        }
    }

    private func handle(_ error: SyncTransportError) {
        switch error {
        case .zoneMissing:
            // Deleted from another device, or from Settings → iCloud. Stop,
            // forget the server's tags, keep every local file.
            index?.forgetServer()
            if let userId {
                SyncStore.setEnabled(false, userId: userId)
                // Sync is off on this device now, so the wakes have nothing
                // to run; the subscription went with the zone anyway.
                SyncPush.deactivate(userId: userId)
            }
            index = nil
            status = .paused(.zoneMissing)
        case .quotaExceeded:
            status = .paused(.quotaExceeded)
        case .network:
            status = .paused(.offline)
        case .notSignedIn:
            status = .paused(.noAccount)
        case .rateLimited(let seconds):
            status = .idle
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.requestSync(kinds: nil)
            }
        case .tokenExpired:
            index?.state.changeToken = nil
            index?.save()
            status = .idle
            requestSync(kinds: nil)
        case .limitExceeded, .other:
            status = .failed(Self.describe(error))
        }
        Analytics.capture("sync_error", ["reason": Self.describe(error)])
    }

    nonisolated static func describe(_ error: SyncTransportError) -> String {
        switch error {
        case .tokenExpired: return "token expired"
        case .zoneMissing: return "zone missing"
        case .quotaExceeded: return "quota exceeded"
        case .rateLimited: return "rate limited"
        case .limitExceeded: return "limit exceeded"
        case .network: return "offline"
        case .notSignedIn: return "not signed in"
        case .other(let s): return s
        }
    }

    // MARK: - Pull

    private func pull(index: SyncIndex, zone: String) async throws {
        progress = Progress(phase: .pulling, done: 0, total: 0)
        var batch: SyncChangeBatch
        do {
            batch = try await transport.changes(in: zone, since: index.state.changeToken)
        } catch SyncTransportError.tokenExpired {
            index.state.changeToken = nil
            batch = try await transport.changes(in: zone, since: nil)
        }
        try Task.checkCancellation()

        // Records the server lost outright (never by this app). The index
        // forgets them so a re-push isn't refused for a missing record.
        for name in batch.deleted where index[name] != nil {
            var entry = index[name]!
            entry.systemFields = nil
            entry.pushedAt = nil
            entry.needsPush = !entry.isDeleted
            index[name] = entry
        }

        // Group by (kind, lang) in registry order.
        var groups: [String: [SyncRecord]] = [:]
        for record in batch.changed {
            groups["\(record.kind.rawValue)|\(record.lang ?? "")", default: []].append(record)
        }
        var applied: Set<SyncKind> = []
        var cascades: [SyncCascade] = []
        var skipped = false
        let now = Date()
        for handler in SyncKindRegistry.all {
            let langs = groups.keys.filter { $0.hasPrefix(handler.kind.rawValue + "|") }
            for groupKey in langs.sorted() {
                guard let records = groups[groupKey] else { continue }
                let lang = records.first?.lang
                if handler.kind.isBlob {
                    applyBlobChanges(records, handler: handler, index: index, now: now)
                    continue
                }
                guard let local = handler.read(lang: lang) else {
                    skipped = true
                    continue
                }
                let outcome = try await apply(records, local: local, handler: handler, lang: lang,
                                              index: index, now: now)
                if outcome.wrote { applied.insert(handler.kind) }
                cascades += outcome.cascades
            }
        }
        for cascade in cascades { await run(cascade, index: index) }
        if !skipped { index.state.changeToken = batch.token }
        index.state.lastPullAt = now
        index.save()
        if !applied.isEmpty {
            onApplied?(applied)
            Analytics.capture("sync_pull", ["records": batch.changed.count, "kinds": applied.count])
        }
    }

    private struct ApplyOutcome {
        var wrote = false
        var cascades: [SyncCascade] = []
    }

    /// Merges one (kind, lang) group of remote records into the local file.
    /// The index entry is written BEFORE the file — see the class note.
    private func apply(_ records: [SyncRecord], local: SyncSnapshot,
                       handler: any SyncKindHandler, lang: String?,
                       index: SyncIndex, now: Date) async throws -> ApplyOutcome {
        var merged: [String: SyncItem] = [:]
        for (key, payload) in local {
            let at = index.entry(kind: handler.kind, lang: lang, key: key)?.observedAt ?? now
            merged[key] = SyncItem(payload: payload, at: at)
        }
        var outcome = ApplyOutcome()
        for var record in records {
            try Task.checkCancellation()
            if record.payload == nil, !record.isTombstone {
                // Oversized payload lives in an asset on the record.
                guard let full = try await transport.fetch(recordName: record.recordName, in: zoneName ?? "")
                else { continue }
                record = full
            }
            let key = record.key
            let previous = local[key]
            let existing = index.entry(kind: handler.kind, lang: lang, key: key)
            let localSide = previous.map { SyncSide(payload: $0, at: existing?.observedAt ?? now, deleted: false) }
                ?? existing.flatMap { $0.isDeleted ? SyncSide(payload: nil, at: $0.deletedAt ?? .distantPast, deleted: true) : nil }
            let remoteSide = SyncSide(payload: record.payload, at: record.deletedAt ?? record.modifiedAt,
                                      deleted: record.isTombstone)
            let frozen = record.schema > SyncSchema.version
            if frozen { needsAppUpdate = true }
            let result = handler.merge(local: localSide, remote: remoteSide)

            let matchesServer = record.isTombstone ? (result == nil) : (result == record.payload)
            var entry = SyncIndex.Entry(
                kind: handler.kind, lang: lang, key: key,
                hash: result.map(SyncCanonical.hash) ?? "",
                observedAt: max(localSide?.at ?? .distantPast, remoteSide.at),
                pushedAt: matchesServer ? now : nil,
                needsPush: !matchesServer && !frozen,
                deletedAt: result == nil ? (record.deletedAt ?? now) : nil,
                systemFields: record.systemFields,
                frozen: frozen)
            entry.size = record.size
            index.set(entry)

            if let result {
                if previous != result {
                    merged[key] = SyncItem(payload: result, at: entry.observedAt)
                    outcome.wrote = true
                }
            } else if previous != nil {
                merged.removeValue(forKey: key)
                outcome.wrote = true
                outcome.cascades += handler.cascade(deletedKey: key, lang: lang, previous: previous)
            }
        }
        if outcome.wrote {
            try handler.write(merged, lang: lang)
        }
        return outcome
    }

    /// A blob's bytes never merge: a file this device has is the file; one
    /// it lacks is wanted; a tombstone removes it.
    private func applyBlobChanges(_ records: [SyncRecord], handler: any SyncKindHandler,
                                  index: SyncIndex, now: Date) {
        guard let blob = handler as? BlobKind else { return }
        let local = blob.read(lang: nil) ?? [:]
        for record in records {
            let key = record.key
            var entry = index.entry(kind: blob.kind, lang: nil, key: key)
                ?? SyncIndex.Entry(kind: blob.kind, lang: nil, key: key, hash: "", observedAt: now)
            entry.systemFields = record.systemFields
            entry.size = record.size
            if record.isTombstone {
                if local[key] != nil {
                    try? FileManager.default.removeItem(at: blob.fileURL(key))
                }
                entry.deletedAt = record.deletedAt ?? now
                entry.wanted = false
                entry.needsPush = false
                entry.pushedAt = now
                entry.hash = ""
            } else if let fingerprint = local[key] {
                entry.hash = String(decoding: fingerprint, as: UTF8.self)
                entry.deletedAt = nil
                entry.wanted = false
                entry.needsPush = false
                entry.pushedAt = now
            } else {
                entry.deletedAt = nil
                entry.wanted = true
                entry.needsPush = false
                entry.pushedAt = now
                // When the audio was made, not when this device heard of it
                // — a first pull hears of everything at once, and the
                // download queue is sorted on this so the newest talk's
                // audio lands first.
                entry.observedAt = record.modifiedAt
            }
            index.set(entry)
        }
    }

    private func run(_ cascade: SyncCascade, index: SyncIndex) async {
        switch cascade {
        case let .sessionDeleted(sessionId, turnIds, lang):
            if let drill = SyncKindRegistry.handler(for: .drill), let cards = drill.read(lang: lang) {
                var kept: [String: SyncItem] = [:]
                var removed = false
                for (key, payload) in cards {
                    if let card = try? SyncCanonical.decode(DrillCard.self, from: payload),
                       card.sourceSessionId == sessionId {
                        removed = true
                        continue
                    }
                    let at = index.entry(kind: .drill, lang: lang, key: key)?.observedAt ?? Date()
                    kept[key] = SyncItem(payload: payload, at: at)
                }
                if removed {
                    try? drill.write(kept, lang: lang)
                    dirty.insert(.drill)
                }
            }
            for id in turnIds { TurnAudioStore.shared.delete(turnId: id) }
            if !turnIds.isEmpty { dirty.insert(.blobTurn) }
        case let .deleteFile(kind, key):
            if let blob = SyncKindRegistry.handler(for: kind) as? BlobKind {
                try? FileManager.default.removeItem(at: blob.fileURL(key))
                dirty.insert(kind)
            }
        }
    }

    // MARK: - Push

    /// Diffs the given kinds against the index and pushes what moved.
    /// Returns true if any record was refused as a conflict (the server has
    /// a newer copy — a pull will bring it through the merge).
    private func push(kinds: Set<SyncKind>, index: SyncIndex, zone: String) async throws -> Bool {
        var records: [SyncRecord] = []
        let now = Date()
        var blobURLs: [String: URL] = [:]
        for handler in SyncKindRegistry.all where kinds.contains(handler.kind) {
            let langs: [String?] = handler.kind.isLanguageScoped
                ? Array(Set(LanguageScope.enrolled).union(index.languages(for: handler.kind))).sorted().map { $0 }
                : [nil]
            for lang in langs {
                try Task.checkCancellation()
                guard let snapshot = handler.read(lang: lang) else { continue }
                diff(snapshot, handler: handler, lang: lang, index: index, now: now)
                for entry in index.entries(kind: handler.kind, lang: lang) where entry.needsPush && !entry.frozen {
                    var record = SyncRecord(kind: entry.kind, key: entry.key, lang: entry.lang,
                                            modifiedAt: entry.observedAt, deletedAt: entry.deletedAt,
                                            systemFields: entry.systemFields)
                    if !entry.isDeleted {
                        if handler.kind.isBlob, let blob = handler as? BlobKind {
                            let url = blob.fileURL(entry.key)
                            record.assetURL = url
                            record.size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                            blobURLs[record.recordName] = url
                        } else {
                            guard let payload = snapshot[entry.key] else { continue }
                            record.payload = payload
                            record.size = payload.count
                        }
                    }
                    records.append(record)
                }
            }
        }
        guard !records.isEmpty else { return false }

        let isBlobPush = records.first?.kind.isBlob == true
        progress = Progress(phase: isBlobPush ? .uploadingAudio : .pushing, done: 0, total: records.count)
        var conflicts = false
        var done = 0
        var batchSize = isBlobPush ? Self.blobBatch : Self.itemBatch
        var cursor = 0
        while cursor < records.count {
            try Task.checkCancellation()
            let slice = Array(records[cursor..<min(cursor + batchSize, records.count)])
            let outcomes: [String: SyncSaveOutcome]
            do {
                outcomes = try await transport.save(slice, in: zone)
            } catch SyncTransportError.limitExceeded where batchSize > 1 {
                batchSize = max(1, batchSize / 2)
                continue
            }
            var quota = false
            for record in slice {
                guard var entry = index[record.recordName] else { continue }
                switch outcomes[record.recordName] {
                case .saved(let fields)?:
                    entry.systemFields = fields
                    entry.pushedAt = now
                    entry.needsPush = false
                    index[record.recordName] = entry
                case .conflict?:
                    conflicts = true
                case .failed(let error)?:
                    if error == .quotaExceeded { quota = true }
                    if error == .zoneMissing { throw error }
                case nil:
                    break
                }
            }
            done += slice.count
            cursor += slice.count
            progress = Progress(phase: isBlobPush ? .uploadingAudio : .pushing, done: done, total: records.count)
            index.save()
            if quota { throw SyncTransportError.quotaExceeded }
        }
        index.state.lastPushAt = now
        // A pass per CHANGE is the norm here — a write debounces into its own
        // pass, and a talk's turn audio is one file per pass — so capturing
        // every push made the first learner who turned sync on 427 events in a
        // day (measured 2026-09-26; 363 of them carried a single record). What
        // a diagnosis actually asks is whether the BIG pushes landed and
        // whether devices are fighting, so only those are recorded; `sync_error`
        // is untouched and keeps every failure.
        if records.count >= Self.reportPushFrom || conflicts {
            Analytics.capture("sync_push", ["records": records.count, "blobs": isBlobPush, "conflicts": conflicts])
        }
        return conflicts
    }

    /// Compares a snapshot with the index: new and changed items are marked
    /// for push, and anything the index knows that the file no longer holds
    /// becomes a tombstone.
    private func diff(_ snapshot: SyncSnapshot, handler: any SyncKindHandler, lang: String?,
                      index: SyncIndex, now: Date) {
        for (key, payload) in snapshot {
            let hash = handler.kind.isBlob
                ? String(decoding: payload, as: UTF8.self)
                : SyncCanonical.hash(payload)
            if var entry = index.entry(kind: handler.kind, lang: lang, key: key) {
                guard !entry.frozen else { continue }
                if entry.hash != hash || entry.isDeleted {
                    entry.hash = hash
                    entry.observedAt = now
                    entry.deletedAt = nil
                    entry.wanted = false
                    entry.needsPush = true
                    index.set(entry)
                }
            } else {
                index.set(SyncIndex.Entry(kind: handler.kind, lang: lang, key: key, hash: hash,
                                          observedAt: now, needsPush: true))
            }
        }
        for var entry in index.entries(kind: handler.kind, lang: lang)
        where snapshot[entry.key] == nil && !entry.isDeleted && !entry.frozen && !entry.wanted {
            entry.deletedAt = now
            entry.observedAt = now
            entry.hash = ""
            entry.needsPush = true
            index.set(entry)
        }
    }

    // MARK: - Audio downloads

    /// Fetches blobs the server has and this device doesn't, requested ones
    /// first, then newest talk first. `blobFetchBatch` per round trip: one
    /// fetch per file was a full round trip per turn of audio, and a
    /// first sync of a few hundred took the afternoon.
    static let blobFetchBatch = 10

    private func downloadWanted(index: SyncIndex, zone: String) async throws {
        var wanted = index.wantedBlobs
        guard !wanted.isEmpty else { return }
        let requested = Set(requestedBlobs)
        wanted.sort { a, b in
            let ra = requested.contains(a.recordName), rb = requested.contains(b.recordName)
            if ra != rb { return ra }
            return a.observedAt > b.observedAt
        }
        let total = wanted.count
        var done = 0
        var cursor = 0
        while cursor < wanted.count {
            try Task.checkCancellation()
            progress = Progress(phase: .downloadingAudio, done: done, total: total)
            let slice = Array(wanted[cursor..<min(cursor + Self.blobFetchBatch, wanted.count)])
            cursor += slice.count
            let fetched: [String: SyncRecord]
            do {
                fetched = try await transport.fetch(recordNames: slice.map(\.recordName), in: zone)
            } catch SyncTransportError.other {
                done += slice.count
                continue
            }
            for entry in slice {
                land(fetched[entry.recordName], for: entry, index: index)
                done += 1
            }
            index.save()
            refreshCounts()
        }
    }

    /// Moves one fetched blob into place, or forgets one the server no
    /// longer has.
    private func land(_ record: SyncRecord?, for entry: SyncIndex.Entry, index: SyncIndex) {
        guard let blob = SyncKindRegistry.handler(for: entry.kind) as? BlobKind else { return }
        guard let record, let temp = record.assetURL else {
            // Gone from the server; forget it.
            var e = entry
            e.wanted = false
            index.set(e)
            return
        }
        let dest = blob.fileURL(entry.key)
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: temp, to: dest)
        } catch {
            return
        }
        var e = entry
        e.wanted = false
        e.needsPush = false
        e.pushedAt = Date()
        if let attrs = try? fm.attributesOfItem(atPath: dest.path),
           let size = attrs[.size] as? Int, let mtime = attrs[.modificationDate] as? Date {
            e.hash = SyncCanonical.blobFingerprint(size: size, modifiedAt: mtime)
        }
        index.set(e)
        requestedBlobs.removeAll { $0 == entry.recordName }
    }

    enum BlobState { case local, queued, absent }

    /// Whether a file the UI wants to play is here, on its way, or unknown.
    func blobState(kind: SyncKind, key: String) -> BlobState {
        if let blob = SyncKindRegistry.handler(for: kind) as? BlobKind,
           FileManager.default.fileExists(atPath: blob.fileURL(key).path) {
            return .local
        }
        if let entry = index?.entry(kind: kind, lang: nil, key: key), entry.wanted { return .queued }
        return .absent
    }

    /// Move one blob to the front of the download queue.
    func requestBlob(kind: SyncKind, key: String) {
        let name = SyncRecord.recordName(kind: kind, lang: nil, key: key)
        requestedBlobs.removeAll { $0 == name }
        requestedBlobs.insert(name, at: 0)
        requestSync(kinds: [])
    }

    // MARK: - Counts

    private func refreshCounts() {
        guard let index else {
            pendingItems = 0; pendingAudio = 0; wantedAudio = 0
            return
        }
        let pending = index.pendingPush
        pendingItems = pending.filter { !$0.kind.isBlob }.count
        pendingAudio = pending.filter { $0.kind.isBlob }.count
        wantedAudio = index.wantedBlobs.count
    }
}


/// `UIApplication.beginBackgroundTask`, ended exactly once.
@MainActor
private final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    static func begin(onExpire: @escaping @MainActor () -> Void) -> BackgroundAssertion {
        let a = BackgroundAssertion()
        a.id = UIApplication.shared.beginBackgroundTask(withName: "sync") { [weak a] in
            MainActor.assumeIsolated {
                onExpire()
                a?.end()
            }
        }
        return a
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
