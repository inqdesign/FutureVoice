import CryptoKit
import Foundation

/// On-disk cache for `DrillCardEnrichment`, keyed by the PHRASE it explains —
/// `(target phrase, target language, native language)` — rather than by the
/// `DrillCard.id` it was opened from. Files live under
/// `Documents/DrillEnrichment/{sha256}.json`. Same shape and reasoning as
/// `PhraseAudioStore`: what costs money is the content, so the content is the
/// key.
///
/// ## Why the card can't be the cache
///
/// `DrillCard.enrichment` was the only copy, and a card is not a stable thing:
///
/// - A correction studied from a talk book may have no card in the store at
///   all — `DrillStore.ingest` skips meta-rule targets and dedupes against
///   every card ever minted — so `ConversationDetailView.openCard` mints one
///   on the spot. If `load()`'s read-time filter then drops it, the next tap
///   finds nothing, mints ANOTHER card with a fresh id, and pays for the
///   generation again. Measured on 2026-08-19: distinct card ids in the usage
///   ledger seconds apart, all for the same correction.
/// - `SessionSummarizer` calls `clearUnreviewedCards` on every re-analysis
///   (Continue a talk, regenerate a summary), which deletes box-0 untouched
///   cards — and with them whatever was generated for them.
///
/// Keyed by content, none of that matters: the card keeps a mirror copy for
/// the deck's "already enriched" pill, but losing it costs nothing.
final class DrillEnrichmentStore {
    static let shared = DrillEnrichmentStore()

    private let dir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("DrillEnrichment", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Read / write

    func enrichment(for phrase: String,
                    targetLanguage: String,
                    nativeLanguage: String) -> DrillCardEnrichment? {
        let url = fileURL(for: Self.key(phrase: phrase,
                                        targetLanguage: targetLanguage,
                                        nativeLanguage: nativeLanguage))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DrillCardEnrichment.self, from: data)
    }

    @discardableResult
    func save(_ enrichment: DrillCardEnrichment,
              phrase: String,
              targetLanguage: String,
              nativeLanguage: String) -> Bool {
        let url = fileURL(for: Self.key(phrase: phrase,
                                        targetLanguage: targetLanguage,
                                        nativeLanguage: nativeLanguage))
        guard let data = try? encoder.encode(enrichment) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }

    // MARK: - Key

    /// Also the request's idempotency key, so even a cache miss that races
    /// itself (two opens of the same phrase) is billed once — the edge
    /// function's usage ledger dedupes on it.
    ///
    /// The native language is in the key because most of the payload —
    /// situations, notes, the memory hook — is written in it; the target
    /// language is there because the same sentence can be studied in two
    /// enrolled languages. Casing and punctuation are normalized away so a
    /// card whose target was trimmed at read time still hits what the
    /// untrimmed one generated.
    static func key(phrase: String, targetLanguage: String, nativeLanguage: String) -> String {
        let seed = "\(targetLanguage)\n\(nativeLanguage)\n\(normalized(phrase))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = String(text.unicodeScalars.filter { allowed.contains($0) })
        return stripped
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func fileURL(for key: String) -> URL {
        dir.appendingPathComponent("\(key).json")
    }
}
