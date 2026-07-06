import SwiftUI
import UserNotifications

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
    @State private var selectedTier: String = "premium"

    enum Step { case pitch, timeline, plans }

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
    private var showsTrial: Bool { offerTrial && store.trialEligible }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
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
            Text("Your subscription is active. Credits land on your account as soon as Apple confirms the purchase.")
        }
        .alert("Purchase failed", isPresented: failedBinding) {
            Button("OK") { store.purchaseState = .idle }
        } message: {
            if case .failed(let msg) = store.purchaseState { Text(msg) }
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
                case .plans:    Task { await purchaseSelected() }
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

            if step == .plans {
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("\(store.trialDays) days free. Cancel anytime.")
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
            return showsTrial && selectedOption?.trialDays != nil
                ? "Start my free \(store.trialDays)-day trial"
                : "Subscribe"
        }
    }

    // MARK: - Step 1 · Pitch

    private var pitchContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You, but fluent")
                    .font(.largeTitle.weight(.bold))
                Text("Everything Future Voice does, fueled up — in your own voice.")
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
                Text("We'll remind you before your trial ends.")
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

            Picker("Billing period", selection: $period) {
                ForEach(PlanPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                planCard(tier: "premium",
                         name: "Premium",
                         blurb: "Serious immersion — three times the credits.",
                         badge: "Best value")
                planCard(tier: "pro",
                         name: "Pro",
                         blurb: "Steady daily practice.",
                         badge: nil)
            }

            if store.options.allSatisfy({ $0.product == nil }) && !store.loading {
                Label("Prices load from the App Store — not available yet in this build.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Credits power voice synthesis and AI calls, and refill every cycle. Unused practice data never expires.")
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

    /// Rough conversation time per day this plan buys. A 10-minute talk costs
    /// ~45 credits (the CreditGuideView numbers, which mirror the server's
    /// priceFor) → ~4.5 credits per spoken minute.
    private func dailyTalkMinutes(credits: Int) -> Int {
        let days: Double
        switch period {
        case .weekly:  days = 7
        case .monthly: days = 30
        case .annual:  days = 365
        }
        return max(1, Int((Double(credits) / days / 4.5).rounded()))
    }

    private func option(tier: String) -> StoreKitService.PlanOption? {
        store.options.first { $0.plan.tier == tier && $0.plan.period == period.rawValue }
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
                    if let credits = opt?.plan.credits_per_cycle {
                        // Lead with what the credits MEAN — minutes of talking
                        // per day — and keep the raw number as the detail.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("≈ \(dailyTalkMinutes(credits: credits)) min of conversation a day")
                                .font(.footnote.weight(.semibold))
                            Text("\(credits.formatted()) credits / \(period.cycleNoun)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(opt?.localizedPrice.map { "\($0) / \(period.cycleNoun)" } ?? "—")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        content.body = "Your Future Voice trial converts in 2 days. Cancel anytime in the App Store."
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
