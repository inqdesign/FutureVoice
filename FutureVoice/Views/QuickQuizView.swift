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
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
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
/// then the score and what was missed. Nothing is saved.
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
        .onDisappear { advance?.cancel() }
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

    private var question: some View {
        let item = items[index]
        return VStack(spacing: 0) {
            ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                .padding(.horizontal, 20)
            ScrollView {
                VStack(spacing: 20) {
                    face
                        .padding(.top, 16)
                    Text(heading(item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !item.prompt.isEmpty {
                        Text(item.prompt)
                            .font(item.kind == .word ? .title2.weight(.semibold) : .title3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 10) {
                        ForEach(item.options, id: \.self) { option in
                            optionButton(option, item: item)
                        }
                    }
                    .padding(.top, 4)
                    // A note (why, or what it means) waits to be read.
                    if chosen != nil, let note = item.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // Next sits in ONE place at the bottom, whatever the question's
            // length (founder, 2026-10-19: under the note it moved with the
            // content). Its room is kept while it is hidden, so the question
            // never shifts when it appears.
            let waiting = chosen != nil && item.note != nil
            Button("Next") { next() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .opacity(waiting ? 1 : 0)
                .disabled(!waiting)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
    }

    private func optionButton(_ option: String, item: QuickQuizItem) -> some View {
        let isAnswer = option == item.answer
        let tint: Color = {
            guard let chosen else { return .accentColor }
            if isAnswer { return .green }
            return option == chosen ? .red : .secondary
        }()
        return Button { pick(option, item: item) } label: {
            Text(option)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .tint(tint)
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
        let built = await QuickQuizEngine.build(appState: appState)
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

    private func setMood(_ m: WeeklyTestCharacter.Mood) {
        mood = m
        moodSince = Date()
    }
}
