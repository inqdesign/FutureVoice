import CloudKit
import XCTest
@testable import FutureVoice

/// The silent push, as far as a test can reach it.
///
/// What is Apple's — that a zone change actually produces a push and that the
/// push actually reaches a suspended app — can only be watched on a device.
/// What is OURS is the parse: a payload arrives as an untyped dictionary and
/// `SyncPush.isOurs` decides whether the wake belongs to this account. That
/// decision failing silently is indistinguishable from a push that never
/// came, which is the one failure nobody would have gone looking for, so the
/// payload shape is pinned here.
///
/// `scripts/sync-push-probe.sh` builds the SAME dictionary and hands it to a
/// booted simulator, so a green test means the probe's payload is right and
/// anything the probe then fails to show is downstream of this file.
@MainActor
final class SyncPushTests: XCTestCase {

    /// A CloudKit record-zone notification, in the shape the service sends.
    ///
    /// The subscription id lives INSIDE `fet`, beside the zone it fired for —
    /// not at the top of `ck`, which is where a reasonable person puts it and
    /// where the first version of this file put it. `CKNotification` accepts
    /// that dictionary happily and hands back a `CKRecordZoneNotification`
    /// with the right zone and a **nil `subscriptionID`**, so a probe built
    /// on the wrong shape would have looked exactly like a handler that
    /// ignores its own account's pushes. Measured against `CKNotification`
    /// itself, which is Apple's parser for Apple's own payload, so wherever
    /// it reads the id from is where CloudKit writes it. `ce` is the CloudKit
    /// environment and may not be 0 (it raises).
    static func payload(subscriptionID: String, zone: String,
                        container: String = "iCloud.com.roro.futurevoice.dev")
        -> [AnyHashable: Any] {
        [
            "aps": ["content-available": 1],
            "ck": [
                "ce": 2,
                "cid": container,
                "nid": UUID().uuidString,
                "fet": [
                    "zid": zone,
                    "zoid": "_defaultOwner",
                    "dbs": 2,
                    "sid": subscriptionID,
                ],
            ],
        ]
    }

    func testTheSubscriptionIdIsBuiltFromTheZone() {
        XCTAssertEqual(SyncPush.subscriptionID(for: "nawana-abc"), "changes-nawana-abc")
    }

    /// The parse itself: CloudKit has to recognise the dictionary, and the
    /// subscription id has to survive it.
    func testACloudKitZonePayloadParsesAndCarriesItsSubscription() throws {
        let zone = "nawana-abc"
        let dict = Self.payload(subscriptionID: SyncPush.subscriptionID(for: zone), zone: zone)
        let note = try XCTUnwrap(CKNotification(fromRemoteNotificationDictionary: dict),
                                 "CloudKit must recognise the payload the probe sends")
        XCTAssertEqual(note.subscriptionID, "changes-nawana-abc")
        XCTAssertEqual((note as? CKRecordZoneNotification)?.recordZoneID?.zoneName, zone)
    }

    func testOurOwnZonesPushIsAccepted() {
        let zone = "nawana-abc"
        let dict = Self.payload(subscriptionID: SyncPush.subscriptionID(for: zone), zone: zone)
        XCTAssertTrue(SyncPush.isOurs(dict, zone: zone))
    }

    /// A shared iPad holding two app accounts: the other account's zone pushes
    /// too, and this install must not run a pass on data it can't see.
    func testAnotherAccountsZoneIsLeftAlone() {
        let mine = "nawana-abc", theirs = "nawana-xyz"
        let dict = Self.payload(subscriptionID: SyncPush.subscriptionID(for: theirs), zone: theirs)
        XCTAssertFalse(SyncPush.isOurs(dict, zone: mine))
    }

    /// Anything that isn't a CloudKit notification at all — a future push of
    /// our own, a malformed payload — is not this handler's.
    func testANonCloudKitPayloadIsNotOurs() {
        XCTAssertFalse(SyncPush.isOurs(["aps": ["alert": "hello"]], zone: "nawana-abc"))
    }
}
