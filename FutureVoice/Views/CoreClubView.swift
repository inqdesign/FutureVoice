import SwiftUI

/// The Core, from wherever the learner currently stands. One screen, three
/// states, because they are three points on one path rather than three
/// features:
///
///   * **Challenger** — hasn't qualified. Sees a DISTANCE ("6 days to go"),
///     never a verdict. No "failed", no "start over": the window is rolling,
///     so a missed day defers entry by a day, and the copy has to say so or
///     the learner will read a gap as a broken streak and quit.
///   * **Seated** — in the club. Sees tenure and the week's cushion, not a
///     rank. Rank decides who gets in; inside, everyone is equal, and a
///     leaderboard here would rebuild the anxiety the design removed.
///   * **Seatless** — qualified, currently out. Sees that the badge is
///     permanent and how far the way back is. Never a scolding, never a
///     record of who took the seat.
struct CoreClubView: View {
    @State private var progress: CoreClubService.Progress?
    @State private var isLoading = true

    var body: some View {
        List {
            if let p = progress {
                Section { header(p) }
                Section {
                    monthGrid(p)
                } header: {
                    Text("Last 30 days")
                } footer: {
                    Text(explain("A missed day pushes your date back by one. Nothing resets to zero."))
                }
                Section {
                    LabeledContent("Seats") {
                        Text(verbatim: "\(p.club_size) / \(p.seats)")
                            .monospacedDigit()
                    }
                } footer: {
                    Text(explain("A seat only opens when the member holding it stops showing up — never because someone new outranked them."))
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                Text(explain("The Core is unavailable right now."))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("The Core")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header, one per state

    @ViewBuilder
    private func header(_ p: CoreClubService.Progress) -> some View {
        if let m = p.member, m.seated {
            seatedHeader(p, m)
        } else if let m = p.member {
            seatlessHeader(p, m)
        } else {
            challengerHeader(p)
        }
    }

    private func seatedHeader(_ p: CoreClubService.Progress,
                              _ m: CoreClubService.Progress.Member) -> some View {
        Group {
            CoreSealLabel(seated: true, joinNumber: m.join_number)
            LabeledContent("Total days") {
                Text(verbatim: "\(m.days_total)").monospacedDigit()
            }
            LabeledContent("This week") {
                Text(verbatim: "\(p.met_keep) / \(p.keep_required)").monospacedDigit()
            }
            Text(explain("While you hold a seat you get \(p.bonus_seconds / 60) extra minutes of talk a day."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func seatlessHeader(_ p: CoreClubService.Progress,
                                _ m: CoreClubService.Progress.Member) -> some View {
        Group {
            CoreSealLabel(seated: false, joinNumber: m.join_number)
            LabeledContent("Total days") {
                Text(verbatim: "\(m.days_total)").monospacedDigit()
            }
            if p.waiting_for_seat {
                Text(explain("You're above the bar. The next seat to open is yours."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else if let back = p.days_to_return {
                bigNumber(back, label: "Days to return")
                if p.requalifying {
                    Text(explain("You've been away a while, so the full month counts again."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text(explain("Your number and your days are yours for good — a seat is the only thing that comes and goes."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func challengerHeader(_ p: CoreClubService.Progress) -> some View {
        Group {
            if let togo = p.days_to_entry {
                bigNumber(togo, label: "Days to entry")
            }
            LabeledContent("Days met") {
                Text(verbatim: "\(p.met_entry) / \(p.entry_required)").monospacedDigit()
            }
            LabeledContent("Absences") {
                // Spare, not "remaining lives" — the window forgives by
                // deferring, so this is a cushion and not a countdown to
                // failure.
                Text(verbatim: "\(p.missedInEntryWindow) · \(p.spareAbsences)")
                    .monospacedDigit()
            }
            LabeledContent("Daily goal") {
                Text("\(p.bar_seconds / 60) min")
            }
        }
    }

    private func bigNumber(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.coreClub)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - The month

    /// One dot per day in the entry window, oldest first. The point of
    /// drawing all thirty is to make the ROLLING window visible: the gaps
    /// slide off the left edge as the days pass, which is the difference
    /// between "deferred" and "broken".
    private func monthGrid(_ p: CoreClubService.Progress) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
            spacing: 8
        ) {
            ForEach(Array(p.days.enumerated()), id: \.offset) { _, day in
                Image(systemName: day.met ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(day.met ? Color.coreClub : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement()
        .accessibilityLabel(Text("Days met"))
        .accessibilityValue(Text(verbatim: "\(p.met_entry) / \(p.days.count)"))
    }

    private func load() async {
        isLoading = true
        progress = await CoreClubService.fetchProgress()
        isLoading = false
    }
}
