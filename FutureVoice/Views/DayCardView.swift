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
    /// `displayTitle`, in order, de-duplicated.
    var topics: [String]
    static let maxTopics = 4

    /// Anything on it at all — an empty day has no card.
    var hasActivity: Bool { talkMinutes > 0 || talks > 0 || studyMinutes > 0 }

    /// The day as it should be shown: the FROZEN record when one exists, else
    /// read live from the logs. Frozen wins because the logs are pruned at
    /// 45 days and the streak rule can change — a card is what that day
    /// was, and must not drift afterwards.
    @MainActor
    static func resolve(day: Date, calendar: Calendar = .current) -> DayCardData {
        DayCardStore.shared.snapshot(for: day) ?? make(day: day, calendar: calendar)
    }

    /// The numbers row: talk and study always, then whatever else the day
    /// has, up to four cells — a zero is never printed.
    struct Stat: Identifiable {
        let label: LocalizedStringKey
        let value: String
        var id: String { value + "\(label)" }
    }
    var stats: [Stat] {
        var out = [Stat(label: "Talk", value: "\(talkMinutes) min"),
                   Stat(label: "Study", value: "\(studyMinutes) min")]
        if streakDays > 0 { out.append(Stat(label: "Streak", value: "\(streakDays) days")) }
        if talks > 0 { out.append(Stat(label: "Talks", value: "\(talks)")) }
        if reviews > 0 { out.append(Stat(label: "Reviews", value: "\(reviews)")) }
        if shadowTakes > 0 { out.append(Stat(label: "Shadow", value: "\(shadowTakes)")) }
        return Array(out.prefix(4))
    }

    /// Any day the Activity page can select — the card is the day's record,
    /// so yesterday's is as real as today's.
    @MainActor
    static func make(day: Date, calendar: Calendar = .current) -> DayCardData {
        let sessions = SessionStore.shared.load()
            .filter { $0.mode == .conversation }
            .filter { s in s.endedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { $0.startedAt < $1.startedAt }
        var seen = Set<String>()
        let topics = sessions.map(\.displayTitle)
            .filter { seen.insert($0.lowercased()).inserted }
        let talk = TalkTimeLog.seconds(on: day)
        let study = max(AppUsageLog.seconds(on: day), talk)
        let log = PracticeLog.shared.day(day)
        return DayCardData(
            date: day,
            talkMinutes: Int((Double(talk) / 60).rounded()),
            studyMinutes: Int((Double(study) / 60).rounded()),
            streakDays: PracticeStats.streakDays(asOf: day, calendar: calendar),
            talks: sessions.count,
            reviews: log?.drillReps ?? 0,
            shadowTakes: log?.shadowReps ?? 0,
            topics: Array(topics.prefix(maxTopics)))
    }
}

enum DayCardFormat: String, CaseIterable, Identifiable {
    /// 4:5 — Instagram's tall feed frame, which Threads takes as is. A 9:16
    /// story was the first cut and read as a poster, not a card.
    case feed, square
    var id: String { rawValue }
    /// Logical size in points; exported at `exportScale` → 1080×1350 / 1080×1080.
    var size: CGSize {
        self == .feed ? CGSize(width: 360, height: 450) : CGSize(width: 360, height: 360)
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

    private var isFeed: Bool { format == .feed }
    private var margin: CGFloat { isFeed ? 24 : 21 }

    /// One topic gets the headline size; a list shares the space.
    private var topicSize: CGFloat {
        let base: CGFloat = isFeed ? 35 : 29
        switch data.topics.count {
        case 0, 1: return base
        case 2: return base * 0.74
        default: return base * 0.58
        }
    }

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
                stops: isFeed
                    ? [.init(color: ink.opacity(0.18), location: 0), .init(color: ink.opacity(0), location: 0.26),
                       .init(color: ink.opacity(0), location: 0.40), .init(color: ink.opacity(0.86), location: 0.72),
                       .init(color: ink.opacity(0.94), location: 1)]
                    : [.init(color: ink.opacity(0.16), location: 0), .init(color: ink.opacity(0), location: 0.30),
                       .init(color: ink.opacity(0.88), location: 0.72), .init(color: ink.opacity(0.94), location: 1)],
                startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: isFeed ? 15 : 11) {
                if !data.topics.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(data.topics.enumerated()), id: \.offset) { _, topic in
                            Text(topic)
                                .geistPixel(topicSize)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                statsRow
                footer
            }
            .padding(.horizontal, margin)
            .padding(.bottom, isFeed ? 26 : 21)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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

    /// Up to four numbers in a row — the value in the pixel face, the label
    /// small and tracked beneath, like the stat row under a run.
    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(data.stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.value).geistPixel(isFeed ? 15 : 13)
                    Text(stat.label)
                        .font(.system(size: isFeed ? 7.3 : 6.7, design: .monospaced))
                        .tracking(1)
                        .textCase(.uppercase)
                        .opacity(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                .geistPixel(isFeed ? 10.7 : 9.7)
        }
        .frame(width: isFeed ? 88 : 80, height: isFeed ? 32 : 29)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(paper.opacity(0.28), lineWidth: 0.5))
    }

    private var footer: some View {
        HStack {
            datePill
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Learn a language from your fluent self.")
                    .geistPixel(isFeed ? 8.7 : 8)
                Text("nawana.app")
                    .font(.system(size: isFeed ? 8.7 : 8, design: .monospaced))
                    .tracking(1.2)
                    .opacity(0.72)
            }
        }
        .padding(.top, isFeed ? 10.7 : 8.7)
        .overlay(alignment: .top) { Rectangle().fill(paper.opacity(0.28)).frame(height: 0.5) }
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
