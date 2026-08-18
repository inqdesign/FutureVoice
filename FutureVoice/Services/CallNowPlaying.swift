import Foundation
import MediaPlayer

/// The call as the LOCK SCREEN sees it.
///
/// The app keeps its audio session alive in the background (`UIBackgroundModes:
/// audio` in Info.plist) so a call survives the screen going dark. That leaves
/// a problem the foreground never had: a call the learner can't see is a call
/// they can't hang up without unlocking, and iOS shows nothing for an app that
/// plays audio without publishing Now Playing info — the lock screen would keep
/// displaying whatever played before us.
///
/// So a live call publishes itself: the topic as the title, and play/pause
/// wired to the same hang-up and resume the mic button performs. Nothing else
/// is offered — there is no seeking in a conversation, which is also why it is
/// flagged as a live stream (that hides the scrubber).
///
/// Bracketing matters more than the metadata: `end()` must run on every exit
/// from a call, or the phone keeps showing a call that isn't happening.
@MainActor
enum CallNowPlaying {
    private static var isActive = false

    /// Publish a call. `onResume` / `onPause` are the lock screen's play and
    /// pause — the same two things the mic button does.
    static func begin(title: String,
                      onResume: @escaping () -> Void,
                      onPause: @escaping () -> Void) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        // Hopping to the main actor rather than asserting isolation:
        // MediaPlayer makes no promise about which thread a remote command
        // arrives on, and a wrong guess there is a crash on a lock-screen tap.
        center.playCommand.addTarget { _ in
            Task { @MainActor in onResume() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }
        // Headphone pinch/click lands here, not on play or pause.
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in isPlaying ? onPause() : onResume() }
            return .success
        }
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        // Everything else would draw a control that means nothing in a call.
        for unused in [center.nextTrackCommand, center.previousTrackCommand,
                       center.seekForwardCommand, center.seekBackwardCommand,
                       center.changePlaybackPositionCommand, center.stopCommand] {
            unused.isEnabled = false
        }

        isActive = true
        update(title: title, isPlaying: true)
    }

    private static var isPlaying = false

    /// Refresh what the lock screen shows — the topic once it's known, and
    /// whether the call is live or on hold.
    static func update(title: String, isPlaying playing: Bool) {
        guard isActive else { return }
        isPlaying = playing
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: Bundle.main
                .object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "nawana",
            // A conversation has no timeline to scrub.
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    /// Take the call off the lock screen. Idempotent — every close path calls
    /// it, and `tearDown()` may already have.
    static func end() {
        guard isActive else { return }
        isActive = false
        isPlaying = false
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
