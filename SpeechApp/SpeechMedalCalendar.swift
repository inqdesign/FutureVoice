import SwiftUI

/// My days as one endless row (2026-11-12, founder: no frame, no header,
/// scroll back as far as you like). The app puts out one challenge a day, so
/// each slot is that day's challenge: my best on it as a medal, a "+" for one
/// still to read, an empty slot for a day without one. It opens on this week
/// and scrolls back through every day before. The medals and the streak sit
/// under it, small.
struct ArenaMedalCalendar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    /// Challenges by the day they came out.
    let byDay: [Date: SpeechScript]
    let best: (SpeechScript) -> Int?
    let rank: Int?
    let medals: Int
    let streak: Int

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = locale
        return c
    }

    /// From a year back (or the first challenge, if older) to TODAY,
    /// oldest first. Today is always the last slot, so it sits at the right
    /// edge every day (2026-11-16, founder: it moved through the week).
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let earliest = byDay.keys.min() ?? today
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
    }

    @State private var showingGuide = false

    @ViewBuilder
    private func slot(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let start = calendar.startOfDay(for: day)
        let future = start > calendar.startOfDay(for: Date())
        let script = byDay[start]
        let letter = calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        let dayNumber = calendar.component(.day, from: day)
        let content = VStack(spacing: 6) {
            Text(letter)
                .font(.subheadline.weight(today ? .bold : .regular))
                .foregroundStyle(today ? Color.white : Arena.dim.opacity(future ? 0.45 : 1))
            ZStack {
                if let script, let score = best(script), let tier = MedalTier(score: score) {
                    MedalBadge(tier: tier, label: "\(score)", size: 42)
                } else if let script, let score = best(script) {
                    flatSlot(lit: today)
                    Text(verbatim: "\(score)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                } else if let script, !future, let art = ChallengeArt.image(for: script.id) {
                    // Still to read: the challenge's own picture (2026-11-13,
                    // founder), on its cream card ground.
                    Circle().fill(ChallengeArt.paper)
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .clipShape(Circle())
                    Circle().stroke(Color.white.opacity(today ? 0.9 : 0), lineWidth: 1.5)
                } else {
                    flatSlot(lit: today)
                }
            }
            .frame(width: 44, height: 44)
            // The month shows on its first day, so a long scroll back
            // still says where it is.
            Text(dayNumber == 1 ? day.formatted(.dateTime.month(.abbreviated)) : "\(dayNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Arena.dim.opacity(future ? 0.45 : 0.8))
        }
        if let script, !future {
            NavigationLink {
                SpeechArenaDetail(script: script).environmentObject(appState)
            } label: { content }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// An empty slot: flat, no light on it (a lit bead read as a ball).
    private func flatSlot(lit: Bool) -> some View {
        Circle()
            .fill(Color.white.opacity(lit ? 0.14 : 0.07))
            .overlay(Circle().stroke(Color.white.opacity(lit ? 0.9 : 0), lineWidth: 1.5))
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
