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
}

struct SessionSummary: Codable {
    var phrasesUsed: [PhraseFeedback]
    var newPatternsDetected: [LearnerPattern]
    var suggestedDrills: [String]
    var overallNote: String
    var scorecard: SessionScorecard?
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
}

struct AxisScore: Codable, Hashable {
    var score: Int       // 0–100
    var note: String     // one short sentence
}

struct PhraseFeedback: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var userSaid: String
    var fluentAlternative: String
    var reason: String
}

// MARK: - User Persona

/// Rich personal context the avatar uses to ground every conversation.
/// The more of this is filled in, the more the avatar's English sounds
/// like the user actually lives this life — not generic textbook English.
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
    var englishSituations: [String]   // ["Kita parent small talk", "client calls", "doctor visits"]
    var freeNotes: String             // catch-all
    var updatedAt: Date

    static let empty = UserPersona(
        displayName: "",
        city: "",
        country: "",
        lengthOfStay: "",
        occupation: "",
        household: "",
        interests: [],
        englishSituations: [],
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
            || !englishSituations.isEmpty
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
    var turns: [DialogueEngineTurn]
    var createdAt: Date = Date()
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

    /// Human-readable title shown in the list. Kept simple so the user can
    /// scan a long list quickly.
    var displayTitle: String {
        "\(environment) · with \(role)"
    }

    /// Structured prompt blurb the conversation system prompt parses to put
    /// the avatar into character. Same `environment=… | role=… | notes=…`
    /// format the builder previously wrote directly into topicBlurb.
    var promptBlurb: String {
        var parts = ["environment=\(environment)", "role=\(role)"]
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("notes=\(notes)")
        }
        return parts.joined(separator: " | ")
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
