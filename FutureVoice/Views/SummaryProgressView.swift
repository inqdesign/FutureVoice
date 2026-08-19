import SwiftUI

/// The wait at the end of a talk, told as what is actually being built.
///
/// It used to be a spinner over "Wrapping up your session…", which is the one
/// thing the learner already knows. Meanwhile the app is doing the most
/// valuable minute of work it does all day — reading the transcript back,
/// pulling out the words they used, verifying every correction against their
/// own sentences, checking whether anything they'd been studying came out
/// unprompted, minting the cards. None of that was visible, so the wait read
/// as dead time instead of as the thing they get for having talked.
///
/// **Every line is a real step with a real number.** The counts come from
/// `SessionSummarizer.Progress`, reported at the point each piece of work
/// finishes, and they are the same numbers the summary sheet then shows. A
/// step is ticked only once it is genuinely done — nothing here is a
/// simulated progress bar, which is why the first row (the one long model
/// call) sits spinning for as long as it really takes and shows facts about
/// the talk that are already known instead of a fake percentage.
struct SummaryProgressView: View {
    let progress: SessionSummarizer.Progress
    /// True facts about the talk just finished ("12 turns · 4 min"), shown
    /// while the analysis runs so the longest step still says something.
    let facts: String?

    private struct Step: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let icon: String
        /// nil = not finished yet. A finished step with 0 shows its tick
        /// alone: "checked, nothing there" is a result, "0" reads as a score.
        let count: Int?
    }

    private var steps: [Step] {
        [
            Step(id: 0, title: "Reading the conversation back", icon: "text.bubble",
                 count: progress.words == nil ? nil : 0),
            Step(id: 1, title: "Words and expressions you used", icon: "character.book.closed",
                 count: progress.words),
            Step(id: 2, title: "Corrections worth keeping", icon: "checkmark.bubble",
                 count: progress.corrections),
            Step(id: 3, title: "Things you'd been studying", icon: "arrow.uturn.up",
                 count: progress.carryovers),
            Step(id: 4, title: "Review cards", icon: "rectangle.stack", count: progress.cards),
        ]
    }

    private var doneCount: Int { steps.filter { $0.count != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Building your review material")
                    .font(.headline)
                ProgressView(value: Double(doneCount), total: Double(steps.count))
                    .tint(.accentColor)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps) { step in
                    row(step, isCurrent: step.id == doneCount)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }

    private func row(_ step: Step, isCurrent: Bool) -> some View {
        let done = step.count != nil
        return HStack(spacing: 10) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else if isCurrent {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline)
                    .foregroundStyle(done || isCurrent ? .primary : .secondary)
                // The one long step gets the talk's own numbers under it —
                // known before the call returns, so it costs nothing and is
                // never a guess.
                if isCurrent, step.id == 0, let facts {
                    Text(facts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let count = step.count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .transition(.opacity)
            }
        }
        .opacity(done || isCurrent ? 1 : 0.5)
    }
}
