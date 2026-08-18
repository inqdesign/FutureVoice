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
///   * **Challenger** — hasn't qualified. Sees how far they have come and how
///     far is left, as two numbers. No verdict, no grid.
///   * **Seated** — in the club. Sees tenure and the month's one forgiven
///     day, not a rank. Rank decides who gets in; inside, everyone is equal,
///     and a leaderboard here would rebuild the anxiety the design removed.
///   * **Seatless** — qualified, currently out. Sees that the badge is
///     permanent and how far the way back is. Never a scolding, never a
///     record of who took the seat.
///
/// **NUMBERS, NOT A PICTURE** (2026-08-17). This screen used to draw thirty
/// dots under "Days met 3 / 28". Two things were wrong with it and neither
/// was fixable by restyling. The grid was a scoreboard of a month already
/// spent — it answered "how did I do" when the only question here is "what do
/// I do today" — and it could not state its own rule: nothing in a field of
/// dots says which two of them were forgiven. The rule is now a streak, which
/// is a rule people already hold in their heads, and a streak is one number.
/// Do not bring the grid back to "show progress"; the progress is the number.
///
/// The other thing the picture quietly implied is that filling it got you in.
/// It doesn't, and never did: finishing the streak puts you in LINE, and the
/// room at the top is what you are waiting on. `queue_ahead` says so in the
/// one state where it matters.
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
            Text(explain("Talk \(p.bar_seconds / 60) minutes a day, \(p.entry_streak) days in a row."))
            // Said plainly, and never softened. A streak that quietly forgives
            // is a rolling window wearing a streak's clothes, and the learner
            // finds out which one it really is at the worst possible moment.
            Text(explain("Miss a day and the count starts again at zero."))
            // The correction this screen most needed: filling the streak is
            // not the door, it is the queue.
            Text(explain("Finishing puts you in line — it doesn't seat you."))
            Text(explain("\(p.seats) seats. One opens only when the person in it stops — never because someone new arrived."))
            Text(explain("Whoever qualified first takes it."))
            Text(explain("Once you're in, one missed day a month is forgiven."))
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
    /// One section, and every row in it is a number with a name. The lead is
    /// the only thing that varies by state, so the rows under it don't move
    /// when the state changes.
    ///
    /// What is deliberately NOT here: any rendering of the last thirty days.
    /// See the type comment — the streak replaced it, and a grid beside a
    /// streak would just be the old rule arguing with the new one.
    private func standingSection(_ p: CoreClubService.Progress) -> some View {
        Section {
            standingLead(p)

            // The streak is shown to everyone, in every state, because it is
            // the one number that answers "what do I do today" — and for a
            // seated member it is the thing the forgiven day is spent from.
            LabeledContent("Current streak") {
                Text(verbatim: "\(p.streak)").monospacedDigit()
            }

            if let m = p.member {
                if m.seated {
                    LabeledContent("Days in the Core") {
                        Text(verbatim: "\(m.days_total)").monospacedDigit()
                    }
                    // The keep rule as a number rather than a warning. "0 / 1"
                    // is a cushion; "you have one day left" is a threat, and
                    // the same fact read as a threat is what makes people stop
                    // opening the app.
                    LabeledContent("Missed this month") {
                        Text(verbatim: "\(p.missed_recent) / \(p.keep_grace)").monospacedDigit()
                    }
                } else if let ahead = p.queue_ahead {
                    LabeledContent("People ahead of you") {
                        Text(verbatim: "\(ahead)").monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Where you stand")
        }
        // No footer. There was one saying "only Talk counts, watching a scene
        // doesn't" — written to head off a confusion that nobody had. Naming
        // Watch here is what plants the idea that Watch might count; the rule
        // section says "Talk" and that is the whole job. An answer to an
        // unasked question is just noise with a defensive tone.
    }

    /// The one line that differs by state. Everything under it is the same
    /// handful of rows for everybody.
    @ViewBuilder
    private func standingLead(_ p: CoreClubService.Progress) -> some View {
        if let m = p.member, m.seated {
            CoreSealRow(seated: true)
        } else if p.member != nil {
            CoreSealRow(seated: false)
            if p.waiting_for_seat {
                // Qualified and over the bar. Which of the two things they are
                // waiting on depends on the room at the top of this screen, and
                // saying "a seat opens when someone stops" to someone looking
                // at ninety empty ones is the app not reading its own screen.
                if p.club_size < p.seats {
                    Text(explain("You're in line, and there's room. You take a seat tonight."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(explain("You're in line. A seat opens when someone stops."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if let back = p.days_to_return {
                bigNumber(back, label: "Days to return")
                if p.requalifying {
                    Text(explain("You've been away a while, so the full streak counts again."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else if let togo = p.days_to_entry {
            if togo == 0 {
                // Streak complete, settlement not yet run. Saying "0 days to
                // go" here would read as a stall; this is the one moment the
                // screen gets to be pleased.
                Text(explain("You've done the \(p.entry_streak) days. You join the line tonight."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                bigNumber(togo, label: "Days to go")
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
