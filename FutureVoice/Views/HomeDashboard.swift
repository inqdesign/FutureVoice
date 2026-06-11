import SwiftUI

/// Home-state header shown above an empty conversation feed.
///
/// Two responsibilities:
///   1. Surface practice progress (streak, last session, week chart).
///   2. Act as the **primary entry surface** for the app's three modes —
///      Topic / Drill / Shadow each get a tappable action card with current
///      counts. Promoting these into the body keeps the top toolbar minimal
///      (just Profile + ⋯ menu) instead of stuffed with mode icons.
struct HomeDashboard: View {
    let snapshot: PracticeStats.Snapshot
    let currentTopic: String
    let onPickTopic: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            streakRow
            topicCard
            // Replaced the per-session "you scored X" lines with a
            // multi-session weekly report. Single-session scoring was too
            // noisy to be honest; the engine now waits for enough data.
            WeeklyReportView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var topicCard: some View {
        Button(action: onPickTopic) {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(currentTopic.isEmpty ? Color.accentColor : .primary)
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTopic.isEmpty ? "Pick a scenario to start" : currentTopic)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(currentTopic.isEmpty
                         ? "Persona-grounded suggestions"
                         : "Tap to change")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak row

    private var streakRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.subheadline)
                .foregroundStyle(snapshot.streakDays > 0 ? .orange : .secondary)
            Text(streakText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Text(totalSessionsText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var streakText: String {
        switch snapshot.streakDays {
        case 0:  return "Start a streak today"
        case 1:  return "1-day streak"
        default: return "\(snapshot.streakDays)-day streak"
        }
    }

    private var totalSessionsText: String {
        snapshot.totalSessions == 1
            ? "1 session"
            : "\(snapshot.totalSessions) sessions"
    }

    // MARK: - Weekly chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This week")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(snapshot.lastSevenDayScores.enumerated()), id: \.offset) { _, score in
                    Capsule()
                        .fill(color(for: score))
                        .frame(width: 14, height: max(4, CGFloat(score) * 0.5))
                        .opacity(score == 0 ? 0.25 : 1.0)
                }
                Spacer()
            }
            .frame(height: 50, alignment: .bottom)
        }
    }

    // MARK: - Last session

    @ViewBuilder
    private func lastSessionLine(_ card: SessionScorecard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.topLine)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }

    private func color(for score: Double) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        case 1..<50: return .orange
        default: return .secondary
        }
    }
}
