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
    /// Set when the paywall is NOT a sheet — onboarding hosts it as the
    /// screen itself, where `dismiss()` has nothing to dismiss and every exit
    /// would dead-end into a wall. Sheet callers leave it nil.
    private let onClose: (() -> Void)?

    /// The tier this sheet was OPENED for, when the caller named one. It
    /// outranks the held plan below: someone who arrives by tapping "Move to
    /// Plus" on the spent-allowance sheet must not land on a screen with
    /// Light — the plan they already have — selected.
    private let preselectTier: String?

    init(onClose: (() -> Void)? = nil, preselectTier: String? = nil) {
        self.onClose = onClose
        self.preselectTier = preselectTier
    }

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
    @State private var selectedTier: String = "plus"

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

    /// The plan this account holds right now (`light_monthly`), or nil.
    private var currentPlanId: String? { isSubscriber ? account.planId : nil }

    private func isCurrentPlan(tier: String, period: PlanPeriod) -> Bool {
        currentPlanId == "\(tier)_\(period.rawValue)"
    }

    /// True when the selection IS what they already pay for — the one case
    /// where the button must not say "Subscribe".
    private var selectionIsCurrentPlan: Bool {
        isCurrentPlan(tier: selectedTier, period: period)
    }

    /// The held plan, named the way the CARDS name it ("Plus · Monthly") —
    /// `AccountStatus.planLabel` builds the same string but joins its own
    /// period label, so the two would drift the moment either is reworded.
    /// The TIER half comes from the one place tier names live.
    private var currentPlanLabel: String {
        guard let id = currentPlanId else { return "" }
        let name = AccountStatus.tierName(id)
        // The trial is metered at the Light pool pro-rated, whatever plan it
        // trials, so the tier it names is the plan it will BECOME, not what
        // it currently allows.
        if account.isTrialing { return explain("\(name) trial") }
        guard let raw = id.split(separator: "_").dropFirst().first,
              let held = PlanPeriod(rawValue: String(raw)) else { return name }
        return "\(name) · \(held.label)"
    }

    /// The one exit. Also drops the billing gate's cached answer: a purchase
    /// made here changes what every launcher in the app is allowed to start,
    /// and the next tap must ask the server again rather than replay the
    /// snapshot that sent them to this screen.
    private func close() {
        BillingGate.shared.invalidate()
        if let onClose { onClose() } else { dismiss() }
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
            // The billing cycle still comes from the plan they hold (or the
            // monthly default) — only the TIER is what the caller asked for.
            if let preselectTier { selectedTier = preselectTier }
            // Pitch the trial only to someone who could actually take it:
            // not a current subscriber, not during the beta, and only while
            // Apple still offers this account an intro offer.
            step = walkedTrialFunnel ? .pitch : .plans
            #if DEBUG
            // Screenshot harness: the plan cards are two taps in, and a
            // capture run can't tap. Never reachable outside `-capture`.
            if UserDefaults.standard.string(forKey: "capture") == "paywall-plans" {
                step = .plans
            }
            #endif
        }
        .onChange(of: store.purchaseState) { _, state in
            if state == .purchased, showsTrial {
                scheduleTrialEndingReminder(trialDays: store.trialDays)
            }
        }
        .alert(Text(explain("You're in")), isPresented: purchasedBinding) {
            Button(explain("Done")) { close() }
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
                case .resolving: close()
                case .pitch:    close()
                case .timeline: step = .pitch
                // Without a trial funnel there are no earlier steps — back
                // from plans just closes.
                case .plans:    walkedTrialFunnel ? (step = .timeline) : close()
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
                            caption: explain("Your trial starts — a week's worth of talk, and all the review it produces."),
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
                // The plans differ in AMOUNT — that is the honest axis, and
                // pretending otherwise (purpose, level, "serious learners")
                // would send people to the wrong plan. But the label must not
                // grade the buyer: "heavy/light user" tells someone they are
                // the small one. So each card carries the SAME two rows in the
                // SAME order and units, and lets the reader compare.
                // This line is the only PITCH on the card — the rows below
                // already state the size, so a line that restates the size in
                // words ("talk at length, most days") is the meter reading
                // twice and sells nothing. It names the SITUATION the plan
                // suits.
                //
                // A situation, and deliberately not a PERSON. The tiers are
                // feature-identical, so "for experts / for beginners" promises
                // a difference that isn't there — and it misroutes: someone
                // prepping one interview needs ~90 minutes total and belongs
                // on Light, while a hobbyist who talks daily needs Plus.
                // Naming what you're DOING keeps the recognition and keeps the
                // claim true, because a deadline really does mean long daily
                // calls and habit-building really does mean short frequent
                // ones — the situations line up with the amounts. The label
                // must still never grade the buyer: no "heavy user", no
                // "serious learners".
                planCard(tier: "plus",
                         audience: explain("Get fluent for an exam or interview"),
                         name: AccountStatus.tierName("plus"))
                planCard(tier: "light",
                         audience: explain("Keep it up as a habit"),
                         name: AccountStatus.tierName("light"))
            }

            // Nothing between the cards and the legal block. There used to be
            // a sentence ("both refill every billing period" — now carried by
            // the "/mo" on each figure) and an "Always free" box, whose three
            // items are rows on the cards themselves now. Everything the
            // buyer is choosing between is inside the thing they tap.

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

    /// Talk minutes, as a plan card prints them.
    ///
    /// **Both tiers use MINUTES**, deliberately. The big figure used to switch
    /// to hours ("30 hours" beside Light's "150 min"), which made the two
    /// cards non-comparable at the exact moment the reader is comparing them —
    /// nobody divides 30 by 2.5 in their head, and a plan picker whose whole
    /// job is one ratio must not hide it behind a unit change.
    ///
    /// The reason hours were reached for was real, and is handled here
    /// instead: an interpolated `Int` is grouped by the FORMATTING locale, so
    /// a German-grouped "1.800" inside a Korean sentence reads as one point
    /// eight. Grouping explicitly in the learner's own language fixes that
    /// without touching the unit.
    private func minutesLabel(_ minutes: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: LanguageCatalog.currentNative)
        let grouped = f.string(from: NSNumber(value: minutes)) ?? "\(minutes)"
        // The PERIOD rides on the figure. It used to sit in a sentence under
        // the cards ("both refill every billing period"), which is a thing
        // nobody reads and which left "1,800 min" period-less on the card
        // itself. It also does the work of showing that the pool is the same
        // on the annual cycle — only the price below it changes.
        return explain("\(grouped) min/mo")
    }

    /// One line of a card's spec block. Label left, figure right — the same
    /// labels in the same order on both cards, so the eye compares down the
    /// column instead of parsing two sentences.
    ///
    /// `note` is a smaller line UNDER the figure, for the one row that needs
    /// converting: a month is the unit the plan is sold in, but nobody has an
    /// instinct for what 1,800 minutes feels like. It is a size cue, not a
    /// rule — the pool has no daily limit, which is why this sits under the
    /// monthly figure as an aside rather than replacing it.
    private func specRow(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .layoutPriority(1)
        }
    }

    /// "about 5 min a day" — what the month's pool works out to per day, from
    /// the catalog's own `daily_seconds`, which the migration defines as
    /// `monthly_seconds / 30` and exists for exactly this line. Falls back to
    /// the division so an older catalog row still prints something true.
    private func perDayLabel(_ opt: StoreKitService.PlanOption?) -> String? {
        guard let plan = opt?.plan else { return nil }
        let seconds = plan.daily_seconds ?? (plan.monthly_seconds.map { $0 / 30 } ?? 0)
        guard seconds > 0 else { return nil }
        if seconds >= 3600 {
            return explain("about \(seconds / 3600) hr a day")
        }
        return explain("about \(seconds / 60) min a day")
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
        // Live prices decide the badge — nothing else may. A hardcoded
        // fallback would claim a savings percentage computed from numbers the
        // viewer is never shown, on a card whose price field is blank.
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
    /// The plan's monthly pools, as the card prints them. Nil where the
    /// catalog hasn't loaded — a card with no numbers is better than a card
    /// with guessed ones.
    private func pools(_ opt: StoreKitService.PlanOption?) -> (minutes: Int, scenes: Int)? {
        guard let seconds = opt?.plan.monthly_seconds, seconds > 0,
              let scenes = opt?.plan.monthly_scenes else { return nil }
        return (seconds / 60, scenes)
    }

    private func planCard(tier: String, audience: String, name: String) -> some View {
        let opt = option(tier: tier)
        let isSelected = selectedTier == tier
        let isCurrent = isCurrentPlan(tier: tier, period: period)
        let pool = pools(opt)
        return Button {
            selectedTier = tier
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.title3.weight(.bold))
                        // A filled capsule reads as an award — it ranked the
                        // plans on one axis and made the smaller one look
                        // like less. This is a quiet line that says who the
                        // plan is for. For the plan already held, WHICH ONE
                        // IT IS outranks that question.
                        Text(isCurrent ? explain("Current plan") : audience)
                            .font(.caption.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(.tint)
                                                       : AnyShapeStyle(Color.secondary))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .font(.title3)
                }
                // Everything the plan holds, in one list: the two metered
                // pools with their sizes, then the two that aren't metered at
                // all. They used to be split — sizes on the card, "Always
                // free" in a box underneath — which asked the reader to
                // assemble the offer from two places and made the free half
                // look like a consolation prize rather than part of what they
                // are buying. Both tiers carry all four rows; the last two are
                // identical by design, because they really are the same.
                if let pool {
                    VStack(spacing: 6) {
                        specRow(explain("Talking"), minutesLabel(pool.minutes),
                                note: perDayLabel(opt))
                        specRow(explain("Watch scenes"), explain("\(pool.scenes)/mo"))
                        specRow(explain("Your own review book"), explain("Unlimited"))
                        specRow(explain("Shadowing · words · replays · drills"),
                                explain("Unlimited"))
                    }
                }
                // No placeholder when StoreKit hasn't priced it: a dash reads
                // as a broken field, and an absent price says the same thing
                // more quietly. The whole ROW goes with it — an HStack of two
                // absent children still takes the VStack's spacing, which
                // left a card with unexplained air under its figures.
                if let price = displayPrice(opt) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(price) / \(period.cycleNoun)")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        if period == .annual, let saved = annualSavingsPercent(tier: tier) {
                            Text(explain("Save \(saved)% vs monthly"))
                                .font(.caption.weight(.semibold))
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
                set: { if !$0 { store.purchaseState = .idle; close() } })
    }

    private var failedBinding: Binding<Bool> {
        Binding(get: {
            if case .failed = store.purchaseState { return true }
            return false
        }, set: { if !$0 { store.purchaseState = .idle } })
    }
}

/// Onboarding's last step: the plans, once, right after the voice exists.
///
/// The choice was always being asked — just later, and from behind something.
/// Under the hard paywall the first tap on Talk cannot succeed without a
/// subscription, so the paywall arrived on top of a call screen that then had
/// to be dismissed, or on Watch after a whole scene had been written. Asking
/// here costs the learner nothing extra and asks at the one moment they have
/// just heard their own voice speak the language fluently.
///
/// Skippable, and the flag is set on BOTH exits — the same rule the daily-call
/// step follows. A paywall with no way past it is a wall, and the app still
/// has plenty to show someone who says not yet.
struct OnboardingPaywallView: View {
    @AppStorage("futurevoice.paywall.onboarded") private var onboarded = false

    /// Nil while the account is still being asked. Nobody who already pays —
    /// or who still has minutes in the pool — is shown a pitch, which is what
    /// keeps the update that adds this step from ambushing existing installs
    /// with a screen selling them what they hold.
    @State private var shows: Bool?

    var body: some View {
        Group {
            if shows == true {
                PaywallView(onClose: { onboarded = true })
            } else {
                // The same blank hold RootView's auth gate uses: never a
                // flash of a pitch at someone who isn't going to be shown one.
                Color(.systemBackground).ignoresSafeArea()
            }
        }
        .task {
            guard shows == nil else { return }
            let blocked = await BillingGate.shared.blocks()
            shows = blocked
            // Couldn't ask, or nothing to sell — step aside for good. A
            // failed lookup must not park the learner on a paywall forever;
            // the first paid tap asks the server again anyway.
            if !blocked { onboarded = true }
        }
    }
}
