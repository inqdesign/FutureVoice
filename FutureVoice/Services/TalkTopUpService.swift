import Foundation
import StoreKit
import Supabase

/// Talk-minute packs — the consumable that replaced "unlimited" on
/// 2026-09-26. A subscriber whose month is spent buys a hundred minutes at a
/// time instead of a bigger plan, and the heavy tail pays for what it talks
/// rather than being a risk the plan absorbs (`docs/launch-billing.md`,
/// "2026-09-26 revision").
///
/// Same split as the plans: the server says what a pack GRANTS
/// (`talk_topups.seconds`), Apple says what it COSTS (`Product.displayPrice`).
/// The purchase is landed by handing the signed transaction to `apple-topup`,
/// which verifies Apple's signature and grants through `apply_talk_topup`
/// under the transaction id — so a re-sent receipt grants nothing twice and
/// a jailbroken client can't mint minutes. **The transaction is finished only
/// after the server has answered**: an unfinished consumable is re-delivered
/// by StoreKit on every launch (`Transaction.updates`, which routes back
/// through `redeem`), so a purchase made with no network is never lost.
///
/// The seconds land in `user_credits.balance` — the pool invite minutes live
/// in — which the meter spends before the plan's own pool; `talk_allowance`
/// reports it as `bonus` and the Usage page shows it as "+N min".
@MainActor
final class TalkTopUpService: ObservableObject {

    struct Pack: Identifiable {
        let productId: String
        let seconds: Int
        let product: Product?
        var id: String { productId }
        var minutes: Int { seconds / 60 }
        var localizedPrice: String? { product?.displayPrice }
    }

    enum State: Equatable {
        case idle, purchasing, purchased, failed(String)
    }

    @Published private(set) var pack: Pack?
    @Published var state: State = .idle

    private var inflightLoad: Task<Void, Never>?

    /// The one pack on sale, with its live price. Nil while loading, and nil
    /// for good when either the catalog row or the App Store product is
    /// missing — a button with no price is not offered.
    func load() async {
        guard pack == nil else { return }
        if let inflightLoad { await inflightLoad.value; return }
        let task = Task { await fetch() }
        inflightLoad = task
        await task.value
        inflightLoad = nil
    }

    private func fetch() async {
        #if DEBUG
        // `-capture paywall-ladder…`: a Debug build has no priced product.
        if UserDefaults.standard.string(forKey: "capture")?.hasPrefix("paywall-ladder") == true {
            pack = Pack(productId: "com.roro.futurevoice.talk_50", seconds: 3000, product: nil)
            return
        }
        #endif
        struct Row: Decodable { let apple_product_id: String; let seconds: Int }
        guard let rows: [Row] = try? await SupabaseProvider.shared
            .from("talk_topups")
            .select("apple_product_id,seconds")
            .eq("is_active", value: true)
            .order("seconds")
            .execute()
            .value,
              let row = rows.first else { return }
        let products = (try? await Product.products(for: [row.apple_product_id])) ?? []
        pack = Pack(productId: row.apple_product_id, seconds: row.seconds,
                    product: products.first)
    }

    func purchase() async {
        guard let pack, let product = pack.product else {
            state = .failed(explain("This pack isn't available on the App Store yet."))
            return
        }
        guard let session = try? await SupabaseProvider.shared.auth.session else {
            state = .failed(explain("You need to be signed in to buy minutes."))
            return
        }
        state = .purchasing
        do {
            let result = try await product.purchase(options: [.appAccountToken(session.user.id)])
            switch result {
            case .success(let verification):
                guard case .verified = verification else {
                    state = .failed(explain("Purchase could not be verified."))
                    return
                }
                if await Self.redeem(verification) {
                    state = .purchased
                } else {
                    // Apple has the money and StoreKit keeps the transaction:
                    // `Transaction.updates` presents it again on the next
                    // launch, and `redeem` lands it then.
                    state = .failed(explain("Couldn't reach the server. Your minutes will be added the next time the app opens."))
                }
            case .userCancelled:
                state = .idle
            case .pending:
                state = .failed(explain("Purchase is pending approval."))
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Hands a verified consumable to the server and finishes it once the
    /// server has it. Returns whether it is now safely on the account — true
    /// also for "already applied", which is a retry of a landed purchase.
    /// Never finishes a transaction the server has not acknowledged.
    @discardableResult
    static func redeem(_ result: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = result,
              transaction.productType == .consumable,
              transaction.productID.hasPrefix("com.roro.futurevoice.") else { return false }
        guard (try? await SupabaseProvider.shared.auth.session) != nil else { return false }

        struct Body: Encodable { let jws: String }
        struct Reply: Decodable { let applied: Bool; let seconds: Int?; let balance: Int? }
        do {
            let reply: Reply = try await SupabaseProvider.shared.functions.invoke(
                "apple-topup",
                options: FunctionInvokeOptions(
                    headers: try await SupabaseProvider.authorizedHeaders(),
                    body: Body(jws: result.jwsRepresentation)
                )
            )
            await transaction.finish()
            // The paywall gate and the Me tab read a cached snapshot; minutes
            // that just landed must be spendable on the next tap.
            await MainActor.run { BillingGate.shared.invalidate() }
            let props = ["applied": reply.applied ? "1" : "0",
                         "seconds": String(reply.seconds ?? 0),
                         "product": transaction.productID]
            Telemetry.log("topup_landed", props)
            Analytics.capture("topup_landed", props)
            return true
        } catch {
            // Offline, or the function is not deployed yet. StoreKit keeps
            // the transaction and presents it again.
            return false
        }
    }
}
