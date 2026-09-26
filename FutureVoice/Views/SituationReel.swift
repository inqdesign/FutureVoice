import SwiftUI

/// Example situations rolling slowly past the empty situation box.
///
/// Two jobs, and the second is the reason it moves. It answers "what do I
/// even put here" for someone facing a blank field — and because every line
/// is written at the length the field is asking for, it shows what "the more
/// detail, the better" actually means far better than the sentence saying so.
/// A static list of three would do the first job; a reel does the second,
/// because the variety IS the point: this box takes anything, not a category.
///
/// Touch FREEZES the roll and lifting picks the line the finger landed on.
/// Without that it would be a moving tap target, which is the usual reason a
/// marquee is the wrong control — the freeze is what makes it a control at
/// all. The hit test reads `startLocation` against the offset held at
/// touch-down, so the line that was under the finger is the line that lands,
/// never the one that scrolled into its place.
///
/// Under Reduce Motion nothing moves: the same lines sit still, and the
/// picking works identically.
struct SituationReel: View {
    let lines: [String]
    let onPick: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One example's slot. Two lines of body text fit; a third would mean
    /// the example is longer than the situation it is demonstrating.
    private let rowHeight: CGFloat = 80
    private let visibleRows = 3
    /// How long one example takes to cross its own height. This is a thing
    /// to READ, not a ticker: at 2.2s a line was gone before it had been
    /// taken in, and a finger reaching for it arrived late.
    private let secondsPerRow: TimeInterval = 4.5
    private var speed: CGFloat { rowHeight / CGFloat(secondsPerRow) }

    @State private var start = Date()
    /// Total time spent frozen, so resuming never jumps.
    @State private var pausedTotal: TimeInterval = 0
    @State private var pauseBegan: Date?
    /// The offset held while a finger is down — also what the hit test reads.
    @State private var frozenOffset: CGFloat?

    private var loopHeight: CGFloat { rowHeight * CGFloat(max(lines.count, 1)) }

    var body: some View {
        Group {
            if reduceMotion || lines.isEmpty {
                still
            } else {
                rolling
            }
        }
        .frame(height: rowHeight * CGFloat(visibleRows))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Example situations")
    }

    // MARK: - Still (Reduce Motion, or nothing to roll)

    private var still: some View {
        VStack(spacing: 0) {
            ForEach(lines.prefix(visibleRows), id: \.self) { line in
                Button { onPick(line) } label: { row(line) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rolling

    private var rolling: some View {
        TimelineView(.animation) { context in
            let offset = frozenOffset ?? wrappedOffset(at: context.date)
            VStack(spacing: 0) {
                // Twice through, so the seam is always off-screen.
                ForEach(0..<(lines.count * 2), id: \.self) { i in
                    row(lines[i % lines.count])
                }
            }
            .offset(y: -offset)
            .frame(height: rowHeight * CGFloat(visibleRows), alignment: .top)
            .clipped()
            .mask(
                LinearGradient(colors: [.clear, .black, .black, .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard frozenOffset == nil else { return }
                        frozenOffset = wrappedOffset(at: Date())
                        pauseBegan = Date()
                    }
                    .onEnded { value in
                        let held = frozenOffset ?? 0
                        // Only a TAP picks. A drag was the learner scrolling
                        // the page, and picking on it would fill the field
                        // from a gesture that meant nothing of the kind.
                        if abs(value.translation.height) < 12,
                           abs(value.translation.width) < 12 {
                            let y = held + value.startLocation.y
                            let index = Int(floor(y / rowHeight)) % lines.count
                            onPick(lines[(index + lines.count) % lines.count])
                        }
                        if let began = pauseBegan {
                            pausedTotal += Date().timeIntervalSince(began)
                            pauseBegan = nil
                        }
                        frozenOffset = nil
                    }
            )
        }
    }

    private func wrappedOffset(at date: Date) -> CGFloat {
        let frozen = pauseBegan.map { date.timeIntervalSince($0) } ?? 0
        let elapsed = date.timeIntervalSince(start) - pausedTotal - frozen
        guard elapsed > 0, loopHeight > 0 else { return 0 }
        return (CGFloat(elapsed) * speed).truncatingRemainder(dividingBy: loopHeight)
    }

    private func row(_ line: String) -> some View {
        Text(line)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .padding(.horizontal, 24)
    }
}
