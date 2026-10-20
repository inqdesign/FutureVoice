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
/// The sheet shows what there IS to do, one card at a time (2026-10-20,
/// founder: not "how much will you study a day" but "here is what you can
/// study — put in what you want"): the daily call, say it again, review,
/// shadowing, listening, speech. Each card says what it is in one line and
/// asks when; "Add to my routine" puts it on the grid on the days chosen on
/// the first card, "Not interested" moves on. The call's card picks the
/// days because it comes first, and passing on it still keeps them. Shown
/// over the Talk tab once; Done shrinks it into the Activity chip, which is
/// where it lives from then on.
struct RoutineOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var handoff = RoutineHandoff.shared
    var onFinished: () -> Void

    private enum Step: Equatable { case intro, item(StudyPlan.Kind), done }

    /// The cards, in order. The call first (it sets the days), say it again
    /// right after it, as it is in the day.
    static let kinds: [StudyPlan.Kind] = [.talk, .sayItAgain, .review, .shadow, .listen, .speech]

    @State private var step: Step = .intro
    @State private var sheetUp = false
    @State private var spotlight: WeeklyPlanEditor.Spotlight?
    @State private var working = false
    /// Neither alarms nor notifications were allowed: the routine stands,
    /// but nothing can ring.
    @State private var callBlocked = false

    @State private var callMinutes = 5
    @State private var callTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var days: Set<Int> = Set(1...7)
    /// Times chosen on the other cards; a card not visited yet reads its
    /// default (`defaultTime`).
    @State private var times: [StudyPlan.Kind: Date] = [:]
    @State private var amounts: [StudyPlan.Kind: Int] = [.review: 10, .shadow: 1]
    /// What went in, by kind.
    @State private var picked: [StudyPlan.Kind: StudyPlan.Block] = [:]

    @State private var ownFrame: CGRect = .zero
    @State private var shrink: CGFloat = 0
    @State private var fade = false

    static let callChoices = [5, 10, 15, 20]
    static let amountChoices: [StudyPlan.Kind: [Int]] = [.review: [10, 20, 40], .shadow: [1, 3, 5]]

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
                // `-routineStep call|sayItAgain|review|shadow|listen|speech|done|finish`:
                // a step for a capture;
                // `finish` runs Done by itself after a moment.
                switch UserDefaults.standard.string(forKey: "routineStep") {
                case "call": step = .item(.talk)
                case "done": step = .done
                case "finish":
                    step = .done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { finish() }
                case let name?:
                    if let k = StudyPlan.Kind(rawValue: name), Self.kinds.contains(k) { step = .item(k) }
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
            "call_minutes": picked[.talk] == nil ? 0 : callMinutes,
            "call_hour": cal.component(.hour, from: callTime),
            "days": days.count,
            "picked": Self.kinds.filter { picked[$0] != nil }.map(\.rawValue).joined(separator: ","),
            "call_on": picked[.talk] != nil && !callBlocked
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
        case .item(.talk): return .height(520)
        case .item(let k): return .height(Self.amountChoices[k] == nil ? 400 : 470)
        case .done: return .height(300)
        }
    }

    @ViewBuilder
    private var sheet: some View {
        switch step {
        case .intro: intro
        case .item(.talk): callStep
        case .item(let k): itemStep(k)
        case .done: done
        }
    }

    private var intro: some View {
        message(icon: "calendar.badge.clock", tint: .accentColor,
                title: explain("Let's make your routine"),
                body: explain("Try it just as it is for a week. You can change it any time."),
                button: explain("Make my routine")) {
            withAnimation { step = .item(.talk) }
        }
    }

    private var done: some View {
        message(icon: picked.isEmpty ? "calendar" : "checkmark.circle.fill",
                tint: picked.isEmpty ? .secondary : .green,
                title: picked.isEmpty ? explain("You can make it later") : explain("Your routine is ready"),
                body: picked.isEmpty
                    ? explain("Your routine is under Activity on the Talk screen whenever you want one.")
                    : picked[.talk] != nil && callBlocked
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
                buttons(.talk) { await saveCall() }
            }
        }
    }

    /// One thing the routine can hold: what it is, when, how much.
    private func itemStep(_ kind: StudyPlan.Kind) -> some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(pitch(kind))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: kind.symbol).foregroundStyle(kind.color)
                    }
                }
                Section {
                    DatePicker("Time", selection: timeBinding(kind), displayedComponents: .hourAndMinute)
                        .environment(\.locale, uiLocale)
                    if let choices = Self.amountChoices[kind] {
                        Picker("How many", selection: amountBinding(kind)) {
                            ForEach(choices, id: \.self) { n in
                                Text(kind.amountText(n)).tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text(explain("When?"))
                }
            }
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        withAnimation { step = previous(kind) }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text("Back"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                buttons(kind) { await save(kind) }
            }
        }
    }

    /// What each card is, in one line.
    private func pitch(_ kind: StudyPlan.Kind) -> String {
        switch kind {
        case .sayItAgain: return explain("Do a talk you just had again, saying your part the better way.")
        case .review: return explain("Go through the words, expressions and sentences your talks left you.")
        case .shadow: return explain("Say your fluent self's lines along with them, in the same rhythm.")
        case .listen: return explain("Listen to the nawana Podcast and the situations you've watched, one after another.")
        case .speech: return explain("Read a script out loud on camera and see how it went.")
        default: return ""
        }
    }

    /// Where each card's block goes if the learner doesn't move it. Say it
    /// again sits right after the call, as it is in the day.
    private func defaultTime(_ kind: StudyPlan.Kind) -> Date {
        let callEnd = callTimeValue.hour * 60 + callTimeValue.minute + callMinutes
        let afterCall = callEnd + StudyPlan.sayItAgainMinutes <= 24 * 60 ? (callEnd / 60, callEnd % 60) : (8, 15)
        let (h, m): (Int, Int) = switch kind {
        case .sayItAgain: picked[.talk] != nil ? afterCall : (8, 15)
        case .review: (21, 0)
        case .shadow: (12, 30)
        case .listen: (8, 30)
        case .speech: (20, 0)
        default: (8, 0)
        }
        return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private func timeBinding(_ kind: StudyPlan.Kind) -> Binding<Date> {
        Binding(get: { times[kind] ?? defaultTime(kind) }, set: { times[kind] = $0 })
    }

    private func amountBinding(_ kind: StudyPlan.Kind) -> Binding<Int> {
        Binding(get: { amounts[kind] ?? kind.defaultAmount }, set: { amounts[kind] = $0 })
    }

    private func previous(_ kind: StudyPlan.Kind) -> Step {
        guard let i = Self.kinds.firstIndex(of: kind), i > 0 else { return .intro }
        return .item(Self.kinds[i - 1])
    }

    private func next(after kind: StudyPlan.Kind) -> Step {
        guard let i = Self.kinds.firstIndex(of: kind), i + 1 < Self.kinds.count else { return .done }
        return .item(Self.kinds[i + 1])
    }

    /// Add it, or pass on it. Passing takes back one added before (Back,
    /// then a change of mind).
    private func buttons(_ kind: StudyPlan.Kind, save: @escaping () async -> Void) -> some View {
        VStack(spacing: 4) {
            saveButton(save)
            Button(explain("Not interested")) {
                if picked.removeValue(forKey: kind) != nil {
                    apply()
                    // No call in the routine: nothing rings.
                    if kind == .talk { DailyCallStore.shared.isEnabled = false }
                }
                withAnimation { step = next(after: kind) }
            }
            .controlSize(.large)
            .disabled(working)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
                Text(explain("Add to my routine"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(working || days.isEmpty)
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

    private var callTimeValue: DailyCallStore.CallTime {
        let c = cal.dateComponents([.hour, .minute], from: callTime)
        return DailyCallStore.CallTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
    }

    private func apply() {
        let blocks = Self.kinds.compactMap { picked[$0] }
        let plan = StudyPlanStore.shared.plan.withOnboardingRoutine(blocks, days: days)
        StudyPlanStore.shared.update(plan, byLearner: true)
    }

    /// The call lands on the grid first, then the permission it needs is
    /// asked — with the block it is for in view behind the alert.
    private func saveCall() async {
        picked[.talk] = StudyPlan.Block(kind: .talk, weekdays: days, hour: callTimeValue.hour,
                                        minute: callTimeValue.minute, minutes: callMinutes)
        apply()
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
        withAnimation { step = next(after: .talk) }
    }

    /// Any other card: on the grid, then — the first time a block that
    /// reminds goes in — the notification permission its reminder needs.
    private func save(_ kind: StudyPlan.Kind) async {
        let c = cal.dateComponents([.hour, .minute], from: timeBinding(kind).wrappedValue)
        let block = StudyPlan.Block(kind: kind, weekdays: days, hour: c.hour ?? 8, minute: c.minute ?? 0,
                                    minutes: amountBinding(kind).wrappedValue)
        picked[kind] = block
        apply()
        spotlight = .init(kind: kind, minute: block.startMinute, token: (spotlight?.token ?? 0) + 1)
        try? await Task.sleep(for: .milliseconds(500))
        await PlanReminder.requestPermissionIfNeeded()
        withAnimation { step = next(after: kind) }
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
