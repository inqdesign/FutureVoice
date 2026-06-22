import Foundation

/// On-demand translation of a single line into the user's native language, for
/// "tap to see the meaning" in conversations. Cached (memory + disk) so the
/// same line is never re-billed.
@MainActor
enum Translator {
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

        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: lang) ?? lang
        do {
            let out = try await GeminiClient.shared.send(
                system: """
                You are a translator. Translate the user's text into \(languageName). \
                Output ONLY the translation — no quotes, no romanization, no notes, no original text.
                """,
                messages: [GeminiClient.Message(role: .user, content: text)],
                maxTokens: 400,
                temperature: 0.2
            )
            let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            memory[k] = t
            saveDisk()
            return t
        } catch {
            return nil
        }
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
