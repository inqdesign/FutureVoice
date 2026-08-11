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
        let id: String                 // 'pro_monthly'
        let tier: String               // 'pro' | 'premium'
        let period: String             // 'weekly' | 'monthly' | 'annual'
        let daily_seconds: Int?        // per-day talk allowance (minutes-native model)
        let apple_product_id: String
    }

    /// One selectable option: catalog row + (when App Store Connect has the
    /// product configured) the live StoreKit product carrying price + trial.
    struct PlanOption: Identifiable {
        let plan: DBPlan
        let product: Product?
        var id: String { plan.id }

        /// Live App Store price when the product loads, else the planned launch
        /// price from `docs/launch-billing.md` — so the paywall (and beta WTP
        /// survey) show real numbers before StoreKit products are live.
        /// Weekly is an impulse tier with no fixed price yet → nil ("—").
        var localizedPrice: String? { product?.displayPrice ?? PlanOption.plannedPrice[plan.id] }

        // KRW App Store–style points for the locked EUR list prices in
        // docs/launch-billing.md. Live StoreKit localizes once products ship.
        static let plannedPrice: [String: String] = [
            "pro_monthly":     "₩14,000",
            "pro_annual":      "₩119,000",
            "premium_monthly": "₩29,000",
            "premium_annual":  "₩299,000",
        ]

        /// Numeric price for math (annual-vs-monthly savings). Live products
        /// carry `product.price`; the fallback mirrors `plannedPrice`.
        static let plannedPriceValue: [String: Decimal] = [
            "pro_monthly":     14_000,
            "pro_annual":      119_000,
            "premium_monthly": 29_000,
            "premium_annual":  299_000,
        ]

        var priceValue: Decimal? { product?.price ?? PlanOption.plannedPriceValue[plan.id] }

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

    func load() async {
        guard options.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }

        var plans: [DBPlan] = []
        do {
            plans = try await SupabaseProvider.shared
                .from("subscription_plans")
                .select("id,tier,period,daily_seconds,apple_product_id")
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
        options = plans.map { PlanOption(plan: $0, product: byId[$0.apple_product_id]) }

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
