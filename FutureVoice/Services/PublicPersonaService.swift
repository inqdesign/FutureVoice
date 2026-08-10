import Foundation

/// The shared "Find people" pool — public personas any learner can pick as a
/// conversation partner, like meeting a stranger at a language school. Reads
/// `public_personas` on Supabase (curated rows now, user-contributed later).
///
/// Bookmarks are a purely local affair (a set of remote ids in UserDefaults):
/// bookmarking someone has zero effect on them, which is the whole social
/// contract of the feature.
enum PublicPersonaService {

    // MARK: - Remote rows

    struct PublicPersona: Decodable, Identifiable, Hashable {
        let id: String
        let owner_user_id: String?
        let display_name: String
        let intro: String
        let location: String
        let occupation: String
        let interests: String
        let conversation_style: String
        let language: String
        let voice_preset_id: String
        let kind: String?

        /// What the sheet groups this row under. A published learner is a
        /// "user" whatever the column says — ownership is the fact, `kind`
        /// only distinguishes the seeded rows from each other.
        var group: Group {
            return owner_user_id != nil ? .user : .character
        }
    }

    /// The pools Find people shows behind its tabs. `kind` on the row is
    /// what a future third pool would key off; today ownership decides.
    enum Group: String, CaseIterable, Identifiable {
        case user, character
        var id: String { rawValue }
    }

    private static let columns =
        "id,owner_user_id,display_name,intro,location,occupation,interests,conversation_style,language,voice_preset_id,kind"

    /// The whole active pool for one target language. The pool is curated-
    /// catalog sized (tens, not thousands), so one fetch + local shuffle/
    /// filter beats server-side pagination for now. The user's own published
    /// intro is filtered out — you don't meet yourself.
    static func fetchPool(language: String) async throws -> [PublicPersona] {
        var rows: [PublicPersona] = try await SupabaseProvider.shared
            .from("public_personas")
            .select(columns)
            .eq("language", value: language)
            .eq("is_active", value: true)
            .execute()
            .value
        if let uid = try? await SupabaseProvider.shared.auth.session.user.id.uuidString {
            rows.removeAll { $0.owner_user_id == uid }
        }
        return rows
    }

    /// "People today" — a deterministic daily shuffle so the sheet shows the
    /// same faces all day but different ones tomorrow. Seeded by day number,
    /// not Date.now-per-call, so re-opening the sheet doesn't reshuffle.
    static func todaysPeople(from pool: [PublicPersona], count: Int = 6,
                             excluding met: Set<String>, day: Int? = nil) -> [PublicPersona] {
        let dayNumber = day ?? Int(Date().timeIntervalSince1970 / 86_400)
        var generator = SeededGenerator(seed: UInt64(dayNumber))
        let fresh = pool.filter { !met.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).shuffled(using: &generator).prefix(count).map { $0 }
    }

    /// Local substring search over name, intro, interests, occupation.
    static func search(_ query: String, in pool: [PublicPersona]) -> [PublicPersona] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return pool.filter {
            $0.display_name.lowercased().contains(q)
                || $0.intro.lowercased().contains(q)
                || $0.interests.lowercased().contains(q)
                || $0.occupation.lowercased().contains(q)
                || $0.location.lowercased().contains(q)
        }
    }

    /// Materialize a remote persona as a local Counterpart so the whole
    /// existing machinery (composer, scenes, prompts, voice) just works.
    /// Reuses the already-saved Counterpart when the user met them before —
    /// sessions link on the LOCAL id, so it must stay stable.
    static func asCounterpart(_ p: PublicPersona, existing: [Counterpart]) -> Counterpart {
        if let known = existing.first(where: { $0.remoteId == p.id }) { return known }
        var c = Counterpart(
            id: localId(forRemote: p.id),
            name: p.display_name,
            relationship: String(localized: "Met on Future Voice"),
            background: p.intro,
            conversationStyle: p.conversation_style,
            voicePresetId: VoicePreset.catalog.contains(where: { $0.id == p.voice_preset_id })
                ? p.voice_preset_id : VoicePreset.catalog.first!.id
        )
        c.location = p.location
        c.commonTopics = p.interests
        c.remoteId = p.id
        c.intro = p.intro
        c.personaKind = p.group.rawValue
        return c
    }

    /// Repair rows saved while `Counterpart.encode` was dropping `remoteId`:
    /// they came back from disk looking like people the user made themselves,
    /// which put every stranger they had ever talked to into Watch's own-people
    /// row. The match is exact, never a guess — a stranger's local id IS its
    /// remote id (see `localId`), so only rows whose id is literally a persona
    /// in the pool are touched. Saving through the store also collapses any
    /// twins the same bug left behind.
    @MainActor
    static func healRowsMissingRemoteId(pool: [PublicPersona],
                                        counterparts: [Counterpart]) -> Bool {
        guard !pool.isEmpty else { return false }
        let byLocalId = Dictionary(pool.map { (localId(forRemote: $0.id), $0) },
                                   uniquingKeysWith: { a, _ in a })
        var healed = false
        for c in counterparts where c.remoteId == nil {
            guard let p = byLocalId[c.id] else { continue }
            var fixed = c
            fixed.remoteId = p.id
            if fixed.intro.isEmpty { fixed.intro = p.intro }
            CounterpartStore.shared.save(fixed)
            healed = true
        }
        return healed
    }

    /// The local `Counterpart.id` for a remote persona, derived from its
    /// remote id so it is the SAME every time — minting one is idempotent.
    ///
    /// Without this the id was a fresh `UUID()` per call, and `asCounterpart`
    /// runs on every row render: a person saved from one render no longer
    /// matched the value a later render pushed, so each talk filed a new
    /// duplicate row (and its past talks, keyed on the old id, went missing
    /// from the person's card). Remote ids are already UUID strings, so the
    /// mapping is usually a straight parse; the hash path is a fallback for
    /// any non-UUID id a future pool might use.
    static func localId(forRemote remoteId: String) -> UUID {
        if let direct = UUID(uuidString: remoteId) { return direct }
        var bytes = [UInt8]()
        var seed = SeededGenerator(seed: UInt64(bitPattern: Int64(remoteId.hashValue)))
        for _ in 0..<2 { withUnsafeBytes(of: seed.next().bigEndian) { bytes.append(contentsOf: $0) } }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - My own public intro (one row per owner + language)

    /// The signed-in user's own published intro for one target language, if any.
    static func fetchMine(language: String) async throws -> PublicPersona? {
        let session = try await SupabaseProvider.shared.auth.session
        let rows: [PublicPersona] = try await SupabaseProvider.shared
            .from("public_personas")
            .select(columns)
            .eq("owner_user_id", value: session.user.id.uuidString)
            .eq("language", value: language)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Publish (or update) the user's self-introduction into the pool. The
    /// intro is written in the TARGET language — it doubles as the persona's
    /// conversational substance AND as writing practice for the author.
    static func publishMine(displayName: String, intro: String,
                            location: String, occupation: String, interests: String,
                            voicePresetId: String, language: String) async throws {
        let session = try await SupabaseProvider.shared.auth.session
        struct Row: Encodable {
            let owner_user_id: String
            let display_name: String
            let intro: String
            let location: String
            let occupation: String
            let interests: String
            let language: String
            let voice_preset_id: String
            let is_active: Bool
        }
        let row = Row(owner_user_id: session.user.id.uuidString,
                      display_name: displayName, intro: intro,
                      location: location, occupation: occupation, interests: interests,
                      language: language, voice_preset_id: voicePresetId,
                      is_active: true)
        if let existing = try await fetchMine(language: language) {
            try await SupabaseProvider.shared
                .from("public_personas")
                .update(row)
                .eq("id", value: existing.id)
                .execute()
        } else {
            try await SupabaseProvider.shared
                .from("public_personas")
                .insert(row)
                .execute()
        }
    }

    /// Take the user's intro out of the pool entirely.
    static func withdrawMine(language: String) async throws {
        let session = try await SupabaseProvider.shared.auth.session
        try await SupabaseProvider.shared
            .from("public_personas")
            .delete()
            .eq("owner_user_id", value: session.user.id.uuidString)
            .eq("language", value: language)
            .execute()
    }

    // MARK: - Auto-publish (current users appear without lifting a finger)

    /// Set once the user has taken control of their public intro by hand —
    /// published or taken it down in Me → Find people. From then on the
    /// auto-sync below never touches their row again: an explicit choice
    /// always beats the automatic one.
    static let manualIntroKey = "futurevoice.publicIntroManaged"

    /// Mirror the onboarding profile into the pool so EXISTING users show up
    /// in Find people without doing anything. Runs fire-and-forget at app
    /// start; skips when the user manages their intro manually, when the
    /// persona is too thin to carry a conversation, or when signed out.
    /// Re-running keeps the row in step with persona edits.
    static func autoSyncMyPersona(_ persona: UserPersona?, language: String) async {
        guard !UserDefaults.standard.bool(forKey: manualIntroKey),
              let p = persona, p.isMinimallyComplete else { return }
        let intro = composedIntro(p)
        guard intro.count >= 30 else { return }
        guard let uid = try? await SupabaseProvider.shared.auth.session.user.id else { return }
        // Stable per-user voice pick so "you" doesn't change voices between
        // launches — hash the user id into the preset catalog.
        let voice = VoicePreset.catalog[abs(uid.uuidString.hashValue) % VoicePreset.catalog.count]
        try? await publishMine(
            displayName: p.displayName,
            intro: intro,
            location: [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", "),
            occupation: p.occupation,
            interests: p.interests.joined(separator: ", "),
            voicePresetId: voice.id,
            language: language)
    }

    /// The onboarding profile, folded into one spoken-style paragraph. The
    /// user wrote these fields in their own words (often their native
    /// language) — the conversation prompt's language guard keeps the talk
    /// in the target language regardless.
    private static func composedIntro(_ p: UserPersona) -> String {
        var parts: [String] = []
        if !p.occupation.isEmpty { parts.append(p.occupation) }
        if !p.household.isEmpty { parts.append(p.household) }
        if !p.lengthOfStay.isEmpty, !p.city.isEmpty {
            parts.append("\(p.city) · \(p.lengthOfStay)")
        }
        if !p.situations.isEmpty { parts.append(p.situations.joined(separator: ", ")) }
        if !p.freeNotes.isEmpty { parts.append(p.freeNotes) }
        return parts.joined(separator: "\n")
    }

    // MARK: - Bookmarks (local only)

    private static let bookmarksKey = "futurevoice.personaBookmarks"

    static func bookmarkedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: bookmarksKey) ?? [])
    }

    static func isBookmarked(_ remoteId: String) -> Bool {
        bookmarkedIds().contains(remoteId)
    }

    @discardableResult
    static func toggleBookmark(_ remoteId: String) -> Bool {
        var ids = bookmarkedIds()
        let nowOn: Bool
        if ids.contains(remoteId) { ids.remove(remoteId); nowOn = false }
        else { ids.insert(remoteId); nowOn = true }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: bookmarksKey)
        return nowOn
    }

    // MARK: - Deterministic shuffle support

    /// SplitMix64 — tiny seeded RNG so "today's people" is stable within a day.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
