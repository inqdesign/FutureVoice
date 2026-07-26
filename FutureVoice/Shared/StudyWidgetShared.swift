import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Data contract between the app and the home-screen widgets. Compiled into
/// BOTH targets (app + FutureVoiceWidget) — keep it dependency-free: no
/// stores, no Models.swift types, just what the widgets need to render.
///
/// There are two widgets, one per `Section`: a Vocabulary widget (notebook
/// words) and an Expressions widget (phrases from talks). Each has its own
/// snapshot file in the shared App Group container, its own WidgetKit `kind`,
/// and its own deep link. The app is the only writer (`StudyWidgetRefresher`);
/// the widget extension only reads.
struct StudyWidgetItem: Codable, Hashable {
    var text: String       // the word or expression to study
    var note: String       // short trailing caption: CEFR level, or usage count
}

struct StudyWidgetSnapshot: Codable {
    var updatedAt: Date
    /// Size of the whole collection (not just the windowed items) — the badge.
    var total: Int
    var items: [StudyWidgetItem]

    static let empty = StudyWidgetSnapshot(updatedAt: .distantPast, total: 0, items: [])
}

/// The two independent widgets. Everything that differs between them —
/// storage file, WidgetKit kind, gallery copy, deep link — hangs off here so
/// the app and the extension stay in sync from one definition.
enum StudyWidgetSection: String, CaseIterable {
    case words
    case expressions

    var filename: String { "widget_\(rawValue).json" }
    var widgetKind: String {
        switch self {
        case .words:       return "FutureVoiceVocabularyWidget"
        case .expressions: return "FutureVoiceExpressionsWidget"
        }
    }
    var displayName: String {
        switch self {
        case .words:       return "Vocabulary"
        case .expressions: return "Expressions"
        }
    }
    var galleryDescription: String {
        switch self {
        case .words:       return "Words from your notebook to keep studying."
        case .expressions: return "Phrases you've picked up in your talks."
        }
    }
    /// Header label inside the widget.
    var shortLabel: String {
        switch self {
        case .words:       return "Words"
        case .expressions: return "Phrases"
        }
    }
    var systemImage: String {
        switch self {
        case .words:       return "character.book.closed"
        case .expressions: return "quote.bubble"
        }
    }
    var deepLink: URL? {
        switch self {
        case .words:       return URL(string: "futurevoice://vocab")
        case .expressions: return URL(string: "futurevoice://expressions")
        }
    }

    /// Deep link to a SPECIFIC item — a tapped word or phrase carries its text
    /// as `?q=…` so the app opens that item's page, not just the list. Falls
    /// back to the plain list link if the text is empty or the URL can't build.
    func deepLink(for text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = deepLink,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return deepLink
        }
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return comps.url ?? deepLink
    }
    /// Whether a row's trailing note (CEFR level) should render. Expressions
    /// carry a usage count instead, which reads as clutter in a glance.
    var showsNote: Bool { self == .words }
}

enum StudyWidgetSnapshotStore {
    static let appGroupID = "group.com.roro.futurevoice"

    /// Small cross-target defaults kept alongside the snapshot files: the
    /// Futureself palette index (so the widget's pin accents match the app's
    /// chosen theme) and a per-section shuffle cursor (bumped by the
    /// in-widget Shuffle button's AppIntent, read by the timeline provider).
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Futureself theme index (`FutureselfTheme.rawValue`), written by the app
    /// on refresh. Defaults to 0 (blue) when unset.
    static var themeIndex: Int {
        get { defaults?.integer(forKey: "widget_theme") ?? 0 }
        set { defaults?.set(newValue, forKey: "widget_theme") }
    }

    /// The currently-shown item index for a section — bumped ±1 by the widget's
    /// Prev/Next buttons. Can go negative or past the end; the provider wraps it
    /// with a modulo against the live item count.
    static func cursor(_ section: StudyWidgetSection) -> Int {
        defaults?.integer(forKey: "widget_cursor_\(section.rawValue)") ?? 0
    }

    static func stepCursor(_ section: StudyWidgetSection, by delta: Int) {
        defaults?.set(cursor(section) + delta, forKey: "widget_cursor_\(section.rawValue)")
    }

    private static func fileURL(for section: StudyWidgetSection) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(section.filename)
    }

    static func load(_ section: StudyWidgetSection) -> StudyWidgetSnapshot {
        guard let url = fileURL(for: section),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(StudyWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: StudyWidgetSnapshot, for section: StudyWidgetSection) {
        guard let url = fileURL(for: section),
              let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}

// MARK: - Single-word card (grid surface + pixel word + prev/next), shared

/// The widget's charcoal grid surface — graph-paper lines over a dark ground.
/// A single committed dark look (like the design mock), so it doesn't follow
/// light/dark; the pixel word reads the same on any home screen.

/// The bundled pixel title font as a concrete Font — built from a UIFont so an
/// ancestor's `.fontDesign(.rounded)` (the app applies one globally) can't
/// swap it for a system face the way `Font.custom` gets overridden.
func pixelFont(_ size: CGFloat) -> Font {
    #if canImport(UIKit)
    if let ui = UIFont(name: "GeistPixel-Square", size: size) { return Font(ui) }
    #endif
    return .system(size: size, weight: .semibold, design: .monospaced)
}

struct WidgetGrid: View {
    /// Corner shape — matches the home-screen widget's own radius via
    /// `ContainerRelativeShape` inside a widget; a rounded rect elsewhere (the
    /// app's design-review gallery).
    var shape: AnyShape = AnyShape(ContainerRelativeShape())

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.16, green: 0.16, blue: 0.17)))
            let step: CGFloat = 26
            var x: CGFloat = 0
            let line = Color.white.opacity(0.055)
            while x <= size.width {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(line), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(line), lineWidth: 1)
                y += step
            }
        }
        // Inner shadow — a soft dark ring hugging the edge, so the grid reads
        // as a recessed display behind the bezel.
        .overlay {
            shape
                .stroke(Color.black.opacity(0.8), lineWidth: 14)
                .blur(radius: 9)
                .mask(shape)
        }
        // Thick display bezel (stroke is centered on the edge; the OS clips
        // the outer half, leaving a solid inner frame).
        .overlay {
            shape.stroke(Color.black, lineWidth: 9)
        }
    }
}

/// A prev/next control's look — a dark disc with a pixel chevron. The widget
/// wraps it in a `Button(intent:)`; the app's preview renders it bare.
struct NavCircle: View {
    enum Direction { case prev, next }
    let direction: Direction
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            Text(direction == .prev ? "<" : ">")
                .font(pixelFont(size * 0.5))
                .foregroundStyle(.white)
                .offset(x: direction == .prev ? -1 : 1)
        }
        .frame(width: size, height: size)
    }
}

/// One word/phrase, big, in the pixel title font — label top-left, the item
/// centered, prev/next discs pinned to the bottom corners. Shared so the
/// widget and the app's design-review gallery render identically.
struct StudyCard<Prev: View, Next: View>: View {
    let label: String        // "Words" / "Phrases"
    let word: String         // the single item; empty → empty state
    let note: String         // CEFR level / usage count, shown small
    let emptyText: String
    var compact: Bool = false
    @ViewBuilder var prev: () -> Prev
    @ViewBuilder var next: () -> Next

    var body: some View {
        ZStack {
            // The word — centered in the WHOLE container.
            content

            // Label — centered at the very top, floating (an overlay, so it
            // never shifts the word off-centre and the corner can't clip it).
            VStack(spacing: 0) {
                Text(label)
                    .font(pixelFont(compact ? 11 : 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }

            // Prev / next, bottom corners — with extra inset so they clear the
            // widget's rounded corner (tight padding alone glues them to it).
            VStack {
                Spacer()
                HStack {
                    prev()
                    Spacer()
                    next()
                }
                .padding(.horizontal, compact ? 8 : 4)
                .padding(.bottom, compact ? 5 : 1)
            }
        }
        // The ONLY inset now that the widget's system content margins are
        // disabled — just enough to clear the display bezel.
        .padding(compact ? 7 : 10)
    }

    @ViewBuilder
    private var content: some View {
        if word.isEmpty {
            Text(emptyText)
                .font(pixelFont(compact ? 14 : 17))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: compact ? 2 : 5) {
                Text(word)
                    .font(pixelFont(compact ? 30 : 42))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                if !note.isEmpty {
                    Text(note)
                        .font(pixelFont(compact ? 12 : 14))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, compact ? 4 : 10)
            .frame(maxWidth: .infinity)
        }
    }
}
