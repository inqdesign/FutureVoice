import Foundation
import Supabase   // FunctionInvokeOptions for the free `translate` function

/// On-demand translation of a single line into the user's native language, for
/// "tap to see the meaning" in conversations. Goes through the FREE `translate`
/// Edge Function (fixed server-side prompt — see the function for why free
/// paths can't live on the credit-gated `gemini` function), and is cached
/// (memory + disk) so the same line is never requested twice.
@MainActor
enum Translator {
    private struct RequestBody: Encodable {
        let kind: String
        var text: String? = nil
        var original: String? = nil
        var alternative: String? = nil
        let to_lang: String
    }
    private struct ResponseBody: Decodable { let text: String }

    private static func invoke(_ body: RequestBody) async -> String? {
        do {
            let res: ResponseBody = try await SupabaseProvider.shared.functions.invoke(
                "translate",
                options: FunctionInvokeOptions(body: body)
            )
            let t = res.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        } catch {
            return nil
        }
    }

    private static var memory: [String: String] = loadDisk()

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("translations.json")
    }()

    private static func key(_ text: String, _ lang: String) -> String { lang + "\u{1}" + text }

    /// Cached translation if we already have one (no network).
    static func cached(_ text: String, to lang: String) -> String? {
        memory[key(text, lang)]
    }

    /// Translate `text` into `lang` (BCP-47, e.g. "ko"). Returns nil on failure.
    static func translate(_ text: String, to lang: String) async -> String? {
        let k = key(text, lang)
        if let c = memory[k] { return c }

        guard let t = await invoke(RequestBody(kind: "translate", text: text, to_lang: lang))
        else { return nil }
        memory[k] = t
        saveDisk()
        return t
    }

    // MARK: - Correction explanations

    private static func explainKey(_ original: String, _ alternative: String, _ lang: String) -> String {
        "EXPLAIN\u{1}" + lang + "\u{1}" + original + "\u{1}" + alternative
    }

    /// Cached explanation if we already have one (no network).
    static func cachedExplanation(original: String, alternative: String, to lang: String) -> String? {
        memory[explainKey(original, alternative, lang)]
    }

    /// Native-language coaching note for one correction: what actually changed
    /// between what the learner said and the more natural version, and why.
    /// (Just translating the English reason string says nothing — the
    /// explanation has to reference the specific words.) Cached like
    /// translations so the same correction is never re-billed.
    static func explainCorrection(original: String, alternative: String, to lang: String) async -> String? {
        let k = explainKey(original, alternative, lang)
        if let c = memory[k] { return c }

        guard let t = await invoke(RequestBody(kind: "explain",
                                               original: original,
                                               alternative: alternative,
                                               to_lang: lang))
        else { return nil }
        memory[k] = t
        saveDisk()
        return t
    }

    // MARK: - Disk cache

    private static func loadDisk() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveDisk() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
