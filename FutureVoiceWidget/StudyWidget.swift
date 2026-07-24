import AppIntents
import SwiftUI
import WidgetKit

@main
struct FutureVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        VocabularyWidget()
        ExpressionsWidget()
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

/// Shared configuration — both widgets are the same pinboard, only their data
/// source, copy, and deep link differ (all carried by `StudyWidgetSection`).
struct StudyWidgetConfiguration {
    let section: StudyWidgetSection

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: section.widgetKind,
            provider: StudyTimelineProvider(section: section)
        ) { entry in
            StudyWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Corkboard behind the stickies — fixed grain: the board
                    // stays put while notes come and go.
                    CorkSurface()
                }
        }
        .configurationDisplayName(section.displayName)
        .description(section.galleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Shuffle (interactive)

/// The in-widget Shuffle button. Bumps the section's shuffle cursor in the
/// App Group so the timeline provider advances the visible words on the next
/// (immediate) reload — the one lever that gives a widget on-demand motion.
struct ShuffleStudyIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle words"

    @Parameter(title: "Section") var sectionRaw: String

    init() {}
    init(section: StudyWidgetSection) { sectionRaw = section.rawValue }

    func perform() async throws -> some IntentResult {
        if let section = StudyWidgetSection(rawValue: sectionRaw) {
            StudyWidgetSnapshotStore.bumpShuffle(section, by: 3)
        }
        return .result()
    }
}

// MARK: - Timeline

struct StudyEntry: TimelineEntry {
    let date: Date
    let section: StudyWidgetSection
    /// The collection, rotated so this entry's window starts at a fresh item.
    let items: [StudyWidgetItem]
    let total: Int
    let theme: Int
    /// Drives the cork grain + sticky jitter; shifts with the window so the
    /// board re-pins subtly on each slide and on every manual shuffle.
    let seed: Int
}

struct StudyTimelineProvider: TimelineProvider {
    let section: StudyWidgetSection

    func placeholder(in context: Context) -> StudyEntry {
        StudyEntry(date: Date(), section: section, items: sampleItems,
                   total: sampleItems.count, theme: 0, seed: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entries(from: StudyWidgetSnapshotStore.load(section)).first ?? placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        completion(Timeline(entries: entries(from: StudyWidgetSnapshotStore.load(section)), policy: .atEnd))
    }

    private var sampleItems: [StudyWidgetItem] {
        switch section {
        case .words:
            return [StudyWidgetItem(text: "negotiate", note: "B1"),
                    StudyWidgetItem(text: "tentative", note: "C1"),
                    StudyWidgetItem(text: "revitalize", note: "C1")]
        case .expressions:
            return [StudyWidgetItem(text: "walk me through it", note: ""),
                    StudyWidgetItem(text: "I'd rather grab a coffee", note: ""),
                    StudyWidgetItem(text: "it seems a lot of parents", note: "×2")]
        }
    }

    /// One entry per 30 minutes for ~6h, each sliding the list window forward
    /// a few rows — spaced exposure to the whole collection instead of the
    /// same pinned few. The manual shuffle cursor is folded into the offset so
    /// a tap jumps the window immediately. `.atEnd` re-reads and starts over.
    private func entries(from snapshot: StudyWidgetSnapshot, now: Date = Date()) -> [StudyEntry] {
        let items = snapshot.items
        let theme = StudyWidgetSnapshotStore.themeIndex
        let shuffle = StudyWidgetSnapshotStore.shuffleCursor(section)
        guard !items.isEmpty else {
            return [StudyEntry(date: now, section: section, items: [], total: 0, theme: theme, seed: shuffle)]
        }
        let stride = 3
        let slots = items.count <= stride ? 1 : 12
        return (0..<slots).map { slot in
            let base = slot * stride + shuffle
            let offset = ((base % items.count) + items.count) % items.count
            return StudyEntry(
                date: now.addingTimeInterval(Double(slot) * 30 * 60),
                section: section,
                items: Array(items[offset...] + items[..<offset]),
                total: snapshot.total,
                theme: theme,
                seed: base
            )
        }
    }
}

// MARK: - View

struct StudyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: StudyEntry

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreen
            } else {
                let style = boardStyle
                PinboardBoard(section: entry.section, items: entry.items,
                              theme: entry.theme, seed: entry.seed,
                              capacity: style.capacity, columns: style.columns,
                              noteSpacing: style.spacing, noteSize: style.size,
                              fillsBoard: style.fills) {
                    if family != .systemSmall {
                        Button(intent: ShuffleStudyIntent(section: entry.section)) {
                            ShuffleSticker()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .widgetURL(entry.section.deepLink)
    }

    private struct BoardStyle {
        let capacity: Int
        let columns: Int
        let size: StickyNote.Size
        let fills: Bool
        let spacing: CGFloat
    }

    /// Per-family board shape. Words are short → two columns on wide
    /// families; expressions are strips → always one. Large boards grow the
    /// paper (`.large` + fills) so notes scale with the widget instead of
    /// leaving bare cork.
    private var boardStyle: BoardStyle {
        switch family {
        case .systemLarge:
            return entry.section == .words
                ? BoardStyle(capacity: 8, columns: 2, size: .large, fills: true, spacing: 16)
                : BoardStyle(capacity: 6, columns: 1, size: .large, fills: true, spacing: 16)
        case .systemMedium:
            return entry.section == .words
                ? BoardStyle(capacity: 4, columns: 2, size: .compact, fills: false, spacing: 12)
                : BoardStyle(capacity: 3, columns: 1, size: .regular, fills: true, spacing: 12)
        default:
            return BoardStyle(capacity: 3, columns: 1, size: .regular, fills: true, spacing: 12)
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let first = entry.items.first {
                Text(first.text)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if entry.items.count > 1 {
                    Text(entry.items.dropFirst().prefix(2).map(\.text).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Future Voice").font(.headline)
                Text(entry.section == .words
                     ? "Save words to study them here"
                     : "Have a talk to collect phrases")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
