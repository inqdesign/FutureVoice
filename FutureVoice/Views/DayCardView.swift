import SwiftUI
import UIKit

/// What goes on a day's card — the day as the app already counts it. Every
/// value is one some screen already shows; the card restates the day, it
/// never computes something of its own.
struct DayCardData: Codable, Equatable {
    var date: Date
    /// Metered talk seconds (`TalkTimeLog`) — the ring's number.
    var talkMinutes: Int
    /// Foreground time (`AppUsageLog`), never less than the talk time.
    var studyMinutes: Int
    /// The streak as it stood that day (`PracticeStats.streakDays(asOf:)`).
    var streakDays: Int
    /// Conversations finished that day.
    var talks: Int
    /// Drill cards graded that day (`PracticeLog`).
    var reviews: Int
    /// Shadow takes that day (`PracticeLog`).
    var shadowTakes: Int
    /// What today's talks were about — each finished conversation's
    /// `displayTitle`, de-duplicated, the day's MAIN talk first (the one the
    /// learner spoke longest in). The card prints only the first: on a real
    /// day the titles are sentences (news talks especially), and a stack of
    /// them buried the photo in text — the rest of the day is the TALKS
    /// number. Kept as a list so frozen snapshots still hold the record.
    var topics: [String]
    static let maxTopics = 4
    /// The headline the learner settled (`DayCardStore.setHeadline`) — one
    /// of `topics`, or their own words. Nil is automatic. Optional with a
    /// default so snapshots written before it decode.
    var headline: String? = nil
    /// Everything else done that day, each in the unit the app counts it in
    /// (only a talk is measured in minutes). Optional so snapshots written
    /// before 2026-11-10 decode; those days list what they have.
    var sayItAgainRuns: Int? = nil
    var speechTakes: Int? = nil
    /// Podcast episodes and situations heard in the player.
    var listens: Int? = nil
    var reads: Int? = nil
    var scenes: Int? = nil
    /// Word and expression cards worked through.
    var words: Int? = nil

    /// What the card prints at the top: the settled headline, else the main
    /// talk's title.
    var title: String? {
        headline.flatMap { $0.isEmpty ? nil : $0 } ?? topics.first
    }

    private static func spokenMs(_ s: Session) -> Int {
        s.turns.filter { $0.role == .user }.reduce(0) { $0 + $1.durationMs }
    }
    /// A picked or generated title, as opposed to `displayTitle`'s fallbacks.
    private static func hasTitle(_ s: Session) -> Bool {
        !(s.topic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Anything on it at all — an empty day has no card.
    var hasActivity: Bool { talkMinutes > 0 || talks > 0 || studyMinutes > 0 }

    /// The day as it should be shown: the FROZEN record when one exists, else
    /// read live from the logs. Frozen wins because the logs are pruned at
    /// 45 days and the streak rule can change — a card is what that day
    /// was, and must not drift afterwards.
    ///
    /// TODAY is the exception and is always read live. It is still being
    /// lived, so a snapshot of it is a number that stopped moving while the
    /// ring beside it kept counting — which is how a card came to read 7 min
    /// next to a home screen reading 11. Builds before 2026-08-31 froze today
    /// the moment the card sheet was opened, so a stale record may still be on
    /// disk; this ignores it, and `DayCardStore.freezePastDays` replaces it
    /// once the day is over.
    @MainActor
    static func resolve(day: Date, calendar: Calendar = .current) -> DayCardData {
        guard !calendar.isDateInToday(day) else { return make(day: day, calendar: calendar) }
        return DayCardStore.shared.snapshot(for: day) ?? make(day: day, calendar: calendar)
    }

    /// The list at the card's bottom left: everything done that day, one
    /// line each, a zero never printed. Talk is minutes (metered); the rest
    /// are counts, because that is what the app records for them.
    struct Line: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
    var lines: [Line] {
        func n(_ count: Int?, _ one: String, _ many: String) -> String? {
            guard let count, count > 0 else { return nil }
            return "\(count) \(count == 1 ? one : many)"
        }
        let rows: [(String, String?)] = [
            ("Talk", talkMinutes > 0 ? "\(talkMinutes) min" : n(talks, "talk", "talks")),
            ("Say it again", n(sayItAgainRuns, "run", "runs")),
            ("Speech", n(speechTakes, "take", "takes")),
            ("Listening", n(listens, "episode", "episodes")),
            ("Reading", n(reads, "article", "articles")),
            ("Scenes", n(scenes, "scene", "scenes")),
            ("Shadowing", n(shadowTakes, "take", "takes")),
            ("Review", n(reviews, "card", "cards")),
            ("Words", n(words, "word", "words")),
        ]
        return rows.compactMap { row in row.1.map { Line(label: row.0, value: $0) } }
    }

    /// Any day the Activity page can select — the card is the day's record,
    /// so yesterday's is as real as today's.
    @MainActor
    static func make(day: Date, calendar: Calendar = .current) -> DayCardData {
        // Every enrolled language: the card is the DAY's, and its minutes
        // already are. Reading the active language alone put the numbers of
        // two talks under the title of none, whenever the second was in the
        // other language.
        let sessions = SessionStore.shared.loadAcrossLanguages()
            .filter { $0.mode == .conversation }
            .filter { s in s.endedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.startedAt < $1.startedAt }
        // Main talk first: the one the learner spoke longest in — among the
        // talks that HAVE a title. A talk whose summary never landed falls
        // back to its first words or "Conversation", and that must not head
        // the card while a titled talk sits beside it.
        let bySpoken = sessions.sorted {
            let (a, b) = (hasTitle($0), hasTitle($1))
            return a != b ? a : spokenMs($0) > spokenMs($1)
        }
        var seen = Set<String>()
        let topics = bySpoken.map(\.displayTitle)
            .filter { seen.insert($0.lowercased()).inserted }
        let talk = TalkTimeLog.seconds(on: day)
        let study = max(AppUsageLog.seconds(on: day), talk)
        let log = PracticeLog.shared.day(day)
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let events = ActivityEventLog.shared.events(from: start, to: end)
        func count(_ kind: ActivityEventLog.Kind) -> Int { events.filter { $0.kind == kind }.count }
        return DayCardData(
            date: day,
            // FLOORED, like the home ring (`todaySpokenSeconds / 60`) and the
            // widget. One rule or none: rounding here put the card a minute
            // ahead of the ring for the same afternoon.
            talkMinutes: talk / 60,
            studyMinutes: study / 60,
            streakDays: PracticeStats.streakDays(asOf: day, calendar: calendar),
            talks: sessions.count,
            reviews: log?.drillReps ?? 0,
            shadowTakes: log?.shadowReps ?? 0,
            topics: Array(topics.prefix(maxTopics)),
            headline: DayCardStore.shared.headline(for: day),
            sayItAgainRuns: count(.sayItAgain),
            speechTakes: count(.speech),
            listens: count(.listen),
            reads: count(.read),
            scenes: log?.sceneReps ?? 0,
            words: (log?.wordReps ?? 0) + (log?.expressionReps ?? 0))
    }
}

enum DayCardFormat: String, CaseIterable, Identifiable {
    /// 9:16 — the tall card, with room for the whole day's list (2026-11-10).
    /// 4:5 is Instagram's feed frame, which Threads takes as is.
    case story, feed, square
    var id: String { rawValue }
    /// Logical size in points; exported at `exportScale` → 1080 wide.
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .feed: CGSize(width: 360, height: 450)
        case .square: CGSize(width: 360, height: 360)
        }
    }
    /// How many lines of the day's list fit under the headline.
    var maxLines: Int {
        switch self {
        case .story: 9
        case .feed: 5
        case .square: 3
        }
    }
    static let exportScale: CGFloat = 3
}

/// The day's card — the design's "A": the place photo full-bleed, today's
/// topics in the pixel face, talk and study minutes, then the call pill (in
/// the learner's own Futureself theme) stamped with the date, and the URL. Nothing else — a card that has to
/// be read isn't a card. Fixed size; `render` turns it into the shared image.
///
/// It is an exported picture, not app chrome, so it wears the brand (ink,
/// paper, the mosaic's blue) rather than system colours — the same face as
/// the landing page.
struct DayCardView: View {
    let data: DayCardData
    let photo: UIImage?
    var format: DayCardFormat = .feed
    /// The learner's Futureself theme — read straight from defaults, because
    /// this view is also drawn by an `ImageRenderer` with no environment.
    var theme: Int = UserDefaults.standard.integer(forKey: "futureselfTheme")

    private let ink = Color(red: 20 / 255, green: 19 / 255, blue: 16 / 255)
    private let paper = Color(red: 252 / 255, green: 251 / 255, blue: 248 / 255)

    private var isFeed: Bool { format != .square }
    private var margin: CGFloat { isFeed ? 24 : 21 }

    /// Top: the date pill and the streak. Bottom: the headline, then the
    /// day's list at the left with the day's total at the right, then the
    /// name. The photo keeps the middle.
    var body: some View {
        let size = format.size
        ZStack(alignment: .topLeading) {
            ink
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            LinearGradient(
                stops: [.init(color: ink.opacity(0.34), location: 0), .init(color: ink.opacity(0), location: 0.2),
                        .init(color: ink.opacity(0), location: format == .story ? 0.38 : 0.26),
                        .init(color: ink.opacity(0.88), location: format == .story ? 0.66 : 0.6),
                        .init(color: ink.opacity(0.95), location: 1)],
                startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    datePill
                    Spacer()
                    if data.streakDays > 0 {
                        Text(verbatim: "\(data.streakDays) day streak").brandPixel(isFeed ? 10.7 : 9.7)
                    }
                }
                Spacer(minLength: 8)
                if let topic = data.title {
                    Text(topic)
                        .brandPixel(isFeed ? 31 : 25)
                        .lineLimit(format == .story ? 3 : 2)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, isFeed ? 14 : 10)
                }
                rule
                HStack(alignment: .bottom, spacing: 12) {
                    list
                    Spacer(minLength: 0)
                    total
                }
                .padding(.vertical, isFeed ? 12 : 9)
                rule
                footer
            }
            .padding(.horizontal, margin)
            .padding(.top, margin)
            .padding(.bottom, isFeed ? 22 : 18)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .foregroundStyle(paper)
        .environment(\.colorScheme, .dark)
        // The card is for a feed, not for the learner: it speaks English
        // whatever the app language, so it reads the same to everyone it
        // reaches. The one place chrome doesn't follow the learner's choice.
        .environment(\.locale, Locale(identifier: "en"))
    }

    private var rule: some View { Rectangle().fill(paper.opacity(0.28)).frame(height: 0.5) }

    /// What was done, one line each: the name small and tracked, the amount
    /// in the pixel face beside it.
    private var list: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: isFeed ? 7 : 5) {
            ForEach(data.lines.prefix(format.maxLines)) { line in
                GridRow {
                    Text(verbatim: line.label)
                        .font(.system(size: isFeed ? 8 : 7.3, design: .monospaced))
                        .tracking(1)
                        .textCase(.uppercase)
                        .opacity(0.72)
                    Text(verbatim: line.value).brandPixel(isFeed ? 13 : 12)
                }
            }
        }
    }

    /// The day's whole time in the app, large, at the bottom right.
    private var total: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: "\(data.studyMinutes)").brandPixel(isFeed ? 40 : 32)
            Text(verbatim: "min today")
                .font(.system(size: isFeed ? 7.3 : 6.7, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .opacity(0.72)
        }
    }

    /// The call screen's pill, shrunk to a badge and carrying the DATE: the
    /// mosaic at a 6.4 pt cell keeps its five rows, capsule-clipped with the
    /// hairline rim, in the learner's Futureself theme — the thing they
    /// talked to, stamped with the day. Dark palette: the card's ground is
    /// ink whatever the phone's mode. A light veil keeps the date legible
    /// over the brightest cells; the name is only in the footer's URL now.
    private var datePill: some View {
        ZStack {
            // Quiet on purpose: a badge, not the call in full voice — low
            // drive and a steep colour falloff leave most cells dark so the
            // date reads and the theme shows as an accent, not a flood.
            FutureselfPixels(theme: theme, mode: .speaking, level: 0.42, time: 3.2,
                             cell: 6.4, colourFalloff: 1.25, maxStep: 3, dark: true)
            ink.opacity(0.18)
            Text(data.date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en"))))
                .brandPixel(isFeed ? 10.7 : 9.7)
        }
        .frame(width: isFeed ? 88 : 80, height: isFeed ? 32 : 29)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(paper.opacity(0.28), lineWidth: 0.5))
    }

    private var footer: some View {
        HStack {
            Text("Learn a language from your fluent self.")
                .brandPixel(isFeed ? 8.7 : 8)
            Spacer()
            Text("nawana.app")
                .font(.system(size: isFeed ? 8.7 : 8, design: .monospaced))
                .tracking(1.2)
                .opacity(0.72)
        }
        .padding(.top, isFeed ? 10.7 : 8.7)
    }
}

extension DayCardView {
    /// The card as a bitmap. Type size is pinned here because an
    /// `ImageRenderer` has no ancestor and would otherwise take the phone's
    /// Dynamic Type; the locale is pinned on the view itself (English).
    @MainActor
    func render(scale: CGFloat = DayCardFormat.exportScale) -> UIImage? {
        let renderer = ImageRenderer(
            content: self.dynamicTypeSize(.large))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer.uiImage
    }
}

/// The app mark, as drawn on the landing page (viewBox 1024).
struct NawanaMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 1024
        var p = Path()
        for r in [(290, 237, 410, 100), (186, 337, 104, 349), (700, 337, 104, 349),
                  (290, 686, 410, 100), (806, 686, 95, 100)] {
            p.addRect(CGRect(x: rect.minX + CGFloat(r.0) * s, y: rect.minY + CGFloat(r.1) * s,
                             width: CGFloat(r.2) * s, height: CGFloat(r.3) * s))
        }
        return p
    }
}
