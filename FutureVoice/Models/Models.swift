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
        case grammarIssues
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

    enum CodingKeys: String, CodingKey {
        case displayName, city, country, lengthOfStay, occupation, household,
             interests, freeNotes, updatedAt
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

    /// Persona-grounded scenario library specific to this counterpart. Fed by
    /// `TopicEngine.suggestForCounterpart` and cached here so opening Watch
    /// for the same person doesn't re-bill Gemini every time. Empty until
    /// first WatchSetupSheet open.
    var savedScenarios: [SuggestedTopic] = []

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

/// Curated subset of ElevenLabs default voices (all stable, well-known IDs)
/// used for counterpart voices. We deliberately keep the list small so the
/// user can pick quickly instead of scrolling through hundreds.
struct VoicePreset: Hashable, Identifiable {
    let id: String           // ElevenLabs voice id
    let displayName: String
    let gender: String
    let accent: String
    let description: String

    static let catalog: [VoicePreset] = [
        VoicePreset(id: "21m00Tcm4TlvDq8ikWAM",
                    displayName: "Rachel", gender: "Female", accent: "American",
                    description: "Calm, conversational"),
        VoicePreset(id: "EXAVITQu4vr4xnSDxMaL",
                    displayName: "Bella", gender: "Female", accent: "American",
                    description: "Soft, friendly"),
        VoicePreset(id: "AZnzlk1XvdvUeBnXmlld",
                    displayName: "Domi", gender: "Female", accent: "American",
                    description: "Strong, confident"),
        VoicePreset(id: "MF3mGyEYCl7XYWbV9V6O",
                    displayName: "Elli", gender: "Female", accent: "American",
                    description: "Emotional, youthful"),
        VoicePreset(id: "ErXwobaYiN019PkySvjV",
                    displayName: "Antoni", gender: "Male", accent: "American",
                    description: "Well-rounded narrator"),
        VoicePreset(id: "VR6AewLTigWG4xSOukaG",
                    displayName: "Arnold", gender: "Male", accent: "American",
                    description: "Crisp, mature"),
        VoicePreset(id: "TxGEqnHWrfWFTfGW9XjX",
                    displayName: "Josh", gender: "Male", accent: "American",
                    description: "Deep, casual"),
        VoicePreset(id: "pNInz6obpgDQGcFmaJgB",
                    displayName: "Adam", gender: "Male", accent: "American",
                    description: "Deep, narration"),
    ]

    static func by(id: String) -> VoicePreset {
        catalog.first(where: { $0.id == id }) ?? catalog[0]
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
    /// The scenario's course content — words, expressions, and shadow lines
    /// to master. Generated once on first open of the scenario page and
    /// persisted here. nil for scenarios that haven't been opened yet
    /// (and for all rows saved before this existed).
    var curriculum: ScenarioCurriculum? = nil
    /// Set when the user shelves a mastered (or abandoned) scenario. Archived
    /// scenarios drop out of the main grid into the Archive section.
    var archivedAt: Date? = nil
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
        var note: String
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
