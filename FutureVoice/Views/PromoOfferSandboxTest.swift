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
    private static let signatures: [(String, Int, String)] = [
        ("cace4404-89c0-4ee7-bcea-96eac166737b", 1795084637294, "MEQCIGr9PodQ3YnkxW6ZEMzgfRvcVrp8drVg3aYpg4ZY+JSWAiBGe/Wng6tuEa5utFzYpro7XAA/dKdtyGRl8Rz72iE0GA=="),
        ("a8f6a3f4-a06b-40bc-a32c-5fd161541d11", 1795084637305, "MEUCIAttChTd2BVCuwvQzNpZ2EQpHQ70YjnlFkL0ESCvOvtuAiEA2BDCHqK67fYapOQcz+mnly3b1wIkPeAcuAdv8+m0i/A="),
        ("55f41d90-db39-4be9-8b36-8046c81dc2bb", 1795084637311, "MEYCIQCpSVU/ZnKYimy4O7lx1vKBVbH8Pg56iUC3ajYF3Po4bAIhAJeouVDJU7ey0eip0ncZuFeD6xb3VHPe9q5H5L7lc7Sw"),
        ("6519bd94-98ff-4ee8-8503-d683bce14765", 1795084637317, "MEYCIQCQIuEkLMWhRwP6NnUV8J1kK+7hUzx+NPqJeYayCJn0ugIhAPWG5/Wy8ZdkYDdg7yWCY4Nwaog+AAr107YyPmE/KbtG"),
        ("924b9e11-dab2-4062-88e2-3e291bf2586a", 1795084637323, "MEUCIBWyiBDHni45jEKI85GmuqEhV0EFcsJcEyVg0n5148KqAiEA1oEfpdmw6VstgMy2TS9UGLjfIu3UMklh3IqRkbeaEUI="),
        ("2bc4d289-8e9a-43c3-a7cc-cee6a3ce9fda", 1795084637329, "MEUCIQCX4wpx5f7YCI/yGOuIdP+Uwxga+t7qvRQ2c6ccsfsp0AIgEt0+AcGGfmOx0bi9u7VlySk+zyNSG8DStrKqzO6c9JY="),
    ]
    @AppStorage("debug.promoOffer.used") private var used = 0
    @State private var log = ""
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Button("1. Buy Light monthly (plain)") { run { try await buy(offer: false) } }
                Button("2. Take the half-price offer") { run { try await buy(offer: true) } }
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

    private func show(_ note: String) async {
        var lines = ["\(Date().formatted(date: .omitted, time: .standard))  \(note)"]
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
#endif
