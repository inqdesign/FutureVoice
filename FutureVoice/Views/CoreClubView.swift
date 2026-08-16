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
                // The room, then YOUR standing, then the rules. One order for
                // everyone.
                //
                // It used to branch: members saw their standing second,
                // non-members saw it last, after four sections of rules. But
                // the rules were four sections precisely because they repeated
                // themselves, and the person who opens this screen — member or
                // not — opens it to find out where they are. Making them read
                // the pitch first is the app talking past them.
                roomSection
                standingSection(p)
                howItWorksSection(p)
                whatYouKeepSection()
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
            // A count, and the one thing the picture can't say for itself.
            // The old caption taught a three-clause legend — filled, empty,
            // outlined — for a grid that mostly reads on sight, and spent its
            // longest clause explaining the colours instead of letting them
            // land.
            VStack(alignment: .leading, spacing: 6) {
                if let m = seatMap {
                    Text(explain("\(m.taken) of \(m.seats) seats taken."))
                    if m.mine != nil {
                        Text(explain("The outlined cell is you."))
                    } else {
                        Text(explain("Each filled cell is a member, in the colour they chose."))
                    }
                }
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

    /// Every rule, once each.
    ///
    /// This replaced three sections — "The Core", "Getting in", "Keeping the
    /// seat" — that between them stated the daily bar three times, the seat
    /// count three times, and devoted a whole section to saying "the same as
    /// getting in". Repetition read as importance the first time and as
    /// padding by the third, and it pushed the learner's own standing four
    /// screens down.
    ///
    /// One of the removed lines was also false: "the people who have kept it
    /// up the longest". Nobody is ranked by length. The bar is pass/fail and
    /// the queue is first-qualified-first, which is a fairness claim the old
    /// wording quietly contradicted.
    private func howItWorksSection(_ p: CoreClubService.Progress) -> some View {
        Section {
            Text(explain("Talk \(p.bar_seconds / 60) minutes a day, \(p.entry_required) days out of \(p.days.count)."))
            Text(explain("The same bar to get in and to stay."))
            Text(explain("\(p.seats) seats. One opens only when the person in it stops — never because someone new arrived."))
            Text(explain("Whoever qualified first takes it."))
        } header: {
            Text("How it works")
        }
    }

    /// What being in it actually leaves you with.
    ///
    /// The Core hands over nothing, and this section does not SAY so. Stating
    /// "no extra minutes, no unlocked features" was the app explaining a
    /// decision only its author knew had been made — nobody was expecting a
    /// payout, so the sentence introduced a disappointment and then answered
    /// it. You don't advertise the absence of a thing.
    ///
    /// Never add a perk row to make this feel more generous, and never add a
    /// line explaining why there isn't one.
    private func whatYouKeepSection() -> some View {
        Section {
            Label {
                // The seal's only real audience is a stranger, so name the
                // place they'll see it — a badge nobody can point at isn't one.
                Text(explain("A badge next to your name where you meet people."))
            } icon: {
                Image(systemName: "seal.fill").foregroundStyle(Color.coreClub)
            }
            Label {
                // What "keeping" concretely means: the seal survives losing
                // the seat. The line here used to be "your days stay yours,
                // even after you leave", which answered an anxiety the reader
                // hasn't formed yet (they don't know a seat can be lost),
                // about a number they cannot see (the day count is only shown
                // to members), landing somewhere unnamed. Three vaguenesses in
                // one sentence.
                Text(explain("The badge stays even if you lose the seat."))
            } icon: {
                Image(systemName: "seal").foregroundStyle(Color.coreClub)
            }
        } header: {
            Text("What you keep")
        } footer: {
            Text(explain("A promise to yourself, and a record that you kept it."))
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
                // One forward-looking fact, or nothing.
                //
                // This used to be three sentences: when the server started
                // counting, what the faint cells mean, and the date. All three
                // were about the SYSTEM — its ledger, its pixel shading, its
                // history — and a learner opening this screen is asking one
                // question, which is when they can get in. The rest was the
                // app explaining its own plumbing and apologising for it.
                //
                // It also only matters for the first month, so it must not
                // read like permanent furniture.
                if let first = p.firstSeatDate, p.hasUncountedDays, p.member == nil {
                    Text(explain("The first seats open on \(first)."))
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
