import SwiftUI

/// The last step of onboarding: introducing the daily call and letting them
/// pick its hour.
///
/// It comes AFTER the voice clone because the call is the clone's first real
/// job — by this screen the learner has already heard themselves speak
/// fluently, so "they'll phone you tomorrow" lands as a promise rather than a
/// permissions request. Asking before the clone existed would make it just
/// another notification opt-in.
///
/// Also shown once to learners who onboarded before this existed, which is how
/// they find out the feature is there at all.
struct DailyCallOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    /// Set on either exit — turning the call on, or skipping — so the screen
    /// never appears twice.
    @AppStorage("futurevoice.dailyCall.onboarded") private var onboarded = false

    @State private var time = Calendar.current.date(
        bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var working = false
    /// They said yes and iOS said no. The screen has to say so, or they leave
    /// believing a call is coming that never will.
    @State private var permissionDenied = false

    /// The learner as this screen calls them — Korean takes its vocative
    /// particle here (see `LearnerAddress`). nil when they never gave a name.
    private var name: String? {
        LearnerAddress.vocative(appState.persona?.displayName)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                Image(systemName: "phone.arrow.down.left.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                // The title is the FUTURE SELF talking, in the first person —
                // not a feature name. What this screen has to land is that
                // showing up daily is the hard part, that doing it alone is
                // why people stop, and that somebody is offering to carry it.
                // "A call every day" described the mechanism and sold nothing.
                VStack(spacing: 10) {
                    // By NAME when there is one. Everything from here on is
                    // the future self speaking, and being called by name is
                    // what separates that from an app announcing a feature.
                    Text(name.map { explain("\($0), I'll help you keep it up") }
                         ?? explain("I'll help you keep it up"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(explain("Speaking once is easy. Every day is the hard part — so I'll call you. One question a day, answered out loud, and that day is done."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(explain("It rings even on silent, and I remember how the last call went."))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    // Said on this screen because this is where the prompt
                    // comes from, on EITHER exit — and because a permission
                    // asked for one feature, granted, and then used for
                    // another is a thing learners are right to resent.
                    Text(explain("Even if you'd rather I didn't call, notifications are how I reach you — news, and anything about your plan."))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                DatePicker("Calls at", selection: $time,
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxHeight: 150)

                if permissionDenied {
                    Text(explain("iOS is blocking the call. Turn on notifications for nawana in Settings, then switch it on again in Me."))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    enable()
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Call me every day")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(working)

                Button("Not now") { skip() }
                    .disabled(working)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func enable() {
        working = true
        permissionDenied = false
        Task {
            let granted = await DailyCallScheduler.requestPermission()
            guard granted else {
                working = false
                permissionDenied = true
                return
            }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            DailyCallStore.shared.hour = parts.hour ?? 8
            DailyCallStore.shared.minute = parts.minute ?? 0
            DailyCallStore.shared.isEnabled = true
            Analytics.capture("daily_call_onboarding", [
                "enabled": true, "hour": DailyCallStore.shared.hour
            ])
            // The first call has to be WRITTEN before it can ring, and this is
            // the last foreground moment onboarding guarantees us.
            appState.refreshDailyCall(force: true)
            onboarded = true
        }
    }

    /// Declining the CALL is not declining to be reached.
    ///
    /// This screen is the only place in onboarding that asks about
    /// notifications, and until 2026-09-26 the skip path asked nothing — so
    /// everyone who tapped Not now (and anyone who never enabled a review
    /// reminder either) could never be sent anything at all: not a word about
    /// their plan, not an announcement, nothing. An app that has never asked
    /// doesn't even appear in Settings → Notifications, so that silence was
    /// permanent and invisible from both ends. The prompt is asked here on
    /// BOTH exits, which is also why the copy above says what notifications
    /// are for beyond the call.
    private func skip() {
        Analytics.capture("daily_call_onboarding", ["enabled": false])
        DailyCallStore.shared.isEnabled = false
        Task {
            await PushTokens.ensurePermission()
            onboarded = true
        }
    }
}
