import SwiftUI

/// Trimmer-style player for the shadow target line. The loop region shows as a
/// band with grabbable START and END handles (like a video trimmer), so it's
/// obvious where the loop begins and ends and easy to nudge. Selection is a
/// WORD-INDEX range shared with the target-line text, so editing either side
/// keeps them in sync and the loop tracks it live. Drives the parent's
/// AudioPlayer so karaoke highlighting follows playback.
struct ShadowTimelinePlayer: View {
    let audioURL: URL
    let timings: [WordTiming]
    @Binding var selectedWordRange: ClosedRange<Int>?
    @ObservedObject var player: AudioPlayer

    @State private var loop = false
    @State private var playbackRate: Float = 1.0
    @State private var dragMode: DragMode?
    @State private var scrubStartX: CGFloat = 0

    private enum DragMode { case start, end, scrub }
    private static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25]

    private static let trackHeight: CGFloat = 54
    private static let handleW: CGFloat = 14
    private static let grabRadius: CGFloat = 24

    private var markerTimes: [Double] { timings.map { Double($0.startMs) / 1000.0 } }

    private var selectionTimes: (start: Double, end: Double)? {
        guard let r = selectedWordRange,
              r.lowerBound >= 0, r.upperBound < timings.count else { return nil }
        return (Double(timings[r.lowerBound].startMs) / 1000.0,
                Double(timings[r.upperBound].endMs) / 1000.0)
    }

    var body: some View {
        VStack(spacing: 12) {
            timeline
            labels
            controls
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear {
            guard !player.isPlaying, let data = try? Data(contentsOf: audioURL) else { return }
            player.prepare(data, forceSessionReset: true)
        }
        .onDisappear { player.stop() }
        .onChange(of: selectedWordRange) { _, _ in
            if player.isPlaying, let s = selectionTimes {
                player.updateSegment(from: s.start, to: s.end)
            }
        }
    }

    // MARK: - Timeline (trimmer)

    private var timeline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(player.duration, 0.01)
            let sel = selectionTimes
            let sx = sel.map { CGFloat($0.start / dur) * w }
            let ex = sel.map { CGFloat($0.end / dur) * w }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: Self.trackHeight)

                ForEach(Array(markerTimes.enumerated()), id: \.offset) { _, t in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 1.5, height: 16)
                        .offset(x: CGFloat(t / dur) * w)
                }

                if let sx, let ex {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: max(0, ex - sx), height: Self.trackHeight)
                        .offset(x: sx)
                    handle(at: sx)
                    handle(at: ex)
                }

                // Playhead
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2.5, height: Self.trackHeight + 8)
                    .offset(x: max(0, min(w - 2.5, CGFloat(player.currentTime / dur) * w)))
                    .shadow(color: Color(.systemBackground), radius: 1)
            }
            .frame(height: Self.trackHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(w: w, dur: dur, sx: sx, ex: ex))
        }
        .frame(height: Self.trackHeight)
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .frame(width: Self.handleW, height: Self.trackHeight)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: 16)
            )
            .offset(x: x - Self.handleW / 2)
    }

    private func dragGesture(w: CGFloat, dur: Double, sx: CGFloat?, ex: CGFloat?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragMode == nil {
                    if let sx, abs(g.startLocation.x - sx) < Self.grabRadius {
                        dragMode = .start
                    } else if let ex, abs(g.startLocation.x - ex) < Self.grabRadius {
                        dragMode = .end
                    } else {
                        dragMode = .scrub
                        scrubStartX = g.startLocation.x
                    }
                }
                switch dragMode {
                case .start: moveHandle(isStart: true, x: g.location.x, w: w, dur: dur)
                case .end:   moveHandle(isStart: false, x: g.location.x, w: w, dur: dur)
                case .scrub: selectRange(from: scrubStartX, to: g.location.x, w: w, dur: dur)
                case .none:  break
                }
            }
            .onEnded { g in
                if dragMode == .scrub, abs(g.translation.width) < 6 {
                    // Tap → select the word under the tap + move the playhead.
                    let t = time(at: g.location.x, w: w, dur: dur)
                    if let i = wordIndex(at: t) { selectedWordRange = i...i }
                    player.seek(to: t)
                }
                dragMode = nil
            }
    }

    // MARK: - Labels & controls

    private var labels: some View {
        HStack {
            Text(timeLabel(player.currentTime))
            Spacer()
            if let s = selectionTimes {
                Text("loop \(timeLabel(s.start))–\(timeLabel(s.end))")
                    .foregroundStyle(.tint)
            } else {
                Text("full line")
            }
            Spacer()
            Text(timeLabel(player.duration))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button { togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            Button { loop.toggle(); player.setLoopEnabled(loop) } label: {
                Image(systemName: loop ? "repeat.circle.fill" : "repeat.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(loop ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            speedMenu

            Button { selectedWordRange = nil } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedWordRange == nil ? Color(.tertiaryLabel) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(selectedWordRange == nil)
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $playbackRate) {
                ForEach(Self.speeds, id: \.self) { r in
                    Text(speedLabel(r)).tag(r)
                }
            }
        } label: {
            Text(speedLabel(playbackRate))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(playbackRate == 1.0 ? Color.secondary : Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .onChange(of: playbackRate) { _, r in player.setRate(r) }
    }

    private func speedLabel(_ r: Float) -> String {
        r == 1.0 ? "1×" : String(format: "%g×", r)
    }

    // MARK: - Logic

    private func togglePlay() {
        if player.isPlaying { player.pause(); return }
        // A finished whole-file play releases the player; reload before replay.
        if !player.isLoaded, let data = try? Data(contentsOf: audioURL) {
            player.prepare(data)
            player.setRate(playbackRate)
        }
        if let s = selectionTimes {
            player.playSegment(from: s.start, to: s.end, loop: loop)
        } else {
            let start = player.currentTime < player.duration - 0.05 ? player.currentTime : 0
            player.playSegment(from: start, to: nil, loop: loop)
        }
    }

    private func moveHandle(isStart: Bool, x: CGFloat, w: CGFloat, dur: Double) {
        let t = time(at: x, w: w, dur: dur)
        guard let i = wordIndex(at: t) else { return }
        let r = selectedWordRange ?? i...i
        if isStart {
            selectedWordRange = min(i, r.upperBound)...r.upperBound
        } else {
            selectedWordRange = r.lowerBound...max(i, r.lowerBound)
        }
    }

    private func selectRange(from x0: CGFloat, to x1: CGFloat, w: CGFloat, dur: Double) {
        let a = time(at: x0, w: w, dur: dur)
        let b = time(at: x1, w: w, dur: dur)
        guard let i = wordIndex(at: min(a, b)), let j = wordIndex(at: max(a, b)) else { return }
        selectedWordRange = min(i, j)...max(i, j)
    }

    private func wordIndex(at t: Double) -> Int? {
        guard !timings.isEmpty else { return nil }
        for (i, wt) in timings.enumerated()
        where t >= Double(wt.startMs) / 1000.0 && t <= Double(wt.endMs) / 1000.0 {
            return i
        }
        return timings.enumerated().min(by: {
            abs(Double($0.element.startMs) / 1000.0 - t) < abs(Double($1.element.startMs) / 1000.0 - t)
        })?.offset
    }

    private func time(at x: CGFloat, w: CGFloat, dur: Double) -> Double {
        guard w > 0 else { return 0 }
        return max(0, min(dur, Double(x / w) * dur))
    }

    private func timeLabel(_ s: Double) -> String {
        String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}
