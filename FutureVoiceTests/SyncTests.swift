import XCTest
@testable import FutureVoice

/// iCloud standing in as a dictionary. Enforces the one server rule the
/// engine leans on — a save with a stale change tag is a conflict, never an
/// overwrite — and can be told to fail like the real thing.
final class InMemorySyncTransport: SyncTransport {
    struct Stored {
        var record: SyncRecord
        var tag: Int
        var seq: Int
    }

    var zones: Set<String> = []
    var records: [String: Stored] = [:]
    private var seq = 0
    var account: SyncAccountState = .available
    /// Subscription ids the server holds — the silent-push side.
    var subscriptions: Set<String> = []
    /// Errors to throw on the next call of each operation, once.
    var nextSaveError: SyncTransportError?
    var nextChangesError: SyncTransportError?
    var saves = 0

    func accountAvailable() async -> SyncAccountState { account }

    func subscribeToZoneChanges(_ zone: String, subscriptionID: String) async throws {
        subscriptions.insert(subscriptionID)
    }

    func unsubscribeFromZoneChanges(subscriptionID: String) async throws {
        subscriptions.remove(subscriptionID)
    }

    func ensureZone(_ zone: String) async throws { zones.insert(zone) }
    func zoneExists(_ zone: String) async throws -> Bool { zones.contains(zone) }
    func deleteZone(_ zone: String) async throws {
        zones.remove(zone)
        records = [:]
    }

    private func tagData(_ tag: Int) -> Data { Data("tag:\(tag)".utf8) }
    private func tag(from data: Data?) -> Int? {
        guard let data, let s = String(data: data, encoding: .utf8), s.hasPrefix("tag:") else { return nil }
        return Int(s.dropFirst(4))
    }

    func save(_ records: [SyncRecord], in zone: String) async throws -> [String: SyncSaveOutcome] {
        saves += 1
        if let e = nextSaveError { nextSaveError = nil; throw e }
        guard zones.contains(zone) else { throw SyncTransportError.zoneMissing }
        var out: [String: SyncSaveOutcome] = [:]
        for var record in records {
            let name = record.recordName
            if let existing = self.records[name], tag(from: record.systemFields) != existing.tag {
                out[name] = .conflict
                continue
            }
            seq += 1
            let newTag = (self.records[name]?.tag ?? 0) + 1
            // The server keeps a copy of the asset; the caller's temp file
            // may be gone by the time it's fetched.
            if let url = record.assetURL, let data = try? Data(contentsOf: url) {
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("srv-\(UUID().uuidString)")
                try? data.write(to: copy)
                record.assetURL = copy
            }
            record.systemFields = tagData(newTag)
            self.records[name] = Stored(record: record, tag: newTag, seq: seq)
            out[name] = .saved(systemFields: tagData(newTag))
        }
        return out
    }

    func changes(in zone: String, since token: Data?) async throws -> SyncChangeBatch {
        if let e = nextChangesError { nextChangesError = nil; throw e }
        guard zones.contains(zone) else { throw SyncTransportError.zoneMissing }
        let since = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        var batch = SyncChangeBatch()
        for stored in records.values.sorted(by: { $0.seq < $1.seq }) where stored.seq > since {
            var r = stored.record
            r.assetURL = nil   // a listing never carries the asset
            batch.changed.append(r)
        }
        batch.token = Data(String(seq).utf8)
        return batch
    }

    func fetch(recordName: String, in zone: String) async throws -> SyncRecord? {
        records[recordName]?.record
    }
}

@MainActor
final class SyncTests: XCTestCase {

    private var roots: [URL] = []
    private let user = "test-user"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(["en"], forKey: LanguageScope.enrolledDefaultsKey)
        SyncStore.setEnabled(true, userId: user)
        // Persisted per account, so one test's subscription would make the
        // next one's `activate` a no-op.
        SyncStore.setSubscribedToPush(false, userId: user)
    }

    override func tearDown() async throws {
        SyncFiles.documentsOverride = nil
        for root in roots { try? FileManager.default.removeItem(at: root) }
        SyncStore.setEnabled(false, userId: user)
        SyncStore.setSubscribedToPush(false, userId: user)
        try await super.tearDown()
    }

    /// A "device": its own Documents tree and its own engine, sharing the
    /// transport with the other devices.
    private func device(_ transport: InMemorySyncTransport) -> (root: URL, engine: SyncEngine) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        SyncFiles.documentsOverride = root
        let engine = SyncEngine(transport: transport)
        engine.setUser(user)
        return (root, engine)
    }

    private func on(_ root: URL) { SyncFiles.documentsOverride = root }

    private func sessions(_ root: URL) -> [Session] {
        on(root)
        return SyncFiles.read([Session].self, at: SyncFiles.url("sessions.json", lang: "en"),
                              decoder: SyncFiles.storeDecoder, empty: []) ?? []
    }

    private func cards(_ root: URL) -> [DrillCard] {
        on(root)
        return SyncFiles.read([DrillCard].self, at: SyncFiles.url("drills.json", lang: "en"),
                              decoder: SyncFiles.storeDecoder, empty: []) ?? []
    }

    private func writeSessions(_ list: [Session], _ root: URL) throws {
        on(root)
        try SyncFiles.write(list, to: SyncFiles.url("sessions.json", lang: "en"), encoder: SyncFiles.storeEncoder)
    }

    private func writeCards(_ list: [DrillCard], _ root: URL) throws {
        on(root)
        try SyncFiles.write(list, to: SyncFiles.url("drills.json", lang: "en"), encoder: SyncFiles.storeEncoder)
    }

    private func sample(_ topic: String, at: Date = Date()) -> Session {
        Session(id: UUID(), userId: UUID(), targetLanguage: "en", mode: .conversation, topic: topic,
                startedAt: at, endedAt: at.addingTimeInterval(60),
                turns: [Turn(id: UUID(), role: .user, audioURL: URL(fileURLWithPath: "/private/var/x.m4a"),
                             transcript: "hi", durationMs: 800, timestamp: at)],
                summary: nil)
    }

    private func card(_ text: String, box: Int = 0, sessionId: UUID? = nil) -> DrillCard {
        DrillCard(sourcePhrase: "", targetPhrase: text, reason: "", createdAt: Date(),
                  nextReviewAt: Date(), box: box, sourceSessionId: sessionId)
    }

    private func sync(_ d: (root: URL, engine: SyncEngine)) async {
        on(d.root)
        await d.engine.runSync(kinds: nil)
    }

    // MARK: - Merge rules

    func testDrillMergeTakesTheHigherProgress() {
        var a = card("I'd like a coffee", box: 2)
        a.timesSeen = 3
        a.lastReviewedAt = Date(timeIntervalSince1970: 100)
        var b = a
        b.box = 4
        b.timesSeen = 2
        b.lastReviewedAt = Date(timeIntervalSince1970: 200)
        b.usedInTalkAt = Date(timeIntervalSince1970: 150)
        let m = SyncKindRegistry.mergeCards(a, b)
        XCTAssertEqual(m.box, 4)
        XCTAssertEqual(m.timesSeen, 3)
        XCTAssertEqual(m.lastReviewedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(m.usedInTalkAt, Date(timeIntervalSince1970: 150))
        XCTAssertEqual(SyncKindRegistry.mergeCards(b, a).box, 4, "commutative")
    }

    func testRetiredCardStaysRetiredWhateverTheOtherSideDid() {
        var a = card("x", box: 5)
        a.nextReviewAt = DrillStore.retiredReviewDate
        let b = card("x", box: 1)
        XCTAssertEqual(SyncKindRegistry.mergeCards(a, b).nextReviewAt, DrillStore.retiredReviewDate)
    }

    func testVocabRecordUsedOutranksKnown() {
        let known = VocabStore.Record(state: .known, firstAt: Date(timeIntervalSince1970: 50),
                                      lastAt: Date(timeIntervalSince1970: 60), count: 0)
        let used = VocabStore.Record(state: .used, firstAt: Date(timeIntervalSince1970: 70),
                                     lastAt: Date(timeIntervalSince1970: 80), count: 2)
        let m = SyncKindRegistry.mergeRecords(known, used)
        XCTAssertEqual(m.state, .used)
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m.firstAt, Date(timeIntervalSince1970: 50))
        XCTAssertEqual(m.lastAt, Date(timeIntervalSince1970: 80))
    }

    func testLWWNewerDeletionWinsAndOlderDeletionLoses() {
        let payload = Data("a".utf8)
        let local = SyncSide(payload: payload, at: Date(timeIntervalSince1970: 100), deleted: false)
        XCTAssertNil(SyncMerge.lww(local, SyncSide(payload: nil, at: Date(timeIntervalSince1970: 200), deleted: true)))
        XCTAssertEqual(SyncMerge.lww(local, SyncSide(payload: nil, at: Date(timeIntervalSince1970: 50), deleted: true)), payload)
    }

    func testUnionNeverDeletes() {
        let payload = Data("a".utf8)
        let local = SyncSide(payload: payload, at: Date(), deleted: false)
        let tomb = SyncSide(payload: nil, at: Date().addingTimeInterval(10), deleted: true)
        XCTAssertEqual(SyncMerge.union(local, tomb) { a, _ in a }, payload)
    }

    func testPracticeDayTakesTheMaxPerFieldNotTheSum() {
        var a = PracticeLog.Day(); a.drillReps = 3; a.wordDone = 1
        var b = PracticeLog.Day(); b.drillReps = 5; b.wordDone = 0; b.shadowReps = 2
        let m = SyncKindRegistry.maxDay(a, b)
        XCTAssertEqual(m.drillReps, 5)
        XCTAssertEqual(m.wordDone, 1)
        XCTAssertEqual(m.shadowReps, 2)
    }

    /// A Watch scene is a streak day, so it has to survive the merge — and a
    /// day with no scenes must encode exactly as it did before the field
    /// existed, or every day in every log re-uploads once for nothing.
    func testPracticeDaySceneRepsMergeAndStayOffTheWireWhenZero() throws {
        var a = PracticeLog.Day(); a.sceneReps = 2
        let b = PracticeLog.Day()
        XCTAssertEqual(SyncKindRegistry.maxDay(a, b).sceneReps, 2)
        XCTAssertTrue(a.showedUp)
        XCTAssertFalse(b.showedUp)

        let bare = String(decoding: try JSONEncoder().encode(b), as: UTF8.self)
        XCTAssertFalse(bare.contains("sceneReps"))
        let round = try JSONDecoder().decode(PracticeLog.Day.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(round.sceneReps, 2)
    }

    // MARK: - Canonical form

    func testCanonicalHashIsStableAcrossKeyOrder() throws {
        let a = try SyncCanonical.encode(["b": 1, "a": 2])
        let b = try SyncCanonical.encode(["a": 2, "b": 1])
        XCTAssertEqual(SyncCanonical.hash(a), SyncCanonical.hash(b))
    }

    func testRecordNameIsASCIIForAnyKey() {
        let name = SyncRecord.recordName(kind: .vocabRecord, lang: "ko", key: "김치찌개")
        XCTAssertTrue(name.allSatisfy { $0.isASCII })
        XCTAssertLessThan(name.count, 255)
    }

    // MARK: - Silent push

    /// `activate` subscribes off the call, so the assertion has to wait for
    /// it rather than read straight after `enable`.
    private func eventually(_ condition: () -> Bool, _ message: String) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(message)
    }

    func testEnablingSubscribesTheZoneToSilentPushes() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        try await a.engine.enable()
        await eventually({ cloud.subscriptions.contains("changes-nawana-\(self.user)") },
                         "enable must subscribe the account's own zone")
    }

    /// One device turning sync off says nothing about the learner's other
    /// device, and the subscription is the ACCOUNT's — dropping it here would
    /// quietly stop the tablet being woken too.
    func testTurningSyncOffLeavesTheAccountsSubscriptionAlone() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        try await a.engine.enable()
        await eventually({ !cloud.subscriptions.isEmpty }, "expected a subscription")
        a.engine.disable()
        XCTAssertEqual(cloud.subscriptions.count, 1)
    }

    /// "Delete from iCloud" is the one caller that speaks for every device.
    func testDeletingFromCloudRemovesTheSubscription() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        try await a.engine.enable()
        await eventually({ !cloud.subscriptions.isEmpty }, "expected a subscription")
        try await a.engine.deleteFromCloud()
        XCTAssertTrue(cloud.subscriptions.isEmpty)
    }

    // MARK: - Two devices

    func testSecondDeviceReceivesTheFirstDevicesTalks() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        let s1 = sample("Coffee"), s2 = sample("Rent")
        try writeSessions([s1, s2], a.root)
        try writeCards([card("one", sessionId: s1.id)], a.root)
        try await a.engine.enable()

        let b = device(cloud)
        try await b.engine.enable()
        let got = sessions(b.root)
        XCTAssertEqual(Set(got.map(\.id)), [s1.id, s2.id])
        XCTAssertNil(got.first?.turns.first?.audioURL, "sandbox paths never travel")
        XCTAssertEqual(cards(b.root).count, 1)
    }

    func testEditsOnBothSidesMergeAndConverge() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        let shared = card("shared line", box: 1)
        try writeCards([shared], a.root)
        try await a.engine.enable()
        let b = device(cloud)
        try await b.engine.enable()

        // A reviews it to box 3; B, offline, to box 2 and mints a new card.
        var onA = cards(a.root)[0]; onA.box = 3; onA.timesSeen = 4
        try writeCards([onA], a.root)
        var onB = cards(b.root)[0]; onB.box = 2; onB.timesSeen = 1
        try writeCards([onB, card("new on b")], b.root)

        await sync(a)
        await sync(b)
        await sync(a)
        await sync(b)

        let ca = cards(a.root), cb = cards(b.root)
        XCTAssertEqual(ca.count, 2)
        XCTAssertEqual(cb.count, 2)
        XCTAssertEqual(ca.first { $0.id == shared.id }?.box, 3)
        XCTAssertEqual(cb.first { $0.id == shared.id }?.box, 3)
        XCTAssertEqual(ca.first { $0.id == shared.id }?.timesSeen, 4)
        XCTAssertEqual(Set(ca.map(\.id)), Set(cb.map(\.id)))
    }

    func testDeletingATalkDeletesItAndItsCardsEverywhere() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        let s = sample("Gone")
        try writeSessions([s], a.root)
        try writeCards([card("from gone", sessionId: s.id), card("unrelated")], a.root)
        try await a.engine.enable()
        let b = device(cloud)
        try await b.engine.enable()
        XCTAssertEqual(sessions(b.root).count, 1)
        XCTAssertEqual(cards(b.root).count, 2)

        // B reviews the card while A deletes the talk.
        var reviewed = cards(b.root).first { $0.sourceSessionId == s.id }!
        reviewed.box = 4
        try writeCards(cards(b.root).map { $0.id == reviewed.id ? reviewed : $0 }, b.root)
        // …exactly what `AppState.deleteSession` does: the row and its cards.
        let unrelated = cards(a.root).first { $0.sourceSessionId == nil }!
        try writeSessions([], a.root)
        try writeCards([unrelated], a.root)

        await sync(a)
        await sync(b)
        await sync(a)

        XCTAssertEqual(sessions(b.root).count, 0)
        XCTAssertEqual(cards(b.root).map(\.targetPhrase), ["unrelated"], "the deleted talk's card went with it")
        XCTAssertEqual(cards(a.root).map(\.targetPhrase), ["unrelated"])
    }

    func testPullDoesNotPingPong() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        try writeSessions([sample("Once")], a.root)
        try await a.engine.enable()
        let b = device(cloud)
        try await b.engine.enable()
        let after = cloud.saves
        await sync(b)
        await sync(a)
        await sync(b)
        XCTAssertEqual(cloud.saves, after, "nothing changed, nothing was pushed")
    }

    func testStaleTagIsAConflictThatTheNextPassResolves() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        let c = card("line", box: 0)
        try writeCards([c], a.root)
        try await a.engine.enable()
        let b = device(cloud)
        try await b.engine.enable()

        var ca = cards(a.root)[0]; ca.box = 2
        try writeCards([ca], a.root)
        await sync(a)                    // server now holds box 2 with a new tag
        var cb = cards(b.root)[0]; cb.box = 1
        try writeCards([cb], b.root)
        await sync(b)                    // b's save conflicts, pulls, merges to 2, pushes
        XCTAssertEqual(cards(b.root)[0].box, 2)
        await sync(a)
        XCTAssertEqual(cards(a.root)[0].box, 2)
    }

    func testMissingZoneSwitchesSyncOff() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        try writeSessions([sample("x")], a.root)
        try await a.engine.enable()
        try await cloud.deleteZone(a.engine.zoneName!)
        await sync(a)
        XCTAssertEqual(a.engine.status, .paused(.zoneMissing))
        XCTAssertFalse(a.engine.isEnabled)
        XCTAssertEqual(sessions(a.root).count, 1, "local data untouched")
    }

    func testBlobsTravelAsAssets() async throws {
        let cloud = InMemorySyncTransport()
        let a = device(cloud)
        let turnDir = a.root.appendingPathComponent("TurnAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: turnDir, withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: turnDir.appendingPathComponent("T1.mp3"))
        try await a.engine.enable()
        // Audio follows enable() in a pass nobody waits on.
        await a.engine.waitUntilIdle()

        let b = device(cloud)
        try await b.engine.enable()
        await b.engine.waitUntilIdle()
        let landed = b.root.appendingPathComponent("TurnAudio/T1.mp3")
        XCTAssertEqual(try Data(contentsOf: landed), Data([1, 2, 3, 4]))
        XCTAssertEqual(b.engine.blobState(kind: .blobTurn, key: "T1.mp3"), .local)
    }
}
