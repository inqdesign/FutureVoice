import SwiftUI

/// The quick quiz's door on the Talk tab: the test host's face and nothing
/// else, floating beside "Find a topic" (2026-10-18, founder).
struct QuickQuizButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            WeeklyTestCharacter(mood: .waiting, since: .distantPast, tile: .clear)
                .scaleEffect(30 / WeeklyTestCharacter.size)
                .frame(width: 30, height: 30)
        }
        .modifier(GlassCircleButton())
        .accessibilityLabel(Text("Quiz"))
        // Only in the foreground: a launch nobody sees (an update, a
        // background wake) would be suspended mid-request.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            QuickQuizStock.prewarm(appState: appState)
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "openQuiz") { showing = true } }
        #endif
        .fullScreenCover(isPresented: $showing) {
            QuickQuizView().environmentObject(appState)
        }
    }
}

private struct GlassCircleButton: ViewModifier {
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

/// Ten one-tap questions on what is being studied now (`QuickQuizEngine`),
/// then the score and what was missed. Nothing is saved to disk; a quiz
/// closed midway waits in memory for the next open.
struct QuickQuizView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case loading, empty, asking, done }
    @State private var stage: Stage = .loading
    @State private var items: [QuickQuizItem] = []
    @State private var index = 0
    @State private var chosen: String?
    @State private var missed: [QuickQuizItem] = []
    @State private var mood: WeeklyTestCharacter.Mood = .thinking
    @State private var moodSince = Date()
    @State private var advance: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .loading: loading
                case .empty: empty
                case .asking: question
                case .done: result
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(Text("Quiz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
                if stage == .asking {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(verbatim: "\(index + 1) / \(items.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await start() }
        .onDisappear {
            advance?.cancel()
            // Closed mid-quiz: kept for the next open. An answered question
            // counts as done, since its auto-advance was just cancelled.
            if stage == .asking {
                QuickQuizEngine.park(items: items, index: chosen == nil ? index : index + 1,
                                     missed: missed, language: appState.targetLanguage)
            }
        }
    }

    // MARK: - Stages

    private var loading: some View {
        VStack(spacing: 16) {
            face
            Text("Getting your quiz ready…")
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            face
            Text("Not much to quiz yet")
                .font(.headline)
            Text("Save a few words or have another talk, and the quiz fills up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    /// The question sits in the middle of the space above, the choices at
    /// the bottom where the thumb is, and Next keeps one slot under them
    /// (2026-10-22, founder: the first layout stacked everything at the top
    /// and left the lower half empty).
    private var question: some View {
        let item = items[index]
        let waiting = chosen != nil && item.note != nil
        return VStack(spacing: 0) {
            ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                .tint(Color.themeAccent)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)
                        VStack(spacing: 14) {
                            face
                            Text(heading(item))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            if !item.prompt.isEmpty {
                                Text(item.prompt)
                                    .font(item.kind == .word ? .title.weight(.semibold) : .title2.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                            // A note (why, or what it means) waits to be read.
                            if chosen != nil, let note = item.note {
                                Text(note)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 6)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 28)
                        Spacer(minLength: 24)
                        VStack(spacing: 10) {
                            ForEach(item.options, id: \.self) { option in
                                optionButton(option, item: item)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            // Next keeps its room while hidden, so nothing shifts when it
            // appears (founder, 2026-10-19).
            Button {
                next()
            } label: {
                Text("Next").frame(maxWidth: .infinity)
            }
            .accentProminent()
            .controlSize(.large)
            .padding(.horizontal, 20)
            .opacity(waiting ? 1 : 0)
            .disabled(!waiting)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .animation(.easeOut(duration: 0.2), value: chosen)
    }

    /// Neutral until answered; then the answer turns green, a wrong pick red,
    /// and the rest step back.
    private func optionButton(_ option: String, item: QuickQuizItem) -> some View {
        let isAnswer = option == item.answer
        let isPicked = option == chosen
        let tint: Color = {
            guard chosen != nil else { return .gray }
            if isAnswer { return .green }
            return isPicked ? .red : .gray
        }()
        return Button { pick(option, item: item) } label: {
            HStack(spacing: 10) {
                Text(option)
                    .font(.body.weight(.medium))
                    .foregroundStyle(chosen == nil || isAnswer || isPicked ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if chosen != nil, isAnswer || isPicked {
                    Image(systemName: isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .tint(tint)
        .opacity(chosen == nil || isAnswer || isPicked ? 1 : 0.55)
        .allowsHitTesting(chosen == nil)
    }

    private var result: some View {
        let right = items.count - missed.count
        return List {
            Section {
                VStack(spacing: 12) {
                    face(tile: Color(.secondarySystemGroupedBackground))
                    Text(verbatim: "\(right) / \(items.count)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    if !missed.isEmpty {
                        Text("The ones you missed are back in your review.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            if !missed.isEmpty {
                Section {
                    ForEach(missed) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.kind == .word ? item.answer : item.solved)
                                .font(.body.weight(.medium))
                            Text(item.kind == .word ? item.prompt : (item.heading ?? item.answer))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Missed")
                }
                Section {
                    Button { retryMissed() } label: {
                        Label("Try the missed ones", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            Section {
                Button("Done") { dismiss() }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var face: some View { face(tile: Color(.secondarySystemBackground)) }

    /// On the result List the plain tile vanishes into the grouped page.
    private func face(tile: Color) -> some View {
        WeeklyTestCharacter(mood: mood, since: moodSince, tile: tile)
            .scaleEffect(56 / WeeklyTestCharacter.size)
            .frame(width: 56, height: 56)
    }

    private func heading(_ item: QuickQuizItem) -> String {
        switch item.kind {
        case .word: explain("What's the word?")
        case .expression: explain("Fill in the blank")
        case .grammar: item.heading ?? explain("Grammar")
        }
    }

    // MARK: - Flow

    private func start() async {
        #if DEBUG
        // Capture harness: `-quizsample 1` deals fixed questions (no network),
        // `-quizindex N` opens on one, `-quizanswer 1` answers it right.
        if UserDefaults.standard.bool(forKey: "quizsample") {
            items = Self.sampleItems
            index = min(max(UserDefaults.standard.integer(forKey: "quizindex"), 0), items.count - 1)
            setMood(.waiting)
            stage = .asking
            if UserDefaults.standard.bool(forKey: "quizanswer") { pick(items[index].answer, item: items[index]) }
            return
        }
        #endif
        if let paused = QuickQuizEngine.takeUnfinished(language: appState.targetLanguage) {
            items = paused.items
            index = paused.index
            missed = paused.missed
            setMood(.waiting)
            stage = .asking
            Analytics.capture("quick_quiz_resumed", ["items": items.count, "at": index])
            return
        }
        let built = await QuickQuizEngine.build(appState: appState)
        // Closed while it was being written: keep it for the next open
        // rather than throwing away questions already marked asked.
        if Task.isCancelled {
            QuickQuizEngine.park(items: built, index: 0, missed: [], language: appState.targetLanguage)
            return
        }
        items = built
        setMood(.waiting)
        stage = built.isEmpty ? .empty : .asking
        Analytics.capture("quick_quiz_started", ["items": built.count])
    }

    private func pick(_ option: String, item: QuickQuizItem) {
        guard chosen == nil else { return }
        chosen = option
        let correct = option == item.answer
        QuickQuizEngine.apply(item, correct: correct)
        if correct {
            HapticEngine.success()
            SoundEffects.play(.right)
            setMood(.happy)
        } else {
            missed.append(item)
            HapticEngine.error()
            SoundEffects.play(.wrong)
            setMood(.sad)
        }
        // An item with a note waits on its Next button, under the note.
        guard item.note == nil else { return }
        advance = Task { @MainActor in
            try? await Task.sleep(nanoseconds: correct ? 700_000_000 : 1_400_000_000)
            guard !Task.isCancelled else { return }
            next()
        }
    }

    private func next() {
        chosen = nil
        if index + 1 < items.count {
            index += 1
            setMood(.waiting)
        } else {
            let ratio = Double(items.count - missed.count) / Double(max(items.count, 1))
            setMood(ratio >= 0.8 ? .happy : .waiting)
            SoundEffects.play(.done)
            stage = .done
            Analytics.capture("quick_quiz_finished", ["items": items.count, "missed": missed.count])
        }
    }

    private func retryMissed() {
        items = missed.map { QuickQuizItem(kind: $0.kind, prompt: $0.prompt, answer: $0.answer,
                                          options: $0.options.shuffled(),
                                          heading: $0.heading, note: $0.note, isOwn: $0.isOwn) }
        missed = []
        index = 0
        chosen = nil
        setMood(.waiting)
        stage = .asking
    }

    #if DEBUG
    static let sampleItems: [QuickQuizItem] = [
        QuickQuizItem(kind: .expression, prompt: "You look so quiet today. \(WeeklyTestEngine.blankMark)?",
                      answer: "What's on your mind",
                      options: ["How does that sound", "What's on your mind", "Where are you headed", "What brings you here"],
                      note: "What's on your mind — 무슨 생각해?", isOwn: true),
        QuickQuizItem(kind: .word, prompt: "어떤 일을 하기 싫어서 미루다", answer: "procrastinate",
                      options: ["procrastinate", "negotiate", "hesitate", "appreciate"]),
        QuickQuizItem(kind: .grammar, prompt: "I \(WeeklyTestEngine.blankMark) here since 2020.",
                      answer: "have worked", options: ["work", "have worked", "am working", "worked"],
                      heading: "현재완료", note: "since로 지금까지 이어지는 일은 현재완료예요."),
    ]
    #endif

    private func setMood(_ m: WeeklyTestCharacter.Mood) {
        mood = m
        moodSince = Date()
    }
}
