import CryptoKit
import Foundation

/// The ONE encoding every synced payload is written and hashed in.
///
/// The stores' own encoders must never be reused here: two of them
/// (`PracticeLog`, `VocabStore`) are bare `JSONEncoder()`s, whose key order
/// follows Swift's per-process dictionary seed — the same record would hash
/// differently on every launch and the diff would re-push the whole library
/// each morning. Sorted keys and ISO-8601 dates make the bytes a function of
/// the value alone. Changing anything here is a one-off full re-push, so
/// treat it like a schema bump.
enum SyncCanonical {
    static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// Content fingerprint of a payload — what the index compares to decide
    /// whether an item changed since it was last pushed.
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprint of a blob without reading it: a turn's audio is written
    /// once and never edited, so size + modification time identify the bytes
    /// and the diff pass doesn't SHA a gigabyte of MP3 on every foreground.
    static func blobFingerprint(size: Int, modifiedAt: Date) -> String {
        "\(size):\(Int(modifiedAt.timeIntervalSince1970))"
    }
}
