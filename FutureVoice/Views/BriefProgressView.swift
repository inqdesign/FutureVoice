import SwiftUI

/// The board shown while a scenario's attached material is being read —
/// the wrap-up board's shape (`SummaryProgressView`), for the same reason:
/// the one call is the whole wait, it streams, and a section ticks the
/// moment the model closes it. Every number is the count that lands on the
/// book page afterwards; nothing here is simulated.
struct BriefProgressView: View {
    let sources: [ScenarioBrief.Source]
    let progress: ScenarioBriefEngine.Progress

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let done: Bool
        let count: Int?
    }

    private var steps: [Step] {
        var out: [Step] = []
        for (i, src) in sources.enumerated() {
            let done = i < progress.sourcesRead.count && progress.sourcesRead[i]
            let title: String
            switch src.kind {
            case .link: title = explain("Reading the link")
            case .file: title = explain("Reading \(src.label)")
            case .image: title = explain("Reading the photo")
            }
            out.append(Step(id: i, title: title, done: done, count: nil))
        }
        let base = sources.count
        out.append(Step(id: base, title: explain("What this is about"), done: progress.summary, count: nil))
        out.append(Step(id: base + 1, title: explain("What they will ask"),
                        done: progress.likelyQuestions != nil, count: progress.likelyQuestions))
        out.append(Step(id: base + 2, title: explain("What to have ready"),
                        done: progress.learnerFacts != nil, count: progress.learnerFacts))
        out.append(Step(id: base + 3, title: explain("Key expressions"),
                        done: progress.keyExpressions != nil, count: progress.keyExpressions))
        return out
    }

    private var doneCount: Int { steps.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading your material…")
                .font(.title3.weight(.semibold))
            ProgressView(value: Double(doneCount), total: Double(max(steps.count, 1)))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(spacing: 10) {
                        if step.done {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if step.id == doneCount {
                            ProgressView().controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                        Text(step.title)
                            .foregroundStyle(step.done ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                        if step.done, let n = step.count, n > 0 {
                            Text("\(n)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .animation(.easeOut(duration: 0.2), value: step.done)
                }
            }
            Text(explain("Read once. The files stay where they are on your phone — only what was read is kept."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: 440)
    }
}
