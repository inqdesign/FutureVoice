import SwiftUI

/// Layout constants for the trimmer. Kept OUTSIDE the (now generic) player —
/// generic types can't hold static stored properties.
private enum TLConst {
    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25]
    static let trackHeight: CGFloat = 54
    static let handleW: CGFloat = 14
    static let grabRadius: CGFloat = 24
    static let minTimeSelection: Double = 0.2
}

/// Trimmer-style player for the shadow target line. The loop region shows as a
/// band with grabbable START and END handles (like a video trimmer), so it's
/// obvious where the loop begins and ends and easy to nudge. Selection is a
/// WORD-INDEX range shared with the target-line text, so editing either side
/// keeps them in sync and the loop tracks it live. Drives the parent's
/// AudioPlayer so karaoke highlighting follows playback.
struct ShadowTimelinePlayer<MicControl: View>: View {
    let audioURL: URL
    let timings: [WordTiming]
    @Binding var selectedWordRange: ClosedRange<Int>?
    @ObservedObject var player: AudioPlayer
    /// The parent's mic/record control, dropped into the transport row between
    /// the loop toggle and the speed menu so the primary action shares the
    /// row instead of owning a whole block below (which crowded the analysis).
    private let micControl: MicControl

    init(audioURL: URL,
         timings: [WordTiming],
         selectedWordRange: Binding<ClosedRange<Int>?>,
         player: AudioPlayer,
         @ViewBuilder micControl: () -> MicControl) {
        self.audioURL = audioURL
        self.timings = timings
        self._selectedWordRange = selectedWordRange
        self.player = player
        self.micControl = micControl()
    }

    @State private var loop = false
    @State private var playbackRate: Float = 1.0
    @State private var dragMode: DragMode?
    @State private var scrubStartX: CGFloat = 0
    /// Time-based loop selection (seconds) — the fallback when this line has
    /// no word timings (e.g. they'd cost credits the user doesn't have).
    /// Playback is pure time-based either way; words only add snapping.
    @State private var timeSelection: ClosedRange<Double>?

    private enum DragMode { case start, end, scrub }

    private var markerTimes: [Double] { timings.map { Double($0.startMs) / 1000.0 } }

    private var selectionTimes: (start: Double, end: Double)? {
        if let r = selectedWordRange,
           r.lowerBound >= 0, r.upperBound < timings.count {
            return (Double(timings[r.lowerBound].startMs) / 1000.0,
                    Double(timings[r.upperBound].endMs) / 1000.0)
        }
        if timings.isEmpty, let t = timeSelection {
            return (t.lowerBound, t.upperBound)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            timeline
            labels
            controls
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear {
            guard !player.isPlaying, let data = try? Data(contentsOf: audioURL) else { return }
            player.prepare(data, forceSessionReset: true)
            // Default to the whole line selected: visible handles teach at a
            // glance that the loop region is adjustable, and "loop the full
            // line" is the most common starting point anyway.
            if selectedWordRange == nil && timeSelection == nil {
                if timings.isEmpty {
                    timeSelection = 0...max(player.duration, TLConst.minTimeSelection)
                } else {
                    selectedWordRange = 0...(timings.count - 1)
                }
            }
        }
        .onDisappear { player.stop() }
        .onChange(of: selectedWordRange) { _, _ in
            if player.isPlaying, let s = selectionTimes {
                player.updateSegment(from: s.start, to: s.end)
            }
        }
        .onChange(of: timeSelection) { _, _ in
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
                    .frame(height: TLConst.trackHeight)

                ForEach(Array(markerTimes.enumerated()), id: \.offset) { _, t in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.30))
                        .frame(width: 1.5, height: 16)
                        .offset(x: CGFloat(t / dur) * w)
                }

                if let sx, let ex {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: max(0, ex - sx), height: TLConst.trackHeight)
                        .offset(x: sx)
                    handle(at: sx)
                    handle(at: ex)
                }

                // Playhead
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2.5, height: TLConst.trackHeight + 8)
                    .offset(x: max(0, min(w - 2.5, CGFloat(player.currentTime / dur) * w)))
                    .shadow(color: Color(.systemBackground), radius: 1)
            }
            .frame(height: TLConst.trackHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(w: w, dur: dur, sx: sx, ex: ex))
        }
        .frame(height: TLConst.trackHeight)
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .frame(width: TLConst.handleW, height: TLConst.trackHeight)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: 16)
            )
            .offset(x: x - TLConst.handleW / 2)
    }

    private func dragGesture(w: CGFloat, dur: Double, sx: CGFloat?, ex: CGFloat?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragMode == nil {
                    if let sx, abs(g.startLocation.x - sx) < TLConst.grabRadius {
                        dragMode = .start
                    } else if let ex, abs(g.startLocation.x - ex) < TLConst.grabRadius {
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
                    // Tap → just move the playhead. It must NOT touch the
                    // selection: collapsing to the tapped word silently turned
                    // the NEXT mic attempt into a one-word shadow ("the
                    // karaoke stops at the first word"). Selecting stays an
                    // explicit gesture — drag on the track, or tap words on
                    // the target line.
                    player.seek(to: time(at: g.location.x, w: w, dur: dur))
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
        // Mic is CENTERED to the row via an overlay, not squeezed between the
        // side groups — the speed pill's variable width would otherwise shove
        // it off-center. Play/loop hug the left, speed/clear hug the right.
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

            Spacer(minLength: 72)

            speedMenu

            Button { selectedWordRange = nil; timeSelection = nil } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(selectionTimes == nil ? Color(.tertiaryLabel) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(selectionTimes == nil)
        }
        .overlay { micControl }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $playbackRate) {
                ForEach(TLConst.speeds, id: \.self) { r in
                    Text(speedLabel(r)).tag(r)
                }
            }
        } label: {
            Text(speedLabel(playbackRate))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                // Primary (not secondary) at 1× — on the dark pill the muted
                // gray was near-invisible, so the label looked blank; accent
                // still marks a changed speed.
                .foregroundStyle(playbackRate == 1.0 ? Color.primary : Color.accentColor)
                .padding(.horizontal, 12)
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
        if timings.isEmpty {
            let r = timeSelection ?? t...t
            timeSelection = isStart
                ? min(t, r.upperBound - TLConst.minTimeSelection)...r.upperBound
                : r.lowerBound...max(t, r.lowerBound + TLConst.minTimeSelection)
            return
        }
        guard let i = wordIndex(at: t) else { return }
        let r = selectedWordRange ?? i...i
        if isStart {
            selectedWordRange = min(i, r.upperBound)...r.upperBound
        } else {
            selectedWordRange = r.lowerBound...max(i, r.lowerBound)
        }
    }

    /// Smallest useful time-based loop — avoids zero-width selections that
    /// would stutter the player.

    private func selectRange(from x0: CGFloat, to x1: CGFloat, w: CGFloat, dur: Double) {
        let a = time(at: x0, w: w, dur: dur)
        let b = time(at: x1, w: w, dur: dur)
        if timings.isEmpty {
            let lo = min(a, b), hi = max(a, b)
            if hi - lo >= TLConst.minTimeSelection { timeSelection = lo...hi }
            return
        }
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
