import CoreGraphics
import Foundation

/// How the prompter column moves, frame by frame — pure, so it can be driven
/// by a test as well as by the display clock (`PrompterScroller`).
///
/// FOLLOWING THE VOICE moves at the reader's SPEED, not to the reader's last
/// known spot. The recognizer reports where they are in bursts — a few words
/// every half second to a second, Korean later still — and every earlier
/// version that chased those reports glided to each one and stopped, which
/// read as the text jerking along (founder, 2026-10-05, after three tries:
/// a learned pace with a hard stop at the line, then a pure ease to the
/// spot). So: the reader's pace is a running average of how fast their
/// reported spot advances; while they speak, the text moves at that pace,
/// a little faster when it has fallen behind the spot and a little slower
/// when it is ahead; when they stop speaking it eases to a stop. The report
/// steers the speed and never moves the text by itself.
struct PrompterMotion {
    struct Input {
        var recording: Bool
        var follow: Bool
        var speed: CGFloat
        var speaking: Bool
        var held: Bool
    }

    /// How far the column has risen, in its own points.
    private(set) var position: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    /// The reader's pace, in column points per second.
    private(set) var pace: CGFloat = 0

    /// The language's ordinary reading pace in column points per second —
    /// where following starts, and the band the reader's pace is kept in.
    var plannedPace: CGFloat = 0

    private(set) var target: CGFloat = 0
    private var lastTarget: CGFloat = 0
    private var lineTop: CGFloat = .greatestFiniteMagnitude
    private(set) var lineAdvance: CGFloat = 40

    /// Seconds the reader's pace is averaged over.
    static let paceWindow: CGFloat = 3
    /// Seconds a change of speed takes.
    static let speedWindow: CGFloat = 0.35
    /// Speed added per line the text trails the reader (and taken away per
    /// line it leads), as a share of their pace.
    static let pullPerLine: CGFloat = 0.8
    static let maxFactor: CGFloat = 2.2

    /// Where the reader is (their word's line, and how far across it), and
    /// the line they're on.
    mutating func setTarget(_ y: CGFloat, lineTop: CGFloat, lineAdvance: CGFloat) {
        if lineAdvance > 0 { self.lineAdvance = lineAdvance }
        self.lineTop = lineTop
        target = y
    }

    /// Back onto the reader's spot, at rest.
    mutating func snap() {
        position = target
        lastTarget = target
        velocity = 0
        pace = 0
    }

    mutating func step(dt: CGFloat, _ input: Input) {
        guard dt > 0 else { return }
        let planned = plannedPace > 0 ? plannedPace : lineAdvance / 2
        var wanted: CGFloat = 0

        if !input.recording {
            wanted = 0
        } else if !input.follow {
            // Steady speed: exactly that — eased, so a press-and-hold stops
            // it gently and letting go starts it again.
            wanted = input.held ? 0 : planned * input.speed
        } else {
            if pace == 0 { pace = planned }
            // The spot's advance, averaged: a burst of three words is the
            // same total as three single words, and the average turns either
            // into one speed.
            let advance = max(0, target - lastTarget)
            if input.speaking {
                pace += (advance / dt - pace) * min(1, dt / Self.paceWindow)
                pace = min(max(pace, planned * 0.5), planned * 2)
            }
            let linesBehind = (target - position) / max(1, lineAdvance)
            let factor = min(max(1 + Self.pullPerLine * linesBehind, 0), Self.maxFactor)
            wanted = input.speaking ? pace * factor : 0
        }
        lastTarget = target

        velocity += (wanted - velocity) * min(1, dt / Self.speedWindow)
        var next = position + max(0, velocity) * dt
        // Safety: the line being read never goes above the top of the
        // prompter (its top may rise at most one line over its rest place).
        // Normal following never reaches this — the pull slows the text well
        // before — so it never turns into a stop-and-wait.
        if input.recording, input.follow {
            next = min(next, max(position, lineTop + lineAdvance))
        }
        position = next
    }
}
