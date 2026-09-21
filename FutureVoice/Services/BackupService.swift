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
        /// Entries whose path had to be repaired on the way in — see
        /// `normalizedPath`. Non-zero means the envelope came from a build
        /// with the truncated-path bug.
        var repaired = 0
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
    /// `sync/` is this install's relationship with iCloud (`SyncIndex`) —
    /// change tags and fingerprints that mean nothing on another install.
    private static let excludedFolders: Set<String> = ["PhraseAudio", "sync"]

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

    // MARK: - Paths

    /// `url`'s path relative to `root`, or nil if it isn't under it.
    ///
    /// Compared COMPONENT BY COMPONENT, with symlinks resolved on both sides,
    /// because string arithmetic on the two paths is not safe: on iOS the
    /// container lives under `/var/mobile/…`, which is a symlink to
    /// `/private/var/mobile/…`, and `FileManager.enumerator` hands back the
    /// RESOLVED path while `urls(for:)` returns the unresolved one. Dropping
    /// `root.path.count + 1` characters from a path that is 8 characters
    /// longer at the FRONT ate the wrong end: every entry in every backup ever
    /// exported from a device was filed as `cuments/lang/en/sessions.json`
    /// (the tail of "Documents"), so a restore laid the whole library down in
    /// `Documents/cuments/…` — a directory nothing reads — reported "restored
    /// N files", and the receiving install showed no practice data at all.
    /// It also defeated `excludedFolders`, whose test is the FIRST component,
    /// which is why those exports carried the entire PhraseAudio cache.
    static func relativePath(of url: URL, under root: URL) -> String? {
        let child = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard child.count > base.count, Array(child.prefix(base.count)) == base else { return nil }
        return child.dropFirst(base.count).joined(separator: "/")
    }

    /// Repairs a path written by a build with the bug described above, so the
    /// backups already sitting in people's Files app still import.
    ///
    /// The damage is always the same shape: a leading component that is a
    /// PROPER SUFFIX of "Documents" (`cuments` for the 8-character `/private`
    /// prefix). Nothing this app writes to Documents is named that, so the
    /// test can't catch a real folder.
    static func normalizedPath(_ path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first,
              first != "Documents",
              !first.isEmpty,
              "Documents".hasSuffix(first),
              parts.count > 1
        else { return path }
        parts.removeFirst()
        return parts.joined(separator: "/")
    }

    /// Writes the envelope into tmp and returns its URL for the share sheet.
    ///
    /// `nonisolated` on purpose: the caller is a view, so an inherited main
    /// actor would run the whole pack on the main thread — which is what made
    /// this look hung rather than slow. The reporting closure hops back.
    ///
    /// STREAMED, one file at a time, and it has to be (2026-09-17). It used to
    /// read every file into one `Envelope` and hand that to `JSONEncoder` —
    /// the library, then its base64, then the encoded file, all in memory at
    /// once. A real device's Documents was 1.14 GB (a month of call audio), so
    /// the export reached iOS's per-process limit (~3.4 GB) and was killed
    /// mid-"Writing the backup file" with no crash log of our own, only a
    /// JetsamEvent. The bytes on disk are the same JSON shape as before, so a
    /// file written here still imports on a build that decodes it whole.
    nonisolated static func export(
        onProgress: @escaping @MainActor (Step) -> Void
    ) async throws -> URL {
        await onProgress(.scanning)
        let fm = FileManager.default
        let docs = documents

        // Walk first, read second: the count has to exist before anything can
        // be reported as "340 of 1,204", and listing is cheap next to reading.
        let found = backupableFiles(in: docs)

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let tmp = fm.temporaryDirectory
        // A previous export is the size of the whole library and nothing
        // reads it once shared — keeping them would stack a gigabyte a tap.
        for old in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension == "fvbackup" {
            try? fm.removeItem(at: old)
        }
        // Prefix is cosmetic — the importer accepts `.item` and reads the
        // envelope, so it never parses this name. Extension stays
        // `.fvbackup` so older exports still import.
        let out = tmp.appendingPathComponent("nawana-\(df.string(from: Date())).fvbackup")
        guard fm.createFile(atPath: out.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: out)
            defer { try? handle.close() }
            try handle.write(contentsOf: envelopeHead(defaults: defaultsSnapshot()))
            for (index, entry) in found.enumerated() {
                try Task.checkCancellation()
                try autoreleasepool {
                    try handle.write(contentsOf: envelopeEntry(
                        path: entry.path,
                        data: Data(contentsOf: entry.url, options: .mappedIfSafe),
                        first: index == 0))
                }
                if index % progressStride == 0 {
                    await onProgress(.packing(done: index + 1, total: found.count))
                }
            }
            await onProgress(.packing(done: found.count, total: found.count))
            await onProgress(.encoding)
            try handle.write(contentsOf: Data("]}".utf8))
        } catch {
            try? fm.removeItem(at: out)
            throw error
        }
        return out
    }

    /// Everything before the first file: `{"version":2,"createdAt":…,
    /// "defaults":{…},"files":[`. Encoded with `JSONEncoder` piece by piece so
    /// each value is spelled exactly as the whole-envelope encoder spelled it.
    static func envelopeHead(defaults: [String: Data], createdAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        var head = Data(#"{"version":2,"createdAt":"#.utf8)
        head.append(try encoder.encode(createdAt))
        head.append(contentsOf: #","defaults":"#.utf8)
        head.append(try encoder.encode(defaults))
        head.append(contentsOf: #","files":["#.utf8)
        return head
    }

    /// One `{"path":…,"data":"<base64>"}` element of the files array.
    static func envelopeEntry(path: String, data: Data, first: Bool) throws -> Data {
        var chunk = Data((first ? "" : ",").utf8)
        chunk.append(contentsOf: #"{"path":"#.utf8)
        chunk.append(try JSONEncoder().encode(path))
        chunk.append(contentsOf: #","data":""#.utf8)
        chunk.append(data.base64EncodedData())
        chunk.append(contentsOf: #""}"#.utf8)
        return chunk
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
            guard let rel = relativePath(of: url, under: docs) else { continue }
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
        // Mapped, never read: a mapped file's pages are the file's, so they
        // don't count against the process the way a 1.5 GB `Data` would —
        // which is the export's crash again, on the other install.
        let mapped = try Data(contentsOf: url, options: .alwaysMapped)
        let total = EnvelopeReader.countEntries(in: mapped)
        let fm = FileManager.default
        let docs = documents
        var report = RestoreReport()
        // The reader is synchronous (it walks raw bytes), so progress is
        // posted rather than awaited; posts from one task keep their order.
        let post: (Step) -> Void = { step in Task { @MainActor in onProgress(step) } }
        post(.restoring(done: 0, total: total))
        var seen = 0
        let defaults = try EnvelopeReader.read(mapped) { rawPath, data in
            try Task.checkCancellation()
            seen += 1
            if seen % progressStride == 0 {
                post(.restoring(done: seen, total: max(total, seen)))
            }
            let path = normalizedPath(rawPath)
            if path != rawPath { report.repaired += 1 }
            // Never let a crafted path escape Documents.
            let dest = docs.appendingPathComponent(path).standardizedFileURL
            guard dest.path.hasPrefix(docs.path + "/") else {
                report.skipped += 1
                return
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            report.files += 1
        }
        await onProgress(.restoring(done: seen, total: seen))
        report.defaults = applyDefaults(defaults)
        if report.files > 0 { discardMisfiledTrees(in: docs) }
        return report
    }

    /// Removes what an import made by a buggy build left behind:
    /// `Documents/cuments/…`, a full copy of another install's library filed
    /// under the tail of "Documents" (see `relativePath`). Only ever created
    /// by that bug, and this restore has just laid the same envelope down in
    /// the right place, so nothing here is the only copy of anything.
    ///
    /// Left alone it isn't merely wasted space — it is inside Documents, so
    /// the NEXT export packs it too, and each round trip nests another copy.
    private static func discardMisfiledTrees(in docs: URL) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            let name = url.lastPathComponent
            guard name != "Documents", !name.isEmpty, "Documents".hasSuffix(name),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            try? fm.removeItem(at: url)
        }
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

    enum BackupFileError: LocalizedError {
        case damaged

        var errorDescription: String? {
            explain("This backup file is damaged or incomplete. Export it again from the other install.")
        }
    }

    /// Reads an envelope ONE FILE AT A TIME, straight off the bytes.
    ///
    /// `JSONDecoder` can only hand back the whole `Envelope`, i.e. the whole
    /// library in memory plus its parse tree — see `export` for why that dies
    /// on a real device. This walks the same JSON and gives each file to the
    /// caller as soon as it is decoded, so only one file is ever held. It
    /// reads every envelope version: key order is free (the whole-envelope
    /// encoder never fixed it), unknown keys are skipped, and escapes are
    /// honoured (`JSONEncoder` writes base64's `/` as `\/`).
    enum EnvelopeReader {
        /// How many file entries the envelope holds, for the progress bar.
        /// Base64 has no quote in its alphabet and a path's quotes are
        /// escaped, so `"path"` appears once per entry.
        static func countEntries(in data: Data) -> Int {
            let needle = Array(#""path""#.utf8)
            return data.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress, raw.count >= needle.count else { return 0 }
                var count = 0
                var offset = 0
                while offset < raw.count,
                      let hit = memmem(base + offset, raw.count - offset, needle, needle.count) {
                    count += 1
                    offset = base.distance(to: UnsafeRawPointer(hit)) + needle.count
                }
                return count
            }
        }

        /// Calls `onFile` for every entry in order and returns the defaults.
        static func read(_ data: Data,
                         onFile: (_ path: String, _ data: Data) throws -> Void) throws -> [String: Data] {
            try data.withUnsafeBytes { raw in
                let cursor = Cursor(bytes: raw)
                var defaults: [String: Data] = [:]
                try cursor.expect(UInt8(ascii: "{"))
                try cursor.members { key in
                    switch key {
                    case "files":
                        try cursor.elements {
                            var path: String?
                            var bytes: Data?
                            try cursor.expect(UInt8(ascii: "{"))
                            try cursor.members { field in
                                switch field {
                                case "path": path = String(decoding: try cursor.string(), as: UTF8.self)
                                case "data": bytes = try cursor.base64()
                                default: try cursor.skipValue()
                                }
                            }
                            guard let path, let bytes else { throw BackupFileError.damaged }
                            try autoreleasepool { try onFile(path, bytes) }
                        }
                    case "defaults":
                        try cursor.expect(UInt8(ascii: "{"))
                        try cursor.members { name in defaults[name] = try cursor.base64() }
                    default:
                        try cursor.skipValue()
                    }
                }
                return defaults
            }
        }

        /// A class, not a struct: the nested `members`/`elements` bodies
        /// advance the same cursor they were called on.
        private final class Cursor {
            let bytes: UnsafeRawBufferPointer
            var index = 0

            init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

            func peek() throws -> UInt8 {
                while index < bytes.count {
                    switch bytes[index] {
                    case 0x20, 0x09, 0x0A, 0x0D: index += 1
                    default: return bytes[index]
                    }
                }
                throw BackupFileError.damaged
            }

            func expect(_ byte: UInt8) throws {
                guard try peek() == byte else { throw BackupFileError.damaged }
                index += 1
            }

            /// `"key": value, …}` — the opening brace already consumed.
            func members(_ body: (String) throws -> Void) throws {
                if try peek() == UInt8(ascii: "}") { index += 1; return }
                while true {
                    let key = String(decoding: try string(), as: UTF8.self)
                    try expect(UInt8(ascii: ":"))
                    try body(key)
                    switch try peek() {
                    case UInt8(ascii: ","): index += 1
                    case UInt8(ascii: "}"): index += 1; return
                    default: throw BackupFileError.damaged
                    }
                }
            }

            /// `[value, …]` — including the opening bracket.
            func elements(_ body: () throws -> Void) throws {
                try expect(UInt8(ascii: "["))
                if try peek() == UInt8(ascii: "]") { index += 1; return }
                while true {
                    try body()
                    switch try peek() {
                    case UInt8(ascii: ","): index += 1
                    case UInt8(ascii: "]"): index += 1; return
                    default: throw BackupFileError.damaged
                    }
                }
            }

            func base64() throws -> Data {
                guard let data = Data(base64Encoded: try string()) else { throw BackupFileError.damaged }
                return data
            }

            /// A string's UTF-8 bytes, unescaped. The common case — no
            /// backslash before the closing quote — is two `memchr`s and one
            /// copy, which is what keeps a gigabyte of base64 quick.
            func string() throws -> Data {
                try expect(UInt8(ascii: "\""))
                guard let base = bytes.baseAddress else { throw BackupFileError.damaged }
                let start = index
                let remaining = bytes.count - start
                guard let quote = memchr(base + start, 0x22, remaining) else { throw BackupFileError.damaged }
                let end = base.distance(to: UnsafeRawPointer(quote))
                if memchr(base + start, 0x5C, end - start) == nil {
                    index = end + 1
                    return Data(bytes: base + start, count: end - start)
                }
                var out = Data()
                out.reserveCapacity(end - start)
                while true {
                    guard index < bytes.count else { throw BackupFileError.damaged }
                    let byte = bytes[index]
                    index += 1
                    if byte == 0x22 { return out }
                    guard byte == 0x5C else { out.append(byte); continue }
                    guard index < bytes.count else { throw BackupFileError.damaged }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var scalar = try hex4()
                        if (0xD800..<0xDC00).contains(scalar) {
                            guard index + 1 < bytes.count,
                                  bytes[index] == 0x5C, bytes[index + 1] == UInt8(ascii: "u")
                            else { throw BackupFileError.damaged }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00..<0xE000).contains(low) else { throw BackupFileError.damaged }
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let unicode = Unicode.Scalar(scalar) else { throw BackupFileError.damaged }
                        out.append(contentsOf: String(Character(unicode)).utf8)
                    default:
                        // `"`, `\`, `/` stand for themselves.
                        out.append(escape)
                    }
                }
            }

            private func hex4() throws -> UInt32 {
                guard index + 4 <= bytes.count,
                      let value = UInt32(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[index..<index + 4]),
                                                as: UTF8.self), radix: 16)
                else { throw BackupFileError.damaged }
                index += 4
                return value
            }

            func skipValue() throws {
                switch try peek() {
                case UInt8(ascii: "\""):
                    _ = try string()
                case UInt8(ascii: "{"):
                    index += 1
                    try members { _ in try skipValue() }
                case UInt8(ascii: "["):
                    try elements { try skipValue() }
                default:
                    // number, true, false, null
                    let start = index
                    while index < bytes.count {
                        switch bytes[index] {
                        case UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"),
                             0x20, 0x09, 0x0A, 0x0D:
                            if index == start { throw BackupFileError.damaged }
                            return
                        default: index += 1
                        }
                    }
                    throw BackupFileError.damaged
                }
            }
        }
    }
}
