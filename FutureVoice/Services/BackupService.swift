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
        var version: Int = 1
        var createdAt: Date = Date()
        var files: [File]

        struct File: Codable {
            let path: String
            let data: Data
        }
    }

    /// Top-level Documents folders that hold regenerable caches — big, and
    /// pointless to carry across installs (audio re-synthesizes on demand,
    /// keyed by the same content hashes).
    private static let excludedFolders: Set<String> = ["PhraseAudio"]

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Writes the envelope into tmp and returns its URL for the share sheet.
    static func export() throws -> URL {
        let fm = FileManager.default
        let docs = documents
        var files: [Envelope.File] = []
        if let enumerator = fm.enumerator(at: docs,
                                          includingPropertiesForKeys: [.isRegularFileKey]) {
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
                files.append(.init(path: rel, data: try Data(contentsOf: url)))
            }
        }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let out = fm.temporaryDirectory
            .appendingPathComponent("FutureVoice-\(df.string(from: Date())).fvbackup")
        try JSONEncoder().encode(Envelope(files: files)).write(to: out, options: .atomic)
        return out
    }

    /// Lays the envelope's files back down over Documents (overwriting on
    /// collision, never deleting anything extra). Returns how many files
    /// were restored. The caller must relaunch the app afterwards — store
    /// singletons hold whatever they read before the restore.
    @discardableResult
    static func restore(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        let fm = FileManager.default
        let docs = documents
        for file in envelope.files {
            // Never let a crafted path escape Documents.
            let dest = docs.appendingPathComponent(file.path).standardizedFileURL
            guard dest.path.hasPrefix(docs.path + "/") else { continue }
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try file.data.write(to: dest, options: .atomic)
        }
        return envelope.files.count
    }
}
