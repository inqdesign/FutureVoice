import AppIntents
import SwiftUI
import WidgetKit

/// Every widget renders in the app's chrome language — the language being
/// learned — not the phone's. A widget is one of the app's surfaces, and the
/// learner reading "Words" on the home screen is getting the same free
/// exposure the tab bar gives them. Read per timeline render, so switching
/// target language in the app repaints the widgets in the new language.
extension Locale {
    static var widgetChrome: Locale {
        Locale(identifier: StudyWidgetSnapshotStore.chromeLanguage)
    }
}

@main
struct FutureVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        VocabularyWidget()
        ExpressionsWidget()
        FreeTalkWidget()
        ProgressWidget()
        BookWidget()
        StreakWidget()
    }
}

// MARK: - Streak widget — Duolingo-style day counter

/// Big flame + day count to keep the learner's run alive; an at-risk badge
/// shows when today's goal isn't met yet. Reads the shared progress snapshot;
/// tapping opens Talk to do an activity.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: streakWidgetKind,
                            provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                // Grid cells match the mascot's pixels — one coherent display.
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme, step: streakPixel) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName("Streak")
        .description("Keep your daily talking streak alive.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let doneToday: Bool
    let deadline: Date       // next local midnight — the streak's daily wire
    let theme: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streakDays: 12, doneToday: false,
                    deadline: Date().addingTimeInterval(5 * 3600),
                    theme: StudyWidgetSnapshotStore.themeIndex)
    }
    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let now = Date()
        completion(entry(at: now, done: previewDone(context), streak: previewStreak(context),
                         deadline: Self.nextMidnight(after: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date()
        let deadline = Self.nextMidnight(after: now)
        let s = StudyWidgetSnapshotStore.loadProgress()
        // Only count "today" if the snapshot is actually from today; otherwise a
        // stale snapshot after midnight would wrongly read as done.
        let freshToday = Calendar.current.isDate(s.updatedAt, inSameDayAs: now)
        let done = freshToday && s.todaySeconds >= max(1, s.goalMinutes * 60)

        var entries = [entry(at: now, done: done, streak: s.streakDays, deadline: deadline)]
        // If the streak's alive but unmet, add an entry 3h before the wire so the
        // mascot turns anxious on its own without the app writing anything.
        if !done, s.streakDays > 0 {
            let anxiousAt = deadline.addingTimeInterval(-3 * 3600)
            if anxiousAt > now {
                entries.append(entry(at: anxiousAt, done: false, streak: s.streakDays, deadline: deadline))
            }
        }
        // Re-read after midnight (new day → new deadline, streak may have moved).
        completion(Timeline(entries: entries, policy: .after(deadline)))
    }

    private func entry(at date: Date, done: Bool, streak: Int, deadline: Date) -> StreakEntry {
        StreakEntry(date: date, streakDays: streak, doneToday: done,
                    deadline: deadline, theme: StudyWidgetSnapshotStore.themeIndex)
    }

    /// Local midnight strictly after `date`.
    static func nextMidnight(after date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))
            ?? date.addingTimeInterval(6 * 3600)
    }

    private func previewDone(_ context: Context) -> Bool { false }
    private func previewStreak(_ context: Context) -> Int { 12 }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        StreakCard(theme: entry.theme,
                   streakDays: entry.streakDays,
                   doneToday: entry.doneToday,
                   renderDate: entry.date,
                   deadline: entry.deadline,
                   compact: family == .systemSmall)
            .widgetURL(URL(string: "futurevoice://talk"))
    }
}

// MARK: - Continue widget — the book you're mid-way through, opens its detail

/// Shows the single most-recently-studied in-progress book (Talk or Watch) with
/// its mastery progress, and taps straight into that book's detail page. Static
/// snapshot — the app rewrites it on every store change.
struct BookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: bookWidgetKind,
                            provider: BookProvider()) { entry in
            BookWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName("Continue studying")
        .description("Jump back into the book you're working through.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BookEntry: TimelineEntry {
    let date: Date
    let snapshot: StudyBookSnapshot
    let theme: Int
}

struct BookProvider: TimelineProvider {
    func placeholder(in context: Context) -> BookEntry {
        BookEntry(date: Date(), snapshot: Self.sample, theme: StudyWidgetSnapshotStore.themeIndex)
    }
    func getSnapshot(in context: Context, completion: @escaping (BookEntry) -> Void) {
        let snap = context.isPreview ? Self.sample : StudyWidgetSnapshotStore.loadBook()
        completion(BookEntry(date: Date(), snapshot: snap, theme: StudyWidgetSnapshotStore.themeIndex))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BookEntry>) -> Void) {
        let entry = BookEntry(date: Date(),
                              snapshot: StudyWidgetSnapshotStore.loadBook(),
                              theme: StudyWidgetSnapshotStore.themeIndex)
        completion(Timeline(entries: [entry], policy: .never))
    }

    static let sample = StudyBookSnapshot(
        updatedAt: Date(), hasBook: true, kind: "watch", id: "",
        title: "Ordering at a busy café", subtitle: "with Barista",
        mastered: 3, total: 8)
}

struct BookWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BookEntry

    var body: some View {
        let s = entry.snapshot
        BookCard(theme: entry.theme,
                 hasBook: s.hasBook,
                 kind: s.kind,
                 title: s.title,
                 subtitle: s.subtitle,
                 mastered: s.mastered,
                 total: s.total,
                 compact: family == .systemSmall)
            .widgetURL(s.deepLink)
    }
}

// MARK: - Progress widget — today's goal + study counts, opens Studying

/// A glance at where the learner stands today: the goal ring, streak, review
/// backlog, and study counts. Tap opens the app on Practice → Studying. Wears
/// the same themed grid surface as the other widgets. Static snapshot — the
/// app rewrites it on every store change.
struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: progressWidgetKind,
                            provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName("Progress")
        .description("Today's goal, streak, and what's left to study.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: StudyProgressSnapshot
    let theme: Int
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), snapshot: Self.sample, theme: StudyWidgetSnapshotStore.themeIndex)
    }
    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let snap = context.isPreview ? Self.sample : StudyWidgetSnapshotStore.loadProgress()
        completion(ProgressEntry(date: Date(), snapshot: snap, theme: StudyWidgetSnapshotStore.themeIndex))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: Date(),
                                  snapshot: StudyWidgetSnapshotStore.loadProgress(),
                                  theme: StudyWidgetSnapshotStore.themeIndex)
        completion(Timeline(entries: [entry], policy: .never))
    }

    static let sample = StudyProgressSnapshot(
        updatedAt: Date(), todaySeconds: 7 * 60, goalMinutes: 10,
        streakDays: 4, dueCount: 12, studyingWords: 18, studyingExpressions: 6)
}

struct ProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    var body: some View {
        let s = entry.snapshot
        ProgressCard(theme: entry.theme,
                     todaySeconds: s.todaySeconds,
                     goalMinutes: s.goalMinutes,
                     streakDays: s.streakDays,
                     dueCount: s.dueCount,
                     studyingWords: s.studyingWords,
                     studyingExpressions: s.studyingExpressions,
                     compact: family == .systemSmall)
            .widgetURL(URL(string: "futurevoice://practice"))
    }
}

// MARK: - Free Talk widget — one tap starts a call

/// A dedicated small button: tap the whole widget to open the app and start a
/// Free Talk call (widgets can't record audio, so it deep-links). Wears a
/// STATIC Futureself surface (the live Metal shader can't run in a widget) in
/// the user's chosen theme.
struct FreeTalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: freeTalkWidgetKind,
                            provider: FreeTalkProvider()) { entry in
            FreeTalkWidgetView(theme: entry.theme)
                // Same surface as the Words/Phrases widgets — themed grid + bezel.
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName("Free Talk")
        .description("One tap to call your fluent self.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct FreeTalkEntry: TimelineEntry {
    let date: Date
    let theme: Int
}

struct FreeTalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> FreeTalkEntry {
        FreeTalkEntry(date: Date(), theme: StudyWidgetSnapshotStore.themeIndex)
    }
    func getSnapshot(in context: Context, completion: @escaping (FreeTalkEntry) -> Void) {
        completion(FreeTalkEntry(date: Date(), theme: StudyWidgetSnapshotStore.themeIndex))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FreeTalkEntry>) -> Void) {
        completion(Timeline(entries: [FreeTalkEntry(date: Date(), theme: StudyWidgetSnapshotStore.themeIndex)],
                            policy: .never))
    }
}

struct FreeTalkWidgetView: View {
    let theme: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(WidgetTheme.vivid(theme))
            Text("Let's talk")
                .font(pixelFont(16))
                .foregroundStyle(WidgetTheme.vivid(theme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "futurevoice://freetalk"))
    }
}

// MARK: - The two widgets

/// Notebook words to keep studying. Taps open the Vocabulary page.
struct VocabularyWidget: Widget {
    var body: some WidgetConfiguration { StudyWidgetConfiguration(section: .words).body }
}

/// Phrases picked up in talks. Taps open the Expressions page.
struct ExpressionsWidget: Widget {
    var body: some WidgetConfiguration { StudyWidgetConfiguration(section: .expressions).body }
}

/// Shared configuration — both widgets are the same single-word card, only
/// their data source, copy, and deep link differ (carried by the section).
struct StudyWidgetConfiguration {
    let section: StudyWidgetSection

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: section.widgetKind,
            provider: StudyTimelineProvider(section: section)
        ) { entry in
            StudyWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
                .environment(\.locale, .widgetChrome)
        }
        .configurationDisplayName(section.displayName)
        .description(section.galleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        // Drop the system's default content margins so the grid/bezel and the
        // word use the full widget — our own tight padding controls the inset.
        .contentMarginsDisabled()
    }
}

// MARK: - Prev / Next (interactive)

/// Steps the section's cursor ±1 in the App Group, so tapping Prev/Next moves
/// to the neighbouring word on the next (immediate) widget reload.
struct StepStudyIntent: AppIntent {
    static var title: LocalizedStringResource = "Next / previous word"

    @Parameter(title: "Section") var sectionRaw: String
    @Parameter(title: "Delta") var delta: Int

    init() {}
    init(section: StudyWidgetSection, delta: Int) {
        sectionRaw = section.rawValue
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        if let section = StudyWidgetSection(rawValue: sectionRaw) {
            StudyWidgetSnapshotStore.stepCursor(section, by: delta)
        }
        return .result()
    }
}

// MARK: - Timeline (a single item at the cursor)

struct StudyEntry: TimelineEntry {
    let date: Date
    let section: StudyWidgetSection
    let item: StudyWidgetItem?     // the word/phrase at the cursor; nil = empty
    let position: Int              // 1-based index for the "3 / 20" style count
    let total: Int
    let theme: Int                 // the user's Futureself theme index
    var language: String? = nil    // set only when >1 language is enrolled
}

struct StudyTimelineProvider: TimelineProvider {
    let section: StudyWidgetSection

    func placeholder(in context: Context) -> StudyEntry {
        StudyEntry(date: Date(), section: section, item: sampleItem, position: 1, total: 12,
                   theme: StudyWidgetSnapshotStore.themeIndex)
    }

    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context)
                                     : entry(from: StudyWidgetSnapshotStore.load(section)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        // One entry — the word at the current cursor. The Prev/Next buttons (and
        // app-side snapshot writes) reload the timeline; no time-based rotation.
        completion(Timeline(entries: [entry(from: StudyWidgetSnapshotStore.load(section))],
                            policy: .never))
    }

    private var sampleItem: StudyWidgetItem {
        section == .words ? StudyWidgetItem(text: "Negotiate", note: "B1")
                          : StudyWidgetItem(text: "Walk me through it", note: "")
    }

    private func entry(from snapshot: StudyWidgetSnapshot, now: Date = Date()) -> StudyEntry {
        let theme = StudyWidgetSnapshotStore.themeIndex
        let items = snapshot.items
        guard !items.isEmpty else {
            return StudyEntry(date: now, section: section, item: nil, position: 0, total: 0,
                              theme: theme, language: snapshot.language)
        }
        let raw = StudyWidgetSnapshotStore.cursor(section)
        let idx = ((raw % items.count) + items.count) % items.count
        return StudyEntry(date: now, section: section, item: items[idx],
                          position: idx + 1, total: items.count, theme: theme,
                          language: snapshot.language)
    }
}

// MARK: - View

struct StudyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudyEntry

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreen
            } else {
                card
            }
        }
        // Tapping the card body (not the buttons) opens this item's page.
        .widgetURL(entry.item.map { entry.section.deepLink(for: $0.text) } ?? entry.section.deepLink)
    }

    private var compact: Bool { family == .systemSmall }
    private var navSize: CGFloat { compact ? 30 : 38 }

    /// "Words" normally; "Words · DE" once a second language is enrolled, so
    /// a glance says WHICH language's queue this is after a switch.
    private var cardLabel: String {
        guard let code = entry.language, !code.isEmpty else { return entry.section.shortLabel }
        return "\(entry.section.shortLabel) · \(code.uppercased())"
    }

    private var card: some View {
        StudyCard(label: cardLabel,
                  word: entry.item?.text ?? "",
                  note: entry.section.showsNote ? (entry.item?.note ?? "") : "",
                  emptyText: emptyText,
                  compact: compact,
                  wordColor: WidgetTheme.vivid(entry.theme)) {
            Button(intent: StepStudyIntent(section: entry.section, delta: -1)) {
                NavCircle(direction: .prev, size: navSize)
            }
            .buttonStyle(.plain)
            .disabled(entry.total <= 1)
        } next: {
            Button(intent: StepStudyIntent(section: entry.section, delta: 1)) {
                NavCircle(direction: .next, size: navSize)
            }
            .buttonStyle(.plain)
            .disabled(entry.total <= 1)
        }
    }

    private var emptyText: LocalizedStringKey {
        entry.section == .words
            ? "Save words to study them here"
            : "Bookmark phrases to study them here"
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = entry.item {
                Text(item.text)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if entry.total > 1 {
                    Text("\(entry.position) / \(entry.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Future Voice").font(.headline)
                Text(entry.section == .words
                     ? "Save words to study them here"
                     : "Bookmark phrases to study them here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
