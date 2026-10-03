import SwiftUI

/// "Your week" from the Practice row (2026-10-03): the week still running,
/// whose deck isn't ready until it closes, and every closed week's deck
/// behind it, newest first.
///
/// A deck slides up by itself once, when its week closes (`RootTabView`);
/// after that this list is the only way back to it. A closed week is never
/// rebuilt here — what was frozen is what is shown.
struct WeekRecapArchiveView: View {
    /// What the learner chose on a deck's last card; the presenter acts on
    /// it once this sheet is gone.
    let onAction: (WeekRecapSheet.Action) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var thisWeek: WeekInProgress?
    @State private var weeks: [WeekRecap] = []
    @State private var open: WeekRecap?
    @State private var action: WeekRecapSheet.Action?

    var body: some View {
        NavigationStack {
            List {
                if let week = thisWeek {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.readyLine(week))
                                    .font(.subheadline.weight(.medium))
                                Text("\(week.daysActive) days · \(week.talkMinutes) min of talk")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    } header: {
                        Text("In progress")
                    }
                }
                Section {
                    if weeks.isEmpty {
                        Text("Your first week's cards arrive when it closes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(weeks) { recap in
                        Button { open = recap } label: { row(recap) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Past weeks")
                }
            }
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $open, onDismiss: {
            reload()
            guard let chosen = action else { return }
            action = nil
            onAction(chosen)
            dismiss()
        }) { recap in
            WeekRecapSheet(recap: recap, action: $action)
                .environmentObject(appState)
        }
        .task { reload() }
    }

    private func row(_ recap: WeekRecap) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.range(recap))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(recap.daysActive) days · \(recap.talkMinutes) min of talk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // The closed week whose deck hasn't been opened yet.
            if !WeekRecapStore.shared.wasShown(recap) {
                Text("New")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func reload() {
        _ = WeekRecapStore.shared.lastWeek()
        thisWeek = WeekRecapBuilder.thisWeek()
        weeks = WeekRecapStore.shared.archive()
    }

    // MARK: - Text

    private static var chromeLocale: Locale { Locale(identifier: UILanguage.chromeLanguage) }

    /// "Sat, Oct 10" — a DATE, not just a weekday: on the opening day
    /// itself "Sat" can't say whether it means today or a week from now.
    private static func readyDate(_ week: WeekInProgress) -> String {
        week.readyAt.formatted(Date.FormatStyle(locale: chromeLocale)
            .weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Ready Sat, Oct 10" — when this week's deck arrives.
    static func readyLine(_ week: WeekInProgress) -> String {
        explain("Ready \(readyDate(week))")
    }

    /// The Practice row's caption.
    static func progressLine(_ week: WeekInProgress) -> String {
        explain("This week in progress · ready \(readyDate(week))")
    }

    /// "Sep 26 – Oct 2": seven days, so it doesn't share a day with the next
    /// week's label (the opening day belongs to the week it starts).
    static func range(_ recap: WeekRecap) -> String {
        let style = Date.FormatStyle(locale: chromeLocale).month(.abbreviated).day()
        let last = recap.end.addingTimeInterval(-86_400)
        return "\(recap.start.formatted(style)) – \(last.formatted(style))"
    }
}
