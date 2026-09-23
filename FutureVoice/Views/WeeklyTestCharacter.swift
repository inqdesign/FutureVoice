import SwiftUI

/// The fluent self as the test's host: two pixel eyes on a soft disc, and
/// nothing else. Each eye is ONE cell of the app's 12.8 pt lattice — a
/// single pixel, moved and blinked with smooth motion rather than
/// re-rasterised (user decision, 2026-09-23, after a mosaic background in
/// colour and in grey, and a sub-pixel rasterised eye, were all tried and
/// set aside the same day). The eyes carry the whole expression: no mouth,
/// no brows.
///
/// It waits by glancing around and blinking; a right answer lifts the eyes
/// with a quick flutter of blinks and a bounce; a wrong one drops them, half-lidded;
/// a second wrong in a row narrows and slants them inward for a moment (a
/// pout at itself, never a scold); while a test is being written they sweep
/// left and right. Everything is the same two pixels, moved, squeezed and
/// tilted — no extra strokes.
struct WeeklyTestCharacter: View {
    /// `happy` is a right answer, `sad` a wrong one, `angry` the second wrong
    /// in a row — a pout at itself, brief, never a scold at the learner.
    enum Mood: Equatable { case thinking, waiting, happy, sad, angry }

    var mood: Mood
    /// When `mood` began — the ease-in and the verdict blinks run from here.
    var since: Date
    /// The tile's fill. On a plain page the secondary background reads as a
    /// soft tile; on a grouped page (the result List) it vanishes into the
    /// page, so that surface passes the grouped secondary instead.
    var tile: Color = Color(.secondarySystemBackground)

    /// The app's fixed pixel scale (`FutureselfPixels.cell`).
    static let cell: CGFloat = 12.8
    /// Six cells across: a cell of margin around the eyes.
    static let cells = 6
    static var size: CGFloat { cell * CGFloat(cells) }
    /// How long a change of mood takes to arrive on the face.
    static let ease: Double = 0.28
    /// A shut eye is a line this tall, never nothing — an eye that vanishes
    /// reads as a glitch, one that closes reads as a blink.
    static let closedHeight: CGFloat = 2.5

    /// The eye's outline. A square cell read as a square, not a face, and a
    /// round bean on a round disc read as someone else's robot — so the eye
    /// is a pixel stretched tall (0.82 × 1.12 cells) with corners kept
    /// squarish, on a rounded-square TILE like a cell of the app's mosaic
    /// rather than a circle (user decisions, 2026-09-23). Variants stay
    /// behind a debug flag so the choice can be re-made by eye.
    enum Shape: Int { case squircle = 0, tall, round }
    static var shape: Shape {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "eyeshape"), let n = Int(raw),
           let v = Shape(rawValue: n) { return v }
        #endif
        return .tall
    }
    /// The backdrop's corner radius — a tile, not a disc.
    static let tileRadius: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let elapsed = context.date.timeIntervalSince(since)
            let pose = pose(t: t, elapsed: elapsed)
            ZStack {
                RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
                    .fill(tile)
                Canvas(rendersAsynchronously: false) { ctx, _ in
                    let (w, openH, radius): (CGFloat, CGFloat, CGFloat) = switch Self.shape {
                        case .squircle: (Self.cell, Self.cell, 5.2)
                        case .tall: (Self.cell * 0.82, Self.cell * 1.12, 3.4)
                        case .round: (Self.cell, Self.cell, Self.cell / 2)
                    }
                    for eye in [pose.left, pose.right] {
                        let fullH = openH * CGFloat(eye.scaleY)
                        let h = max(Self.closedHeight, fullH - (fullH - Self.closedHeight) * CGFloat(eye.lid))
                        let ew = w * CGFloat(eye.scaleX)
                        let rect = CGRect(x: -ew / 2, y: -h / 2, width: ew, height: h)
                        // The corner radius closes with the lid, so the shut
                        // line is a capsule and not two clipped arcs.
                        let r = min(radius, h / 2)
                        var path = Path(roundedRect: rect, cornerRadius: r)
                        path = path.applying(CGAffineTransform(translationX: eye.center.x, y: eye.center.y)
                            .rotated(by: eye.tilt))
                        ctx.fill(path, with: .color(ink))
                    }
                }
            }
            .frame(width: Self.size, height: Self.size)
        }
        .frame(width: Self.size, height: Self.size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Eyes

    private var ink: Color {
        colorScheme == .dark ? Color(white: 0.96) : Color(white: 0.10)
    }

    /// One eye, in points inside the tile.
    struct Eye {
        var center: CGPoint
        /// 0 open … 1 closed.
        var lid: Double = 0
        /// Height and width against the open shape: a squint is short and
        /// wide, a glare short and narrow.
        var scaleY: Double = 1
        var scaleX: Double = 1
        /// Rotation in radians, positive = clockwise. Inner corners down
        /// reads as anger, inner corners up as worry.
        var tilt: Double = 0
        static func mix(_ a: Eye, _ b: Eye, _ k: Double) -> Eye {
            Eye(center: CGPoint(x: a.center.x + (b.center.x - a.center.x) * k,
                                y: a.center.y + (b.center.y - a.center.y) * k),
                lid: a.lid + (b.lid - a.lid) * k,
                scaleY: a.scaleY + (b.scaleY - a.scaleY) * k,
                scaleX: a.scaleX + (b.scaleX - a.scaleX) * k,
                tilt: a.tilt + (b.tilt - a.tilt) * k)
        }
    }

    struct Pose {
        var left: Eye
        var right: Eye
        static func mix(_ a: Pose, _ b: Pose, _ k: Double) -> Pose {
            Pose(left: .mix(a.left, b.left, k), right: .mix(a.right, b.right, k))
        }
    }

    /// Where the eyes rest: two cells apart (one cell of gap between them),
    /// a little above the disc's centre. Three cells apart read as far
    /// apart (user, 2026-09-23).
    static let eyeSpacing: CGFloat = 2
    private static let restLeft = CGPoint(x: size / 2 - cell * eyeSpacing / 2, y: cell * 2.5)
    private static let restRight = CGPoint(x: size / 2 + cell * eyeSpacing / 2, y: cell * 2.5)

    /// `offset` is in CELLS; a glance of one cell is a glance of one pixel.
    /// `tilt` is applied mirrored, so the two eyes slant toward each other.
    /// `apart` moves the eyes toward (negative) or away from each other, in cells.
    private static func pose(offset: CGPoint, lid: Double = 0, scaleY: Double = 1, scaleX: Double = 1,
                             tilt: Double = 0, apart: Double = 0) -> Pose {
        let d = CGPoint(x: offset.x * cell, y: offset.y * cell)
        let a = CGFloat(apart) * cell / 2
        return Pose(left: Eye(center: CGPoint(x: restLeft.x + d.x - a, y: restLeft.y + d.y), lid: lid,
                              scaleY: scaleY, scaleX: scaleX, tilt: tilt),
                    right: Eye(center: CGPoint(x: restRight.x + d.x + a, y: restRight.y + d.y), lid: lid,
                               scaleY: scaleY, scaleX: scaleX, tilt: -tilt))
    }

    /// The face at this instant: the mood's pose eased in from the neutral
    /// glance over `ease` seconds, so a verdict arrives as a movement.
    private func pose(t: TimeInterval, elapsed: TimeInterval) -> Pose {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "eyelid"), let forced = Double(raw) {
            return Self.pose(offset: .zero, lid: forced)
        }
        if let raw = UserDefaults.standard.string(forKey: "moodhold") {
            // Freeze a mood at its settled pose (a screenshot can't wait).
            let held: Mood? = ["happy": .happy, "sad": .sad, "angry": .angry][raw]
            if let held { return Self.settled(held) }
        }
        #endif
        let neutral = Self.pose(offset: Self.gaze(t: t), lid: Self.blink(t: t, every: 3.8, seed: 0))
        let k = Self.smooth(elapsed / Self.ease)
        switch mood {
        case .waiting:
            return neutral

        case .thinking:
            // Sweep left and right, a cell each way.
            let target = Self.pose(offset: CGPoint(x: sin(t * 1.4), y: 0),
                                   lid: Self.blink(t: t, every: 5.0, seed: 3.1))
            return .mix(neutral, target, k)

        case .happy:
            // Delight: the eyes rise and flutter — three quick blinks while
            // they climb, a small damped bounce, then they hold open, high.
            // (A squint read as sleepy, not glad — user, 2026-09-23.)
            let flutter = max(Self.pulse(elapsed - 0.10, up: 0.06, hold: 0.04, down: 0.08),
                              Self.pulse(elapsed - 0.36, up: 0.06, hold: 0.04, down: 0.08),
                              Self.pulse(elapsed - 0.62, up: 0.06, hold: 0.04, down: 0.08))
            let bounce = elapsed < 1.4 ? -0.18 * sin(elapsed * 8) * exp(-elapsed * 2.6) : 0
            var target = Self.settled(.happy)
            target.left.lid = flutter
            target.right.lid = flutter
            target.left.center.y += CGFloat(bounce) * Self.cell
            target.right.center.y += CGFloat(bounce) * Self.cell
            return .mix(neutral, target, k)

        case .sad:
            // Half-lidded, looking down, inner corners up; one slow blink
            // after a beat.
            let slow = Self.pulse(elapsed - 0.7, up: 0.15, hold: 0.2, down: 0.2)
            var target = Self.settled(.sad)
            target.left.lid = max(target.left.lid, slow)
            target.right.lid = max(target.right.lid, slow)
            return .mix(neutral, target, k)

        case .angry:
            // Narrowed, slanted inward, pulled a little closer — and a quick
            // shake as it lands, then it holds.
            let shake = elapsed < 0.5 ? 0.12 * sin(elapsed * 40) * exp(-elapsed * 7) : 0
            var target = Self.settled(.angry)
            target.left.center.x += CGFloat(shake) * Self.cell
            target.right.center.x += CGFloat(shake) * Self.cell
            return .mix(neutral, target, k)
        }
    }

    /// Each mood's resting face.
    private static func settled(_ mood: Mood) -> Pose {
        switch mood {
        case .happy:
            return pose(offset: CGPoint(x: 0, y: -0.6))
        case .sad:
            // Long and low, inner corners up: a droop, not a stub (user, 2026-09-23).
            return pose(offset: CGPoint(x: 0, y: 0.6), lid: 0.15, scaleY: 0.6, scaleX: 1.45, tilt: -0.2)
        case .angry:
            // Long and thin: a glare is a slit, not a block (user, 2026-09-23).
            return pose(offset: CGPoint(x: 0, y: 0.1), scaleY: 0.34, scaleX: 1.55, tilt: 0.36, apart: -0.3)
        case .waiting, .thinking:
            return pose(offset: .zero)
        }
    }

    // MARK: - Timing

    /// Lid 0…1 for a blink that recurs roughly `every` seconds — shut for
    /// about a tenth of a second, with an occasional double blink.
    private static func blink(t: TimeInterval, every: Double, seed: Double) -> Double {
        let period = every * (0.75 + 0.5 * hash((t / every).rounded(.down) + seed))
        let phase = t.truncatingRemainder(dividingBy: period)
        let first = pulse(phase, up: 0.08, hold: 0.07, down: 0.11)
        let double = hash((t / every).rounded(.down) + seed + 9) < 0.25
            ? pulse(phase - 0.34, up: 0.08, hold: 0.07, down: 0.11) : 0
        return max(first, double)
    }

    /// One 0→1→0 movement starting at x = 0.
    private static func pulse(_ x: Double, up: Double, hold: Double, down: Double) -> Double {
        if x < 0 { return 0 }
        if x < up { return smooth(x / up) }
        if x < up + hold { return 1 }
        if x < up + hold + down { return 1 - smooth((x - up - hold) / down) }
        return 0
    }

    /// Where the eyes look while waiting, in cells: a new target every
    /// ~1.6 s, eased to over a quarter second.
    private static func gaze(t: TimeInterval) -> CGPoint {
        let hold = 1.6
        let segment = (t / hold).rounded(.down)
        func target(_ seg: Double) -> CGPoint {
            let h1 = hash(seg + 0.5), h2 = hash(seg + 17.3)
            // Mostly centre, sometimes a cell to a side, rarely up.
            let dx = [-1.0, -0.5, 0, 0, 0, 0.5, 1][Int(h1 * 7) % 7]
            let dy = h2 < 0.15 ? -0.5 : (h2 > 0.9 ? 0.25 : 0)
            return CGPoint(x: dx, y: dy)
        }
        let from = target(segment - 1), to = target(segment)
        let k = smooth((t - segment * hold) / 0.25)
        return CGPoint(x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k)
    }

    private static func smooth(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v * v * (3 - 2 * v)
    }

    private static func hash(_ x: Double) -> Double {
        let v = sin(x * 12.9898 + 78.233) * 43758.5453
        return v - v.rounded(.down)
    }
}
