import SwiftUI

/// "Your week" — the closed week as a deck of cards, swiped through like
/// stories, ending on the week's test (2026-09-30). See `WeekRecap`.
///
/// Cards: the week at a glance → talk → what you studied and then SAID →
/// review work → new phrases from the fluent self → what tripped you up →
/// the coach → the test. A card with nothing to say is not dealt, so a quiet
/// week is a short deck, never a row of zeros.
///
/// The same deck is the TRIAL REPORT (`init(trial:)`, see `TrialReport`):
/// the free minutes instead of a week, then the test (required — the level
/// and routine cards are dealt only once it is done), the level, and the
/// routine, whose button opens the plans.
struct WeekRecapSheet: View {
    enum Action { case test, talk }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var recap: WeekRecap
    /// What the learner chose on the last card; the presenter acts on it once
    /// the sheet is gone, so nothing opens underneath a closing sheet.
    @Binding var action: Action?

    @State private var page: Int
    @State private var revealed: Set<Int>
    @State private var coachFailed = false
    @State private var testState: WeeklyTestSchedule.State = .ready
    /// Whether the last card offers next week's notice: only while it is
    /// off and the phone could still ring (a refused permission can't be
    /// asked again from here, so the offer would be a dead button).
    @State private var offerReminder = false
    @State private var reminderJustOn = false

    // Trial report only.
    private let isTrial: Bool
    @State private var trial: TrialReport?
    @State private var trialTest: WeeklyTest?
    @State private var showingTrialTest = false
    @State private var trialLevel: CEFRLevel?
    @State private var trialRationale: String?
    @State private var levelSettled = false
    @State private var routine: [RoutineRecipe.Line] = []
    @State private var routineIsOwn = false
    @State private var showingPaywall = false

    init(recap: WeekRecap, action: Binding<Action?>, startPage: Int = 0) {
        _recap = State(initialValue: recap)
        _action = action
        _page = State(initialValue: startPage)
        _revealed = State(initialValue: [startPage])
        isTrial = false
    }

    init(trial: TrialReport) {
        _recap = State(initialValue: trial.recap)
        _action = .constant(nil)
        var start = 0
        #if DEBUG
        start = UserDefaults.standard.integer(forKey: "trialpage")
        #endif
        _page = State(initialValue: start)
        _revealed = State(initialValue: [start])
        _trial = State(initialValue: trial)
        _trialLevel = State(initialValue: trial.level.flatMap(CEFRLevel.init(rawValue:)))
        _trialRationale = State(initialValue: trial.levelRationale)
        _levelSettled = State(initialValue: trial.level != nil)
        isTrial = true
    }

    enum Card: Hashable {
        case cover, talk, used, review, fresh, stumbles, grammar, words, coach, test
        case trialTest, level, routine
    }

    /// The trial's test is done, or could not be made — either way the
    /// level and the routine are the learner's to see.
    private var trialTestCleared: Bool {
        trialTest?.isFinished == true || trial?.testThin == true
    }

    private var cards: [Card] {
        var list: [Card] = [.cover]
        if recap.talkSeconds > 0 || !recap.talks.isEmpty { list.append(.talk) }
        if recap.usedCount > 0 { list.append(.used) }
        if !recap.nowYours.isEmpty || !recap.sentencesGot.isEmpty
            || recap.shadowTakes + recap.scenes > 0 { list.append(.review) }
        if recap.newExpressionCount > 0 || recap.newCards > 0 { list.append(.fresh) }
        if !recap.stumbles.isEmpty || !recap.shakyLines.isEmpty || testMissed > 0 { list.append(.stumbles) }
        // The coach's cards are dealt whether or not its read has landed —
        // they show their own loading state — so the deck never reshuffles
        // under the learner's thumb.
        if recap.hasActivity { list += [.grammar, .words] }
        list.append(.coach)
        if isTrial {
            list.append(.trialTest)
            if trialTestCleared { list += [.level, .routine] }
        } else {
            list.append(.test)
        }
        return list
    }

    private var testMissed: Int {
        guard let score = recap.testScore, let total = recap.testTotal else { return 0 }
        return total - score
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    cardView(card, index: index)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomButton
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onChange(of: page) { _, new in
            withAnimation(.easeOut(duration: 0.4)) { _ = revealed.insert(new) }
        }
        // One row per viewing, never one per swipe: how far the deck was
        // read is the question, and it is answered once.
        .onDisappear {
            Analytics.capture(isTrial ? "trial_report_closed" : "week_recap_closed",
                              ["reached": (revealed.max() ?? 0) + 1, "cards": cards.count])
        }
        .fullScreenCover(isPresented: $showingTrialTest, onDismiss: reloadTrialTest) {
            WeeklyTestView(trialScope: .init(start: recap.start, minimum: TrialReportStore.minTestItems,
                                             coach: recap.coach))
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingPaywall, onDismiss: {
            // The report has done its job whether or not they bought.
            TrialReportStore.finished = true
            dismiss()
        }) {
            PaywallView(source: "trial_report")
        }
        .task {
            if isTrial { await startTrial(); return }
            // Shown means SEEN: marked here, not where it was raised, so a
            // presentation that never landed doesn't use up the week.
            WeekRecapStore.shared.markShown(recap)
            testState = WeeklyTestSettings.shared.schedule.state(
                tests: WeeklyTestStore.shared.load(), settings: .shared)
            let notifications = await ReviewNotifications.status()
            offerReminder = !WeeklyTestSettings.shared.reminderOn && notifications != .denied
            Analytics.capture("week_recap_opened", ["days": recap.daysActive,
                                                    "talk_min": recap.talkMinutes,
                                                    "cards": cards.count])
            await writeCoachIfNeeded()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 12) {
            // Stories-style segments: where you are in the deck, tappable.
            HStack(spacing: 4) {
                ForEach(cards.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= page ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(height: 3)
                        .onTapGesture { withAnimation { page = i } }
                }
            }
            HStack {
                if isTrial {
                    Text("Your first \(AccountStatus.freeGrantSeconds / 60) minutes")
                        .font(.headline)
                } else {
                    Text("Your week")
                        .font(.headline)
                    Text(dateRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.25), value: page)
    }

    @ViewBuilder
    private var bottomButton: some View {
        if isTrial, let card = cards[safe: page], [.trialTest, .routine].contains(card) {
            if card == .routine {
                primary(Text("Keep going with this routine")) { keepRoutine() }
            } else if trialTestCleared {
                primary(Text("See your level")) { advance() }
            } else if let t = trialTest, !t.answers.isEmpty {
                primary(Text("Continue the test")) { showingTrialTest = true }
            } else {
                primary(Text("Take the test")) { showingTrialTest = true }
            }
        } else if cards[safe: page] == .test {
            switch testState {
            case .ready:
                primary(Text("Start this week's test")) { finish(.test) }
            case .inProgress:
                primary(Text("Continue the test")) { finish(.test) }
            case .done:
                primary(Text("See the results")) { finish(.test) }
            case .thin:
                primary(Text("Start a talk")) { finish(.talk) }
            }
        } else {
            primary(Text("Next")) { advance() }
        }
    }

    private func advance() {
        withAnimation { page = min(page + 1, cards.count - 1) }
    }

    private func primary(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func finish(_ chosen: Action) {
        Analytics.capture("week_recap_action", ["action": chosen == .test ? "test" : "talk"])
        action = chosen
        dismiss()
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardView(_ card: Card, index: Int) -> some View {
        let shown = revealed.contains(index)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                switch card {
                case .cover:    cover
                case .talk:     talk
                case .used:     used
                case .review:   review
                case .fresh:    fresh
                case .stumbles: stumbles
                case .grammar:  grammar
                case .words:    words
                case .coach:    coach
                case .test:     test
                case .trialTest: trialTestCard
                case .level:    levelCard
                case .routine:  routineCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func kicker(_ title: Text, _ symbol: String, _ tint: Color = .accentColor) -> some View {
        Label { title } icon: { Image(systemName: symbol) }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }

    private func bigNumber(_ value: Int, unit: Text? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let unit {
                unit.font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    // 1 — the week at a glance
    @ViewBuilder
    private var cover: some View {
        if isTrial { trialCover } else { weekCover }
    }

    private var weekCover: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Last week"), "calendar")
            if recap.hasActivity {
                bigNumber(recap.daysActive, unit: Text("of 7 days"))
                coverLine
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A quiet week")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("It happens. One talk is enough to start again.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 8) {
                        Circle()
                            .fill(recap.activeDays[safe: i] == true ? Color.accentColor : Color(.tertiarySystemFill))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if recap.activeDays[safe: i] == true {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(weekdayLetter(i))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            if recap.streak > 1 {
                Label { Text("\(recap.streak)-day streak") } icon: { Image(systemName: "flame.fill") }
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            if recap.hasActivity {
                summaryRow
            }
        }
    }

    /// The whole week in one glance, before the cards take it apart.
    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recap.talkSeconds > 0 {
                summaryLine("waveform", Text("\(recap.talkMinutes) min of talk · ^[\(recap.talks.count) talk](inflect: true)"))
            }
            if recap.usedCount > 0 {
                summaryLine("checkmark.seal", Text("^[\(recap.usedCount) thing](inflect: true) you studied, said out loud"))
            }
            if !recap.nowYours.isEmpty {
                summaryLine("rectangle.stack", Text("^[\(recap.nowYours.count) word or phrase](inflect: true) became yours"))
            }
            if recap.newExpressionCount > 0 {
                summaryLine("sparkles", Text("^[\(recap.newExpressionCount) new phrase](inflect: true) from your fluent self"))
            }
        }
        .padding(.top, 4)
    }

    private func summaryLine(_ symbol: String, _ text: Text) -> some View {
        Label { text } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
        }
        .font(.subheadline)
    }

    /// Said differently by how much of the week was used — five days is not
    /// the same news as one, and both deserve their own sentence.
    private var coverLine: Text {
        switch recap.daysActive {
        case 7:    return Text("Every single day. That's a habit now.")
        case 5, 6: return Text("Most of the week. That's a rhythm.")
        case 3, 4: return Text("A few days in. The rhythm is starting.")
        default:   return Text("You showed up. That's the part that counts.")
        }
    }

    // 2 — the talks, every one of them
    private var talk: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Talks"), "waveform")
            bigNumber(recap.talkMinutes, unit: Text("min"))
            let previous = recap.previousTalkSeconds / 60
            if recap.talkMinutes > previous, previous > 0 {
                Label { Text("\(recap.talkMinutes - previous) min more than the week before") }
                    icon: { Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if previous > 0 {
                Text("The week before: \(previous) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !recap.talks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(recap.talks.prefix(6).enumerated()), id: \.offset) { i, t in
                        if i > 0 { Divider().padding(.leading, 40) }
                        HStack(spacing: 12) {
                            Image(systemName: talkSymbol(t.kind))
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                Text("\(weekday(t.day)) · \(t.minutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                    }
                    if recap.talks.count > 6 {
                        Text("and \(recap.talks.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 40)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func talkSymbol(_ kind: String) -> String {
        switch kind {
        case "person":   return "person.fill"
        case "scenario": return "theatermasks.fill"
        case "news":     return "newspaper.fill"
        default:         return "waveform"
        }
    }

    // 3 — the win: studied, then said
    private var used: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("You used what you practiced"), "checkmark.seal.fill", .green)
            bigNumber(recap.usedCount)
            Text("You studied these, then said them yourself in a real talk.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(recap.used, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.item)
                            .font(.headline)
                        Text("\u{201C}\(e.quote)\u{201D}")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // 4 — the review work, told by what it bought. Like every other card
    // it leads with ONE number, and that number is the count of the list
    // right under it: words and phrases that became the learner's this week.
    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Practice"), "rectangle.stack.fill")
            if !recap.nowYours.isEmpty {
                bigNumber(recap.nowYours.count)
                Text("Words and phrases that became yours this week.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                FlowChips(items: Array(recap.nowYours.prefix(12)))
                if recap.nowYours.count > 12 {
                    Text("+\(recap.nowYours.count - 12) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !recap.sentencesGot.isEmpty {
                section(Text("^[\(recap.sentencesGot.count) sentence](inflect: true) you got down")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recap.sentencesGot.prefix(3), id: \.self) { line in
                            Label { Text(line) } icon: {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            if recap.shadowTakes > 0 || recap.scenes > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    if recap.shadowTakes > 0 {
                        Label {
                            HStack(spacing: 6) {
                                Text("^[\(recap.shadowTakes) shadowing take](inflect: true)")
                                if let avg = recap.shadowAverage {
                                    Text(verbatim: "·").foregroundStyle(.secondary)
                                    Text("average \(avg)")
                                    if let prev = recap.previousShadowAverage, avg != prev {
                                        Text(verbatim: avg > prev ? "+\(avg - prev)" : "\(avg - prev)")
                                            .foregroundStyle(avg > prev ? .green : .secondary)
                                    }
                                }
                            }
                        } icon: { Image(systemName: "waveform.badge.mic").foregroundStyle(.tint) }
                    }
                    if recap.scenes > 0 {
                        Label { Text("^[\(recap.scenes) scene](inflect: true) watched") }
                            icon: { Image(systemName: "play.rectangle").foregroundStyle(.tint) }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private func section<C: View>(_ title: Text, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // 5 — new material, in the fluent self's own sentence
    private var fresh: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("New from your fluent self"), "sparkles")
            if recap.newExpressionCount > 0 {
                bigNumber(recap.newExpressionCount)
                Text("Things your fluent self said that you haven't said yet.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recap.newExpressions, id: \.self) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.item)
                                .font(.headline)
                            if !e.quote.isEmpty {
                                Text("\u{201C}\(e.quote)\u{201D}")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                Text("They're waiting in your expressions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if recap.newCards > 0 {
                Label {
                    Text("^[\(recap.newCards) new review card](inflect: true) from your corrections")
                } icon: { Image(systemName: "rectangle.stack.badge.plus") }
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // 6 — what tripped you up
    private var stumbles: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Where you got stuck"), "arrow.triangle.2.circlepath", .orange)
            if !recap.stumbles.isEmpty {
                Text("The same fix kept coming back. One more look and it's yours.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(recap.stumbles, id: \.self) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.was)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.now).font(.headline)
                            Spacer()
                            Text("×\(s.count)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if !recap.shakyLines.isEmpty {
                Text("Lines that didn't quite land when you shadowed them.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(recap.shakyLines, id: \.self) { s in
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.now).font(.headline)
                        Spacer()
                        Text(verbatim: "\(s.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .padding(14)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if testMissed > 0, let score = recap.testScore, let total = recap.testTotal {
                Label {
                    Text("Last test \(score)/\(total). The ^[\(testMissed) you missed](inflect: true) come back this week.")
                } icon: { Image(systemName: "checklist") }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 7 — grammar that goes wrong across different sentences
    private var grammar: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Grammar that keeps slipping"), "text.badge.checkmark", .orange)
            if let c = recap.coach {
                if c.grammar.isEmpty {
                    Text("No grammar point kept coming back this week.")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The same point, in different sentences.")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(c.grammar, id: \.self) { p in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(p.rule)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(p.examples, id: \.self) { e in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.was)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Text(e.now)
                                        .fontWeight(.medium)
                                }
                                .font(.subheadline)
                            }
                            if !p.tip.isEmpty {
                                Label { Text(p.tip) } icon: {
                                    Image(systemName: "lightbulb").foregroundStyle(.orange)
                                }
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                coachPending
            }
        }
    }

    // 8 — the easy words they lean on, and the one a band up
    private var words: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Words to level up"), "arrow.up.forward.circle.fill")
            if let c = recap.coach {
                if c.upgrades.isEmpty {
                    Text("No word carried too much of the load this week.")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Words you leaned on, and one to reach for next.")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(c.upgrades, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(u.instead)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: "×\(u.count)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tint)
                                Text(u.better)
                                    .fontWeight(.semibold)
                            }
                            .font(.headline)
                            if !u.rewritten.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\u{201C}\(u.original)\u{201D}")
                                        .foregroundStyle(.secondary)
                                    Text("\u{201C}\(u.rewritten)\u{201D}")
                                }
                                .font(.subheadline)
                            }
                            if !u.note.isEmpty {
                                Text(u.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                coachPending
            }
        }
    }

    // 9 — the coach: the read, and the plan
    private var coach: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("From your coach"), "quote.bubble.fill")
            if let c = recap.coach {
                Text(c.headline)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if !c.insight.isEmpty {
                    section(Text("How you speak")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(c.insight)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            if !c.insightQuote.isEmpty {
                                Text("\u{201C}\(c.insightQuote)\u{201D}")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !c.plan.isEmpty { planBox(c.plan.map { Text($0) }) }
            } else if recap.hasActivity {
                coachPending
            } else {
                Text("A new week starts now. Start small.")
                    .font(.title3)
                planBox([fallbackFocus])
            }
        }
    }

    /// The coach's read hasn't landed: waiting, or failed with a way back.
    @ViewBuilder
    private var coachPending: some View {
        if coachFailed {
            VStack(alignment: .leading, spacing: 12) {
                (isTrial ? Text("Couldn't read your minutes just now.") : Text("Couldn't read your week just now."))
                    .font(.title3)
                Button {
                    coachFailed = false
                    Task { await writeCoachIfNeeded() }
                } label: {
                    Label { Text("Try again") } icon: { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                (isTrial ? Text("Reading your minutes…") : Text("Reading your week…"))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
    }

    private func planBox(_ items: [Text]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            (isTrial ? Text("Next up") : Text("This week"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(i + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.tint)
                    item
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Written in code when the coach can't be — from the same evidence.
    private var fallbackFocus: Text {
        if let s = recap.stumbles.first {
            return Text("Say \u{201C}\(s.now)\u{201D} in your next talk.")
        }
        if let p = recap.newExpressions.first {
            return Text("Try \u{201C}\(p.item)\u{201D} in your next talk.")
        }
        if let s = recap.shakyLines.first {
            return Text("Shadow \u{201C}\(s.now)\u{201D} once more.")
        }
        return Text("One talk, a few minutes. That's the whole plan.")
    }

    // 8 — the test
    private var test: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("This week's test"), "checklist")
            Image(systemName: "checkmark.circle")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            switch testState {
            case .ready:
                Text("A few minutes, made from your own week: the words, the phrases, the corrections.")
                    .font(.title3)
            case let .inProgress(t):
                Text("You're \(t.answers.count) of \(t.total) in. Pick up where you left off.")
                    .font(.title3)
            case let .done(t, _):
                Text("Done: \(t.score)/\(t.total).")
                    .font(.title3)
            case .thin:
                Text("Not enough from this week yet for a test. A talk or two, and it's ready.")
                    .font(.title3)
            }
            reminderOffer
        }
    }

    /// The deck slides up by itself only when the app is opened; the notice
    /// is what reaches someone who doesn't. Asked here, once the learner has
    /// seen what the notice would bring — never as a cold permission prompt.
    @ViewBuilder private var reminderOffer: some View {
        if reminderJustOn {
            Label(explain("Next week's arrives \(readyDate)"), systemImage: "bell.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if offerReminder {
            Button {
                Task {
                    let status = await ReviewNotifications.request()
                    WeeklyTestSettings.shared.reminderOn = status.canRing
                    await WeeklyTestReminder.reschedule()
                    withAnimation(.easeOut(duration: 0.3)) {
                        reminderJustOn = status.canRing
                        offerReminder = false
                    }
                    Analytics.capture("week_recap_reminder", ["on": status.canRing])
                }
            } label: {
                Label("Tell me when next week's is ready", systemImage: "bell")
            }
            .buttonStyle(.bordered)
        }
    }

    private var readyDate: String {
        WeeklyTestSettings.shared.schedule.nextOpening()
            .formatted(Date.FormatStyle(locale: chromeLocale).weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Trial report

    // 1 — the free minutes at a glance
    private var trialCover: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Your free minutes"), "gift")
            bigNumber(recap.talkMinutes, unit: Text("min"))
            Text("That was your free time. Here's what it showed.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            summaryRow
        }
    }

    // The test — required: the level and the routine come after it.
    private var trialTestCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Your first test"), "checklist")
            Image(systemName: trialTest?.isFinished == true ? "checkmark.circle.fill"
                  : trial?.testThin == true ? "calendar.badge.clock" : "checkmark.circle")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(trialTest?.isFinished == true ? Color.green
                                 : trial?.testThin == true ? Color.secondary : Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            if let t = trialTest, t.isFinished {
                Text("Done: \(t.score)/\(t.total).")
                    .font(.title3.weight(.semibold))
                Text("Next, your level.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if trial?.testThin == true {
                Text("Your talks were too short to make questions from. Your report goes on without it.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let t = trialTest, !t.answers.isEmpty {
                Text("You're \(t.answers.count) of \(t.total) in. Pick up where you left off.")
                    .font(.title3)
            } else {
                Text("A few minutes, made from what you said: the words, the phrases, the corrections.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Take it, then see your level.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // The level — the first assessment, run early for the report.
    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Your level"), "chart.bar.fill")
            if let level = trialLevel {
                Text(LanguageCatalog.levelLabel(level, target: appState.targetLanguage))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                Text(canDo(level))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                if let rationale = trialRationale, !rationale.isEmpty {
                    section(Text("How we read it")) {
                        Text(rationale)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let t = trialTest, t.isFinished {
                    Label { Text("Test \(t.score)/\(t.total)") } icon: { Image(systemName: "checklist") }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("It moves as you talk. Progress keeps track.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if levelSettled {
                Text("A few more talks and your level is ready.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your level…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }
        }
    }

    /// Same lines as Progress's level page.
    private func canDo(_ l: CEFRLevel) -> String {
        switch l {
        case .a1: return explain("Simple words and phrases about immediate, familiar things.")
        case .a2: return explain("Everyday topics in simple terms — routines, plans, basic needs.")
        case .b1: return explain("Familiar topics fluently enough to get by, and tell a simple story.")
        case .b2: return explain("Clear, detailed talk on many topics, including some abstract ones.")
        case .c1: return explain("Fluent, flexible, and precise — even on complex topics.")
        case .c2: return explain("Effortless and nuanced, close to native.")
        }
    }

    // The routine — the way on, and the button to the plans.
    private var routineCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            kicker(Text("Keep it going"), "calendar")
            Text(RoutineRecipe.headline(for: LearningPurposeStore.purposes))
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(explain("About \(StudyPlanStore.goalMinutes) minutes of talk a day, and what it corrected comes back the same evening."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RoutineWeekPicture(blocks: routine.map(\.block))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(routine) { line in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: line.block.kind.symbol)
                            .font(.subheadline)
                            .foregroundStyle(line.block.kind.color)
                            .frame(width: 22)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.block.kind.titled(line.block.minutes))
                                .font(.subheadline.weight(.semibold))
                            Text(SetupFlowView.weekdaySummary(line.block.weekdays))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !line.why.isEmpty {
                                Text(line.why)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            Text(explain("You can change all of it later in My routine."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func startTrial() async {
        TrialReportStore.offers += 1
        Analytics.capture("trial_report_opened", ["talk_min": recap.talkMinutes, "cards": cards.count])
        reloadTrialTest()
        // The routine: the one already chosen in setup, else the one the
        // learner's purposes suggest.
        if UserDefaults.standard.bool(forKey: LearningPurposeStore.routineAppliedKey),
           !StudyPlanStore.shared.plan.blocks.isEmpty {
            routine = StudyPlanStore.shared.plan.blocks.map { RoutineRecipe.Line(block: $0, why: "") }
            routineIsOwn = true
        } else {
            routine = RoutineRecipe.lines(for: LearningPurposeStore.purposes,
                                          goalMinutes: StudyPlanStore.goalMinutes)
        }
        async let level: Void = loadTrialLevel()
        await writeCoachIfNeeded()
        await level
    }

    private func loadTrialLevel() async {
        guard trialLevel == nil else { return }
        let read = await appState.assessTrialLevel()
        withAnimation(.easeOut(duration: 0.3)) {
            trialLevel = read?.level
            trialRationale = read?.rationale
            levelSettled = true
        }
        if let read {
            updateTrial { $0.level = read.level.rawValue; $0.levelRationale = read.rationale }
        }
    }

    private func reloadTrialTest() {
        let wasCleared = trialTestCleared
        let saved = TrialReportStore.load()
        if let saved { trial?.testThin = saved.testThin; trial?.testId = saved.testId }
        if let id = saved?.testId {
            trialTest = WeeklyTestStore.shared.load().first { $0.id == id }
        }
        // Done in this sitting: straight on to the level.
        if !wasCleared, trialTestCleared, let index = cards.firstIndex(of: .level) {
            withAnimation { page = index }
        }
    }

    private func keepRoutine() {
        if !routineIsOwn, !routine.isEmpty {
            StudyPlanStore.shared.update(RoutineRecipe.plan(from: routine))
            UserDefaults.standard.set(true, forKey: LearningPurposeStore.routineAppliedKey)
        }
        Analytics.capture("trial_report_routine", ["own": routineIsOwn])
        showingPaywall = true
    }

    /// Re-read before writing: the test view saves its id into the same file.
    private func updateTrial(_ change: (inout TrialReport) -> Void) {
        guard var latest = TrialReportStore.load() ?? trial else { return }
        change(&latest)
        TrialReportStore.save(latest)
        trial = latest
    }

    // MARK: - Helpers

    private var chromeLocale: Locale { Locale(identifier: UILanguage.chromeLanguage) }

    private func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: chromeLocale).weekday(.abbreviated))
    }

    private var dateRange: String {
        let style = Date.FormatStyle(locale: chromeLocale).month(.abbreviated).day()
        let last = recap.end.addingTimeInterval(-86_400)   // seven days, as in the archive
        return "\(recap.start.formatted(style)) – \(last.formatted(style))"
    }

    private func weekdayLetter(_ offset: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = chromeLocale
        guard let day = calendar.date(byAdding: .day, value: offset, to: recap.start) else { return "" }
        let weekday = calendar.component(.weekday, from: day)
        return calendar.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }

    private func writeCoachIfNeeded() async {
        guard recap.coach == nil, recap.hasActivity else { return }
        do {
            let written = try await WeekRecapCoach.write(for: recap, targetLanguage: appState.targetLanguage,
                                                         level: appState.proficiency)
            withAnimation(.easeOut(duration: 0.3)) { recap.coach = written }
            if isTrial {
                updateTrial { $0.recap = recap }
            } else {
                WeekRecapStore.shared.save(recap)
            }
        } catch {
            coachFailed = true
            Analytics.capture("week_recap_coach_error", ["error": "\(error)".prefix(160).description])
        }
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
