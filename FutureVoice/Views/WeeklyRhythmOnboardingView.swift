import SwiftUI

/// Onboarding's "once a week" step (2026-10-03): introduces the week's two
/// things — the week looked back on (`WeekRecap`) and the test made from it
/// (`WeeklyTest`) — and asks WHEN, because both open at the same moment
/// (`WeeklyTestSettings`' weekday + time). Placed right BEFORE the daily
/// call: the week's rhythm first, then the day's.
///
/// It asks no permission. The reminder toggle only records the wish; the
/// daily-call step that follows asks for notifications on both of its exits
/// and then settles this reminder (`WeeklyTestReminder.settleAfterPermission`),
/// so the learner meets one permission sheet, not two in a row.
///
/// Shown to new installs only (RootView gates it on the daily call not yet
/// onboarded): an existing learner already has a test day — Saturday by
/// default, editable in the goals sheet — and a screen asking for it again
/// would be the app forgetting.
struct WeeklyRhythmOnboardingView: View {
    @AppStorage("futurevoice.weeklyRhythm.onboarded") private var onboarded = false
    @ObservedObject private var settings = WeeklyTestSettings.shared

    @State private var weekday: Int = WeeklyTestSettings.shared.weekday
    @State private var time: Date = WeeklyTestSettings.shared.timeOfDay
    @State private var remind = true

    /// The week in the app language, starting where the learner's calendar
    /// starts it (Monday in most places, Sunday in the US and Korea).
    private var days: [(id: Int, label: String)] {
        var cal = Calendar.current
        cal.locale = Locale(identifier: UILanguage.chromeLanguage)
        let symbols = cal.shortStandaloneWeekdaySymbols   // Sunday first
        return (0..<7).map { offset in
            let day = (cal.firstWeekday - 1 + offset) % 7 + 1
            return (day, symbols[day - 1])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(explain("Once a week, let's look back"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(explain("On the day you pick, I'll put your week together: what you said, the words you picked up, how far you've come. Then a short test, made only from your own talks."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(explain("Pick a time you usually have ten quiet minutes."))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                HStack(spacing: 6) {
                    ForEach(days, id: \.id) { day in
                        dayButton(day.id, label: day.label)
                    }
                }

                DatePicker("Opens at", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 130)
                    .clipped()

                Toggle(isOn: $remind) {
                    Label("Tell me when it's ready", systemImage: "bell")
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            Button {
                save()
            } label: {
                Text("Set my week")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func dayButton(_ id: Int, label: String) -> some View {
        let selected = weekday == id
        Button {
            weekday = id
        } label: {
            // Plain capsule rather than `.bordered`: that style's own side
            // padding cut "Mon" to "M…" with seven across a phone.
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.15)
                                                    : Color(.secondarySystemBackground)))
                .overlay {
                    if selected { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        settings.weekday = weekday
        settings.timeOfDay = time
        // A wish until the next screen asks for notifications; settled there.
        settings.reminderOn = remind
        Analytics.capture("weekly_rhythm_onboarding", [
            "weekday": weekday, "hour": settings.hour, "remind": remind
        ])
        onboarded = true
    }
}
