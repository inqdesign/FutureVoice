import Foundation

/// Persists the RAW voice-clone sample recording (Documents/voice_sample.wav)
/// so the user can regenerate their clone later without recording again — e.g.
/// after switching target language, or if a clone got deleted. We keep the
/// un-normalized take; loudness normalization happens at upload time so a
/// future re-clone always starts from the original capture.
///
/// **It also travels in the learner's iCloud** (2026-10-01, founder decision),
/// when sync is on. A learner reinstalled, paid, and was sent straight to
/// "record your voice again", because this file lived on one install only.
/// The sync carries a COPY in `syncFolder`, named by the moment it was
/// recorded: a blob is written once and never edited (`BlobKind.merge` keeps
/// whichever bytes a side already has), so a re-record has to be a new file
/// for another device to take it — and the newest name is the current take.
/// Only one copy is kept; the old one's deletion goes out as a tombstone, so
/// iCloud holds the latest recording and nothing else. It goes to the
/// learner's own iCloud, never to our servers.
final class VoiceSampleStore {
    static let shared = VoiceSampleStore()

    /// The folder `SyncKindRegistry` syncs as `.blobVoiceSample`.
    static let syncFolder = "VoiceSamples"

    private let fileURL: URL
    private let syncDir: URL

    init(filename: String = "voice_sample.wav") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent(filename)
        syncDir = dir.appendingPathComponent(Self.syncFolder, isDirectory: true)
    }

    var exists: Bool { url != nil }

    /// The recording. On a phone that never made one (a reinstall, another
    /// device) it is the newest copy sync brought down, put in place; and a
    /// copy recorded LATER elsewhere replaces an older take here, so every
    /// device rebuilds the voice from the same, latest recording.
    var url: URL? {
        let fm = FileManager.default
        let local = (try? fm.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        if let synced = newestSyncedCopy, let stamp = Self.recordedAt(synced),
           local == nil || stamp > local!.addingTimeInterval(5) {
            try? fm.removeItem(at: fileURL)
            if (try? fm.copyItem(at: synced, to: fileURL)) != nil { return fileURL }
        }
        return local == nil ? nil : fileURL
    }

    /// When a synced copy was recorded, read off its name.
    private static func recordedAt(_ copy: URL) -> Date? {
        let name = copy.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("sample-"), let ms = Double(name.dropFirst("sample-".count)) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Copy a freshly recorded sample into the stable location, replacing any
    /// previous one. Returns the stored URL, or nil on failure.
    @discardableResult
    func save(from sourceURL: URL) -> URL? {
        try? FileManager.default.removeItem(at: fileURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            refreshSyncedCopy()
            return fileURL
        } catch {
            return nil
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        for old in syncedCopies { try? FileManager.default.removeItem(at: old) }
        SyncEngine.noteChanged(.blobVoiceSample)
    }

    /// A recording made before the copy existed gets one (launch). Cheap: a
    /// directory listing when there is nothing to do.
    func ensureSyncedCopy() {
        guard FileManager.default.fileExists(atPath: fileURL.path), syncedCopies.isEmpty else { return }
        refreshSyncedCopy()
    }

    // MARK: - The synced copy

    private var syncedCopies: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: syncDir.path)) ?? []
        return names.filter { $0.hasSuffix(".wav") }.sorted().map { syncDir.appendingPathComponent($0) }
    }

    private var newestSyncedCopy: URL? { syncedCopies.last }

    /// One copy, named by when it was recorded (zero-padded milliseconds,
    /// so name order is time order).
    private func refreshSyncedCopy() {
        let fm = FileManager.default
        try? fm.createDirectory(at: syncDir, withIntermediateDirectories: true)
        let stamp = String(format: "%015.0f", (Date().timeIntervalSince1970 * 1000).rounded())
        let copy = syncDir.appendingPathComponent("sample-\(stamp).wav")
        guard (try? fm.copyItem(at: fileURL, to: copy)) != nil else { return }
        for old in syncedCopies where old != copy { try? fm.removeItem(at: old) }
        SyncEngine.noteChanged(.blobVoiceSample)
    }
}
