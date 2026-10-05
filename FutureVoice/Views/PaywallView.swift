import SwiftUI
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

    /// Where this sheet was opened from ("onboarding", "after_first_call", …),
    /// stamped on every `paywall_*` event. Until 2026-09-21 the paywall logged
    /// nothing at all, so "saw the plans and said no" and "never saw them"
    /// read identically — which is how onboarding's paywall skipped itself
    /// for every new account for days without a single row saying so.
    private let source: String

    init(source: String = "other", onClose: (() -> Void)? = nil,
         preselectTier: String? = nil) {
        self.source = source
        self.onClose = onClose
        self.preselectTier = preselectTier
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var store = StoreKitService()
    /// The one-time minute pack, offered on the ladder to someone with no
    /// plan (2026-10-02).
    @StateObject private var packStore = TalkTopUpService()
    /// The ladder's selection highlight is ONE shape that moves between rows
    /// (`matchedGeometryEffect`), so picking a plan reads as the highlight
    /// sliding to it rather than one row going dark and another lighting up.
    @Namespace private var ladderSelection

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
    /// Apple's offer-code sheet takes seconds to appear (it loads the
    /// store page inside itself, and a blank sheet is all the learner sees
    /// meanwhile). The button says it is opening so the tap isn't judged dead.
    @State private var openingCodeSheet = false
    /// When the first real step was drawn — nil while `.resolving`, so a
    /// sheet closed before it showed anything reports `seen: 0`.
    @State private var shownAt: Date?
    @State private var furthestStep: Step = .resolving
    @State private var didPurchase = false

    /// `.resolving` is the state before StoreKit and the account snapshot
    /// have answered. Without it the sheet opened on `.pitch` and jumped to
    /// `.plans` a beat later — a "Try for free" pitch flashed at people who
    /// already pay us.
    enum Step {
        case resolving, pitch, timeline, plans

        /// Telemetry label, and the order the funnel walks in.
        var name: String {
            switch self {
            case .resolving: return "resolving"
            case .pitch:     return "pitch"
            case .timeline:  return "timeline"
            case .plans:     return "plans"
            }
        }
        var rank: Int {
            switch self {
            case .resolving: return 0
            case .pitch:     return 1
            case .timeline:  return 2
            case .plans:     return 3
            }
        }
    }

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
            async let pack: Void = packStore.load()
            async let snapshot = AccountStatus.fetch()
            _ = await products
            _ = await pack
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
            // …but never onto a period that is no longer sold. With the picker
            // hidden (one period) its `onChange` clamp never fires, so a
            // subscriber holding last month's annual plan would render cards
            // with no prices and no pool rows on them.
            if !availablePeriods.contains(period), let first = availablePeriods.first {
                period = first
            }
            // Pitch the trial only to someone who could actually take it:
            // not a current subscriber, not during the beta, and only while
            // Apple still offers this account an intro offer.
            step = walkedTrialFunnel ? .pitch : .plans
            #if DEBUG
            // Screenshot harness: the plan cards are two taps in, and a
            // capture run can't tap. Never reachable outside `-capture`.
            let capture = UserDefaults.standard.string(forKey: "capture")
            if capture == "paywall-plans" || Self.seededCapture != nil {
                step = .plans
            }
            if capture == "paywall-max" { selectedTier = "max" }
            if capture?.contains("-yearly") == true { period = .annual }
            if capture?.hasSuffix("-pack") == true { selectedTier = "pack" }
            if capture?.hasSuffix("-light") == true { selectedTier = "light" }
            if capture?.hasSuffix("-max") == true { selectedTier = "max" }
            if capture == "paywall-ladder-anim" {
                // Walks the highlight down the ladder and back, for a screen
                // recording of the slide. Capture runs can't tap.
                Task {
                    for tier in ["light", "plus", "max", "pack", "max", "plus"] {
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                        select(tier)
                    }
                }
            }
            #endif
            shownAt = Date()
            track("paywall_shown", [
                "trial_eligible": showsTrial ? "1" : "0",
                "subscriber": isSubscriber ? "1" : "0",
                "products": String(store.options.filter { $0.product != nil }.count),
            ])
        }
        .onChange(of: step) { old, new in
            // The first step is `paywall_shown`; this is every move after it.
            guard old != .resolving else { furthestStep = new; return }
            if new.rank > furthestStep.rank { furthestStep = new }
            track("paywall_step", ["from": old.name])
        }
        .onDisappear {
            // Every exit lands here — the close button, a swipe, the
            // purchase alert's Done, onboarding moving on.
            let seen = shownAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
            track("paywall_closed", [
                "outcome": didPurchase ? "purchased" : "dismissed",
                "furthest": furthestStep.name,
                "seen_s": String(seen),
            ])
        }
        .onChange(of: store.purchaseState) { _, state in
            if state == .purchased, showsTrial {
                Task { await TrialReminder.schedule(trialDays: store.trialDays) }
            }
        }
        .alert(Text(explain("You're in")), isPresented: purchasedBinding) {
            Button(explain("Done")) { close() }
        } message: {
            if showsTrial, let trialMinutes = store.trialTalkMinutes {
                Text(explain("Your trial is on: \(trialMinutes) minutes of talk over the next \(store.trialDays) days. Your plan's own monthly talk time starts when the trial converts."))
            } else {
                Text(explain("Your subscription is active. Your talk time lands on your account as soon as Apple confirms the purchase."))
            }
        }
        .alert(Text(explain("\(packStore.pack?.minutes ?? 50) minutes added")), isPresented: packPurchasedBinding) {
            Button(explain("Done")) { close() }
        } message: {
            Text(explain("They're on your account now. Start a call whenever you like."))
        }
        .alert(Text(explain("Purchase failed")), isPresented: packFailedBinding) {
            Button(explain("OK")) { packStore.state = .idle }
        } message: {
            if case .failed(let msg) = packStore.state { Text(msg) }
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
                    if selectedTier == "pack" { Task { await purchasePack() } }
                    else if selectionIsCurrentPlan { openURL(Self.manageSubscriptionsURL) }
                    else { Task { await purchaseSelected() } }
                }
            } label: {
                Group {
                    if store.purchaseState == .purchasing || packStore.state == .purchasing {
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
            .disabled(store.purchaseState == .purchasing || packStore.state == .purchasing)
            .opacity(step == .resolving ? 0 : 1)
            .allowsHitTesting(step != .resolving)

            if step == .plans {
                HStack(spacing: 18) {
                    Button(explain("Restore purchases")) {
                        track("paywall_restore_tapped")
                        Task { await store.restore() }
                    }
                    // Beta testers and the waitlist were mailed one-time
                    // App Store offer codes (docs/launch-billing.md §7).
                    // The mail's link opens the same sheet; this is for the
                    // person who opened the app first.
                    Button {
                        guard !openingCodeSheet else { return }
                        track("paywall_code_tapped")
                        openingCodeSheet = true
                        Task {
                            await StoreKitService.presentOfferCodeSheet()
                            openingCodeSheet = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if openingCodeSheet {
                                ProgressView().controlSize(.mini)
                                Text(explain("Opening the App Store…"))
                            } else {
                                Text(explain("Have a code?"))
                            }
                        }
                    }
                    .disabled(openingCodeSheet)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if step != .resolving {
                Text(store.trialTalkMinutes.map {
                    explain("\(store.trialDays) days free with \($0) min of talk. Cancel anytime.")
                } ?? explain("\(store.trialDays) days free. Cancel anytime."))
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
            if selectedTier == "pack" {
                return explain("Buy \(packStore.pack?.minutes ?? 50) minutes")
            }
            if selectionIsCurrentPlan { return explain("Manage subscription") }
            let name = AccountStatus.tierName(selectedTier)
            if isSubscriber { return explain("Change to \(name)") }
            if showsTrial && selectedOption?.trialDays != nil {
                return explain("Start my free \(store.trialDays)-day trial")
            }
            return period == .annual
                ? explain("Subscribe to \(name) · yearly")
                : explain("Subscribe to \(name) · monthly")
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
                // Ordered by importance: the call is the product, the daily
                // call is what makes "every day" credible, then the two
                // rehearse/review halves, then measurement.
                featureRow("bubble.left.and.bubble.right.fill",
                           explain("Real conversations, your voice"),
                           explain("Talk with your fluent self like a live phone call — every reply in your cloned voice."))
                featureRow("phone.fill",
                           explain("Your fluent self calls first"),
                           explain("Pick a time and the phone rings. Miss it, and a voicemail with a question waits for you."))
                featureRow("play.rectangle.on.rectangle.fill",
                           explain("Rehearse before it happens"),
                           explain("Describe what's coming and watch your fluent self handle it first — its expressions stay yours to study."))
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

    /// The day the "it converts soon" notice fires, counting the purchase as
    /// day 1 — nil when it collides with a row the timeline already draws.
    private var reminderDay: Int? {
        let days = store.trialDays
        let day = days - TrialReminder.leadDays(forTrialDays: days)
        return (2..<days).contains(day) ? day : nil
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(explain("\(store.trialDays) days free, no surprises"))
                    .font(.largeTitle.weight(.bold))
                Text(explain("We'll remind you before it converts, and the date is always in Me → Talk time."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                // The trial's SIZE goes here, before anyone taps: it is
                // 35 minutes for the whole trial, not the plan's pool, and a
                // learner who first meets that number when it runs out reads
                // the stop as a paywall (2026-09-25).
                timelineRow(icon: "lock.open.fill",
                            title: explain("Today"),
                            caption: store.trialTalkMinutes.map {
                                explain("Your trial starts: \($0) minutes of talk to use across the \(store.trialDays) days, and all the review it produces.")
                            } ?? explain("Your trial starts — talk time on us, and all the review it produces."),
                            showsLine: true)
                // The reminder's own day, from the one place that decides it.
                // Dropped when it has nowhere of its own to sit: on a short
                // trial the notice can land on the day the trial starts or
                // the day it ends, and a row repeating "Today" or the last
                // row reads as a mistake rather than a schedule.
                if let day = reminderDay {
                    timelineRow(icon: "bell.fill",
                                title: explain("Day \(day)"),
                                caption: explain("A reminder that your trial is about to convert — we ask to send notifications when the trial starts."),
                                showsLine: true)
                }
                timelineRow(icon: "crown.fill",
                            title: explain("Day \(store.trialDays)"),
                            caption: explain("Your subscription starts, and its own monthly talk time with it. Cancel any time before then in the App Store."),
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
    //
    // One LADDER, smallest first, one line per plan (2026-10-02, founder:
    // "make it easy to compare"). The card layout it replaced spent half of
    // every card on two rows that were identical on all of them, and three
    // cards plus a pack needed two screens of scrolling to compare. Now the
    // whole choice is on one screen and comparing is a glance down a column:
    // each row carries its minutes, its scenes on a line of their own, the
    // price, and the price PER MINUTE — the one number that says what a bigger
    // plan buys. What every plan shares is said once, under the ladder.
    //
    // The one-time pack sits in its own group ("extra minutes"): a different
    // kind of purchase from the plans, bought before one or on top of one.
    // No size bars — tried the same day and read as a second, competing
    // number; the per-minute price is the comparison.

    private var plansContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isSubscriber ? explain("Your plan") : explain("Keep talking"))
                    .font(.largeTitle.weight(.bold))
                if isSubscriber {
                    Label(account.isTrialing
                          ? (account.cancelAtPeriodEnd
                             ? explain("You're on the \(currentPlanLabel) — it ends on \(account.renewalLabel).")
                             : explain("You're on the \(currentPlanLabel) — it converts unless you cancel."))
                          : explain("You're subscribed to \(currentPlanLabel)."),
                          systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(explain("Pick how much you want to talk each month."))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)

            if availablePeriods.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    // The segment says only the period: "Jährlich · 2 Monate
                    // kostenlos" did not fit half a segmented control. The
                    // saving sits on each row, where "a year" would be.
                    Picker(explain("Billing period"), selection: $period) {
                        ForEach(availablePeriods) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: availablePeriods) { _, periods in
                        if !periods.contains(period), let first = periods.first { period = first }
                    }
                    .onChange(of: period) { _, now in
                        // Max was picked on the monthly side and has no yearly
                        // product: the highlight moves to the biggest tier that does.
                        guard selectedTier != "pack", option(tier: selectedTier) == nil else { return }
                        let fallback = shownTiers.last { t in
                            store.options.contains { $0.plan.tier == t && $0.plan.period == now.rawValue }
                        }
                        if let fallback { select(fallback) }
                    }
                }
            }

            ladderGroup {
                ForEach(Array(shownTiers.enumerated()), id: \.element) { i, tier in
                    if i > 0 { Divider().padding(.leading, 52) }
                    ladderRow(tier: tier)
                }
            }

            if showsPack, let pack = packStore.pack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explain("Extra minutes"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    ladderGroup { packRow(pack) }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(explain("Review book, shadowing, words, replays and drills are unlimited on every plan."),
                      systemImage: "checkmark.circle")
                Label(explain("A 10-minute tutor call every weekday is about 200 minutes a month. Here, minutes count only while the conversation is going — pauses are free."),
                      systemImage: "phone")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)

            subscriptionLegal
        }
    }

    /// The tier most people actually bought — a FACT the row can state, which
    /// is why it says "most chosen" and never "recommended" (an opinion that
    /// would need a reason). Measured 2026-10-02: Plus was the first paid plan
    /// of 6 of 9 subscribers and 23 of 35 charges in the last 30 days. Text in
    /// the tint, like "Current plan" — a filled capsule reads as an award and
    /// makes the other plans look like less. Re-check the count before moving
    /// it; never put it on a tier nobody has bought.
    static let mostChosenTier = "plus"

    /// Every tier the catalog sells, smallest first. A tier with no product
    /// in the selected period still shows (as "monthly only") so the ladder
    /// keeps its shape when the period flips.
    private var shownTiers: [String] {
        let sold = AccountStatus.tierOrder.filter { tier in
            store.options.contains { $0.plan.tier == tier }
        }
        return sold.isEmpty ? ["light", "plus"] : sold
    }

    /// The pack is for anyone — before a plan, or on top of one. Not for the
    /// few grandfathered uncapped rows, whose meter never spends a balance.
    /// Loaded alongside the catalog; draws only with a live price.
    private var showsPack: Bool { !account.isUncappedTalk && packPrice != nil }

    private var packPrice: Price? {
        #if DEBUG
        if Self.seededCapture != nil {
            return Price(value: Self.seededKorean ? 5900 : 4.99, style: Self.seededStyle)
        }
        #endif
        guard let product = packStore.pack?.product else { return nil }
        return Price(value: product.price, style: product.priceFormatStyle)
    }

    private func ladderGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
    }

    /// The whole row, lit: a tinted fill and an accent edge, drawn only under
    /// the selected row and matched across rows so it slides.
    @ViewBuilder
    private func selectionHighlight(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2))
                .matchedGeometryEffect(id: "selection", in: ladderSelection)
        }
    }

    /// Ease, not a spring: the UI rules allow subtle motion only.
    private func select(_ tier: String) {
        withAnimation(.easeInOut(duration: 0.28)) { selectedTier = tier }
    }

    private func radio(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.6)))
            .frame(width: 28)
    }

    /// One line of the ladder: name and minutes, a bar for the size, the
    /// per-day cue and scenes, the price and the price per minute.
    private func ladderRow(tier: String) -> some View {
        let opt = option(tier: tier)
        let monthlyOnly = opt == nil && period == .annual
        let shown = opt ?? store.options.first { $0.plan.tier == tier && $0.plan.period == "monthly" }
        let minutes = (shown?.plan.monthly_seconds ?? 0) / 60
        let scenes = shown?.plan.monthly_scenes ?? 0
        let perDay = minutes / 30
        let on = selectedTier == tier && !monthlyOnly
        let isCurrent = isCurrentPlan(tier: tier, period: period)
        let price = priceOf(shown)
        return Button {
            select(tier)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                radio(on)
                VStack(alignment: .leading, spacing: 5) {
                    // The tag rides ABOVE the name, on a line of its own: beside
                    // it, "Am häufigsten gewählt" pushed "Plus 600 Min." onto
                    // two lines (measured in de/fr, 2026-10-02).
                    if isCurrent {
                        Text(explain("Current plan"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    } else if tier == Self.mostChosenTier {
                        Text(explain("Most chosen"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    HStack(spacing: 6) {
                        Text(AccountStatus.tierName(tier)).font(.headline)
                        if isUncappedTalk(shown) {
                            Text(explain("No limit")).font(.headline)
                        } else if minutes > 0 {
                            Text(explain("\(grouped(minutes)) min")).font(.headline).monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    if scenes > 0 {
                        Text(explain("+ \(scenes) scenes"))
                            .font(.subheadline.weight(.medium))
                    }
                    // Writing Speech scripts (AI or your own) is these tiers'
                    // alone — the same rule `canWriteSpeechScripts` enforces,
                    // so the row can't promise what the tab then refuses.
                    if ["plus", "max"].contains(tier) {
                        Text(explain("+ Speech"))
                            .font(.subheadline.weight(.medium))
                    }
                    if perDay > 0 {
                        Text(explain("about \(perDay) min a day"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if monthlyOnly {
                        Text(explain("Monthly only")).font(.caption).foregroundStyle(.secondary)
                    } else if let price {
                        Text(price.formatted).font(.headline).monospacedDigit()
                        if period == .annual, let saving = annualSavingLabel(tier: tier) {
                            Text(saving)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Text(period == .annual ? explain("a year") : explain("a month"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if minutes > 0 {
                            Text(perMinuteLabel(price, minutes: period == .annual ? minutes * 12 : minutes))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .opacity(monthlyOnly ? 0.55 : 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background { selectionHighlight(on) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A tier with no yearly product is shown so the ladder keeps its
        // shape, but it can't be picked on the yearly side (founder, 2026-10-02).
        .disabled(monthlyOnly)
    }

    private func packRow(_ pack: TalkTopUpService.Pack) -> some View {
        let on = selectedTier == "pack"
        return Button { select("pack") } label: {
            HStack(alignment: .center, spacing: 12) {
                radio(on)
                VStack(alignment: .leading, spacing: 5) {
                    Text(explain("\(pack.minutes) min")).font(.headline).monospacedDigit()
                    Text(explain("one time · no expiry"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(explain("Available with or without a plan"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let price = packPrice {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price.formatted).font(.headline).monospacedDigit()
                        Text(explain("once")).font(.caption2).foregroundStyle(.secondary)
                        Text(perMinuteLabel(price, minutes: pack.minutes))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background { selectionHighlight(on) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A price as the store states it, kept as a number so the ladder can
    /// divide it.
    struct Price {
        let value: Decimal
        let style: Decimal.FormatStyle.Currency
        var formatted: String { value.formatted(style) }
    }

    private func priceOf(_ opt: StoreKitService.PlanOption?) -> Price? {
        #if DEBUG
        if Self.seededCapture != nil, let opt {
            // The storefront a reviewer of the capture would be in: won for
            // a Korean app language, dollars otherwise.
            let table: [String: Decimal] = Self.seededKorean
                ? ["light_monthly": 15000, "plus_monthly": 29000, "max_monthly": 58000,
                   "light_annual": 149000, "plus_annual": 290000]
                : ["light_monthly": 9.99, "plus_monthly": 24.99, "max_monthly": 49.99,
                   "light_annual": 99.99, "plus_annual": 249.99]
            return table[opt.plan.id].map { Price(value: $0, style: Self.seededStyle) }
        }
        #endif
        guard let product = opt?.product else { return nil }
        return Price(value: product.price, style: product.priceFormatStyle)
    }

    /// "₩48 a min" / "$0.04 a min" — whole units where the currency's unit is
    /// already small (won, yen), two decimals where it isn't.
    private func perMinuteLabel(_ price: Price, minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        let each = price.value / Decimal(minutes)
        let text = each >= 1
            ? each.formatted(price.style.precision(.fractionLength(0)))
            : each.formatted(price.style.precision(.fractionLength(2)))
        return explain("\(text) a min")
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
    #if DEBUG
    /// Capture names that seed the catalog with US prices (a Debug build is
    /// never priced by StoreKit): `-capture paywall-max`, `paywall-ladder`,
    /// `paywall-ladder-yearly`, `paywall-ladder-pack`.
    static var seededKorean: Bool { LanguageCatalog.currentNative == "ko" }
    static var seededStyle: Decimal.FormatStyle.Currency {
        seededKorean ? .currency(code: "KRW").locale(Locale(identifier: "ko_KR"))
                     : .currency(code: "USD").locale(Locale(identifier: "en_US"))
    }

    static var seededCapture: String? {
        guard let c = UserDefaults.standard.string(forKey: "capture"),
              c.hasPrefix("paywall-max") || c.hasPrefix("paywall-ladder") else { return nil }
        return c
    }
    #endif

    /// Billing periods the picker offers: only those with a product actually
    /// on sale, so a SKU that doesn't exist in App Store Connect can't be
    /// selected into "This plan isn't available". With nothing loaded, the
    /// monthly period alone.
    private var availablePeriods: [PlanPeriod] {
        #if DEBUG
        if Self.seededCapture != nil { return [.monthly, .annual] }
        #endif
        let live = PlanPeriod.allCases.filter { p in
            store.options.contains { $0.plan.period == p.rawValue && $0.product != nil }
        }
        return live.isEmpty ? [.monthly] : live
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

    /// A figure grouped in the LEARNER's language, for any card number that
    /// can reach four digits.
    ///
    /// **Never interpolate such an `Int` straight into a localized string.**
    /// `%lld` is grouped by the RESOLVING locale, which follows the device
    /// region rather than the app language — that is how "공정 사용 월
    /// 1,800분" shipped as "1.800분", a German grouping inside a Korean
    /// sentence, where it reads as one point eight. Format here, pass the
    /// result in as `%@`.
    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: LanguageCatalog.currentNative)
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// True for a plan whose TALKING is not capped at all — none on sale
    /// since 2026-09-26, when Plus became a 300-minute pool and the tail
    /// moved to minute packs. Read from the catalog's own switch
    /// (`subscription_plans.talk_unlimited`, in the DB since 2026-08-21, so
    /// selecting it no longer risks emptying the catalog) rather than the
    /// tier: the tier no longer says anything about counting, and a card
    /// printing "No limit" over a pool the meter enforces is the ambush the
    /// rows exist to prevent. Kept as a branch so the catalog can sell an
    /// uncapped plan again with no app change.
    private func isUncappedTalk(_ opt: StoreKitService.PlanOption?) -> Bool {
        opt?.plan.talk_unlimited ?? false
    }

    private func option(tier: String) -> StoreKitService.PlanOption? {
        store.options.first { $0.plan.tier == tier && $0.plan.period == period.rawValue }
    }

    /// The annual saving, said the way the offer is actually built: **"2
    /// months free"** when a year costs a whole number of months less than
    /// paying monthly, and a percentage otherwise (2026-09-26). Months are
    /// what a buyer can check in their head; 17% is the same fact in a form
    /// nobody converts back. Both come from LIVE App Store prices, so the
    /// badge can never advertise a discount that isn't being charged.
    private func annualSavingLabel(tier: String) -> String? {
        guard let monthly = monthlyPrice(tier: tier), let annual = annualPrice(tier: tier),
              monthly > 0 else { return nil }
        let free = (monthly * 12 - annual) / monthly
        // Within a fifth of a month of a whole number — the rounding that
        // puts $199.99 beside $19.99 — is "2 months free"; anything else is
        // a shape the sentence would misdescribe, so it stays a percentage.
        let whole = (free).rounded()
        if whole >= 1, abs(free - whole) < 0.2 {
            return explain("\(Int(whole)) months free")
        }
        return annualSavingsPercent(tier: tier).map { explain("Save \($0)% vs monthly") }
    }

    private func monthlyPrice(tier: String) -> Double? {
        priceOf(store.options.first { $0.plan.tier == tier && $0.plan.period == "monthly" })
            .map { NSDecimalNumber(decimal: $0.value).doubleValue }
    }

    private func annualPrice(tier: String) -> Double? {
        priceOf(store.options.first { $0.plan.tier == tier && $0.plan.period == "annual" })
            .map { NSDecimalNumber(decimal: $0.value).doubleValue }
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

    // MARK: - Actions

    private func purchaseSelected() async {
        // Nothing to sell, and the button said "Subscribe" anyway. StoreKit
        // answering with no products leaves `selectedOption` nil while the
        // cards still draw (they come from the server catalog) — so the tap
        // returns here and, until 2026-09-24, logged NOTHING: the one moment
        // of highest intent in the app was the one moment invisible to us.
        // Four of the first thirteen accounts to see a paywall saw it with
        // `products: 0`, so this is not hypothetical.
        guard let opt = selectedOption else {
            track("paywall_purchase_unavailable",
                  ["tier": selectedTier, "period": period.rawValue,
                   "options": String(store.options.count)])
            OwnerPing.paywall(phase: "result", outcome: "unavailable",
                              plan: "\(selectedTier)_\(period.rawValue)",
                              trial: showsTrial, source: source, step: step.name)
            return
        }
        let plan = ["plan": opt.id, "trial": showsTrial ? "1" : "0"]
        track("paywall_purchase_tapped", plan)
        OwnerPing.paywall(phase: "tapped", option: opt, trial: showsTrial,
                          source: source, step: step.name)
        await store.purchase(opt)
        // `.idle` after a purchase is Apple's sheet cancelled (or an
        // unknown result StoreKit may add later) — the one outcome with no
        // state of its own.
        let outcome: String
        switch store.purchaseState {
        case .purchased: outcome = "purchased"; didPurchase = true
        case .failed:    outcome = "failed"
        case .idle, .purchasing: outcome = "cancelled"
        }
        track("paywall_purchase_result", plan.merging(["outcome": outcome]) { $1 })
        OwnerPing.paywall(phase: "result", outcome: outcome, option: opt,
                          trial: showsTrial, source: source, step: step.name)
    }

    /// The one-time pack. `TalkTopUpService` lands it on the server before
    /// finishing the transaction; the alert below says it arrived.
    private func purchasePack() async {
        let props = ["plan": packStore.pack?.productId ?? "pack", "trial": "0"]
        track("paywall_purchase_tapped", props)
        await packStore.purchase()
        let outcome: String
        switch packStore.state {
        case .purchased: outcome = "purchased"; didPurchase = true
        case .failed:    outcome = "failed"
        default:         outcome = "cancelled"
        }
        track("paywall_purchase_result", props.merging(["outcome": outcome]) { $1 })
    }

    /// One event, both sinks: PostHog for the funnel, `client_events` so a
    /// billing question can be answered next to `user_subscriptions` in SQL.
    private func track(_ event: String, _ extra: [String: String] = [:]) {
        var props = extra
        props["source"] = source
        props["step"] = step.name
        Telemetry.log(event, props)
        Analytics.capture(event, props)
    }

    /// Honor the timeline promise: a local reminder two days before the
    /// trial converts. Quietly skipped if notifications are denied.
    // MARK: - Bindings

    private var purchasedBinding: Binding<Bool> {
        Binding(get: { store.purchaseState == .purchased },
                set: { if !$0 { store.purchaseState = .idle; close() } })
    }

    private var packPurchasedBinding: Binding<Bool> {
        Binding(get: { packStore.state == .purchased },
                set: { if !$0 { packStore.state = .idle; close() } })
    }

    private var packFailedBinding: Binding<Bool> {
        Binding(get: {
            if case .failed = packStore.state { return true }
            return false
        }, set: { if !$0 { packStore.state = .idle } })
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
                PaywallView(source: "onboarding", onClose: { onboarded = true })
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
            if !blocked {
                onboarded = true
                // The skip is silent on screen, so it has to be loud here: a
                // free-call grant makes EVERY new account take this branch.
                let account = await BillingGate.shared.snapshot()
                let reason: String
                if let account {
                    reason = account.isEntitled ? "entitled"
                        : account.unlimited ? "unlimited"
                        : account.secondsBalance > 0 ? "balance" : "unknown"
                } else {
                    reason = "lookup_failed"
                }
                let props = ["reason": reason,
                             "balance_s": String(account?.secondsBalance ?? -1)]
                Telemetry.log("onboarding_paywall_skipped", props)
                Analytics.capture("onboarding_paywall_skipped", props)
            }
        }
    }
}
