import Foundation

/// On-disk persistence for the `LearnerProfile` (`Documents/profile.json`).
/// Mirrors `PersonaStore` / `DrillStore` pattern — Phase 2 moves to Supabase.
///
/// One profile per target language, keyed inside a single JSON file so
/// switching target language later doesn't lose progress in the old one.
final class ProfileStore {
    static let shared = ProfileStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Stable anonymous learner id, minted once per install. Sessions and
    /// profiles share it so local data hangs together before Supabase sync.
    static var localUserId: UUID {
        let key = "futurevoice.localUserId"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let fresh = UUID()
        UserDefaults.standard.set(fresh.uuidString, forKey: key)
        return fresh
    }

    init(filename: String = "profile.json") {
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

    /// Profile for the given target language, creating a fresh one on first use.
    func load(targetLanguage: String, proficiency: CEFRLevel) -> LearnerProfile {
        if let existing = loadAll().first(where: { $0.targetLanguage == targetLanguage }) {
            return existing
        }
        return LearnerProfile(
            id: UUID(),
            userId: Self.localUserId,
            targetLanguage: targetLanguage,
            proficiencyLevel: proficiency,
            recurringMistakes: [],
            weakVocabAreas: [],
            strongPatterns: [],
            totalSessions: 0,
            totalSpeakingSeconds: 0,
            lastSessionAt: nil,
            summaryEmbedding: nil
        )
    }

    func save(_ profile: LearnerProfile) {
        var all = loadAll()
        all.removeAll { $0.targetLanguage == profile.targetLanguage }
        all.append(profile)
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func loadAll() -> [LearnerProfile] {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? decoder.decode([LearnerProfile].self, from: data) else {
            return []
        }
        return profiles
    }
}
