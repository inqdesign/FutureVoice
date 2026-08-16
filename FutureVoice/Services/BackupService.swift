import Foundation

/// One-file backup of everything the learner has built on this device —
/// every store under Documents (all languages: sessions, drills, vocab,
/// scenarios, shadow attempts, practice log, recordings), minus the
/// regenerable TTS cache. Exists to move progress between INSTALLS: the dev
/// build (`com.roro.futurevoice.dev`) and the release build are separate
/// sandboxes, so practice done in one never reaches the other by itself.
///
/// Format: a versioned JSON envelope of relative path → file bytes. Both
/// sides run this same code, so the store formats always match; restoring
/// simply lays the files back down and the stores read them like their own.
enum BackupService {
    struct Envelope: Codable {
        var version: Int = 2
        var createdAt: Date = Date()
        var files: [File]
        /// `futurevoice.*` UserDefaults, each value property-list encoded.
        ///
        /// Files alone are NOT a backup: which files the stores even LOOK at
        /// is decided here. `LanguageScope.active` reads
        /// `futurevoice.targetLanguage` to resolve `Documents/lang/<code>/`,
        /// so a v1 envelope restored onto a fresh install laid every file
        /// down correctly and then showed nothing, because the install was
        /// pointed at a different language. Levels, goals, enrolled
        /// languages and the daily call live here too.
        ///
        /// Optional so a v1 envelope still decodes.
        var defaults: [String: Data]?

        struct File: Codable {
            let path: String
            let data: Data
        }
    }

    /// What a restore actually did — as opposed to what was in the file.
    struct RestoreReport {
        var files = 0
        var defaults = 0
        var skipped = 0
    }

    /// Where a running export/import has got to.
    ///
    /// Both directions are slow enough to look hung — a full library is
    /// hundreds of megabytes, and the two ends that carry it (`JSONEncoder`
    /// over base64, `JSONDecoder` back) are single opaque calls. The per-file
    /// loops in between are the only part that can be counted, so they are
    /// counted, and the opaque ends get their own named step rather than a
    /// frozen screen.
    enum Step: Equatable {
        case scanning
        case packing(done: Int, total: Int)
        case encoding
        case decoding
        case restoring(done: Int, total: Int)

        /// 0…1 where the step knows, `nil` where it genuinely can't say — an
        /// invented fraction on the opaque steps would sit still and read as
        /// stuck, which is the thing this type exists to avoid.
        var fraction: Double? {
            switch self {
            case let .packing(done, total), let .restoring(done, total):
                return total > 0 ? Double(done) / Double(total) : nil
            case .scanning, .encoding, .decoding:
                return nil
            }
        }
    }

    /// Main-actor hops cost more than reading a small JSON file, so the
    /// per-file loops report every `progressStride` items (plus once at the
    /// end, so the bar always lands on full).
    private static let progressStride = 25

    /// Top-level Documents folders that hold regenerable caches — big, and
    /// pointless to carry across installs (audio re-synthesizes on demand,
    /// keyed by the same content hashes).
    private static let excludedFolders: Set<String> = ["PhraseAudio"]

    /// Defaults that belong to the ACCOUNT or to this particular install, not
    /// to the practice. The footer in Me promises "your voice and minutes
    /// already follow your account" — carrying them in the file would make
    /// two installs disagree with the server. Two are actively destructive:
    /// `pendingDeleteVoiceId` makes the receiving install delete a voice from
    /// ElevenLabs at startup, and `langScopeMigrated` would suppress the
    /// receiving install's own flat-layout migration.
    private static let excludedDefaults: Set<String> = [
        "futurevoice.voiceCloneId",
        "futurevoice.voiceName",
        "futurevoice.voiceNameToken",
        "futurevoice.voiceAccentId",
        "futurevoice.pendingDeleteVoiceId",
        "futurevoice.pendingCloneTake",
        "futurevoice.ownVoiceLineage",
        "futurevoice.localUserId",
        "futurevoice.setupComplete",
        "futurevoice.pendingInviteCode",
        "futurevoice.langScopeMigrated",
        "futurevoice.appleName",
        "futurevoice.publicIntroManaged",
        "futurevoice.core.lastSeenEventId",
        "futurevoice.ttsIdemSalt",
    ]

    /// Consent is a record of what THIS person agreed to on THIS install, and
    /// re-asking costs one tap. Never carried.
    private static let excludedDefaultPrefixes = ["futurevoice.consent."]

    private static func isCarried(_ key: String) -> Bool {
        key.hasPrefix("futurevoice.")
            && !excludedDefaults.contains(key)
            && !excludedDefaultPrefixes.contains(where: key.hasPrefix)
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Writes the envelope into tmp and returns its URL for the share sheet.
    ///
    /// `nonisolated` on purpose: the caller is a view, so an inherited main
    /// actor would run the whole pack on the main thread — which is what made
    /// this look hung rather than slow. The reporting closure hops back.
    nonisolated static func export(
        onProgress: @escaping @MainActor (Step) -> Void
    ) async throws -> URL {
        await onProgress(.scanning)
        let fm = FileManager.default
        let docs = documents

        // Walk first, read second: the count has to exist before anything can
        // be reported as "340 of 1,204", and listing is cheap next to reading.
        let found = backupableFiles(in: docs)

        var files: [Envelope.File] = []
        files.reserveCapacity(found.count)
        for (index, entry) in found.enumerated() {
            try Task.checkCancellation()
            files.append(.init(path: entry.path, data: try Data(contentsOf: entry.url)))
            if index % progressStride == 0 {
                await onProgress(.packing(done: index + 1, total: found.count))
            }
        }
        await onProgress(.packing(done: found.count, total: found.count))

        await onProgress(.encoding)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let out = fm.temporaryDirectory
            .appendingPathComponent("FutureVoice-\(df.string(from: Date())).fvbackup")
        let envelope = Envelope(files: files, defaults: defaultsSnapshot())
        try JSONEncoder().encode(envelope).write(to: out, options: .atomic)
        return out
    }

    /// Every regular file under Documents worth carrying, as (url, path
    /// relative to Documents). Synchronous because `DirectoryEnumerator`'s
    /// iterator is unavailable from an async context.
    private nonisolated static func backupableFiles(in docs: URL) -> [(url: URL, path: String)] {
        guard let enumerator = FileManager.default
            .enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var found: [(url: URL, path: String)] = []
        for case let url as URL in enumerator {
            let rel = String(url.path.dropFirst(docs.path.count + 1))
            if let top = rel.split(separator: "/").first,
               excludedFolders.contains(String(top)) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            found.append((url, rel))
        }
        return found
    }

    /// Every carried default, wrapped in a one-element array because a
    /// property list's top level can't be a bare scalar. Values are
    /// heterogeneous (String, Bool, Int, [String], Date, Data), so plist is
    /// the only encoding that round-trips all of them without a per-key case.
    private static func defaultsSnapshot() -> [String: Data] {
        var out: [String: Data] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where isCarried(key) {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: [value],
                                                                 format: .binary,
                                                                 options: 0)
            else { continue }
            out[key] = data
        }
        return out
    }

    /// Lays the envelope's files back down over Documents (overwriting on
    /// collision, never deleting anything extra) and re-applies the carried
    /// defaults. The caller must relaunch the app afterwards — store
    /// singletons hold whatever they read before the restore.
    ///
    /// The report counts what was WRITTEN, never what the file contained: the
    /// path guard below skips silently, and a restore that skipped everything
    /// used to report the envelope's full count as a success.
    @discardableResult
    nonisolated static func restore(
        from url: URL,
        onProgress: @escaping @MainActor (Step) -> Void
    ) async throws -> RestoreReport {
        await onProgress(.decoding)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        let fm = FileManager.default
        let docs = documents
        var report = RestoreReport()
        for (index, file) in envelope.files.enumerated() {
            try Task.checkCancellation()
            if index % progressStride == 0 {
                await onProgress(.restoring(done: index + 1, total: envelope.files.count))
            }
            // Never let a crafted path escape Documents.
            let dest = docs.appendingPathComponent(file.path).standardizedFileURL
            guard dest.path.hasPrefix(docs.path + "/") else {
                report.skipped += 1
                continue
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try file.data.write(to: dest, options: .atomic)
            report.files += 1
        }
        await onProgress(.restoring(done: envelope.files.count, total: envelope.files.count))
        report.defaults = applyDefaults(envelope.defaults ?? [:])
        return report
    }

    /// Re-applies the carried defaults, re-checking `isCarried` on the way IN
    /// so an envelope written by a build with a laxer allowlist can't hand
    /// this install an account key.
    private static func applyDefaults(_ stored: [String: Data]) -> Int {
        var applied = 0
        for (key, data) in stored where isCarried(key) {
            guard let list = try? PropertyListSerialization.propertyList(from: data,
                                                                         options: [],
                                                                         format: nil) as? [Any],
                  let value = list.first
            else { continue }
            UserDefaults.standard.set(value, forKey: key)
            applied += 1
        }
        return applied
    }
}
