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
/// - after each line, `CoachJudge` reads the question that was ACTUALLY asked
///   and returns the candidate a natural answer would use — or nothing, which
///   is the ordinary answer and draws no hint.
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

/// Reads the question the fluent self just asked and names the studied item
/// a natural answer to it would use. Free (`purpose: "coach"`, flash-lite),
/// off the voice's path — it runs while the learner is already thinking.
@MainActor
enum CoachJudge {
    private struct Verdict: Decodable { let word: String? }

    static func pick(question: String,
                     learnerSaid: String?,
                     candidates: [TalkGoalItem],
                     key: String) async -> TalkGoalItem? {
        guard !candidates.isEmpty else { return nil }
        let list = candidates.map { "- \($0.text)" }.joined(separator: "\n")
        var content = ""
        if let learnerSaid, !learnerSaid.isEmpty {
            content += "The learner had said: \"\(learnerSaid)\"\n"
        }
        content += "They were then asked: \"\(question)\"\n\nStudied items:\n\(list)"
        let verdict: Verdict? = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content)],
            model: .flashLite31,
            maxTokens: 200,
            purpose: "coach",
            idempotencyKey: "coach:\(key)",
            requestTimeout: 8,
            fastThinking: true)
        guard let word = verdict?.word?.trimmingCharacters(in: .whitespacesAndNewlines),
              !word.isEmpty else { return nil }
        let wanted = CarryoverDetector.normalized(word)
        return candidates.first { $0.key == wanted || CarryoverDetector.normalized($0.text) == wanted }
    }

    private static let system = """
        A language learner is on a spoken call and has just been asked a \
        question. They are studying the items listed. Decide whether a \
        natural, honest answer to THAT question would use one of those items.

        Return {"word": "<the item exactly as listed>"} only when the fit is \
        obvious: the item would carry what the answer MEANS — the thing the \
        question is about — in its usual sense. A reaction word that could \
        end any answer ("awesome", "sure") or a small word that could appear \
        in any sentence does not count. If the learner would have to force \
        it in, if the line asks nothing, or if nothing fits, return \
        {"word": null}. null is the usual answer. Never return a word that \
        is not listed.
        """
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
