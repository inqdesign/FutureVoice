import Foundation

/// Centralized access to API keys.
///
/// Phase 1 (spike): reads from `Bundle.main.infoDictionary` after Xcode injects
/// values from `FutureVoice.xcconfig` via Info.plist `$(KEY)` substitution.
/// As a fallback during local iteration, you can paste a value into `devOverride`.
///
/// Production / Phase 2: secrets should move behind a Supabase Edge Function
/// proxy so the iOS app never holds raw provider keys. Mirrors the pattern
/// used in the DearMyChild project.
enum Secrets {
    enum Key: String {
        case elevenLabs = "ELEVENLABS_API_KEY"
        case anthropic  = "ANTHROPIC_API_KEY"
        case openAI     = "OPENAI_API_KEY"
        case supabaseURL = "SUPABASE_URL"
        case supabaseAnonKey = "SUPABASE_ANON_KEY"
    }

    /// Returns the value or crashes loudly. Phase 1 only — never ship to TestFlight like this.
    static func require(_ key: Key) -> String {
        if let value = string(for: key), !value.isEmpty {
            return value
        }
        fatalError("Missing secret: \(key.rawValue). Set it in FutureVoice.xcconfig.")
    }

    static func string(for key: Key) -> String? {
        if let override = devOverride[key.rawValue], !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String
    }

    /// Local-only override. Leave empty. NEVER COMMIT values here.
    /// Example (do NOT commit): ["ELEVENLABS_API_KEY": "sk_..."]
    private static let devOverride: [String: String] = [:]
}
