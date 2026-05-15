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
}

struct PhraseFeedback: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var userSaid: String
    var fluentAlternative: String
    var reason: String
}
