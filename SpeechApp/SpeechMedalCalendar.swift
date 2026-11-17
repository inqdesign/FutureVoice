import SwiftUI

/// One day's practice: a script read that day, its best score that day, and
/// how many takes.
struct ArenaDayItem: Identifiable {
    let script: SpeechScript
    let best: Int
    let takes: Int
    var id: UUID { script.id }
}

/// My days as one endless row (2026-11-12, founder: no frame, no header,
/// scroll back as far as you like). Since 2026-11-15 it is my DAILY ACTIVITY,
/// not the challenge list by release date (founder: as a list of challenges
/// it was only a shortcut, and a past challenge done today lit nothing
/// today). A day with practice shows what was read: one picture, or a collage
/// of up to four, with the day's best score on a pill; a tap lists that
/// day's takes. The streak under it counts the same days.
struct ArenaMedalCalendar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    /// What was read each day, best score first.
    let activity: [Date: [ArenaDayItem]]
    let rank: Int?
    let medals: Int
    let streak: Int

    @State private var showingGuide = false
    @State private var openDay: OpenDay?
    /// A day with ONE challenge opens that challenge straight away (2026-11-15,
    /// founder: a list of one is an extra step).
    @State private var openScript: SpeechScript?
    private struct OpenDay: Identifiable {
        let day: Date
        let items: [ArenaDayItem]
        var id: Date { day }
    }

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = locale
        return c
    }

    /// From a year back (or the first day practised, if older) to TODAY,
    /// oldest first. Today is always the last slot, so it sits at the right
    /// edge every day (2026-11-16, founder: it moved through the week).
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let earliest = activity.keys.min() ?? today
        let yearBack = calendar.date(byAdding: .day, value: -364, to: today)!
        let first = calendar.startOfDay(for: min(earliest, yearBack))
        var out: [Date] = []
        var day = first
        while day < end {
            out.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let slot = (geo.size.width) / 7
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            self.slot(day).frame(width: slot)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .defaultScrollAnchor(.trailing)
            }
            .frame(height: 96)
            .padding(.horizontal, -16)
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                if let rank { Text("#\(rank)") }
                Button { showingGuide = true } label: {
                    HStack(spacing: 3) {
                        Text("\(medals) medals")
                        Image(systemName: "info.circle")
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak > 0 ? Arena.accent : Arena.dim)
                    Text("\(streak)-day streak")
                }
            }
            .font(.footnote)
            .foregroundStyle(Arena.dim)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingGuide) { MedalGuideSheet() }
        .sheet(item: $openDay) { open in
            ArenaDaySheet(day: open.day, items: open.items)
                .environmentObject(appState)
        }
        .navigationDestination(item: $openScript) { script in
            SpeechArenaDetail(script: script).environmentObject(appState)
        }
    }

    @ViewBuilder
    private func slot(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let start = calendar.startOfDay(for: day)
        let future = start > calendar.startOfDay(for: Date())
        let items = activity[start] ?? []
        let letter = calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        let dayNumber = calendar.component(.day, from: day)
        let content = VStack(spacing: 6) {
            Text(letter)
                .font(.subheadline.weight(today ? .bold : .regular))
                .foregroundStyle(today ? Color.white : Arena.dim.opacity(future ? 0.45 : 1))
            ZStack(alignment: .bottomTrailing) {
                if items.isEmpty {
                    flatSlot(lit: today)
                } else {
                    ArenaDayCollage(items: items)
                        .overlay(Circle().stroke(Color.white.opacity(today ? 0.9 : 0), lineWidth: 1.5))
                    if let best = items.map(\.best).max() {
                        scorePill(best).offset(x: 6, y: 4)
                    }
                }
            }
            .frame(width: 44, height: 44)
            // The month shows on its first day, so a long scroll back
            // still says where it is.
            Text(dayNumber == 1 ? day.formatted(.dateTime.month(.abbreviated)) : "\(dayNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Arena.dim.opacity(future ? 0.45 : 0.8))
        }
        if items.isEmpty {
            content
        } else {
            Button {
                if items.count == 1, items[0].script.isChallenge {
                    openScript = items[0].script
                } else {
                    openDay = OpenDay(day: start, items: items)
                }
            } label: { content }
                .buttonStyle(.plain)
        }
    }

    /// The day's best score, in its medal's colour (grey under a medal).
    private func scorePill(_ score: Int) -> some View {
        let tier = MedalTier(score: score)
        return Text(verbatim: "\(score)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(tier == nil ? Color.white : Color.black)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(Capsule().fill(tier.map { Color($0.metal) } ?? Color(white: 0.24)))
            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
    }

    /// An empty slot: flat, no light on it (a lit bead read as a ball).
    private func flatSlot(lit: Bool) -> some View {
        Circle()
            .fill(Color.white.opacity(lit ? 0.14 : 0.07))
            .overlay(Circle().stroke(Color.white.opacity(lit ? 0.9 : 0), lineWidth: 1.5))
    }
}

/// The pictures of a day's scripts in one circle: one fills it, two split it,
/// three are one big and two small, four or more are four tiles with the
/// rest counted on the last.
struct ArenaDayCollage: View {
    let items: [ArenaDayItem]
    private let gap: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let half = (w - gap) / 2, halfH = (h - gap) / 2
            ZStack(alignment: .topLeading) {
                Color.black
                switch items.count {
                case 1:
                    tile(items[0]).frame(width: w, height: h)
                case 2:
                    HStack(spacing: gap) {
                        tile(items[0]).frame(width: half, height: h)
                        tile(items[1]).frame(width: half, height: h)
                    }
                case 3:
                    HStack(spacing: gap) {
                        tile(items[0]).frame(width: half, height: h)
                        VStack(spacing: gap) {
                            tile(items[1]).frame(width: half, height: halfH)
                            tile(items[2]).frame(width: half, height: halfH)
                        }
                    }
                default:
                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            tile(items[0]).frame(width: half, height: halfH)
                            tile(items[1]).frame(width: half, height: halfH)
                        }
                        HStack(spacing: gap) {
                            tile(items[2]).frame(width: half, height: halfH)
                            tile(items[3])
                                .frame(width: half, height: halfH)
                                .overlay {
                                    if items.count > 4 {
                                        Color.black.opacity(0.55)
                                        Text(verbatim: "+\(items.count - 3)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .clipShape(Circle())
    }

    /// One script's picture on the card's cream, the figure's upper part
    /// filling the tile; a script with no picture shows its kind.
    private func tile(_ item: ArenaDayItem) -> some View {
        ZStack {
            ChallengeArt.paper
            if let art = ChallengeArt.image(for: item.script.id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.35, anchor: UnitPoint(x: 0.5, y: 0.3))
            } else {
                Image(systemName: item.script.genre.symbol)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.7))
            }
        }
        .clipped()
    }
}

/// One day's practice: every script read that day, its takes and its best
/// score that day. A challenge opens its page.
struct ArenaDaySheet: View {
    let day: Date
    let items: [ArenaDayItem]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    if item.script.isChallenge {
                        NavigationLink {
                            SpeechArenaDetail(script: item.script).environmentObject(appState)
                        } label: { row(item) }
                    } else {
                        row(item)
                    }
                }
            }
            .navigationTitle(Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: ArenaDayItem) -> some View {
        HStack(spacing: 12) {
            ArenaDayCollage(items: [item])
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.script.title).lineLimit(2)
                Text("\(item.takes) takes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let tier = MedalTier(score: item.best)
            Text(verbatim: "\(item.best)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tier == nil ? Color.white : Color.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(tier.map { Color($0.metal) } ?? Color(white: 0.24)))
        }
    }
}

/// How medals work (2026-11-13, founder): a medal is your own best score, so
/// anyone can win gold; the rank is the board, and the two are separate.
struct MedalGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MedalTier.allCases, id: \.self) { tier in
                        HStack(spacing: 14) {
                            MedalBadge(tier: tier, label: "\(tier.bar)", size: 40)
                            Text(name(tier))
                            Spacer()
                            Text(verbatim: "\(tier.bar)+")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Your best take on a challenge earns its medal. Everyone who reaches the score gets it.")
                }
                Section("Rank") {
                    Text("Your place on the challenge's board, by best score. It's separate from the medal: gold and 7th place can go together.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How medals work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func name(_ tier: MedalTier) -> LocalizedStringKey {
        switch tier {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }
}
