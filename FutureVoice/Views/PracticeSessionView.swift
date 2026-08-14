import SwiftUI

/// The guided shadow session (optionally preceded by the card deck).
///
///   [cards (the due SRS deck) →] shadow lines (today's picks) → done summary
///
/// The Today card launches cards and shadowing as SEPARATE actions — with a
/// 30-card backlog, forcing the deck before shadowing would mean never
/// shadowing. `includeCards: false` starts straight at the first line.
struct PracticeSessionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Today's shadow lines (the Today card advertises up to 2).
    let shadowPicks: [PracticeStats.ShadowPick]
    let includeCards: Bool

    /// 0 = card deck · 1…shadowPicks.count = shadow line n · beyond = done.
    @State private var stage: Int

    init(shadowPicks: [PracticeStats.ShadowPick], includeCards: Bool = true) {
        self.shadowPicks = shadowPicks
        self.includeCards = includeCards
        _stage = State(initialValue: includeCards ? 0 : 1)
    }
    @State private var activeShadow: PracticeStats.ShadowPick?
    /// SHADOW reps already logged today when the session began — the done
    /// screen reports THIS session's work, not the whole day's. Shadow reps
    /// only: the old version compared the day's TOTAL, so a word judged in
    /// another sheet could credit a session where nothing was said out loud.
    @State private var shadowRepsAtStart = -1
    /// Lines the learner tapped Skip on. Skipping used to be indistinguishable
    /// from finishing — both just advanced the stage — so skipping every line
    /// still ended on a green "That's your session".
    @State private var skipped = 0

    private var isDone: Bool { stage > shadowPicks.count }

    var body: some View {
        Group {
            if stage == 0 {
                DrillView(onDeckCompleted: {
                    withAnimation(.easeInOut(duration: 0.25)) { stage = 1 }
                })
            } else if !isDone {
                shadowStage(shadowPicks[stage - 1])
            } else {
                doneStage
            }
        }
        .navigationTitle(stageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if shadowRepsAtStart < 0 {
                shadowRepsAtStart = PracticeLog.shared.day(Date())?.shadowReps ?? 0
            }
            // Stale entry (cards got cleared elsewhere) → skip to shadowing.
            if stage == 0, DrillStore.shared.due().isEmpty {
                stage = 1
            }
        }
        .sheet(item: $activeShadow, onDismiss: {
            withAnimation(.easeInOut(duration: 0.25)) { stage += 1 }
        }) { pick in
            ShadowDrillView(turn: pick.turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
    }

    private var stageTitle: String {
        if stage == 0 { return "Review" }
        if isDone { return saidSomething ? "Session done" : "Nothing said" }
        return shadowPicks.count > 1 ? "Shadow \(stage) of \(shadowPicks.count)" : "Shadow"
    }

    // MARK: - Shadow stage

    private func shadowStage(_ pick: PracticeStats.ShadowPick) -> some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                // "Cards done" only makes sense when a deck actually preceded
                // this — entered straight from the Shadowing challenge there
                // were no cards.
                Label(includeCards ? "Cards done — now say it out loud"
                                   : "Say it out loud",
                      systemImage: includeCards ? "checkmark.circle.fill" : "waveform.badge.mic")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(includeCards ? .green : .secondary)
                Text("\u{201C}\(pick.turn.transcript)\u{201D}")
                    .font(DrillView.targetFont(for: pick.turn.transcript))
                    .fixedSize(horizontal: false, vertical: true)
                Text(pick.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 16)

            Button {
                activeShadow = pick
            } label: {
                Label("Shadow this line", systemImage: "waveform.badge.mic")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)

            Button("Skip") {
                skipped += 1
                withAnimation(.easeInOut(duration: 0.25)) { stage += 1 }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Done stage

    /// Did the learner actually say anything out loud in THIS session? A
    /// recorded shadow attempt is the only evidence that counts — opening the
    /// drill and backing out isn't practice, and neither is Skip.
    private var saidSomething: Bool { sessionReps > 0 }

    private var sessionReps: Int {
        max(0, (PracticeLog.shared.day(Date())?.shadowReps ?? 0) - max(0, shadowRepsAtStart))
    }

    private var doneStage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: saidSomething ? "checkmark.circle.fill" : "waveform.badge.mic")
                .font(.system(size: 56))
                .foregroundStyle(saidSomething ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            Text(saidSomething ? "That's your session" : "Nothing said out loud")
                .font(.title2.weight(.semibold))
            Text(sessionSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var sessionSummaryText: String {
        if sessionReps > 0 {
            return "\(sessionReps) rep\(sessionReps == 1 ? "" : "s") this session — it all counts toward your level."
        }
        // Never "come back when the next cards are due" here: launched from
        // the Shadowing challenge there are no cards, and the learner skipped
        // — saying so plainly beats congratulating them for nothing.
        return skipped > 0
            ? explain("You skipped every line. They'll be waiting whenever you want to say them.")
            : explain("Nothing recorded this time — shadowing only counts once you say the line.")
    }
}
