import Foundation
import Supabase

/// A message to the OWNER, on Telegram, while it is still happening.
///
/// Everything the paywall does is already logged — `paywall_purchase_tapped`
/// and `paywall_purchase_result` go to `client_events` and PostHog, and the
/// funnel is answerable in SQL. What a table cannot do is arrive. The tap
/// that never becomes a charge is the one worth hearing about at the time:
/// Korea's ₩0→정가 screen is refused inside Apple's own sheet, so the app's
/// own data shows someone who reached the button and then nothing, and by
/// the time the row is read the person has been gone for days.
///
/// Rules this helper keeps, and the reason each is here:
///
/// * **It is never waited on.** A detached task with no result: the caller
///   is a `Button` in the middle of a purchase, and a notification must not
///   put a single millisecond in front of Apple's sheet.
/// * **It never throws, and a signed-out phone simply doesn't ping.** Same
///   contract as `Telemetry` — a failure here must not become a second
///   user-facing failure on the screen that takes money.
/// * **It sends FACTS, never a sentence.** The edge function composes the
///   text from a fixed vocabulary. This is the one client-triggered path
///   into the owner's Telegram, so the client must not be able to write to
///   it; the server also caps how many it will send per account per day.
enum OwnerPing {
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    private static let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    private struct Body: Encodable {
        let phase: String
        let outcome: String?
        let plan: String
        let source: String
        let step: String
        let trial: Bool
        let price: String?
        let country: String?
        let build: String
        let version: String
    }

    /// `phase` is "tapped" (the button, before Apple's sheet) or "result"
    /// (purchased / cancelled / failed / unavailable). Both are sent: a tap
    /// alone can't say whether it converted, and a result alone is never sent
    /// at all when the app is killed on top of the sheet.
    static func paywall(phase: String, outcome: String? = nil,
                        option: StoreKitService.PlanOption,
                        trial: Bool, source: String, step: String) {
        paywall(phase: phase, outcome: outcome, plan: option.id,
                price: option.localizedPrice, country: option.storefrontCountry,
                trial: trial, source: source, step: step)
    }

    /// The same ping where there is no `PlanOption` to name — StoreKit gave
    /// us no product, so the learner tapped a button that could not buy
    /// anything. That tap is the most worth hearing about of all.
    static func paywall(phase: String, outcome: String? = nil,
                        plan: String, price: String? = nil, country: String? = nil,
                        trial: Bool, source: String, step: String) {
        let body = Body(phase: phase, outcome: outcome, plan: plan,
                        source: source, step: step, trial: trial,
                        price: price, country: country,
                        build: build, version: version)
        Task.detached(priority: .utility) {
            // Resolved explicitly: `functions.invoke` falls back to the anon
            // key when the session can't be read, and an anonymous ping is a
            // 401 that says nothing about who tapped.
            guard let headers = try? await SupabaseProvider.authorizedHeaders() else { return }
            try? await SupabaseProvider.shared.functions.invoke(
                "paywall-notify",
                options: FunctionInvokeOptions(headers: headers, body: body)
            )
        }
    }
}
