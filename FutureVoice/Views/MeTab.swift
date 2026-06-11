import SwiftUI

/// Tab home for user-facing metadata — profile, voice clone, history, and
/// practice trends. The "Reflect" surface of the four-tab structure.
struct MeTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var dashboard: PracticeStats.Snapshot = PracticeStats.Snapshot(
        streakDays: 0, totalSessions: 0, lastScorecard: nil,
        lastSessionEndedAt: nil, lastSevenDayScores: Array(repeating: 0, count: 7),
        shadowableLineCount: 0
    )
    @State private var showingPersonaEdit = false
    @State private var confirmingVoiceReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    streakRow
                    if !dashboard.lastSevenDayScores.allSatisfy({ $0 == 0 }) {
                        weeklyChart
                    }
                    if let card = dashboard.lastScorecard {
                        lastSessionCard(card)
                    }
                    shadowTrendRow
                } header: {
                    Text("This week")
                }

                Section("Profile") {
                    Button {
                        showingPersonaEdit = true
                    } label: {
                        row(icon: "person.text.rectangle",
                            title: appState.persona?.displayName.isEmpty == false
                                ? appState.persona!.displayName
                                : "Edit profile",
                            subtitle: "Persona used in every conversation")
                    }
                }

                Section {
                    Picker(selection: $appState.proficiency) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(level.rawValue.uppercased()).tag(level)
                        }
                    } label: {
                        row(icon: "chart.bar",
                            title: "Level",
                            subtitle: "Calibrates conversations and feedback")
                    }
                } header: {
                    Text("Learning")
                } footer: {
                    Text("CEFR scale — A1 beginner to C2 near-native. The avatar stays at your level and grades against it.")
                }

                Section("Voice") {
                    Button(role: .destructive) {
                        confirmingVoiceReset = true
                    } label: {
                        row(icon: "mic.badge.plus",
                            title: "Re-record voice",
                            subtitle: "Replace your current clone with a new one")
                    }
                }

                Section("History") {
                    NavigationLink {
                        HistoryView()
                            .navigationTitle("History")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        row(icon: "clock.arrow.circlepath",
                            title: "Past sessions",
                            subtitle: "\(dashboard.totalSessions) total")
                    }
                }
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPersonaEdit) {
                PersonaOnboardingView(initialPersona: appState.persona)
                    .environmentObject(appState)
            }
            .alert("Re-record your voice?", isPresented: $confirmingVoiceReset) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    appState.resetVoiceClone()   // RootView swaps to onboarding
                }
            } message: {
                Text("Your current clone will be deleted on ElevenLabs after the new one is created.")
            }
            .onAppear { dashboard = PracticeStats.snapshot() }
        }
    }

    // MARK: - Pieces

    private var streakRow: some View {
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

    /// Deterministic pronunciation read from shadow-practice scores — the
    /// one axis the LLM scorecard can't grade. Hidden until the user has
    /// shadowed at least once this week.
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

    @ViewBuilder
    private func lastSessionCard(_ card: SessionScorecard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.topLine)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
