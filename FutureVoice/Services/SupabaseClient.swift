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
