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

    static func patternKey(_ p: LearnerPattern) -> String {
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
    /// A fluent-self line the learner talked over moments after it began
    /// (realtime path, 2026-09-29) — the gateway took a pause for the end of
    /// their turn and cut in, and they carried on with the SAME sentence. The
    /// line was written (it is on screen) but not really heard, and the
    /// learner's words on either side of it are one utterance. Say it again
    /// reads them as one line (`SayItAgainScript.mergingCutIns`). Encoded
    /// only when true, so every turn already on disk keeps its bytes and its
    /// sync fingerprint.
    var talkedOver: Bool = false
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
        case suggestion, fluency, excludedFromScoring, talkedOver
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(audioURL, forKey: .audioURL)
        try c.encode(transcript, forKey: .transcript)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(suggestion, forKey: .suggestion)
        try c.encodeIfPresent(fluency, forKey: .fluency)
        try c.encode(excludedFromScoring, forKey: .excludedFromScoring)
        if talkedOver { try c.encode(true, forKey: .talkedOver) }
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
        talkedOver = try c.decodeIfPresent(Bool.self, forKey: .talkedOver) ?? false
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
    /// False when the span was never observed — a character-count estimate
    /// (`ShadowDrillView.estimatedTimings`) or a word `LocalAlignment.fill`
    /// spread across the gap between two anchored neighbours. Karaoke may
    /// light on either; the rhythm card may only GRADE a measured one.
    /// Defaults true so every timing already cached on disk keeps working.
    var isMeasured: Bool = true

    init(word: String, startMs: Int, endMs: Int, isMeasured: Bool = true) {
        self.word = word
        self.startMs = startMs
        self.endMs = endMs
        self.isMeasured = isMeasured
    }

    private enum CodingKeys: String, CodingKey { case word, startMs, endMs, isMeasured }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        startMs = try c.decode(Int.self, forKey: .startMs)
        endMs = try c.decode(Int.self, forKey: .endMs)
        isMeasured = try c.decodeIfPresent(Bool.self, forKey: .isMeasured) ?? true
    }
}

/// One spoken turn, answered in the two ways a learner needs.
///
/// **They are different questions and both matter** (2026-09-27, user
/// decision, after a replay showed a 40-word utterance answered by a
/// 12-word fragment): "how would a fluent speaker say this whole thing?"
/// and "what did I actually get wrong?". The first is the line; the second
/// is the list under it.
struct TurnSuggestion: Codable, Hashable {
    /// The learner's WHOLE turn, said the way a fluent speaker would say it
    /// in this conversation — every idea they raised, in their own register,
    /// with the hesitation taken out.
    ///
    /// **Never a fragment.** It used to be one sentence of at most 15 words,
    /// because a drill card cannot be a paragraph — and that constraint had
    /// leaked into the one place the line has to be complete: the
    /// say-it-again reads it aloud IN the conversation, so a fragment left
    /// the re-run answering a question nobody asked. Cards now come from
    /// `fixes`, which are short by nature, so the line is free to be whole.
    var alternative: String
    /// Why the rewrite reads better, in the learner's native language.
    var reason: String
    /// The outright ERRORS inside that turn, quoted and fixed one by one.
    /// Empty is an ordinary answer — a turn can be grammatical and still not
    /// be what a fluent speaker would say. Optional so every turn saved
    /// before this decodes (Swift synthesizes `decodeIfPresent` for an
    /// Optional; a defaulted non-optional would throw).
    var fixes: [TurnFix]? = nil
}

/// One grammatical slip inside a turn: what they said, what it should be,
/// and why — the pair a drill card is made of.
struct TurnFix: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Quoted from the learner's own line, verbatim.
    var was: String
    /// The same words, corrected — nothing else restyled.
    var now: String
    /// The grammar point, in the learner's native language.
    var why: String
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
    /// Coach mode's grammar focus for this call and how it went
    /// (`GrammarFocus`). Optional so old rows decode unchanged; also what the
    /// next call reads to retire a focus the learner has stopped tripping on.
    var grammarFocus: GrammarFocusRecord? = nil
    /// The call ran with coach mode on at some point — a PRACTICE call
    /// (2026-10-01, founder decision). The learner was answering with a
    /// suggested sentence in front of them, so nothing said in it is evidence
    /// of their level: it is left out of the weekly assessment and every
    /// Progress measurement, and what they said is credited as practice, never
    /// as "used in a talk". Everything else about a talk stands — minutes,
    /// streak, corrections → cards, the book. Optional so old rows decode
    /// unchanged; an older build ignores it.
    var coached: Bool? = nil

    /// See `coached`.
    var isPractice: Bool { coached == true }
}

/// One call's grammar focus, as it was shown and as it went (2026-09-30).
/// `label` is coaching (native language); `mistake` / `correction` are the
/// learner's own slip and its fix (target language) — the concrete pair is
/// always shown beside the name, never the name alone.
struct GrammarFocusRecord: Codable, Equatable {
    /// `LearnerProfile` pattern key (normalized mistake→correction).
    var patternKey: String
    var label: String
    var mistake: String
    var correction: String
    /// Times the same slip came back in this call, judged per correction.
    var repeats: Int
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
            let snippet = WordSplitter.snippet(first, words: 6, characters: 14)
            return "\u{201C}\(snippet)\u{201D}"
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
    /// Multi-word expressions the FLUENT SELF used this session and the learner
    /// did not — verified verbatim against the fluent-self turns, the same
    /// hallucination guard `expressionsUsed` gets. This is the talk's NEW
    /// material (the other list is its evidence), and the one thing a call
    /// produces that nothing else in the app could: phrases spoken in the
    /// learner's own voice, about their own situation. Merged into the
    /// expression library at read time by `ExpressionCatalog` — never copied
    /// into `VocabStore`, whose rows count times SAID.
    var expressionsOffered: [String] = []
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
        case knownWord            // a word they had marked known, now confirmed out loud
        case knownExpression      // an expression they had marked known, now confirmed
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
        case .knownWord:          return "Words you marked known"
        case .knownExpression:    return "Expressions you marked known"
        }
    }

    /// `label`, resolved in the app language. A `switch` of literals rather
    /// than `explain(label)`, so the build's string extraction sees every key.
    var localizedLabel: String {
        switch self {
        case .drillCard:          return explain("Review cards")
        case .curriculumItem:     return explain("Your books")
        case .studyingExpression: return explain("Expression notebook")
        case .studyingWord:       return explain("Word notebook")
        case .suggestion:         return explain("In-call suggestions")
        case .knownWord:          return explain("Words you marked known")
        case .knownExpression:    return explain("Expressions you marked known")
        }
    }

    var icon: String {
        switch self {
        case .drillCard:          return "rectangle.stack"
        case .curriculumItem:     return "book"
        case .studyingExpression: return "bookmark"
        case .studyingWord:       return "text.book.closed"
        case .suggestion:         return "lightbulb"
        case .knownWord:          return "checkmark.circle"
        case .knownExpression:    return "checkmark.circle"
        }
    }

    /// Fixed display order — heaviest evidence first, so the breakdown reads
    /// the same everywhere and never reshuffles between reloads.
    static let displayOrder: [Carryover.Source] = [
        .drillCard, .curriculumItem, .studyingExpression, .studyingWord,
        .knownExpression, .knownWord, .suggestion,
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
        case scorecard, newWordsUsed, expressionsUsed, expressionsOffered, weakVocabAreas
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
        expressionsOffered = try c.decodeIfPresent([String].self, forKey: .expressionsOffered) ?? []
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
    /// The CEFR band of the grammatical STRUCTURES the learner actually
    /// produced in this talk (a1…c2) — range, as distinct from accuracy.
    /// `grammar.score` and the verified slips measure how accurately they
    /// spoke; this says how much grammar they reached for. A learner who
    /// stays in short present-tense clauses makes no slips and used to read
    /// C2 on Progress (2026-09-24) — a level is the meeting of both, so the
    /// ≈Grammar band is the LOWER of the two. Optional: talks summarized
    /// before the field decode without it.
    var grammarRange: String? = nil
}

extension SessionScorecard {
    /// `grammarRange` as a level, nil when absent or unrecognized.
    var grammarRangeLevel: CEFRLevel? {
        grammarRange.flatMap { CEFRLevel(rawValue: $0.lowercased()) }
    }

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
    /// The learner's own hand moves on the share level — the last few times
    /// they overruled the summary call's pick, newest last. Fed back into
    /// the next summary call so it sorts the way THIS person draws the line:
    /// people differ on what counts as private, and a correction is the only
    /// signal that says where. Capped at `maxShareCorrections`.
    var shareCorrections: [ShareCorrection] = []

    enum CodingKeys: String, CodingKey {
        case displayName, city, country, lengthOfStay, occupation, household,
             interests, freeNotes, updatedAt, learnedNotes, metAt, shareCorrections
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
    /// How much of this a STRANGER gets — the Find-people intro, a cast
    /// counterpart in a call. Three rungs, not a switch (2026-09-16): in
    /// real life the details of a story are private while its shape is not
    /// — "two kids, kindergarten age" is family, but "a parent of young
    /// kids" is what anyone at a language school would be told. `.gist`
    /// hands out `gist`, `.all` the line itself, `.nothing` nothing. The
    /// line always rides into the fluent self's own prompt whatever this
    /// says; that is what the notebook is for. The summary call sorts each
    /// line at write time and says why (`why`); the learner overrules it in
    /// Me → Profile. DEFAULTS TO NOTHING — a note nobody has judged is
    /// hidden, never shown.
    var share: Share = .nothing
    /// The sentence the line was distilled from, in the learner's own words.
    /// A note is a standing truth ("two kids, kindergarten age"), never the
    /// episode it came out of ("dropped the kids off this morning") — but
    /// the episode is the evidence, and the profile shows it under the line
    /// so the learner can see why the app believes something. Nil on notes
    /// written before 2026-09-16.
    var heard: String? = nil
    /// The one-rung-up version a stranger may hear when `share == .gist`.
    /// Written by the summary call beside the fact; editable. Nil when the
    /// model found no honest gist (health, money, someone else's private
    /// life) — such a line can only be nothing or everything.
    var gist: String? = nil
    /// The model's one-clause reason for its `share` pick, in the app
    /// language. Shown in the profile so the pick is checkable rather than
    /// a bare lock.
    var why: String? = nil
    /// How long this is expected to stay true. A `fact` (job, town, family,
    /// a weekly routine) has no horizon; a `now` line (a trip coming up, jet
    /// lag, a deadline, a cold) is worth knowing on the next call and stale
    /// a month later. Before 2026-09-15 every line was a fact and the file
    /// still said "planning to visit Seoul" weeks after the trip — a
    /// memory with no sense of time asks about the preparations after
    /// you're back. `now` lines expire (`isExpired`) and are shown to the
    /// fluent self as recent news, dated, under the durable lines.
    var kind: Kind = .fact

    enum Kind: String, Codable, Hashable {
        case fact, now
    }

    /// What a stranger gets. Ordered least to most.
    enum Share: String, Codable, Hashable, CaseIterable {
        case nothing, gist, all
    }

    /// Kept for readers that only need the binary: nothing at all leaves the
    /// notebook. A `.gist` line is NOT private in this sense — its gist does.
    var isPrivate: Bool { share == .nothing }

    /// The line as a stranger-facing surface may read it, or nil. `.gist`
    /// with no gist on file yields nil rather than falling back to the text:
    /// the learner chose "the outline", and the outline is missing, so
    /// nothing goes out.
    var strangerLine: String? {
        switch share {
        case .nothing: return nil
        case .all: return text
        case .gist:
            let g = (gist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return g.isEmpty ? nil : g
        }
    }

    /// How long a `now` line is believed after it was learned.
    static let nowHorizon: TimeInterval = 30 * 86_400

    /// `isPrivate` is never written: a build from before 2026-09-16 reading
    /// a `.gist` line with `isPrivate: false` on it would put the WHOLE line
    /// in the intro. It is no longer read either — see `init(from:)`.
    private enum CodingKeys: String, CodingKey {
        case id, text, sessionId, learnedAt, isPrivate, kind, share, heard, gist, why
    }

    init(id: UUID = UUID(), text: String, sessionId: UUID? = nil, learnedAt: Date,
         share: Share = .nothing, kind: Kind = .fact,
         heard: String? = nil, gist: String? = nil, why: String? = nil) {
        self.id = id
        self.text = text
        self.sessionId = sessionId
        self.learnedAt = learnedAt
        self.share = share
        self.kind = kind
        self.heard = heard
        self.gist = gist
        self.why = why
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(learnedAt, forKey: .learnedAt)
        try c.encode(kind, forKey: .kind)
        try c.encode(share, forKey: .share)
        try c.encodeIfPresent(heard, forKey: .heard)
        try c.encodeIfPresent(gist, forKey: .gist)
        try c.encodeIfPresent(why, forKey: .why)
    }

    /// A `now` line past its horizon. Facts never expire.
    func isExpired(at now: Date = Date()) -> Bool {
        kind == .now && now.timeIntervalSince(learnedAt) > Self.nowHorizon
    }

    /// Lenient on everything but the text: every note written before a
    /// field existed has no key for it, and a throw here would empty
    /// `learnedNotes` wholesale through `UserPersona`'s own lenient decoder.
    /// `share` falls back to the old two-way lock (`isPrivate` true →
    /// nothing, false → all), and with neither key to nothing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        sessionId = try? c.decodeIfPresent(UUID.self, forKey: .sessionId)
        learnedAt = (try? c.decodeIfPresent(Date.self, forKey: .learnedAt)) ?? Date()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .fact
        // A note with no `share` is from before the rungs — either the
        // two-way lock of 2026-09-15 or nothing at all — and lands on
        // `nothing` EITHER WAY (2026-09-25). "Unlocked" used to map onto
        // `all`, and those lines were the ones the one-day-old prompt had
        // written as episodes ("Gained a new app user from Hong Kong"), with
        // no gist and no reason on them; they went out in full in every
        // intro. The learner opens a line in Me → Profile, where they can
        // read it first.
        share = (try? c.decodeIfPresent(Share.self, forKey: .share)) ?? .nothing
        heard = try? c.decodeIfPresent(String.self, forKey: .heard)
        gist = try? c.decodeIfPresent(String.self, forKey: .gist)
        why = try? c.decodeIfPresent(String.self, forKey: .why)
    }

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
        shareCorrections = value(.shareCorrections, [])
    }

    /// One time the learner moved a line's share level by hand.
    struct ShareCorrection: Codable, Hashable {
        var text: String
        var from: PersonaNote.Share
        var to: PersonaNote.Share
        var at: Date
    }

    static let maxShareCorrections = 8

    /// Record the learner's hand moves between what was on file and what
    /// they saved, so the next summary call can learn from them. Only a
    /// CHANGED level counts; a line saved as it was says nothing.
    mutating func recordShareCorrections(from previous: [PersonaNote], now: Date = Date()) {
        let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for note in learnedNotes {
            guard let old = before[note.id], old.share != note.share else { continue }
            shareCorrections.append(.init(text: note.text, from: old.share, to: note.share, at: now))
        }
        if shareCorrections.count > Self.maxShareCorrections {
            shareCorrections.removeFirst(shareCorrections.count - Self.maxShareCorrections)
        }
    }

    /// Everything the learner TYPED about themselves, as plain lines. Handed
    /// to the summary call as the "don't hand this back as a discovery" list —
    /// without it the same fact is re-learned every session and the profile
    /// fills with paraphrases of one sentence. The remembered lines go to the
    /// same call separately (`currentNotes`), numbered and dated, because
    /// those are the ones it may also UPDATE.
    var knownFacts: [String] {
        var out: [String] = []
        let place = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { out.append("Lives in \(place)") }
        if !occupation.isEmpty { out.append(occupation) }
        if !household.isEmpty { out.append(household) }
        if !interests.isEmpty { out.append("Interested in \(interests.joined(separator: ", "))") }
        if !freeNotes.isEmpty { out.append(freeNotes) }
        return out
    }

    /// The remembered lines still believed: everything on file minus the
    /// `now` lines whose month has passed. Every reader of the notebook — the
    /// conversation prompt, the summary call's on-file list, the public
    /// intro — goes through this, so an expired line is gone from all of
    /// them at once even before the next save prunes it from disk.
    func currentNotes(at now: Date = Date()) -> [PersonaNote] {
        learnedNotes.filter { !$0.isExpired(at: now) }
    }

    /// What a STRANGER gets from the notebook — the only lines any
    /// stranger-facing surface (the Find-people intro, a cast counterpart's
    /// prompt) may read: the text of an `.all` line, the gist of a `.gist`
    /// line, nothing of a `.nothing` one. Never the notes themselves.
    var strangerLines: [String] { currentNotes().compactMap(\.strangerLine) }

    /// The stranger set narrowed to STANDING truths — what the public intro
    /// is written from (2026-09-25). A `now` line is news, not who you are:
    /// "on the way to the kids' Korean school" was going out as the second
    /// sentence of an introduction. The live counterpart block keeps
    /// `strangerLines`, where an unlocked piece of news is fair small talk.
    var strangerFacts: [String] {
        currentNotes().filter { $0.kind == .fact }.compactMap(\.strangerLine)
    }

    /// A line the summary call says has CHANGED: the trip that was planned
    /// has happened, the job that was hunted was found. `replacing` is the
    /// on-file line it supersedes; the new one takes its place in the
    /// notebook as the freshest line.
    struct NoteUpdate {
        var replacing: UUID
        var note: PersonaNote
    }

    /// Fold what a talk taught into the notebook. Updates first — an
    /// outdated line goes and its successor is appended as the newest —
    /// then additions, dropping anything already on file. Expired `now`
    /// lines are pruned here too. Newest last; the oldest fall off past
    /// `limit` so the conversation prompt this feeds can't grow without
    /// bound.
    mutating func absorb(notes: [PersonaNote], updates: [NoteUpdate] = [],
                         limit: Int = 40, now: Date = Date()) {
        for update in updates {
            guard let idx = learnedNotes.firstIndex(where: { $0.id == update.replacing }) else { continue }
            learnedNotes.remove(at: idx)
            learnedNotes.append(update.note)
        }
        learnedNotes.removeAll { $0.isExpired(at: now) }
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

    /// True for a public figure (a singer, an athlete, an author) added under
    /// the "Public figure" relationship: their profile is filled from PUBLIC
    /// coverage rather than the learner's own notes, and every stranger-facing
    /// rule for a preset voice applies — never a clone. Optional so rows saved
    /// before this decode unchanged.
    var isPublicFigure: Bool? = nil
    /// The identity the grounded parse settled on ("BTS Jimin · singer"),
    /// shown for the learner to confirm. nil for anyone else.
    var publicIdentity: String? = nil
    /// When public facts were last looked up. "Refresh public info" re-runs
    /// the grounded parse and moves this.
    var factsRefreshedAt: Date? = nil

    // How the two of them talk (2026-09-28). The profile above says who the
    // person IS; none of it said how they and the learner SPEAK to each
    // other, so every call and scene had to guess the level of address —
    // and the call prompt, which cast everyone as a new acquaintance,
    // guessed polite for a best friend.
    /// The intake's relationship chip (`"Friend"`, `"Manager"` …), kept as
    /// its English raw value because `relationship` is the learner's own
    /// words and can say anything. nil for people made before this, and for
    /// strangers from the pool.
    var relationshipKind: String? = nil
    /// How the LEARNER speaks to this person. nil = not set: the relationship
    /// decides, as it always did.
    var myRegister: SpeechRegister? = nil
    /// How this person speaks to the learner. Its own field because Korean
    /// and Japanese let the two differ (a manager in 반말, the learner in 존댓말).
    var theirRegister: SpeechRegister? = nil
    /// What the learner calls them ("형", "부장님", "Sarah").
    var iCallThem: String = ""
    /// What they call the learner.
    var theyCallMe: String = ""
    /// Whether this person knows the learner's life the way someone close
    /// does — the whole notebook, private lines included — or only what a
    /// stranger is allowed to hear. nil = the relationship's default
    /// (`knowsMyLifeByDefault`).
    var knowsMyLife: Bool? = nil

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
        case isPublicFigure, publicIdentity, factsRefreshedAt
        case relationshipKind, myRegister, theirRegister, iCallThem, theyCallMe, knowsMyLife
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
        isPublicFigure = try c.decodeIfPresent(Bool.self, forKey: .isPublicFigure)
        publicIdentity = try c.decodeIfPresent(String.self, forKey: .publicIdentity)
        factsRefreshedAt = try c.decodeIfPresent(Date.self, forKey: .factsRefreshedAt)
        relationshipKind = try c.decodeIfPresent(String.self, forKey: .relationshipKind)
        // A rung this build doesn't know (a newer build's) reads as "not
        // set" rather than failing the whole person.
        myRegister = (try? c.decodeIfPresent(SpeechRegister.self, forKey: .myRegister)) ?? nil
        theirRegister = (try? c.decodeIfPresent(SpeechRegister.self, forKey: .theirRegister)) ?? nil
        iCallThem = try c.decodeIfPresent(String.self, forKey: .iCallThem) ?? ""
        theyCallMe = try c.decodeIfPresent(String.self, forKey: .theyCallMe) ?? ""
        knowsMyLife = try c.decodeIfPresent(Bool.self, forKey: .knowsMyLife)
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
        // These three were decoded but never written until 2026-09-28, so a
        // public figure stopped being one on the first save-and-reload.
        try c.encodeIfPresent(isPublicFigure, forKey: .isPublicFigure)
        try c.encodeIfPresent(publicIdentity, forKey: .publicIdentity)
        try c.encodeIfPresent(factsRefreshedAt, forKey: .factsRefreshedAt)
        try c.encodeIfPresent(relationshipKind, forKey: .relationshipKind)
        try c.encodeIfPresent(myRegister, forKey: .myRegister)
        try c.encodeIfPresent(theirRegister, forKey: .theirRegister)
        try c.encode(iCallThem, forKey: .iCallThem)
        try c.encode(theyCallMe, forKey: .theyCallMe)
        try c.encodeIfPresent(knowsMyLife, forKey: .knowsMyLife)
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
    /// The English voice's own name. What screens show is `displayName`,
    /// which follows the target language (see `localNames`).
    let englishName: String
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
                    englishName: "Paige", gender: "Female", accent: "American",
                    description: "Engaging, natural"),
        VoicePreset(id: "UgBBYS2sOqTuMpoF3BR0",
                    englishName: "Mark", gender: "Male", accent: "American",
                    description: "Natural, conversational"),
        VoicePreset(id: "FF59babHL8N8gfTgtBMT",
                    englishName: "Emma", gender: "Female", accent: "British",
                    description: "Clear, friendly"),
        VoicePreset(id: "L0Dsvb3SLTyegXwtm47J",
                    englishName: "James", gender: "Male", accent: "British",
                    description: "Warm, easygoing"),
    ]

    static func by(id: String) -> VoicePreset {
        catalog.first(where: { $0.id == id }) ?? catalog[0]
    }

    // MARK: - A preset is a SLOT, voiced per target language (2026-09-28)
    //
    // The four voices above are American/British speakers, and reading Korean
    // they sounded like exactly that — every Korean scene partner and stranger
    // was an English speaker reading Korean. So a preset id is now a SLOT: what
    // is stored (on a Counterpart, a Scenario, a public persona row, a
    // StockPerson) is still the English id, and the voice that actually speaks
    // is resolved from it at synthesis time, for the language being spoken.
    // Nothing stored changes, and a person — who is shared by every target
    // language — speaks natively in each one.
    //
    // Korean voices picked by ear by the founder from the ElevenLabs library
    // (native ko speakers, added to the account 2026-09-28 — a library voice
    // must be in "My Voices" to synthesize). Japanese uses the same four by
    // the founder's decision; German and English keep the originals. Every id
    // here must also be in the two server allowlists (gateway/src/supabase.ts,
    // supabase/functions/elevenlabs-tts) or the server refuses it.
    private static let voicedBySlot: [String: [String: String]] = {
        let korean = [
            "NDTYOmYEjbDIVCKB35i3": "5n5gqmaQi9Ewevrz7bOS",  // Paige → Sian (F)
            "UgBBYS2sOqTuMpoF3BR0": "L4az9Gb378GIycFl2nAB",  // Mark  → "KO - Calm, Friendly, Warm" (M)
            "FF59babHL8N8gfTgtBMT": "8jHHF8rMqMlg8if2mOUe",  // Emma  → Han (F)
            "L0Dsvb3SLTyegXwtm47J": "AKF7f2y1L8ktV5vxXILw",  // James → Joon (M)
        ]
        return ["ko": korean, "ja": korean]
    }()

    /// The voice that speaks a stored voice id in `language`. Anything that
    /// isn't a preset slot — the learner's clone, a retired preset id —
    /// passes through untouched.
    static func speaking(_ voiceId: String, in language: String) -> String {
        voicedBySlot[language]?[voiceId] ?? voiceId
    }

    /// Where a slot speaks in another language's own voice, it goes by a name
    /// from that language too — a Korean speaker introduced as "Paige" reads
    /// as a mistake. MATERIAL, so the TARGET language (the name is said in
    /// scenes), not the app language. Japanese keeps the founder's Korean
    /// voices but takes Japanese names, because the scene is written in
    /// Japanese around them.
    private static let localNames: [String: [String: String]] = [
        "ko": ["NDTYOmYEjbDIVCKB35i3": "시안", "UgBBYS2sOqTuMpoF3BR0": "민준",
               "FF59babHL8N8gfTgtBMT": "한별", "L0Dsvb3SLTyegXwtm47J": "준호"],
        "ja": ["NDTYOmYEjbDIVCKB35i3": "美咲", "UgBBYS2sOqTuMpoF3BR0": "翔太",
               "FF59babHL8N8gfTgtBMT": "陽菜", "L0Dsvb3SLTyegXwtm47J": "健太"],
    ]

    func name(in language: String) -> String {
        Self.localNames[language]?[id] ?? englishName
    }

    /// The name for the language being practised right now — every screen
    /// that shows a preset reads this.
    var displayName: String {
        name(in: UserDefaults.standard.string(
            forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en")
    }

    /// The picker's caption. The accent and description are the ENGLISH
    /// voice's, so a slot voiced by someone else in `language` shows only
    /// what is still true of it: the gender.
    func caption(in language: String) -> String {
        Self.speaking(id, in: language) == id
            ? "\(gender) · \(accent) · \(description)"
            : gender
    }

    /// Same, for the language being practised right now. Every synthesis runs
    /// in the active target language (scenes, strangers and books are all
    /// per-language), which is why the network layer can resolve on its own.
    static func speaking(_ voiceId: String) -> String {
        speaking(voiceId, in: UserDefaults.standard.string(
            forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en")
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

    /// `identity` for a scene in `language`. It names the ENGLISH voice's
    /// nationality ("Paige — American, …"); where the slot speaks in another
    /// native voice (`VoicePreset.speaking`) that would cast an American
    /// speaking Korean, so the nationality is dropped and the rest stands.
    func identity(in language: String) -> String {
        guard VoicePreset.speaking(voice.id, in: language) != voice.id else { return identity }
        let rest = identity.replacingOccurrences(
            of: #"(American|British), "#, with: "", options: .regularExpression)
        // …and the name is the one this language gives the slot.
        guard rest.hasPrefix(voice.englishName) else { return rest }
        return voice.name(in: language) + rest.dropFirst(voice.englishName.count)
    }

    /// A built-in person's saved row, named for `language`. The row is saved
    /// the first time the person is picked, under whatever name they had
    /// then, and one row serves every target language (people are global),
    /// so the name and the scene identity are rewritten on read — on load
    /// (`CounterpartStore.load`) and on a language switch. Any other row
    /// passes through untouched.
    static func localized(_ c: Counterpart, language: String) -> Counterpart {
        guard let rid = c.remoteId, rid.hasPrefix("builtin:"),
              let stock = catalog.first(where: { $0.remoteKey == rid }) else { return c }
        var out = c
        out.name = stock.voice.name(in: language)
        out.background = stock.identity(in: language)
        out.intro = stock.identity(in: language)
        return out
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
        let language = UserDefaults.standard.string(
            forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en"
        if let known = existing.first(where: { $0.remoteId == remoteKey || $0.id == localId }) {
            return Self.localized(known, language: language)
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
        return Self.localized(c, language: language)
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
    /// Material the learner attached to this situation (a job posting's
    /// link, their CV from the Files app) and what ONE reading of it
    /// produced. The reading happens once, before the first scene; the
    /// files themselves are never copied — see `ScenarioBrief`. Optional so
    /// scenarios saved before this decode unchanged.
    var brief: ScenarioBrief? = nil
    /// Set on a scenario minted from one of Talk's ready-made situations
    /// (`StarterSituation.id`), so the next tap on that row reuses it and the
    /// "Your scenarios" lists leave it out. Optional so old rows decode.
    var starterId: String? = nil

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

// MARK: - Scenario Brief (what the learner attached, read once)

/// The learner's own material for a situation — a posting's link, a CV or
/// portfolio picked from the Files app, a photo of a letter — and the facts
/// one reading of it produced. Two rules:
///
///   - **The file is never copied.** A picked file is read where it lives
///     (security-scoped access, bytes straight into the analysis request)
///     and only its NAME and an iOS bookmark stay here, so "Read again" can
///     open the same file and a moved one asks to be picked again. Nothing
///     lands in the sandbox, the sync payload, or the usage ledger.
///   - **Two sides, kept apart.** `counterpartFacts` and `likelyQuestions`
///     are the OTHER side (the company, the position, what they will ask)
///     and ride into the counterpart block of every prompt; `learnerFacts`
///     are the learner's own (the 2023 gap, the +18% project) and ride into
///     the persona block. Mixing them is how a scene hands the learner's CV
///     to the interviewer to recite.
struct ScenarioBrief: Codable, Hashable {
    struct Source: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case link, file, image }
        var id: UUID = UUID()
        var kind: Kind
        /// A link's URL, or a file's display name.
        var label: String
        /// Security-scoped bookmark for a picked file. nil for links and for
        /// a file whose bookmark could not be made.
        var bookmark: Data? = nil
        /// False once a reading reported it could not open this source.
        var readOK: Bool = true
        /// One short line the reading wrote about it ("job posting · Berlin",
        /// "3 pages").
        var detail: String? = nil
    }

    var sources: [Source] = []
    /// One line naming what the material is about ("Zalando · Senior Product
    /// Designer · Berlin"). Empty until read.
    var summary: String = ""
    /// The other side: who they are, what they want, how they talk.
    var counterpartFacts: [String] = []
    /// What the other side is likely to ask or say. Scenes vary which ones
    /// they use, so a template keeps producing fresh takes.
    var likelyQuestions: [String] = []
    /// The learner's side: what to prepare, what to bring up, what to have
    /// an answer for.
    var learnerFacts: [String] = []
    /// Reusable phrases the situation calls for — the scene plants them, the
    /// call's chip row asks for them.
    var keyExpressions: [String] = []
    /// When the sources were last read. nil = attached but not read yet
    /// (the reading runs before the first scene).
    var readAt: Date? = nil

    var hasSources: Bool { !sources.isEmpty }
    var needsReading: Bool { hasSources && readAt == nil }
    var hasContent: Bool {
        !counterpartFacts.isEmpty || !likelyQuestions.isEmpty
            || !learnerFacts.isEmpty || !keyExpressions.isEmpty
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
    /// The word range of the line this take practised when the learner had
    /// selected a PHRASE — nil for the whole line. Optional so attempts
    /// saved before it decode. A phrase take is real practice (it is
    /// counted, listed and replayable) but it is not the LINE: nothing that
    /// masters, retries or ranks a line may read one — nailing "the bank"
    /// used to check off the sentence it came from.
    var phraseRange: ClosedRange<Int>? = nil
    var isPartial: Bool { phraseRange != nil }

    /// The number this attempt is JUDGED by, everywhere. `matchScore` alone
    /// answers "did you say the right words", which is reading aloud;
    /// shadowing is the beat as well, so rhythm is folded in whenever it
    /// could be measured. Attempts saved before 2026-09-13 carry no
    /// `rhythmScore`, so their number is unchanged — the blend can only ever
    /// apply to takes that were actually measured for it.
    var overallScore: Int {
        ShadowEngine.overallScore(match: matchScore, rhythm: rhythmScore)
    }
}

// MARK: - Shadow Feedback

/// Result of comparing a learner's shadow-attempt against a fluent-self line.
/// Returned by `ShadowEngine` via Gemini; rendered as three short bullets in
/// `ShadowDrillView`.
struct ShadowFeedback: Codable, Hashable {
    var pronunciation: String   // one line on accuracy / pronunciation match
    var pacing: String          // one line on intonation + speed delta
    var fix: String             // one concrete thing to try next attempt
    var matchScore: Int         // 0–100 word match alone
    /// nil = the attempt could not be timed, which the score card says out
    /// loud rather than quietly reverting to a words-only number.
    var rhythmScore: Int? = nil

    var overallScore: Int {
        ShadowEngine.overallScore(match: matchScore, rhythm: rhythmScore)
    }
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
    /// When the learner PRODUCED this line in a real talk — the strongest
    /// evidence there is. "Got it" is the learner's own verdict and only
    /// reaches the top rung; this is what makes that verdict CONFIRMED.
    /// nil for a card that was only ever marked known by hand.
    var usedInTalkAt: Date?
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

// MARK: - Weekly test

/// One week's test, built from THAT learner's own week — the words the talks
/// taught, the phrases the fluent self used, the sentences that were
/// corrected, the lines worth hearing again. Nothing here comes from a
/// generic bank; an item with no source in the learner's material is not an
/// item. Frozen once built (`items`), so a test read later still asks what
/// it asked; the answers accumulate as the learner plays.
struct WeeklyTest: Codable, Identifiable, Equatable {
    /// A weekly paper from the week's material, or the monthly paper made of
    /// every item the month's weekly tests got wrong.
    enum Kind: String, Codable { case weekly, monthly }

    let id: UUID
    let targetLanguage: String
    /// nil decodes as `.weekly` (tests written before the monthly existed).
    var kind: Kind? = nil
    var isMonthly: Bool { kind == .monthly }
    /// The window the material was drawn from.
    let periodStart: Date
    let periodEnd: Date
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var items: [WeeklyTestItem]
    var answers: [WeeklyTestAnswer] = []
    /// Longest run of correct answers in a row while playing.
    var bestStreak: Int = 0
    /// When the result was written into the review loop (`WeeklyTestEngine.apply`);
    /// nil until then, so a finished test is applied exactly once.
    var appliedAt: Date? = nil

    var isFinished: Bool { finishedAt != nil }
    var score: Int { answers.filter(\.correct).count }
    var total: Int { items.count }
    /// The next item to play, nil once every one is answered.
    var nextItem: WeeklyTestItem? {
        let done = Set(answers.map(\.itemId))
        return items.first { !done.contains($0.id) }
    }
}

struct WeeklyTestItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        /// A word the talks taught: its meaning is shown, pick the word.
        case meaning
        /// A line the fluent self said with its phrase blanked out: pick the phrase.
        case gap
        /// A sentence the learner said and was corrected: rebuild the fluent
        /// version from shuffled word tiles.
        case build
        /// A fluent-self line played from its saved audio: pick what was said.
        case listen
        /// A fluent-self line to say out loud, scored like a shadow take.
        case speak
        /// A grammar point the week's report found going wrong in more than
        /// one sentence: its rule is shown with one of the learner's lines,
        /// and the line is rebuilt the right way from tiles.
        case grammar
        /// A word the learner leans on (the report's "upgrades"): their line
        /// with it marked, pick the better word.
        case upgrade
    }
    let id: UUID
    let kind: Kind
    /// meaning: the sense in the learner's language · gap: the line with the
    /// blank · build: what the learner originally said · listen: empty.
    let prompt: String
    /// The correct answer, as the material spells it.
    let answer: String
    /// meaning/gap/listen: the choices, answer included, in display order ·
    /// build: the word tiles, in display order.
    let options: [String]
    /// Where the item came from, so the result can write back to the review
    /// loop and the screen can name the talk.
    var sessionId: UUID? = nil
    var turnId: UUID? = nil
    var cardId: UUID? = nil
    /// build: the correction's one-line reason (coaching, native language).
    var note: String? = nil
    /// True when the item came back from an earlier test's wrong answers.
    var isRetake: Bool? = nil
    /// grammar: the rule in the learner's language.
    var rule: String? = nil
    /// grammar: the span that was wrong · upgrade: the leaned-on word —
    /// marked inside `prompt`.
    var focus: String? = nil
    /// upgrade: the learner's line with the better word in it.
    var example: String? = nil
}

struct WeeklyTestAnswer: Codable, Hashable {
    let itemId: UUID
    let given: String
    let correct: Bool
    let at: Date
    /// speak: the shadow match score the verdict was made from.
    var score: Int? = nil
}

// MARK: - Speech (the read-aloud tab)

/// What a speech script does for its listener. The genre decides the shape the
/// writer is asked for (an explainer builds up, a product pitch lands on why it
/// matters, a news read is neutral), never the topic.
enum SpeechGenre: String, Codable, CaseIterable, Identifiable {
    case explainer, product, person, briefing, news
    var id: String { rawValue }
}

/// A script the learner reads aloud under the prompter. MATERIAL — `title`,
/// `body` and each key term are in the target language; `summary` and the
/// meanings are NOTES in the native language.
struct SpeechScript: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var genre: SpeechGenre
    /// What the learner asked for, as they typed it. Empty = the writer chose.
    var topic: String
    var body: String
    var summary: String
    var keyTerms: [SpeechKeyTerm]
    /// Where the facts came from, by name. Shown under the script.
    var sources: [String]
    var language: String
    var targetSeconds: Int
    var createdAt: Date
    /// Bundled with the app — the one script every account can practise.
    var isBuiltIn: Bool
}

struct SpeechKeyTerm: Codable, Hashable {
    var term: String
    var meaning: String
}

/// One read of a script. Every number in `metrics` is computed in code from
/// the recording and the transcript; only `coaching` is written by a model.
struct SpeechTake: Codable, Identifiable, Hashable {
    let id: UUID
    var scriptId: UUID
    var createdAt: Date
    var durationSeconds: Double
    /// `Documents/Speech/<file>` — the learner's own voice, always kept.
    var audioFilename: String
    /// The camera take with the voice muxed in, when the camera was on and
    /// the learner kept it. Nil once deleted.
    var videoFilename: String?
    var transcript: String
    var metrics: SpeechMetrics
    var coaching: SpeechCoaching?
}

struct SpeechMetrics: Codable, Hashable {
    /// 0–100, how much of the script was said as written.
    var accuracy: Int
    /// Script words (spaced languages) or syllables/characters (ko, ja) per
    /// minute of speaking — first voice to last voice.
    var rate: Int
    var rateLow: Int
    var rateHigh: Int
    var paceScore: Int
    /// Sentence ends where the speaker actually paused, out of all of them.
    var pausesAtBreaks: Int
    var breaks: Int
    /// Silences over `SpeechAnalyzer.hesitationSeconds` inside a sentence.
    var hesitations: Int
    var pauseScore: Int
    var fillers: Int
    var fillerScore: Int
    /// How even the voice stayed, and how much it dropped at sentence ends.
    var steadiness: Int
    /// Script words skipped or said differently, in script order (capped).
    var missed: [String]
    var overall: Int
}

/// The model's notes on a take, in the NATIVE language, anchored to the
/// numbers it was given.
struct SpeechCoaching: Codable, Hashable {
    var headline: String
    var tips: [String]
}
