import SwiftUI

/// "Say it again" from the timetable: which talk? A scheduled say-it-again
/// block names no talk — it recurs every week, and the talk worth redoing is
/// whichever the learner just had — so the choice is made when it is time,
/// here. The most recent talk is picked already; one tap starts it.
struct SayItAgainPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var talks: [Session] = []
    @State private var picked: UUID?
    @State private var running: Session?

    /// How far back the list reaches, and how long it may get.
    static let lookbackDays = 14
    static let limit = 12

    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    var body: some View {
        NavigationStack {
            List {
                if talks.isEmpty {
                    Text("No talks to say again yet. Have a talk first.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(talks) { talk in
                            Button { picked = talk.id } label: { row(talk) }
                                .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("The whole talk again, with your lines the way they should have gone.")
                    }
                }
            }
            .navigationTitle(explain("Say it again"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        running = talks.first { $0.id == picked }
                        Analytics.capture("plan_say_again_start", [
                            "index": talks.firstIndex { $0.id == picked } ?? -1,
                        ])
                    }
                    .disabled(picked == nil)
                }
            }
            .onAppear(perform: load)
            .fullScreenCover(item: $running, onDismiss: { dismiss() }) { session in
                SayItAgainView(source: .talk(session))
                    .environmentObject(appState)
            }
        }
    }

    private func row(_ talk: Session) -> some View {
        let lines = talk.turns.filter { $0.role == .user }.count
        let when = talk.endedAt ?? talk.startedAt
        return HStack(spacing: 12) {
            Image(systemName: picked == talk.id ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(picked == talk.id ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(talk.displayTitle)
                    .font(.body)
                    .lineLimit(2)
                Text(explain("\(when.formatted(Date.FormatStyle(locale: uiLocale).month(.abbreviated).day().weekday(.abbreviated).hour().minute())) · \(lines) lines"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func load() {
        let since = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? .distantPast
        talks = SessionStore.shared.load()
            .filter { s in
                guard let end = s.endedAt, end >= since else { return false }
                // A talk the learner never spoke in has nothing to say again.
                return s.turns.contains { $0.role == .user }
            }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .prefix(Self.limit)
            .map { $0 }
        if picked == nil { picked = talks.first?.id }
    }
}
