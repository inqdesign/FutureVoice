import SwiftUI

// The tutor bot's three surfaces (`TutorBot`): the face, the note and the
// bubble float over the Talk home; the chat is a sheet.

/// The face at the bottom right. Tap = ask; hold = today's plan again,
/// the quiz, or the bot's introduction.
struct TutorBotButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var bot = TutorBot.shared

    var body: some View {
        Button { bot.openChat() } label: {
            WeeklyTestCharacter(mood: bot.bubble != nil || bot.noteShown ? .happy : .waiting,
                                since: bot.bubbleSince, tile: .clear)
                .scaleEffect(30 / WeeklyTestCharacter.size)
                .frame(width: 30, height: 30)
        }
        .modifier(GlassCircleButton())
        // No ring around the face while the note is up (founder,
        // 2026-10-29: the highlight outline read as odd); the note's tail
        // already says where it came from.
        .accessibilityLabel(Text("Tutor"))
        .accessibilityHint(Text("Ask what to do next"))
        .contextMenu {
            Button { bot.showNote() } label: { Label("Today's plan", systemImage: "list.bullet") }
            Button { bot.start(nil, appState: appState) } label: { Label("Quick quiz", systemImage: "questionmark.circle") }
            Button { bot.showNote(intro: true) } label: { Label("What the tutor does", systemImage: "info.circle") }
        }
        // The quiz the face used to open, still one hold away — and
        // something the tutor can hand you.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            QuickQuizStock.prewarm(appState: appState)
        }
        .fullScreenCover(isPresented: $bot.quizOpen) {
            QuickQuizView().environmentObject(appState)
        }
        .sheet(isPresented: $bot.chatOpen) {
            TutorChatView().environmentObject(appState)
        }
    }
}

/// The note and the bubble, laid over the Talk home above the bottom row.
/// Nothing is dimmed and nothing blocks: a tap outside the note folds it
/// back into the face.
struct TutorBotLayer: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bot = TutorBot.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if bot.noteShown {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { bot.closeNote() }
                    .ignoresSafeArea()
                TutorNoteCard()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 80)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            } else if let b = bot.bubble {
                TutorBubbleView(bubble: b)
                    .padding(.trailing, 16)
                    .padding(.bottom, 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .sheet(item: $bot.goalPage) { goal in
            UpcomingGoalPage(goal: goal).environmentObject(appState)
        }
        // The chat shows its own; this one is for a reading opened from the note.
        .sheet(item: Binding(get: { bot.chatOpen ? nil : bot.reading },
                             set: { bot.reading = $0 })) { r in
            TutorReadingSheet(reading: r).environmentObject(appState)
        }
    }
}

// MARK: - The note

private struct TutorNoteCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bot = TutorBot.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if bot.introShown { intro } else { plan }
        }
        .padding(16)
        .padding(.bottom, TutorNoteShape.tailHeight)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: TutorNoteShape())
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    // The first meeting: who this is and what it does.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your own nawana tutor.").font(.headline)
                    Text("I know your routine, your talks, your mistakes and your cards. My job is that you always know what to do next, and why.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                introRow("sun.max", "Once a day, I leave you a short note with today's plan.")
                introRow("bubble.left", "When something is ready, I'll say so here. Otherwise I stay quiet.")
                introRow("hand.tap", "Tap me any time to ask: what to do, why a mistake keeps coming back, how you're doing.")
            }
            Button {
                bot.introShown = false
                UserDefaults.standard.set(true, forKey: "futurevoice.tutorBot.introSeen")
            } label: {
                Text("Show me today").frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftChipStyle(selected: true))
        }
    }

    private func introRow(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
              icon: { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
    }

    private var plan: some View {
        let t = bot.today
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TutorCopy.greeting()).font(.headline)
                    Text(TutorCopy.opening(bot)).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let why = TutorCopy.why(t) {
                        Text(why).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // The nearest thing they're preparing for, with its countdown.
            if let goal = UpcomingGoalStore.shared.active(language: appState.targetLanguage).first {
                Button {
                    bot.closeNote()
                    bot.goalPage = goal
                } label: {
                    HStack(spacing: 6) {
                        UpcomingGoalRow(goal: goal)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !bot.picks.isEmpty {
                TutorPickRows(picks: Array(bot.picks.prefix(3)), balance: bot.balance)
            }
            if !t.items.isEmpty {
                TutorPlanRows(today: t)
            }
            HStack(spacing: 10) {
                if t.suggested {
                    Button("Make a routine") {
                        bot.closeNote()
                        appState.openRoutinePage = true
                    }
                    .buttonStyle(SoftChipStyle())
                } else {
                    Button("Later") { bot.closeNote() }
                        .buttonStyle(SoftChipStyle())
                }
                Spacer(minLength: 0)
                Button { bot.openChat() } label: {
                    Label("Ask me", systemImage: "bubble.left")
                }
                .buttonStyle(SoftChipStyle(selected: true))
            }
        }
    }
}

/// The note's card, with a tail at the bottom right pointing down at the
/// tutor's face (`TutorBotButton`), so the note reads as the face talking.
/// `tailInset` is from the card's trailing edge to the tail's centre: the
/// card sits 12 pt from the screen edge and the face's centre ~50 pt.
struct TutorNoteShape: Shape {
    static let tailHeight: CGFloat = 12
    var cornerRadius: CGFloat = 24
    var tailInset: CGFloat = 38
    var tailHalfWidth: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var body = rect
        body.size.height -= Self.tailHeight
        let card = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let x = rect.maxX - tailInset
        var tail = Path()
        tail.move(to: CGPoint(x: x - tailHalfWidth, y: body.maxY - 2))
        tail.addLine(to: CGPoint(x: x, y: rect.maxY))
        tail.addLine(to: CGPoint(x: x + tailHalfWidth, y: body.maxY - 2))
        tail.closeSubpath()
        // ONE outline: drawn as two overlapping subpaths the tail met the
        // card along a visible seam, like a separate piece stuck on.
        return card.union(tail)
    }
}

/// The two other buttons of the Talk home's bottom row while the tutor's
/// note is up: out of focus and out of reach, so only the face stays sharp.
struct SoftenedBehindNote: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: on ? 6 : 0)
            .opacity(on ? 0.5 : 1)
            .allowsHitTesting(!on)
            .animation(.easeOut(duration: 0.3), value: on)
    }
}

/// Today's items: done ones ticked, the next one with Start. Shared by the
/// note and the chat's first message.
struct TutorPlanRows: View {
    @EnvironmentObject private var appState: AppState
    let today: TutorBot.Today

    var body: some View {
        let next = today.next()
        VStack(spacing: 0) {
            ForEach(Array(today.items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Divider().padding(.leading, 40) }
                HStack(spacing: 12) {
                    Image(systemName: item.kind.symbol)
                        .font(.footnote)
                        .foregroundStyle(item.kind.color)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.subheadline)
                            .strikethrough(item.done, color: .secondary)
                            .foregroundStyle(item.done ? .secondary : .primary)
                        Text(TutorCopy.when(item)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if item.done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if item.id == next?.id {
                        Button("Start") { TutorBot.shared.start(item.kind, appState: appState) }
                            .buttonStyle(SoftChipStyle(selected: true))
                    } else if item.progress > 0 {
                        Gauge(value: item.progress) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .scaleEffect(0.45)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "circle").foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
        }
    }
}

// MARK: - The bubble

private struct TutorBubbleView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bot = TutorBot.shared
    let bubble: TutorBot.Bubble

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bubble.text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let action = bubble.action {
                    Button(action) { bot.start(bubble.kind, appState: appState) }
                        .buttonStyle(SoftChipStyle(selected: true))
                    Button("Not now") { bot.dismissBubble() }
                        .buttonStyle(SoftChipStyle())
                } else {
                    Button("OK") { bot.dismissBubble() }
                        .buttonStyle(SoftChipStyle())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                               bottomTrailingRadius: 6, topTrailingRadius: 18,
                                               style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The chat

/// The chat is built from what the app already has: every line is a
/// `DialogueLine` (the call's own surface), the input is Watch's situation
/// box (`SpeakOrTypeField` with the send button inside its row), and every
/// button is `SoftChipStyle`.
struct TutorChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bot = TutorBot.shared
    @ObservedObject private var chat = TutorChat.shared
    @State private var draft = ""
    @State private var dictationLocale = ""
    @FocusState private var typing: Bool
    @ObservedObject private var goals = UpcomingGoalStore.shared
    @State private var addingGoal = false
    @State private var goalPage: UpcomingGoal?

    private var suggestions: [String] {
        [explain("What should I do now?"),
         explain("Why do I keep making the same mistake?"),
         explain("I only have 5 minutes"),
         explain("Am I getting better?"),
         explain("How do I reach the next level?")]
    }

    private var tutorName: String { explain("Tutor") }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        goalLine
                        DialogueLine(speaker: .other, name: tutorName) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(TutorCopy.opening(bot))
                                if let why = TutorCopy.why(bot.today) {
                                    Text(why).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if !bot.picks.isEmpty {
                                    TutorPickRows(picks: bot.picks, balance: bot.balance).padding(.top, 4)
                                }
                                if !bot.today.items.isEmpty {
                                    TutorPlanRows(today: bot.today).padding(.top, 4)
                                }
                            }
                        }
                        DialogueLine(speaker: .other, name: tutorName) {
                            Text("Ask me anything about your practice. I answer from your own talks, cards and routine.")
                        }
                        ForEach(chat.messages) { m in
                            messageLine(m).id(m.id)
                        }
                        if chat.thinking {
                            DialogueLine(speaker: .other, name: tutorName) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Thinking…").foregroundStyle(.secondary)
                                }
                            }
                            .id("thinking")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
                .onChange(of: chat.thinking) { _, on in
                    if on { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Text("Personal tutor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
            // The call's own bottom bar (`fadingBottomBar`): the messages
            // dissolve under the chips and the box instead of being cut.
            .fadingBottomBar { composer }
        }
        .sheet(item: $bot.reading) { r in
            TutorReadingSheet(reading: r).environmentObject(appState)
        }
        .sheet(isPresented: $addingGoal) {
            UpcomingGoalEditor(goal: nil, language: appState.targetLanguage).environmentObject(appState)
        }
        .sheet(item: $goalPage) { goal in
            UpcomingGoalPage(goal: goal).environmentObject(appState)
        }
        .onChange(of: goals.goals) { _, _ in bot.loadPicks(appState: appState) }
        .presentationDragIndicator(.visible)
        .onAppear {
            if dictationLocale.isEmpty {
                dictationLocale = SpeakOrTypeField.defaultLocale(appLanguage: appState.nativeLanguage,
                                                                 targetLanguage: appState.targetLanguage)
            }
            chat.resetIfNewDay()
            bot.refresh(appState: appState, visible: false)
            Analytics.capture("tutor_bot_opened")
        }
    }

    /// What the learner is preparing for, first: the goals ahead (tap one
    /// for its page), or the offer to write one, right here.
    private var goalLine: some View {
        let ahead = goals.active(language: appState.targetLanguage)
        return DialogueLine(speaker: .other, name: tutorName) {
            VStack(alignment: .leading, spacing: 10) {
                if ahead.isEmpty {
                    Text("Preparing for something? An interview, an exam, a presentation. Tell me what and when, and every day I'll prepare you for it.")
                    Button { addingGoal = true } label: {
                        Label("Add a goal", systemImage: "plus")
                    }
                    .buttonStyle(SoftChipStyle(selected: true))
                } else {
                    ForEach(ahead) { goal in
                        Button { goalPage = goal } label: {
                            HStack(spacing: 6) {
                                UpcomingGoalRow(goal: goal)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { addingGoal = true } label: {
                        Label("Add a goal", systemImage: "plus")
                    }
                    .buttonStyle(SoftChipStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func messageLine(_ m: TutorChat.Message) -> some View {
        if m.fromLearner {
            DialogueLine(speaker: .user, name: chrome("You")) { Text(m.text) }
        } else {
            DialogueLine(speaker: .other, name: tutorName) {
                Text(m.text).textSelection(.enabled)
            } accessory: {
                if let kind = m.action {
                    Button { bot.start(kind, appState: appState) } label: {
                        Label(TutorCopy.startTitle(kind), systemImage: kind.symbol)
                    }
                    .buttonStyle(SoftChipStyle(selected: true))
                } else if m.quiz {
                    Button { bot.start(nil, appState: appState) } label: {
                        Label("Quick quiz", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(SoftChipStyle(selected: true))
                }
            }
        }
    }

    /// Watch's situation box: suggestion chips above, one field whose row
    /// carries the mic, the dictation language and the send button.
    private var composer: some View {
        VStack(spacing: 0) {
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { q in
                            Button(q) { send(q) }
                                .buttonStyle(SoftChipStyle(selected: true))
                                .disabled(chat.thinking)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
            SpeakOrTypeField(text: $draft,
                             locale: $dictationLocale,
                             placeholder: explain("Ask me anything…"),
                             showsLocalePicker: true,
                             lineRange: 1...5,
                             externalFocus: $typing,
                             micStyle: .plain,
                             trailingControls: AnyView(sendButton))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: draft.isEmpty)
    }

    /// The box's own CTA (`ScenarioComposerSheet.inlineCTA`): a filled
    /// accent circle, shown once there is something to send.
    @ViewBuilder private var sendButton: some View {
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !chat.thinking {
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.themeAccent))
                    .foregroundStyle(Color.onAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Send"))
        }
    }

    private func send(_ q: String) {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        typing = false
        Task { await chat.ask(text, appState: appState) }
    }
}

// MARK: - Words

/// What the note and the chat's first message say. Computed from the day,
/// never asked of a model, so it is instant and agrees with My routine.
enum TutorCopy {
    static func greeting(now: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: now)
        switch h {
        case 5..<12: return explain("Good morning.")
        case 12..<18: return explain("Hi there.")
        default: return explain("Good evening.")
        }
    }

    /// The note's and the chat's first line: today's plan in numbers
    /// (2026-10-28, founder: the first pick's announcement, "Today's episode
    /// is here. Listen first.", read wrong as the title — the pick's own row
    /// already says it). With nothing planned but picks to offer, says so.
    @MainActor
    static func opening(_ bot: TutorBot) -> String {
        if bot.today.items.isEmpty, !bot.today.restDay, !bot.picks.isEmpty {
            return explain("Here's what I'd pick for today.")
        }
        return summary(bot.today)
    }

    static func summary(_ t: TutorBot.Today) -> String {
        if t.restDay {
            return t.dueCards > 0
                ? explain("Today is a rest day in your routine. If you feel like it, \(t.dueCards) cards are waiting.")
                : explain("Today is a rest day in your routine. Nothing you have to do.")
        }
        if t.items.isEmpty { return explain("Nothing planned today.") }
        if t.allDone { return explain("Everything for today is done. See you tomorrow.") }
        if t.suggested { return explain("You don't have a routine yet, so here's what I'd do today.") }
        let left = t.left.count
        if left == t.items.count {
            return explain("Today: \(left) things, about \(t.minutesLeft) minutes.")
        }
        return explain("\(t.items.count - left) done, \(left) to go, about \(t.minutesLeft) minutes.")
    }

    /// Why today looks like this — one line, only when there is a reason.
    static func why(_ t: TutorBot.Today) -> String? {
        if let label = t.focusLabel, t.focusTalks >= GrammarFocus.minTalks {
            return explain("We're working on \(label). It came up in \(t.focusTalks) of your talks.")
        }
        let reviewPlanned = t.items.contains { $0.kind == .review }
        if t.dueCards > 0, !reviewPlanned {
            return explain("\(t.dueCards) cards from your own talks are waiting.")
        }
        if t.streak >= 2 { return explain("\(t.streak) days in a row. Keep it going.") }
        return nil
    }

    static func when(_ item: TutorBot.Item) -> String {
        if item.done { return explain("Done") }
        if item.anytime { return explain("Anytime") }
        return item.start.formatted(date: .omitted, time: .shortened)
    }

    static func startTitle(_ kind: StudyPlan.Kind) -> String {
        switch kind {
        case .talk: return explain("Start a talk")
        case .review, .words, .expressions: return explain("Start review")
        case .shadow: return explain("Start shadowing")
        case .sayItAgain: return explain("Say it again")
        case .listen: return explain("Listen")
        case .speech: return explain("Open Speech")
        case .test: return explain("Take the test")
        }
    }
}

// MARK: - Picks

/// Today's picks beyond the routine, each with why it is here now, under
/// the week's speaking / listening / reading days.
struct TutorPickRows: View {
    @EnvironmentObject private var appState: AppState
    let picks: [TutorPick]
    let balance: TutorBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(explain("This week · speaking \(balance.speaking) d · listening \(balance.listening) d · reading \(balance.reading) d"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                if i > 0 { Divider().padding(.leading, 40) }
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: pick.symbol)
                        .font(.footnote)
                        .foregroundStyle(color(pick.kind))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        if let tag = pick.tag {
                            Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(color(pick.kind))
                        }
                        Text(pick.title).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !pick.why.isEmpty {
                            Text(pick.why).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(pick.buttonTitle) { TutorBot.shared.start(pick, appState: appState) }
                        .buttonStyle(SoftChipStyle(selected: true))
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func color(_ kind: TutorPick.Kind) -> Color {
        switch kind {
        case .rankDrop: return .red
        case .newEpisode, .listen: return .cyan
        case .firstSpeech: return .purple
        case .readScript, .readNews: return .brown
        case .goalReading, .goalSpeech, .goalDrill: return .purple
        }
    }
}

/// A reading opened from a pick: the episode's script at once, or the news
/// article, written the first time anyone opens it.
struct TutorReadingSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let reading: TutorReading
    @State private var script: SpeechScript?
    @State private var failed = false

    var body: some View {
        Group {
            if let s = script ?? reading.script {
                SpeechScriptSheet(script: s, study: reading.study, shipped: true,
                                  studyHere: reading.script == nil || reading.goal != nil,
                                  canPractice: reading.part == .speech)
            } else {
                NavigationStack {
                    Group {
                        if failed {
                            ContentUnavailableView {
                                Label("Couldn't open the article", systemImage: "newspaper")
                            } description: {
                                Text("Check your connection and try again.")
                            } actions: {
                                Button("Try again") { failed = false; Task { await load() } }
                            }
                        } else {
                            ProgressView {
                                Text(reading.goal == nil ? "Writing the article for your level…"
                                                         : "Writing today's preparation for your goal…")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(Text("Close"))
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard script == nil, reading.script == nil else { return }
        if let goal = reading.goal, let part = reading.part {
            do {
                let prep = try await GoalPrep.load(goal: goal, appState: appState)
                script = prep.script(part)
                TutorBot.shared.loadPicks(appState: appState, force: true)
            } catch {
                failed = true
            }
            return
        }
        guard let story = reading.story else { return }
        do {
            script = try await NewsArticle.load(story, language: appState.targetLanguage,
                                                level: appState.proficiency)
            ActivityEventLog.shared.record(.read)
            Analytics.capture("news_article_opened", ["category": story.category ?? ""])
        } catch {
            failed = true
        }
    }
}
