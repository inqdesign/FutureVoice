import SwiftUI

// The tutor bot's three surfaces (`TutorBot`): the face, the note and the
// bubble float over the Talk home; the chat is a sheet. On the Mac's
// two-column Talk page the chat is the column's Tutor tab (`TalkSideColumn`).

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
    /// The Mac's two-column Talk page: the note and the chat live in the
    /// column's Tutor tab, and there is no bottom row to sit above.
    var inColumnMode = false
    /// False while the Tutor tab is showing — it says the same thing.
    var showBubble = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if bot.noteShown && !inColumnMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { bot.closeNote() }
                    .ignoresSafeArea()
                TutorNoteCard()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 80)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            } else if let b = bot.bubble, showBubble {
                TutorBubbleView(bubble: b)
                    .padding(.trailing, 16)
                    .padding(.bottom, inColumnMode ? 16 : 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        // The model writes these plainly (see `TutorBot.closeNote`); the
        // note and the bubble animate here.
        .animation(bot.noteShown ? .smooth(duration: 0.3) : .easeInOut(duration: 0.35), value: bot.noteShown)
        .animation(bot.bubble == nil ? .easeOut(duration: 0.25) : .easeOut(duration: 0.35), value: bot.bubble)
        .sheet(item: $bot.goalPage) { goal in
            UpcomingGoalPage(goal: goal).environmentObject(appState)
        }
        // The chat shows its own; this one is for a reading opened from the note.
        .sheet(item: Binding(get: { bot.chatOpen || inColumnMode ? nil : bot.reading },
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
            if !bot.picks.isEmpty || !t.items.isEmpty {
                TutorTodayRows()
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
                Button { TutorBot.shared.start(item.kind, appState: appState) } label: {
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
                    } else if item.progress > 0 {
                        Gauge(value: item.progress) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .scaleEffect(0.45)
                            .frame(width: 22, height: 22)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.id == next?.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
    @Environment(\.inTalkSideColumn) private var inColumn
    @ObservedObject private var bot = TutorBot.shared
    @ObservedObject private var chat = TutorChat.shared
    /// Tutor replies whose translation is unfolded.
    @State private var translated: Set<UUID> = []
    @State private var draft = ""
    @State private var dictationLocale = ""
    @FocusState private var typing: Bool
    @ObservedObject private var goals = UpcomingGoalStore.shared
    @State private var addingGoal = false
    @State private var goalPage: UpcomingGoal?
    @State private var todayOpen = false

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
                                if !bot.picks.isEmpty || !bot.today.items.isEmpty {
                                    TutorTodayRows().padding(.top, 4)
                                }
                            }
                        }
                        DialogueLine(speaker: .other, name: tutorName) {
                            Text("Ask me anything about your practice. I answer from your own talks, cards and routine.")
                        }
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { i, m in
                            // A day's first message carries its date: the
                            // thread is kept, so yesterday's answer must not
                            // read as today's.
                            if i == 0 || !Calendar.current.isDate(chat.messages[i - 1].at, inSameDayAs: m.at) {
                                Text(m.at.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            messageLine(m).id(m.id)
                        }
                        if chat.thinking {
                            DialogueLine(speaker: .other, name: tutorName) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(chat.status.isEmpty ? explain("Thinking…") : chat.status)
                                        .foregroundStyle(.secondary)
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
            // In the Mac's Talk column it wears the column's grouped ground,
            // like the player and the topics beside it.
            .background((inColumn ? Color(.systemGroupedBackground) : Color(.systemBackground)).ignoresSafeArea())
            .navigationTitle(Text("Personal tutor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A tab of the Mac's Talk column stays open; only the sheet closes.
                if !inColumn {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("Close"))
                    }
                }
                if !chat.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        moreMenu
                        .accessibilityLabel(Text("More"))
                    }
                }
            }
            // The call's own bottom bar (`fadingBottomBar`): the messages
            // dissolve under the chips and the box instead of being cut.
            .fadingBottomBar { composer }
        }
        .sheet(item: $bot.reading) { r in
            TutorReadingSheet(reading: r).environmentObject(appState)
        }
        .sheet(isPresented: $bot.callSettingsOpen) { CallSettingsSheet() }
        .sheet(isPresented: $bot.purposesOpen) { PurposesEditor().environmentObject(appState) }
        .sheet(isPresented: $addingGoal) {
            UpcomingGoalEditor(goal: nil, language: appState.targetLanguage).environmentObject(appState)
        }
        .sheet(item: $goalPage) { goal in
            UpcomingGoalPage(goal: goal).environmentObject(appState)
        }
        .sheet(isPresented: $todayOpen) { todaySheet.environmentObject(appState) }
        .onChange(of: goals.goals) { _, _ in bot.loadPicks(appState: appState) }
        .presentationDragIndicator(.visible)
        .onAppear {
            if dictationLocale.isEmpty {
                dictationLocale = SpeakOrTypeField.defaultLocale(appLanguage: appState.nativeLanguage,
                                                                 targetLanguage: appState.targetLanguage)
            }
            // This page offers two languages only: the one being learned and their own.
            if !voiceLocales.isEmpty, !voiceLocales.contains(dictationLocale) {
                dictationLocale = voiceLocales.last ?? dictationLocale
            }
            chat.load(language: appState.targetLanguage)
            bot.refresh(appState: appState, visible: false)
            Analytics.capture("tutor_bot_opened")
        }
    }

    private var moreMenu: some View {
    AppMenu {
        Button(role: .destructive) { chat.clear() } label: {
            Label("Clear this chat", systemImage: "trash")
        }
    } label: {
        Image(systemName: "ellipsis")
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.text).textSelection(.enabled)
                    // The tutor speaks the language being learned; its words
                    // in the learner's own are one tap away, never in the way.
                    if let translation = m.translation {
                        if translated.contains(m.id) {
                            Text(translation).font(.subheadline).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button {
                            if !translated.insert(m.id).inserted { translated.remove(m.id) }
                        } label: {
                            Label(translated.contains(m.id) ? "Hide translation" : "Show translation",
                                  systemImage: "translate")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            } accessory: {
                if !m.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(m.actions.enumerated()), id: \.offset) { i, action in
                            Button { bot.perform(action, appState: appState) } label: {
                                Label(action.title, systemImage: action.symbol)
                            }
                            .buttonStyle(SoftChipStyle(selected: i == 0))
                        }
                    }
                }
            }
        }
    }

    /// Watch's situation box: suggestion chips above, one field whose row
    /// carries the mic, the dictation language and the send button.
    /// The two languages the box's mic can dictate in: the one being
    /// learned first (the tutor speaks it), then the learner's own.
    private var voiceLocales: [String] {
        var out: [String] = []
        for code in [appState.targetLanguage, appState.nativeLanguage]
        where LanguageCatalog.canDictate(code) && !out.contains(where: { LanguageCatalog.sameLanguage($0, code) }) {
            out.append(code)
        }
        return out
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shortcutChips
                .padding(.bottom, 10)
                .transition(.opacity)
            }
            SpeakOrTypeField(text: $draft,
                             locale: $dictationLocale,
                             placeholder: explain("Ask me anything…"),
                             showsLocalePicker: true,
                             localeChoices: voiceLocales,
                             lineRange: 1...5,
                             externalFocus: $typing,
                             cardBackground: Color.clear,
                             micStyle: .plain,
                             trailingControls: AnyView(sendButton))
                // The Watch situation box's own card (24 pt, continuous):
                // the field's built-in 12 pt card read as a different
                // component. The fill is grey on the sheet's systemBackground,
                // where the grouped white would vanish, and the grouped card
                // white in the Mac's Talk column, whose ground is that grey.
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(inColumn ? Color(.secondarySystemGroupedBackground)
                                   : Color(.secondarySystemBackground)))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: draft.isEmpty)
    }

    /// Always within reach above the box (2026-11-19, founder): what the
    /// tutor works FROM, and where the learner sets it. The goals and
    /// today's plan open the thread, and a long conversation scrolled them
    /// away; canned questions sat here before and read as filler.
    private var shortcutChips: some View {
        let ahead = goals.active(language: appState.targetLanguage)
        let left = bot.today.left.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ahead.prefix(2)) { goal in
                    chip(goal.countdown().map { "\(goal.title) · \($0)" } ?? goal.title, "flag.fill", "goal") {
                        goalPage = goal
                    }
                }
                chip(explain("Add a goal"), "plus", "add_goal", selected: ahead.isEmpty) { addingGoal = true }
                chip(left > 0 ? "\(explain("Today's plan")) · \(left)" : explain("Today's plan"),
                     "checklist", "today") { todayOpen = true }
                chip(explain("My routine"), "calendar", "routine") { bot.perform(TutorAction(type: .routine), appState: appState) }
                chip(explain("Why are you learning?"), "target", "purposes") { bot.purposesOpen = true }
                chip(explain("Call settings"), "slider.horizontal.3", "settings") { bot.callSettingsOpen = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, _ symbol: String, _ kind: String, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button {
            typing = false
            Analytics.capture("tutor_bot_shortcut", ["kind": kind])
            action()
        } label: {
            Label(title, systemImage: symbol).lineLimit(1)
        }
        // The box's own fill: grey on the sheet's white, the grouped card
        // white in the Mac's Talk column, whose ground is that grey.
        .buttonStyle(SoftChipStyle(selected: selected,
                                   fill: inColumn ? Color(.secondarySystemGroupedBackground)
                                                  : Color(.secondarySystemBackground)))
    }

    /// Today's plan as its own sheet: the same rows the thread opens with.
    private var todaySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(TutorCopy.opening(bot)).font(.headline)
                    if let why = TutorCopy.why(bot.today) {
                        Text(why).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !bot.picks.isEmpty || !bot.today.items.isEmpty {
                        TutorTodayRows().padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle(Text("Today's plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton(action: { todayOpen = false }) }
            }
        }
        .presentationDetents([.medium, .large])
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
        // The count is the ROUTINE's: the list under it also holds the
        // tutor's picks, and "2 things" over six rows read as wrong.
        let left = t.left.count
        if left == t.items.count {
            return explain("Your routine today: \(left) things, about \(t.minutesLeft) minutes.")
        }
        return explain("Routine: \(t.items.count - left) done, \(left) to go, about \(t.minutesLeft) minutes.")
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
                Button { TutorBot.shared.start(pick, appState: appState) } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: pick.symbol)
                        .font(.footnote)
                        .foregroundStyle(Self.color(pick.kind))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        if let tag = pick.tag {
                            Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Self.color(pick.kind))
                        }
                        Text(pick.title).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !pick.why.isEmpty {
                            Text(pick.why).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(pick.buttonTitle))
            }
        }
    }

    static func color(_ kind: TutorPick.Kind) -> Color {
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
                                  // Everything the tutor wrote (a goal's reading and
                                  // answer, a news article) can be said under the
                                  // prompter; a podcast episode is two hosts talking.
                                  canPractice: reading.goal != nil || reading.story != nil)
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
