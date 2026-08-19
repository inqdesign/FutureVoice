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
        /// Finished — either the model closed this section, or the local pass
        /// produced its number.
        let done: Bool
        /// nil until the verified number exists. A finished step with 0 shows
        /// its tick alone: "checked, nothing there" is a result, "0" reads as
        /// a score.
        let count: Int?
    }

    /// In the order the work actually happens: the model writes its sections
    /// top to bottom, then the local pass fills in the verified counts, then
    /// the two steps only the app can do.
    private var steps: [Step] {
        [
            Step(id: 0, title: "Reading the conversation back",
                 done: progress.readBack, count: nil),
            Step(id: 1, title: "Lines worth saying differently",
                 done: progress.wroteCorrections, count: progress.phrases),
            Step(id: 2, title: "Review cards",
                 done: progress.wroteDrills, count: progress.cards),
            Step(id: 3, title: "Words and expressions you used",
                 done: progress.wroteExpressions, count: progress.words),
            Step(id: 4, title: "Corrections worth keeping",
                 done: progress.wroteGrammar, count: progress.corrections),
            Step(id: 5, title: "Things you'd been studying",
                 done: progress.carryovers != nil, count: progress.carryovers),
        ]
    }

    private var doneCount: Int { steps.filter(\.done).count }

    /// How many steps are on screen as done. Trails `doneCount` by design:
    /// the model's sections can land in one burst (a fast write, or a deploy
    /// with no SSE at all), and six rows ticking in a single frame is the
    /// "nothing, then everything" the board exists to fix. Nothing is ever
    /// shown before it is genuinely finished — this only spaces out what is.
    @State private var shown = 0

    /// Time to walk one step onto the screen. Callers that hold the board
    /// open at the end (`ConversationView.endSession`) size their beat from
    /// this, so the reveal can never be cut off by the summary sheet.
    static let revealInterval: Double = 0.18
    static let revealTail: Double = revealInterval * 6 + 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Building your review material")
                    .font(.headline)
                ProgressView(value: Double(shown), total: Double(steps.count))
                    .tint(.accentColor)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps) { step in
                    row(step, isCurrent: step.id == shown)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .animation(.easeInOut(duration: 0.25), value: shown)
        .animation(.easeInOut(duration: 0.25), value: progress)
        .task(id: doneCount) {
            while shown < doneCount, !Task.isCancelled {
                shown += 1
                try? await Task.sleep(nanoseconds: UInt64(Self.revealInterval * 1_000_000_000))
            }
        }
    }

    private func row(_ step: Step, isCurrent: Bool) -> some View {
        let done = step.id < shown
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
