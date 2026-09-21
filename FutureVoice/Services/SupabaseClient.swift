import Foundation
import Supabase

/// Single shared Supabase client. Reads URL + anon key from `Secrets`
/// (which pulls them from `Config/FutureVoice.xcconfig`).
///
/// Never expose the service_role key here — that one lives only on the
/// server side as a Supabase Function secret.
enum SupabaseProvider {
    static let shared: SupabaseClient = {
        guard
            let urlString = Secrets.string(for: .supabaseURL),
            let url = URL(string: urlString),
            let anon = Secrets.string(for: .supabaseAnonKey)
        else {
            fatalError("SUPABASE_URL / SUPABASE_ANON_KEY missing from xcconfig")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anon)
    }()
}

/// Thrown when an Edge Function call can't be given the learner's own token.
/// Named rather than swallowed, because the alternative is the call going out
/// anonymously and coming back as a 401 the learner can't act on.
struct NotSignedInError: LocalizedError {
    var errorDescription: String? {
        explain("You're signed out. Sign in again, then try once more.")
    }
}

extension SupabaseProvider {
    /// The learner's OWN `Authorization` header for an Edge Function call.
    ///
    /// `functions.invoke` alone does not guarantee one. The functions client
    /// is built with `Bearer <anon key>` already in its default headers, and
    /// the per-request adapter overwrites that only `if let token` — so
    /// whenever `auth.session` fails to resolve (a refresh that couldn't
    /// reach the network, a restore that hasn't landed yet) the call silently
    /// goes out ANONYMOUSLY. Every function's `requireUser` then answers 401,
    /// and the learner is told the server refused them, for a request that
    /// never said who they were.
    ///
    /// Seen in prod 2026-09-13: one iPad got 401 on `news-topics` and on
    /// `account-delete` twenty seconds apart, and the auth log names the
    /// cause — `403: invalid claim: missing sub claim`, which is the anon key
    /// arriving where a user token was meant to be. "Couldn't delete
    /// account" with no way forward is the worst possible place for it.
    ///
    /// Resolving the token here makes a dead session SAY so, and sending it
    /// explicitly means no fallback can happen underneath.
    static func authorizedHeaders() async throws -> [String: String] {
        guard let token = try? await shared.auth.session.accessToken else {
            throw NotSignedInError()
        }
        return ["Authorization": "Bearer \(token)"]
    }
}
