import Foundation

// MARK: - User

struct User: Codable, Identifiable {
    let id: UUID
    var email: String
    var nativeLanguage: String          // BCP-47, e.g. "ko"
    var targetLanguages: [String]       // e.g. ["en", "de"]
    var voiceCloneId: String?           // ElevenLabs voice_id
    var createdAt: Date
}

// MARK: - Learner Profile

struct LearnerProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var targetLanguage: String
    var proficiencyLevel: CEFRLevel
    var recurringMistakes: [LearnerPattern]
    var weakVocabAreas: [String]
    var strongPatterns: [String]
    var totalSessions: Int
    var totalSpeakingSeconds: Int
    var lastSessionAt: Date?
    /// Compressed long-term memory across older sessions.
    var summaryEmbedding: [Float]?
}

enum CEFRLevel: String, Codable, CaseIterable {
    case a1, a2, b1, b2, c1, c2
}

extension LearnerProfile {

    /// How many recurring mistakes the profile keeps. Spec §7.3: older
    /// history compresses into the top-N patterns by frequency.
    static let maxRecurringMistakes = 10

    /// How many weak vocab areas the profile keeps (newest-first). They are
    /// injected verbatim into the conversation system prompt, so a short list
    /// beats an exhaustive one.
    static let maxWeakVocabAreas = 5

    /// Fold one finished session into the profile — this is the "each
    /// session feeds the next" loop from spec §3. New patterns merge into
    /// `recurringMistakes` (matching on normalized mistake+correction text,
    /// bumping frequency), then the list is re-ranked and capped.
    mutating func absorb(summary: SessionSummary, speakingSeconds: Double, now: Date = Date()) {
        for incoming in summary.newPatternsDetected {
            let key = Self.patternKey(incoming)
            if let idx = recurringMistakes.firstIndex(where: { Self.patternKey($0) == key }) {
                recurringMistakes[idx].frequency += incoming.frequency
                recurringMistakes[idx].lastSeenAt = now
                // Keep the freshest phrasing of the correction/context —
                // later sessions tend to capture the cleaner version.
                recurringMistakes[idx].correction = incoming.correction
                if !incoming.context.isEmpty {
                    recurringMistakes[idx].context = incoming.context
                }
            } else {
                var p = incoming
                p.lastSeenAt = now
                recurringMistakes.append(p)
            }
        }
        recurringMistakes.sort {
            $0.frequency != $1.frequency
                ? $0.frequency > $1.frequency
                : $0.lastSeenAt > $1.lastSeenAt
        }
        if recurringMistakes.count > Self.maxRecurringMistakes {
            recurringMistakes.removeLast(recurringMistakes.count - Self.maxRecurringMistakes)
        }

        // Newest-first merge of weak vocab areas (case-insensitive dedup,
        // capped) — closes the loop into the next conversation's prompt.
        for area in summary.weakVocabAreas {
            let trimmed = area.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            weakVocabAreas.removeAll { $0.lowercased() == trimmed.lowercased() }
            weakVocabAreas.insert(trimmed, at: 0)
        }
        if weakVocabAreas.count > Self.maxWeakVocabAreas {
            weakVocabAreas.removeLast(weakVocabAreas.count - Self.maxWeakVocabAreas)
        }

        totalSessions += 1
        totalSpeakingSeconds += Int(speakingSeconds.rounded())
        lastSessionAt = now
    }

    private static func patternKey(_ p: LearnerPattern) -> String {
        let norm = { (s: String) in
            s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return norm(p.mistake) + "→" + norm(p.correction)
    }
}

struct LearnerPattern: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var mistake: String
    var correction: String
    var context: String
    var frequency: Int
    var lastSeenAt: Date
}

// MARK: - Session

enum SessionMode: String, Codable {
    case pronunciation
    case conversation
}

/// Where a talk started from — the SOURCE, distinct from the activity (a talk
/// is always the Talk activity). Drives the per-book origin badge in Practice
/// so a scenario-launched or news-launched call is tellable from a plain free
/// talk. Optional on `Session` so pre-origin rows decode unchanged.
enum SessionOrigin: String, Codable {
    case free      // Free talk — no seed topic
    case news      // Launched from an "In the news" topic
    case scenario  // Launched from a scenario (see `Session.originScenarioId`)
}

enum TurnRole: String, Codable {
    case user
    case fluentSelf
}

struct Turn: Codable, Identifiable {
    let id: UUID
    let role: TurnRole
    var audioURL: URL?
    var transcript: String
    var durationMs: Int
    let timestamp: Date
    var suggestion: TurnSuggestion?
    var fluency: FluencyStats? = nil   // measured delivery for user turns
    /// User marked this turn as misheard by speech-to-text. Excluded from
    /// every assessment path (scorecard metrics, weekly-read evidence,
    /// review material) — the recording stays in the transcript for context.
    var excludedFromScoring: Bool = false
    /// True while `transcript` still holds only the on-device recognizer's
    /// guess and the audio-grounded rewrite is in flight.
    ///
    /// On-device dictation is the weakest link in the app — it mishears
    /// accented speech and, in Korean, writes the wrong numeral system
    /// outright ("한번" → "1번", read "일번"). Gemini hears the actual
    /// recording in the same call that writes the reply, so its transcript is
    /// what the learner should ever SEE. The guess still lives in
    /// `transcript` — it goes to Gemini as a hint and is the fallback when the
    /// rewrite never lands — but a pending turn renders as a placeholder
    /// instead of showing the learner words they didn't say. Never persisted:
    /// a turn is only pending while its own reply is in flight.
    var transcriptPending: Bool = false
}

extension Turn {
    enum CodingKeys: String, CodingKey {
        case id, role, audioURL, transcript, durationMs, timestamp
        case suggestion, fluency, excludedFromScoring
    }

    // Custom decode so turns saved before `excludedFromScoring` existed still
    // load — synthesized Decodable throws keyNotFound on the missing Bool.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(TurnRole.self, forKey: .role)
        audioURL = try c.decodeIfPresent(URL.self, forKey: .audioURL)
        transcript = try c.decode(String.self, forKey: .transcript)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        suggestion = try c.decodeIfPresent(TurnSuggestion.self, forKey: .suggestion)
        fluency = try c.decodeIfPresent(FluencyStats.self, forKey: .fluency)
        excludedFromScoring = try c.decodeIfPresent(Bool.self, forKey: .excludedFromScoring) ?? false
    }
}

/// Measured speaking delivery for one user turn — from the live mic energy.
struct FluencyStats: Codable, Hashable {
    var speakingSeconds: Double        // voiced time
    var totalSeconds: Double           // voiced + mid-speech silence
    var pauseCount: Int                // mid-utterance silences ≥ ~0.35s
    var pauseSeconds: Double           // total mid-speech silence
    var longestPauseSeconds: Double
}

/// Word-level alignment from ElevenLabs `with-timestamps` synthesis. Drives
/// karaoke-style highlighting in shadow practice — the UI looks up which
/// word's [startMs, endMs] contains the current playback time.
struct WordTiming: Codable, Hashable {
    var word: String
    var startMs: Int
    var endMs: Int
}

struct TurnSuggestion: Codable, Hashable {
    var alternative: String
    var reason: String
}

struct Session: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let targetLanguage: String
    let mode: SessionMode
    var topic: String?
    let startedAt: Date
    var endedAt: Date?
    var turns: [Turn]
    var summary: SessionSummary?
    /// Set when the user shelves a finished talk whose review material
    /// (see `TalkCurriculum`) is mastered — same lifecycle as an archived
    /// scenario book. Optional so old rows decode unchanged.
    var archivedAt: Date? = nil
    /// Where this talk was launched from (free / news / scenario). Optional so
    /// pre-origin rows decode; nil is treated as free (or news if it carried a
    /// topic) for the Practice badge.
    var origin: SessionOrigin? = nil
    /// The scenario this talk was launched from, when `origin == .scenario` —
    /// lets a Talk book tie back to its scenario.
    var originScenarioId: UUID? = nil
    /// The Counterpart (local id) this talk was WITH, when it was launched
    /// from a person — a Find-people stranger or an own persona. Lets the
    /// person's card list every talk you've had with them. Optional so old
    /// rows decode unchanged.
    var counterpartId: UUID? = nil
}

extension Session {
    /// What this session is called in lists. The picked topic when there is
    /// one; otherwise the title the summary call generated into `topic`;
    /// for legacy/empty sessions, the user's own first words — anything but
    /// rows of identical "Conversation".
    var displayTitle: String {
        if let t = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let first = turns.first(where: { $0.role == .user })?.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            let words = first.split(separator: " ")
            let snippet = words.prefix(6).joined(separator: " ")
            return "\u{201C}\(snippet)\(words.count > 6 ? "…" : "")\u{201D}"
        }
        return "Conversation"
    }
}

struct SessionSummary: Codable {
    var phrasesUsed: [PhraseFeedback]
    var newPatternsDetected: [LearnerPattern]
    var suggestedDrills: [String]
    var overallNote: String
    var scorecard: SessionScorecard?
    /// Words from the core list the user used for the FIRST time this session
    /// (filled in deterministically from VocabStore — no LLM). Default keeps
    /// old saved sessions decodable.
    var newWordsUsed: [String] = []
    /// Multi-word expressions the LLM flagged AND we verified appear verbatim
    /// in the user's own turns (hallucination-guarded).
    var expressionsUsed: [String] = []
    /// Short topic labels where the user visibly lacked words this session
    /// ("cooking verbs", "phone-call phrases"). Absorbed into
    /// `LearnerProfile.weakVocabAreas` → next conversation's system prompt.
    var weakVocabAreas: [String] = []
    /// Every clear grammar slip in the user's own turns — the EVIDENCE behind
    /// the scorecard's grammar score. Quotes are verified to literally appear
    /// in the user's turns before being stored (hallucination-guarded, same
    /// policy as `expressionsUsed`).
    var grammarIssues: [GrammarIssue] = []
    /// Things the learner had already been given — a review card, or a
    /// suggestion earlier in this same call — that they then PRODUCED
    /// unprompted. Filled in deterministically by `CarryoverDetector`; no LLM.
    var carryovers: [Carryover] = []
}

/// One piece of studied material the learner actually said in a real
/// conversation. The app's strongest evidence of learning, and the one thing
/// the learner cannot notice about themselves — you don't feel yourself
/// reaching for a phrase you were corrected on last week.
///
/// Always carries the learner's OWN sentence (`quote`) and the turn it came
/// from, so the achievement is shown as evidence — with their own recording
/// one tap away — rather than as a claim.
struct Carryover: Codable, Identifiable, Hashable {
    /// Where the studied item came from. Ordered by how much it took to
    /// produce: a card from a past talk is a bigger win than applying a
    /// suggestion still fresh on screen.
    enum Source: String, Codable {
        case drillCard            // a correction card minted in an earlier talk
        case curriculumItem       // study material from a Watch book
        case studyingExpression   // a phrase they'd bookmarked in their notebook
        case suggestion           // a suggestion given earlier in THIS call
        case studyingWord         // a word they'd collected into their notebook
    }

    var id: UUID = UUID()
    var sessionId: UUID
    var source: Source
    /// The studied item, verbatim as it was being practiced.
    var item: String
    /// The learner's own words that prove it — always from a user turn.
    var quote: String
    /// Turn `quote` came from, so the receipt can play their own recording.
    var turnId: UUID
    /// The `DrillCard` (for `.drillCard`) or the suggestion's originating
    /// user turn (for `.suggestion`).
    var sourceId: UUID?
    var detectedAt: Date
}

extension Carryover.Source {
    /// Where the learner met this item, in their words. Lives on the type so
    /// the wrap-up and Progress can't drift into describing the same source
    /// two different ways. (Plain strings — no UI framework involved; the
    /// icon is just an SF Symbol name.)
    var label: String {
        switch self {
        case .drillCard:          return "Review cards"
        case .curriculumItem:     return "Your books"
        case .studyingExpression: return "Expression notebook"
        case .studyingWord:       return "Word notebook"
        case .suggestion:         return "In-call suggestions"
        }
    }

    var icon: String {
        switch self {
        case .drillCard:          return "rectangle.stack"
        case .curriculumItem:     return "book"
        case .studyingExpression: return "bookmark"
        case .studyingWord:       return "text.book.closed"
        case .suggestion:         return "lightbulb"
        }
    }

    /// Fixed display order — heaviest evidence first, so the breakdown reads
    /// the same everywhere and never reshuffles between reloads.
    static let displayOrder: [Carryover.Source] = [
        .drillCard, .curriculumItem, .studyingExpression, .studyingWord, .suggestion,
    ]
}

/// One concrete grammar slip from this session: the user's sentence verbatim,
/// the grammatically fixed version, and the grammar point involved. Distinct
/// from `PhraseFeedback`, which is about more NATURAL phrasing — this is
/// strictly about incorrect grammar.
struct GrammarIssue: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var quote: String       // what the user actually said
    var correction: String  // same sentence, grammar fixed — nothing restyled
    var note: String        // the grammar point, e.g. "missing article"
}

extension SessionSummary {
    enum CodingKeys: String, CodingKey {
        case phrasesUsed, newPatternsDetected, suggestedDrills, overallNote
        case scorecard, newWordsUsed, expressionsUsed, weakVocabAreas
        case grammarIssues, carryovers
    }

    // Custom decode so sessions saved BEFORE newWordsUsed/expressionsUsed
    // existed still load — Swift's synthesized Decodable ignores default
    // values and throws keyNotFound on any missing key. decodeIfPresent keeps
    // old data readable; encode(to:) is still synthesized from these keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phrasesUsed = try c.decodeIfPresent([PhraseFeedback].self, forKey: .phrasesUsed) ?? []
        newPatternsDetected = try c.decodeIfPresent([LearnerPattern].self, forKey: .newPatternsDetected) ?? []
        suggestedDrills = try c.decodeIfPresent([String].self, forKey: .suggestedDrills) ?? []
        overallNote = try c.decodeIfPresent(String.self, forKey: .overallNote) ?? ""
        scorecard = try c.decodeIfPresent(SessionScorecard.self, forKey: .scorecard)
        newWordsUsed = try c.decodeIfPresent([String].self, forKey: .newWordsUsed) ?? []
        expressionsUsed = try c.decodeIfPresent([String].self, forKey: .expressionsUsed) ?? []
        weakVocabAreas = try c.decodeIfPresent([String].self, forKey: .weakVocabAreas) ?? []
        grammarIssues = try c.decodeIfPresent([GrammarIssue].self, forKey: .grammarIssues) ?? []
        carryovers = try c.decodeIfPresent([Carryover].self, forKey: .carryovers) ?? []
    }
}

// MARK: - Session Scorecard ("nutrition label")

/// Multi-axis snapshot of one session, rendered as the post-session "nutrition"
/// card. Four axes are judged from the conversation itself; `pronunciation` is
/// gated on shadow-practice data and surfaces a friendly "needs more data"
/// placeholder until the learner has done some shadow drills.
struct SessionScorecard: Codable, Hashable {
    var vocabulary: AxisScore
    var grammar: AxisScore
    var expressiveness: AxisScore
    var fluency: AxisScore
    var pronunciation: AxisScore?     // nil until shadow drills exist
    var topLine: String               // 1-sentence holistic note
    var cefrLevel: String?            // AI's holistic CEFR read of the whole talk (a1…c2)
}

extension SessionScorecard {
    /// Mean of the axis scores (+ pronunciation when present) — the single
    /// headline number for a talk, shared by the detail header and the Talk
    /// book card.
    var overall: Int {
        var s = [vocabulary.score, grammar.score, expressiveness.score, fluency.score]
        if let p = pronunciation { s.append(p.score) }
        return s.isEmpty ? 0 : s.reduce(0, +) / s.count
    }
}

struct AxisScore: Codable, Hashable {
    var score: Int       // 0–100
    var note: String     // one short sentence
}

// MARK: - Weekly Report
//
// The per-session 4-axis scorecard above is statistically noisy at small N
// (one 5-minute conversation is a poor sample for grading vocabulary, and
// the grammar score is the LLM grading its own suggestion count — circular).
// Instead of pretending each session deserves a grade, we now defer
// analysis until we have enough sessions to say something true, then
// produce a *trend* report comparing this week vs. last.

/// One periodic learning report. Generated when (a) lifetime sessions ≥ 5
/// for the first one, then (b) ≥7 days + ≥3 new sessions thereafter. Cached
/// to disk by `WeeklyReportStore`. Surfaced from the Practice tab.
struct WeeklyReport: Codable, Identifiable {
    let id: UUID
    let periodStart: Date            // first session in the window
    let periodEnd: Date              // last session in the window
    let sessionCount: Int
    let targetLanguage: String

    /// Phrases / chunks the user produced for the first time in this window,
    /// judged against the corpus of every prior session's transcript. Single
    /// words don't qualify — only 2+ word collocations.
    var newExpressions: [LearnedExpression]

    /// Same fluent-alternative came up multiple times this window. These are
    /// the patterns to actively drill — the user is still defaulting to a
    /// less native phrasing.
    var repeatedMistakes: [RepeatedMistake]

    /// Phrases the user *didn't* produce but would have fit naturally given
    /// the topics they discussed. Forward-looking vocabulary to add.
    var suggestedExpressions: [SuggestedExpression]

    /// 1–2 sentence trend vs. the previous report (nil on the very first one).
    var summary: String

    /// Pooled CEFR estimate over the whole window's user speech — a far
    /// larger sample than any single session, so this (when present) is the
    /// preferred source for the Progress tab's "Estimated level". Optional so
    /// reports generated before this field decode unchanged.
    var cefrLevel: String?

    /// The judge's own 2-3 sentence justification of `cefrLevel`, citing the
    /// specific evidence (pace band, slip density, per-talk reads). Shown in
    /// "How this is assessed" so the level is never an unexplainable verdict.
    var levelRationale: String? = nil

    /// Verbatim snapshot of the measured-delivery evidence block the judge
    /// received — kept for accountability/debugging, so a surprising verdict
    /// can be checked against what the judge actually saw.
    var levelEvidence: String? = nil

    var generatedAt: Date
}

struct LearnedExpression: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var phrase: String         // "let me get back to you"
    var sampleSentence: String // the user's actual utterance containing it
}

struct RepeatedMistake: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var userSaid: String
    var fluentAlternative: String
    var count: Int             // occurrences this window
    var note: String           // one sentence on what to focus on
}

struct SuggestedExpression: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var phrase: String
    var whenToUse: String      // short context cue
    var example: String        // example sentence using it
}

struct PhraseFeedback: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var userSaid: String
    var fluentAlternative: String
    var reason: String
}

// MARK: - User Persona

/// Rich personal context the avatar uses to ground every conversation.
/// The more of this is filled in, the more the avatar's speech sounds
/// like the user actually lives this life — not generic textbook language.
/// Drives conversation system prompts, summary grading, and (Phase B)
/// simulation-mode scenario generation.
struct UserPersona: Codable {
    var displayName: String           // "Eunggyu"
    var city: String                  // "Munich"
    var country: String               // "Germany"
    var lengthOfStay: String          // "3 years" — optional free text
    var occupation: String            // free text — "Solo founder of an AI app for parents"
    var household: String             // free text — "Wife and 4yo daughter at Kita"
    var interests: [String]           // ["AI", "parenting", "language learning"]
    var situations: [String]          // target-language moments — ["Kita parent small talk", "client calls"]
    var freeNotes: String             // catch-all
    var updatedAt: Date
    /// What the fluent self has picked up about the user IN their calls —
    /// the other half of this record. Everything above is the user writing
    /// about themselves; this is the person on the other end of the phone
    /// remembering what they were told. Same file, same editor, so there is
    /// one profile rather than two.
    var learnedNotes: [PersonaNote] = []
    /// When the fluent self first properly met the user — the free talk that
    /// was spent getting to know them. Nil until that call has happened, and
    /// that is what makes the first call read as a first call.
    var metAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case displayName, city, country, lengthOfStay, occupation, household,
             interests, freeNotes, updatedAt, learnedNotes, metAt
        // Personas on disk predate multi-language prep — keep the legacy key.
        case situations = "englishSituations"
    }

    static let empty = UserPersona(
        displayName: "",
        city: "",
        country: "",
        lengthOfStay: "",
        occupation: "",
        household: "",
        interests: [],
        situations: [],
        freeNotes: "",
        updatedAt: Date()
    )

    /// True iff the user has supplied at least their name + city + one of
    /// {occupation, household, interests, situations}. Used as the "good
    /// enough to skip onboarding" bar.
    var isMinimallyComplete: Bool {
        let coreFilled = !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
        let contextFilled = !occupation.trimmingCharacters(in: .whitespaces).isEmpty
            || !household.trimmingCharacters(in: .whitespaces).isEmpty
            || !interests.isEmpty
            || !situations.isEmpty
        return coreFilled && contextFilled
    }
}

/// One thing the fluent self learned about the user during a talk, kept so the
/// next call starts from what it was told rather than from nothing.
///
/// NATIVE language: the learner reads these in their own profile, and they go
/// back into the conversation prompt as context, never as material.
struct PersonaNote: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    /// The talk it came out of — provenance, so a note is never orphaned.
    var sessionId: UUID?
    var learnedAt: Date

    /// Comparison form for "do we already know this?" — the model rewrites
    /// the same fact with different punctuation and spacing every session.
    var dedupeKey: String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension UserPersona {
    /// Decoded LENIENTLY, and it has to be: a persona written by an earlier
    /// build has no `learnedNotes` key, and the synthesized decoder throws on
    /// a missing key for a non-optional field. Here that throw means
    /// `PersonaStore.load()` returns nil — which walks an existing user back
    /// into first-run onboarding and loses their profile. Every field falls
    /// back instead, so adding the next one can't do that either.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        displayName = value(.displayName, "")
        city = value(.city, "")
        country = value(.country, "")
        lengthOfStay = value(.lengthOfStay, "")
        occupation = value(.occupation, "")
        household = value(.household, "")
        interests = value(.interests, [])
        situations = value(.situations, [])
        freeNotes = value(.freeNotes, "")
        updatedAt = value(.updatedAt, Date())
        learnedNotes = value(.learnedNotes, [])
        metAt = (try? c.decodeIfPresent(Date.self, forKey: .metAt)) ?? nil
    }

    /// Everything already on file about this person, as plain lines. Handed
    /// to the summary call as the "don't hand this back as a discovery" list —
    /// without it the same fact is re-learned every session and the profile
    /// fills with paraphrases of one sentence.
    var knownFacts: [String] {
        var out: [String] = []
        let place = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { out.append("Lives in \(place)") }
        if !occupation.isEmpty { out.append(occupation) }
        if !household.isEmpty { out.append(household) }
        if !interests.isEmpty { out.append("Interested in \(interests.joined(separator: ", "))") }
        if !freeNotes.isEmpty { out.append(freeNotes) }
        out.append(contentsOf: learnedNotes.map(\.text))
        return out
    }

    /// Append what a talk taught, dropping anything already on file. Newest
    /// last; the oldest fall off past `limit` so the conversation prompt this
    /// feeds can't grow without bound.
    mutating func absorb(notes: [PersonaNote], limit: Int = 40) {
        var seen = Set(learnedNotes.map(\.dedupeKey))
        for note in notes where !note.dedupeKey.isEmpty && !seen.contains(note.dedupeKey) {
            seen.insert(note.dedupeKey)
            learnedNotes.append(note)
        }
        if learnedNotes.count > limit {
            learnedNotes.removeFirst(learnedNotes.count - limit)
        }
    }
}

// MARK: - Watch Dialogue (saved Watch-mode dialogues for replay)

/// A generated Watch-mode dialogue, persisted so the user can replay later
/// instead of regenerating (which costs another Gemini call + first-time TTS).
/// Audio for each turn is cached separately via `PhraseAudioStore` and gets
/// looked up by (text, voiceId) on replay — so replays are effectively free.
struct WatchDialogue: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var counterpartId: UUID
    var scenarioTitle: String
    var scenarioBlurb: String
    /// Dialogue-specific title from the engine ("Boram's moving news") so
    /// repeated runs of the same scenario stay tellable apart in lists.
    /// Optional for rows persisted before this existed.
    var title: String?
    var turns: [DialogueEngineTurn]
    var createdAt: Date = Date()
    /// Who the user talked WITH — a counterpart name, or a scenario role like
    /// "the Doctor". Lets the Watch list show + replay the dialogue even when
    /// there's no saved Counterpart (scenario watches), and survives counterpart
    /// deletion. Optional for rows persisted before this existed.
    var speakerName: String?
    /// ElevenLabs voice for the non-user turns, stored so replay works without
    /// the Counterpart object.
    var voicePresetId: String?

    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return scenarioTitle
    }
}

/// Storable mirror of `DialogueEngine.Turn` so we don't have to expose the
/// engine's nested types as the on-disk schema. Speaker is stored as raw
/// string for forward compat.
struct DialogueEngineTurn: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var speaker: String      // "user" or "counterpart"
    var text: String
}

// MARK: - Counterpart (the OTHER character in Watch mode)

/// A person from the user's actual life — best friend, Kita parent, manager.
/// In Watch mode, the user's voice clone has a conversation WITH this
/// counterpart (voiced by an ElevenLabs preset). Specificity here is what
/// makes the dialogues feel real instead of generic.
struct Counterpart: Codable, Identifiable, Hashable {
    var id: UUID = UUID()

    // Who
    var name: String                       // "Boram", "Sarah", "Frau Schmidt"
    var relationship: String               // "Best friend" / "Kita parent" / "Manager"

    // About them
    var location: String = ""              // "Lives in Seoul, recently moved from Tokyo"

    // Your history together
    var howWeMet: String = ""              // "College roommate, 8 years"
    /// Shared context, recurring topics, inside jokes. Was the original single
    /// catch-all field — kept under the same name for migration but relabelled
    /// in the form as "Shared context".
    var background: String

    // Communication
    var conversationStyle: String          // "direct, jokes a lot" / "formal, careful"
    var commonTopics: String = ""          // "Tech, parenting, recent travel"

    // Voice
    var voicePresetId: String              // ElevenLabs voice id (see VoicePreset.catalog)

    // Catch-all
    var freeNotes: String = ""             // anything that doesn't fit above

    // Find people (public-persona pool)
    /// Set when this person came from the shared `public_personas` pool (a
    /// stranger "met" via Find people). nil = a person the user made
    /// themselves. Remote personas are hidden from Watch's stories row —
    /// they live in the Find sheet's "People you've met" section instead.
    var remoteId: String? = nil
    /// The self-introduction the persona's author wrote, verbatim, in the
    /// target language. Kept alongside the parsed fields because it IS the
    /// conversational substance — prompts quote it directly.
    var intro: String = ""
    /// What KIND of remote persona this is: "user" (a real learner who
    /// published an intro) or "character" (an invented seed persona). nil for
    /// people the user made. Find people's tabs group on this, so a person
    /// stays in the tab they were met in.
    var personaKind: String? = nil

    /// Persona-grounded scenario library specific to this counterpart, KEYED
    /// BY TARGET LANGUAGE. Fed by `TopicEngine.suggestForCounterpart` and
    /// cached so opening Watch for the same person doesn't re-bill Gemini
    /// every time. Empty until first WatchSetupSheet open.
    ///
    /// The person stays global — nobody should re-enter their own life once
    /// per language — but these ideas ARE written in the language being
    /// practiced, so they can't be shared across languages. Keying them
    /// (rather than clearing the cache on every switch) keeps both pools
    /// alive, so moving back and forth never re-bills.
    ///
    /// Rows written before multi-language hold a bare array under the old
    /// `savedScenarios` key; they decode into the "en" bucket, which is
    /// where they belong — the practice target was fixed to English then.
    var scenariosByLanguage: [String: [SuggestedTopic]] = [:]

    func savedScenarios(in language: String) -> [SuggestedTopic] {
        scenariosByLanguage[language] ?? []
    }

    mutating func setSavedScenarios(_ list: [SuggestedTopic], in language: String) {
        scenariosByLanguage[language] = list
    }

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    static let empty = Counterpart(
        name: "",
        relationship: "",
        background: "",
        conversationStyle: "",
        voicePresetId: VoicePreset.catalog.first!.id
    )

    var isMinimallyComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !relationship.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension Counterpart {
    enum CodingKeys: String, CodingKey {
        case id, name, relationship, location, howWeMet, background
        case conversationStyle, commonTopics, voicePresetId, freeNotes
        case remoteId, intro, personaKind
        case scenariosByLanguage, createdAt, updatedAt
        /// Pre-multi-language rows: one flat array, always English.
        case savedScenarios
    }

    /// Hand-written so rows saved before the per-language split still load —
    /// their flat `savedScenarios` array becomes the "en" bucket, which is
    /// where it belongs (the practice target was fixed to English then).
    /// Every optional-with-default field is decoded leniently for the same
    /// reason: this store predates several of them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        relationship = try c.decode(String.self, forKey: .relationship)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        howWeMet = try c.decodeIfPresent(String.self, forKey: .howWeMet) ?? ""
        background = try c.decode(String.self, forKey: .background)
        conversationStyle = try c.decode(String.self, forKey: .conversationStyle)
        commonTopics = try c.decodeIfPresent(String.self, forKey: .commonTopics) ?? ""
        voicePresetId = try c.decode(String.self, forKey: .voicePresetId)
        freeNotes = try c.decodeIfPresent(String.self, forKey: .freeNotes) ?? ""
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        personaKind = try c.decodeIfPresent(String.self, forKey: .personaKind)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        if let keyed = try c.decodeIfPresent([String: [SuggestedTopic]].self,
                                             forKey: .scenariosByLanguage) {
            scenariosByLanguage = keyed
        } else if let legacy = try c.decodeIfPresent([SuggestedTopic].self,
                                                     forKey: .savedScenarios),
                  !legacy.isEmpty {
            scenariosByLanguage = ["en": legacy]
        } else {
            scenariosByLanguage = [:]
        }
    }

    /// Explicit because `CodingKeys` carries a legacy case with no property —
    /// the synthesized encoder can't be used. `savedScenarios` is read-only
    /// history: never written back.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(relationship, forKey: .relationship)
        try c.encode(location, forKey: .location)
        try c.encode(howWeMet, forKey: .howWeMet)
        try c.encode(background, forKey: .background)
        try c.encode(conversationStyle, forKey: .conversationStyle)
        try c.encode(commonTopics, forKey: .commonTopics)
        try c.encode(voicePresetId, forKey: .voicePresetId)
        try c.encode(freeNotes, forKey: .freeNotes)
        // Load-bearing: `remoteId` is what marks a person as someone from the
        // Find people pool rather than one the user made. Dropping it here
        // (as an earlier version did) silently promoted every stranger to
        // "your own person" on the next read.
        try c.encodeIfPresent(remoteId, forKey: .remoteId)
        try c.encode(intro, forKey: .intro)
        try c.encodeIfPresent(personaKind, forKey: .personaKind)
        try c.encode(scenariosByLanguage, forKey: .scenariosByLanguage)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Curated subset of ElevenLabs default voices (all stable, well-known IDs)
/// used for counterpart voices. We deliberately keep the list small so the
/// user can pick quickly instead of scrolling through hundreds.
struct VoicePreset: Hashable, Identifiable {
    let id: String           // ElevenLabs voice id
    let displayName: String
    let gender: String
    let accent: String
    let description: String

    // Four voices, hand-picked from the ElevenLabs library (2026-07): one
    // female + one male per accent, chosen for conversation. All four IDs
    // are verified synthesizable with the production API key. The two
    // British voices are library (shared) voices whose upstream names the
    // voices API doesn't expose — display names for those are ours. Old
    // stored IDs from the retired 8-voice premade list keep synthesizing
    // fine but fall back to catalog[0] for display.
    static let catalog: [VoicePreset] = [
        VoicePreset(id: "NDTYOmYEjbDIVCKB35i3",
                    displayName: "Paige", gender: "Female", accent: "American",
                    description: "Engaging, natural"),
        VoicePreset(id: "UgBBYS2sOqTuMpoF3BR0",
                    displayName: "Mark", gender: "Male", accent: "American",
                    description: "Natural, conversational"),
        VoicePreset(id: "FF59babHL8N8gfTgtBMT",
                    displayName: "Emma", gender: "Female", accent: "British",
                    description: "Clear, friendly"),
        VoicePreset(id: "L0Dsvb3SLTyegXwtm47J",
                    displayName: "James", gender: "Male", accent: "British",
                    description: "Warm, easygoing"),
    ]

    static func by(id: String) -> VoicePreset {
        catalog.first(where: { $0.id == id }) ?? catalog[0]
    }

    /// UserDefaults key for the fallback voice of Watch scenes that have no
    /// linked persona ("Make your own situation", likely-situation leaves).
    /// Personas keep their own per-person `voicePresetId`; this only covers
    /// the synthetic counterpart. Set in Me → Voice → Scene partner voice.
    static let sceneDefaultKey = "futurevoice.defaultSceneVoice"

    static var sceneDefault: VoicePreset {
        by(id: UserDefaults.standard.string(forKey: sceneDefaultKey) ?? catalog[0].id)
    }
}

/// The four BUILT-IN characters — the app's own contribution to the same
/// "가상인물" pool the Find-people characters live in. Built 1:1 on the
/// preset voices (the person's id is the voice preset id), always available
/// without a network, and deliberately light: unlike the curated characters,
/// who arrive mid-problem, these exist to PLAY whatever role a scenario
/// implies, so their identity is personality only, never a job.
///
/// Picking one in the composer materializes an ordinary `Counterpart`
/// (`asCounterpart`) with `personaKind: "character"` and a `builtin:` remote
/// id — from there the whole people machinery (scenes, calls, books, "People
/// you've met") treats them exactly like a character met in Find people.
struct StockPerson: Identifiable, Hashable {
    let voice: VoicePreset
    /// Stable local `Counterpart.id` — hardcoded so a builtin materialized
    /// today matches one materialized last month (sessions link on it).
    let localId: UUID
    /// One-line character for the picker card — UI, resolved in the app
    /// language at access time (see `catalog` being computed).
    let vibe: String
    /// Identity blurb injected into scene prompts. Machine-consumed, so it
    /// stays English — and deliberately job-free: the situation casts their
    /// role (barista, landlord, interviewer); this only says who plays it.
    let identity: String

    var id: String { voice.id }
    var name: String { voice.displayName }
    /// The `Counterpart.remoteId` marker. Not a server row — the prefix is
    /// what keeps builtins out of "your own people" surfaces (those filter on
    /// `remoteId == nil`) while grouping them with the character pool.
    var remoteKey: String { "builtin:" + voice.id }

    /// Computed, not cached, so `vibe` re-resolves when the app language
    /// changes mid-session. Order mirrors `VoicePreset.catalog`.
    static var catalog: [StockPerson] {
        let v = VoicePreset.catalog
        return [
            StockPerson(voice: v[0],
                        localId: UUID(uuidString: "7A1C89E4-0D2B-4A54-9B6F-2E8C11D0A001")!,
                        vibe: explain("Bright and upbeat"),
                        identity: "Paige — American, twenties; bright and upbeat, quick to encourage, keeps the conversation moving"),
            StockPerson(voice: v[1],
                        localId: UUID(uuidString: "7A1C89E4-0D2B-4A54-9B6F-2E8C11D0A002")!,
                        vibe: explain("Easygoing, a little dry"),
                        identity: "Mark — American, thirties; easygoing and direct, with a dry sense of humor"),
            StockPerson(voice: v[2],
                        localId: UUID(uuidString: "7A1C89E4-0D2B-4A54-9B6F-2E8C11D0A003")!,
                        vibe: explain("Warm and chatty"),
                        identity: "Emma — British, twenties; warm and chatty, asks friendly follow-up questions"),
            StockPerson(voice: v[3],
                        localId: UUID(uuidString: "7A1C89E4-0D2B-4A54-9B6F-2E8C11D0A004")!,
                        vibe: explain("Calm, gently witty"),
                        identity: "James — British, forties; calm and courteous, unhurried, gently witty"),
        ]
    }

    /// Resolve a scenario's stored voice id (nil = the Me-tab default) to its
    /// person. Retired legacy voice ids resolve to the first person, matching
    /// `VoicePreset.by`'s display fallback.
    static func by(voiceId: String?) -> StockPerson {
        let preset = VoicePreset.by(id: voiceId ?? VoicePreset.sceneDefault.id)
        return catalog.first { $0.id == preset.id } ?? catalog[0]
    }

    /// This person as an ordinary `Counterpart`, reusing the already-saved
    /// row when they've been used before (books and sessions link on the
    /// local id, so it must stay stable — and it does, see `localId`).
    func asCounterpart(existing: [Counterpart]) -> Counterpart {
        if let known = existing.first(where: { $0.remoteId == remoteKey || $0.id == localId }) {
            return known
        }
        var c = Counterpart(
            id: localId,
            name: name,
            relationship: "",
            background: identity,
            conversationStyle: "",
            voicePresetId: voice.id
        )
        c.remoteId = remoteKey
        c.intro = identity
        c.personaKind = PublicPersonaService.Group.character.rawValue
        return c
    }
}

// MARK: - Scenario (user-built practice scenario, saved as a library)

/// A reusable Talk-mode practice scenario the user constructed once and can
/// re-enter with a single tap. Most learners only really practice 3–5
/// recurring situations (Kita pickup, work meeting, doctor visit, etc.) — a
/// library beats a fresh wizard every time AND beats stale auto-suggestions.
struct Scenario: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var environment: String     // "Cafe / restaurant" or custom
    var role: String            // "Doctor / nurse" or custom — the role the avatar plays
    var notes: String           // optional free-text context
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    /// Optional link to one of the user's own personas (Counterpart). When
    /// set, `role` holds that persona's relationship, and watching this
    /// scenario uses the persona's real voice/identity instead of a generic
    /// preset. Optional so scenarios saved before this decode unchanged.
    var counterpartId: UUID? = nil
    /// Voice for the scene's counterpart when NO persona is linked — picked
    /// in the composer's "Talking with" section. nil = the user's default
    /// scene voice (`VoicePreset.sceneDefault`). Optional so scenarios saved
    /// before this decode unchanged.
    var voicePresetId: String? = nil
    /// The scenario's course content — words, expressions, and shadow lines
    /// to master. Generated once on first open of the scenario page and
    /// persisted here. nil for scenarios that haven't been opened yet
    /// (and for all rows saved before this existed).
    var curriculum: ScenarioCurriculum? = nil
    /// Set when the user shelves a mastered (or abandoned) scenario. Archived
    /// scenarios drop out of the main grid into the Archive section.
    var archivedAt: Date? = nil
    /// Opening lines for talks on this scenario — a small pool generated in
    /// ONE Gemini call on the first talk, then rotated (`openerCursor`) so
    /// every later talk starts instantly and free (and each line's TTS hits
    /// the phrase cache after its first play). Optional so old rows decode.
    var openers: [String]? = nil
    var openerCursor: Int? = nil
    /// True for topic books — scenarios born from a news story (Home's Watch
    /// verb on a News ingredient) rather than a built situation. Same
    /// curriculum mechanics; drives Practice's "Topics" shelf and a
    /// discussion-flavored scene prompt. Optional so old rows decode.
    var isTopic: Bool? = nil
    /// The category bucket this scenario was built/filed under (composer:
    /// "Cafe", "Interview", …) + its SF Symbol. Shown as a tag on the card.
    /// Optional so scenarios saved before this decode unchanged.
    var category: String? = nil
    var categoryIcon: String? = nil
    /// A short, clean summary of the situation for the card — NOT the raw
    /// prompt the user typed (which drives the conversation via `environment`).
    var summary: String? = nil
    /// True for the scene behind a Find-people person's Watch. A `Scenario` is
    /// the only container the scene machinery has, so meeting someone mints
    /// one — but it isn't a situation the user BUILT, and listing it under
    /// "Your scenarios" put a conversation with a person in among the
    /// situations they wrote themselves. The book still lives in Practice,
    /// where reviewing what came out of it belongs. Optional so old rows
    /// decode unchanged.
    var isMeeting: Bool? = nil

    /// Rows minted before the flag existed carry only the category, so read
    /// both — otherwise the meetings already on disk stay in the list this
    /// flag was added to get them out of.
    var isMeetingScene: Bool { isMeeting == true || category == "Meeting" }

    var isArchived: Bool { archivedAt != nil }

    /// What the card shows: the tidy summary if we have one, else the
    /// environment text (older scenarios, or ones with no summary yet).
    var cardTitle: String {
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        return environment
    }

    /// True once every curriculum item is mastered — the "book is finished"
    /// state that unlocks archiving with a sense of completion.
    var isMastered: Bool {
        guard let c = curriculum, c.totalCount > 0 else { return false }
        return c.masteredCount == c.totalCount
    }

    /// Human-readable title shown in the list. Kept simple so the user can
    /// scan a long list quickly. Free-described situations (Watch composer,
    /// no person) have no role — the description IS the title.
    var displayTitle: String {
        let r = role.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? environment : "\(environment) · with \(r)"
    }

    /// Structured prompt blurb the conversation system prompt parses to put
    /// the avatar into character. Same `environment=… | role=… | notes=…`
    /// format the builder previously wrote directly into topicBlurb.
    var promptBlurb: String {
        var parts = ["environment=\(environment)"]
        let r = role.trimmingCharacters(in: .whitespaces)
        if !r.isEmpty { parts.append("role=\(r)") }
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("notes=\(notes)")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Scenario Curriculum (the scenario's "book" content)

/// The course content of one scenario: the words, expressions, and shadow
/// lines a learner should be able to produce in that situation. A scenario
/// is a curriculum, not a replay shortcut — the goal is to master every item,
/// then archive the book.
///
/// Mastery is deterministic, never LLM-judged, and rides the app's existing
/// vocab tracking rather than a parallel system:
///   - words → the word is in `VocabStore` (used in a real talk, or marked
///     "I know it" on its word card)
///   - expressions → in the VocabStore expression pool (used in a real talk
///     or marked "I know it" on the card), or said under this scenario
///   - shadow lines → a saved shadow attempt on the line scored ≥ threshold
struct ScenarioCurriculum: Codable, Hashable {
    struct Item: Codable, Identifiable, Hashable {
        /// Stable id. Doubles as the synthetic Turn.id when the item is
        /// practiced aloud, so shadow attempts + cached TTS audio stay
        /// attached across opens.
        var id: UUID = UUID()
        var text: String
        /// One-line usage hint ("when the nurse asks about symptoms").
        /// Default empty string so items saved before this field was added still decode.
        var note: String = ""
        /// For words/expressions: a natural first-person sentence using the
        /// item in this scenario's context. nil for shadow lines (text IS
        /// the sentence) and for curricula generated before this existed.
        var example: String? = nil
        var masteredAt: Date? = nil

        /// The line practiced aloud for this item — the example in context
        /// when there is one, the bare text otherwise.
        var spokenText: String { example ?? text }
    }

    var words: [Item] = []
    var expressions: [Item] = []
    var shadowLines: [Item] = []
    /// The scene this whole curriculum is extracted from — ONE dialogue,
    /// generated with the words/expressions in the same Gemini call so the
    /// study list and what you watch are the same material. Replaying it is
    /// free (audio content-cache); there is no "new watch" inside a book.
    /// Optional so curricula persisted before this decode unchanged.
    var dialogueTitle: String? = nil
    var dialogue: [DialogueEngineTurn]? = nil
    var generatedAt: Date = Date()

    /// A shadow attempt at or above this score masters the line.
    static let shadowMasteryScore = 80

    var totalCount: Int { words.count + expressions.count + shadowLines.count }
    var masteredCount: Int {
        [words, expressions, shadowLines].flatMap { $0 }
            .filter { $0.masteredAt != nil }.count
    }
    var progress: Double {
        totalCount == 0 ? 0 : Double(masteredCount) / Double(totalCount)
    }

    /// Fold a freshly generated take into this book: the new scene replaces
    /// the playing dialogue, while study items accumulate — new ones append
    /// (deduped by text), existing ones keep their ids, shadow attempts, and
    /// mastery. A scenario is a reusable template; each watch writes a new
    /// take, but the book keeps everything the takes have taught.
    mutating func absorb(_ fresh: ScenarioCurriculum) {
        func merged(_ old: [Item], _ new: [Item]) -> [Item] {
            var seen = Set(old.map { $0.text.lowercased() })
            return old + new.filter { seen.insert($0.text.lowercased()).inserted }
        }
        words = merged(words, fresh.words)
        expressions = merged(expressions, fresh.expressions)
        shadowLines = merged(shadowLines, fresh.shadowLines)
        dialogueTitle = fresh.dialogueTitle
        dialogue = fresh.dialogue
        generatedAt = fresh.generatedAt
    }
}

// MARK: - Suggested Topic

/// One persona-grounded conversation scenario produced by `TopicEngine`.
/// Title is what the user sees in the topic picker; blurb is a one-line
/// elaboration that doubles as the system-prompt context for the avatar.
struct SuggestedTopic: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var blurb: String
    /// The interest/category this story was matched from (news topics only).
    /// Optional so persona scenarios and rows saved before this decode fine.
    var category: String? = nil
    /// Grounded facts collected ONCE at platform pool generation (news topics
    /// only) — seeds the conversation's `newsFacts` so a talk isn't limited
    /// to the one-line blurb. Optional so older cached pools decode fine.
    var facts: [String]? = nil
}

// MARK: - Saved Line (user's personal shadow archive)

/// A line the user explicitly bookmarked for repeated shadow practice.
/// `id` is the source `Turn.id`, so saved attempts (`ShadowAttempt.turnId`)
/// stay attached when the line is reopened later.
struct SavedLine: Codable, Identifiable, Hashable {
    var id: UUID                  // = source Turn.id
    var text: String
    var source: String            // topic / counterpart name; may be empty
    var savedAt: Date = Date()
}

// MARK: - Shadow Attempt (persisted shadow-practice attempt)

/// One saved shadow-practice attempt — score, your transcript, the
/// Gemini-judged bullets, and a filename pointing at the WAV recording
/// (`Documents/Recordings/`). Lets the user revisit past attempts and play
/// back their own voice.
struct ShadowAttempt: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var turnId: UUID               // the target line (Turn.id) this attempt was for
    var targetText: String         // captured at attempt time for display
    var learnerTranscript: String  // STT of the user
    var recordingFilename: String? // file in Documents/Recordings/ (nil if recording failed)
    var matchScore: Int            // 0–100
    var rhythmScore: Int?          // 0–100 word-onset timing (nil = not measurable)
    var pronunciation: String
    var pacing: String
    var fix: String
    var createdAt: Date = Date()
}

// MARK: - Shadow Feedback

/// Result of comparing a learner's shadow-attempt against a fluent-self line.
/// Returned by `ShadowEngine` via Gemini; rendered as three short bullets in
/// `ShadowDrillView`.
struct ShadowFeedback: Codable, Hashable {
    var pronunciation: String   // one line on accuracy / pronunciation match
    var pacing: String          // one line on intonation + speed delta
    var fix: String             // one concrete thing to try next attempt
    var matchScore: Int         // 0–100 rough overall match
}

// MARK: - Drill Card (SRS)

/// One Leitner-style spaced-repetition card. Drill cards are derived from
/// per-turn suggestions and post-session summaries — they represent specific
/// "say this instead" moments the learner should revisit on a schedule.
struct DrillCard: Codable, Identifiable {
    var id: UUID = UUID()
    var sourcePhrase: String          // what the user originally said (may be empty)
    var targetPhrase: String          // the more natural / correct version
    var reason: String                // short note explaining the swap
    var createdAt: Date
    var lastReviewedAt: Date?
    var nextReviewAt: Date            // Leitner schedule — when this is due
    var box: Int                      // 0…5 Leitner box
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var sourceSessionId: UUID?
    /// User turn this card was minted from. Lets the drill card play back the
    /// user's OWN recording (TurnAudioStore) next to the transcript — the
    /// transcript is STT output and sometimes wrong, so hearing what they
    /// actually said is the ground truth. nil for cards without a source
    /// utterance (suggested drills, Watch "Save phrase", pre-existing cards).
    var sourceTurnId: UUID?
    var enrichment: DrillCardEnrichment?  // on-demand, persisted once fetched
}

/// Richer learning content layered on top of a thin DrillCard so the user
/// can really internalize a pattern instead of memorizing one swap. Generated
/// lazily via `DrillEnrichmentEngine` and persisted back into the card.
struct DrillCardEnrichment: Codable, Hashable {
    struct Example: Codable, Hashable {
        var situation: String   // 1-line context — "Bumping into a Kita parent"
        var sentence: String    // the line using the target phrase, in target language
    }
    struct Variant: Codable, Hashable {
        var phrase: String      // alternate way to express the same idea
        var note: String        // brief note on when it fits
    }
    var examples: [Example]
    var variants: [Variant]
    var memoryHook: String      // 1-line trigger to help recall when to reach for it
    var generatedAt: Date
}
