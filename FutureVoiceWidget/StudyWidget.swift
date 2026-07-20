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

/// Shared configuration — both widgets are the same list, only their data
/// source, copy, and deep link differ (all carried by `StudyWidgetSection`).
struct StudyWidgetConfiguration {
    let section: StudyWidgetSection

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: section.widgetKind,
            provider: StudyTimelineProvider(section: section)
        ) { entry in
            StudyWidgetView(entry: entry)
                .containerBackground(Color(.systemBackground), for: .widget)
        }
        .configurationDisplayName(section.displayName)
        .description(section.galleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Timeline

struct StudyEntry: TimelineEntry {
    let date: Date
    let section: StudyWidgetSection
    /// The collection, rotated so this entry's window starts at a fresh item.
    let items: [StudyWidgetItem]
    let total: Int
}

struct StudyTimelineProvider: TimelineProvider {
    let section: StudyWidgetSection

    func placeholder(in context: Context) -> StudyEntry {
        StudyEntry(date: Date(), section: section, items: sampleItems, total: sampleItems.count)
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
    /// same pinned few. `.atEnd` re-reads the snapshot and starts over.
    private func entries(from snapshot: StudyWidgetSnapshot, now: Date = Date()) -> [StudyEntry] {
        let items = snapshot.items
        guard !items.isEmpty else {
            return [StudyEntry(date: now, section: section, items: [], total: 0)]
        }
        let stride = 3
        let slots = items.count <= stride ? 1 : 12
        return (0..<slots).map { slot in
            let offset = (slot * stride) % items.count
            return StudyEntry(
                date: now.addingTimeInterval(Double(slot) * 30 * 60),
                section: section,
                items: Array(items[offset...] + items[..<offset]),
                total: snapshot.total
            )
        }
    }
}

// MARK: - Views

struct StudyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudyEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: lockScreen
            case .systemLarge:          list(rows: 8, spacing: 10)
            case .systemMedium:         list(rows: 4, spacing: 7)
            default:                    list(rows: 3, spacing: 7)
            }
        }
        .widgetURL(entry.section.deepLink)
    }

    private func list(rows: Int, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(rows), id: \.self) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: StudyWidgetItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.text)
                .font(.subheadline.weight(entry.section == .words ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.section.showsNote, !item.note.isEmpty {
                Text(item.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Label(entry.section.shortLabel, systemImage: entry.section.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if entry.total > 0 {
                Text("\(entry.total)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.section == .words ? "No saved words yet" : "Nothing collected yet")
                .font(.subheadline.weight(.semibold))
            Text(entry.section == .words
                 ? "Tap a word in a talk to save it."
                 : "Have a talk — phrases land here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
