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
        .modifier(TutorGlassCircle())
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

private struct TutorGlassCircle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass(homeGlass(colorScheme)))
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .background(Circle().fill(.regularMaterial))
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
                    .padding(.bottom, 84)
                    .transition(.scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            } else if let b = bot.bubble {
                TutorBubbleView(bubble: b)
                    .padding(.trailing, 16)
                    .padding(.bottom, 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var face: some View {
        WeeklyTestCharacter(mood: .happy, since: bot.bubbleSince)
            .scaleEffect(40 / WeeklyTestCharacter.size)
            .frame(width: 40, height: 40)
    }

    // The first meeting: who this is and what it does.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                face
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hi, I'm your tutor.").font(.headline)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                face
                VStack(alignment: .leading, spacing: 4) {
                    Text(TutorCopy.greeting()).font(.headline)
                    Text(TutorCopy.summary(t)).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let why = TutorCopy.why(t) {
                        Text(why).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !t.items.isEmpty {
                TutorPlanRows(today: t)
            }
            HStack {
                if t.suggested {
                    Button("Make a routine") {
                        bot.closeNote()
                        appState.openRoutinePage = true
                    }
                } else {
                    Button("Later") { bot.closeNote() }
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { bot.openChat() } label: {
                    Label("Ask me", systemImage: "chevron.right").labelStyle(TrailingIconLabel())
                }
            }
            .font(.subheadline.weight(.semibold))
        }
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
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
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

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.title; configuration.icon.imageScale(.small) }
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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Not now") { bot.dismissBubble() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("OK") { bot.dismissBubble() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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

struct TutorChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bot = TutorBot.shared
    @ObservedObject private var chat = TutorChat.shared
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var suggestions: [String] {
        [explain("What should I do now?"),
         explain("Why do I keep making the same mistake?"),
         explain("I only have 5 minutes"),
         explain("Am I getting better?"),
         explain("How do I reach the next level?")]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            WeeklyTestCharacter(mood: .waiting, since: .distantPast)
                                .scaleEffect(36 / WeeklyTestCharacter.size)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TutorCopy.summary(bot.today)).font(.subheadline)
                                if let why = TutorCopy.why(bot.today) {
                                    Text(why).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !bot.today.items.isEmpty {
                            TutorPlanRows(today: bot.today)
                        }
                    } footer: {
                        Text("Ask me anything about your practice. I answer from your own talks, cards and routine.")
                    }

                    ForEach(chat.messages) { m in
                        messageRow(m).id(m.id)
                    }
                    if chat.thinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
            }
            .navigationTitle(Text("Tutor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            chat.resetIfNewDay()
            bot.refresh(appState: appState, visible: false)
            Analytics.capture("tutor_bot_opened")
        }
    }

    @ViewBuilder
    private func messageRow(_ m: TutorChat.Message) -> some View {
        if m.fromLearner {
            Text(m.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.text).font(.subheadline)
                    .textSelection(.enabled)
                if let kind = m.action {
                    Button { bot.start(kind, appState: appState) } label: {
                        Label(TutorCopy.startTitle(kind), systemImage: kind.symbol)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if m.quiz {
                    Button { bot.start(nil, appState: appState) } label: {
                        Label("Quick quiz", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !typing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { q in
                            Button(q) { send(q) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(chat.thinking)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 8) {
                TextField("Ask me anything…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($typing)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.thinking)
                    .accessibilityLabel(Text("Send"))
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.bar)
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
