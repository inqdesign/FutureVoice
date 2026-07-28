import AppIntents
import SwiftUI
import WidgetKit

@main
struct FutureVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        VocabularyWidget()
        ExpressionsWidget()
        FreeTalkWidget()
    }
}

// MARK: - Free Talk widget — one tap starts a call

/// A dedicated small button: tap the whole widget to open the app and start a
/// Free Talk call (widgets can't record audio, so it deep-links). Wears a
/// STATIC Futureself surface (the live Metal shader can't run in a widget) in
/// the user's chosen theme.
struct FreeTalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FutureVoiceFreeTalkWidget",
                            provider: FreeTalkProvider()) { entry in
            FreeTalkWidgetView(theme: entry.theme)
                // Same surface as the Words/Phrases widgets — themed grid + bezel.
                .containerBackground(for: .widget) { WidgetGrid(theme: entry.theme) }
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
            return StudyEntry(date: now, section: section, item: nil, position: 0, total: 0, theme: theme)
        }
        let raw = StudyWidgetSnapshotStore.cursor(section)
        let idx = ((raw % items.count) + items.count) % items.count
        return StudyEntry(date: now, section: section, item: items[idx],
                          position: idx + 1, total: items.count, theme: theme)
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

    private var card: some View {
        StudyCard(label: entry.section.shortLabel,
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

    private var emptyText: String {
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
