import StoreKit
import UIKit

/// The App Store's own rating prompt, asked of people who have actually LIVED
/// with the app — never of someone still forming a first impression.
///
/// Three bars, all on the meter the ring reads (`TalkTimeLog`, which is the
/// ledger's receipt), and each rules out a rating that says nothing:
///
/// - **20 minutes of talk in total.** Talking is the product; a rating from
///   someone who hasn't spent real time in a call is a rating of the onboarding.
/// - **Talk on 3 different days.** Coming back is the verdict; twenty minutes
///   in one sitting is still a first impression.
/// - **The call that just ended ran 3 minutes.** Asked on the way out of a
///   real conversation, never after a dropped or abandoned one.
///
/// Rules that come from Apple, not from us:
///
/// - **iOS decides whether it appears** (at most three times in 365 days, never
///   in TestFlight), and nothing tells the app whether it did. So the ask is
///   spent per APP VERSION the moment it is requested — a version is the unit
///   a new rating actually describes.
/// - **It is gated on use, never on sentiment.** Showing it only to someone who
///   gave `FeedbackSheet` five stars is review gating, which the guidelines
///   forbid. The two never share a call: the feedback sheet wins its call, and
///   this waits for a later one.
enum ReviewRequest {
    static let minTalkSeconds = 20 * 60
    static let minTalkDays = 3
    static let minCallSeconds: TimeInterval = 3 * 60

    private static let askedVersionKey = "futurevoice.reviewRequest.askedVersion"

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func shouldAsk(callSeconds: TimeInterval) -> Bool {
        guard callSeconds >= minCallSeconds,
              UserDefaults.standard.string(forKey: askedVersionKey) != appVersion
        else { return false }
        return TalkTimeLog.totalSeconds() >= minTalkSeconds
            && TalkTimeLog.daysWithTalk() >= minTalkDays
    }

    /// Spends this version's ask and requests the prompt once the call screen
    /// has gone — presented over a screen mid-dismissal, the system can drop it.
    @MainActor
    static func ask() {
        UserDefaults.standard.set(appVersion, forKey: askedVersionKey)
        Analytics.capture("review_requested", [
            "talk_seconds": TalkTimeLog.totalSeconds(),
            "talk_days": TalkTimeLog.daysWithTalk(),
        ])
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
