import Foundation

/// One synced kind: how to read its items off the disk, how to combine one
/// item with the cloud's copy, and how to lay the merged set back down.
///
/// Reads go straight to the FILES by path, never through the store
/// singletons — those are pinned to the active language, and a pull for a
/// language the learner isn't currently in still has to land. Writes go the
/// same way and then poke the store so what's in memory matches.
protocol SyncKindHandler {
    var kind: SyncKind { get }
    /// Items on disk for `lang` (nil for a global kind), keyed by the item's
    /// sync key, each as its canonical payload. `nil` = the file exists but
    /// can't be decoded; the pass skips the kind rather than tombstoning
    /// everything in it.
    func read(lang: String?) -> SyncSnapshot?
    /// The one rule for this kind. `local == nil` means the item isn't on
    /// this device. Return nil to delete it locally.
    func merge(local: SyncSide?, remote: SyncSide) -> Data?
    /// Persist the whole merged set and refresh whatever holds it in memory.
    @MainActor func write(_ items: [String: SyncItem], lang: String?) throws
    /// Anything outside this kind's own file that a deletion drags along.
    func cascade(deletedKey: String, lang: String?, previous: Data?) -> [SyncCascade]
}

extension SyncKindHandler {
    func cascade(deletedKey: String, lang: String?, previous: Data?) -> [SyncCascade] { [] }
}

struct SyncItem {
    var payload: Data
    /// The LWW timestamp the merge settled on — what an ordered list sorts by.
    var at: Date
}

enum SyncCascade {
    /// A talk is gone: its cards go, its audio goes.
    case sessionDeleted(sessionId: UUID, turnIds: [UUID], lang: String)
    /// A blob file this device holds is no longer wanted.
    case deleteFile(kind: SyncKind, key: String)
}

// MARK: - Merge rules

enum SyncMerge {
    /// Newest side wins, deletion included. An equal payload keeps the local
    /// bytes so nothing is rewritten for nothing. Ties go to the remote —
    /// deterministic, and the same on both devices.
    static func lww(_ local: SyncSide?, _ remote: SyncSide) -> Data? {
        guard let local else { return remote.deleted ? nil : remote.payload }
        if remote.deleted {
            return remote.at >= local.at ? nil : local.payload
        }
        if local.deleted { return remote.at >= local.at ? remote.payload : nil }
        if local.payload == remote.payload { return local.payload }
        return remote.at >= local.at ? remote.payload : local.payload
    }

    /// A remote deletion always deletes — for records whose deletion is the
    /// learner's decision about the THING (a talk deleted is deleted, however
    /// much the other device reviewed its cards). Both present → `combine`.
    static func tombstoneWins(_ local: SyncSide?, _ remote: SyncSide,
                              combine: (Data, Data) -> Data) -> Data? {
        if remote.deleted { return nil }
        guard let local, let lp = local.payload, !local.deleted else { return remote.payload }
        guard let rp = remote.payload else { return lp }
        return lp == rp ? lp : combine(lp, rp)
    }

    /// Both present → `combine`; a deletion wins only if it is newer than
    /// the other side's last change (so a word re-bookmarked after being
    /// removed elsewhere comes back).
    static func combineOrNewerDelete(_ local: SyncSide?, _ remote: SyncSide,
                                     combine: (Data, Data) -> Data) -> Data? {
        guard let local, let lp = local.payload, !local.deleted else {
            return remote.deleted ? nil : remote.payload
        }
        if remote.deleted { return remote.at >= local.at ? nil : lp }
        guard let rp = remote.payload else { return lp }
        return lp == rp ? lp : combine(lp, rp)
    }

    /// Never deletes; both present → `combine`.
    static func union(_ local: SyncSide?, _ remote: SyncSide,
                      combine: (Data, Data) -> Data) -> Data? {
        guard let local, let lp = local.payload, !local.deleted else {
            return remote.deleted ? local?.payload : remote.payload
        }
        guard !remote.deleted, let rp = remote.payload else { return lp }
        return lp == rp ? lp : combine(lp, rp)
    }

    /// Lifts a typed combine over canonical payloads. A payload that fails
    /// to decode (a newer build's shape) yields the OTHER side rather than
    /// throwing the item away.
    static func typed<T: Codable>(_ f: @escaping (T, T) -> T) -> (Data, Data) -> Data {
        { a, b in
            guard let x = try? SyncCanonical.decode(T.self, from: a) else { return b }
            guard let y = try? SyncCanonical.decode(T.self, from: b) else { return a }
            return (try? SyncCanonical.encode(f(x, y))) ?? b
        }
    }
}

// MARK: - File helpers

enum SyncFiles {
    /// Tests point the sync at a scratch tree so two engines can stand in
    /// for two devices in one process. Never set in the app.
    static var documentsOverride: URL?

    static var documents: URL {
        documentsOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ filename: String, lang: String?) -> URL {
        guard let lang else { return documents.appendingPathComponent(filename) }
        if documentsOverride != nil {
            let dir = documents.appendingPathComponent("lang", isDirectory: true)
                .appendingPathComponent(lang, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(filename)
        }
        return LanguageScope.directory(for: lang).appendingPathComponent(filename)
    }

    /// The stores' own on-disk style: pretty, sorted, ISO-8601 dates.
    static let storeEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
    static let storeDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
    /// VocabStore and PracticeLog write with a bare encoder (dates as
    /// seconds since 2001). Their files must be read and written the same
    /// way or the store can't open them.
    static let bareEncoder = JSONEncoder()
    static let bareDecoder = JSONDecoder()

    /// Decodes a file, distinguishing "absent" (empty result) from
    /// "unreadable" (nil), which is the difference between an empty store
    /// and one the sync must not touch.
    static func read<T: Decodable>(_ type: T.Type, at url: URL, decoder: JSONDecoder,
                                   empty: T) -> T? {
        guard let data = try? Data(contentsOf: url) else { return empty }
        return try? decoder.decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Generic handlers

/// A file holding `[T]` where each item has a stable id.
struct ArrayKind<T: Codable & Identifiable>: SyncKindHandler where T.ID == UUID {
    let kind: SyncKind
    let filename: String
    var encoder: JSONEncoder = SyncFiles.storeEncoder
    var decoder: JSONDecoder = SyncFiles.storeDecoder
    /// Transform an item before it becomes a payload (strip device-local
    /// fields). Identity by default.
    var outbound: (T) -> T = { $0 }
    var mergeRule: (SyncSide?, SyncSide) -> Data?
    var sortForFile: ([T]) -> [T] = { $0 }
    /// Collapses duplicates the file should never carry (two ids for one
    /// sentence). Identity by default.
    var collapse: ([T]) -> [T] = { $0 }
    var cascadeRule: (String, String?, T?) -> [SyncCascade] = { _, _, _ in [] }
    var afterWrite: @MainActor (String?) -> Void = { _ in }

    func read(lang: String?) -> SyncSnapshot? {
        guard let list = SyncFiles.read([T].self, at: SyncFiles.url(filename, lang: lang),
                                        decoder: decoder, empty: []) else { return nil }
        var out: SyncSnapshot = [:]
        for item in list {
            guard let data = try? SyncCanonical.encode(outbound(item)) else { continue }
            out[item.id.uuidString] = data
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? { mergeRule(local, remote) }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        var list: [T] = []
        for item in items.values {
            if let decoded = try? SyncCanonical.decode(T.self, from: item.payload) {
                list.append(decoded)
            }
        }
        list = sortForFile(collapse(list))
        try SyncFiles.write(list, to: SyncFiles.url(filename, lang: lang), encoder: encoder)
        afterWrite(lang)
    }

    func cascade(deletedKey: String, lang: String?, previous: Data?) -> [SyncCascade] {
        let item = previous.flatMap { try? SyncCanonical.decode(T.self, from: $0) }
        return cascadeRule(deletedKey, lang, item)
    }
}

/// A file holding `[String: V]`.
struct DictKind<V: Codable>: SyncKindHandler {
    let kind: SyncKind
    let filename: String
    var encoder: JSONEncoder = SyncFiles.storeEncoder
    var decoder: JSONDecoder = SyncFiles.storeDecoder
    var mergeRule: (SyncSide?, SyncSide) -> Data?
    var afterWrite: @MainActor (String?) -> Void = { _ in }

    func read(lang: String?) -> SyncSnapshot? {
        guard let dict = SyncFiles.read([String: V].self, at: SyncFiles.url(filename, lang: lang),
                                        decoder: decoder, empty: [:]) else { return nil }
        var out: SyncSnapshot = [:]
        for (key, value) in dict {
            if let data = try? SyncCanonical.encode(value) { out[key] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? { mergeRule(local, remote) }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        var dict: [String: V] = [:]
        for (key, item) in items {
            if let v = try? SyncCanonical.decode(V.self, from: item.payload) { dict[key] = v }
        }
        try SyncFiles.write(dict, to: SyncFiles.url(filename, lang: lang), encoder: encoder)
        afterWrite(lang)
    }
}

/// A file holding `[String]` — a set, or an ordered notebook (newest first).
/// The key is the string itself; the payload wraps it so a payload is never
/// empty.
struct StringListKind: SyncKindHandler {
    struct Wrapped: Codable { var text: String }

    let kind: SyncKind
    let filename: String
    /// Ordered lists keep newest-first by the item's LWW time; sets are
    /// written sorted so the file is stable.
    var ordered: Bool
    var mergeRule: (SyncSide?, SyncSide) -> Data?
    var afterWrite: @MainActor (String?) -> Void = { _ in }

    func read(lang: String?) -> SyncSnapshot? {
        guard let list = SyncFiles.read([String].self, at: SyncFiles.url(filename, lang: lang),
                                        decoder: SyncFiles.bareDecoder, empty: []) else { return nil }
        var out: SyncSnapshot = [:]
        for text in list {
            if let data = try? SyncCanonical.encode(Wrapped(text: text)) { out[text] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? { mergeRule(local, remote) }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        let url = SyncFiles.url(filename, lang: lang)
        let current = SyncFiles.read([String].self, at: url, decoder: SyncFiles.bareDecoder, empty: []) ?? []
        let position = Dictionary(current.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var list: [String] = []
        if ordered {
            // Newest first; among items the diff first saw at the same
            // moment (everything present at enable), keep the file's order.
            list = items.sorted { a, b in
                if a.value.at != b.value.at { return a.value.at > b.value.at }
                return (position[a.key] ?? Int.max) < (position[b.key] ?? Int.max)
            }.map { $0.key }
        } else {
            list = items.keys.sorted()
        }
        try SyncFiles.write(list, to: url, encoder: SyncFiles.bareEncoder)
        afterWrite(lang)
    }
}

/// A `[String: Int]` map in UserDefaults (the per-day second counts).
struct DefaultsCountKind: SyncKindHandler {
    struct Wrapped: Codable { var seconds: Int }

    let kind: SyncKind
    let defaultsKey: String

    func read(lang: String?) -> SyncSnapshot? {
        let map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:]
        var out: SyncSnapshot = [:]
        for (day, seconds) in map {
            if let data = try? SyncCanonical.encode(Wrapped(seconds: seconds)) { out[day] = data }
        }
        return out
    }

    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        SyncMerge.combineOrNewerDelete(local, remote, combine: SyncMerge.typed { (a: Wrapped, b: Wrapped) in
            Wrapped(seconds: max(a.seconds, b.seconds))
        })
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        var map: [String: Int] = [:]
        for (day, item) in items {
            if let w = try? SyncCanonical.decode(Wrapped.self, from: item.payload) { map[day] = w.seconds }
        }
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}

/// A folder of files carried as assets. The "payload" on disk is only the
/// fingerprint; the engine moves the bytes.
struct BlobKind: SyncKindHandler {
    let kind: SyncKind
    let directory: URL
    /// Which files in the folder are this kind's (nil = every regular file).
    var accepts: (String) -> Bool = { _ in true }

    func fileURL(_ key: String) -> URL { directory.appendingPathComponent(key) }

    func read(lang: String?) -> SyncSnapshot? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var out: SyncSnapshot = [:]
        for name in names where accepts(name) && !name.hasPrefix(".") {
            let url = fileURL(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  (attrs[.type] as? FileAttributeType) == .typeRegular,
                  let size = attrs[.size] as? Int,
                  let mtime = attrs[.modificationDate] as? Date else { continue }
            out[name] = Data(SyncCanonical.blobFingerprint(size: size, modifiedAt: mtime).utf8)
        }
        return out
    }

    /// A blob is written once, so whichever side has bytes has THE bytes;
    /// only a deletion moves anything.
    func merge(local: SyncSide?, remote: SyncSide) -> Data? {
        if remote.deleted { return nil }
        return local?.payload ?? remote.payload
    }

    @MainActor
    func write(_ items: [String: SyncItem], lang: String?) throws {
        // The engine removes deleted files and downloads wanted ones; the
        // fingerprints themselves are never written anywhere.
    }
}
