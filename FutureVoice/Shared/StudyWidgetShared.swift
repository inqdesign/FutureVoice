import Foundation
import SwiftUI

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

    /// How many rows the user has manually shuffled past for a section. The
    /// provider adds this to its sliding-window offset so a tap advances the
    /// visible words immediately; wraps naturally via the provider's modulo.
    static func shuffleCursor(_ section: StudyWidgetSection) -> Int {
        defaults?.integer(forKey: "widget_shuffle_\(section.rawValue)") ?? 0
    }

    static func bumpShuffle(_ section: StudyWidgetSection, by rows: Int) {
        let next = shuffleCursor(section) + max(1, rows)
        defaults?.set(next, forKey: "widget_shuffle_\(section.rawValue)")
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

// MARK: - Pinboard render (compiled into app + widget)

/// Deterministic pseudo-randomness for the board. Widgets re-render the same
/// entry many times, and `String.hashValue` is seeded per process — so every
/// jitter (speckle position, sticky rotation, paper colour) derives from
/// these stable hashes instead.
enum WidgetHash {
    /// 0…1 from integer coordinates + seed.
    static func cell(_ a: Int, _ b: Int, _ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(a &+ 1) &* 73_856_093
                       ^ Int64(b &+ 1) &* 19_349_663
                       ^ Int64(seed &+ 1) &* 83_492_791)
        x ^= x >> 33; x = x &* 0xFF51_AFD7_ED55_8CCD; x ^= x >> 33
        return Double(x % 100_000) / 100_000
    }

    /// 0…1 from a string + salt, stable across launches (unlike hashValue).
    static func stable(_ text: String, _ salt: Int) -> Double {
        var acc = UInt64(truncatingIfNeeded: salt) &+ 1_469_598_103
        for u in text.unicodeScalars { acc = acc &* 131 &+ UInt64(u.value) }
        return Double(acc % 100_000) / 100_000
    }
}

/// Corkboard background: warm base with hashed speckles, light and dark
/// variants. Static by design — widgets can't animate; the texture re-seeds
/// per timeline entry so the board subtly changes grain as it slides.
struct CorkSurface: View {
    var seed: Int = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let dark = scheme == .dark
            let base = dark ? Color(red: 0.26, green: 0.19, blue: 0.13)
                            : Color(red: 0.80, green: 0.64, blue: 0.46)
            let deep = dark ? Color(red: 0.18, green: 0.13, blue: 0.08)
                            : Color(red: 0.67, green: 0.51, blue: 0.34)
            let lite = dark ? Color(red: 0.35, green: 0.26, blue: 0.18)
                            : Color(red: 0.88, green: 0.74, blue: 0.56)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

            let count = Int(size.width * size.height / 120)
            for i in 0..<count {
                let hx = WidgetHash.cell(i, 1, seed)
                let hy = WidgetHash.cell(i, 2, seed)
                let hr = WidgetHash.cell(i, 3, seed)
                let hc = WidgetHash.cell(i, 4, seed)
                let r = 0.8 + hr * 1.8
                let rect = CGRect(x: hx * size.width, y: hy * size.height,
                                  width: r * 2, height: r * 1.5)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color((hc < 0.62 ? deep : lite).opacity(0.30 + 0.30 * hr)))
            }
        }
    }
}

/// Classic sticky-note paper colours. Words are colour-coded by CEFR level —
/// mint (A, easy) → yellow (B) → pink (C, advanced), sky for unrated — so the
/// board doubles as a difficulty map. Expressions carry no level and hash
/// their text across the set instead (stable: a phrase keeps its colour).
enum StickyPalette {
    // order: mint · yellow · pink · sky
    private static let light: [Color] = [
        Color(red: 0.79, green: 0.93, blue: 0.70),
        Color(red: 1.00, green: 0.91, blue: 0.52),
        Color(red: 1.00, green: 0.78, blue: 0.80),
        Color(red: 0.76, green: 0.88, blue: 1.00),
    ]
    private static let dim: [Color] = [
        Color(red: 0.61, green: 0.76, blue: 0.52),
        Color(red: 0.84, green: 0.74, blue: 0.38),
        Color(red: 0.85, green: 0.60, blue: 0.62),
        Color(red: 0.58, green: 0.71, blue: 0.86),
    ]

    /// `level` is the CEFR tag ("B1") when the note is level-coded, nil to
    /// fall back to a stable text hash (expressions).
    static func paper(level: String?, text: String, dark: Bool) -> Color {
        let idx: Int
        if let level {
            switch level.first {
            case "A": idx = 0
            case "B": idx = 1
            case "C": idx = 2
            default:  idx = 3   // unrated word
            }
        } else {
            idx = Int(WidgetHash.stable(text, 7) * 4) % 4
        }
        return (dark ? dim : light)[idx]
    }

    /// Handwriting ink — always dark so it reads on paper in both schemes.
    static let ink = Color(red: 0.18, green: 0.14, blue: 0.08)
}

/// One post-it: paper colour hashed from the text, slight rotation, a
/// theme-tinted pushpin, marker-dark ink. Square corners on purpose — it's
/// paper, not an iOS card.
struct StickyNote: View {
    /// Type scale per widget family — large boards get bigger paper, not
    /// just more empty cork.
    enum Size { case compact, regular, large }

    let text: String
    let tag: String
    let pin: Color
    let salt: Int
    var size: Size = .regular
    /// Words colour by CEFR tag; expressions (false) hash their text.
    var levelColored = false
    /// Stretch the paper to fill its slot (large families) instead of
    /// hugging the text — this is what makes notes scale with the widget.
    var expands = false
    /// Paper only as wide as its writing (expressions) — full-width strips
    /// read as banners, not notes.
    var hugsWidth = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(textFont)
                .foregroundStyle(StickyPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if !tag.isEmpty {
                Spacer(minLength: 4)
                Text(tag)
                    .font(.system(size == .large ? .caption : .caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(StickyPalette.ink.opacity(0.45))
            } else if !hugsWidth {
                // Left-aligns the writing on full-width paper. A hugging
                // note must NOT carry it — the Spacer would stretch the
                // HStack right back to the proposed width.
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, size == .large ? 12 : 9)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: hugsWidth ? nil : .infinity,
               maxHeight: expands ? .infinity : nil, alignment: .leading)
        .background(StickyPalette.paper(level: levelColored ? tag : nil,
                                        text: text, dark: scheme == .dark))
        .overlay(alignment: .top) {
            ZStack {
                Circle().fill(pin)
                Circle().fill(.white.opacity(0.55))
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: -1, y: -1)
            }
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .offset(y: -3.5)
        }
        // Flatten before shadowing so the paper casts one clean shadow and
        // the ink stays crisp — without this, .shadow haloes every glyph.
        .compositingGroup()
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.25), radius: 2.5, y: 2)
        .rotationEffect(.degrees((WidgetHash.stable(text, salt) - 0.5) * 5))
    }

    private var textFont: Font {
        switch size {
        case .compact: return .system(.footnote, design: .rounded).weight(.semibold)
        case .regular: return .system(.subheadline, design: .rounded).weight(.semibold)
        case .large:   return .system(.body, design: .rounded).weight(.semibold)
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: return 7
        case .regular: return 9
        case .large:   return 12
        }
    }
}

/// Round white "sticker" holding the shuffle glyph — the widget wraps it in a
/// `Button(intent:)`, the design-review gallery shows it bare. The glyph is
/// always ink, never the theme accent: mono's near-white accent vanished
/// against the white sticker.
struct ShuffleSticker: View {
    var body: some View {
        Image(systemName: "shuffle")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(StickyPalette.ink)
            .padding(6)
            .background(Circle().fill(.white))
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }
}

/// The whole board: masking-tape header label, sticky notes in one or two
/// columns, an optional trailing accessory (the shuffle button). Shared so the
/// widget and the app's capture gallery render the exact same layout.
struct PinboardBoard<Accessory: View>: View {
    let section: StudyWidgetSection
    let items: [StudyWidgetItem]
    let theme: Int
    let seed: Int
    let capacity: Int
    let columns: Int
    /// Vertical gap between notes — larger families spread their notes out so
    /// the board fills instead of clustering at the top.
    var noteSpacing: CGFloat = 12
    var noteSize: StickyNote.Size = .regular
    /// Large families: notes stretch to share the board's full height, so the
    /// paper scales with the widget instead of leaving bare cork below.
    var fillsBoard = false
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pin = FutureselfWidgetPalette.accent(theme: theme, dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 10) {
            header
            if items.isEmpty {
                Spacer(minLength: 0)
                StickyNote(text: emptyText, tag: "", pin: pin, salt: 1)
                Spacer(minLength: 0)
            } else if columns >= 2 {
                let shown = Array(items.prefix(capacity).enumerated())
                HStack(alignment: .top, spacing: 12) {
                    noteColumn(shown.filter { $0.offset.isMultiple(of: 2) }, pin: pin)
                    noteColumn(shown.filter { !$0.offset.isMultiple(of: 2) }, pin: pin)
                }
                if !fillsBoard { Spacer(minLength: 0) }
            } else {
                let shown = Array(items.prefix(capacity).enumerated())
                ForEach(shown, id: \.offset) { i, item in
                    // Expressions hug their writing and land staggered
                    // (left / center / right) like notes actually pinned to
                    // a board; full-width strips read as banners.
                    // Each note deep-links to ITS item (word/phrase) so a tap
                    // opens that page — not just the list. (Links are per-note
                    // on medium/large; small falls back to the widgetURL.)
                    Link(destination: noteLink(item.text)) {
                        StickyNote(text: item.text,
                                   tag: section.showsNote ? item.note : "",
                                   pin: pin, salt: seed &+ i, size: noteSize,
                                   levelColored: section.showsNote,
                                   expands: fillsBoard,
                                   hugsWidth: section == .expressions)
                    }
                    .frame(maxWidth: .infinity, alignment: staggerAlignment(i))
                    if !fillsBoard, i < shown.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func noteColumn(_ slice: [(offset: Int, element: StudyWidgetItem)],
                            pin: Color) -> some View {
        VStack(spacing: noteSpacing) {
            ForEach(slice, id: \.offset) { pair in
                Link(destination: noteLink(pair.element.text)) {
                    StickyNote(text: pair.element.text,
                               tag: section.showsNote ? pair.element.note : "",
                               pin: pin, salt: seed &+ pair.offset, size: noteSize,
                               levelColored: section.showsNote,
                               expands: fillsBoard)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsBoard ? .infinity : nil)
    }

    /// Per-note deep link to its specific word/phrase.
    private func noteLink(_ text: String) -> URL {
        section.deepLink(for: text) ?? URL(string: "futurevoice://practice")!
    }

    /// A strip of masking tape carrying the label, slightly askew.
    private var header: some View {
        HStack(spacing: 6) {
            Text(section.shortLabel)
                .foregroundStyle(StickyPalette.ink.opacity(0.75))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Rectangle().fill(.white.opacity(0.82)))
                .compositingGroup()
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .rotationEffect(.degrees(-1.5))
            Spacer()
            accessory()
        }
    }

    /// Where a hugging note lands in its row — cycles by position + seed so
    /// each shuffle re-pins the notes somewhere new. Words fill their row, so
    /// alignment is moot for them.
    private func staggerAlignment(_ index: Int) -> Alignment {
        let h = WidgetHash.cell(index, 9, seed)
        if h < 0.4 { return .leading }
        if h < 0.7 { return .center }
        return .trailing
    }

    private var emptyText: String {
        section == .words
            ? "No saved words yet — tap a word in a talk to save it."
            : "Nothing collected yet — have a talk, phrases land here."
    }
}

/// Colour ramps mirroring `Futureself.metal`'s `kPalette` (dark + light
/// variants, 5 steps: near-ground → vivid). The board only uses the vivid
/// step (pushpins, count), which keeps the widget on the app's chosen theme.
enum FutureselfWidgetPalette {
    private static let dark: [[Color]] = [
        [c(0.020,0.028,0.060), c(0.080,0.095,0.130), c(0.020,0.130,0.400), c(0.040,0.360,0.960), c(0.480,0.720,1.000)], // blue
        [c(0.020,0.020,0.022), c(0.090,0.090,0.095), c(0.220,0.220,0.230), c(0.550,0.550,0.560), c(0.960,0.960,0.970)], // mono
        [c(0.015,0.030,0.025), c(0.075,0.100,0.090), c(0.020,0.230,0.160), c(0.050,0.640,0.420), c(0.560,0.940,0.760)], // emerald
        [c(0.040,0.028,0.015), c(0.110,0.095,0.070), c(0.400,0.220,0.020), c(0.960,0.560,0.050), c(1.000,0.830,0.480)], // amber
        [c(0.040,0.015,0.030), c(0.110,0.070,0.085), c(0.380,0.050,0.140), c(0.950,0.230,0.320), c(1.000,0.640,0.660)], // coral
        [c(0.012,0.030,0.036), c(0.070,0.100,0.108), c(0.015,0.230,0.280), c(0.040,0.640,0.760), c(0.560,0.940,1.000)], // aqua
    ]
    private static let light: [[Color]] = [
        [c(0.965,0.972,1.000), c(0.900,0.922,0.970), c(0.720,0.830,1.000), c(0.450,0.680,1.000), c(0.030,0.340,0.950)],
        [c(0.970,0.970,0.972), c(0.905,0.905,0.910), c(0.760,0.760,0.770), c(0.420,0.420,0.430), c(0.070,0.070,0.080)],
        [c(0.960,0.980,0.970), c(0.885,0.925,0.905), c(0.700,0.900,0.800), c(0.350,0.780,0.560), c(0.020,0.480,0.300)],
        [c(1.000,0.975,0.950), c(0.945,0.910,0.860), c(1.000,0.850,0.620), c(1.000,0.690,0.330), c(0.900,0.450,0.020)],
        [c(1.000,0.960,0.960), c(0.950,0.890,0.890), c(1.000,0.760,0.760), c(0.990,0.500,0.520), c(0.870,0.120,0.230)],
        [c(0.955,0.980,0.985), c(0.880,0.925,0.930), c(0.680,0.890,0.930), c(0.300,0.760,0.850), c(0.020,0.480,0.590)],
    ]

    static func ramp(theme: Int, dark isDark: Bool) -> [Color] {
        let table = isDark ? dark : light
        return table[(theme % table.count + table.count) % table.count]
    }

    /// The vivid step — pins, count badge, shuffle glyph.
    static func accent(theme: Int, dark isDark: Bool) -> Color { ramp(theme: theme, dark: isDark)[4] }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}
