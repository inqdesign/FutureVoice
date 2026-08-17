import Foundation
import StoreKit
import Supabase

/// Joins the server-side plan catalog (`subscription_plans` — credits per
/// cycle, tier, period) with live StoreKit products (localized price, intro
/// offer). The DB stays the source of truth for what a plan GRANTS; Apple
/// stays the source of truth for what it COSTS.
///
/// Entitlement note: a successful purchase here does NOT directly grant
/// credits — that happens server-side when Apple's server notification /
/// receipt hits the (upcoming) subscription webhook, so a jailbroken client
/// can't mint credits. Until that function ships, purchases complete on
/// Apple's side and the balance updates once the webhook lands.
@MainActor
final class StoreKitService: ObservableObject {

    struct DBPlan: Decodable, Identifiable {
        let id: String                 // 'daily_monthly'
        let tier: String               // 'daily' | 'unlimited'
        let period: String             // 'weekly' | 'monthly' | 'annual'
        let daily_seconds: Int?        // per-day talk allowance (minutes-native model)
        let daily_scenes: Int?         // per-day Watch scene count (scenes left the talk meter 2026-08-14)
        let apple_product_id: String
    }

    /// One selectable option: catalog row + (when App Store Connect has the
    /// product configured) the live StoreKit product carrying price + trial.
    struct PlanOption: Identifiable {
        let plan: DBPlan
        let product: Product?
        var id: String { plan.id }

        /// The price we may SHOW on a card that can be bought: Apple's, for
        /// this customer's storefront, or nothing. Never the planned map —
        /// that is one hardcoded currency (KRW) and would quote a Japanese
        /// customer a Korean number. Showing NO price is the honest state
        /// when StoreKit hasn't answered — the card omits the line.
        var localizedPrice: String? { product?.displayPrice }

        /// Planned launch price for the BETA SURVEY only — an anchor for a
        /// hypothetical ("would you pay this?"), explicitly labelled as
        /// planned, never presented as a live charge.
        var plannedPriceLabel: String? {
            PlanOption.plannedPrice(plan.id, storefront: storefrontCountry)
        }

        /// The viewer's App Store country (ISO-3, e.g. "KOR"), captured with
        /// the catalog so the fallback can pick a currency.
        var storefrontCountry: String?

        // Planned launch prices from docs/launch-billing.md — the EUR list
        // and Apple's own suggested KRW points (App Store Connect,
        // 2026-08-11). Used ONLY before StoreKit has products; the live
        // `displayPrice` is always the customer's own storefront currency.
        static let plannedPriceKRW: [String: String] = [
            "daily_monthly":     "₩15,000",
            "daily_annual":      "₩110,000",
            "unlimited_monthly": "₩29,000",
            "unlimited_annual":  "₩299,000",
        ]
        static let plannedPriceEUR: [String: String] = [
            "daily_monthly":     "€9.99",
            "daily_annual":      "€79.99",
            "unlimited_monthly": "€19.99",
            "unlimited_annual":  "€199.99",
        ]

        /// Currency follows the App Store STOREFRONT, never the app's
        /// language — a Korean-speaking learner with a US account pays in
        /// USD. StoreKit does this for us on live products; this fallback
        /// only has two currencies, so it picks by storefront country and
        /// quotes EUR (the list currency) everywhere else.
        static func plannedPrice(_ id: String, storefront: String?) -> String? {
            storefront == "KOR" ? plannedPriceKRW[id] : plannedPriceEUR[id]
        }

        /// Numeric price for math (annual-vs-monthly savings). Live products
        /// carry `product.price`; the fallback mirrors `plannedPrice`.
        /// Numeric planned prices for the savings badge. Ratios (annual vs
        /// 12× monthly) differ per currency because Apple price points are a
        /// tier table, not a conversion — so this must follow the storefront
        /// too: 39% off in KRW, 33% in EUR.
        static let plannedValueKRW: [String: Decimal] = [
            "daily_monthly":     15_000,
            "daily_annual":      110_000,
            "unlimited_monthly": 29_000,
            "unlimited_annual":  299_000,
        ]
        static let plannedValueEUR: [String: Decimal] = [
            "daily_monthly":     9.99,
            "daily_annual":      79.99,
            "unlimited_monthly": 19.99,
            "unlimited_annual":  199.99,
        ]
        static func plannedValue(_ id: String, storefront: String?) -> Decimal? {
            storefront == "KOR" ? plannedValueKRW[id] : plannedValueEUR[id]
        }

        var priceValue: Decimal? { product?.price }

        /// Intro-offer length in days, when Apple has one configured.
        var trialDays: Int? {
            guard let offer = product?.subscription?.introductoryOffer,
                  offer.paymentMode == .freeTrial else { return nil }
            let p = offer.period
            switch p.unit {
            case .day:   return p.value
            case .week:  return p.value * 7
            case .month: return p.value * 30
            case .year:  return p.value * 365
            @unknown default: return nil
            }
        }
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
    }

    @Published private(set) var options: [PlanOption] = []
    @Published private(set) var loading = false
    @Published var purchaseState: PurchaseState = .idle
    /// Whether Apple says this account can still redeem an intro offer. A
    /// user who already burned their free trial (or their free credits) must
    /// not be pitched "Try for free" again — the paywall skips straight to
    /// plans when this is false.
    @Published private(set) var trialEligible = true

    /// Longest free trial across loaded products — drives the timeline copy.
    /// Falls back to 7 while products aren't configured yet.
    var trialDays: Int {
        options.compactMap(\.trialDays).max() ?? 7
    }

    // MARK: - App-lifetime transaction listener

    private static var updatesTask: Task<Void, Never>?

    /// Finishes transactions that arrive OUTSIDE `purchase()` — renewals, a
    /// purchase made on another device, an Ask-to-Buy approval, or a payment
    /// that was interrupted and completed later. Apple re-delivers every
    /// unfinished transaction on each launch forever, and an Ask-to-Buy
    /// approval never resolves in-app without this.
    ///
    /// Entitlement is NOT read from here: the server decides that from
    /// Apple's server notifications (`apple-webhook`), so a jailbroken client
    /// can't mint a subscription. This only clears Apple's queue.
    ///
    /// Must run for the app's whole life, so it lives on the type rather than
    /// on the instance the paywall creates and throws away.
    static func startTransactionListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
            }
        }
    }

    func load() async {
        guard options.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }

        var plans: [DBPlan] = []
        do {
            plans = try await SupabaseProvider.shared
                .from("subscription_plans")
                .select("id,tier,period,daily_seconds,daily_scenes,apple_product_id")
                .eq("is_active", value: true)
                .execute()
                .value
        } catch {
            // No catalog → nothing to sell; the paywall shows a quiet
            // unavailable state rather than crashing the flow.
            options = []
            return
        }

        let products: [Product]
        do {
            products = try await Product.products(for: plans.map(\.apple_product_id))
        } catch {
            products = []
        }
        let byId = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        // The storefront is the App Store account's country — nothing to do
        // with the device or app language.
        let storefront = await Storefront.current?.countryCode
        options = plans.map {
            PlanOption(plan: $0, product: byId[$0.apple_product_id],
                       storefrontCountry: storefront)
        }

        // Trial eligibility, straight from StoreKit: eligible if ANY loaded
        // product's subscription still offers this account an intro offer.
        // With no products loaded there's nothing purchasable anyway — leave
        // the default (true) rather than guessing.
        if !products.isEmpty {
            var eligible = false
            for p in products {
                if let sub = p.subscription, await sub.isEligibleForIntroOffer {
                    eligible = true
                    break
                }
            }
            trialEligible = eligible
        }
    }

    func purchase(_ option: PlanOption) async {
        guard let product = option.product else {
            purchaseState = .failed("This plan isn't available on the App Store yet.")
            return
        }
        purchaseState = .purchasing
        do {
            // appAccountToken ties the Apple transaction to our Supabase user,
            // so the apple-webhook Edge Function can attribute every server
            // notification without receipt-to-account guesswork. Purchasing
            // without a session would create an unmappable transaction — bail
            // out loudly instead.
            guard let session = try? await SupabaseProvider.shared.auth.session else {
                purchaseState = .failed("You need to be signed in to subscribe.")
                return
            }
            let result = try await product.purchase(options: [.appAccountToken(session.user.id)])
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Credits are granted server-side via Apple's server
                    // notifications — finishing here just acknowledges
                    // receipt on-device.
                    await transaction.finish()
                    purchaseState = .purchased
                case .unverified:
                    purchaseState = .failed("Purchase could not be verified.")
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .failed("Purchase is pending approval.")
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
            purchaseState = .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}
