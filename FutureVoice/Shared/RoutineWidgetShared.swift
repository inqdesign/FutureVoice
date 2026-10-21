import SwiftUI

/// The routine widget's day and its card. Shared with the app so the card
/// can be rendered in the design-review gallery (`-capture widget-routine`);
/// the extension can't be screenshotted headlessly.
extension RoutineWidgetSnapshot {
    /// The blocks of the day `date` falls on. Past midnight `tomorrow`
    /// becomes today, so the widget keeps going until the app next writes.
    func blocks(at date: Date) -> [RoutineWidgetBlock] {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: day) { return today }
        if let next = cal.date(byAdding: .day, value: 1, to: day),
           cal.isDate(date, inSameDayAs: next) { return tomorrow }
        return []
    }

    /// The block whose time is on.
    func now(at date: Date) -> RoutineWidgetBlock? {
        blocks(at: date).first { $0.isNow(at: date) }
    }

    /// The next timed block still to come, else an anytime one not done,
    /// else one whose time passed undone — done any time that day still
    /// counts (`PlannerDay.progress`), so it is still on the day.
    func next(at date: Date) -> RoutineWidgetBlock? {
        let b = blocks(at: date)
        return b.first { !$0.done && !$0.anytime && $0.start > date }
            ?? b.first { !$0.done && $0.anytime }
            ?? b.first { !$0.done }
    }

    /// Tomorrow's first block — what an empty or finished day points at.
    func tomorrowFirst(at date: Date) -> RoutineWidgetBlock? {
        Calendar.current.isDate(date, inSameDayAs: day) ? tomorrow.first : nil
    }

    /// What a tap on the whole widget opens: the block due or next.
    func deepLink(at date: Date) -> URL? {
        (now(at: date) ?? next(at: date))?.deepLink ?? URL(string: "futurevoice://routine")
    }
}

/// 24-hour, like Activity's day list.
func routineClock(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
}

/// Small: the one thing that matters now. Medium: the day as a list, with
/// now marked.
struct RoutineCard: View {
    var theme: Int = 0
    let snapshot: RoutineWidgetSnapshot
    let date: Date
    var compact: Bool = false

    private var vivid: Color { WidgetTheme.vivid(theme) }
    private var snap: RoutineWidgetSnapshot { snapshot }
    private var blocks: [RoutineWidgetBlock] { snap.blocks(at: date) }
    private var nowBlock: RoutineWidgetBlock? { snap.now(at: date) }
    private var nextBlock: RoutineWidgetBlock? { snap.next(at: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if compact {
                Spacer(minLength: 0)
                hero
            } else if blocks.isEmpty {
                Spacer(minLength: 0)
                dayOver
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleRows, id: \.id) { row($0) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var header: some View {
        Text(snap.label("title"))
            .font(pixelFont(12))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }

    /// Every state of the small widget is the same three lines — icon,
    /// one large line, one caption — so only the words change.
    @ViewBuilder
    private var hero: some View {
        if let b = nowBlock {
            // The block's name stays; the state is the caption.
            heroLayout(symbol: b.symbol, tint: routineTint(b.kind),
                       main: b.title, caption: b.nowLine)
        } else if let b = nextBlock {
            let when = b.anytime ? snap.label("anytime")
                : "\(snap.label(b.start <= date ? "today" : "next")) · \(routineClock(b.start))"
            heroLayout(symbol: b.symbol, tint: routineTint(b.kind), main: b.title, caption: when)
        } else {
            dayOver
        }
    }

    /// Nothing left today. Still a block's name on top, the state below:
    /// a finished day shows its last block, a rest day tomorrow's first.
    /// Only a day with nothing planned anywhere has no block to name.
    @ViewBuilder
    private var dayOver: some View {
        if let last = blocks.last {
            heroLayout(symbol: last.symbol, tint: routineTint(last.kind),
                       main: last.title, caption: snap.label("allDone"))
        } else if let t = snap.tomorrowFirst(at: date) {
            heroLayout(symbol: t.symbol, tint: routineTint(t.kind), main: t.title,
                       caption: "\(snap.label("tomorrow")) · \(t.anytime ? snap.label("anytime") : routineClock(t.start))")
        } else {
            heroLayout(symbol: "moon.zzz.fill", tint: vivid.opacity(0.85),
                       main: snap.label("empty"), caption: nil)
        }
    }

    @ViewBuilder
    private func heroLayout(symbol: String, tint: Color, main: String, caption: String?) -> some View {
        // Fixed slots: the words change, the places never do. One line for
        // the large text (shrunk, never wrapped) and a caption line kept
        // even when it is empty.
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tint)
            .frame(height: 26, alignment: .leading)
        Text(verbatim: main)
            .font(pixelFont(17))
            .foregroundStyle(vivid)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(height: 22, alignment: .leading)
        Text(verbatim: caption ?? " ")
            .font(pixelFont(11))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: 14, alignment: .leading)
    }

    /// Four rows at most, kept around now: the block due or next, with the
    /// one before it when there is room.
    private var visibleRows: [RoutineWidgetBlock] {
        let limit = 4
        guard blocks.count > limit else { return blocks }
        // A finished day keeps its last rows on screen.
        let focus = (nowBlock ?? nextBlock).flatMap { f in blocks.firstIndex { $0.id == f.id } }
            ?? blocks.count - 1
        let start = max(0, min(focus - 1, blocks.count - limit))
        return Array(blocks[start..<start + limit])
    }

    private func row(_ b: RoutineWidgetBlock) -> some View {
        let isNow = b.isNow(at: date)
        let lapsed = !b.done && !b.anytime && b.end <= date
        return Link(destination: b.deepLink ?? URL(string: "futurevoice://routine")!) {
            HStack(spacing: 8) {
                // The time even for the block due now: the row's highlight and
                // its line already say "now", and a word here ("Maintenant")
                // doesn't fit the column in every language.
                Text(verbatim: b.anytime ? snap.label("anytime") : routineClock(b.start))
                    .font(pixelFont(11))
                    .foregroundStyle(isNow ? vivid : .white.opacity(0.55))
                    .frame(width: 44, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: b.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(lapsed ? .white.opacity(0.35) : routineTint(b.kind))
                    .frame(width: 16)
                Text(b.title)
                    .font(pixelFont(12))
                    .foregroundStyle(isNow ? vivid : .white.opacity(lapsed ? 0.4 : 0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                RoutineRing(progress: b.done ? 1 : (b.progress ?? 0), faded: lapsed)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(isNow ? vivid.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension RoutineWidgetSnapshot {
    /// A day mid-routine, for the widget gallery and the placeholder.
    static func sample(now: Date = Date()) -> RoutineWidgetSnapshot {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
        func block(_ kind: String, _ start: Date, _ minutes: Int, _ title: String,
                   _ symbol: String, done: Bool, progress: Double = 0) -> RoutineWidgetBlock {
            RoutineWidgetBlock(id: kind + "\(start)", kind: kind, start: start,
                               end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                               anytime: false, title: title, nowLine: "Ready to review",
                               symbol: symbol, done: done, progress: done ? 1 : progress)
        }
        return RoutineWidgetSnapshot(
            updatedAt: now, day: day,
            today: [block("talk", at(8, 0), 10, "Talk 10 min", "phone.fill", done: true),
                    block("shadow", at(12, 30), 15, "Shadowing 2 lines", "waveform", done: true),
                    block("review", now.addingTimeInterval(-300), 15, "Review",
                          "rectangle.stack.fill", done: false, progress: 0.4),
                    block("speech", at(21, 30), 15, "Speech", "music.mic", done: false)]
                .sorted { $0.start < $1.start },
            tomorrow: [],
            labels: ["title": "My routine", "now": "Now", "next": "Up next",
                     "today": "Today", "tomorrow": "Tomorrow", "anytime": "Anytime",
                     "allDone": "Done for today", "empty": "Rest day."])
    }
}

/// Activity's ring (`PlannerDayView.ProgressRing`) on the widget's dark
/// ground: empty circle → filling green ring → green tick.
struct RoutineRing: View {
    let progress: Double
    var faded = false

    var body: some View {
        ZStack {
            if progress >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.green)
            } else {
                Circle().strokeBorder(.white.opacity(faded ? 0.2 : 0.35), lineWidth: 1.5)
                if progress > 0 {
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
            }
        }
        .frame(width: 15, height: 15)
    }
}
