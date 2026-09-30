import Foundation

/// Rotating pools of Free-talk greeting lines, one per language + persona
/// (`Documents/freetalk_openers_by_language.json`).
///
/// A free talk opens with more or less the same kind of greeting every time,
/// so paying a Gemini call per session to write one (and an ElevenLabs call
/// to voice a line that's never repeated) is waste. Instead ONE Gemini call
/// writes a small pool of openers; sessions rotate through it, and because
/// the texts repeat verbatim, `PhraseAudioStore`'s content cache makes every
/// TTS after each line's first play free.
///
/// Topic/scenario/news openers stay dynamic — this pool is only for the
/// no-topic free talk. The pool is keyed to language + persona name and
/// regenerates when either changes. Until a pool exists, `fallbackOpener`
/// (bundled, per language) is what a call speaks — the first free talk must
/// never wait on a live Gemini round trip.
final class FreeTalkOpeners {
    static let shared = FreeTalkOpeners()

    struct Pool: Codable {
        var key: String
        var lines: [String]
        var cursor: Int
        var generatedAt: Date
    }

    private struct Payload: Decodable {
        let openers: [String]
    }

    /// The single-pool file from before 2026-09-28 — read for migration only.
    private let fileURL: URL
    private let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "freetalk_openers.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)
        self.storeURL = dir.appendingPathComponent(
            (filename as NSString).deletingPathExtension + "_by_language.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    private static func key(language: String, personaName: String?) -> String {
        "\(language)|\(personaName ?? "")"
    }

    /// The line a free talk opens on while no pool exists yet — the very
    /// first call, or the one right after a language/persona switch. Bundled
    /// per target language so the greeting NEVER waits on a live Gemini call;
    /// the pool is generated in the background instead. MATERIAL → target
    /// language. Deliberately name-free: one cache entry serves every persona,
    /// and its TTS can be warmed before a persona even exists.
    static func fallbackOpener(language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return fallbackOpeners[code] ?? fallbackOpeners["en"]!
    }

    /// The line the VERY FIRST free talk opens on, before the fluent self has
    /// met the learner (`UserPersona.metAt == nil`). It outranks both the pool
    /// and the fallback above, because a rotating "good to hear you" is a
    /// greeting between people who already know each other — and the whole of
    /// that first call is spent meeting (see `ConversationEngine`'s FIRST CALL
    /// block, which the rest of the conversation runs on).
    ///
    /// **This one is a PROMISE, not a greeting, and that is deliberate.** It
    /// says who it is, that it is looking forward to the talks ahead, and
    /// that the learner can become it — so don't give up, let's do this
    /// together.
    ///
    /// Several rounds were spent writing the casual-phone-call version of
    /// this line instead, and every one of them failed the same way: "you, a
    /// few years from now" is a premise to decode, "the you who speaks this
    /// without thinking about it" is a definition and nobody introduces
    /// themselves with a relative clause, "same voice, right?" dodges the
    /// sentence altogether. All of them had the character narrating the app's
    /// own premise, which reads as a product explaining itself. The fix was
    /// not a better casual line. It was noticing that the first call is not
    /// small talk: it is the moment the learner decides whether this is worth
    /// doing, and the only thing worth saying then is why it is.
    ///
    /// So this line breaks a rule the rest of the call keeps, on purpose: it
    /// runs longer than `ConversationEngine.maxTurnSentences` (that ceiling
    /// governs the model's turns, not this one — see the type's doc). Nothing
    /// after it is allowed to sound like this; the FIRST CALL block takes
    /// over on the next turn and gets on with actually meeting them.
    ///
    /// **It still has to end on a question.** The promise is the point, but a
    /// promise leaves the learner holding an open mic with nothing specific
    /// to say, and a first call that opens on a silence is a first call that
    /// gets hung up. The question is small on purpose — "what are you up to
    /// these days" is answerable in three words at A1 and opens exactly the
    /// ground the FIRST CALL block wants (what they do with their days),
    /// where "tell me about yourself" is the interview line and has no floor
    /// and no ceiling.
    ///
    /// Bundled for the same reason as the fallback: the first greeting of all
    /// must never wait on a live Gemini call. MATERIAL → target language, and
    /// name-free so one cache entry serves everyone.
    ///
    /// Nine entries because `LanguageCatalog.targets` has nine, but only the
    /// three with a CEFR wordlist are reachable from the picker today (en,
    /// de, ko — see `selectableTargets`). The other six are written in the
    /// same voice and wait for their wordlist.
    static func introOpener(language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return introOpeners[code] ?? introOpeners["en"]!
    }

    private static let introOpeners: [String: String] = [
        "en": "Hi. I'm the future you — the one who speaks English fluently. I can't wait for all the talks ahead of us. Don't give up, and let's get you here, together. So — what are you up to these days?",
        "de": "Hallo. Ich bin das zukünftige Du — das, das fließend Deutsch spricht. Ich freue mich auf all die Gespräche, die vor uns liegen. Gib nicht auf, und lass uns zusammen dafür sorgen, dass du hierher kommst. Also — was machst du gerade so?",
        "ko": "안녕. 나는 유창하게 말하는 미래의 너야. 앞으로 너와 함께할 많은 이야기들이 기대된다. 포기하지 말고, 지금의 네가 내가 될 수 있게 같이 해보자. 그래서 말인데, 요즘 어떻게 지내?",
        // Rewritten 2026-09-18 ("it doesn't breathe right"): the first cut put
        // a comma between a modifier and its noun (流暢に話す、未来のきみ) —
        // the synthesizer pauses there, mid-phrase — and opened in written
        // Japanese (楽しみでならない). Commas now sit only where a speaker
        // breathes; A/B by ear with scripts/tts-language-probe.sh.
        "ja": "やあ、未来のきみだよ。日本語、もうすらすら話せるようになったんだ。これからいっぱい話せるの、すごく楽しみ。今のきみがここまで来られるように、あきらめないで一緒にがんばろう。で、最近どうしてる？",
        "es": "Hola. Soy tu yo del futuro, el que habla español con fluidez. Tengo muchas ganas de todas las charlas que nos esperan. No te rindas, y vamos a llevarte hasta aquí, juntos. Bueno — ¿qué tal te va últimamente?",
        "fr": "Salut. Je suis le toi du futur, celui qui parle français couramment. J'ai hâte de toutes les conversations qui nous attendent. N'abandonne pas, et on va t'amener jusqu'ici, ensemble. Alors — tu fais quoi de tes journées en ce moment ?",
        "it": "Ciao. Sono il te del futuro, quello che parla italiano fluentemente. Non vedo l'ora di tutte le chiacchierate che ci aspettano. Non mollare, e arriviamoci insieme. Allora — cosa fai di bello in questi giorni?",
        "pt": "Oi. Sou o você do futuro, o que fala português com fluência. Mal posso esperar por todas as conversas que temos pela frente. Não desista, e vamos chegar até aqui juntos. Então — o que você anda fazendo esses dias?",
        "zh": "你好。我是流利说中文的未来的你。我很期待我们接下来的每一次聊天。别放弃，我们一起，让现在的你变成我。对了，你最近都在忙什么？",
    ]

    // Time-neutral since 2026-09-28: "how was your day?" is heard at 8 a.m.
    // as often as at 8 p.m., and a call that opens as if the day were over is
    // the "it thinks it's the afternoon" complaint in its first line.
    private static let fallbackOpeners: [String: String] = [
        "en": "Hey, good to hear you. What were you up to just now?",
        "de": "Hey, schön dich zu hören. Was hast du gerade gemacht?",
        "ko": "안녕, 목소리 들으니까 좋다. 방금 뭐 하고 있었어?",
        "ja": "やあ、話せてうれしいよ。いま何してたの？",
        "es": "Hola, qué bueno escucharte. ¿Qué estabas haciendo?",
        "fr": "Salut, ça fait plaisir de t'entendre. Tu faisais quoi, là\u{00A0}?",
        "it": "Ciao, che bello sentirti. Cosa stavi facendo?",
        "pt": "Oi, que bom te ouvir. O que você estava fazendo agora?",
        "zh": "嘿，听到你的声音真好。你刚才在忙什么？",
    ]

    /// The next greeting in rotation, or nil when no valid pool exists yet
    /// (caller falls back to a generated opener). Advances and persists the
    /// cursor so consecutive free talks don't repeat the same line.
    func next(language: String, personaName: String?) -> String? {
        guard var pool = load(key: Self.key(language: language, personaName: personaName)),
              !pool.lines.isEmpty else { return nil }
        let line = pool.lines[pool.cursor % pool.lines.count]
        pool.cursor = (pool.cursor + 1) % pool.lines.count
        save(pool)
        return line
    }

    /// The line `next()` WOULD return, without consuming it. Read-only — the
    /// launcher uses this to synthesize the upcoming greeting ahead of the
    /// tap, so the call opens on cached audio instead of an ElevenLabs round
    /// trip. Must stay in sync with `next()`'s index arithmetic.
    func peek(language: String, personaName: String?) -> String? {
        guard let pool = load(key: Self.key(language: language, personaName: personaName)),
              !pool.lines.isEmpty else { return nil }
        return pool.lines[pool.cursor % pool.lines.count]
    }

    /// Every line in the current pool (empty when none). Read-only — the
    /// launcher warms EACH line's TTS once, so any rotation position opens
    /// the call on cached audio.
    func lines(language: String, personaName: String?) -> [String] {
        guard let pool = load(key: Self.key(language: language, personaName: personaName)),
              !pool.lines.isEmpty else { return [] }
        return pool.lines
    }

    /// Synthesize EVERY pool line's audio that isn't cached yet, so any
    /// rotation position opens a call on cached audio — no ElevenLabs round
    /// trip on the greeting. Bounded cost: one synthesis per unique line per
    /// voice, ever (the content cache makes later uses free). A failure
    /// aborts the sweep (the rest would fail the same way); the live call
    /// still falls back to on-demand TTS.
    func warmAudio(language: String, personaName: String?, voiceId: String?) async {
        guard let voiceId else { return }
        do {
            for line in lines(language: language, personaName: personaName) {
                guard !Task.isCancelled else { return }
                try await warmLine(line, voiceId: voiceId)
            }
        } catch {
            return
        }
    }

    /// Synthesize ONE line into the phrase cache (no-op when already there,
    /// at the speed in force now). `allowLineage: false` mirrors the live
    /// call's lookup — warming a line the call would still consider a miss is
    /// pointless.
    private func warmLine(_ line: String, voiceId: String) async throws {
        let stale = needsBake(line)
        if stale { PhraseAudioStore.shared.removeAudio(text: line, voiceId: voiceId) }
        guard stale || PhraseAudioStore.shared.data(text: line, voiceId: voiceId,
                                                    allowLineage: false) == nil else { return }
        let audio: Data
        do {
            // A line of several sentences is made sentence by sentence so it
            // breathes like the answers after it (see `PacedSpeech`); a
            // one-sentence line, or an edge with no streaming, takes the
            // ordinary single synthesis.
            if let paced = try await PacedSpeech.synthesizePCM(
                voiceId: voiceId, text: line,
                modelId: ElevenLabsClient.conversationModelId, purpose: "turn") {
                audio = AudioLoudness.wavData(fromPCM16: paced.pcm,
                                              sampleRate: Int(paced.sampleRate))
            } else {
                audio = try await ElevenLabsClient.shared.synthesize(
                    voiceId: voiceId, text: line,
                    modelId: ElevenLabsClient.conversationModelId,
                    purpose: "turn")
            }
        } catch {
            Self.report("opener_audio_failed", language: nil, error: error)
            throw error
        }
        PhraseAudioStore.shared.save(audio, text: line, voiceId: voiceId)
        markBaked(line)
    }

    /// Failures only — one row each, never a success, so the volume is the
    /// number of things that went wrong.
    private static func report(_ event: String, language: String?, error: Error) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        let reason = String(String(describing: error).prefix(200))
        RealtimeTalkClient.step("\(event): \(reason)")
        var props = ["error": reason]
        if let language { props["language"] = language }
        Telemetry.log(event, props)
    }

    // MARK: - The opener follows the speaking speed

    /// **Openers are the one cached line that has to be re-made when the
    /// speaking speed moves** (2026-09-25). `PhraseAudioStore` keeps what is
    /// already produced — the default rung's cache tag is empty, so a line
    /// synthesized before `SpeechSpeed` existed is still found and still
    /// played. That is right for a library of hundreds of lines and wrong for
    /// the handful that OPEN a call: a learner who already had warm opener
    /// audio would hear the greeting at the old speed and every answer after
    /// it at the new one, on every call, for as long as the pool text held.
    /// The first thing a call says is the worst place to put that seam, and
    /// re-making a few short lines is the cheapest fix there is.
    ///
    /// Recorded per LINE rather than per language: the pool is per language
    /// AND per persona name, the intro and fallback lines are warmed from a
    /// different path, and a language-wide flag set by whichever of those ran
    /// first would leave the rest stale. Any future speed change re-bakes
    /// them the same way — this is not a one-off migration.
    private static let bakedSpeedKey = "futurevoice.freeTalkOpeners.bakedSpeed"
    private static let bakedLinesKey = "futurevoice.freeTalkOpeners.bakedLines"
    /// Pool text is regenerated over time, so the list would otherwise grow
    /// without end. Only the CURRENT pool can be asked for, and it is a
    /// handful of lines; dropping the oldest costs at worst one re-synthesis
    /// of a line nobody is going to hear again.
    private static let maxBakedLines = 60

    private func needsBake(_ line: String) -> Bool {
        let defaults = UserDefaults.standard
        let current = SpeechSpeed.current.multiplier
        if defaults.object(forKey: Self.bakedSpeedKey) as? Double != current {
            // The speed moved (or this build is the first to ask): every line
            // on file was made at some other speed.
            defaults.set(current, forKey: Self.bakedSpeedKey)
            defaults.removeObject(forKey: Self.bakedLinesKey)
            return true
        }
        return !(defaults.stringArray(forKey: Self.bakedLinesKey) ?? []).contains(line)
    }

    /// Marked only after the audio is on disk, so a failed synthesis is tried
    /// again next time instead of being remembered as done.
    private func markBaked(_ line: String) {
        let defaults = UserDefaults.standard
        var lines = defaults.stringArray(forKey: Self.bakedLinesKey) ?? []
        guard !lines.contains(line) else { return }
        lines.append(line)
        if lines.count > Self.maxBakedLines {
            lines.removeFirst(lines.count - Self.maxBakedLines)
        }
        defaults.set(lines, forKey: Self.bakedLinesKey)
    }

    /// One-stop warm-up: make the NEXT free talk open on cached assets
    /// whatever state it finds. While no pool exists, the bundled fallback
    /// line is what a call would speak — warm its audio FIRST (it's one short
    /// line, the cheapest path to an instant first call), then generate the
    /// pool text, then warm every pool line. Everything is cache-checked, so
    /// repeat calls cost nothing. Called from the Talk launcher and from
    /// every point that mints a new voice id (clone, re-record, accent remix)
    /// — a new id invalidates all warmed audio at once.
    func warmFirstCall(language: String, personaName: String?,
                       proficiency: CEFRLevel, voiceId: String?,
                       firstMeeting: Bool = false) async {
        // The introduction line is what an unmet learner's call actually
        // opens on — warming the pool around it would leave the one greeting
        // they're going to hear as the only slow one.
        if let voiceId, firstMeeting {
            try? await warmLine(Self.introOpener(language: language), voiceId: voiceId)
        }
        if let voiceId, !hasPool(language: language, personaName: personaName) {
            try? await warmLine(Self.fallbackOpener(language: language), voiceId: voiceId)
        }
        await warmUp(language: language, personaName: personaName, proficiency: proficiency)
        await warmAudio(language: language, personaName: personaName, voiceId: voiceId)
    }

    /// True when a valid pool exists for this language/persona. Read-only —
    /// unlike `next()` it never advances the rotation cursor.
    func hasPool(language: String, personaName: String?) -> Bool {
        guard let pool = load(key: Self.key(language: language, personaName: personaName)),
              !pool.lines.isEmpty else { return false }
        return true
    }

    /// Fire-and-forget warm-up for the Talk launcher: generate the pool ahead
    /// of the first "Let's talk" so that call opens on a canned line instead
    /// of holding the greeting hostage to a live Gemini call (which, cold,
    /// used to be the multi-second blank screen on the first free talk).
    /// No-op when a valid pool already exists; failures stay silent — the
    /// in-call fallback path still generates on demand.
    func warmUp(language: String, personaName: String?, proficiency: CEFRLevel) async {
        guard !hasPool(language: language, personaName: personaName) else { return }
        _ = try? await generatePool(language: language, personaName: personaName,
                                    proficiency: proficiency)
    }

    /// Generate (or refresh) the pool with one Gemini call. Returns the first
    /// line in rotation so the generating session can use it directly.
    func generatePool(language: String,
                      personaName: String?,
                      proficiency: CEFRLevel) async throws -> String {
        do {
            return try await writePool(language: language, personaName: personaName,
                                       proficiency: proficiency)
        } catch {
            // Every caller discards this with `try?`, and a pool that is never
            // written is a call that opens on the fallback line forever — each
            // one a fresh ElevenLabs take nobody can see the reason for.
            Self.report("freetalk_openers_failed", language: language, error: error)
            throw error
        }
    }

    private func writePool(language: String,
                           personaName: String?,
                           proficiency: CEFRLevel) async throws -> String {
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: Self.systemPrompt(language: language, personaName: personaName,
                                      proficiency: proficiency),
            messages: [GeminiClient.Message(role: .user, content: "Write the greetings.")],
            model: .flashLite31,
            maxTokens: 1200,
            purpose: "freetalk-openers",
            idempotencyKey: "freetalk-openers:\(Self.key(language: language, personaName: personaName))"
        )
        let lines = payload.openers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else {
            throw GeminiError.jsonNotFound(raw: "empty opener pool")
        }
        save(Pool(key: Self.key(language: language, personaName: personaName),
                  lines: lines, cursor: 1, generatedAt: Date()))
        return first
    }

    private static func systemPrompt(language: String, personaName: String?,
                                     proficiency: CEFRLevel) -> String {
        let name = (personaName?.isEmpty == false) ? personaName! : "the learner"
        let languageName = LanguageCatalog.englishName(language)
        return """
        You are the learner's fluent future self opening a casual, free-form
        voice chat in \(languageName). Write 6 SHORT greeting openers (6–14 words
        each) that could start such a call on any day, at any time of day.

        Rules:
        - Warm, natural spoken \(languageName) a CEFR \(proficiency.rawValue.uppercased()) learner easily follows.
        - \(CoachingLanguage.breathPunctuation)
        - Each opener distinct in flavor; every one must invite a reply.
        - Address \(name) by name in AT MOST two of them.
        - In a language that separates formal from informal address (Korean
          반말, Japanese plain form, German du, French tu, Spanish tú…), use the
          INFORMAL form — it is you talking to yourself.
        - No references to specific shared events, dates, news, or time of day —
          and nothing that assumes the day is over or just starting ("how was
          your day", "good morning", "tonight"): each line is heard at any hour.
        - Speakable as-is: no placeholders, brackets, or stage directions.

        Return STRICT JSON only — no prose, no code fences:
        { "openers": ["...", "..."] }
        """
    }

    // MARK: - Disk

    /// One pool PER language + persona, in one file. Until 2026-09-28 the file
    /// held a single pool, so a learner who talked in two languages threw one
    /// language's pool away every time they used the other — each switch
    /// meant a new Gemini call, the bundled fallback line in the meantime,
    /// and new ElevenLabs takes of lines whose audio had already been paid
    /// for. The old single-pool file is read once and folded in.
    private struct Store: Codable {
        var pools: [String: Pool]
    }
    /// Languages × persona names a learner actually uses is a handful; the
    /// cap only stops a long history of renames from growing the file.
    private static let maxPools = 8

    private func loadStore() -> Store {
        if let data = try? Data(contentsOf: storeURL),
           let store = try? decoder.decode(Store.self, from: data) {
            return store
        }
        if let data = try? Data(contentsOf: fileURL),
           let legacy = try? decoder.decode(Pool.self, from: data) {
            return Store(pools: [legacy.key: legacy])
        }
        return Store(pools: [:])
    }

    private func load(key: String) -> Pool? {
        guard let pool = loadStore().pools[key], pool.key == key else { return nil }
        return pool
    }

    private func save(_ pool: Pool) {
        var store = loadStore()
        store.pools[pool.key] = pool
        if store.pools.count > Self.maxPools {
            let keep = store.pools.values
                .sorted { $0.generatedAt > $1.generatedAt }
                .prefix(Self.maxPools)
            store.pools = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0) })
        }
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
