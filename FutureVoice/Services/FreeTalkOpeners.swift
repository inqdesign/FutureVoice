import Foundation

/// How a no-topic free talk picks up: one light hello per language and part
/// of the day (`pickUpLines`), chosen at the moment of the call, plus the
/// first-call introduction (`introOpener`). The texts repeat verbatim, so
/// `PhraseAudioStore`'s content cache makes every TTS after a line's first
/// play free. Until 2026-10-13 a Gemini call wrote a rotating pool of six per
/// learner (`Documents/freetalk_openers_by_language.json`, no longer read).
///
/// Topic/scenario/news openers stay dynamic — this is only the no-topic talk.
final class FreeTalkOpeners {
    static let shared = FreeTalkOpeners()

    /// Lines being synthesized right now, so two warm-ups landing at once
    /// (a new voice id arrives while the Talk tab's own warm-up is running)
    /// make each take ONCE. Measured 2026-10-02: the same seven lines billed
    /// twice in one second on a fresh clone.
    private var inFlight: Set<String> = []
    private let inFlightLock = NSLock()

    /// How many lines ahead of the rotation are kept warm. Until 2026-10-02
    /// every line of the pool was synthesized up front — six takes for a
    /// learner who may call once, and the whole set again on every speed
    /// change, pool rewrite or new voice. Only the NEXT line can open the next
    /// call; one spare covers a second call before the launcher re-warms
    /// (it does after every call). A miss is still a working call: the
    /// gateway speaks the line itself, one round trip slower.
    ///
    /// One since 2026-10-09: the spare was for a second call before the
    /// re-warm, but the launcher re-warms the moment a call closes and on
    /// every foreground, so the spare was made and almost never the one
    /// played. Measured over 7 days: 183 opener takes for 148 calls (25
    /// learners), 42 of them for 8 learners who never called at all.
    static let warmAhead = 1

    /// The line a free talk placed now opens on. MATERIAL → target language,
    /// name-free, so one cache entry serves every persona.
    static func pickUpOpener(language: String) -> String {
        pickUpLine(language: language, at: Date())
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

    /// How a free talk picks up — one light hello for the time of day,
    /// written by hand per language (2026-10-13, founder). Until then one
    /// flash-lite call wrote six lines per learner, and every one put a
    /// guessed subject to them ("how's your project going?", "what's been
    /// worrying you?", "got a minute?") when it was THEY who placed the call
    /// and came with something to say. Prompted to only hand them the floor,
    /// it still answered in Korean with 무슨 일이야 / 왜 전화했어 (an
    /// emergency, or being bothered), turned a Hangul name into kanji in
    /// Japanese, and assumed the hour. The founder then weighed a list of
    /// door-opening lines, "여보세요", and the learner going first, and picked
    /// a friend's hello that knows what time it is: "안녕, 잘 잤어?" in the
    /// morning, "안녕, 지금 뭐해?" by day, "안녕, 오늘은 어땠어?" in the
    /// evening, "안녕, 아직 안 자?" at night. It says the line is live, is
    /// heard in their own voice, and steers nothing; whatever they say next IS
    /// the call, and a greeting answered back or "nothing much" is the
    /// conversation prompt's THEY CALLED YOU block's to answer.
    ///
    /// The part of the day is `PromptClock.partOfDay`, the same split the
    /// call's own prompt is told, so the hello and the model agree on the
    /// hour. MATERIAL → target language, informal address throughout, no
    /// leading interjection (founder: "앞에 감탄사들 다 빼").
    private static let pickUpLines: [String: [String: String]] = [
        "en": [
            "morning": "Hi, did you sleep well?",
            "afternoon": "Hi, what are you up to?",
            "evening": "Hi, how was your day?",
            "night": "Hi, still up?",
        ],
        "de": [
            "morning": "Hi, gut geschlafen?",
            "afternoon": "Hi, was machst du gerade?",
            "evening": "Hi, wie war dein Tag?",
            "night": "Hi, noch wach?",
        ],
        "ko": [
            "morning": "안녕, 잘 잤어?",
            "afternoon": "안녕, 지금 뭐해?",
            "evening": "안녕, 오늘은 어땠어?",
            "night": "안녕, 아직 안 자?",
        ],
        "ja": [
            "morning": "おはよう、よく眠れた？",
            "afternoon": "やあ、今なにしてる？",
            "evening": "やあ、今日はどうだった？",
            "night": "やあ、まだ起きてるの？",
        ],
        "es": [
            "morning": "¡Hola! ¿Dormiste bien?",
            "afternoon": "¡Hola! ¿Qué haces?",
            "evening": "¡Hola! ¿Qué tal tu día?",
            "night": "¡Hola! ¿Aún no te has dormido?",
        ],
        "fr": [
            "morning": "Salut, bien dormi\u{00A0}?",
            "afternoon": "Salut, tu fais quoi\u{00A0}?",
            "evening": "Salut, c’était comment ta journée\u{00A0}?",
            "night": "Salut, tu ne dors pas encore\u{00A0}?",
        ],
        "it": [
            "morning": "Ciao, dormito bene?",
            "afternoon": "Ciao, che fai?",
            "evening": "Ciao, com'è andata oggi?",
            "night": "Ciao, non dormi ancora?",
        ],
        "pt": [
            "morning": "Oi, dormiu bem?",
            "afternoon": "Oi, o que você tá fazendo?",
            "evening": "Oi, como foi o seu dia?",
            "night": "Oi, ainda não foi dormir?",
        ],
        "zh": [
            "morning": "早啊，睡得好吗？",
            "afternoon": "嗨，在干嘛呢？",
            "evening": "嗨，今天过得怎么样？",
            "night": "嗨，还没睡呀？",
        ],
    ]

    static func pickUpLine(language: String, at date: Date) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        let lines = pickUpLines[code] ?? pickUpLines["en"]!
        let hour = Calendar.current.component(.hour, from: date)
        return lines[PromptClock.partOfDay(hour: hour)] ?? lines["afternoon"]!
    }

    /// The line a call placed now opens on, then — when asked for more — the
    /// next parts of the day's, so a warm-up just before a boundary still
    /// has the following hello ready.
    func upcomingLines(language: String, personaName: String?, count: Int) -> [String] {
        var out: [String] = []
        var date = Date()
        for _ in 0..<max(0, count) {
            let line = Self.pickUpLine(language: language, at: date)
            if !out.contains(line) { out.append(line) }
            date = date.addingTimeInterval(5 * 3600)
        }
        return out
    }

    /// Synthesize the next `warmAhead` lines' audio that isn't cached yet, so
    /// the next call opens on cached audio — no ElevenLabs round trip on the
    /// greeting. Called again after every call, so the window walks with the
    /// rotation. A failure aborts the sweep (the rest would fail the same
    /// way); the live call still falls back to on-demand TTS.
    func warmAudio(language: String, personaName: String?, voiceId: String?) async {
        guard let voiceId else { return }
        do {
            for line in upcomingLines(language: language, personaName: personaName,
                                      count: Self.warmAhead) {
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
        let flight = "\(voiceId)|\(line)"
        let claimed: Bool = inFlightLock.withLock { inFlight.insert(flight).inserted }
        guard claimed else { return }
        defer { _ = inFlightLock.withLock { inFlight.remove(flight) } }
        let stale = needsBake(line, voiceId: voiceId)
        if stale { PhraseAudioStore.shared.removeAudio(text: line, voiceId: voiceId) }
        guard stale || PhraseAudioStore.shared.data(text: line, voiceId: voiceId,
                                                    allowLineage: false) == nil else { return }
        let audio: Data
        do {
            // A line of several sentences is made sentence by sentence so it
            // breathes like the answers after it (see `PacedSpeech`); a
            // one-sentence line, or an edge with no streaming, takes the
            // ordinary single synthesis.
            //
            // Billed as "opener", not "turn" (2026-10-02): the edge prices
            // the two identically (`TALK_PURPOSES`), but a warm-up filed as
            // "turn" was indistinguishable in the ledger from a call's reply,
            // and the admin console read a language switch as a 6-minute call.
            if let paced = try await PacedSpeech.synthesizePCM(
                voiceId: voiceId, text: line,
                modelId: ElevenLabsClient.conversationModelId, purpose: "opener") {
                audio = AudioLoudness.wavData(fromPCM16: paced.pcm,
                                              sampleRate: Int(paced.sampleRate))
            } else {
                audio = try await ElevenLabsClient.shared.synthesize(
                    voiceId: voiceId, text: line,
                    modelId: ElevenLabsClient.conversationModelId,
                    purpose: "opener")
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
    /// Set once a Cartesia voice's openers have been re-made WHOLE
    /// (2026-10-13): the ones made before were split sentence by sentence
    /// (`PacedSpeech`), which a Cartesia line must not be.
    private static let cartesiaWholeKey = "futurevoice.freeTalkOpeners.cartesiaWhole"

    private func needsBake(_ line: String, voiceId: String) -> Bool {
        let defaults = UserDefaults.standard
        if VoiceMove.isCartesia(voiceId), !defaults.bool(forKey: Self.cartesiaWholeKey) {
            defaults.set(true, forKey: Self.cartesiaWholeKey)
            defaults.removeObject(forKey: Self.bakedLinesKey)
            return true
        }
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
    /// pool text, then warm the next `warmAhead` pool lines. Everything is cache-checked, so
    /// repeat calls cost nothing. Called from the Talk launcher and from
    /// every point that mints a new voice id (clone, re-record, accent remix)
    /// — a new id invalidates all warmed audio at once.
    func warmFirstCall(language: String, personaName: String?,
                       proficiency: CEFRLevel, voiceId: String?,
                       firstMeeting: Bool = false) async {
        // The introduction line is what an unmet learner's call actually
        // opens on — warming the hello instead would leave the one greeting
        // they're going to hear as the only slow one.
        if let voiceId, firstMeeting {
            try? await warmLine(Self.introOpener(language: language), voiceId: voiceId)
        }
        // An unmet learner's first free talk opens on the introduction, never
        // on a pool line, so pool AUDIO made now could only open a second
        // call — and is made again whenever the voice id moves before then
        // (the onboarding accent remix is one). It waits for the first call's
        // own re-warm (`RootTabView`, after the call closes). Reported
        // 2026-10-09: two pool lines in a new learner's voice history before
        // they had said a word.
        guard !firstMeeting else { return }
        await warmAudio(language: language, personaName: personaName, voiceId: voiceId)
    }
}
