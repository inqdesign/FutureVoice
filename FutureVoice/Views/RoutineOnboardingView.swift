import SwiftUI

/// Where the routine builder lands when it is done: the Talk header's
/// Activity chip reports its frame here, and the builder shrinks into it.
/// The chip then shows a one-time hint that the routine lives behind it.
@MainActor
final class RoutineHandoff: ObservableObject {
    static let shared = RoutineHandoff()
    /// The Activity chip, in global coordinates. Zero until it has drawn.
    @Published var chipFrame: CGRect = .zero
    /// The hint under the chip, right after the builder went into it.
    @Published var showHint = false
    /// Bumped when the builder lands, so the chip can bounce.
    @Published var landed = 0
}

/// Onboarding's routine (2026-10-18, founder: "making the routine is the
/// core"). It replaced three places that each set a piece of it — setup's
/// daily goal and purpose-made week, then a weekly-test screen and a
/// daily-call screen after the clone — with ONE: the My routine grid itself,
/// and a sheet over it that asks two things. How long the daily call is,
/// when and on which days; then how much study time there is, which goes in
/// as review at 21:00 on the same days. Each answer is written to the plan
/// on Save, so the learner watches it land on the grid. Shown over the Talk
/// tab once; Done shrinks it into the Activity chip, which is where it
/// lives from then on.
struct RoutineOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var handoff = RoutineHandoff.shared
    var onFinished: () -> Void

    private enum Step { case intro, call, study, done }

    @State private var step: Step = .intro
    @State private var sheetUp = false
    @State private var spotlight: WeeklyPlanEditor.Spotlight?
    @State private var working = false
    /// Neither alarms nor notifications were allowed: the routine stands,
    /// but nothing can ring.
    @State private var callBlocked = false

    @State private var callMinutes = 10
    @State private var callTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var days: Set<Int> = Set(1...7)
    @State private var studyMinutes = 30

    @State private var ownFrame: CGRect = .zero
    @State private var shrink: CGFloat = 0
    @State private var fade = false

    static let callChoices = [5, 10, 15, 20]
    static let studyChoices = [15, 30, 60]
    /// "Around 9 in the evening" — the review slot study time goes into.
    static let reviewTime = DailyCallStore.CallTime(hour: 21, minute: 0)

    private var cal: Calendar { Calendar.current }
    private var uiLocale: Locale { Locale(identifier: LanguageCatalog.currentNative) }

    var body: some View {
        WeeklyPlanEditor(onboarding: true, spotlight: spotlight)
            .clipShape(RoundedRectangle(cornerRadius: 44 * min(1, shrink * 3), style: .continuous))
            .scaleEffect(x: scale.width, y: scale.height)
            .offset(x: offset.width, y: offset.height)
            .opacity(fade ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ownFrame = $0 }
            .allowsHitTesting(shrink == 0)
            .onAppear {
                // A beat for the grid to be seen on its own first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sheetUp = true }
                #if DEBUG
                // `-routineStep call|study|done|finish`: a step for a capture;
                // `finish` runs Done by itself after a moment.
                switch UserDefaults.standard.string(forKey: "routineStep") {
                case "call": step = .call
                case "study": step = .study
                case "done": step = .done
                case "finish":
                    step = .done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { finish() }
                default: break
                }
                #endif
            }
            .sheet(isPresented: $sheetUp) {
                sheet
                    .presentationDetents([detent])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
            }
    }

    // MARK: - The shrink into the chip

    /// 0 = full screen, 1 = the size and place of the Activity chip.
    private var scale: CGSize {
        let target = handoff.chipFrame
        guard shrink > 0, ownFrame.width > 0, target.width > 0 else { return CGSize(width: 1, height: 1) }
        return CGSize(width: 1 + (target.width / ownFrame.width - 1) * shrink,
                      height: 1 + (target.height / ownFrame.height - 1) * shrink)
    }

    private var offset: CGSize {
        let target = handoff.chipFrame
        guard shrink > 0, ownFrame.width > 0, target.width > 0 else { return .zero }
        return CGSize(width: (target.midX - ownFrame.midX) * shrink,
                      height: (target.midY - ownFrame.midY) * shrink)
    }

    private func finish() {
        Analytics.capture("routine_onboarding", [
            "call_minutes": callMinutes,
            "call_hour": cal.component(.hour, from: callTime),
            "days": days.count,
            "study_minutes": studyMinutes,
            "call_on": !callBlocked
        ])
        sheetUp = false
        // The sheet goes down first, then the page is drawn into the chip:
        // a quick pull back, then in, fading out as it reaches the chip.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeIn(duration: 0.5)) { shrink = 1 }
            withAnimation(.easeIn(duration: 0.15).delay(0.4)) { fade = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                HapticEngine.light()
                handoff.landed += 1
                onFinished()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { handoff.showHint = true }
                // It closes on its own too: the sheets that waited for the
                // builder (Talk's guide) come after it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { handoff.showHint = false }
            }
        }
    }

    // MARK: - The sheet

    private var detent: PresentationDetent {
        switch step {
        case .intro: return .height(300)
        case .call: return .height(470)
        case .study: return .height(330)
        case .done: return .height(300)
        }
    }

    @ViewBuilder
    private var sheet: some View {
        switch step {
        case .intro: intro
        case .call: callStep
        case .study: studyStep
        case .done: done
        }
    }

    private var intro: some View {
        message(icon: "calendar.badge.clock", tint: .accentColor,
                title: explain("Let's make your routine"),
                body: explain("Try it just as it is for a week. You can change it any time."),
                button: explain("Make my routine")) {
            withAnimation { step = .call }
        }
    }

    private var done: some View {
        message(icon: "checkmark.circle.fill", tint: .green,
                title: explain("Your routine is ready"),
                body: callBlocked
                    ? explain("Notifications are off, so I can't call you yet. Turn them on in Settings. Your routine is under Activity on the Talk screen.")
                    : explain("Try it like this for a week. It's under Activity on the Talk screen whenever you want to change it."),
                button: explain("Done")) {
            finish()
        }
    }

    private func message(icon: String, tint: Color, title: String, body: String,
                         button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: action) {
                Text(button).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var callStep: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Minutes", selection: $callMinutes) {
                        ForEach(Self.callChoices, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(explain("How long a call?"))
                }
                Section {
                    DatePicker("Calls at", selection: $callTime, displayedComponents: .hourAndMinute)
                    dayChips
                } header: {
                    Text(explain("When?"))
                } footer: {
                    Text(explain("Your fluent self calls you at this time."))
                }
            }
            .navigationTitle(explain("Your daily call"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                saveButton { await saveCall() }
            }
        }
    }

    private var studyStep: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Study time", selection: $studyMinutes) {
                        ForEach(Self.studyChoices, id: \.self) { m in
                            Text(m == 60 ? explain("1 hour") : chrome("\(m) min")).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(explain("How much can you study a day?"))
                } footer: {
                    Text(explain("I'll put review in at \(reviewTimeText), about \(studyMinutes * StudyPlan.Kind.reviewCardsPerQuarter / 15) cards. Drag it on the grid to move it later."))
                }
            }
            .navigationTitle(explain("Study time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation { step = .call }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text("Back"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton { saveStudy() }
            }
        }
    }

    private func saveButton(_ action: @escaping () async -> Void) -> some View {
        Button {
            working = true
            Task {
                await action()
                working = false
            }
        } label: {
            HStack {
                if working { ProgressView().tint(.white) }
                Text("Save")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(working || days.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// The days the call (and review) run on. Lit = a study day; at least one.
    private var dayChips: some View {
        var c = cal
        c.locale = uiLocale
        let symbols = c.veryShortWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { wd in
                let on = days.contains(wd)
                Button {
                    if on { if days.count > 1 { days.remove(wd) } } else { days.insert(wd) }
                } label: {
                    Text(symbols[wd - 1])
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var reviewTimeText: String {
        let d = cal.date(bySettingHour: Self.reviewTime.hour, minute: Self.reviewTime.minute, second: 0, of: Date()) ?? Date()
        return d.formatted(Date.FormatStyle(locale: uiLocale).hour().minute())
    }

    private var callTimeValue: DailyCallStore.CallTime {
        let c = cal.dateComponents([.hour, .minute], from: callTime)
        return DailyCallStore.CallTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
    }

    private func apply(study: Int?) {
        let plan = StudyPlanStore.shared.plan.withOnboardingRoutine(
            callMinutes: callMinutes, callTime: callTimeValue, days: days,
            studyMinutes: study, reviewTime: Self.reviewTime)
        StudyPlanStore.shared.update(plan, byLearner: true)
    }

    /// The call lands on the grid first, then the permission it needs is
    /// asked — with the block it is for in view behind the alert.
    private func saveCall() async {
        apply(study: nil)
        UserDefaults.standard.set(callMinutes, forKey: "futurevoice.dailyGoalMinutes")
        spotlight = .init(kind: .talk, minute: callTimeValue.id, token: (spotlight?.token ?? 0) + 1)
        try? await Task.sleep(for: .milliseconds(700))
        // The weekly test's "it's ready" notice rides on the same answer.
        WeeklyTestSettings.shared.reminderOn = true
        let granted = await DailyCallScheduler.requestPermission()
        await WeeklyTestReminder.settleAfterPermission()
        DailyCallStore.shared.isEnabled = granted
        callBlocked = !granted
        if granted { appState.refreshDailyCall(force: true) }
        withAnimation { step = .study }
    }

    private func saveStudy() {
        apply(study: studyMinutes)
        spotlight = .init(kind: .review, minute: Self.reviewTime.id, token: (spotlight?.token ?? 0) + 1)
        withAnimation { step = .done }
    }
}

#if DEBUG
/// `-onboardingPreview routine`: the builder over the tabs, as a new install
/// meets it, without walking setup and the clone first.
struct RoutinePreview: View {
    @State private var done = false

    var body: some View {
        RootTabView(holdingForRoutine: !done)
            .overlay {
                if !done { RoutineOnboardingView { done = true } }
            }
    }
}
#endif
