import Foundation

/// Coach mode (2026-09-28): the call's listening moment, used.
///
/// The learner already studies words; the call is the only place they can be
/// spent, and the chip row above the transcript only waits for that to happen
/// by chance. Coach mode makes it happen on purpose — the fluent self may ask
/// something whose natural answer uses a word the learner is studying, and
/// while they think about their answer, their own "Listening…" bubble says
/// "Try using · *profound*". It ticks the moment they do, by the same
/// `CarryoverDetector` the chips use.
///
/// **The hint comes FROM the question, never from a list.** The first cut
/// picked the next word in list order and told the model to ask about it; the
/// model rightly ignored the words that didn't fit, but it ends most lines
/// with a question anyway, so the learner was shown words in list order with
/// no relation to what they had just been asked (device test, same day). Now:
/// - the steer hands the model the whole CANDIDATE list as permission ("if
///   one of these fits what you're already talking about…"), and
/// - after each line, `CoachSuggester` writes an answer to the line that was
///   ACTUALLY said, and only names a candidate when that answer naturally
///   uses one — nothing, the ordinary case, draws no word hint (the
///   suggestion itself is drawn every line; it replaced `CoachJudge`
///   2026-10-01).
///
/// `CoachPlan` rations it in code: at most `maxHints` a call and
/// `repliesBetweenHints` plain lines after each; the steer is withdrawn
/// during the gap so the conversation gets its own turns.
///
/// ON by default for A1/A2, off above (2026-09-30, founder's call): a
/// beginner is who the slower, steered call is for, and a switch buried in
/// Call settings is one they never find. The learner's own flip always wins
/// — the key is only written by the toggle, so "never touched" is the
/// absence of a value, and the default follows the level until then.
/// Realtime path only: the gateway takes the steer on `set` and appends it to
/// the reply's system prompt (`SetMessage.steer`).
enum CoachMode {
    static let key = "futurevoice.call.coachMode"

    static func defaultOn(for level: CEFRLevel) -> Bool { level == .a1 || level == .a2 }

    /// The learner's choice if they made one, else the level's default.
    /// Views pass their `@AppStorage` values so they re-render on change.
    static func resolve(choice: Bool?, levelRaw: String) -> Bool {
        choice ?? defaultOn(for: CEFRLevel(rawValue: levelRaw) ?? .b1)
    }

    static var isOn: Bool {
        let d = UserDefaults.standard
        return resolve(choice: d.object(forKey: key) as? Bool,
                       levelRaw: d.string(forKey: AppState.proficiencyKey) ?? "")
    }

    /// How many studied items the model and the judge are shown at once.
    static let maxCandidates = 8
}

/// Tutor mode (2026-10-13; rebuilt 2026-10-24, founder: "the goal of the
/// call is that they can say it properly — keep repeating until they nail
/// it").
///
/// The call is a LESSON with one goal: a topic (the call's own, one picked
/// from the button right of the pill, or one said when asked) becomes a
/// curriculum of 3–4 challenges (`TutorLesson`), shown as a checklist above
/// the transcript. The tutor stays on a challenge until the app ticks it —
/// no fixes from the correction call AND the judge says the line did it —
/// then moves on; a finished lesson ends the call into the usual wrap-up,
/// and one left halfway is picked up by the next tutor call.
///
/// It lives in the conversation's SYSTEM prompt
/// (`ConversationEngine.tutorBlock`), resent on every tick (`set.system`);
/// the tutor's own lines for a topic picked or a lesson ready go out as
/// gateway `nudge` notes. Off by default; with it off the prompt is
/// byte-identical to before (`TutorModeTests`).
///
/// A tutored call is judged LINE BY LINE (2026-10-28, `Turn.tutorRole`): a
/// challenge line is a drill (a set sentence, an example in front of them,
/// often a repeat of a correction) and only a try at the final check — the
/// whole thing in one go, nothing on screen — is evidence. A call that never
/// reached the check is a practice call (`Session.isPractice`).
enum TutorMode {
    static let key = "futurevoice.call.tutorMode"

    /// Hidden 2026-10-16 while the concept was rethought; back 2026-10-24
    /// as the goal-and-curriculum lesson. A learner who had it on before
    /// still has it on.
    static let isAvailable = true

    static var isOn: Bool { isAvailable && UserDefaults.standard.bool(forKey: key) }
}

/// Send-to-answer turns (2026-10-15, founder: "for beginners — the question
/// comes, the learner talks, presses send, and only then the next turn").
///
/// A pause never ends the learner's turn; the Send button above the pill
/// does (`RealtimeTalkClient.sendTurn`), and Clear throws the turn away. The
/// gateway holds everything the transcriber hears until then
/// (`StartMessage.manualTurns`). Training wheels, not a second kind of call:
/// the screen, the voice and the transcript are unchanged — only who decides
/// the turn is over.
///
/// ON by default for A1, A2 and B1 (A2 added 2026-10-16, founder: the same
/// beginners coach mode is on for; B1 2026-11-06, founder: a B1 learner who
/// pauses mid-sentence was cut off 11 times in one call); the learner's own
/// flip always wins, like
/// `CoachMode` (the key is written only by the toggle). Realtime path only.
enum SendToAnswer {
    static let key = "futurevoice.call.sendToAnswer"

    static func defaultOn(for level: CEFRLevel) -> Bool { level == .a1 || level == .a2 || level == .b1 }

    static func resolve(choice: Bool?, levelRaw: String) -> Bool {
        choice ?? defaultOn(for: CEFRLevel(rawValue: levelRaw) ?? .b1)
    }

    static var isOn: Bool {
        let d = UserDefaults.standard
        return resolve(choice: d.object(forKey: key) as? Bool,
                       levelRaw: d.string(forKey: AppState.proficiencyKey) ?? "")
    }
}

/// The ration, as a value so it can be reasoned about (and tested) apart
/// from the call screen.
struct CoachPlan: Equatable {
    static let maxHints = 3
    static let repliesBetweenHints = 2

    private(set) var hintsShown = 0
    private(set) var hinted: [String] = []
    /// Lines since the last hint (or since the call opened).
    private var repliesSinceHint = Self.repliesBetweenHints

    /// Whether a hint may be drawn for the NEXT line — and therefore whether
    /// the model should be steered for it.
    var mayHint: Bool {
        hintsShown < Self.maxHints && repliesSinceHint >= Self.repliesBetweenHints
    }

    /// Items still worth offering, in the caller's order.
    func candidates(from pending: [TalkGoalItem]) -> [TalkGoalItem] {
        Array(pending.filter { !hinted.contains($0.key) }.prefix(CoachMode.maxCandidates))
    }

    /// A fluent-self line has finished.
    mutating func replyFinished() { repliesSinceHint += 1 }

    /// The judge matched a question to `item` and it is on screen.
    mutating func hintShown(_ item: TalkGoalItem) {
        hintsShown += 1
        hinted.append(item.key)
        repliesSinceHint = 0
    }

    static func endsInQuestion(_ text: String) -> Bool {
        let closers = CharacterSet(charactersIn: "\"'”’」』)） \n\t")
        let trimmed = text.trimmingCharacters(in: closers)
        return trimmed.hasSuffix("?") || trimmed.hasSuffix("？")
    }
}

extension ConversationEngine {
    /// The steer coach mode hands the gateway while a hint may be drawn:
    /// the candidate list as PERMISSION, never an assignment. English like
    /// every other prompt; items quoted as the learner saved them.
    static func coachSteer(for items: [TalkGoalItem], focus: GrammarFocus? = nil) -> String {
        var parts: [String] = []
        if !items.isEmpty {
            let list = items.map { "\"\($0.text)\"" }.joined(separator: ", ")
            parts.append("""
                COACH MODE. The learner is studying: \(list). If — and only if — \
                one of them fits what you are ALREADY talking about, you may end \
                this reply with a question whose most natural answer would use \
                it. Do not say that word yourself, do not mention practice, words \
                or coaching, and never steer the topic toward a word. Most \
                replies should simply continue the conversation as they would \
                have.
                """)
        }
        // The grammar focus rides the same permission: a question whose
        // natural answer NEEDS the structure is practice the learner gets
        // without being told. The correction itself stays the card's job.
        if let focus {
            parts.append("""
                GRAMMAR FOCUS. The learner keeps slipping on this: they say \
                "\(focus.pattern.mistake)" where a fluent speaker says \
                "\(focus.pattern.correction)" (\(focus.pattern.context)). If it \
                fits the conversation, you may ask something whose natural answer \
                needs that structure. Never correct them in your reply, never \
                mention grammar, and don't do it every turn.
                """)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// Coach mode's answer for EVERY line (2026-10-01, founder: "every turn, a
/// suggestion of how to answer"). The word hint above only ever fired when a
/// studied item fit, so most turns a beginner faced the question empty-handed
/// — and the empty hand, not the question, is what stops them talking.
///
/// One short thing they could say back, at their level, with a blank where
/// only they know the answer ("I usually get up at ___."), and its meaning in
/// their own language. It is a starting point, not a script: the blank makes
/// them add their own words. It runs on the opener too — the first answer of
/// a call is the hardest one. When a studied item fits the answer naturally
/// the suggestion carries it and names it, which is how the word hint is
/// drawn now (one call per line, not two).
struct CoachReply: Equatable {
    /// Target language. "[7]" is an example the learner swaps for their own
    /// words — drawn faded (`CoachReplyLabel`).
    let say: String
    /// Native language, the same brackets translated.
    let meaning: String
    let turnId: UUID
    /// The label above the line — "Try saying", or "You go first" when the
    /// learner opens the call (`StarterSituation.learnerFirst`).
    /// nil = "Try saying". Already localized.
    var heading: String? = nil
}

/// Whether a learner's line was READ off the coach's "try saying"
/// (2026-10-14, founder: "even with coach mode on, if they don't use the
/// suggested sentence as is, it doesn't matter"). A coached call used to be
/// a practice call as a whole; now only the lines read off the suggestion
/// are left out of the score, the level and "used in a talk". A line built
/// around the WORD hint counts in full — making the sentence is the practice
/// (founder, same day).
///
/// Read = most of the suggestion's own words came out (`minCoverage`) and
/// they are most of what was said (`minShare`), so reading it and then
/// carrying on in their own words counts as their own line. The faded
/// "[example]" and the "___" blank are theirs to fill, so they are not part
/// of the comparison. A suggestion with fewer than `minFixedWords` words of
/// its own ("Yes, [I do].") can't be told apart from answering, and never
/// counts as read.
enum CoachRead {
    static let minCoverage = 0.8
    static let minShare = 0.6
    static let minFixedWords = 3

    static func isRead(_ said: String, line: String?) -> Bool {
        guard let line, !line.isEmpty else { return false }
        let fixed = words(line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ",
                                                    options: .regularExpression))
        guard fixed.count >= minFixedWords else { return false }
        let spoken = words(said)
        guard !spoken.isEmpty else { return false }
        let fixedSet = Set(fixed), spokenSet = Set(spoken)
        let coverage = Double(fixedSet.intersection(spokenSet).count) / Double(fixedSet.count)
        let share = Double(spoken.filter { fixedSet.contains($0) }.count) / Double(spoken.count)
        return coverage >= minCoverage && share >= minShare
    }

    private static func words(_ text: String) -> [String] {
        WordSplitter.words(CarryoverDetector.normalized(text)).filter { !$0.isEmpty }
    }
}

@MainActor
enum CoachSuggester {
    private struct Payload: Decodable {
        let say: String?
        let meaning: String?
        let word: String?
    }

    /// One line of the call before the one being answered.
    struct Line {
        let isLearner: Bool
        let text: String
    }

    /// How many earlier lines ride along. The suggestion only knew the line
    /// before and the learner's last turn, so it answered each question as if
    /// the call had just started and invented the learner's facts (2026-10-22,
    /// founder: "아무 말이나 적어두지 말고").
    static let recentLines = 8
    /// The newest notebook lines handed over, so a bracket holds the
    /// learner's own fact rather than a guess.
    static let maxFacts = 12

    static func suggest(line: String,
                        recent: [Line],
                        aboutLearner: [String] = [],
                        otherSpeaker: String? = nil,
                        situation: String? = nil,
                        register: SpeechRegister? = nil,
                        previousSay: String? = nil,
                        candidates: [TalkGoalItem],
                        target: String,
                        native: String,
                        level: CEFRLevel,
                        turnId: UUID) async -> (reply: CoachReply, item: TalkGoalItem?)? {
        var content = ""
        if let otherSpeaker, !otherSpeaker.isEmpty { content += "The other speaker: \(otherSpeaker)\n" }
        if let situation, !situation.isEmpty { content += "Situation: \(situation)\n" }
        if !aboutLearner.isEmpty {
            content += "About the learner:\n" + aboutLearner.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        let said = recent.suffix(recentLines).filter { !$0.text.isEmpty }
        if !said.isEmpty {
            content += "The call so far:\n" + said.map {
                "\($0.isLearner ? "Learner" : "Other"): \"\($0.text)\""
            }.joined(separator: "\n") + "\n"
        }
        // The level was read off this one line, so a line with no clear
        // ending re-decided it and the suggestions flipped between 반말 and
        // 존댓말 inside one call (2026-10-09). The last suggestion anchors it
        // where the call has no level of its own (a scene).
        if let previousSay, !previousSay.isEmpty { content += "Your previous suggestion was: \"\(previousSay)\"\n" }
        content += "Now the other speaker says: \"\(line)\""
        if !candidates.isEmpty {
            content += "\n\nStudied items:\n" + candidates.map { "- \($0.text)" }.joined(separator: "\n")
        }
        let payload: Payload? = try? await GeminiClient.background.sendJSON(
            system: system(target: target, native: native, level: level, register: register),
            messages: [GeminiClient.Message(role: .user, content: content)],
            // The default model, not flash-lite (2026-10-04): the line is
            // what the learner is about to SAY, and flash-lite wrote "I will
            // have a coffee please" and "I'm going to London, please" under
            // a prompt that forbids both; 3.6 Flash didn't, at the same
            // ~1–1.8 s. Its thinking needs room, or the JSON comes back cut:
            // routed to Haiku, it thinks 680–970 tokens on a B1+ answer, and
            // at 1000 three of 80 probe answers came back cut (2026-10-30).
            model: .flash36,
            maxTokens: 2000,
            purpose: "coach",
            idempotencyKey: "coach-reply:\(turnId.uuidString)",
            requestTimeout: 8,
            fastThinking: true)
        // The line it answers can carry another script — the learner's name
        // in Hangul on an English call — and flash-lite followed it and wrote
        // the whole suggestion in Korean (device test, 2026-10-01). A
        // suggestion they can't say in the call's language is no suggestion.
        guard let say = payload?.say?.trimmingCharacters(in: .whitespacesAndNewlines),
              !say.isEmpty,
              TextScript.isInTargetScript(say, language: target) else { return nil }
        // A learner whose own language IS the one on the call (an English
        // app learning English) would read the same sentence twice.
        let meaning = LanguageCatalog.sameLanguage(target, native) ? ""
            : payload?.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var item: TalkGoalItem?
        if let word = payload?.word?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty {
            let wanted = CarryoverDetector.normalized(word)
            item = candidates.first { $0.key == wanted || CarryoverDetector.normalized($0.text) == wanted }
        }
        return (CoachReply(say: say, meaning: meaning, turnId: turnId), item)
    }

    /// What a suggestion at this level SAYS, not only which words it uses
    /// (2026-10-30, founder: the suggestions read the same at every level).
    /// Every band was held to 3–10 words, one sentence, "kept easy", so a C1
    /// learner was handed "I'll have the pasta". The ladder follows the
    /// tutor's (`TutorPlanner.levelLadder`): what grows is the content — a
    /// reason, a story, a view, steering the talk — and length only with it.
    static func suggestionShape(for level: CEFRLevel) -> String {
        switch level {
        case .a1:
            return "3–6 words, one short sentence with ONE fact or answer. Kept easy."
        case .a2:
            return """
            One sentence, about 5–10 words: the answer plus one small detail \
              or a reason with "because" / "but". Kept easy.
            """
        case .b1:
            return """
            One or two sentences, about 8–15 words: the answer plus WHY or a \
              short example from their own life — what a B1 speaker can say \
              but doesn't yet say on their own.
            """
        case .b2:
            return """
            One or two sentences, about 10–20 words: a view, not only a fact \
              — the answer with a reason, a contrast ("…, though …") or a \
              comparison, or a follow-up that keeps the talk going. Natural \
              hedging ("I guess", "kind of") where a native would use it.
            """
        case .c1, .c2:
            return """
            One or two sentences, about 10–25 words, the way a fluent adult \
              really talks: an idiom or a precise word where it fits, nuance, \
              a light aside or humour, and steering the talk where they want \
              it. Never simplified — this learner is here for what they can't \
              produce yet.
            """
        }
    }

    /// Internal, not private, so `CoachPromptDumpTests` can hand the live
    /// prompt to `scripts/coach-probe.py`.
    static func system(target: String, native: String, level: CEFRLevel,
                       register: SpeechRegister?) -> String {
        let targetName = LanguageCatalog.englishName(target)
        let address: String
        if let register, SpeechRegister.hasForms(target) {
            address = """
            - The learner speaks to the other person in \(register.promptDescription(in: target)). \
              Every "say" is in that form, whatever endings the line itself \
              happens to use.
            """
        } else {
            address = """
            - Use the same form of address the other speaker uses with them \
              (Korean 반말 or 존댓말, Japanese plain or polite, du or Sie, tu or \
              vous…), and keep ONE form for the whole call: when a previous \
              suggestion is given, use its form unless this line clearly \
              changes it.
            """
        }
        let nativeName = LanguageCatalog.englishName(native)
        let scale = ConversationEngine.speechScale(for: level)
        return """
        A \(level.rawValue.uppercased()) learner of \(targetName) is on a spoken call. \
        The other speaker has just said the line below. Write ONE thing the \
        learner could say back next — exactly what a native speaker would \
        actually say out loud in that moment, at THIS learner's level. Never \
        a textbook sentence: if a native would not say it that way, it is \
        wrong however simple it is.

        - SPOKEN, not written: contractions where speech has them ("I'll", \
          "I'm", "don't"), the everyday phrasing people really use in that \
          place ("Can I get a latte?", "I'll have the pasta", "Just looking, \
          thanks"), never a stiff full form ("I will have a coffee please").
          When a situation is given, answer as a real customer, guest or \
          caller there would. One answer, one idea — not "just looking" AND \
          a request — and "please" only on a request, never on a statement \
          ("I'm going to London, please").

        - "say": in \(targetName) ONLY — always, even when the line contains \
          names or words in another language. \(suggestionShape(for: level)) \
          \(scale.vocabulary)\(ConversationEngine.varietyGuard(target))
        - Where the answer depends on something only the learner knows (their \
          name, a time, a place, what they did, what they like, which drink \
          or dish or item they want), put a \
          plausible EXAMPLE in square brackets — "I usually get up at [7]." — \
          which the learner swaps for their own. It is shown faded as a \
          placeholder, so it is never a claim about them. One or two \
          brackets, a word or two inside each, nothing else in brackets. \
          Every detail of their life the answer gives (a city, how long, \
          who, what they did) is in brackets or left out, never stated \
          plainly: a longer answer adds a reason or a view, not more facts.\(bracketAgreementLine(target))
        - It is the SAME person who said the learner's earlier lines in the \
          call: carry on from what they already said, never contradict it, \
          never give again a fact they already gave, and stay on the thread \
          the two are on. Answer what THIS line asks, not an earlier one.
        - When the answer is about the learner and "About the learner" \
          covers it, the bracketed example IS that fact, said in \
          \(targetName) ("I'm a [designer]" for someone who designs), not a \
          guess. Bring up only what this line asks about; never pull in a \
          fact it didn't ask for.
        - When "The other speaker" is given, answer as the learner would \
          talk to THAT person: someone they know well gets the shorthand of \
          people who share a life (no introductions, no "nice to meet you"), \
          a new acquaintance gets easy small talk, a public figure gets what \
          a fan would actually say to them. Their own future self already \
          knows everything about them: never introduce yourself to it.
        - When the line asks them to say something again, to say it all in \
          one go, or hands them a line to say, "say" is that sentence \
          itself, starting on its own first word: the words they are \
          practising, taken from their earlier lines or the line handed to \
          them and fitted to them, with nothing before or after it. It is \
          the sentence to practise, not a reply to being asked.
        - If the line asks nothing, "say" is a natural reaction or a short \
          follow-up question back, about what was just said.
        - Asking the same question straight back ("And you?", "Und du?", \
          "너는?") is something people do now and then, not on every answer: \
          by default "say" just answers. Never ask back what the line already \
          told them (they gave their name, then asked yours).
        \(address)
        - Honorifics that raise a person (Korean -(으)시-, Japanese 尊敬語) \
          are for the OTHER person only — never on the learner's own \
          actions, even when the line used them: Korean 살았어요, not \
          사셨어요.
        - "meaning": the \(nativeName) translation, natural, with the \
          bracketed example translated inside brackets in the matching place.
        - "word": if studied items are listed and one fits this answer \
          naturally — in its usual sense, carrying what the answer means — \
          use it in "say" and return it exactly as listed. Otherwise null, \
          which is the usual case. Never force one in.

        Return STRICT JSON only: {"say": "...", "meaning": "...", "word": null}
        """
    }
}
