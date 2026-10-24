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
                        .foregroundStyle(lesson?.isFinished == true ? Color.green : Color.accentColor)
                    if let lesson {
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
                        if !lesson.isFinished {
                            Menu {
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
            .disabled(lesson == nil)

            if let lesson, expanded {
                if lesson.isFinished {
                    Text(explain("All done. You can say it now."))
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
                    Image(systemName: "\(i + 1).circle.fill").foregroundStyle(Color.accentColor)
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

/// Topics to practice, for a learner who has no idea (the button right of
/// the pill). The Talk tab's own ready-made situations, by the learner's
/// purposes, plus the situations they built themselves — nothing new to
/// make or fetch. Picking one starts the lesson.
struct TutorTopicSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    private struct Group: Identifiable {
        let id: String
        let title: String
        let rows: [(icon: String, title: String)]
    }

    private var groups: [Group] {
        var seen = Set<String>()
        var out: [Group] = []
        let chips = LearningPurposeStore.chips(level: appState.proficiency)
        let ordered = chips.filter { $0.starters != nil }
            + (chips.contains(.everyday) ? [] : [DiscoverChip.everyday])
        for chip in ordered {
            let rows = (chip.starters ?? []).filter { seen.insert($0.id).inserted }
                .map { (icon: $0.icon, title: $0.title) }
            if !rows.isEmpty { out.append(Group(id: chip.rawValue, title: chip.label, rows: rows)) }
        }
        let own = appState.scenarios.filter { $0.starterId == nil && $0.archivedAt == nil }.prefix(12)
            .map { (icon: "theatermasks.fill", title: $0.environment) }
        if !own.isEmpty { out.append(Group(id: "own", title: chrome("Your scenarios"), rows: Array(own))) }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { g in
                    Section(g.title) {
                        ForEach(Array(g.rows.enumerated()), id: \.offset) { _, row in
                            Button {
                                onPick(row.title)
                                dismiss()
                            } label: {
                                Label(row.title, systemImage: row.icon)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(explain("What to practice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(explain("Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
