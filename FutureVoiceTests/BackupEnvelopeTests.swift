import XCTest
@testable import FutureVoice

/// The backup is written and read one file at a time (a whole-envelope
/// encode of a 1 GB library was killed by iOS mid-export), but the bytes must
/// stay the SAME JSON the whole-envelope coder reads and writes — older builds
/// import what this build exports, and this build imports what they exported.
final class BackupEnvelopeTests: XCTestCase {

    private let sample: [(path: String, data: Data)] = [
        ("lang/en/sessions.json", Data(#"[{"t":"a/b \"q\""}]"#.utf8)),
        ("TurnAudio/한국어 파일.mp3", Data((0..<4096).map { UInt8($0 % 256) })),
        ("empty.json", Data()),
    ]
    private let defaults: [String: Data] = ["futurevoice.targetLanguage": Data([1, 2, 3, 250])]

    private func streamed() throws -> Data {
        var out = try BackupService.envelopeHead(defaults: defaults)
        for (i, file) in sample.enumerated() {
            out.append(try BackupService.envelopeEntry(path: file.path, data: file.data, first: i == 0))
        }
        out.append(contentsOf: "]}".utf8)
        return out
    }

    private func readAll(_ data: Data) throws -> (files: [(String, Data)], defaults: [String: Data]) {
        var files: [(String, Data)] = []
        let defaults = try BackupService.EnvelopeReader.read(data) { files.append(($0, $1)) }
        return (files, defaults)
    }

    func testStreamedExportDecodesWithTheWholeEnvelopeDecoder() throws {
        let envelope = try JSONDecoder().decode(BackupService.Envelope.self, from: streamed())
        XCTAssertEqual(envelope.version, 2)
        XCTAssertEqual(envelope.files.map(\.path), sample.map(\.path))
        XCTAssertEqual(envelope.files.map(\.data), sample.map(\.data))
        XCTAssertEqual(envelope.defaults, defaults)
    }

    func testStreamedReaderReadsTheStreamedExport() throws {
        let data = try streamed()
        let result = try readAll(data)
        XCTAssertEqual(result.files.map(\.0), sample.map(\.path))
        XCTAssertEqual(result.files.map(\.1), sample.map(\.data))
        XCTAssertEqual(result.defaults, defaults)
        XCTAssertEqual(BackupService.EnvelopeReader.countEntries(in: data), sample.count)
    }

    /// Exports from older builds: whole-envelope `JSONEncoder` output, keys in
    /// whatever order it chose, `/` escaped inside base64, pretty-printed too.
    func testStreamedReaderReadsWholeEnvelopeExports() throws {
        let envelope = BackupService.Envelope(
            files: sample.map { .init(path: $0.path, data: $0.data) },
            defaults: defaults)
        let encoder = JSONEncoder()
        for formatting: JSONEncoder.OutputFormatting in [[], [.prettyPrinted, .sortedKeys]] {
            encoder.outputFormatting = formatting
            let result = try readAll(encoder.encode(envelope))
            XCTAssertEqual(result.files.map(\.0), sample.map(\.path))
            XCTAssertEqual(result.files.map(\.1), sample.map(\.data))
            XCTAssertEqual(result.defaults, defaults)
        }
    }

    func testTruncatedFileIsReportedAsDamaged() throws {
        let data = try streamed()
        XCTAssertThrowsError(try readAll(data.prefix(data.count - 40)))
    }
}
