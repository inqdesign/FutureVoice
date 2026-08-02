import SwiftUI

/// Surfaces the most recent `WeeklyReport`, or a "still gathering data"
/// empty state when not enough sessions exist yet.
///
/// Embedded as a section in PracticeTab. Kept as its own view so it can
/// also be pushed standalone (e.g. from a future Me-tab "your progress"
/// row) without rewiring.
struct WeeklyReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let sessions = SessionStore.shared.load().filter { $0.endedAt != nil }
        let report = appState.weeklyReports.first
        let state = WeeklyReportEngine.unlockState(
            endedSessions: sessions,
            lastReport: report
        )

        // One card per topic, not one wall — the summary reads first, and
        // each list is scannable on its own.
        VStack(alignment: .leading, spacing: 16) {
            card {
                header
                pronunciationLine
                if let report {
                    Text(report.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(report.sessionCount) sessions · \(dateRange(report))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    emptyState(state)
                }
            }
            if let report {
                reportBody(report)
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Your \(LanguageCatalog.englishName(appState.targetLanguage))")
                .font(.headline)
            Spacer()
            if appState.weeklyReportGenerating {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// Deterministic pronunciation trend from shadow scores — independent of
    /// the LLM report, so it shows even while the report is still locked.
    @ViewBuilder
    private var pronunciationLine: some View {
        let trend = PracticeStats.shadowTrend(attempts: appState.shadowAttempts)
        if trend.attemptsThisWeek > 0 {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Shadow avg \(trend.avgThisWeek) this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let delta = trend.delta, delta != 0 {
                    Text(delta > 0 ? "+\(delta) vs last week" : "\(delta) vs last week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                }
                Spacer()
            }
        }
    }

    // MARK: - Report content

    @ViewBuilder
    private func reportBody(_ r: WeeklyReport) -> some View {
        if !r.newExpressions.isEmpty {
            card {
                section(title: "New expressions you used") {
                    ForEach(r.newExpressions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.phrase).font(.body).fontWeight(.semibold)
                            Text("\u{201C}\(item.sampleSentence)\u{201D}")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        if !r.repeatedMistakes.isEmpty {
            card {
                section(title: "Patterns to work on") {
                    ForEach(r.repeatedMistakes) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.userSaid)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                if item.count > 1 {
                                    Text("×\(item.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text("\u{2192} \(item.fluentAlternative)")
                                .fontWeight(.medium)
                            Text(item.note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        if !r.suggestedExpressions.isEmpty {
            card {
                section(title: "Try adding these") {
                    ForEach(r.suggestedExpressions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.phrase).font(.body).fontWeight(.semibold)
                            Text(item.whenToUse)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("e.g. \u{201C}\(item.example)\u{201D}")
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(_ state: WeeklyReportEngine.UnlockState) -> some View {
        switch state {
        case .lockedFirst(let accumulated, let required):
            let doneMin = Int(accumulated / 60)
            let totalMin = Int(required / 60)
            VStack(alignment: .leading, spacing: 12) {
                Text(explain("Your first report unlocks after \(totalMin) minutes of practice."))
                    .font(.subheadline)
                ProgressView(value: accumulated, total: required)
                Text(explain("\(doneMin) / \(totalMin) min so far."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(explain("We measure your time talking, not the number of sessions — a one-minute exchange tells us nothing, ten one-minute exchanges tell us a lot."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .lockedNext(let days, let secondsRemaining):
            let minsRem = Int((secondsRemaining + 59) / 60) // round up
            VStack(alignment: .leading, spacing: 8) {
                Text(explain("Next report in \(max(days, 0))d · \(max(minsRem, 0)) more minutes of practice."))
                    .font(.subheadline)
                Text(explain("Reports compare week-over-week, so we wait until there's enough new material."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            HStack {
                ProgressView().controlSize(.small)
                Text("Analyzing your week…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dateRange(_ r: WeeklyReport) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: r.periodStart)) – \(fmt.string(from: r.periodEnd))"
    }
}
