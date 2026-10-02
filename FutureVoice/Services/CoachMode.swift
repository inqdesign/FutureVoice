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
}

@MainActor
enum CoachSuggester {
    private struct Payload: Decodable {
        let say: String?
        let meaning: String?
        let word: String?
    }

    static func suggest(line: String,
                        learnerSaid: String?,
                        earlier: String?,
                        candidates: [TalkGoalItem],
                        target: String,
                        native: String,
                        level: CEFRLevel,
                        turnId: UUID) async -> (reply: CoachReply, item: TalkGoalItem?)? {
        var content = ""
        if let earlier, !earlier.isEmpty { content += "Earlier they said: \"\(earlier)\"\n" }
        if let learnerSaid, !learnerSaid.isEmpty { content += "The learner said: \"\(learnerSaid)\"\n" }
        content += "Now the other speaker says: \"\(line)\""
        if !candidates.isEmpty {
            content += "\n\nStudied items:\n" + candidates.map { "- \($0.text)" }.joined(separator: "\n")
        }
        let payload: Payload? = try? await GeminiClient.background.sendJSON(
            system: system(target: target, native: native, level: level),
            messages: [GeminiClient.Message(role: .user, content: content)],
            model: .flashLite31,
            maxTokens: 300,
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

    private static func system(target: String, native: String, level: CEFRLevel) -> String {
        let targetName = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        let scale = ConversationEngine.speechScale(for: level)
        return """
        A \(level.rawValue.uppercased()) learner of \(targetName) is on a spoken call. \
        The other speaker has just said the line below. Write ONE short thing \
        the learner could say back next — an easy, natural answer the way a \
        real person would reply, not a textbook sentence.

        - "say": in \(targetName) ONLY — always, even when the line contains \
          names or words in another language. 3–10 words, one sentence (two \
          very short ones at most). \(scale.vocabulary)
        - Where the answer depends on something only the learner knows (their \
          name, a time, a place, what they did, what they like), put a \
          plausible EXAMPLE in square brackets — "I usually get up at [7]." — \
          which the learner swaps for their own. It is shown faded as a \
          placeholder, so it is never a claim about them. One or two \
          brackets, a word or two inside each, nothing else in brackets.
        - If the line asks nothing, "say" is a natural reaction or a short \
          follow-up question back.
        - Use the same form of address the other speaker uses with them \
          (Korean 반말 or 존댓말, Japanese plain or polite, du or Sie, tu or \
          vous…).
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
