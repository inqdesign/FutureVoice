import CryptoKit
import Foundation

/// The kinds of thing the sync carries — one per store, or per independently
/// merged PART of a store (VocabStore is nine files and nine rules).
///
/// A kind is the unit of merge: every item of a kind is combined by the same
/// rule (`SyncKindHandler`). The raw value is the record type's `kind`
/// field on the server, so renaming one is a schema change.
enum SyncKind: String, Codable, CaseIterable, Hashable {
    // Language-scoped (`Documents/lang/<code>/`).
    case session
    case drill
    case vocabRecord
    case vocabExpression
    case vocabStudying
    case vocabStudyingExpression
    case vocabRemovedByHand
    case vocabAutoKept
    case vocabDismissed
    case vocabIngested
    case vocabExpressionIngested
    case schedule
    case shadow
    case savedLine
    case scenario
    case dialogue
    case weekly
    case weeklyTest
    // Global (Documents root / UserDefaults).
    case practiceDay
    case talkDay
    case usageDay
    case persona
    case personaNote
    case profile
    case counterpart
    case dayCard
    case defaults
    // Blobs — files carried as assets, keyed by filename.
    case blobTurn
    case blobRecording
    case blobDayCard
    case blobAvatar

    /// Whether items live under `Documents/lang/<code>/` (one set per
    /// enrolled language) or once per install.
    var isLanguageScoped: Bool {
        switch self {
        case .session, .drill, .vocabRecord, .vocabExpression, .vocabStudying,
             .vocabStudyingExpression, .vocabRemovedByHand, .vocabAutoKept,
             .vocabDismissed, .vocabIngested, .vocabExpressionIngested,
             .schedule, .shadow, .savedLine, .scenario, .dialogue, .weekly, .weeklyTest:
            return true
        case .practiceDay, .talkDay, .usageDay, .persona, .personaNote, .profile,
             .counterpart, .dayCard, .defaults,
             .blobTurn, .blobRecording, .blobDayCard, .blobAvatar:
            return false
        }
    }

    /// A blob is a file carried as a `CKAsset`; its "payload" locally is
    /// only a fingerprint (size + mtime), never the bytes.
    var isBlob: Bool {
        switch self {
        case .blobTurn, .blobRecording, .blobDayCard, .blobAvatar: return true
        default: return false
        }
    }

    /// The server record type. Blobs and items are different types so a
    /// change fetch can leave the asset field out of the items' `desiredKeys`
    /// without touching the items' payload.
    var recordType: String { isBlob ? "Blob" : "Item" }
}

/// One app-wide version of "what a payload looks like". Bump it on any
/// change to a synced type that an older build could NOT read harmlessly —
/// a new enum case, a renamed key, a field the old build would drop and then
/// push back without. Adding an optional field the old build may lose is
/// NOT a bump: the merge is idempotent and the newer device rewrites it.
///
/// A record carrying a higher schema than this build's is applied if it
/// decodes and FROZEN in the index either way (never pushed back, never
/// tombstoned), so an old phone can't quietly delete what a new one wrote.
enum SyncSchema {
    static let version = 1
}

/// One record as the transport sees it — the only shape `CKRecord` is ever
/// mapped to and from, so every rule above the transport is testable with a
/// dictionary standing in for iCloud.
struct SyncRecord: Equatable {
    var kind: SyncKind
    var key: String
    /// Language code for a scoped kind, nil for a global one.
    var lang: String?
    /// The item's canonical JSON (`SyncCanonical`), nil on a tombstone and
    /// on a blob (whose bytes travel as `assetURL`).
    var payload: Data?
    /// Local file to upload (push) or the downloaded temp file (fetch).
    var assetURL: URL?
    /// Byte size of a blob, carried as a field so a change fetch can list
    /// blobs without downloading them.
    var size: Int
    var schema: Int
    /// When the DEVICE last changed this item — the LWW clock. Device time,
    /// and deliberately so: the learner's own phone and tablet are the only
    /// writers, both set their clock from the network, and the domain
    /// timestamps every kind prefers (`lastReviewedAt`, `updatedAt`) are
    /// device time too.
    var modifiedAt: Date
    var deletedAt: Date?
    /// `CKRecord.encodeSystemFields` of the server's copy — the change tag.
    /// Re-saving without it is rejected as a conflict on every re-push.
    var systemFields: Data?

    var isTombstone: Bool { deletedAt != nil }

    init(kind: SyncKind, key: String, lang: String?, payload: Data? = nil,
         assetURL: URL? = nil, size: Int = 0, schema: Int = SyncSchema.version,
         modifiedAt: Date, deletedAt: Date? = nil, systemFields: Data? = nil) {
        self.kind = kind
        self.key = key
        self.lang = lang
        self.payload = payload
        self.assetURL = assetURL
        self.size = size
        self.schema = schema
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.systemFields = systemFields
    }

    /// The server-side name. Kind and language are readable; the key is
    /// hashed because a vocabulary key is a lemma in whatever script the
    /// learner studies and a record name must be ASCII under 255 bytes.
    var recordName: String { Self.recordName(kind: kind, lang: lang, key: key) }

    static func recordName(kind: SyncKind, lang: String?, key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return "\(kind.rawValue)|\(lang ?? "")|\(hex)"
    }
}

/// How the sync reads a kind's items off the disk. `nil` means the file
/// exists but could not be decoded — the pass skips the kind rather than
/// mistaking an unreadable file for an empty one and tombstoning everything.
typealias SyncSnapshot = [String: Data]

/// What `merge` is told about one side of an item.
struct SyncSide {
    var payload: Data?
    /// Local: when the diff first saw this exact payload. Remote: the
    /// writer's `modifiedAt`. Tombstone: when it was deleted.
    var at: Date
    var deleted: Bool
}
