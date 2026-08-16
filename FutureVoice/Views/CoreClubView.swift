import SwiftUI

/// The Core, from wherever the learner currently stands.
///
/// The screen opens on the ROOM — a hundred seats, filled ones wearing their
/// member's own colour — and only then talks numbers. It used to open on
/// "25 days to entry / 3 of 28 / Absences 27 · 0", which is a requirements
/// checklist for a thing the learner had never been told the meaning of. A
/// person deciding whether to walk toward a door needs to see the room first.
///
/// Under the room, three questions in the order they actually get asked: what
/// is this, how do I get in, what changes if I do. Everything after that is
/// the learner's own standing, in one of three states, because they are three
/// points on one path rather than three features:
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
    /// Which club this is. There is one per target language, so the screen
    /// shows the one the learner is currently practising — switching language
    /// in Me switches which room this is.
    @EnvironmentObject private var appState: AppState
    @State private var progress: CoreClubService.Progress?
    @State private var seatMap: CoreClubService.SeatMap?
    @State private var isLoading = true

    private var isSeated: Bool { progress?.member?.seated == true }

    var body: some View {
        List {
            if let p = progress {
                roomSection
                // A member gets their own standing first — they already know
                // what the club is, and being made to read the pitch again on
                // the way to their own seat is the app talking past them.
                if isSeated { standingSection(p) }

                whatItIsSection
                if !isSeated { howToJoinSection(p) }
                keepSection(p)
                whatItMeansSection()

                if !isSeated { standingSection(p) }
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

    // MARK: - The room

    /// A hundred dots, drawn before a single number is spoken.
    private var roomSection: some View {
        Section {
            CoreSeatGrid(map: seatMap)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let m = seatMap {
                    Text(explain("\(m.taken) of \(m.seats) seats taken."))
                }
                Text(explain("One cell is one person, in the colour they picked for their own app. Empty cells are free seats; the outlined one is you."))
            }
        }
    }

    // MARK: - The rules, as points
    //
    // Everything below is written as a LIST of facts, not as paragraphs. The
    // first version of this screen explained in prose and every sentence had
    // to soften, qualify or apologise for the rule it was describing — which
    // is how it ended up saying things that were merely comforting and not
    // true ("missing a day moves your date one day later"; it does not, once
    // you have used up your two). A point can't hedge.

    private var whatItIsSection: some View {
        Section {
            Text(explain("100 seats."))
            Text(explain("The people who have kept it up the longest."))
            Text(explain("A seat is never taken from you. It opens only when the person in it stops."))
        } header: {
            Text("The Core")
        }
    }

    private func howToJoinSection(_ p: CoreClubService.Progress) -> some View {
        Section {
            Text(explain("\(p.entry_required) of the last \(p.days.count) days, \(p.bar_seconds / 60) minutes of talk or more each. Two days off is fine."))
            // Qualifying is not entering, and the screen said it was. Someone
            // who completes the month into a full club and is then told
            // nothing has changed will read it as broken.
            Text(explain("A seat has to be free. If all \(p.seats) are taken, you wait."))
            Text(explain("Keep clearing it while you wait. Stop, and a seat opening won't be yours."))
            Text(explain("First to qualify, first to sit."))
        } header: {
            Text("Getting in")
        }
    }

    /// One bar, stated twice on purpose — under "getting in" and again here —
    /// because the question "and then what do I have to keep doing?" is asked
    /// separately even when the answer is the same.
    private func keepSection(_ p: CoreClubService.Progress) -> some View {
        Section {
            Text(explain("The same as getting in: \(p.keep_required) of the last \(p.days.count) days."))
        } header: {
            Text("Keeping the seat")
        }
    }

    /// Deliberately NOT "what you get".
    ///
    /// This section used to lead with "4 more minutes of talk a day", which
    /// was two mistakes at once. Tier-wise it was near-worthless to the people
    /// most likely to be here — against Unlimited's 60 min/day it was under
    /// 7% — and framing-wise it turned a record of having kept something up
    /// into a loyalty scheme with a discount attached.
    ///
    /// The Core hands over nothing. So this says what is TRUE of being in it
    /// and makes no offer: the seal exists because other people see it, the
    /// day count exists because it happened. Never add a perk row here to make
    /// the section feel more generous — the absence is the design.
    private func whatItMeansSection() -> some View {
        Section {
            Label {
                Text(explain("Nothing is handed to you for it. No extra minutes, no unlocked features."))
            } icon: {
                Image(systemName: "hand.raised").foregroundStyle(Color.coreClub)
            }
            Label {
                // The seal's only real audience is a stranger, so name the
                // place they'll see it — a badge nobody can point at isn't
                // one.
                Text(explain("A badge next to your name where you meet people."))
            } icon: {
                Image(systemName: "seal.fill").foregroundStyle(Color.coreClub)
            }
            Label {
                Text(explain("A count of the days you kept it. It stays yours even after you leave."))
            } icon: {
                Image(systemName: "calendar").foregroundStyle(Color.coreClub)
            }
        } header: {
            Text("What it means")
        } footer: {
            Text(explain("It's a promise to yourself, and a record that you kept it."))
        }
    }

    // MARK: - Where you stand: ONE container

    /// The learner's own standing, whole, in a single section.
    ///
    /// It used to be spread over two: a header section with the countdown and
    /// a count, then — after the explanations — a separate "Last 30 days"
    /// section with the month grid. So "Days met 3 / 28" sat in one box and
    /// the thirty dots that ARE that number sat in another, with several
    /// screens of rules between them. Two containers for one fact reads as
    /// two facts, and the learner has to work out that they're the same one.
    ///
    /// The order inside is fixed for all three states — where you stand, the
    /// count, the month — so the numbers don't move when your state changes.
    private func standingSection(_ p: CoreClubService.Progress) -> some View {
        Section {
            standingLead(p)

            LabeledContent("Days met") {
                Text(verbatim: "\(p.met_entry) / \(p.entry_required)").monospacedDigit()
            }
            if let m = p.member {
                LabeledContent("Days in the Core") {
                    Text(verbatim: "\(m.days_total)").monospacedDigit()
                }
            }

            monthGrid(p)
        } header: {
            Text("Where you stand")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                // While the window still reaches back past the day counting
                // began, an empty month is not a verdict — it's a start date.
                // Give them something to wait for instead of a score to lose.
                if let first = p.firstSeatDate, p.hasUncountedDays {
                    Text(explain("Counting started \(p.countingSinceText). The faint days are before that — they're not misses. The first seat can be taken on \(first)."))
                }
                // Watch now has its own visible daily allowance, which makes
                // it reasonable to assume scenes count here too. They never
                // have and never will — say so rather than let someone watch
                // their way toward a seat that isn't coming.
                Text(explain("Only Talk counts. Watching a scene doesn't."))
            }
        }
    }

    /// The one line that differs by state. Everything under it is the same
    /// three rows for everybody.
    @ViewBuilder
    private func standingLead(_ p: CoreClubService.Progress) -> some View {
        if let m = p.member, m.seated {
            CoreSealRow(seated: true)
        } else if p.member != nil {
            CoreSealRow(seated: false)
            if p.waiting_for_seat {
                Text(explain("You're over the bar. The next seat is yours."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else if let back = p.days_to_return {
                bigNumber(back, label: "Days to return")
                if p.requalifying {
                    Text(explain("You've been away a while, so the full month counts again."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else if let togo = p.days_to_entry {
            // "Absences 27 · 0" used to sit under this — two unlabelled
            // numbers telling a beginner they had already failed 27 times with
            // no cushion left, which is the precise feeling this whole design
            // exists to avoid. The month grid says the same thing without the
            // verdict.
            bigNumber(togo, label: "Days to qualify")
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
                // Three states, not two. A day before counting began is drawn
                // faintest and hollow: it is not a day the learner missed, and
                // showing it as one turned a fresh start into a month of
                // failure for anyone who had been talking all along.
                Image(systemName: day.met ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(day.met ? Color.coreClub
                                     : Color.secondary.opacity(day.wasCounted ? 0.4 : 0.12))
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
        // Two calls, one screen: the room is drawn from the club's seats and
        // the rest from the learner's own days. Concurrent so the grid isn't
        // waiting behind a month of activity.
        async let p = CoreClubService.fetchProgress(language: appState.targetLanguage)
        async let m = CoreClubService.fetchSeatMap(language: appState.targetLanguage)
        (progress, seatMap) = await (p, m)
        isLoading = false
    }
}
