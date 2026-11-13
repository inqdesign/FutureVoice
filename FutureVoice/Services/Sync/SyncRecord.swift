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
    /// The Speech tab's own scripts and its takes (score, transcript, notes).
    /// Small; the recordings travel as `blobSpeechAudio` / `blobSpeechVideo`.
    case speechScript
    case speechTake
    /// Tutor lessons in progress (`TutorLessonStore`), the tutor chat thread
    /// (`TutorChat`), which curriculum topics are done (`TutorProgressStore`),
    /// the student file (`LearnerStateStore`) and the pronunciation ledger
    /// (`PronunciationLedger`) — 2026-11-03, founder: a learner's practice
    /// is the same on every device. An older build skips these kinds.
    case tutorLesson
    case tutorChat
    case tutorProgress
    case learnerState
    case pronunciation
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
    /// Upcoming goals (`UpcomingGoalStore`). An older build can't name this
    /// kind and skips the record, so no schema bump.
    case upcomingGoal
    /// Why the learner is learning (`LearningPurposeStore`): one record, so
    /// onboarding's answer and every later edit reach the other devices.
    /// An older build can't name this kind and skips it, so no schema bump.
    case learningPurpose
    /// The routine (`StudyPlanStore`, one record). It used to stay on the
    /// device "because two devices must not both ring" — but what rings is
    /// the daily call, whose switch stays per device (2026-11-03, founder:
    /// the routine is the same everywhere, the phone rings).
    case studyPlan
    /// The promise's judged days (`PromiseLedger`), one record per day, so
    /// the streak reads the same on every device.
    case promiseDay
    /// When each rep happened (`ActivityEventLog`), so a routine block done
    /// on the Mac is ticked on the phone.
    case activityEvent
    /// A day's reading and model answer for an upcoming goal (`GoalPrep`):
    /// written once, so the other device reads the same text.
    case goalPrep
    /// Which upcoming goals' plans are in the routine (`GoalPlanStore`).
    /// An older build can't name this kind and skips it, so no schema bump.
    case goalPlan
    /// The "Your week" archive (`WeekRecapStore`), keyed by the week's end.
    case weekRecap
    // Blobs — files carried as assets, keyed by filename.
    case blobTurn
    case blobRecording
    case blobDayCard
    case blobAvatar
    /// The voice-clone recording (`VoiceSampleStore`), so a new phone or a
    /// reinstall rebuilds the voice without recording again (2026-10-01,
    /// founder decision). An older build can't name this kind and skips the
    /// record (`CloudKitTransport.makeSyncRecord`), so no schema bump.
    case blobVoiceSample
    /// A Speech take's voice (`Documents/Speech/*.wav`), like a shadow take.
    case blobSpeechAudio
    /// The COPY of a Speech camera take that goes to iCloud
    /// (`Documents/Speech/Synced/`), made only when the learner picked a
    /// video quality (`SpeechVideoSync`). The camera's own file never
    /// travels: at 1080p a three-minute take is hundreds of megabytes, so
    /// the learner chooses what iCloud gets — a standard copy, or the
    /// original, and the original is downloaded on another device only when
    /// asked for (`BlobKind.onDemand`).
    case blobSpeechVideo
    /// A person's photo (`CounterpartPhotoStore`), one small JPEG per id.
    case blobCounterpartPhoto

    /// Whether items live under `Documents/lang/<code>/` (one set per
    /// enrolled language) or once per install.
    var isLanguageScoped: Bool {
        switch self {
        case .session, .drill, .vocabRecord, .vocabExpression, .vocabStudying,
             .vocabStudyingExpression, .vocabRemovedByHand, .vocabAutoKept,
             .vocabDismissed, .vocabIngested, .vocabExpressionIngested,
             .schedule, .shadow, .savedLine, .scenario, .dialogue, .weekly, .weeklyTest,
             .speechScript, .speechTake,
             .tutorLesson, .tutorChat, .tutorProgress, .learnerState, .pronunciation:
            return true
        case .practiceDay, .talkDay, .usageDay, .persona, .personaNote, .profile,
             .counterpart, .dayCard, .defaults, .upcomingGoal, .learningPurpose,
             .studyPlan, .promiseDay, .activityEvent, .goalPrep, .goalPlan, .weekRecap,
             .blobCounterpartPhoto,
             .blobTurn, .blobRecording, .blobDayCard, .blobAvatar, .blobVoiceSample,
             .blobSpeechAudio, .blobSpeechVideo:
            return false
        }
    }

    /// A blob is a file carried as a `CKAsset`; its "payload" locally is
    /// only a fingerprint (size + mtime), never the bytes.
    var isBlob: Bool {
        switch self {
        case .blobTurn, .blobRecording, .blobDayCard, .blobAvatar, .blobVoiceSample,
             .blobSpeechAudio, .blobSpeechVideo, .blobCounterpartPhoto: return true
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
/// push back without. An optional field the old build may lose is NOT a bump
/// on a kind whose merge the newer device wins; on a last-writer-wins kind
/// the old build's copy IS the newer one, so it needs a per-kind stamp below.
///
/// A record carrying a higher schema than this build can read is applied if
/// it decodes and FROZEN in the index either way (never pushed back, never
/// tombstoned), so an old phone can't quietly delete what a new one wrote.
enum SyncSchema {
    static let version = 1
    /// The newest stamp this build understands. Above `version` because a
    /// single kind may be stamped ahead of the rest, without touching the
    /// others or dropping anyone's change token (`thawIfUpgraded`).
    static let readable = 2

    /// What a record of this kind is stamped with on push.
    ///
    /// A speech take is 2 (2026-11-09): macOS launches a Catalyst app for a
    /// silent push, window or no window, and a Mac on 1.3.0 (132) decoded the
    /// phone's take without `reading` / `prompter`, rewrote it and pushed it.
    /// Last writer won, so the phone lost its Season 2 result and its video
    /// on the result page six minutes after the take. Every build already
    /// shipped freezes a record stamped above 1, so none can do that again.
    static func stamp(for kind: SyncKind) -> Int {
        kind == .speechTake ? 2 : version
    }
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
