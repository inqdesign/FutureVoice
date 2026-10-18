import StoreKit
import SwiftUI
import UIKit

/// Apple is waiting on the learner's consent before it charges (2026-10-18).
///
/// Korean law (in force 2025-02-14) asks for a SECOND consent before a free
/// trial or a discounted offer turns into the regular price, and Apple asks it
/// as a price increase: an email, a push, and an in-app sheet that StoreKit
/// raises by itself the moment the app is opened once it is time. Ignored, the
/// subscription is not charged and simply ends, with auto-renew still on.
/// Measured 2026-09-23: six Korean trialers reached their renewal, all six were
/// asked, four never answered and lapsed.
///
/// What was missing was OUR half of that moment. The system sheet appeared
/// with no context, wherever the learner happened to be (a call included), and
/// read "₩0 → ₩29,000, agree to the price increase?" to someone who had chosen
/// that plan a week earlier. So:
///
/// - The consent message is HELD (`Message.messages`): once the app listens,
///   StoreKit stops raising messages by itself. Every other kind of message is
///   shown at once, exactly as the system would have.
/// - The app's own sheet (`PriceConsentSheet`) says what this is first, then
///   opens Apple's sheet. Never during a call; at most once a day by itself.
/// - The state is read from StoreKit (`priceIncreaseStatus`), not from the
///   message: a held message can be spent, the status can't. Once Apple's own
///   sheet is gone, "Confirm" opens the subscription page in Settings, where
///   the same consent waits.
/// - Me shows a row for as long as it is pending.
///
/// The server keeps its own copy of the same fact (`apple-webhook` →
/// `user_subscriptions.price_consent_*`) for the reminder push two days before
/// the charge (`consent-reminder`) and for the admin console.
@MainActor
final class PriceConsent: ObservableObject {
    static let shared = PriceConsent()

    struct Pending: Equatable {
        /// Still in the free trial (the Korean case) or a running plan.
        let isTrial: Bool
        /// What the renewal will charge, formatted in its own currency.
        let price: String?
        /// When the charge that needs the consent would happen.
        let renewsAt: Date?
    }

    /// Non-nil while Apple is waiting on the learner.
    @Published private(set) var pending: Pending?
    /// The app's explanation sheet, raised by `offerIfDue` or a tap.
    @Published var showingSheet = false

    /// Apple's own consent sheet, held until the learner asks for it.
    private var heldMessage: Message?
    private var listener: Task<Void, Never>?

    private static let lastOfferedKey = "futurevoice.priceConsent.lastOffered"

    // MARK: - StoreKit messages

    /// Starts listening for StoreKit messages. Must run at launch: StoreKit
    /// delivers them as the app becomes active, and from the moment anything
    /// listens it no longer shows them by itself.
    func startMessageListener() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await message in Message.messages {
                guard let self else { return }
                if message.reason == .priceIncreaseConsent {
                    self.heldMessage = message
                    await self.refresh()
                    // StoreKit decided it is time; the status may not say so
                    // yet on this device, and the message is the proof.
                    if self.pending == nil {
                        self.pending = Pending(isTrial: false, price: nil, renewsAt: nil)
                    }
                    self.offerIfDue()
                } else {
                    // Not ours to hold: show it as the system would have.
                    if let scene = await Self.activeScene() {
                        try? await message.display(in: scene)
                    }
                }
            }
        }
    }

    // MARK: - State

    /// Reads whether any of our subscriptions is waiting on consent. Cheap and
    /// local; run on every foreground.
    func refresh() async {
        var found: Pending?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  transaction.productID.hasPrefix("com.roro.futurevoice."),
                  let status = await transaction.subscriptionStatus,
                  case .verified(let info) = status.renewalInfo,
                  info.priceIncreaseStatus == .pending else { continue }
            let price: String? = {
                guard let amount = info.renewalPrice, let currency = info.currency else { return nil }
                return amount.formatted(.currency(code: currency.identifier)
                    .locale(Locale(identifier: UILanguage.chromeLanguage)))
            }()
            found = Pending(isTrial: transaction.offerType == .introductory,
                            price: price,
                            renewsAt: info.renewalDate ?? transaction.expirationDate)
            break
        }
        if found == nil, heldMessage != nil {
            // Held message, status not visible (StoreKit cache): keep asking.
            found = pending ?? Pending(isTrial: false, price: nil, renewsAt: nil)
        }
        if pending != found { pending = found }
        if found == nil, showingSheet { showingSheet = false }
    }

    /// Raises the explanation by itself, at most once a day and never over a
    /// live call. A tap on the reminder push or the Me row opens it any time.
    func offerIfDue() {
        guard pending != nil, !showingSheet, !DailyCallScheduler.isLiveCall else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: Self.lastOfferedKey) as? Date,
           last >= today { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastOfferedKey)
        showingSheet = true
        Analytics.capture("price_consent_offered", ["held": heldMessage == nil ? "0" : "1"])
    }

    /// Opened from the push, the Me row or a deep link.
    func open() {
        showingSheet = true
    }

    // MARK: - Asking Apple

    /// Apple's own consent sheet if StoreKit handed one over, otherwise the
    /// subscription page in Settings, where the same consent is waiting.
    func confirm() async {
        guard let scene = await Self.activeScene() else { return }
        Analytics.capture("price_consent_confirm", ["held": heldMessage == nil ? "0" : "1"])
        if let message = heldMessage {
            heldMessage = nil
            try? await message.display(in: scene)
        } else {
            try? await AppStore.showManageSubscriptions(in: scene)
        }
        await refresh()
        if pending == nil { Analytics.capture("price_consent_agreed") }
    }

    /// The foreground scene, waiting a moment for one at launch.
    private static func activeScene() async -> UIWindowScene? {
        for _ in 0..<20 {
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                return scene
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }
}

/// What the consent is, before Apple's sheet asks for it.
struct PriceConsentSheet: View {
    @ObservedObject private var consent = PriceConsent.shared
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("One tap keeps your plan going")
                            .font(.title2.bold())
                        Text(consent.pending?.isTrial ?? true
                             ? "Before your free trial turns into your plan, Apple asks you to confirm it once more. Without it, the plan doesn't start."
                             : "Before your next renewal, Apple asks you to confirm it once more. Without it, the plan ends at the end of this period.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                if let pending = consent.pending, pending.price != nil || pending.renewsAt != nil {
                    Section {
                        if let price = pending.price {
                            LabeledContent("Price", value: price)
                        }
                        if let date = pending.renewsAt {
                            LabeledContent(pending.isTrial ? "Plan starts" : "Renews",
                                           value: date.formatted(.dateTime.month().day()
                                               .locale(Locale(identifier: UILanguage.chromeLanguage))))
                        }
                    } footer: {
                        Text("The same plan you picked. Cancel any time in Settings.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        working = true
                        Task {
                            await consent.confirm()
                            working = false
                            if consent.pending == nil { dismiss() }
                        }
                    } label: {
                        Text("Confirm with Apple")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working)
                    Button("Later") { dismiss() }
                        .controlSize(.large)
                }
                .padding()
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await consent.refresh() }
    }
}
