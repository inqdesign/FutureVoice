import SwiftUI

/// The language-development hub — every growth signal in one place instead
/// of scattered across Talk home and the old Me tab:
///   streak + weekly score chart, the weekly trend report, the deterministic
///   pronunciation (shadow) trend, the recurring-mistake patterns the
///   learner profile is tracking, and the full session history.
struct ProgressTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var dashboard: PracticeStats.Snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )

    var body: some View {
        NavigationStack {
            List {
                thisWeekSection
                reportSection
                patternsSection
                historySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { dashboard = PracticeStats.snapshot() }
        }
    }

    // MARK: - This week

    private var thisWeekSection: some View {
        Section("This week") {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(dashboard.streakDays > 0 ? .orange : .secondary)
                Text(streakText)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(dashboard.totalSessions == 1 ? "1 session" : "\(dashboard.totalSessions) sessions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !dashboard.lastSevenDayScores.allSatisfy({ $0 == 0 }) {
                weeklyChart
            }
            shadowTrendRow
            if let card = dashboard.lastScorecard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.topLine)
                        .font(.callout)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var streakText: String {
        switch dashboard.streakDays {
        case 0:  return "No streak yet"
        case 1:  return "1-day streak"
        default: return "\(dashboard.streakDays)-day streak"
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(dashboard.lastSevenDayScores.enumerated()), id: \.offset) { _, score in
                    Capsule()
                        .fill(color(for: score))
                        .frame(width: 14, height: max(4, CGFloat(score) * 0.5))
                        .opacity(score == 0 ? 0.25 : 1.0)
                }
                Spacer()
            }
            .frame(height: 50, alignment: .bottom)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var shadowTrendRow: some View {
        let trend = PracticeStats.shadowTrend(attempts: appState.shadowAttempts)
        if trend.attemptsThisWeek > 0 {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pronunciation (shadow)")
                        .font(.subheadline.weight(.medium))
                    Text("\(trend.attemptsThisWeek) attempt\(trend.attemptsThisWeek == 1 ? "" : "s") this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(trend.avgThisWeek)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(color(for: Double(trend.avgThisWeek)))
                        .monospacedDigit()
                    if let delta = trend.delta, delta != 0 {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delta > 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Weekly report

    private var reportSection: some View {
        Section {
            WeeklyReportView()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Patterns (the learner profile, made visible)

    @ViewBuilder
    private var patternsSection: some View {
        let patterns = appState.learnerProfile.recurringMistakes.prefix(5)
        if !patterns.isEmpty {
            Section {
                ForEach(Array(patterns)) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(p.mistake)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            if p.frequency > 1 {
                                Text("×\(p.frequency)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text("\u{2192} \(p.correction)")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Patterns you're working on")
            } footer: {
                Text("Carried across sessions — the avatar stays aware of these and your drills target them.")
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            NavigationLink {
                HistoryView()
                    .navigationTitle("History")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Past sessions").font(.body)
                        Text("\(dashboard.totalSessions) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
