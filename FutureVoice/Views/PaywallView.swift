import SwiftUI
import UserNotifications
import Supabase

/// Three-step trial-first paywall (pitch → trial timeline → plan picker),
/// modeled on the Speak flow: sell the value, de-risk the trial, then show
/// prices last. Pure SwiftUI + system colors; prices and trial length come
/// live from StoreKit, credits-per-cycle from the server plan catalog.
struct PaywallView: View {
    /// Whether to pitch the free trial at all. Callers pass `false` when the
    /// user has already used their free credits (out-of-credits blocks, or a
    /// zero balance) — "Try for free" makes no sense to someone who's already
    /// spent the free tier, regardless of what Apple's intro-offer flag says
    /// (that only tracks subscription history, not credit usage).
    var offerTrial: Bool = true

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreKitService()

    @State private var step: Step = .pitch
    @State private var period: PlanPeriod = .annual
    @State private var selectedTier: String = "unlimited"

    // Beta subscription-preference survey (last step while `BetaConfig.isBeta`).
    // Answers are folded into one `beta_reviews` row so no migration is needed.
    @State private var surveyTier: String = "unlimited"    // unlimited | daily | none
    @State private var surveyPeriod: PlanPeriod = .monthly
    @State private var surveyComment: String = ""
    @State private var surveySubmitting = false
    @State private var surveySent = false
    @State private var surveyError: String?

    enum Step { case pitch, timeline, plans, survey }

    enum PlanPeriod: String, CaseIterable, Identifiable {
        case weekly, monthly, annual
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var cycleNoun: String {
            switch self {
            case .weekly: return "week"
            case .monthly: return "month"
            case .annual: return "year"
            }
        }
    }

    /// Show the trial funnel only when the caller allows it AND Apple still
    /// offers this account an intro offer. Either being false means: skip the
    /// pitch, open on plans, and say "Subscribe" instead of "Try for free".
    private var showsTrial: Bool { offerTrial && store.trialEligible && !BetaConfig.isBeta }

    /// During the beta the paywall can't sell, so it ends in a preference
    /// survey rather than a purchase. `.plans` → `.survey` → submit.
    private var showsSurvey: Bool { BetaConfig.collectsPreferenceSurvey }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case .pitch:    pitchContent
                    case .timeline: timelineContent
                    case .plans:    plansContent
                    case .survey:   surveyContent
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
            await store.load()
            // No trial to pitch (out of credits, zero balance, or Apple says
            // the intro offer is spent): skip the pitch and open on plans.
            if !showsTrial { step = .plans }
        }
        .onChange(of: store.purchaseState) { _, state in
            if state == .purchased, showsTrial {
                scheduleTrialEndingReminder(trialDays: store.trialDays)
            }
        }
        .alert("You're in", isPresented: purchasedBinding) {
            Button("Done") { dismiss() }
        } message: {
            Text(explain("Your subscription is active. Your talk time lands on your account as soon as Apple confirms the purchase."))
        }
        .alert("Purchase failed", isPresented: failedBinding) {
            Button("OK") { store.purchaseState = .idle }
        } message: {
            if case .failed(let msg) = store.purchaseState { Text(msg) }
        }
        .alert("Thank you", isPresented: $surveySent) {
            Button("Done") { dismiss() }
        } message: {
            Text(explain("Thanks — this shapes launch pricing. Keep reviewing your saved words, drills, and dialogues anytime — that stays free."))
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                switch step {
                case .pitch:    dismiss()
                case .timeline: step = .pitch
                // Without a trial funnel there are no earlier steps — back
                // from plans just closes.
                case .plans:    showsTrial ? (step = .timeline) : dismiss()
                case .survey:   step = .plans
                }
            } label: {
                Image(systemName: step == .pitch || (step == .plans && !showsTrial)
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
                case .pitch:    step = .timeline
                case .timeline: step = .plans
                case .plans:
                    if showsSurvey { step = .survey }
                    else { Task { await purchaseSelected() } }
                case .survey:   Task { await submitSurvey() }
                }
            } label: {
                Group {
                    if store.purchaseState == .purchasing || surveySubmitting {
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
            .disabled(store.purchaseState == .purchasing || surveySubmitting)

            if step == .plans && !showsSurvey {
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if step == .survey {
                Text(explain("Your answers go straight to the team building nawana."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if step != .plans {
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
        case .pitch:    return "Try for free"
        case .timeline: return "See plans"
        case .plans:
            if showsSurvey { return "Continue" }
            return showsTrial && selectedOption?.trialDays != nil
                ? "Start my free \(store.trialDays)-day trial"
                : "Subscribe"
        case .survey:
            return "Submit"
        }
    }

    // MARK: - Step 1 · Pitch

    private var pitchContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You, but fluent")
                    .font(.largeTitle.weight(.bold))
                Text(explain("Everything nawana does, fueled up — in your own voice."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 18) {
                featureRow("bubble.left.and.bubble.right.fill",
                           "Real conversations, your voice",
                           "Talk daily with your fluent self — every reply synthesized in your cloned voice.")
                featureRow("sparkles",
                           "Corrections that stick",
                           "Inline fixes become spaced-repetition drills, tuned to your mistakes.")
                featureRow("waveform.badge.mic",
                           "Pronunciation you can measure",
                           "Shadow any line, get a real score, watch the weekly trend.")
                featureRow("newspaper.fill",
                           "Topics from your real life",
                           "Scenarios from your world and this week's news in your interests.")
            }
        }
    }

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
                Text("\(store.trialDays) days free,\nno surprises")
                    .font(.largeTitle.weight(.bold))
                Text(explain("We'll remind you before your trial ends."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                timelineRow(icon: "lock.open.fill", tint: .accentColor,
                            title: "Today",
                            caption: "Full access unlocked — talk, shadow, and drill with your fluent self.",
                            showsLine: true)
                timelineRow(icon: "bell.fill", tint: .accentColor,
                            title: "Day \(max(1, store.trialDays - 2))",
                            caption: "We send a reminder that your trial is about to end.",
                            showsLine: true)
                timelineRow(icon: "crown.fill", tint: .accentColor,
                            title: "Day \(store.trialDays)",
                            caption: "Your subscription starts. Cancel anytime before in the App Store.",
                            showsLine: false)
            }
        }
    }

    private func timelineRow(icon: String, tint: Color, title: String,
                             caption: String, showsLine: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                if showsLine {
                    Rectangle()
                        .fill(tint.opacity(0.5))
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
            Text("Pick your pace")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 12)

            if showsSurvey {
                Label("You're in the beta — subscriptions aren't live yet. Your starting talk time is final, but reviewing always stays free. Tell us what you'd want at launch on the next step.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Billing period", selection: $period) {
                ForEach(PlanPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                // Tier = amount of talk time, not features — the names say
                // the quantity so the plans read as phone-plan sizes.
                planCard(tier: "unlimited",
                         name: "Unlimited",
                         blurb: "Talk as much as you want — calls, Watch scenes, and shadowing without watching a meter.",
                         badge: "Best for launch")
                planCard(tier: "daily",
                         name: "Daily",
                         blurb: "A light daily habit — about five minutes of talk a day.",
                         badge: nil)
            }

            if store.options.allSatisfy({ $0.localizedPrice == nil }) && !store.loading {
                Label("Prices load from the App Store — not available yet in this build.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.options.allSatisfy({ $0.product == nil }) {
                Label("Planned launch pricing — final prices confirm on the App Store at launch.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(explain("Your minutes buy talk time with your fluent self, and reset every day at midnight. Reviewing, replays, drills, and progress stay free forever."))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Always free")
                    .font(.footnote.weight(.semibold))
                freeRow("repeat", "Replay shadow lines", "Loop and slow down cached audio.")
                freeRow("rectangle.stack.fill", "Review drills", "Spaced repetition, graded on device.")
                freeRow("play.rectangle.on.rectangle", "Re-watch dialogues", "Generated once, then cached.")
            }
            .padding(.top, 4)
        }
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
    private func dailyTalkMinutes(seconds: Int) -> Int {
        max(1, seconds / 60)
    }

    private func option(tier: String) -> StoreKitService.PlanOption? {
        store.options.first { $0.plan.tier == tier && $0.plan.period == period.rawValue }
    }

    /// Percentage the annual plan saves versus paying monthly for a year, for
    /// one tier. nil when either price is unknown or annual isn't cheaper.
    private func annualSavingsPercent(tier: String) -> Int? {
        // Prefer live prices; fall back to the planned price map so the badge
        // still shows in the beta build, where StoreKit has no products.
        let monthly = store.options
            .first(where: { $0.plan.tier == tier && $0.plan.period == "monthly" })?.priceValue
            ?? StoreKitService.PlanOption.plannedPriceValue["\(tier)_monthly"]
        let annual = store.options
            .first(where: { $0.plan.tier == tier && $0.plan.period == "annual" })?.priceValue
            ?? StoreKitService.PlanOption.plannedPriceValue["\(tier)_annual"]
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
    private func planCard(tier: String, name: String, blurb: String, badge: String?) -> some View {
        let opt = option(tier: tier)
        let isSelected = selectedTier == tier
        Button {
            selectedTier = tier
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let badge {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(Color(.systemBackground))
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                Text(name).font(.title3.weight(.bold))
                Text(blurb).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    if let capSeconds = opt?.plan.daily_seconds {
                        // The plan IS a daily allowance — say exactly that.
                        Text("\(dailyTalkMinutes(seconds: capSeconds)) min of talk a day")
                            .font(.footnote.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(opt?.localizedPrice.map { "\($0) / \(period.cycleNoun)" } ?? "—")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if period == .annual, let saved = annualSavingsPercent(tier: tier) {
                            Text("Save \(saved)% vs monthly")
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
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4 · Beta preference survey (WTP with price anchors)

    /// Planned launch stickers shown in the survey so answers are real WTP,
    /// not abstract tier names. Keep in sync with `StoreKitService.plannedPrice`
    /// and docs/launch-billing.md.
    private func surveyPriceLabel(tier: String, period: PlanPeriod) -> String {
        let key = "\(tier)_\(period.rawValue)"
        return StoreKitService.PlanOption.plannedPrice[key] ?? "—"
    }

    private var surveyContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Help set the price")
                    .font(.largeTitle.weight(.bold))
                Text(explain("No charge during the beta. Looking at the planned launch prices, which would you actually subscribe to?"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            surveyGroup("Which plan?") {
                VStack(spacing: 10) {
                    surveyTierRow(tier: "unlimited",
                                  name: "Unlimited",
                                  detail: "Talk as much as you want, every day")
                    surveyTierRow(tier: "daily",
                                  name: "Daily",
                                  detail: "Light habit — ~5 min of talk a day")
                    surveyTierRow(tier: "none",
                                  name: "Neither",
                                  detail: "Too expensive or not for me")
                }
            }

            if surveyTier != "none" {
                // Monthly + annual only — weekly has no locked sticker price yet
                // (impulse SKU). Cleaner WTP signal for launch.
                surveyGroup("How would you pay?") {
                    Picker("Billing", selection: $surveyPeriod) {
                        Text(PlanPeriod.monthly.label).tag(PlanPeriod.monthly)
                        Text(PlanPeriod.annual.label).tag(PlanPeriod.annual)
                    }
                    .pickerStyle(.segmented)

                    Text("Selected: \(surveyPriceLabel(tier: surveyTier, period: surveyPeriod)) / \(surveyPeriod.cycleNoun)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            surveyGroup("Anything we should know? (optional)") {
                TextEditor(text: $surveyComment)
                    .frame(minHeight: 90)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground)))
            }

            if let surveyError {
                Label(surveyError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Label("Reviewing your saved words, drills, and dialogues stays free during the beta.",
                  systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    private func surveyTierRow(tier: String, name: String, detail: String) -> some View {
        let isSelected = surveyTier == tier
        let price: String = {
            guard tier != "none" else { return "" }
            return surveyPriceLabel(tier: tier, period: surveyPeriod)
        }()
        return Button {
            surveyTier = tier
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name).font(.body.weight(.semibold))
                        Spacer()
                        if !price.isEmpty {
                            Text(price)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func surveyGroup<Content: View>(_ title: String,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    /// Fold the answers into one `beta_reviews` row. Reuses the existing
    /// table (context + free-text body) so there's no schema migration.
    private func submitSurvey() async {
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            surveyError = "You need to be signed in."
            return
        }
        surveySubmitting = true
        surveyError = nil
        defer { surveySubmitting = false }

        struct Row: Encodable {
            let user_id: String
            let context: String
            let rating: Int?
            let body: String
        }
        let note = surveyComment.trimmingCharacters(in: .whitespacesAndNewlines)
        // Include the price anchor the user saw so we can re-read WTP later
        // even if list prices change.
        let priceSeen = surveyTier == "none"
            ? "n/a"
            : surveyPriceLabel(tier: surveyTier, period: surveyPeriod)
        let body = "tier=\(surveyTier); period=\(surveyPeriod.rawValue); price=\(priceSeen)"
            + (note.isEmpty ? "" : "; note=\(note)")
        do {
            try await SupabaseProvider.shared
                .from("beta_reviews")
                .insert(Row(user_id: session.user.id.uuidString,
                            context: "subscription_survey",
                            rating: nil,
                            body: body))
                .execute()
            surveySent = true
        } catch {
            surveyError = "Couldn't send — please try again."
        }
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
