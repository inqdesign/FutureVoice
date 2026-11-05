import XCTest
@testable import FutureVoice

/// The Drive layout is Android's (`DriveTransport.kt`); a record written by
/// one platform must read back on the other byte for byte.
final class GoogleDriveTransportTests: XCTestCase {

    func testPropertiesAreAndroidsShape() {
        let r = SyncRecord(kind: .session, key: "ABC", lang: "en",
                           payload: Data("{}".utf8), size: 2,
                           modifiedAt: Date(timeIntervalSince1970: 1_762_300_000.123),
                           deletedAt: nil)
        let p = GoogleDriveTransport.properties(for: r)
        XCTAssertEqual(p["k"], "session")
        XCTAssertEqual(p["l"], "en")
        XCTAssertEqual(p["s"], "1")
        // Epoch MILLISECONDS as a plain integer — Android parses with toLongOrNull.
        XCTAssertEqual(p["m"], "1762300000123")
        XCTAssertEqual(p["d"], "")
        XCTAssertEqual(p["z"], "2")
    }

    func testAndroidFileReadsBack() {
        // What Android's DriveTransport writes for a global tombstone.
        let file: [String: Any] = [
            "id": "file-1",
            "name": SyncRecord.recordName(kind: .practiceDay, lang: nil, key: "2026-11-05"),
            "description": "2026-11-05",
            "appProperties": ["k": "practiceDay", "l": "", "s": "1",
                              "m": "1762300000000", "d": "1762300005000", "z": "0"],
        ]
        let r = GoogleDriveTransport.shell(file)
        XCTAssertEqual(r?.kind, .practiceDay)
        XCTAssertEqual(r?.key, "2026-11-05")
        XCTAssertNil(r?.lang)
        XCTAssertEqual(r?.modifiedAt, Date(timeIntervalSince1970: 1_762_300_000))
        XCTAssertEqual(r?.deletedAt, Date(timeIntervalSince1970: 1_762_300_005))
        XCTAssertTrue(r?.isTombstone ?? false)
        XCTAssertEqual(r?.systemFields, Data("file-1".utf8))
    }

    func testUnknownKindIsSkipped() {
        let file: [String: Any] = [
            "id": "x", "description": "k",
            "appProperties": ["k": "somethingNew", "m": "1"],
        ]
        XCTAssertNil(GoogleDriveTransport.shell(file))
    }

    func testRoundTrip() {
        let r = SyncRecord(kind: .session, key: "K", lang: "de", payload: nil, size: 7,
                           modifiedAt: Date(timeIntervalSince1970: 1_700_000_000.5))
        var file: [String: Any] = ["id": "f", "description": r.key]
        file["appProperties"] = GoogleDriveTransport.properties(for: r)
        let back = GoogleDriveTransport.shell(file)
        XCTAssertEqual(back?.recordName, r.recordName)
        XCTAssertEqual(back?.size, 7)
        XCTAssertEqual(back?.modifiedAt.timeIntervalSince1970 ?? 0, 1_700_000_000.5, accuracy: 0.001)
    }

    /// Kinds the two apps don't agree on yet never come off Drive and never
    /// go up — an Android drill card would otherwise be tombstoned here.
    func testExcludedKindsNeverRead() {
        for kind in GoogleDriveTransport.excludedKinds {
            let file: [String: Any] = [
                "id": "x", "description": "k",
                "appProperties": ["k": kind.rawValue, "l": "", "m": "1"],
            ]
            XCTAssertNil(GoogleDriveTransport.shell(file), kind.rawValue)
        }
        XCTAssertTrue(GoogleDriveTransport.excludedKinds.contains(.drill))
        XCTAssertFalse(GoogleDriveTransport.excludedKinds.contains(.session))
    }

    /// Android writes whole Doubles as `85.0`; read back here they must be
    /// the bytes this device writes, or the two echo each other forever.
    func testDictKindNormalizesAndroidBytes() {
        struct V: Codable { var seconds: Double }
        let kind = DictKind<V>(kind: .talkDay, filename: "x.json", mergeRule: SyncMerge.lww)
        let android = Data(#"{"seconds":85.0}"#.utf8)
        let mine = try! SyncCanonical.encode(V(seconds: 85))
        XCTAssertEqual(kind.normalize(android), mine)
        // Something that won't decode is left as it came.
        let junk = Data("not json".utf8)
        XCTAssertEqual(kind.normalize(junk), junk)
    }
}
