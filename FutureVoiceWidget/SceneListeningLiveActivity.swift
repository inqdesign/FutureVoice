import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A situation playing, live: the line being said and who says it, in the
/// Dynamic Island and on the lock screen. Compact, it is a waveform and the
/// place in the list; expanded, the caption and play/pause · next.
struct SceneListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SceneListeningAttributes.self) { context in
            LockScreenSceneView(state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.position)/\(context.state.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.isFluentSelf ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.line)
                            .font(.body)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text(context.state.sceneTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            SceneControls(isPlaying: context.state.isPlaying)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: context.state.isPlaying)
            } compactTrailing: {
                Text("\(context.state.position)/\(context.state.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct LockScreenSceneView: View {
    let state: SceneListeningAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isFluentSelf ? Color.accentColor : .secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(state.position)/\(state.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(state.line)
                .font(.body)
                .lineLimit(3)
            HStack {
                Text(state.sceneTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                SceneControls(isPlaying: state.isPlaying)
            }
        }
    }
}

private struct SceneControls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 18) {
            Button(intent: ToggleScenePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button(intent: NextScenePlaybackIntent()) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .font(.title3)
    }
}
