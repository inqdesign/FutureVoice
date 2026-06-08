import SwiftUI

/// Five-axis "session nutrition" card. Rendered in the post-session summary
/// and the history detail view. iOS-native components only — no chart libs.
struct ScorecardView: View {
    let scorecard: SessionScorecard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scorecard.topLine)
                .font(.callout)
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                axisRow(label: "Vocabulary",     axis: scorecard.vocabulary,     icon: "textformat.abc")
                axisRow(label: "Grammar",        axis: scorecard.grammar,        icon: "checkmark.seal")
                axisRow(label: "Expressiveness", axis: scorecard.expressiveness, icon: "quote.bubble")
                axisRow(label: "Fluency & pace", axis: scorecard.fluency,        icon: "metronome")
                pronunciationRow
            }
        }
    }

    @ViewBuilder
    private func axisRow(label: String, axis: AxisScore, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .font(.subheadline)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(axis.score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: axis.score))
                    .monospacedDigit()
            }
            ProgressView(value: Double(axis.score), total: 100)
                .tint(color(for: axis.score))
            if !axis.note.isEmpty {
                Text(axis.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pronunciationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(width: 18)
                Text("Pronunciation")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let axis = scorecard.pronunciation {
                    Text("\(axis.score)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color(for: axis.score))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(scorecard.pronunciation?.note ?? "Practice shadow drills to track this.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }
}
