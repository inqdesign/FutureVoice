import CryptoKit
import Foundation

/// The report, PRESENTED (2026-10-27, docs/personal-report-plan.md): the
/// fluent self reads the deck aloud, one or two sentences per card, in the
/// voice the learner picked, and the deck moves on when a line ends.
///
/// Founder's picks: the TARGET language at the learner's level, with the
/// native-language caption under it — it is listening practice, and it keeps
/// the fluent self fluent; the caption carries the explanation. First home:
/// the free-minutes report, the moment a learner decides.
///
/// Same rule as the coach note: the script is written FROM the facts the code
/// already put on each card (`ReportNarrator.facts`), never asked for numbers.
/// Written in two halves because the deck fills in two: the counts cards are
/// known the moment it opens, the coach and the level land seconds later.
struct ReportNarration: Codable, Equatable {
    struct Line: Codable, Equatable, Hashable {
        /// `WeekRecapSheet.Card`'s name.
        var card: String
        /// What the fluent self says — target language, the learner's level.
        var text: String
        /// The same line in the native language, for the caption.
        var caption: String
    }

    var lines: [Line] = []

    func line(for card: String) -> Line? { lines.first { $0.card == card } }

    mutating func merge(_ more: [Line]) {
        for line in more {
            if let i = lines.firstIndex(where: { $0.card == line.card }) { lines[i] = line } else { lines.append(line) }
        }
    }
}

enum ReportNarrator {
    /// One card the narrator is asked to speak over, with what is on it.
    struct CardFacts {
        var card: String
        var facts: [String]
    }

    /// The ledger tag for both the script and the voice. The voice is free
    /// to the learner (`tts` FREE_PURPOSES): this report is shown to a
    /// learner whose free minutes are spent, and a report that costs them
    /// minutes they don't have would be a wall.
    static let purpose = "report-narration"

    /// Lines past this length are cut to their first sentences: a card is
    /// looked at for a few seconds, and a paragraph read over it is a lecture.
    static let maxLineCharacters = 220

    static func write(cards: [CardFacts],
                      firstTalks: Bool,
                      targetLanguage: String,
                      nativeLanguage: String = LanguageCatalog.currentNative,
                      level: CEFRLevel,
                      learnerName: String?) async throws -> [ReportNarration.Line] {
        guard !cards.isEmpty else { return [] }
        let target = LanguageCatalog.englishName(targetLanguage)
        let native = LanguageCatalog.englishName(nativeLanguage)
        let scale = ConversationEngine.speechScale(for: level)
        let span = firstTalks ? "their first talks with you, the free minutes that just ran out"
                              : "the week that just closed"
        let system = """
        You are the learner's fluent future self — them, a few years on, \
        speaking \(target) with ease, in their own voice. You are presenting \
        their report to them, card by card, like a friend walking them \
        through a few slides about \(span). Each card is on screen while you \
        speak over it.

        For EVERY card listed, write:
        - "text": what you say over it, in \(target). One or two short \
        spoken sentences, at most ~25 words. Pitch it to their level \
        (\(level.rawValue.uppercased())): \(scale.vocabulary) They must be \
        able to follow it by ear. Talk TO them ("you"), informally, the way \
        you'd talk to yourself. Say what the card means for them, don't read \
        the card out; one number at most per line, only one that is in the \
        facts. The first card opens the report; the last one hands over to \
        what comes next.
        - "caption": the same line in natural \(native), the same informal \
        register (Korean: 반말, never 해요체 or 당신; Japanese: タメ口). \
        Always \(native), whatever language the facts are written in; \
        the words they should say stay in \(target) inside it.

        \(CoachingLanguage.selfWarmth)

        \(CoachingLanguage.breathPunctuation)

        THEY LEARN FROM YOUR VOICE: never say their mistake out loud — \
        say the RIGHT way ("next time, try: I've been working here for \
        three years"), and the caption can name what changed. No grammar \
        terms in what you say (no "present perfect", "article", "tense"); \
        say the words themselves. A word to reach for next goes inside a \
        short sentence of the kind they could use.

        SAY IT THE WAY IT IS SPOKEN: a level is written in "text" as the \
        words a person says (English "A two", German "A zwei", Spanish "A \
        dos", Korean "에이 투", Japanese "エーツー"), never "A2" — the \
        synthesizer misreads the code. The caption keeps "A2".

        RULES: use only the facts given for each card — never invent a \
        number, a word they said, a level or a plan. A quote may appear only \
        if it is in the facts, copied exactly. No exclamation marks, no \
        slogans, no "Great job!" — warmth is in noticing something specific. \
        Never mention cards, slides or the app. \(firstTalks ? "Never say \"this week\" or \"last week\"." : "")

        Return JSON only: {"lines": [{"card": "...", "text": "...", "caption": "..."}]}, \
        one entry per card, same order, the card names exactly as given.
        """
        var user = learnerName.map { "Learner's name: \($0)\n\n" } ?? ""
        user += cards.map { c in
            "CARD \(c.card)\n" + c.facts.map { "- \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let response: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [.init(role: .user, content: user)],
            maxTokens: 4096,
            purpose: purpose,
            requestTimeout: 45
        )
        let asked = Set(cards.map(\.card))
        return response.lines.compactMap { raw in
            let text = trimmed(raw.text)
            guard asked.contains(raw.card), !text.isEmpty else { return nil }
            return .init(card: raw.card, text: text,
                         caption: raw.caption.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private struct Payload: Decodable {
        struct Raw: Decodable { var card: String; var text: String; var caption: String }
        var lines: [Raw]
    }

    /// Whole sentences up to `maxLineCharacters`, at least one.
    static func trimmed(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxLineCharacters else { return clean }
        var out = ""
        for sentence in PacedSpeech.sentences(in: clean) {
            let next = out.isEmpty ? sentence : out + " " + sentence
            if next.count > maxLineCharacters, !out.isEmpty { break }
            out = next
        }
        return out
    }
}

// MARK: - What each card shows

extension ReportNarrator {
    /// Everything the deck knows when it asks for a line. Each card's facts
    /// are the card's own content, in English for the model — the script is
    /// written in the target language and captioned in the native one.
    struct Context {
        var recap: WeekRecap
        var isTrial: Bool
        var level: CEFRLevel?
        var levelRationale: String?
        var testScore: Int?
        var testTotal: Int?
        var testThin = false
        var routineHeadline: String?
        var routine: [String] = []
    }

    /// The cards whose content is known the moment the deck opens.
    static let earlyCards: Set<String> = ["cover", "talk", "used", "review", "fresh", "stumbles"]

    static func facts(card: String, _ c: Context) -> CardFacts? {
        let r = c.recap
        var f: [String] = []
        switch card {
        case "cover":
            if c.isTrial {
                f.append("Opening card: their free minutes are over. They talked \(r.talkMinutes) min in \(r.talks.count) talk(s).")
            } else if r.hasActivity {
                f.append("Opening card: the week. They practised \(r.daysActive) of 7 days, \(r.talkMinutes) min of talk.")
                if r.streak > 1 { f.append("Streak: \(r.streak) days.") }
            } else {
                f.append("Opening card: a quiet week, nothing practised. One talk is enough to start again.")
            }
        case "talk":
            f.append("They talked \(r.talkMinutes) min in \(r.talks.count) talk(s).")
            let titles = r.talks.prefix(4).map(\.title)
            if !titles.isEmpty { f.append("Talks: \(titles.joined(separator: " · "))") }
            let previous = r.previousTalkSeconds / 60
            if previous > 0 { f.append("The week before: \(previous) min.") }
        case "used":
            f.append("\(r.usedCount) thing(s) they had studied, then said themselves in a real talk.")
            for e in r.used.prefix(3) { f.append("Used: \(e.item) — in \"\(e.quote)\"") }
        case "review":
            if !r.nowYours.isEmpty {
                f.append("\(r.nowYours.count) word(s)/phrase(s) became theirs: \(r.nowYours.prefix(6).joined(separator: ", ")).")
            }
            if !r.sentencesGot.isEmpty { f.append("\(r.sentencesGot.count) sentence card(s) learned.") }
            if r.shadowTakes > 0 {
                f.append("\(r.shadowTakes) shadowing take(s)" + (r.shadowAverage.map { ", average score \($0)" } ?? "") + ".")
            }
            if r.scenes > 0 { f.append("\(r.scenes) scene(s) watched.") }
        case "fresh":
            if r.newExpressionCount > 0 {
                f.append("\(r.newExpressionCount) phrase(s) YOU (the fluent self) said that they haven't said yet; they are saved for them.")
                for e in r.newExpressions.prefix(3) { f.append("Phrase: \(e.item)") }
            }
            if r.newCards > 0 { f.append("\(r.newCards) new review card(s) made from their corrections.") }
        case "stumbles":
            if !r.stumbles.isEmpty {
                f.append("The same correction came back more than once:")
                for s in r.stumbles.prefix(3) { f.append("\"\(s.was)\" → \"\(s.now)\", \(s.count) times") }
            } else if !r.shakyLines.isEmpty {
                f.append("Lines that didn't quite land when they shadowed them:")
                for s in r.shakyLines.prefix(2) { f.append("\"\(s.now)\" (score \(s.count))") }
            }
        case "grammar":
            guard let coach = r.coach else { return nil }
            if coach.grammar.isEmpty {
                f.append("No grammar point kept coming back.")
            } else {
                for p in coach.grammar.prefix(2) {
                    f.append("Grammar point that slipped in different sentences: \(p.rule)"
                             + (p.examples.first.map { " — e.g. \"\($0.was)\" → \"\($0.now)\"" } ?? ""))
                }
            }
        case "words":
            guard let coach = r.coach else { return nil }
            if coach.upgrades.isEmpty {
                f.append("No word carried too much of the load.")
            } else {
                for u in coach.upgrades.prefix(2) {
                    f.append("They leaned on \"\(u.instead)\" (\(u.count) times); a word to reach for next: \"\(u.better)\".")
                }
            }
        case "coach":
            guard let coach = r.coach else { return nil }
            f.append("The coach's headline: \(coach.headline)")
            if !coach.insight.isEmpty { f.append("How they speak: \(coach.insight)") }
            for p in coach.plan.prefix(3) { f.append("Next up: \(p)") }
        case "trialTest", "trialTestDone":
            if let s = c.testScore, let t = c.testTotal {
                f.append("They took a short test made from their own talks: \(s)/\(t).")
            } else if c.testThin {
                f.append("Their talks were too short to make a test from; the report goes on without it.")
            } else {
                f.append("Next: a short test made from what they said — the words, the phrases, the corrections. They can take it or skip it.")
            }
        case "level":
            guard let level = c.level else { return nil }
            f.append("Their speaking level, read from their talks: \(level.rawValue.uppercased()).")
            if let why = c.levelRationale, !why.isEmpty { f.append("Why: \(why)") }
            f.append("It moves as they talk.")
        case "routine":
            if let h = c.routineHeadline { f.append("A routine to keep going: \(h)") }
            for line in c.routine.prefix(4) { f.append("Routine: \(line)") }
            f.append("Last card. The button under it keeps this routine going. Hand over to it; don't mention prices or plans.")
        case "test":
            f.append("Last card: this week's test, made from their week, is ready.")
        default:
            return nil
        }
        return f.isEmpty ? nil : CardFacts(card: card, facts: f)
    }
}

// MARK: - Playback

/// Speaks the current card's line and says when it is done, so the deck can
/// move on. Every take is kept in `PhraseAudioStore` (keyed by text + voice),
/// so opening the report again replays it without a second synthesis.
@MainActor
final class ReportNarrationPlayer: ObservableObject {
    /// The learner can silence it from the deck's top bar; the captions stay.
    @Published var isOn = true
    @Published private(set) var speakingCard: String?
    @Published private(set) var loadingCard: String?

    private let player = AudioPlayer()
    private var voiceId: String?
    /// Bumped on every `speak`/`stop`, so a take that lands after the
    /// learner swiped on is never played over the next card.
    private var generation = 0
    private var prefetching: Set<String> = []

    func configure(voiceId: String?) { self.voiceId = voiceId }

    func stop() {
        generation += 1
        player.stop()
        speakingCard = nil
        loadingCard = nil
    }

    /// Plays `line` for `card`; `finished` runs when it ends on its own
    /// (never when it was stopped or replaced).
    func speak(_ line: ReportNarration.Line, finished: @escaping () -> Void) {
        stop()
        guard isOn, let voiceId else { return }
        let mine = generation
        Task {
            loadingCard = line.card
            let data = await audio(for: line.text, voiceId: voiceId)
            guard mine == generation else { return }
            loadingCard = nil
            guard let data else { return }
            speakingCard = line.card
            do {
                try player.play(data, source: "report", forceSessionReset: true) { [weak self] in
                    guard let self, mine == self.generation else { return }
                    self.speakingCard = nil
                    finished()
                }
            } catch {
                speakingCard = nil
            }
        }
    }

    /// Makes the takes ahead of time, in deck order, so a swipe doesn't wait
    /// on the network.
    func prefetch(_ lines: [ReportNarration.Line]) {
        guard let voiceId else { return }
        let todo = lines.filter { !prefetching.contains($0.text)
            && PhraseAudioStore.shared.data(text: $0.text, voiceId: voiceId, allowLineage: false) == nil }
        guard !todo.isEmpty else { return }
        todo.forEach { prefetching.insert($0.text) }
        Task {
            for line in todo { _ = await audio(for: line.text, voiceId: voiceId) }
        }
    }

    private func audio(for text: String, voiceId: String) async -> Data? {
        if let kept = PhraseAudioStore.shared.data(text: text, voiceId: voiceId, allowLineage: false) {
            return kept
        }
        do {
            let data = try await VoiceClient.shared.synthesize(
                voiceId: voiceId, text: text,
                idempotencyKey: "report:" + SHA256.hash(data: Data("\(voiceId)|\(text)".utf8))
                    .prefix(16).map { String(format: "%02x", $0) }.joined(),
                purpose: ReportNarrator.purpose)
            PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId)
            return data
        } catch {
            Analytics.capture("report_narration_tts_failed", ["error": "\(error)".prefix(160).description])
            return nil
        }
    }
}
