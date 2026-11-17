import Foundation

/// The bundled lines a call opens on: the first-call introduction
/// (`introOpener`), a "my own topic" call's line and tutor mode's. A
/// no-topic free talk has no bundled hello since 2026-11-12 (founder): the
/// fluent self says hello itself (`sayHelloNote`), from what its prompt
/// knows, including what came earlier today (`EarlierToday`).
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

    /// The line a "my own topic" call opens on (topics page, draft
    /// 2026-10-18): not a hello for the time of day — the learner came with
    /// something to talk about, so the first thing said hands them the topic.
    /// Bundled like the hellos, so it never waits on Gemini.
    static func topicOpener(language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return topicOpeners[code] ?? topicOpeners["en"]!
    }

    private static let topicOpeners: [String: String] = [
        "en": "Okay, what do you want to talk about today?",
        "de": "Okay, worüber wollen wir heute reden?",
        "ko": "좋아, 오늘은 어떤 주제로 얘기해 볼까?",
        "ja": "よし、今日は何について話そうか？",
        "es": "Bueno, ¿de qué quieres hablar hoy?",
        "fr": "Bon, de quoi tu veux parler aujourd'hui ?",
        "it": "Allora, di cosa vuoi parlare oggi?",
        "pt": "Então, sobre o que você quer conversar hoje?",
        "zh": "好，今天想聊什么？",
    ]

    /// Tutor mode's first line with no lesson to pick up (`TutorLesson`):
    /// the call exists to practice ONE thing, so it opens by asking which,
    /// and says the topic button is there for someone with no idea.
    static func tutorOpener(language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return tutorOpeners[code] ?? tutorOpeners["en"]!
    }

    private static let tutorOpeners: [String: String] = [
        "en": "Okay, lesson time. What do you want to be able to say today? Tell me, or pick a topic from the button.",
        "de": "Okay, Zeit für eine Übung. Was willst du heute sagen können? Sag es mir, oder such dir unten ein Thema aus.",
        "ko": "좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어? 말해 줘도 되고, 버튼에서 주제를 골라도 돼.",
        "ja": "よし、今日はレッスンだよ。今日は何が言えるようになりたい？教えてくれてもいいし、ボタンからテーマを選んでもいいよ。",
        "es": "Bueno, hora de practicar. ¿Qué quieres poder decir hoy? Dímelo, o elige un tema con el botón.",
        "fr": "Bon, on s'entraîne. Qu'est-ce que tu veux savoir dire aujourd'hui ? Dis-le-moi, ou choisis un sujet avec le bouton.",
        "it": "Allora, si fa lezione. Cosa vuoi saper dire oggi? Dimmelo, o scegli un argomento dal pulsante.",
        "pt": "Então, hora da aula. O que você quer conseguir dizer hoje? Me conta, ou escolhe um tema no botão.",
        "zh": "好，今天上课。你今天想学会说什么？告诉我，或者从按钮里选一个话题。",
    ]

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
            // Whole: a Cartesia line already pauses between its sentences.
            // Billed as "opener", not "turn" (2026-10-02): the edge prices
            // the two identically (`TALK_PURPOSES`), but a warm-up filed as
            // "turn" was indistinguishable in the ledger from a call's reply,
            // and the admin console read a language switch as a 6-minute call.
            // A FRESH key per warm (2026-11-16): the default key is derived
            // from the line, so a re-bake (speed moved, baked list reset)
            // re-sent a key already on file, and `tts` refuses a key older
            // than ten minutes with 409. The line's audio had been removed
            // above, so it was never cached again and every warm failed.
            audio = try await VoiceClient.shared.synthesize(
                voiceId: voiceId, text: line,
                idempotencyKey: "tts-opener:\(UUID().uuidString)", purpose: "opener")
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
        if VoiceClient.isCartesiaVoice(voiceId), !defaults.bool(forKey: Self.cartesiaWholeKey) {
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

    /// Warm the one bundled free-talk line still spoken: the first call's
    /// introduction. Cache-checked, so repeat calls cost nothing. Called from
    /// the Talk launcher and from every point that mints a new voice id
    /// (clone, re-record, accent remix).
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
        // Every later free talk opens on a hello the fluent self says itself
        // (2026-11-12, founder): nothing to write or voice ahead.
    }
}

// MARK: - The second call of the day (2026-11-04)

/// What the learner last did with the fluent self EARLIER TODAY — a talk, a
/// tutor lesson, a scene, or a pronunciation drill — as a record for prompts.
///
/// Founder, 2026-11-04: "I call again the same morning and it says 'did you
/// sleep well?' again. A second call of the day should have more context."
/// The hello for the time of day (`pickUpLines`) only ever looked at the
/// hour, so every morning call was the first call of the morning. A friend
/// rung twice in a day picks up where you were: "또 왔네. 아까 말한 회의는
/// 잘 끝났어?" — and that includes what you PRACTISED together ("아까
/// 연습한 think, 이제 좀 편해졌어?"), since a lesson or a drill is time
/// spent with them too (founder, same day).
///
/// A talk WITH someone (a cast person, a stranger: `counterpartId`) is not
/// the fluent self's to pick up and is skipped. A pronunciation drill saves
/// no `Session` ("no summary and no book") — its takes are in
/// `PronunciationLedger` under `pron_call`, and that is what is read here.
///
/// The record is ENGLISH framing around the learner's own words, quoted as
/// said: it is context for a prompt, never material.
struct EarlierToday: Equatable {
    enum Kind: String { case talk, lesson, scene, pronunciation }

    var kind: Kind
    /// What is being picked up: the session's id, or `pron:<last take's id>`.
    var key: String
    /// When it ended (its last line, or its last take).
    var endedAt: Date
    var record: String

    /// The surface `PronunciationLedger` files a pronunciation call's takes
    /// under.
    static let pronSurface = "pron_call"
    /// Takes this close to the last one belong to the same drill.
    static let drillSpan: TimeInterval = 45 * 60

    /// Read from the stores. Main actor: the ledger's cache is unlocked.
    @MainActor
    static func current(language: String, excluding currentSessionId: UUID? = nil,
                        now: Date = Date()) -> EarlierToday? {
        latest(now: now,
               sessions: SessionStore.shared.loadAcrossLanguages(),
               pronEntries: PronunciationLedger.shared.entries(),
               excluding: currentSessionId)
    }

    static func latest(now: Date, sessions: [Session], pronEntries: [PronunciationEntry],
                       excluding currentSessionId: UUID? = nil,
                       calendar: Calendar = .current) -> EarlierToday? {
        let startOfToday = calendar.startOfDay(for: now)
        // The same rule as `PromptClock.make`: a talk counts only if the
        // learner spoke in it, dated by its last line.
        let talk = sessions.compactMap { s -> (Session, Date)? in
            guard s.id != currentSessionId, s.counterpartId == nil,
                  s.turns.contains(where: { $0.role == .user }) else { return nil }
            let at = s.turns.map(\.timestamp).max() ?? s.endedAt ?? s.startedAt
            return (at >= startOfToday && at <= now) ? (s, at) : nil
        }.max { $0.1 < $1.1 }

        let takes = pronEntries.filter {
            $0.surface == pronSurface && $0.date >= startOfToday && $0.date <= now
        }
        let lastTake = takes.max { $0.date < $1.date }

        if let lastTake, talk.map({ lastTake.date > $0.1 }) ?? true {
            let drill = takes.filter { $0.date >= lastTake.date.addingTimeInterval(-drillSpan) }
            return EarlierToday(kind: .pronunciation, key: "pron:\(lastTake.id.uuidString)",
                                endedAt: lastTake.date,
                                record: pronRecord(drill, endedAt: lastTake.date, now: now, calendar: calendar))
        }
        guard let talk else { return nil }
        return fromSession(talk.0, endedAt: talk.1, now: now, calendar: calendar)
    }

    private static func fromSession(_ s: Session, endedAt: Date, now: Date,
                                    calendar: Calendar) -> EarlierToday {
        let gap = PromptClock.gap(from: endedAt, to: now, calendar: calendar)
        let kind: Kind
        var head: String
        if let lesson = s.tutorLesson {
            kind = .lesson
            let progress = lesson.finished
                ? "they finished it"
                : "\(lesson.done.count) of \(lesson.total) challenges cleared, not finished yet"
            head = "A tutor-mode lesson with you on \"\(lesson.title)\" that ended \(gap) — \(progress)."
            let got = lesson.done.prefix(3).map { "\"\(clip($0.line, 160))\"" }
            if !got.isEmpty { head += "\nLines they got right: " + got.joined(separator: " · ") }
        } else if s.turns.contains(where: { $0.tutorRole != nil }) {
            kind = .lesson
            head = "A tutor-mode lesson with you that ended \(gap)."
        } else if s.origin == .scenario {
            kind = .scene
            head = "A role-play scene, \"\(s.displayTitle)\", that ended \(gap). You played a character in it, not yourself."
        } else {
            kind = .talk
            let about = s.topic.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : " about \"\($0)\"" } ?? ""
            head = "A talk\(about) that ended \(gap)."
        }
        // A talk carries as much as a person's call history does
        // (`PersonHistory`, 30 lines / 3,000 chars). It was the last 10 lines
        // until 2026-11-17: a learner said "on my way home" earlier in a talk,
        // the next call said it had "no clear record" of it, and opened
        // instead on a street voice the mic had caught in the last lines.
        let lines = kind == .talk ? lastLines(s.turns, count: 30, budget: 3000)
                                  : lastLines(s.turns, count: 6)
        let record = lines.isEmpty ? head : head + "\nIts last lines, oldest first:\n" + lines
        return EarlierToday(kind: kind, key: s.id.uuidString, endedAt: endedAt, record: record)
    }

    /// The tail of a talk, newest kept when the budget runs out.
    private static func lastLines(_ turns: [Turn], count: Int, budget: Int = 1400) -> String {
        var out: [String] = []
        var used = 0
        // A line the learner flagged as misheard was never theirs (a street
        // voice, a mishearing), and the reply right after it was built on it:
        // both stay out, or the next call opens on them.
        var dropped = Set<UUID>()
        for (i, t) in turns.enumerated() where t.role == .user && t.excludedFromScoring {
            dropped.insert(t.id)
            if i + 1 < turns.count, turns[i + 1].role != .user { dropped.insert(turns[i + 1].id) }
        }
        for t in turns.reversed() where !dropped.contains(t.id) {
            let text = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let line = "\(t.role == .user ? "them" : "you"): \"\(clip(text, 200))\""
            guard used + line.count <= budget, out.count < count else { break }
            out.append(line)
            used += line.count
        }
        return out.reversed().joined(separator: "\n")
    }

    private static func pronRecord(_ drill: [PronunciationEntry], endedAt: Date, now: Date,
                                   calendar: Calendar) -> String {
        let gap = PromptClock.gap(from: endedAt, to: now, calendar: calendar)
        // Lowest first; a word below 70 is one Azure did not hear clearly.
        var scores: [String: [Int]] = [:]
        for e in drill { for w in e.words where w.a < 70 { scores[w.w.lowercased(), default: []].append(w.a) } }
        let hard = scores.map { ($0.key, $0.value.reduce(0, +) / $0.value.count) }
            .sorted { $0.1 < $1.1 }.prefix(3).map { "\"\($0.0)\"" }
        let n = drill.count
        var record = "A pronunciation drill with you that ended \(gap) (a reading drill, not counted as a talk): " +
            "they read \(n == 1 ? "1 sentence" : "\(n) sentences") aloud and you told them which words weren't clear yet."
        record += hard.isEmpty
            ? " Every word came out clear."
            : " The words that still weren't clear: \(hard.joined(separator: ", "))."
        return record
    }

    private static func clip(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}

extension FreeTalkOpeners {
    /// The note a no-topic free talk opens on: the fluent self says hello
    /// itself, from everything its prompt already knows. Until 2026-11-12 it
    /// opened on a bundled hello for the time of day, or a line written ahead
    /// about what came earlier, and fell back to the same "Hi again! What
    /// have you been up to since?" whenever that line wasn't ready.
    static let sayHelloNote = "They just called you. Say hello."
}
