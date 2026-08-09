import Foundation

/// JSON-on-disk store for the user's saved counterparts (people from real
/// life used in Watch mode dialogues). Same pattern as `SessionStore` /
/// `DrillStore` — Phase 2 moves to Supabase.
final class CounterpartStore {
    static let shared = CounterpartStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "counterparts.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() -> [Counterpart] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([Counterpart].self, from: data) else {
            return []
        }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ counterpart: Counterpart) {
        var all = load()
        all.removeAll { $0.id == counterpart.id }
        // A Find-people persona is ONE person however many times it gets
        // materialized — dedupe on the remote id too, so a row written before
        // ids became remote-derived can't survive as a twin.
        if let rid = counterpart.remoteId {
            all.removeAll { $0.remoteId == rid }
        }
        var c = counterpart
        c.updatedAt = Date()
        all.append(c)
        write(all)
    }

    /// One-time repair for rows written while a Find-people persona minted a
    /// fresh local id on every materialization: collapse each remote persona
    /// back to a single row (the one with the now-canonical derived id) and
    /// report the id remapping so sessions filed against a twin can be
    /// pointed at the survivor instead of losing their person. No-op once
    /// clean, so it's safe to run at every launch.
    @discardableResult
    func repairRemoteDuplicates() -> [UUID: UUID] {
        let all = load()
        var byRemote: [String: [Counterpart]] = [:]
        for c in all { if let rid = c.remoteId { byRemote[rid, default: []].append(c) } }
        let dupes = byRemote.filter { $0.value.count > 1 }
        guard !dupes.isEmpty else { return [:] }

        var remap: [UUID: UUID] = [:]
        var survivors: Set<UUID> = []
        for (rid, twins) in dupes {
            let canonical = PublicPersonaService.localId(forRemote: rid)
            // Prefer the canonical row; otherwise the most recently touched
            // twin (load() is newest-first) becomes the survivor.
            let keep = twins.first { $0.id == canonical } ?? twins[0]
            survivors.insert(keep.id)
            for t in twins where t.id != keep.id { remap[t.id] = keep.id }
        }
        write(all.filter { remap[$0.id] == nil })
        return remap
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        write(all)
    }

    private func write(_ list: [Counterpart]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
