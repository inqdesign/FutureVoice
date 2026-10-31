import SwiftUI

/// Tutor mode's checklist, pinned above the transcript (`TutorLesson`).
///
/// The lesson's 3–4 challenges with what is done, what is being worked on
/// now, and what is left. Tapping the header folds it to one line, so a
/// long lesson doesn't eat the transcript. The ticks are the app's
/// (correction + judge), never the tutor's word.
struct TutorLessonStrip: View {
    let lesson: TutorLesson?
    let planning: Bool
    @Binding var expanded: Bool
    /// Drop this lesson and pick another topic.
    var onChangeTopic: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: lesson?.isFinished == true ? "checkmark.seal.fill" : "graduationcap.fill")
                        .foregroundStyle(lesson?.isFinished == true ? Color.green : Color.themeAccent)
                    if let lesson, lesson.inFinalCheck {
                        // The final check: nothing to lean on (founder,
                        // 2026-10-28). The title and the step, no rows, no
                        // way out of it from here.
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(explain("Final check"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.themeAccent)
                    } else if let lesson {
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(lesson.doneCount)/\(lesson.challenges.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                        Group {
                            AppMenu {
                                Button(action: onChangeTopic) {
                                    Label(explain("Choose another topic"), systemImage: "arrow.triangle.2.circlepath")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text(explain("Choose another topic")))
                        }
                    } else {
                        Text(explain("Preparing your lesson…"))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        ProgressView().controlSize(.small)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(lesson == nil || lesson?.inFinalCheck == true)

            if let lesson, lesson.inFinalCheck {
                Text(explain("Say it all in your own words, in one go."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // What it should cover, as the parts' short names only —
                // never their example lines (founder, 2026-10-28: three or
                // four parts are hard to hold in your head with nothing on
                // screen).
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lesson.challenges.enumerated()), id: \.element.id) { i, c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "\(i + 1).circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(c.goal)
                                .font(.footnote)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if let lesson, expanded {
                if lesson.isFinished {
                    Text(explain("Passed. You can say it now."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(lesson.challenges.enumerated()), id: \.element.id) { i, c in
                    row(i, c, isNow: lesson.current == i)
                }
                if planning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(explain("Preparing your lesson…"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func row(_ i: Int, _ c: TutorLesson.Challenge, isNow: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if c.doneAt != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if isNow {
                    Image(systemName: "\(i + 1).circle.fill").foregroundStyle(Color.themeAccent)
                } else {
                    Image(systemName: "\(i + 1).circle").foregroundStyle(.tertiary)
                }
            }
            .font(.footnote)
            Text(c.goal)
                .font(.footnote.weight(isNow ? .semibold : .regular))
                .foregroundStyle(c.doneAt != nil ? .secondary : .primary)
                .strikethrough(c.doneAt != nil, color: .secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(c.doneAt != nil ? Text(explain("Done")) : (isNow ? Text(explain("Now")) : Text("")))
    }
}

/// The tutor's curriculum, behind the button right of the pill
/// (`TutorCurriculum`, 2026-10-28). One "Next up", the chapters with how
/// many topics are passed, and inside a chapter every topic with its state.
/// A topic above the learner's level reads "Step up" and is still a tap
/// away, after one question (soft unlocking). The learner's own scenarios
/// stay at the bottom; they aren't counted on the map. Picking starts the
/// lesson.
struct TutorTopicSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    /// The topic as the planner gets it, and its curriculum id (nil for the
    /// learner's own scenarios).
    let onPick: (String, String?) -> Void
    /// Set when the page stands BESIDE the call (the Mac's side column):
    /// Close calls it, and a pick leaves the page open so the curriculum
    /// stays in view while the lesson runs.
    var onClose: (() -> Void)? = nil

    @State private var progress: [String: TutorTopicProgress] = [:]
    @State private var stepUp: TutorCurriculum.Topic?

    private var level: CEFRLevel { appState.proficiency }

    var body: some View {
        NavigationStack {
            List {
                if let next = TutorCurriculum.next(progress: progress, level: level) {
                    Section(explain("Next up")) {
                        Button { pick(next.topic) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.themeAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(next.topic.title).foregroundStyle(.primary)
                                    Text(progress[next.topic.id]?.checkLeft == true
                                         ? explain("Final check left") : next.chapter.title)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(TutorCurriculum.chapters) { chapter in
                        NavigationLink {
                            chapterPage(chapter)
                        } label: {
                            chapterRow(chapter)
                        }
                    }
                } header: {
                    Text(explain("Curriculum"))
                } footer: {
                    let passed = progress.values.filter { $0.passedAt != nil }.count
                    let total = TutorCurriculum.chapters.reduce(0) { $0 + $1.topics.count }
                    Text(explain("\(passed) of \(total) topics passed"))
                }
                let own = appState.scenarios.filter { $0.starterId == nil && $0.archivedAt == nil }.prefix(12)
                if !own.isEmpty {
                    Section(chrome("Your scenarios")) {
                        ForEach(Array(own), id: \.id) { s in
                            Button {
                                onPick(s.environment, nil)
                                afterPick()
                            } label: {
                                Label(s.environment, systemImage: "theatermasks.fill")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(explain("What to practice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Beside the call (an inspector) a bar item would be merged
                // into the CALL's bar, as a "Cl…" next to its ✕ even while
                // the column is shut, so the column carries its own ✕ below.
                if onClose == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        BarCloseButton() { dismiss() }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(explain("Close"))
                    .padding(12)
                }
            }
            .confirmationDialog(explain("This one is a step up. Try it?"),
                                isPresented: Binding(get: { stepUp != nil },
                                                     set: { if !$0 { stepUp = nil } }),
                                titleVisibility: .visible,
                                presenting: stepUp) { topic in
                Button(explain("Try it")) { start(topic) }
                Button(explain("Not now"), role: .cancel) { stepUp = nil }
            } message: { _ in
                Text(explain("The tutor will keep it at your level."))
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { progress = TutorProgressStore.all(language: appState.targetLanguage) }
    }

    private func chapterRow(_ chapter: TutorCurriculum.Chapter) -> some View {
        let passed = chapter.topics.filter { progress[$0.id]?.passedAt != nil }.count
        return HStack(spacing: 12) {
            Image(systemName: chapter.icon)
                .foregroundStyle(Color.themeAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(chapter.title).foregroundStyle(.primary)
                ProgressView(value: Double(passed), total: Double(max(chapter.topics.count, 1)))
                    .tint(.green)
            }
            Text(verbatim: "\(passed)/\(chapter.topics.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func chapterPage(_ chapter: TutorCurriculum.Chapter) -> some View {
        List {
            ForEach(chapter.topics) { topic in
                Button { pick(topic) } label: { topicRow(topic) }
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func topicRow(_ topic: TutorCurriculum.Topic) -> some View {
        let p = progress[topic.id]
        let step = p?.passedAt == nil && TutorCurriculum.isStepUp(topic, level: level)
        return HStack(spacing: 12) {
            Group {
                if p?.passedAt != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if p?.checkLeft == true {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.green)
                } else if p?.inProgress == true {
                    Image(systemName: "circle.dotted").foregroundStyle(Color.themeAccent)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title).foregroundStyle(step ? .secondary : .primary)
                if p?.checkLeft == true {
                    Text(explain("Final check left")).font(.footnote).foregroundStyle(.secondary)
                } else if p?.inProgress == true {
                    Text(explain("In progress")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let rounds = p?.rounds, rounds > 1 {
                Text(explain("\(rounds) rounds"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if step {
                Text(explain("Step up"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func pick(_ topic: TutorCurriculum.Topic) {
        let p = progress[topic.id]
        if p?.passedAt == nil, TutorCurriculum.isStepUp(topic, level: level) {
            stepUp = topic
        } else {
            start(topic)
        }
    }

    private func start(_ topic: TutorCurriculum.Topic) {
        stepUp = nil
        onPick(topic.title, topic.id)
        afterPick()
    }

    private func afterPick() {
        if onClose == nil {
            dismiss()
        } else {
            progress = TutorProgressStore.all(language: appState.targetLanguage)
        }
    }
}
