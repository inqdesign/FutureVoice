import Foundation
enum LanguageScope { static var active: String = "en" }
enum ShadowEngine {
    static func expandForDiff(_ s: String, language: String) -> String { s }
    static func overallScore(match: Int, rhythm: Int?) -> Int { match }
}
enum JapaneseMorph { static func reading(of s: String) -> String { s } }
enum CarryoverDetector { static func normalized(_ s: String) -> String { s } }
enum DrillStore { static func looksLikeMetaRule(_ s: String) -> Bool { false } }
enum ClaudeClient { struct Message { enum Role { case user, assistant }; let role: Role; let content: String } }
enum GeminiClient { struct Message {
    enum Role { case user, model }
    struct InlineAudio {}
    let role: Role; let content: String; var inlineAudio: InlineAudio? = nil
} }
func explain(_ s: String) -> String { s }
func chrome(_ s: String) -> String { s }
enum PublicPersonaService { enum Group: String { case character, person } }
enum WordSplitter { static func snippet(_ s: String, words: Int, characters: Int) -> String { s } }
func explain(key: String, default d: String) -> String { d }
/// Models.swift reads it for `Turn.readFromCoach` (iOS 3dc33326); no prompt fixture has a coach line.
enum CoachRead { static func isRead(_ said: String, line: String?) -> Bool { false } }
