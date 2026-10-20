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

    /// The first sheet is the intro AND the list: "Make my routine" grows
    /// it in place into the list (founder: no second window).
    private enum Step { case intro, done }

    /// Every kind, in the order of a day. The call is set by hand (length,
    /// time, days); the rest are ticked from a list.
    static let kinds: [StudyPlan.Kind] = [.talk, .sayItAgain, .listen, .shadow, .speech, .review]
    static let others: [StudyPlan.Kind] = kinds.filter { $0 != .talk }
    static let callChoices = [5, 10, 15, 20]

    /// Where each block goes and how much it asks for. Say it again sits
    /// right after the call, as it is in the day.
    private func slot(_ kind: StudyPlan.Kind) -> (hour: Int, minute: Int, amount: Int) {
        let c = cal.dateComponents([.hour, .minute], from: callTime)
        let start = (c.hour ?? 8) * 60 + (c.minute ?? 0)
        let end = start + callMinutes
        switch kind {
        case .talk: return (start / 60, start % 60, callMinutes)
        case .sayItAgain:
            return end + StudyPlan.sayItAgainMinutes <= 24 * 60 ? (end / 60, end % 60, 1) : (8, 15, 1)
        case .listen: return (8, 30, 1)
        case .shadow: return (12, 30, 1)
        case .speech: return (20, 0, 1)
        case .review: return (21, 0, 10)
        default: return (20, 0, kind.defaultAmount)
        }
    }

    @State private var step: Step = .intro
    @State private var callMinutes = 5
    @State private var callTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    /// The days the whole routine runs on; the rest are rest days.
    @State private var days: Set<Int> = Set(1...7)
    /// The intro has grown into the list.
    @State private var expanded = false
    @State private var detent: PresentationDetent = .height(300)
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
                // `-routineStep pick|done|finish|advance`: a step for a capture;
                // `finish` runs Done by itself after a moment.
                switch UserDefaults.standard.string(forKey: "routineStep") {
                case "pick": expand()
                case "advance":
                    // The intro growing into the list, for a recording.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { expand() }
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
                    .presentationDetents([.height(300), .large], selection: $detent)
                    // Dragged up, the intro opens into the list; the list
                    // never folds back into the intro.
                    .onChange(of: detent) { _, d in
                        guard step == .intro else { return }
                        if d == .large, !expanded { expand() }
                        if d != .large, expanded { detent = .large }
                    }
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
            "call_minutes": saved.contains(.talk) ? callMinutes : 0,
            "call_hour": cal.component(.hour, from: callTime),
            "days": days.count,
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
        case .intro: pick
        case .done: done
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

    private func expand() {
        withAnimation(.easeInOut(duration: 0.35)) {
            expanded = true
            detent = .large
        }
    }

    /// The intro, and — once "Make my routine" is tapped — the list under it,
    /// in the same sheet.
    private var pick: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: expanded ? 30 : 40))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(expanded ? explain("What goes in your routine?") : explain("Let's make your routine"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(expanded
                         ? explain("Pick as many as you like.")
                         : explain("Try it just as it is for a week. You can change it any time."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: expanded ? 8 : 20, leading: 24, bottom: 4, trailing: 24))
            }
            if expanded {
                Section {
                    row(.talk)
                    if selected.contains(.talk) {
                        Picker("Minutes", selection: $callMinutes) {
                            ForEach(Self.callChoices, id: \.self) { m in
                                Text("\(m) min").tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker("Calls at", selection: $callTime, displayedComponents: .hourAndMinute)
                            .environment(\.locale, uiLocale)
                    }
                    dayChips
                } header: {
                    Text(explain("Your daily call"))
                } footer: {
                    Text(explain("Everything in your routine runs on these days."))
                }
                .transition(.opacity)
                Section {
                    ForEach(Self.others) { kind in row(kind) }
                } header: {
                    Text(explain("Add more"))
                } footer: {
                    Text(explain("These go in at the times shown to start with. You can change the times and how much under Activity on the Talk screen."))
                }
                .transition(.opacity)
            }
        }
        .scrollDisabled(!expanded)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard expanded else { expand(); return }
                working = true
                Task {
                    await save()
                    working = false
                }
            } label: {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(expanded && selected.isEmpty ? explain("Not now") : expanded ? explain("Done") : explain("Make my routine"))
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
                    // The call's time is set right under it.
                    if kind != .talk {
                        Text(whenText(kind))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
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

    /// The days the routine runs on. Lit = a study day; at least one.
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

    /// What each block is, for someone who has never done it.
    private func pitch(_ kind: StudyPlan.Kind) -> String {
        switch kind {
        case .talk: return explain("Your fluent self calls you, in your own voice, and you talk about anything.")
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
        let s = slot(kind)
        let d = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
        let time = d.formatted(Date.FormatStyle(locale: uiLocale).hour().minute())
        return days.count == 7 ? explain("Every day · \(time)") : time
    }

    /// The ticked blocks on the grid, then the permission they need — the
    /// call's alarm when the call is in, otherwise notifications for the
    /// reminders.
    private func save() async {
        let blocks = Self.kinds.filter { selected.contains($0) }.map { kind in
            let s = slot(kind)
            return StudyPlan.Block(kind: kind, weekdays: days, hour: s.hour, minute: s.minute, minutes: s.amount)
        }
        saved = selected
        detent = .height(300)
        let plan = StudyPlanStore.shared.plan.withOnboardingRoutine(blocks, days: days)
        StudyPlanStore.shared.update(plan, byLearner: true)
        guard let first = blocks.first else {
            withAnimation { step = .done }
            return
        }
        withAnimation { step = .done }
        spotlight = .init(kind: first.kind, minute: first.startMinute, token: (spotlight?.token ?? 0) + 1)
        try? await Task.sleep(for: .milliseconds(700))
        if saved.contains(.talk) {
            UserDefaults.standard.set(callMinutes, forKey: "futurevoice.dailyGoalMinutes")
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
