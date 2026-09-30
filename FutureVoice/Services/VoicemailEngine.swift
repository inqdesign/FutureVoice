import Foundation

/// Writes and voices the daily call's opening line — the fluent self leaving a
/// voicemail before the learner picks up.
///
/// Two calls, both at the END of the previous session rather than in the
/// morning: iOS background execution can't be relied on to run at a chosen
/// hour, and by generation time the app is already foreground with the freshest
/// possible context in hand. The notification then only has to play a file that
/// is already on disk, which works offline and can't fail at 8am.
///
/// The script is MATERIAL (the learner hears it and answers it out loud), so it
/// is written in the TARGET language — see `CoachingLanguage`. Nothing about
/// this call is coaching: it never explains, judges, or frames. It says one
/// concrete thing about yesterday and asks one question.
enum VoicemailEngine {

    /// What the model returns.
    private struct Payload: Decodable {
        let script: String
    }

    /// Everything the script can be grounded in. Assembled by the caller from
    /// state it already has — the engine does no store lookups of its own, so
    /// it stays testable and can't accidentally read the wrong language's data.
    struct Context {
        var targetLanguage: String
        var nativeLanguage: String
        var proficiency: CEFRLevel
        /// The learner's own name, when the persona has one. At most one
        /// mention — a voicemail that says your name twice sounds automated.
        var personaName: String?
        /// What the last talk was about ("ordering at a cafe", "weekend
        /// plans"). Empty for a free talk with no title.
        var lastTopic: String?
        /// A couple of phrases the fluent self actually handed over last time.
        /// Naming one is what makes the call sound like a continuation instead
        /// of a generated greeting.
        var lastPhrases: [String]
        /// When the last talk ended. Drives tone: picking up a thread vs.
        /// coming back after a gap. A DATE, not a day count, because the
        /// script is written at the end of a talk and heard at the next ring
        /// — often the next morning — and the gap has to be measured to the
        /// ring. Counted as "0 days" at writing time, last night's talk was
        /// announced as "you already practiced today" at 8 a.m.
        var lastTalkAt: Date?
        /// How many SRS cards are waiting. Mentioned only as a reason to talk,
        /// never as a number to feel bad about.
        var dueCount: Int

        // MARK: The caller's memory
        //
        // This is what separates a call from an alarm. An alarm announces a
        // time and knows nothing; a person remembers that you couldn't talk
        // yesterday, or that they haven't reached you all week, and opens on
        // that. Filled in by `DailyCallScheduler.refresh` from the call log.

        /// How the previous call ended, nil before there was one.
        var lastOutcome: DailyCallOutcome?
        /// How many times they had to ring back on that previous call.
        var lastCallbacks: Int = 0
        /// Calls in a row that went unanswered. The caller's sense of "I
        /// haven't got hold of you in a while".
        var consecutiveUnanswered: Int = 0

        /// Every time this script will ring, ascending — all on one day
        /// (`DailyCallScheduler.fireDates`). Filled in by the scheduler; empty
        /// means "now", which only a test or a preview ever wants.
        var ringDates: [Date] = []
    }

    /// One Gemini call. Cheap tier: this is six seconds of warm small talk, not
    /// coaching text — the quality that matters here is brevity and that it
    /// ends in a real question.
    static func writeScript(_ context: Context) async throws -> String {
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: systemPrompt(context),
            messages: [GeminiClient.Message(role: .user, content: "Leave the voicemail.")],
            model: .flashLite31,
            maxTokens: 400,
            purpose: "daily-call-script"
        )
        return sanitize(payload.script)
    }

    /// Trim to something a voice can say inside the OS sound limit, and strip
    /// anything a voice can't say at all. A stage direction that reaches TTS
    /// gets read out loud, which breaks the illusion in the first second.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\\*[^*]*\\*", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > maxScriptCharacters else { return s }
        // Over budget: keep whole sentences, never a clipped one — and keep
        // the LAST one, because that's where the question is.
        let clipped = String(s.prefix(maxScriptCharacters))
        if let cut = clipped.lastIndex(where: { ".!?？！。".contains($0) }) {
            return String(clipped[...cut])
        }
        return clipped
    }

    /// The day and the time(s) the script rings, in words the prompt can use.
    /// One ring names its part of the day; several (the learner's later
    /// times, armed with the same message) are listed, and the prompt then
    /// forbids a time-of-day greeting — "good morning" at 13:00 is the
    /// complaint this exists to prevent.
    static func whenHeard(_ ringDates: [Date], calendar: Calendar = .current) -> String {
        let dates = ringDates.isEmpty ? [Date()] : ringDates.sorted()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        let day = PromptClock.dayLine(dates[0], calendar: calendar)
        if dates.count == 1 {
            let part = PromptClock.partOfDay(hour: calendar.component(.hour, from: dates[0]))
            return "It rings on \(day), at \(f.string(from: dates[0])) — \(part)."
        }
        let times = dates.map { f.string(from: $0) }.joined(separator: ", ")
        return "It rings on \(day), at \(times) — the same message each time until they pick up, so you cannot know which part of the day they hear it in."
    }

    /// ~25 s of speech at a natural pace, at speed 1.0. Nobody listens to a
    /// longer voicemail, and the learner is meant to answer a question, not
    /// sit through a monologue. Enforced twice: here in characters, and again
    /// on the PCM in `synthesizeVoicemail`.
    static let baseScriptCharacters = 260

    /// The budget the script is written to and trimmed to. The learner's
    /// speech speed (Me → Voice, `SpeechSpeed`) stretches the audio — Normal
    /// 0.9 is +13%, Slower 0.8 is +27% — while the OS's 30 s ceiling and the
    /// hard cut below do not move, so 260 characters at Slower would be cut
    /// mid-sentence and lose the question at the END, which is the whole
    /// pull. Fewer characters, same seconds. Read at generation time; the
    /// prompt and the trim see the same number within one call.
    static var maxScriptCharacters: Int {
        Int(Double(baseScriptCharacters) * SpeechSpeed.current.multiplier)
    }

    /// Hard cut for the spoken audio, in case a model overruns the character
    /// budget anyway.
    static let maxVoicemailSeconds: Double = 29

    static func systemPrompt(_ c: Context, calendar: Calendar = .current) -> String {
        let targetName = LanguageCatalog.englishName(c.targetLanguage)
        let name = (c.personaName?.isEmpty == false) ? c.personaName! : "the learner"

        var grounding: [String] = []
        if let topic = c.lastTopic, !topic.isEmpty {
            grounding.append("Their last talk was about: \(topic)")
        }
        if !c.lastPhrases.isEmpty {
            grounding.append("Phrases that came up in it: "
                             + c.lastPhrases.prefix(4).map { "\"\($0)\"" }.joined(separator: ", "))
        }
        let ringDay = c.ringDates.min() ?? Date()
        if let last = c.lastTalkAt {
            let days = PromptClock.calendarDays(from: last, to: ringDay, calendar: calendar)
            grounding.append(days == 0 ? "They already had a talk earlier today."
                             : days == 1 ? "Their last talk was yesterday."
                             : "It has been \(days) days since their last talk.")
        }
        if c.dueCount > 0 {
            grounding.append("\(c.dueCount) review cards are waiting.")
        }
        // What YOU did last time you called them. Stated as the caller's own
        // recollection, not as app telemetry.
        switch c.lastOutcome {
        case .answered:
            grounding.append("Last time you called, they picked up and you talked.")
        case .declined:
            grounding.append("Last time you called, they said they couldn't talk right then.")
        case .missed:
            grounding.append("Last time you called, they never picked up.")
        case nil:
            break
        }
        if c.consecutiveUnanswered >= 2 {
            grounding.append("You haven't actually got hold of them in \(c.consecutiveUnanswered) calls.")
        }
        let groundingBlock = grounding.isEmpty
            ? "You have no history with them yet — this is the first call."
            : grounding.map { "- \($0)" }.joined(separator: "\n")

        return """
        You are the learner's own FLUENT FUTURE SELF, leaving them a short
        voicemail to start a practice call. Same person, same voice — you are
        not a tutor, a coach, or an assistant, and you never sound like one.

        WHAT YOU KNOW ABOUT THEM
        \(groundingBlock)

        WHEN THEY HEAR IT
        \(whenHeard(c.ringDates, calendar: calendar))

        YOU ARE CALLING THEM, and that is not a figure of speech. You remember
        how the last call went and you open like someone who does. If they
        couldn't talk last time, acknowledge it lightly and move on. If you
        haven't reached them in days, say so the way a friend would — mild,
        curious, never wounded and never scolding. Guilt is the one thing that
        makes people stop picking up.

        WRITE ONE VOICEMAIL in \(targetName):
        - 2–3 sentences, UNDER \(maxScriptCharacters) characters total. It is
          spoken aloud in under 25 seconds — that ceiling is hard.
        - Sentence 1 picks up something CONCRETE from the grounding above —
          the last call's outcome first if there was one, otherwise the last
          talk. If there is nothing to pick up, say something specific about
          today instead — never a generic "ready to practice?" opener.
        - The LAST sentence is a QUESTION they can answer out loud immediately,
          about their own life. This is the whole point of the call: they
          should feel a question waiting, not an invitation.
        - Natural spoken \(targetName) a CEFR \(c.proficiency.rawValue.uppercased())
          learner follows at speed. Contractions, no literary phrasing.
        - \(CoachingLanguage.breathPunctuation)
        - In a language that separates formal from informal address (Korean
          반말, Japanese plain form, German du, French tu, Spanish tú…), use the
          INFORMAL form — it is you talking to yourself.
        - Warm and casual, the way you'd talk to yourself. Never congratulate
          them, never mention streaks, goals, minutes, or the app.
        - Address \(name) by name at most ONCE, and only if it sounds natural.
        - No numbers read as statistics. If review cards are waiting, that is a
          reason to bring up a phrase, not a count to recite.

        TIME: write for the moment it is HEARD, never the moment it is
        written. "Today" is the day above; "yesterday" is the day before it.
        Name a time of day only when WHEN THEY HEAR IT gives exactly one, and
        never guess a date, a count of calls, or a gap that isn't written
        above.

        OUTPUT LANGUAGE: the script is MATERIAL — every word is in
        \(targetName). Nothing in \(LanguageCatalog.englishName(c.nativeLanguage))
        and nothing in English unless \(targetName) IS English.

        Speakable as-is: no stage directions, no asterisks, no brackets, no
        placeholders, no "[name]".

        Return STRICT JSON only — no prose, no code fences:
        { "script": "..." }
        """
    }

    // MARK: - Ringtone

    /// Synthesize `script` in the learner's clone and return it as playable
    /// WAV. This is the VOICEMAIL — what the caller says once the learner picks
    /// up — not the ring. The ring is a bundled phone tone
    /// (`DailyCallStore.ringtoneFilename`); a runtime-written file cannot be a
    /// notification or alarm sound on iOS 26.
    ///
    /// Uses the STREAMING endpoint purely for its output format: it returns
    /// raw 16-bit LE PCM, and Linear PCM in a WAV container is one of the few
    /// things `UNNotificationSound` will play. The MP3 that `synthesize`
    /// returns is not — decoding it on-device would be a second dependency for
    /// no gain. Returns nil on any failure; the caller then rings on the
    /// default sound rather than not ringing at all.
    ///
    /// Model: turbo, like every other repeating surface (2026-09-26). It ran
    /// `fidelityModelId` on the argument that a voicemail is where "that's my
    /// voice" lands, and that it fires at most once a day — but the founder
    /// compared the two models on their own clone that day and turbo held up
    /// (`scripts/tts-model-probe.sh`), so there is nothing left to buy. The
    /// "once a day" was also not true: the script is re-synthesized at every
    /// SESSION end (`refreshDailyCall(force: true)`), so three talks in a day
    /// meant three voicemails and one ring. Measured over the launch window
    /// this path was 8.6% of all ElevenLabs credits excluding the founder's
    /// own account, and half of that was the 2x.
    @MainActor
    static func synthesizeVoicemail(script: String, voiceId: String) async -> Data? {
        do {
            // Sentence by sentence, so the voicemail breathes between them
            // (see `PacedSpeech`); a one-sentence script takes the single call.
            if let paced = try await PacedSpeech.synthesizePCM(
                voiceId: voiceId, text: script,
                modelId: ElevenLabsClient.cloneModelId, purpose: "daily-call") {
                let trimmed = trim(pcm: paced.pcm, sampleRate: paced.sampleRate,
                                   to: maxVoicemailSeconds)
                return AudioLoudness.wavData(fromPCM16: leveled(trimmed),
                                             sampleRate: Int(paced.sampleRate))
            }
            let audio = try await ElevenLabsClient.shared.synthesizeStreaming(
                voiceId: voiceId,
                text: script,
                modelId: ElevenLabsClient.cloneModelId,
                purpose: "daily-call",
                onPCMChunk: { _, _ in }   // nothing to play — we only want the bytes
            )
            guard case .pcm(let pcm, let sampleRate) = audio else {
                // Older edge deploy with no streaming support handed back MP3,
                // which the OS won't ring. Not worth a decoder: the call still
                // goes out on the default sound.
                return nil
            }
            let trimmed = trim(pcm: pcm, sampleRate: sampleRate,
                               to: maxVoicemailSeconds)
            return AudioLoudness.wavData(fromPCM16: leveled(trimmed),
                                         sampleRate: Int(sampleRate))
        } catch {
            return nil
        }
    }

    /// Hard-cut the PCM at the OS ceiling. The character budget should have
    /// prevented this; a model that overruns anyway must not silence the call.
    static func trim(pcm: Data, sampleRate: Double, to seconds: Double) -> Data {
        let maxBytes = Int(sampleRate * seconds) * 2   // 16-bit mono
        guard pcm.count > maxBytes, maxBytes > 0 else { return pcm }
        return pcm.prefix(maxBytes)
    }

    /// Bring the ringtone to the app's one playback level.
    ///
    /// IVC clones come back markedly quieter than preset voices (see
    /// `AudioLoudness`), and a ringtone that plays under the room is a missed
    /// call. Runs the same `gain(forSpeechRMS:)` rule every other playback path
    /// uses — measured over samples above the same relative gate — so the call
    /// lands at the level the learner already hears the app at, then soft-clips
    /// so a boosted transient can't wrap around.
    static func leveled(_ pcm: Data) -> Data {
        let count = pcm.count / 2
        guard count > 0 else { return pcm }

        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { pcm.copyBytes(to: $0, count: count * 2) }

        var peak: Float = 0
        for s in samples { peak = max(peak, abs(Float(s) / 32767)) }
        guard peak > 0 else { return pcm }

        // Speech level, gated relative to this signal's own peak — room tone
        // and the gaps between sentences must not drag the measurement down.
        let gate = peak * AudioLoudness.speechGateRatio
        var sumSquares: Double = 0
        var voiced = 0
        for s in samples {
            let v = abs(Float(s) / 32767)
            guard v >= gate else { continue }
            sumSquares += Double(v) * Double(v)
            voiced += 1
        }
        guard voiced > 0 else { return pcm }

        let rms = Float((sumSquares / Double(voiced)).squareRoot())
        let gain = AudioLoudness.gain(forSpeechRMS: rms)
        guard abs(gain - 1) > 0.01 else { return pcm }

        for i in samples.indices {
            let boosted = (Float(samples[i]) / 32767) * gain
            samples[i] = Int16(max(-1, min(1, boosted)) * 32767)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
