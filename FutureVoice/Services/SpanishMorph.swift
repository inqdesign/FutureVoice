import Foundation

/// Spanish word → headword, from a bundled table rather than the tagger.
///
/// iOS ships no Spanish lemma model (measured 2026-10-15: `NLTagger` on the
/// simulator returns nil for every Spanish word, `availableTagSchemes` has no
/// `.lemma`, and `requestAssets` downloads only lexical classes), so the
/// tagger path every spaced language takes in `VocabStore` would hand back
/// "comí" and "hermanos" untouched and no Spanish word would ever meet its
/// headword. The Mac's tagger does have one, so `scripts/build-es-wordlist.swift`
/// ran it over Tatoeba in context and wrote what every form came out as:
/// `es_forms.tsv`, form TAB lemma (empty = the form is its own) TAB class.
/// The headwords in `cefr_words_es.tsv` are those same lemmas, so the two
/// can't disagree.
///
/// Only content words are in the table. A form that isn't is its own lemma
/// with no class — a function word, a name, or a word neither corpus used —
/// which is the conservative answer on every path that reads it.
enum SpanishMorph {
    struct Entry { let lemma: String; let wordClass: String }

    nonisolated static func entry(for form: String) -> Entry? {
        table[form.lowercased()]
    }

    /// The headword `form` belongs to, or the form itself (lowercased).
    nonisolated static func lemma(of form: String) -> String {
        let w = form.lowercased()
        return table[w]?.lemma ?? w
    }

    /// Each word of `text` with its range, letters only (accents included),
    /// so callers can ask about capitals the way the tagger path does.
    nonisolated static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
        var out: [(String, Range<String.Index>)] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isLetter {
                if start == nil { start = i }
            } else if let s = start {
                out.append((String(text[s..<i]), s..<i))
                start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { out.append((String(text[s..<text.endIndex]), s..<text.endIndex)) }
        return out
    }

    private static let table: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "es_forms", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: Entry] = [:]
        out.reserveCapacity(60_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }   // the credit line has no tab
            let form = String(parts[0])
            out[form] = Entry(lemma: parts[1].isEmpty ? form : String(parts[1]),
                              wordClass: String(parts[2]))
        }
        return out
    }()
}
