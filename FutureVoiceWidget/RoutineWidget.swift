import SwiftUI
import WidgetKit

// MARK: - Routine widget — today's plan, and what is due now

/// The learner's routine on the home screen: today's planned blocks, and
/// while one's time is on, that one said out loud ("Ready to review"). The
/// widget can't ring — the plan's reminders do — but it changes face at each
/// block's start and end on its own timeline, so it is right with the app
/// closed. Done ticks arrive when the app writes the snapshot, which every
/// rep does.
struct RoutineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: routineWidgetKind, provider: RoutineProvider()) { entry in
            RoutineWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName("My routine")
        .description("What your routine has for today, and what's up now.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct RoutineEntry: TimelineEntry {
    let date: Date
    let snapshot: RoutineWidgetSnapshot
    let theme: Int
}

struct RoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineEntry {
        RoutineEntry(date: Date(), snapshot: .sample(), theme: StudyWidgetSnapshotStore.themeIndex)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineEntry) -> Void) {
        let snap = context.isPreview ? .sample() : StudyWidgetSnapshotStore.loadRoutine()
        completion(RoutineEntry(date: Date(), snapshot: snap, theme: StudyWidgetSnapshotStore.themeIndex))
    }

    /// One entry now and one at every block's start and end from here to the
    /// end of tomorrow — the moments the face changes. All of it is known in
    /// advance, so none of it spends a reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineEntry>) -> Void) {
        let now = Date()
        let snap = StudyWidgetSnapshotStore.loadRoutine()
        let theme = StudyWidgetSnapshotStore.themeIndex
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let edges = (snap.today + snap.tomorrow)
            .filter { !$0.anytime }
            .flatMap { [$0.start, $0.end] } + [midnight]
        let dates = [now] + Set(edges.filter { $0 > now }).sorted()
        let entries = dates.map { RoutineEntry(date: $0, snapshot: snap, theme: theme) }
        let reload = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? midnight
        completion(Timeline(entries: entries, policy: .after(reload)))
    }
}

// MARK: - View

struct RoutineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineEntry

    private var snap: RoutineWidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreen
            } else {
                RoutineCard(theme: entry.theme, snapshot: snap, date: entry.date,
                            compact: family == .systemSmall)
            }
        }
        .widgetURL(snap.deepLink(at: entry.date))
    }

    /// Lock screen: the block's name, its state under it — the home
    /// widget's two lines, in the system's own type.
    private var lockScreen: some View {
        let d = entry.date
        let blocks = snap.blocks(at: d)
        let line: (symbol: String, title: String, state: String)? = {
            if let b = snap.now(at: d) { return (b.symbol, b.title, b.nowLine) }
            if let b = snap.next(at: d) {
                let state = b.anytime ? snap.label("anytime")
                    : "\(snap.label(b.start <= d ? "today" : "next")) · \(routineClock(b.start))"
                return (b.symbol, b.title, state)
            }
            if let b = blocks.last { return (b.symbol, b.title, snap.label("allDone")) }
            if let t = snap.tomorrowFirst(at: d) {
                return (t.symbol, t.title, "\(snap.label("tomorrow")) · \(t.anytime ? snap.label("anytime") : routineClock(t.start))")
            }
            return nil
        }()
        return VStack(alignment: .leading, spacing: 1) {
            if let line {
                Label(line.title, systemImage: line.symbol).font(.headline).lineLimit(1)
                Text(line.state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Label(snap.label("empty"), systemImage: "moon.zzz.fill").font(.headline).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
