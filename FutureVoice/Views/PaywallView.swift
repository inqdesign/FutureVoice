import SwiftUI
import UserNotifications
import Supabase

/// Three-step trial-first paywall (pitch → trial timeline → plan picker),
/// modeled on the Speak flow: sell the value, de-risk the trial, then show
/// prices last. Pure SwiftUI + system colors; prices and trial length come
/// live from StoreKit, the plan catalog from the server.
///
/// LANGUAGE: every word on this screen goes through `explain()` — the
/// learner's NATIVE language — including titles and buttons, which the rest
/// of the app renders as target-language chrome. Paying is a decision you
/// have to understand and consent to, and "Start my free 7-day trial" in a
/// language someone is still learning is a comprehension barrier at exactly
/// the wrong moment. This screen is the documented exception to the chrome
/// rule in CLAUDE.md; keep it that way when adding copy here.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var store = StoreKitService()

    @State private var step: Step = .resolving
    /// The server's billing snapshot. Someone already paying (or in trial)
    /// opened this sheet to CHANGE plans, so the trial funnel is not just
    /// noise — it is wrong; and the plan they hold has to be visible on the
    /// screen that sells plans, or the sheet asks them to buy what they own.
    @State private var account: AccountStatus = .empty
    // Monthly by default: it is the smaller commitment, and a paywall that
    // opens on the year-long option reads as pressure rather than a choice.
    @State private var period: PlanPeriod = .monthly
    @State private var selectedTier: String = "unlimited"

    /// `.resolving` is the state before StoreKit and the account snapshot
    /// have answered. Without it the sheet opened on `.pitch` and jumped to
    /// `.plans` a beat later — a "Try for free" pitch flashed at people who
    /// already pay us.
    enum Step { case resolving, pitch, timeline, plans }

    enum PlanPeriod: String, CaseIterable, Identifiable {
        case weekly, monthly, annual
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekly:  return explain("Weekly")
            case .monthly: return explain("Monthly")
            case .annual:  return explain("Annual")
            }
        }
        var cycleNoun: String {
            switch self {
            case .weekly:  return explain("week")
            case .monthly: return explain("month")
            case .annual:  return explain("year")
            }
        }
    }

    /// Show the trial funnel when Apple still offers this account an intro
    /// offer. That flag IS the truth now — under the hard paywall there are no
    /// free credits to have "already spent", and Apple already returns false
    /// once a trial has been used. False means: skip the pitch, open on plans,
    /// and say "Subscribe" instead of "Try for free".
    private var showsTrial: Bool { store.trialEligible }

    /// Already entitled — paid or in trial.
    private var isSubscriber: Bool { account.isEntitled }

    /// Whether this viewer was actually walked through pitch → timeline. A
    /// subscriber never is, so for them `.plans` is the FIRST step and its
    /// back button has to close the sheet — `showsTrial` alone sent them
    /// backwards into a trial pitch for something they already pay for.
    private var walkedTrialFunnel: Bool { showsTrial && !isSubscriber }

    /// The plan this account holds right now (`daily_monthly`), or nil.
    private var currentPlanId: String? { isSubscriber ? account.planId : nil }

    private func isCurrentPlan(tier: String, period: PlanPeriod) -> Bool {
        currentPlanId == "\(tier)_\(period.rawValue)"
    }

    /// True when the selection IS what they already pay for — the one case
    /// where the button must not say "Subscribe".
    private var selectionIsCurrentPlan: Bool {
        isCurrentPlan(tier: selectedTier, period: period)
    }

    /// The held plan, named the way the CARDS name it ("Unlimited · Monthly")
    /// — `AccountStatus.planLabel` capitalizes the raw plan id, so it reads
    /// English beside a Korean card that says 무제한.
    private var currentPlanLabel: String {
        guard let id = currentPlanId else { return "" }
        let parts = id.split(separator: "_").map(String.init)
        let name = parts.first == "unlimited" ? explain("Unlimited") : explain("Daily")
        // The trial is metered as Daily whatever plan it trials, so the tier
        // it names is the plan it will BECOME, not today's allowance.
        if account.isTrialing { return explain("\(name) trial") }
        guard let raw = parts.dropFirst().first,
              let held = PlanPeriod(rawValue: raw) else { return name }
        return "\(name) · \(held.label)"
    }

    /// Apple's own subscription management screen. Changing or cancelling a
    /// live subscription happens there, never in-app.
    private static let manageSubscriptionsURL = URL(
        string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case .resolving: resolvingContent
                    case .pitch:    pitchContent
                    case .timeline: timelineContent
                    case .plans:    plansContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            bottomBar
        }
        .background(Color(.systemBackground))
        .task {
            // Both answers are needed before the first frame can be chosen,
            // so fetch them together rather than in sequence.
            async let products: Void = store.load()
            async let snapshot = AccountStatus.fetch()
            _ = await products
            account = await snapshot
            // Open on the plan they hold, so the sheet starts by showing
            // their own state rather than a pitch for something else.
            if let id = currentPlanId {
                let parts = id.split(separator: "_")
                if let tier = parts.first { selectedTier = String(tier) }
                if let raw = parts.dropFirst().first,
                   let held = PlanPeriod(rawValue: String(raw)) { period = held }
            }
            // Pitch the trial only to someone who could actually take it:
            // not a current subscriber, not during the beta, and only while
            // Apple still offers this account an intro offer.
            step = walkedTrialFunnel ? .pitch : .plans
        }
        .onChange(of: store.purchaseState) { _, state in
            if state == .purchased, showsTrial {
                scheduleTrialEndingReminder(trialDays: store.trialDays)
            }
        }
        .alert(Text(explain("You're in")), isPresented: purchasedBinding) {
            Button(explain("Done")) { dismiss() }
        } message: {
            Text(explain("Your subscription is active. Your talk time lands on your account as soon as Apple confirms the purchase."))
        }
        .alert(Text(explain("Purchase failed")), isPresented: failedBinding) {
            Button(explain("OK")) { store.purchaseState = .idle }
        } message: {
            if case .failed(let msg) = store.purchaseState { Text(msg) }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                switch step {
                case .resolving: dismiss()
                case .pitch:    dismiss()
                case .timeline: step = .pitch
                // Without a trial funnel there are no earlier steps — back
                // from plans just closes.
                case .plans:    walkedTrialFunnel ? (step = .timeline) : dismiss()
                }
            } label: {
                Image(systemName: step == .pitch || step == .resolving
                      || (step == .plans && !walkedTrialFunnel)
                      ? "xmark" : "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                switch step {
                case .resolving: break
                case .pitch:    step = .timeline
                case .timeline: step = .plans
                case .plans:
                    if selectionIsCurrentPlan { openURL(Self.manageSubscriptionsURL) }
                    else { Task { await purchaseSelected() } }
                }
            } label: {
                Group {
                    if store.purchaseState == .purchasing {
                        ProgressView()
                    } else {
                        Text(ctaTitle)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.purchaseState == .purchasing)
            .opacity(step == .resolving ? 0 : 1)
            .allowsHitTesting(step != .resolving)

            if step == .plans {
                Button(explain("Restore purchases")) {
                    Task { await store.restore() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if step != .resolving {
                Text(explain("\(store.trialDays) days free. Cancel anytime."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var ctaTitle: String {
        switch step {
        case .resolving: return ""
        case .pitch:    return explain("Try for free")
        case .timeline: return explain("See plans")
        case .plans:
            // A subscriber can't buy what they already have — the only real
            // action on their own plan is Apple's management screen. Picking
            // the other plan is a change, not a first purchase, and must not
            // be dressed up as a trial.
            if selectionIsCurrentPlan { return explain("Manage subscription") }
            if isSubscriber { return explain("Change plan") }
            return showsTrial && selectedOption?.trialDays != nil
                ? explain("Start my free \(store.trialDays)-day trial")
                : explain("Subscribe")
        }
    }

    /// Deliberately quiet: a spinner, not a skeleton of the pitch. Whatever
    /// is drawn here is what a subscriber sees for a fraction of a second.
    private var resolvingContent: some View {
        VStack {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 120)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1 · Pitch

    private var pitchContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(explain("You, but fluent"))
                    .font(.largeTitle.weight(.bold))
                Text(explain("Speak every day — and keep everything it teaches you."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 18) {
                featureRow("bubble.left.and.bubble.right.fill",
                           explain("Real conversations, your voice"),
                           explain("Talk daily with your fluent self — every reply synthesized in your cloned voice."))
                featureRow("play.rectangle.on.rectangle.fill",
                           explain("Rehearse before it happens"),
                           explain("Watch your fluent self handle what's coming — from your own life or this week's news."))
                featureRow("sparkles",
                           explain("Corrections that stick"),
                           explain("Inline fixes become spaced-repetition drills, tuned to your mistakes."))
                featureRow("waveform.badge.mic",
                           explain("Pronunciation you can measure"),
                           explain("Shadow any line, get a real score, watch the weekly trend."))
            }
        }
    }

    /// `title` is a LocalizedStringKey so the literal EXTRACTS and follows
    /// the chrome locale; `caption` arrives already resolved through
    /// `explain()`. Passing both as plain `String` is why every feature row
    /// rendered in English next to a Korean subtitle.
    private func featureRow(_ icon: String, _ title: String, _ caption: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2 · Trial timeline

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(explain("\(store.trialDays) days free, no surprises"))
                    .font(.largeTitle.weight(.bold))
                Text(explain("We'll remind you before your trial ends."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                timelineRow(icon: "lock.open.fill",
                            title: explain("Today"),
                            caption: explain("Your trial starts — five minutes of talk a day, and all the review it produces."),
                            showsLine: true)
                timelineRow(icon: "bell.fill",
                            title: explain("Day \(max(1, store.trialDays - 2))"),
                            caption: explain("We send a reminder that your trial is about to end."),
                            showsLine: true)
                timelineRow(icon: "crown.fill",
                            title: explain("Day \(store.trialDays)"),
                            caption: explain("Your subscription starts. Cancel any time before then in the App Store."),
                            showsLine: false)
            }
        }
    }

    /// No tint parameter: the row follows the app's `.tint`, which is the
    /// Futureself palette the learner picked. A literal `Color.accentColor`
    /// does NOT cross a sheet boundary — that is why the badge and selection
    /// ring rendered system blue next to a green button.
    private func timelineRow(icon: String, title: String,
                             caption: String, showsLine: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                if showsLine {
                    Rectangle()
                        .fill(.tint.opacity(0.5))
                        .frame(width: 4)
                        .frame(minHeight: 34)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 22)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 3 · Plans

    private var plansContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isSubscriber ? explain("Your plan") : explain("Choose your plan"))
                .font(.largeTitle.weight(.bold))
                .padding(.top, 12)

            if isSubscriber {
                Label(account.isTrialing
                      ? explain("You're on the \(currentPlanLabel) — it converts unless you cancel.")
                      : explain("You're subscribed to \(currentPlanLabel)."),
                      systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker(explain("Billing period"), selection: $period) {
                ForEach(availablePeriods) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: availablePeriods) { _, periods in
                // A period whose SKU vanished must not stay selected, or the
                // cards below render a plan nobody can buy.
                if !periods.contains(period), let first = periods.first { period = first }
            }

            VStack(spacing: 14) {
                // Tier = amount of talk time, not features — the names say
                // the quantity so the plans read as phone-plan sizes.
                // The plans differ in AMOUNT — that is the honest axis, and
                // pretending otherwise (purpose, level, "serious learners")
                // would send people to the wrong plan. But the label must not
                // grade the buyer: "heavy/light user" tells someone they are
                // the small one. So each card asks the same question about
                // the same number and lets the reader recognise themselves.
                planCard(tier: "unlimited",
                         audience: explain("If five minutes isn't enough"),
                         name: explain("Unlimited"),
                         blurb: explain("Long sessions, several a day — as many calls and scenes as you want."))
                planCard(tier: "daily",
                         audience: explain("If five minutes a day is enough"),
                         name: explain("Daily"),
                         blurb: explain("The same five minutes every day — small enough that you actually do it."))
            }

            // A missing price is a StoreKit state the learner can do
            // nothing about — explaining it ("prices load from the App
            // Store") turned a blank into an apology on every open. The card
            // simply omits the price.
            //
            // Directly under the cards on purpose: the question in a buyer's
            // head right after picking is "what happens if I stop paying?".
            // It used to sit last, below the fold, while the paragraph above
            // made the same promise in prose — one place, and the concrete
            // one, is enough.
            VStack(alignment: .leading, spacing: 12) {
                Text(explain("Always free"))
                    .font(.footnote.weight(.semibold))
                freeRow("repeat", explain("Replay shadow lines"), explain("Loop and slow down cached audio."))
                freeRow("rectangle.stack.fill", explain("Review drills"), explain("Spaced repetition, graded on device."))
                freeRow("play.rectangle.on.rectangle", explain("Re-watch dialogues"), explain("Generated once, then cached."))
            }
            .padding(.top, 4)

            Text(explain("Your plan buys talk time with your fluent self plus a number of Watch scenes each day — two separate daily allowances, both refilling at midnight."))
                .font(.caption)
                .foregroundStyle(.secondary)

            subscriptionLegal
        }
    }

    /// Required on any screen that sells an auto-renewable subscription (App
    /// Store Review 3.1.2): what renews, when it's billed, how to stop it, and
    /// links to the terms + privacy policy. Missing links are the single most
    /// common subscription rejection — this block is not decoration.
    private var subscriptionLegal: some View {
        VStack(spacing: 8) {
            Text(explain("Payment is charged to your Apple Account at purchase. The subscription renews automatically unless you cancel at least 24 hours before the period ends. Manage or cancel it in Settings › Apple Account › Subscriptions."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Link(explain("Terms of Use"), destination: Self.termsURL)
                Text("·").foregroundStyle(.secondary)
                Link(explain("Privacy Policy"), destination: Self.privacyURL)
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Billing periods the picker offers: only those with a product actually
    /// on sale, so a SKU that doesn't exist in App Store Connect can't be
    /// selected into "This plan isn't available" (weekly is exactly that today
    /// — it lives in the DB catalog with no locked price and no ASC product).
    /// Data-driven on purpose: creating the weekly products later makes the
    /// segment appear with no code change. With nothing loaded — the beta, or
    /// products not yet created — fall back to the two the catalog sells.
    private var availablePeriods: [PlanPeriod] {
        let live = PlanPeriod.allCases.filter { p in
            store.options.contains { $0.plan.period == p.rawValue && $0.product != nil }
        }
        return live.isEmpty ? [.monthly, .annual] : live
    }

    /// Apple's standard EULA — the licence this app ships under. Swap this for
    /// our own URL only if custom terms are ever written AND the same link is
    /// set in App Store Connect; the two must agree.
    private static let termsURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// The privacy policy has a Korean edition — a policy you can't read isn't
    /// disclosure, so follow the device's language rather than the app's
    /// target-language chrome.
    private static var privacyURL: URL {
        let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        return URL(string: korean ? "https://nawana.app/privacy-ko.html"
                                  : "https://nawana.app/privacy.html")!
    }

    private func freeRow(_ icon: String, _ title: String, _ caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Talk time per day this plan buys — the server's per-day allowance
    /// (`subscription_plans.daily_seconds`), shown in minutes.
    /// "5 min of talk a day · 2 scenes" — the two allowances a metered plan
    /// buys, in one line. Scenes left the talk meter on 2026-08-14 and are
    /// counted separately, so a card that names only minutes is now lying by
    /// omission about half of what the plan includes.
    private func allowanceLine(seconds: Int, scenes: Int?) -> String {
        let mins = explain("\(dailyTalkMinutes(seconds: seconds)) min of talk a day")
        guard let scenes, scenes > 0 else { return mins }
        return explain("\(mins) · \(scenes) scenes")
    }

    private func dailyTalkMinutes(seconds: Int) -> Int {
        max(1, seconds / 60)
    }

    /// What price a card may show. Live App Store price whenever there is
    /// one. The planned figure is allowed ONLY in the beta survey, where
    /// nothing can be bought and the screen exists to ask "would you pay
    /// this?" — a labelled anchor. On a screen that can actually charge, a
    /// hardcoded KRW figure would quote the wrong currency, so it stays nil
    /// and the card shows no price at all.
    private func displayPrice(_ opt: StoreKitService.PlanOption?) -> String? {
        opt?.localizedPrice
    }

    private func option(tier: String) -> StoreKitService.PlanOption? {
        store.options.first { $0.plan.tier == tier && $0.plan.period == period.rawValue }
    }

    /// Percentage the annual plan saves versus paying monthly for a year, for
    /// one tier. nil when either price is unknown or annual isn't cheaper.
    private func annualSavingsPercent(tier: String) -> Int? {
        // Live prices decide the badge. The planned map is a fallback only
        // in the survey, for the same reason as `displayPrice` — otherwise a
        // card showing "—" would still claim a savings percentage computed
        // from numbers the viewer is never shown.
        let storefront = store.options.first?.storefrontCountry
        func value(_ period: String) -> Decimal? {
            let opt = store.options.first { $0.plan.tier == tier && $0.plan.period == period }
            return opt?.priceValue
        }
        let monthly = value("monthly")
        let annual = value("annual")
        guard let monthly, let annual else { return nil }
        // Do the percentage in Double — Decimal division of these values was
        // truncating the sub-1 quotient to 0.
        let m = NSDecimalNumber(decimal: monthly).doubleValue
        let a = NSDecimalNumber(decimal: annual).doubleValue
        let full = m * 12
        guard m > 0, full > a else { return nil }
        let pct = Int(((full - a) / full * 100).rounded())
        return pct > 0 ? pct : nil
    }

    private var selectedOption: StoreKitService.PlanOption? {
        option(tier: selectedTier)
    }

    @ViewBuilder
    private func planCard(tier: String, audience: String, name: String, blurb: String) -> some View {
        let opt = option(tier: tier)
        let isSelected = selectedTier == tier
        let isCurrent = isCurrentPlan(tier: tier, period: period)
        Button {
            selectedTier = tier
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    // A filled capsule reads as an award — it ranked the
                    // plans on one axis and made Daily look like less. This
                    // is a quiet label that tells you which one is yours.
                    // For the plan already held, WHICH ONE IT IS outranks the
                    // "is this you?" question the audience line asks.
                    Text(isCurrent ? explain("Current plan") : audience)
                        .font(.caption.weight(isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .font(.title3)
                }
                Text(name).font(.title3.weight(.bold))
                Text(blurb).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    // What the plan buys, per day. Unlimited deliberately
                    // shows NO number: its allowance is a fair-use ceiling,
                    // and printing "60 min" next to the word Unlimited reads
                    // as a cap the buyer has to ration.
                    if tier == "unlimited" {
                        Text(explain("Unlimited talk & scenes"))
                            .font(.footnote.weight(.semibold))
                    } else if let capSeconds = opt?.plan.daily_seconds {
                        Text(allowanceLine(seconds: capSeconds, scenes: opt?.plan.daily_scenes))
                            .font(.footnote.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        // No placeholder when StoreKit hasn't priced it: a
                        // dash reads as a broken field, and an absent price
                        // says the same thing more quietly.
                        if let price = displayPrice(opt) {
                            Text("\(price) / \(period.cycleNoun)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if period == .annual, let saved = annualSavingsPercent(tier: tier) {
                            Text(explain("Save \(saved)% vs monthly"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AnyShapeStyle(.tint)
                                       : AnyShapeStyle(Color.primary.opacity(0.06)),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let opt = selectedOption else { return }
        await store.purchase(opt)
    }

    /// Honor the timeline promise: a local reminder two days before the
    /// trial converts. Quietly skipped if notifications are denied.
    private func scheduleTrialEndingReminder(trialDays: Int) {
        guard trialDays > 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your free trial ends soon"
        content.body = "Your nawana trial converts in 2 days. Cancel anytime in the App Store."
        content.sound = .default
        let fireIn = TimeInterval((trialDays - 2) * 24 * 60 * 60)
        let request = UNNotificationRequest(
            identifier: "futurevoice.trial-ending",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Bindings

    private var purchasedBinding: Binding<Bool> {
        Binding(get: { store.purchaseState == .purchased },
                set: { if !$0 { store.purchaseState = .idle; dismiss() } })
    }

    private var failedBinding: Binding<Bool> {
        Binding(get: {
            if case .failed = store.purchaseState { return true }
            return false
        }, set: { if !$0 { store.purchaseState = .idle } })
    }
}
