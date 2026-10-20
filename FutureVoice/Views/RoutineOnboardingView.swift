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
/// and a sheet over it.
///
/// The sheet asks what goes IN the routine (2026-10-20, founder): every kind
/// of block as a row of a list — what it is, in two lines, and when it would
/// go — and the learner ticks as many as they like. Times and amounts are
/// the defaults below and the footer says they can be changed later; a card
/// per kind asking for a time was tried the same day and cut, because the
/// times were the app's guess anyway and six cards of different heights
/// read as a form. Every picked block runs every day. Shown over the Talk
/// tab once; Done shrinks it into the Activity chip, which is where it
/// lives from then on.
struct RoutineOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var handoff = RoutineHandoff.shared
    var onFinished: () -> Void

    private enum Step { case intro, pick, done }

    /// The rows, in the order of a day.
    static let kinds: [StudyPlan.Kind] = [.talk, .sayItAgain, .listen, .shadow, .speech, .review]

    /// Where each block goes and how much it asks for. Say it again sits
    /// right after the call, as it is in the day.
    static let callMinutes = 5
    static func slot(_ kind: StudyPlan.Kind) -> (hour: Int, minute: Int, amount: Int) {
        switch kind {
        case .talk: return (8, 0, callMinutes)
        case .sayItAgain: return (8, callMinutes, 1)
        case .listen: return (8, 30, 1)
        case .shadow: return (12, 30, 1)
        case .speech: return (20, 0, 1)
        case .review: return (21, 0, 10)
        default: return (20, 0, kind.defaultAmount)
        }
    }

    @State private var step: Step = .intro
    @State private var sheetUp = false
    @State private var spotlight: WeeklyPlanEditor.Spotlight?
    @State private var working = false
    /// Neither alarms nor notifications were allowed: the routine stands,
    /// but nothing can ring.
    @State private var callBlocked = false
    /// The call is ticked to begin with: it is what the app is.
    @State private var selected: Set<StudyPlan.Kind> = [.talk]
    /// What was saved — the done card speaks about this, not the ticks.
    @State private var saved: Set<StudyPlan.Kind> = []

    @State private var ownFrame: CGRect = .zero
    @State private var shrink: CGFloat = 0
    @State private var fade = false

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
                // `-routineStep pick|done|finish`: a step for a capture;
                // `finish` runs Done by itself after a moment.
                switch UserDefaults.standard.string(forKey: "routineStep") {
                case "pick": step = .pick
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
                    .presentationDetents([step == .pick ? .large : .height(300)])
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
            "call_minutes": saved.contains(.talk) ? Self.callMinutes : 0,
            "picked": Self.kinds.filter { saved.contains($0) }.map(\.rawValue).joined(separator: ","),
            "call_on": saved.contains(.talk) && !callBlocked
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

    @ViewBuilder
    private var sheet: some View {
        switch step {
        case .intro: intro
        case .pick: pick
        case .done: done
        }
    }

    private var intro: some View {
        message(icon: "calendar.badge.clock", tint: .accentColor,
                title: explain("Let's make your routine"),
                body: explain("Try it just as it is for a week. You can change it any time."),
                button: explain("Make my routine")) {
            withAnimation { step = .pick }
        }
    }

    private var done: some View {
        message(icon: saved.isEmpty ? "calendar" : "checkmark.circle.fill",
                tint: saved.isEmpty ? .secondary : .green,
                title: saved.isEmpty ? explain("You can make it later") : explain("Your routine is ready"),
                body: saved.isEmpty
                    ? explain("Your routine is under Activity on the Talk screen whenever you want one.")
                    : saved.contains(.talk) && callBlocked
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

    // MARK: - What goes in

    private var pick: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.kinds) { kind in row(kind) }
                } footer: {
                    Text(explain("Every day at these times to start with. You can change the times, the days and how much under Activity on the Talk screen."))
                }
            }
            .navigationTitle(explain("What goes in your routine?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation { step = .intro }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text("Back"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    working = true
                    Task {
                        await save()
                        working = false
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text(selected.isEmpty ? explain("Not now") : explain("Make my routine"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(working)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                // The list scrolls under the button; it must not show through.
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func row(_ kind: StudyPlan.Kind) -> some View {
        let on = selected.contains(kind)
        return Button {
            if on { selected.remove(kind) } else { selected.insert(kind) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: kind.symbol)
                    .font(.title3)
                    .foregroundStyle(kind.color)
                    .frame(width: 28)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.label).font(.headline)
                    Text(pitch(kind))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(whenText(kind))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// What each block is, for someone who has never done it.
    private func pitch(_ kind: StudyPlan.Kind) -> String {
        switch kind {
        case .talk: return explain("Your fluent self calls you, in your own voice. Talk for 5 minutes about anything.")
        case .sayItAgain: return explain("Go back through the call you just had. Your lines come up the way a fluent speaker would say them, and you read them out loud.")
        case .listen: return explain("The nawana Podcast and the situations you've watched, played one after another. Good for the commute.")
        case .shadow: return explain("Hear a line from your fluent self and say it along with them, in the same rhythm. You get a score.")
        case .speech: return explain("Read a script out loud on camera and get a score for pronunciation and pace.")
        case .review: return explain("Cards with the words, expressions and corrected sentences from your talks, 10 at a time.")
        default: return ""
        }
    }

    /// "Every day · 8:00", or "Right after the call".
    private func whenText(_ kind: StudyPlan.Kind) -> String {
        if kind == .sayItAgain { return explain("Right after the call") }
        let s = Self.slot(kind)
        let d = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
        return explain("Every day · \(d.formatted(Date.FormatStyle(locale: uiLocale).hour().minute()))")
    }

    /// The ticked blocks on the grid, then the permission they need — the
    /// call's alarm when the call is in, otherwise notifications for the
    /// reminders.
    private func save() async {
        let blocks = Self.kinds.filter { selected.contains($0) }.map { kind in
            let s = Self.slot(kind)
            return StudyPlan.Block(kind: kind, weekdays: Set(1...7), hour: s.hour, minute: s.minute, minutes: s.amount)
        }
        saved = selected
        let plan = StudyPlanStore.shared.plan.withOnboardingRoutine(blocks, days: Set(1...7))
        StudyPlanStore.shared.update(plan, byLearner: true)
        guard let first = blocks.first else {
            withAnimation { step = .done }
            return
        }
        withAnimation { step = .done }
        spotlight = .init(kind: first.kind, minute: first.startMinute, token: (spotlight?.token ?? 0) + 1)
        try? await Task.sleep(for: .milliseconds(700))
        if saved.contains(.talk) {
            UserDefaults.standard.set(Self.callMinutes, forKey: "futurevoice.dailyGoalMinutes")
            // The weekly test's "it's ready" notice rides on the same answer.
            WeeklyTestSettings.shared.reminderOn = true
            let granted = await DailyCallScheduler.requestPermission()
            await WeeklyTestReminder.settleAfterPermission()
            DailyCallStore.shared.isEnabled = granted
            callBlocked = !granted
            if granted { appState.refreshDailyCall(force: true) }
        } else {
            DailyCallStore.shared.isEnabled = false
            await PlanReminder.requestPermissionIfNeeded()
        }
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
