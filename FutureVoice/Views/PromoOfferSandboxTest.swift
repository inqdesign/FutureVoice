#if DEBUG || PROMO_TEST
import SwiftUI
import StoreKit

/// Developer → Sandbox: half-price offer. A test of ONE question before the
/// friend invite is built: when an ACTIVE Light subscriber takes a
/// promotional offer on the same product, does Apple apply it at the next
/// renewal? The signatures below were made on the Mac (the key never ships)
/// and are good for 24 hours from the build.
struct PromoOfferSandboxTest: View {
    private static let productID = "com.roro.futurevoice.daily_monthly"
    private static let offerID = "friend_half_test"
    private static let keyID = "JJ45CCH6HV"
    /// Signed into every signature below, the way the real app attaches the account.
    private static let username = "b172a993-780d-4da0-bc69-bd1e8674909d"
    private static let signatures: [(String, Int, String)] = [
        ("ee115da0-6f13-4e81-87dd-e5fa32a30c99", 1795118683980, "MEUCIF5arhGpemQYz6MtYcCemc3HREOPujGwqzjeTBj8jf1uAiEAwig9UMBqiEYUZr4biqqTdD+cCKWxaWSgT10y5mnmlt0="),
        ("c799c5c6-0d74-4fa1-9d44-c5b76ef263e7", 1795118684020, "MEYCIQD+rD/rVzjk4fL2BeypZbDwGfWsmETXu3bg411yBa3F+wIhAN4W+7wv6b05Qq0jFgLPOGgRPG5jHPNUH9Vbmou189bk"),
        ("81297fc6-b5a1-49df-971a-51adec7e05b8", 1795118684041, "MEUCIQD9jJTEiyPhp/gJKTGbz9lYgNUfk8NbEuYNOd/PGJyfegIgd11vLpZAC/KC3nUi2TUcskJvjOuB0bw0HAm1Rad9V0U="),
        ("11a77741-f405-4967-8a8e-0baf0a098539", 1795118684067, "MEUCIQC68EPo1Qo3DxJO7x6EzyhFtnWeDYdn78sLKDjoIq8pGgIgQyXe2gGRab2C3FpVUoroJr/MOdZGaJ0kRJ8ggGoXmZY="),
        ("f9260825-e3f9-4bc2-a3f0-068f05a39114", 1795118684089, "MEUCIHT21iSvhUjtHRPiKKqPT4r/s4U2xzro+bgtpZH2XsF2AiEAvukrUENhGbwahROTZqbRNy+cictZ5nrzajRr/vBHxTc="),
        ("f7b0a0c3-3ddd-472f-9a51-4e9605cda115", 1795118684109, "MEYCIQCgSDN9AvTk4nQescizCTEzBRjjnbr8RVSLcLINGPawkgIhAN+bDEHLNekBYaMX2tQbAvLHNyZyaEwKDixU0hJVtk2V"),
    ]
    @AppStorage("debug.promoOffer.used2") private var used = 0
    @State private var log = ""
    @State private var busy = false
    @State private var oldNote = ""
    @State private var redeeming = false
    /// Sandbox one-time codes of the test offer for EXISTING subscribers
    /// (App Store Connect, "Friend half month code (sandbox test)").
    private static let codes = ["HX6PP7EFFY3X76JYAP", "MHM36JA8HNXPN7K4PK", "AHA7T3X33NFYENNFML",
                                "AMNF3W3RRLYJMMMAHP", "L8Y34Y3HEERKJWK63Y", "76NXTNMEPFMEXK7HFL"]
    @AppStorage("debug.promoOffer.codesUsed") private var codesUsed = 0
    private var code: String { Self.codes[min(codesUsed, Self.codes.count - 1)] }

    var body: some View {
        List {
            Section {
                Button("1. Buy Light monthly (plain)") { run { try await buy(offer: false) } }
                Button("3. Take the offer (old StoreKit API)") { run { try await buyOld() } }
                Button("4. Redeem an offer code (copies \(code))") {
                    UIPasteboard.general.string = code
                    redeeming = true
                }
                Button("Next code") { codesUsed += 1 }
                Button("Refresh") { run { } }
            } footer: {
                Text(verbatim: "Sandbox only. A month is 5 minutes. Signatures used: \(used)/\(Self.signatures.count)")
            }
            Section {
                Text(verbatim: log.isEmpty ? "…" : log)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
        .disabled(busy)
        .navigationTitle(Text(verbatim: "Half-price offer"))
        .task { await show("opened") }
        .offerCodeRedemption(isPresented: $redeeming) { result in
            Task {
                switch result {
                case .success: await show("redeem sheet closed: success")
                case .failure(let error): await show("redeem sheet closed: \(error)")
                }
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            var note = "ok"
            do { try await work() } catch { note = "error: \(error)" }
            await show(note)
            busy = false
        }
    }

    private func buy(offer: Bool) async throws {
        guard let product = try await Product.products(for: [Self.productID]).first else {
            throw NSError(domain: "promo", code: 1, userInfo: [NSLocalizedDescriptionKey: "product not found"])
        }
        var options: Set<Product.PurchaseOption> = []
        if offer {
            guard used < Self.signatures.count else {
                throw NSError(domain: "promo", code: 2, userInfo: [NSLocalizedDescriptionKey: "no signature left, rebuild"])
            }
            let (nonce, timestamp, signature) = Self.signatures[used]
            used += 1
            options.insert(.promotionalOffer(offerID: Self.offerID, keyID: Self.keyID,
                                             nonce: UUID(uuidString: nonce)!,
                                             signature: Data(base64Encoded: signature)!,
                                             timestamp: timestamp))
        }
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification { await transaction.finish() }
        case .userCancelled:
            throw NSError(domain: "promo", code: 3, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
        case .pending:
            throw NSError(domain: "promo", code: 4, userInfo: [NSLocalizedDescriptionKey: "pending"])
        @unknown default: break
        }
    }

    /// The same offer through StoreKit 1 (SKPaymentQueue + SKPaymentDiscount):
    /// StoreKit 2 answered "already subscribed" without asking Apple.
    private func buyOld() async throws {
        guard used < Self.signatures.count else {
            throw NSError(domain: "promo", code: 2, userInfo: [NSLocalizedDescriptionKey: "no signature left, rebuild"])
        }
        let (nonce, timestamp, signature) = Self.signatures[used]
        used += 1
        let note = try await OldStoreKitBuyer.shared.buy(
            productID: Self.productID, username: Self.username,
            discount: SKPaymentDiscount(identifier: Self.offerID, keyIdentifier: Self.keyID,
                                        nonce: UUID(uuidString: nonce)!, signature: signature,
                                        timestamp: NSNumber(value: timestamp)))
        oldNote = note
    }

    private func show(_ note: String) async {
        var lines = ["\(Date().formatted(date: .omitted, time: .standard))  \(note)"]
        if !oldNote.isEmpty { lines.append("old API: \(oldNote)") }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            lines.append("")
            lines.append("product  \(t.productID)")
            lines.append("original \(t.originalID)")
            lines.append("tx       \(t.id)")
            lines.append("bought   \(t.purchaseDate.formatted(date: .omitted, time: .standard))")
            lines.append("expires  \(t.expirationDate?.formatted(date: .omitted, time: .standard) ?? "-")")
            lines.append("offer    type \(t.offerType?.rawValue.description ?? "none") id \(t.offerID ?? "-")")
            lines.append("env      \(t.environment.rawValue)")
            if let status = await t.subscriptionStatus,
               case .verified(let renewal) = status.renewalInfo {
                lines.append("renews   \(renewal.willAutoRenew) as \(renewal.autoRenewPreference ?? "-")")
                lines.append("next offer type \(renewal.offerType?.rawValue.description ?? "none") id \(renewal.offerID ?? "-")")
            }
        }
        if lines.count == 1 { lines.append("no active subscription") }
        log = lines.joined(separator: "\n")
        // Appended to a file so the result can be read off the Mac.
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent("promo_test.log")
            let entry = (log + "\n----\n").data(using: .utf8)!
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(entry); try? handle.close()
            } else { try? entry.write(to: url) }
        }
    }
}
/// StoreKit 1, for the one test above.
final class OldStoreKitBuyer: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    static let shared = OldStoreKitBuyer()
    private var productWaiter: CheckedContinuation<SKProduct?, Never>?
    private var resultWaiter: CheckedContinuation<String, Never>?
    private var request: SKProductsRequest?

    func buy(productID: String, username: String, discount: SKPaymentDiscount) async throws -> String {
        let product: SKProduct? = await withCheckedContinuation { waiter in
            productWaiter = waiter
            let request = SKProductsRequest(productIdentifiers: [productID])
            request.delegate = self
            self.request = request
            request.start()
        }
        guard let product else { return "product not found" }
        SKPaymentQueue.default().add(self)
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = username
        payment.paymentDiscount = discount
        return await withCheckedContinuation { waiter in
            resultWaiter = waiter
            SKPaymentQueue.default().add(payment)
        }
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        productWaiter?.resume(returning: response.products.first)
        productWaiter = nil
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        productWaiter?.resume(returning: nil)
        productWaiter = nil
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            let offer = transaction.payment.paymentDiscount?.identifier ?? "-"
            switch transaction.transactionState {
            case .purchased, .restored:
                queue.finishTransaction(transaction)
                finish("purchased id \(transaction.transactionIdentifier ?? "-") offer \(offer)")
            case .failed:
                queue.finishTransaction(transaction)
                finish("failed: \(transaction.error.map { String(describing: $0) } ?? "-")")
            case .deferred:
                finish("deferred")
            default:
                break
            }
        }
    }

    private func finish(_ note: String) {
        resultWaiter?.resume(returning: note)
        resultWaiter = nil
    }
}
#endif
