import Foundation

/// The fluent self's spoken goodbye after the learner hangs up (2026-11-12,
/// founder). A call used to end on a progress bar: the book takes 10–30 s to
/// build, and that wait was silence. Now the fluent self says ~12 s of
/// feedback in the learner's own voice while the board fills underneath.
///
/// Three rules came out of the samples the founder listened to:
/// - **Feedback on THIS call, and nothing else.** One thing done well, one
///   tip if a slip was left unfixed, a short bye. No "next time" and never a
///   question: the call is over, there is nothing to answer.
/// - **Code decides what may be praised; the model only phrases it.** Given
///   the transcript, the model praised a line that carried a correction and
///   set a slip the learner had already fixed as homework. So it is handed
///   `praise` (clean lines, slips fixed later in the call, notebook words
///   used) and `tips` (slips never said right) and nothing to choose from
///   beyond them.
/// - **Only what exists at hang-up.** The summary is still being written,
///   so the goodbye reads the turns and their live corrections, which is
///   why it can start about two seconds after End.
///
/// Material, so it is spoken in the target language, informal, at the
/// learner's level; the native-language line under it is for the screen.
enum CallGoodbye {
    struct Facts: Equatable {
        /// Learner lines the live correction found nothing in.
        var cleanLines: [String] = []
        /// Slips corrected during the call and then said right later in it.
        var fixedSlips: [TurnFix] = []
        /// Slips never said right afterwards — the only possible tip.
        var openSlips: [TurnFix] = []
        /// Notebook items the learner used in the call (the ticked chips).
        var wordsUsed: [String] = []

        /// Something to praise. With nothing earned the goodbye is skipped:
        /// a generic "great job" is the one thing it must never say.
        var hasPraise: Bool { !cleanLines.isEmpty || !fixedSlips.isEmpty || !wordsUsed.isEmpty }
    }

    struct Line: Equatable {
        let spoken: String
        /// The same sentences in the native language, for the screen. Empty
        /// when the learner's own language is the one on the call.
        let translation: String
    }

    /// Fewer learner turns than this is not a call to give feedback on.
    static let minLearnerTurns = 3
    /// A clean line shorter than this is "yes" or "okay" — nothing to praise.
    static let minCleanWords = 5
    static let maxEach = 6

    /// What may be said, read off the turns. Lines read off coach mode's
    /// suggestion and lines marked misheard are left out: neither is the
    /// learner's own. A turn whose correction never arrived (`fixes == nil`)
    /// is neither clean nor a slip — nothing is known about it.
    static func facts(turns: [Turn], wordsUsed: [String], target: String) -> Facts? {
        let learner = turns.filter { $0.role == .user && !$0.excludedFromScoring && !$0.readFromCoach }
        guard learner.count >= minLearnerTurns else { return nil }
        let unspaced = !LanguageCatalog.writesSpaces(target)
        func key(_ s: String) -> String {
            let n = CarryoverDetector.normalized(s)
            return unspaced ? n.filter { !$0.isWhitespace } : n
        }
        var facts = Facts(wordsUsed: Array(wordsUsed.prefix(maxEach)))
        var seen = Set<String>()
        for (i, turn) in learner.enumerated() {
            guard let fixes = turn.suggestion?.fixes else { continue }
            if fixes.isEmpty {
                if WordSplitter.count(turn.transcript) >= minCleanWords {
                    facts.cleanLines.append(turn.transcript)
                }
                continue
            }
            for fix in fixes {
                let now = key(fix.now)
                guard !now.isEmpty, seen.insert(now).inserted else { continue }
                let saidRight = learner[(i + 1)...].contains { key($0.transcript).contains(now) }
                if saidRight { facts.fixedSlips.append(fix) } else { facts.openSlips.append(fix) }
            }
        }
        facts.cleanLines = Array(facts.cleanLines.suffix(maxEach))
        facts.fixedSlips = Array(facts.fixedSlips.suffix(maxEach))
        facts.openSlips = Array(facts.openSlips.suffix(maxEach))
        return facts.hasPraise ? facts : nil
    }

    private struct Payload: Decodable {
        let spoken: String?
        let translation: String?
    }

    /// Writes the goodbye, STREAMED: `onFirstSentence` gets the opening
    /// sentence the moment it is written so the voice can start on it while
    /// the rest is still coming (Haiku writes it at ~0.85 s, the whole answer
    /// at ~2 s, measured 2026-11-12). A first sentence that asks something or
    /// isn't in the target script is never handed over; the caller then
    /// speaks the finished line instead.
    static func write(facts: Facts, topic: String?, target: String, native: String,
                      level: CEFRLevel, sessionId: UUID,
                      onFirstSentence: (@MainActor (String) -> Void)? = nil) async -> Line? {
        let payload: Payload? = try? await GeminiClient.background.sendJSONStream(
            system: system(target: target, native: native, level: level),
            messages: [GeminiClient.Message(role: .user, content: content(facts: facts, topic: topic))],
            model: .flash36,
            // Room for thinking: a cut answer loses the whole goodbye.
            maxTokens: 2000,
            purpose: "goodbye",
            idempotencyKey: "goodbye:\(sessionId.uuidString)",
            requestTimeout: 15,
            earlyField: "spoken",
            onEarlyField: { text, isComplete in
                guard !isComplete, let onFirstSentence,
                      !text.contains(where: { $0 == "?" || $0 == "？" }),
                      TextScript.isInTargetScript(text, language: target) else { return }
                onFirstSentence(text)
            },
            // The stream broke after the first sentence went to the voice:
            // keep what is being heard rather than nothing.
            fallbackFromEarly: { Payload(spoken: $0, translation: nil) })
        guard var spoken = payload?.spoken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !spoken.isEmpty else { return nil }
        // A question is the one thing a goodbye may not end on — the line is
        // gone before anyone could answer. A sentence that asks one is cut.
        if spoken.contains(where: { $0 == "?" || $0 == "？" }) {
            spoken = withoutQuestions(spoken)
            guard !spoken.isEmpty else { return nil }
        }
        guard TextScript.isInTargetScript(spoken, language: target) else { return nil }
        let translation = LanguageCatalog.sameLanguage(target, native) ? ""
            : payload?.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Line(spoken: spoken, translation: translation)
    }

    /// What is left to say once `first` has been spoken: the line after it,
    /// or "" when the finished line doesn't start with it (then the first
    /// sentence stands alone rather than saying something twice).
    static func remainder(of spoken: String, after first: String) -> String {
        guard spoken.hasPrefix(first) else { return "" }
        return String(spoken.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text with every sentence that asks something removed.
    static func withoutQuestions(_ text: String) -> String {
        var kept: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?。！？".contains(ch) {
                if ch != "?" && ch != "？" { kept.append(current) }
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { kept.append(current) }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func content(facts: Facts, topic: String?) -> String {
        var c = ""
        if let topic, !topic.isEmpty { c += "The call was about: \(topic)\n\n" }
        c += "MAY BE PRAISED (pick ONE):\n"
        for line in facts.cleanLines { c += "- a line they said with no mistake: \"\(line)\"\n" }
        for fix in facts.fixedSlips {
            c += "- a slip they fixed during the call: they first said \"\(fix.was)\" and later said it right: \"\(fix.now)\"\n"
        }
        for word in facts.wordsUsed { c += "- a word from their notebook they used: \"\(word)\"\n" }
        if facts.openSlips.isEmpty {
            c += "\nTIP: none. Skip the tip.\n"
        } else {
            c += "\nTIP (pick the ONE that matters most, or none):\n"
            for fix in facts.openSlips { c += "- they said \"\(fix.was)\"; right: \"\(fix.now)\" (\(fix.why))\n" }
        }
        return c
    }

    static func system(target: String, native: String, level: CEFRLevel) -> String {
        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        return """
        You are the learner's future self: the same person a few years on, already fluent in \(targetName). \
        You just finished a phone call with them and they hung up. In about 12 seconds of speech you give them \
        feedback on THIS call, the way a caring friend would.

        One short spoken paragraph, 2 to 4 sentences, at most 45 words:
        1. ONE thing they did well, taken ONLY from the MAY BE PRAISED list. Name it concretely (quote the words). \
        Nothing else may be praised, and never a generic "great job" or "great vocabulary".
        2. ONE tip, only from the TIP list: say the right way once, kindly. If the TIP list says none, skip it.
        3. A short bye. Nothing about next time, no plans, no suggestions, and NO question mark anywhere: \
        the call is over and they cannot answer.

        Rules:
        - Spoken \(targetName) only, informal, as to a close friend (\(informal(target))). Words and sentence \
        shapes a \(level.rawValue.uppercased()) learner understands.
        - Every character is spoken aloud. No lists, no brackets, no emojis, no stage directions.
        - A period ends a sentence, a comma only where the voice keeps going.
        - No longing ("I'll miss you", "so good to hear your voice"). Warmth is attention to what they did.
        - No numbers or scores, no app feature names, no names of people, not even theirs.
        - Do not invent anything; use only the lists.

        Reply with JSON only:
        {"spoken": "...", "translation": "exactly the same sentences in casual \(nativeName), for the screen; add nothing, drop nothing; quoted \(targetName) words stay as they are"}
        """
    }

    /// How the fluent self talks to them in each language — the same rule
    /// every call follows (the future self is never formal with itself).
    private static func informal(_ target: String) -> String {
        switch target.split(separator: "-").first.map(String.init) ?? target {
        case "ko": return "반말"
        case "ja": return "plain form, タメ口"
        case "de": return "du"
        case "es": return "tú"
        case "fr": return "tu"
        default: return "casual"
        }
    }
}

/// The goodbye's voice, spoken in pieces on ONE open PCM stream: the first
/// sentence the moment it is written, the rest once the line is finished.
/// A piece joins the stream after a short silence (`gap`) — separately
/// synthesized pieces have almost none at their edges, and two sentences
/// run together read as one breathless one (the call's 0.42 s, `PacedSpeech`).
@MainActor
final class CallGoodbyeVoice {
    static let gap: Double = 0.42

    private let player: AudioPlayer
    private let voiceId: String
    private let sessionId: UUID
    /// Audio has started (streamed, or the buffered fallback).
    private(set) var started = false
    /// The open stream more pieces can join; false after a buffered fallback.
    private var streaming = false
    private var rate: Double?
    private var pieces = 0
    private var stopped = false
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}

    init(player: AudioPlayer, voiceId: String, sessionId: UUID) {
        self.player = player
        self.voiceId = voiceId
        self.sessionId = sessionId
    }

    /// Speaks `text` after whatever is already playing. True when it produced
    /// audio. Only the FIRST piece may fall back to a whole-file play; a later
    /// one that can't join the open stream is dropped rather than talking
    /// over the first.
    @discardableResult
    func speak(_ text: String) async -> Bool {
        guard !stopped, !text.isEmpty, !(started && !streaming) else { return false }
        pieces += 1
        let isFirst = !started
        var joined = false
        do {
            let result = try await VoiceClient.shared.synthesizeStreaming(
                voiceId: voiceId, text: text,
                idempotencyKey: "goodbye-tts:\(sessionId.uuidString):\(pieces)",
                purpose: "goodbye"
            ) { [self] chunk, sampleRate in
                guard !stopped else { return }
                if !started {
                    // The call is over: a playback session, like Watch.
                    guard (try? player.startPCMStream(sampleRate: sampleRate, voiceKey: voiceId,
                                                      completion: { [weak self] in self?.onFinish() })) != nil
                    else { return }
                    started = true
                    streaming = true
                    rate = sampleRate
                    joined = true
                    onStart()
                } else if !joined {
                    guard streaming, sampleRate == rate else { return }
                    joined = true
                    player.feedPCMStream(Data(count: Int(sampleRate * Self.gap) * 2))
                }
                player.feedPCMStream(chunk)
            }
            if joined || stopped { return joined }
            guard isFirst, !started else { return false }
            // The stream never opened (an engine refusal, a server that
            // answered with the whole file): play what came back in one piece.
            let audio: Data
            switch result {
            case .pcm(let pcm, let rate): audio = AudioLoudness.wavData(fromPCM16: pcm, sampleRate: Int(rate))
            case .mp3(let data): audio = data
            }
            guard !audio.isEmpty else { return false }
            try player.play(audio, source: "call_goodbye") { [weak self] in self?.onFinish() }
            started = true
            onStart()
            return true
        } catch {
            return joined
        }
    }

    /// No more pieces are coming.
    func finish() {
        if streaming, !stopped { player.finishPCMStream() }
    }

    func stop() {
        stopped = true
        player.stop()
    }
}
