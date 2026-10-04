import Foundation

/// Scripts and takes for the Speech tab. JSON per target language
/// (`Documents/lang/<code>/speech_*.json`), media global under
/// `Documents/Speech/` like the shadow recordings. Local only — no sync kind:
/// a camera take is hundreds of megabytes, and the learner decides what
/// happens to it (keep · save to Photos · delete).
@MainActor
final class SpeechStore: ObservableObject {
    static let shared = SpeechStore()

    @Published private(set) var scripts: [SpeechScript] = []
    @Published private(set) var takes: [SpeechTake] = []
    /// Takes whose video is still being put together.
    @Published private(set) var videoPending: Set<UUID> = []
    private var loadedLanguage: String?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var mediaDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speech", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func mediaURL(_ filename: String) -> URL {
        mediaDirectory.appendingPathComponent(filename)
    }

    private var scriptsURL: URL { LanguageScope.activeDirectory.appendingPathComponent("speech_scripts.json") }
    private var takesURL: URL { LanguageScope.activeDirectory.appendingPathComponent("speech_takes.json") }

    /// Reads the active language's files. Cheap; called on every appearance
    /// so a language switch is picked up without a store hook.
    func reload() {
        loadedLanguage = LanguageScope.active
        let saved = (try? Data(contentsOf: scriptsURL))
            .flatMap { try? decoder.decode([SpeechScript].self, from: $0) } ?? []
        let builtIn = SpeechLibrary.builtIn(for: LanguageScope.active)
        // The bundled script is never written to disk: a new app version can
        // revise it, and every install reads the revision.
        scripts = (builtIn.map { [$0] } ?? []) + saved.filter { !$0.isBuiltIn }
            .sorted { $0.createdAt > $1.createdAt }
        takes = ((try? Data(contentsOf: takesURL))
            .flatMap { try? decoder.decode([SpeechTake].self, from: $0) } ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    func reloadIfLanguageChanged() {
        if loadedLanguage != LanguageScope.active { reload() }
    }

    func markVideoPending(_ id: UUID, _ pending: Bool) {
        if pending { videoPending.insert(id) } else { videoPending.remove(id) }
    }

    func script(id: UUID) -> SpeechScript? { scripts.first { $0.id == id } }

    func takes(for scriptId: UUID) -> [SpeechTake] { takes.filter { $0.scriptId == scriptId } }

    func best(for scriptId: UUID) -> Int? { takes(for: scriptId).map(\.metrics.overall).max() }

    func add(_ script: SpeechScript) {
        scripts.removeAll { $0.id == script.id }
        let builtIn = scripts.filter(\.isBuiltIn)
        scripts = builtIn + ([script] + scripts.filter { !$0.isBuiltIn })
        writeScripts()
    }

    func deleteScript(id: UUID) {
        for take in takes(for: id) { deleteTake(id: take.id) }
        scripts.removeAll { $0.id == id && !$0.isBuiltIn }
        writeScripts()
    }

    func save(_ take: SpeechTake) {
        takes.removeAll { $0.id == take.id }
        takes.insert(take, at: 0)
        writeTakes()
    }

    func deleteTake(id: UUID) {
        guard let take = takes.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: Self.mediaURL(take.audioFilename))
        if let video = take.videoFilename {
            try? FileManager.default.removeItem(at: Self.mediaURL(video))
        }
        takes.removeAll { $0.id == id }
        writeTakes()
    }

    /// Drops the camera take and keeps everything else — the voice, the
    /// score, the notes.
    func deleteVideo(takeId: UUID) {
        guard var take = takes.first(where: { $0.id == takeId }), let video = take.videoFilename else { return }
        try? FileManager.default.removeItem(at: Self.mediaURL(video))
        take.videoFilename = nil
        save(take)
    }

    private func writeScripts() {
        let own = scripts.filter { !$0.isBuiltIn }
        guard let data = try? encoder.encode(own) else { return }
        try? data.write(to: scriptsURL, options: .atomic)
    }

    private func writeTakes() {
        guard let data = try? encoder.encode(takes) else { return }
        try? data.write(to: takesURL, options: .atomic)
    }
}
