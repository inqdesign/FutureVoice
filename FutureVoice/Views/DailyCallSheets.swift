import SwiftUI

/// "When should I call back?" — shown after declining from the ALARM.
///
/// It exists because of a platform limit, not a design preference:
/// `AlarmPresentation.Alert` gives an app exactly one button it can label, and
/// that one is spent on Answer. So the choice the notification shows inline
/// has to happen here instead, a beat later, in the app.
///
/// Everything about it is built to be over in one tap. Declining is supposed
/// to cost nothing, and this already costs a context switch — it must not also
/// cost a decision the learner has to think about.
struct DailyCallCallbackSheet: View {
    let plan: DailyCallPlan
    /// Called once the choice is made (or the sheet is dismissed) so the
    /// presenter can clear its binding.
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DailyCallScheduler.callbackOptions, id: \.self) { minutes in
                        Button {
                            choose(minutes)
                        } label: {
                            Label(DailyCallScheduler.callbackLabel(minutes),
                                  systemImage: "phone.arrow.up.right")
                        }
                    }
                } header: {
                    Text("Call back")
                } footer: {
                    Text(explain("Nothing is lost by putting this off — no streak breaks and today still counts."))
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await DailyCallScheduler.declineForToday()
                            finish()
                        }
                    } label: {
                        Label("Not today", systemImage: "phone.down")
                    }
                } footer: {
                    Text(explain("The message stays on your Talk tab either way — you can listen whenever."))
                }
            }
            .navigationTitle("When should I call?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissWithDefault() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func choose(_ minutes: Int) {
        Task {
            await DailyCallScheduler.decline(after: minutes)
            finish()
        }
    }

    /// Closed without picking. They DID decline the call, so the caller still
    /// rings back — just on the interval from Me rather than one chosen here.
    /// Cancelling the day on a swipe-down would be the app deciding something
    /// the learner didn't.
    private func dismissWithDefault() {
        Task {
            await DailyCallScheduler.decline()
            finish()
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

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
                    Text("I'll help you keep it up")
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

    private func skip() {
        Analytics.capture("daily_call_onboarding", ["enabled": false])
        DailyCallStore.shared.isEnabled = false
        onboarded = true
    }
}
