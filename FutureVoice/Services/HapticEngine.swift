import UIKit

/// Centralized haptic vocabulary for the app. Semantic methods (instead of
/// raw `UIImpactFeedbackGenerator` calls in every view) so the pattern stays
/// consistent — e.g., every "call started" beat across the app feels the
/// same. iOS-native only, no audio.
@MainActor
enum HapticEngine {

    // MARK: - Primitives

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Semantic events (use these from views)

    /// Phone-call mode just activated (mic listening).
    static func phoneCallStarted() { medium() }

    /// User hung up the phone-call (mic deactivated).
    static func phoneCallEnded() { light() }

    /// VAD detected end-of-utterance and is sending to the avatar.
    static func voiceSent() { soft() }

    /// SRS drill swipe committed as "Got it".
    static func drillCorrect() { success() }

    /// SRS drill swipe committed as "Try again".
    static func drillIncorrect() { warning() }

    /// Shadow countdown 3 / 2 / 1 tick.
    static func countdownTick() { light() }

    /// Shadow countdown "GO" — recording starts now.
    static func countdownGo() { medium() }

    /// Shadow attempt finished — strength scales with match score.
    static func shadowComplete(score: Int) {
        switch score {
        case 80...:    success()
        case 50..<80:  soft()
        default:       warning()
        }
    }
}
