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

    /// The system "a picker moved to a new value" tick. Use this — not
    /// `light()` — whenever a continuous gesture crosses into a new discrete
    /// choice; it's quieter than an impact and doesn't fatigue when it fires
    /// many times inside one drag.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
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

    /// Dragging a drill card crossed into a different bin — one tick per
    /// crossing, so the learner can feel the target change without looking
    /// down at the tray.
    static func drillBinChanged() { selection() }

    /// A drill card was released into a bin. "Got it" gets the success
    /// notification it always had; picking a re-study time is a plain, quieter
    /// commit — it isn't an achievement.
    static func drillBinned(mastered: Bool) {
        if mastered { success() } else { rigid() }
    }

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
