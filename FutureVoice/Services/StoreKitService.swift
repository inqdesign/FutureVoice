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
        let id: String                 // 'light_monthly'
        let tier: String               // 'light' | 'plus'
        let period: String             // 'weekly' | 'monthly' | 'annual'
        // Descriptive only since the pools went monthly — the "N minutes a
        // day" figure the cards print (monthly / 30). Nothing meters a day.
        let daily_seconds: Int?
        let daily_scenes: Int?
        // What is actually enforced: the pool per billing period.
        let monthly_seconds: Int?
        let monthly_scenes: Int?
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

        /// The viewer's App Store country (ISO-3, e.g. "KOR"), captured with
        /// the catalog so the fallback can pick a currency.
        var storefrontCountry: String?

        // The hardcoded planned-price tables lived here to anchor the
        // beta's willingness-to-pay survey. They went with the survey on
        // 2026-08-18: a second copy of the price list in the binary can only
        // drift from App Store Connect, and every surface now shows either
        // StoreKit's own `displayPrice` or no price at all.

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
                .select("id,tier,period,daily_seconds,daily_scenes,monthly_seconds,monthly_scenes,apple_product_id")
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
        // A silent empty answer is the one failure this screen can't explain
        // to itself — every price line simply goes blank. Name the ids Apple
        // refused and the bundle that asked, since the answer is almost always
        // one of the two: a bundle id App Store Connect doesn't know (Debug
        // runs as com.roro.futurevoice.dev, which can never be priced — use
        // the "FutureVoice (Store)" scheme), or products not yet purchasable.
        //
        // NOT behind #if DEBUG on purpose: in a Debug build the cause is known
        // in advance, so the log is worth least exactly where it would have
        // been the only one printed.
        if products.isEmpty {
            print("[StoreKit] no products for \(plans.map(\.apple_product_id)) — "
                  + "asked as \(Bundle.main.bundleIdentifier ?? "?")")
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
