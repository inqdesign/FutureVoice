import Foundation
import os
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Resolves a label in the app's CHROME language — the language being learned,
/// mirrored into the App Group by the app because an extension can't read the
/// app's `UserDefaults`.
///
/// A widget's `Text("literal")` follows `\.locale`, which each widget sets once
/// at its root; this is for the few labels that have to become a `String`
/// before they reach a `Text`. It resolves against the CURRENT target's bundle,
/// so the same call site works in the app and in the extension.
func widgetChrome(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .widgetChrome)
}

extension Bundle {
    /// `.main` fallback is deliberate: the source language ships no `.lproj`,
    /// so a learner practicing English correctly degrades to the catalog keys.
    static var widgetChrome: Bundle {
        let code = StudyWidgetSnapshotStore.chromeLanguage
        if let cached = chromeBundleCache.withLock({ $0[code] }) { return cached ?? .main }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        chromeBundleCache.withLock { $0[code] = resolved }
        return resolved ?? .main
    }

    private static let chromeBundleCache = OSAllocatedUnfairLock(initialState: [String: Bundle?]())
}

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
    /// Target-language code the items belong to ("en", "de"). Written only
    /// when the user is enrolled in MORE than one language — with a single
    /// language the label is noise. nil also covers pre-1.1 snapshots.
    var language: String?

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
    /// Gallery copy — the "Add Widget" sheet. Resolved in the DEVICE language
    /// (plain `String(localized:)`), unlike everything drawn inside the widget:
    /// that sheet is iOS's own UI, listed next to system widgets, and the
    /// learner is browsing it in their phone's language.
    var displayName: String {
        switch self {
        case .words:       return String(localized: "Vocabulary")
        case .expressions: return String(localized: "Expressions")
        }
    }
    var galleryDescription: String {
        switch self {
        case .words:       return String(localized: "Words from your notebook to keep studying.")
        case .expressions: return String(localized: "Phrases you've picked up in your talks.")
        }
    }
    /// Header label inside the widget — OUR surface, so it speaks the app's
    /// chrome language like every other label the learner sees in the app.
    var shortLabel: String {
        switch self {
        case .words:       return widgetChrome("Words")
        case .expressions: return widgetChrome("Phrases")
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

/// WidgetKit `kind` for the Free Talk widget — shared so the widget declares
/// it and the app can reload it when the theme changes.
let freeTalkWidgetKind = "FutureVoiceFreeTalkWidget"

/// WidgetKit `kind` for the learning-progress widget (today's goal + streak +
/// review/study counts). Shared so the app can reload it on any store change.
let progressWidgetKind = "FutureVoiceProgressWidget"

/// A glanceable snapshot of where the learner stands TODAY — everything the
/// progress widget shows, written by `StudyWidgetRefresher` on every store
/// change. All deterministic, computed in-app (no LLM).
struct StudyProgressSnapshot: Codable {
    var updatedAt: Date
    var todaySeconds: Int         // metered talk seconds today, all languages
    var goalMinutes: Int          // the daily goal (minutes)
    var streakDays: Int           // consecutive days over the Core bar, in the active language
    var dueCount: Int             // SRS cards due right now
    var studyingWords: Int        // notebook words being studied
    var studyingExpressions: Int  // bookmarked phrases being studied
    /// Whether today already cleared the Core bar in the language being
    /// practised — the streak's own rule, decided app-side by the same
    /// predicate that computes `streakDays`. It is NOT `todaySeconds >=
    /// goalMinutes`: the goal is the learner's ring, the bar is what makes a
    /// day count, and the streak widget judging by the goal put a "you're
    /// about to lose it" face on a streak that had already been extended.
    /// The two inputs don't even match — `todaySeconds` pools every language.
    var metToday: Bool

    static let empty = StudyProgressSnapshot(
        updatedAt: .distantPast, todaySeconds: 0, goalMinutes: 10,
        streakDays: 0, dueCount: 0, studyingWords: 0, studyingExpressions: 0,
        metToday: false)
}

/// The Core's daily bar, for the ONE case the extension has to guess: a
/// snapshot written by a build older than `metToday`. The app mirrors the real
/// value from `core_club_config`; nothing here may treat this as the rule.
let coreDailyBarFallbackSeconds = 240

extension StudyProgressSnapshot {
    /// Lenient decode, so adding a field can never collapse the whole
    /// snapshot to `.empty` and blank a widget until the app next runs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
        todaySeconds = (try? c.decode(Int.self, forKey: .todaySeconds)) ?? 0
        goalMinutes = (try? c.decode(Int.self, forKey: .goalMinutes)) ?? 10
        streakDays = (try? c.decode(Int.self, forKey: .streakDays)) ?? 0
        dueCount = (try? c.decode(Int.self, forKey: .dueCount)) ?? 0
        studyingWords = (try? c.decode(Int.self, forKey: .studyingWords)) ?? 0
        studyingExpressions = (try? c.decode(Int.self, forKey: .studyingExpressions)) ?? 0
        metToday = (try? c.decode(Bool.self, forKey: .metToday))
            ?? (todaySeconds >= coreDailyBarFallbackSeconds)
    }
}

/// WidgetKit `kind` for the "continue studying" widget — the one book you're
/// mid-way through, tappable straight into its detail page.
let bookWidgetKind = "FutureVoiceBookWidget"

/// WidgetKit `kind` for the streak widget — a Duolingo-style day counter that
/// nudges the learner not to break their run. Reads the shared progress
/// snapshot (streak + whether today's goal is met).
let streakWidgetKind = "FutureVoiceStreakWidget"

/// The single most-recently-studied in-progress book (a Talk or a Watch book),
/// mirrored to the App Group so the Continue widget can render its title +
/// mastery progress and deep-link to its detail page.
struct StudyBookSnapshot: Codable {
    var updatedAt: Date
    var hasBook: Bool
    var kind: String        // "talk" | "watch"
    var id: String          // the book's UUID string, for the deep link
    var title: String
    var subtitle: String    // short context: source / partner / "Talk"
    var mastered: Int
    var total: Int

    static let empty = StudyBookSnapshot(
        updatedAt: .distantPast, hasBook: false, kind: "talk",
        id: "", title: "", subtitle: "", mastered: 0, total: 0)

    /// Deep link to this book's detail page; falls back to the Studying shelf
    /// when there's no in-progress book.
    var deepLink: URL? {
        guard hasBook, !id.isEmpty else { return URL(string: "futurevoice://practice") }
        return URL(string: "futurevoice://book?type=\(kind)&id=\(id)")
    }
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

    /// The app's chrome language (its TARGET language), written by the app on
    /// refresh. The widget is one of the app's surfaces, so it speaks the same
    /// language the tabs and labels do — and it can't read that setting itself,
    /// living in another process with its own `UserDefaults`.
    static var chromeLanguage: String {
        get { defaults?.string(forKey: "widget_chrome_language") ?? "en" }
        set { defaults?.set(newValue, forKey: "widget_chrome_language") }
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

    // MARK: Progress snapshot (its own file, one per install)

    private static var progressURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_progress.json")
    }

    static func loadProgress() -> StudyProgressSnapshot {
        guard let url = progressURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(StudyProgressSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func saveProgress(_ snapshot: StudyProgressSnapshot) {
        guard let url = progressURL,
              let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: Recent-book snapshot (its own file)

    private static var bookURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget_book.json")
    }

    static func loadBook() -> StudyBookSnapshot {
        guard let url = bookURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(StudyBookSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func saveBook(_ snapshot: StudyBookSnapshot) {
        guard let url = bookURL,
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

/// The widget's tone, derived from the user's chosen Futureself theme so the
/// home-screen widget matches the in-app dialer surface. `ground` is the dark
/// display background, `bezel` the thick frame, `vivid` the pixel word colour —
/// all the same hue family. Theme 0 (blue) is the default; 1 (mono) is the
/// neutral charcoal look.
enum WidgetTheme {
    // dark-ramp steps lifted from Futureself.metal (ground → vivid).
    private static let groundC: [(Double, Double, Double)] = [
        (0.030, 0.036, 0.070), (0.030, 0.030, 0.032), (0.022, 0.038, 0.032),
        (0.048, 0.036, 0.020), (0.048, 0.022, 0.036), (0.018, 0.038, 0.044),
    ]
    private static let vividC: [(Double, Double, Double)] = [
        (0.480, 0.720, 1.000), (0.960, 0.960, 0.970), (0.560, 0.940, 0.760),
        (1.000, 0.830, 0.480), (1.000, 0.640, 0.660), (0.560, 0.940, 1.000),
    ]
    private static func c(_ t: [(Double, Double, Double)], _ i: Int) -> Color {
        let v = t[((i % t.count) + t.count) % t.count]
        return Color(red: v.0, green: v.1, blue: v.2)
    }
    static func ground(_ i: Int) -> Color { c(groundC, i) }
    static func vivid(_ i: Int) -> Color { c(vividC, i) }

    /// The frame tone — a DEEP, saturated shade of the accent (same hue, richer
    /// and darker), hand-picked per theme. Scaling the vivid toward grey read
    /// murky, so these are set directly. Mono has a white accent, so its bezel
    /// goes near-black.
    private static let frameC: [(Double, Double, Double)] = [
        (0.030, 0.140, 0.480),  // blue    → deep blue
        (0.090, 0.090, 0.100),  // mono    → near-black
        (0.020, 0.320, 0.210),  // emerald → deep emerald
        (0.500, 0.280, 0.030),  // amber   → deep amber
        (0.500, 0.100, 0.150),  // coral   → deep rose
        (0.020, 0.320, 0.420),  // aqua    → deep teal
    ]
    static func frame(_ i: Int) -> Color { c(frameC, i) }
}

/// The shared pixel unit for the streak widget — the mascot's face pixels AND
/// the background grid cells both use this, so the whole surface reads as one
/// coherent pixel display. Sized so the 11×11 face fits both families.
let streakPixel: CGFloat = 8

struct WidgetGrid: View {
    var theme: Int = 0
    /// Corner shape — matches the home-screen widget's own radius via
    /// `ContainerRelativeShape` inside a widget; a rounded rect elsewhere (the
    /// app's design-review gallery).
    var shape: AnyShape = AnyShape(ContainerRelativeShape())
    /// Grid cell size. Default graph-paper spacing; the streak widget passes
    /// `streakPixel` so its grid matches the mascot's pixels.
    var step: CGFloat = 26
    /// How present the graph paper is. 0 = a flat ground, no lines at all.
    var lineOpacity: Double = 0.06
    /// Set on the Free Talk widget: the paper takes its lattice from the
    /// Futureself surface in front of it (`compact` picks the circle or the
    /// pill), so the two are one grid. Left nil, the paper starts at the corner.
    var freeTalkSurface: Bool? = nil

    var body: some View {
        let ground = WidgetTheme.ground(theme)
        let vivid = WidgetTheme.vivid(theme)
        let step = self.step
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            // Grid lines tinted with the theme's vivid colour, very faint.
            let line = vivid.opacity(lineOpacity)
            let phase = freeTalkSurface.map { FutureselfLattice.phase(in: size, compact: $0) } ?? .zero
            var x: CGFloat = phase.width - step
            while x <= size.width {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(line), lineWidth: 1)
                x += step
            }
            var y: CGFloat = phase.height - step
            while y <= size.height {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(line), lineWidth: 1)
                y += step
            }
        }
        // Inner shadow — a soft dark ring hugging the edge, recessed-display feel.
        .overlay {
            shape
                .stroke(Color.black.opacity(0.8), lineWidth: 14)
                .blur(radius: 9)
                .mask(shape)
        }
        // Thick display bezel in the theme tone (stroke is centered on the
        // edge; the OS clips the outer half, leaving a solid inner frame).
        .overlay {
            shape.stroke(WidgetTheme.frame(theme), lineWidth: 9)
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
    /// A KEY, not a String: the empty state is the one line here that has to be
    /// translated, and a `String` would neither extract into the catalog nor
    /// follow the widget's locale.
    let emptyText: LocalizedStringKey
    var compact: Bool = false
    /// The pixel word's colour — the theme's vivid tone.
    var wordColor: Color = .white
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
                    .foregroundStyle(wordColor)
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

// MARK: - Free Talk card (the Futureself surface itself), shared

/// The shared pixel unit for the Futureself surface — the app pins every live
/// surface to this cell size (`virtualHeight: 64` → 64 / 5 rows), so the widget
/// uses it too and the mosaic never changes scale between them. The background
/// grid steps by the same number, so surface and graph paper line up as one
/// display (the same trick the streak widget plays with `streakPixel`).
let futureselfCell: CGFloat = 12.8

/// Where the lattice that the surface and the background grid SHARE actually
/// sits. Both derive it from the container size alone, so neither has to
/// measure the other across two view trees (the grid is a `containerBackground`).
///
/// Two rules. The surface is a whole number of cells in each direction, so its
/// straight edges land ON lattice lines instead of slicing a row of slivers the
/// full width of the pill. And the lattice is then anchored to the SURFACE
/// rather than the widget's corner, so the shape stays centred: the leftover
/// fraction moves to the tile's own edge, where the widget's rounded corner eats
/// it unseen.
enum FutureselfLattice {
    /// The surface's padding from the widget edge, before snapping.
    static func inset(compact: Bool) -> CGFloat { compact ? 12 : 16 }

    static func surfaceSize(in container: CGSize, compact: Bool) -> CGSize {
        let cell = futureselfCell
        let pad = inset(compact: compact) * 2
        func cells(_ available: CGFloat) -> CGFloat {
            max(cell, (available / cell).rounded(.down) * cell)
        }
        // Both families wear the call bar's pill: as wide as fits, and five
        // cells tall on a small widget — 64pt, the app's own pill height at this
        // cell size. The wide one grows to eight so it doesn't read as a stripe
        // lost in the tile.
        let rows: CGFloat = compact ? 5 : 8
        return CGSize(width: cells(container.width - pad),
                      height: min(cells(container.height - pad), cell * rows))
    }

    /// The lattice offset both the surface and the graph paper start from.
    static func phase(in container: CGSize, compact: Bool) -> CGSize {
        let s = surfaceSize(in: container, compact: compact)
        return CGSize(width: ((container.width - s.width) / 2).truncatingRemainder(dividingBy: futureselfCell),
                      height: ((container.height - s.height) / 2).truncatingRemainder(dividingBy: futureselfCell))
    }
}

/// One tap to call your fluent self — the Futureself surface wearing the app's
/// call bar: a PILL at both families, with "Let's talk" inside it as the app's
/// ring carries the same words. The live Metal shader can't run in a widget, so
/// the surface is `FutureselfPixels`, a static port of the same math.
struct FreeTalkCard: View {
    var theme: Int = 0
    /// Small family — a shorter pill and smaller type.
    var compact: Bool = true
    /// The frozen instant of the shader's clock — vary it per widget reload for
    /// a surface that isn't identical every day.
    var time: Double = 3.2

    /// A still is not a live surface, and the shader's own distribution — tuned
    /// for a mosaic that moves — reads as clutter when it's frozen: colour
    /// everywhere and the lightest tone sparkling in a dozen places at once. So
    /// the widget holds the same lit-cell COUNT (the grid is unchanged) and
    /// pushes the distribution down hard, then withholds the top tone. Blue
    /// becomes the accent it is in the app, not the background.
    /// A small pill holds ~50 cells against the wide one's ~190, so the same
    /// curve leaves it with one or two blue cells — empty, not calm. What the
    /// two families have to share is the DENSITY (~10% of cells coloured), so
    /// the small one gets its own, gentler number.
    private var colourFalloff: Double { compact ? 2.2 : 5 }
    private let maxStep = 3
    private let level = 0.5
    private let wash = 0.14

    var body: some View {
        GeometryReader { geo in
            let size = FutureselfLattice.surfaceSize(in: geo.size, compact: compact)
            surface(Capsule()) { label(compact ? 16 : 24) }
                .frame(width: size.width, height: size.height)
                // Centred in the widget; the lattice follows the surface, so
                // centring costs no alignment.
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Pieces

    /// The surface itself, in whatever shape this pose calls for — mosaic, the
    /// app's uniform inner shadow, a separator hairline, and the ground wash the
    /// app's ring uses so the type reads.
    private func surface<S: InsettableShape, Content: View>(
        _ shape: S, @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            // Cells are the BACKGROUND GRID's cells — the surface reads as that
            // graph paper lighting up inside the shape, not as a second grid
            // pasted over it. The surface DEFINES the lattice (it's a whole
            // number of cells, so its corner is a lattice corner) and the grid
            // behind it takes the phase; gaps stay clear so the grid's own lines
            // run straight through.
            FutureselfPixels(theme: theme, mode: .speaking, level: level,
                             time: time, cell: futureselfCell,
                             opaqueGaps: false, colourFalloff: colourFalloff,
                             maxStep: maxStep, dark: true)
            WidgetTheme.ground(theme).opacity(wash)
            shape
                .strokeBorder(Color.black.opacity(0.45), lineWidth: 10)
                .blur(radius: 6)
                .mask(shape)
            content()
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }

    private func label(_ size: CGFloat) -> some View {
        Text("Let's talk")
            .font(pixelFont(size))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
    }
}

// MARK: - Progress card (goal ring + streak / review / study counts), shared

/// The learning-progress surface: today's goal ring anchors it, with streak,
/// review-due, and study counts alongside — all on the same themed grid the
/// word widgets wear. Deterministic numbers only; tapping opens Practice →
/// Studying. Shared so the app's design-review gallery renders it identically.
struct ProgressCard: View {
    var theme: Int = 0
    var todaySeconds: Int = 0
    var goalMinutes: Int = 10
    var streakDays: Int = 0
    var dueCount: Int = 0
    var studyingWords: Int = 0
    var studyingExpressions: Int = 0
    var compact: Bool = false

    private var vivid: Color { WidgetTheme.vivid(theme) }
    private var minutes: Int { todaySeconds / 60 }
    private var progress: Double {
        min(1, Double(todaySeconds) / Double(max(1, goalMinutes * 60)))
    }

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: compact ? 8 : 10) {
            Text("Studying")
                .font(pixelFont(compact ? 11 : 13))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
            if compact { compactBody } else { mediumBody }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(compact ? 12 : 15)
    }

    // MARK: Goal ring

    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(vivid, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(minutes)")
                    .font(pixelFont(size * 0.36))
                    .foregroundStyle(vivid)
                Text("/ \(goalMinutes)m")
                    .font(pixelFont(size * 0.13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Medium — ring + three stat rows

    private var mediumBody: some View {
        HStack(spacing: 16) {
            ring(size: 92, lineWidth: 9)
            VStack(alignment: .leading, spacing: 11) {
                statRow("flame.fill", "\(streakDays)", "day streak",
                        tint: streakDays > 0 ? vivid : .white.opacity(0.4))
                statRow("checklist", "\(dueCount)", "to review",
                        tint: dueCount > 0 ? vivid : .white.opacity(0.4))
                studyRow
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func statRow(_ icon: String, _ value: String, _ label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 17)
            Text(value).font(pixelFont(17)).foregroundStyle(tint)
            Text(label).font(pixelFont(12)).foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
    }

    private var studyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(vivid)
                .frame(width: 17)
            Text("\(studyingWords)").font(pixelFont(17)).foregroundStyle(vivid)
            Text("words").font(pixelFont(12)).foregroundStyle(.white.opacity(0.55))
            Text("\(studyingExpressions)").font(pixelFont(17)).foregroundStyle(vivid)
            Text("phrases").font(pixelFont(12)).foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
    }

    // MARK: Small — ring + two mini stats

    private var compactBody: some View {
        VStack(spacing: 9) {
            ring(size: 72, lineWidth: 8)
            HStack(spacing: 14) {
                miniStat("flame.fill", "\(streakDays)", streakDays > 0 ? vivid : .white.opacity(0.4))
                miniStat("checklist", "\(dueCount)", dueCount > 0 ? vivid : .white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func miniStat(_ icon: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(pixelFont(15)).foregroundStyle(tint)
        }
    }
}

// MARK: - Continue card (one in-progress book → its detail page), shared

/// The book you're mid-way through — its title, a mastery progress bar, and a
/// "Continue" affordance, on the themed grid. Tapping opens the book's detail
/// page (Talk → the conversation, Watch → the scenario). Titles use a readable
/// system face (they're full phrases); only the counts stay pixel, matching
/// the other widgets' accent treatment.
struct BookCard: View {
    var theme: Int = 0
    var hasBook: Bool = true
    var kind: String = "talk"      // "talk" | "watch"
    var title: String = ""
    var subtitle: String = ""
    var mastered: Int = 0
    var total: Int = 0
    var compact: Bool = false

    private var vivid: Color { WidgetTheme.vivid(theme) }
    private var progress: Double { total == 0 ? 0 : min(1, Double(mastered) / Double(total)) }

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            Text("Studying")
                .font(pixelFont(compact ? 11 : 13))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
            if hasBook { bookBody } else { emptyBody }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(compact ? 12 : 15)
    }

    private var bookBody: some View {
        VStack(spacing: compact ? 6 : 8) {
            // The title block claims the flexible middle (via maxHeight:.infinity)
            // so the title can use its full line allowance instead of being
            // squeezed to one line by greedy spacers.
            VStack(spacing: 5) {
                Text(title)
                    .font(pixelFont(compact ? 15 : 20))
                    .foregroundStyle(vivid)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                if !compact && !subtitle.isEmpty {
                    Text(subtitle)
                        .font(pixelFont(12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            progressRow
        }
    }

    private var progressRow: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(vivid)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 6)
            HStack(spacing: 5) {
                Text("\(mastered)/\(total)")
                    .font(pixelFont(compact ? 12 : 14))
                    .foregroundStyle(vivid)
                Text("mastered")
                    .font(pixelFont(compact ? 11 : 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "books.vertical.fill")
                .font(.system(size: compact ? 24 : 30))
                .foregroundStyle(vivid.opacity(0.85))
            Text("Nothing in progress")
                .font(pixelFont(compact ? 12 : 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pixel face (streak mascot), shared

/// The streak mascot's mood — drives which pixel face renders.
enum StreakFace { case happy, anxious, neutral }

/// A tiny face drawn on the pixel grid, matching the widgets' Futureself look.
/// Each row is a string: '#' = accent pixel, 'o' = a marker pixel (sweat drop)
/// in a second colour, space = empty. Rendered crisply via Canvas so it stays
/// sharp at any size (and works inside a widget, where shaders can't run).
struct PixelFace: View {
    let expression: StreakFace
    var color: Color
    var marker: Color = Color(red: 0.55, green: 0.8, blue: 1.0)

    // Same 11×11 features as the reference faces, but with the outline removed —
    // just dot eyes + a curved smile / flat / frown mouth (sweat bead when anxious).
    private var rows: [String] {
        switch expression {
        case .happy:      // dot eyes + wide smile
            return ["           ",
                    "           ",
                    "           ",
                    "   #   #   ",
                    "           ",
                    "           ",
                    "  #     #  ",
                    "   #####   ",
                    "           ",
                    "           ",
                    "           "]
        case .anxious:    // dot eyes, frown, a sweat bead (o)
            return ["           ",
                    "           ",
                    " o         ",
                    "   #   #   ",
                    "           ",
                    "           ",
                    "   #####   ",
                    "  #     #  ",
                    "           ",
                    "           ",
                    "           "]
        case .neutral:    // dot eyes, flat mouth (resting)
            return ["           ",
                    "           ",
                    "           ",
                    "   #   #   ",
                    "           ",
                    "           ",
                    "           ",
                    "   #####   ",
                    "           ",
                    "           ",
                    "           "]
        }
    }

    var body: some View {
        let grid = rows
        Canvas { ctx, size in
            let cols = grid.map(\.count).max() ?? 1
            let rowsN = grid.count
            let cell = min(size.width / CGFloat(cols), size.height / CGFloat(rowsN))
            let ox = (size.width - cell * CGFloat(cols)) / 2
            let oy = (size.height - cell * CGFloat(rowsN)) / 2
            for (r, line) in grid.enumerated() {
                for (c, ch) in line.enumerated() where ch != " " {
                    let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell,
                                      width: cell * 0.9, height: cell * 0.9)
                    ctx.fill(Path(rect), with: .color(ch == "o" ? marker : color))
                }
            }
        }
    }
}

// MARK: - Streak card (Duolingo-style day counter), shared

/// A pixel-face mascot + day count that pushes the learner to keep their run
/// going — the face's mood tracks state (smiling once today's done, anxious
/// while the day slips by unmet). On the same themed grid as the other widgets;
/// tapping opens Talk to do an activity.
struct StreakCard: View {
    var theme: Int = 0
    var streakDays: Int = 0
    var doneToday: Bool = false
    /// When this entry renders, and the streak's daily deadline (next midnight).
    /// The mascot's mood and the countdown are driven by the gap between them —
    /// a huge streak stays calm all morning and only gets anxious near the wire.
    var renderDate: Date = Date()
    var deadline: Date = Date().addingTimeInterval(6 * 3600)
    var compact: Bool = false

    private var vivid: Color { WidgetTheme.vivid(theme) }
    private var atRisk: Bool { streakDays > 0 && !doneToday }
    private var hoursLeft: Double { max(0, deadline.timeIntervalSince(renderDate) / 3600) }

    var body: some View {
        Group {
            if compact { compactBody } else { mediumBody }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(compact ? 12 : 16)
    }

    /// Mood from TIME PRESSURE, not just done/not-done: smiling once today's
    /// goal is met, calm while there's plenty of the day left, anxious only as
    /// the midnight deadline closes in on an unmet streak.
    private var expression: StreakFace {
        if doneToday { return .happy }
        if streakDays == 0 { return .neutral }
        return hoursLeft <= 3 ? .anxious : .neutral
    }

    /// The pixel-face mascot, cells sized to `streakPixel` so it lines up with
    /// the background grid (9×7 matrix).
    private var faceView: some View {
        PixelFace(expression: expression, color: vivid)
            .frame(width: 11 * streakPixel, height: 11 * streakPixel)
    }

    /// A live countdown to the deadline (WidgetKit ticks it every minute).
    private var countdown: some View {
        Text(timerInterval: renderDate...max(renderDate.addingTimeInterval(60), deadline),
             countsDown: true)
    }

    /// The second line: countdown while at risk, else a short status.
    @ViewBuilder private func statusLine(_ size: CGFloat) -> some View {
        if doneToday {
            Text("Done for today").font(pixelFont(size)).foregroundStyle(.white.opacity(0.7))
        } else if streakDays == 0 {
            Text("Start your streak").font(pixelFont(size)).foregroundStyle(.white.opacity(0.7))
        } else {
            HStack(spacing: 4) {
                countdown
                    .font(pixelFont(size))
                    .foregroundStyle(atRisk && hoursLeft <= 3 ? vivid : .white.opacity(0.85))
                    .monospacedDigit()
                Text("left").font(pixelFont(size)).foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
        }
    }

    private var compactBody: some View {
        VStack(spacing: 4) {
            faceView
            Text("\(streakDays)")
                .font(pixelFont(30))
                .foregroundStyle(vivid)
                .lineLimit(1).minimumScaleFactor(0.4)
            statusLine(10)
        }
    }

    private var mediumBody: some View {
        // Face gets the whole left block; number + label + countdown stack on
        // the right (number on its own line, so digit count never shifts them).
        HStack(spacing: 16) {
            faceView
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streakDays)")
                    .font(pixelFont(44))
                    .foregroundStyle(vivid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("day streak")
                    .font(pixelFont(16))
                    .foregroundStyle(.white)
                statusLine(12)
            }
            Spacer(minLength: 0)
        }
    }
}
