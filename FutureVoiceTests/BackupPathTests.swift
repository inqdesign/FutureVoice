import XCTest
@testable import FutureVoice

/// The one thing a backup has to get right: WHERE each file goes back.
///
/// Every export ever made on a device filed its contents under
/// `cuments/…` — the container path resolves symlinks (`/var` →
/// `/private/var`) on the way out of `FileManager.enumerator` but not out of
/// `urls(for:)`, and the old character arithmetic ate the wrong end. The
/// restore then reported success and the receiving install showed nothing.
final class BackupPathTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A directory reached through a symlink, exactly like the iOS
        // container: `link` → `real`, and the enumerator hands back `real`.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-paths-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real/Documents")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base.appendingPathComponent("real"))
        root = link.appendingPathComponent("Documents")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
        super.tearDown()
    }

    func testRelativePathSurvivesASymlinkedRoot() throws {
        let dir = root.appendingPathComponent("lang/en")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sessions.json")
        try Data("[]".utf8).write(to: file)

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var relatives: [String] = []
        for case let url as URL in enumerator {
            if let rel = BackupService.relativePath(of: url, under: root) { relatives.append(rel) }
        }
        XCTAssertTrue(relatives.contains("lang/en/sessions.json"), "got \(relatives)")
        XCTAssertFalse(relatives.contains(where: { $0.hasPrefix("cuments") }), "got \(relatives)")
    }

    func testUnrelatedPathIsNotRelative() {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere.json")
        XCTAssertNil(BackupService.relativePath(of: outside, under: root))
    }

    /// The backups already in people's Files app still import.
    func testLegacyTruncatedPathsAreRepaired() {
        XCTAssertEqual(BackupService.normalizedPath("cuments/lang/en/sessions.json"),
                       "lang/en/sessions.json")
        XCTAssertEqual(BackupService.normalizedPath("cuments/persona.json"), "persona.json")
        XCTAssertEqual(BackupService.normalizedPath("ments/lang/ko/drills.json"),
                       "lang/ko/drills.json")
    }

    /// A correct path is never "repaired" — nothing this app writes to
    /// Documents is named after a tail of "Documents".
    func testCorrectPathsAreLeftAlone() {
        XCTAssertEqual(BackupService.normalizedPath("lang/en/sessions.json"),
                       "lang/en/sessions.json")
        XCTAssertEqual(BackupService.normalizedPath("persona.json"), "persona.json")
        XCTAssertEqual(BackupService.normalizedPath("PhraseAudio/abc.mp3"), "PhraseAudio/abc.mp3")
    }
}
