import Foundation

/// French word → headword, from a bundled table rather than the tagger.
///
/// Like Spanish (`SpanishMorph`), French can't go through the tagger path
/// every other spaced language takes in `VocabStore`: Apple's French lemma
/// is wrong in context where it matters most (measured on a Mac 2026-11-13:
/// "Je suis fatiguée" → suis → suivre), and it cuts grand-mère and
/// aujourd'hui in two. So `scripts/build-fr-wordlist.py` wrote `fr_forms.tsv`
/// from Lexique 3.83, and the headwords in `cefr_words_fr.tsv` come out of
/// the same table with the same rules, so speech and list can't disagree.
///
/// A row is: form TAB lemma (empty = itself, "-" = a function word) TAB class
/// TAB noun lemma after a determiner TAB verb lemma after a form of avoir.
/// The two context readings are the whole of what the table can't decide
/// alone: "l'été" is summer and "j'ai été" is être; "je suis fatigué" is the
/// adjective and "j'ai aimé" is aimer. `analyze` applies them; every reader
/// that has the whole sentence goes through it.
///
/// Elision: l', j', qu' and the rest are their own (function) words, so
/// "l'école" meets école; a word that keeps its apostrophe or hyphen as part
/// of itself (aujourd'hui, grand-mère, peut-être) is looked up whole first.
enum FrenchMorph {
    struct Entry: Equatable { let lemma: String; let wordClass: String }

    private struct Row { let lemma: String?; let wordClass: String; let noun: String?; let verb: String? }

    /// Each word of `text` with its range and what it reads as here (nil = a
    /// function word, or a word the table doesn't know).
    nonisolated static func analyze(_ text: String) -> [(word: String, range: Range<String.Index>, entry: Entry?)] {
        var out: [(String, Range<String.Index>, Entry?)] = []
        var previous: String?
        for (word, range) in words(in: text) {
            let key = normalized(word)
            out.append((word, range, reading(of: key, after: previous)))
            previous = key
        }
        return out
    }

    /// The headword a lone `form` belongs to, or the form itself (lowercased).
    /// With no sentence around it a function word with a noun reading is the
    /// noun ("personne" on its own is the noun).
    nonisolated static func lemma(of form: String) -> String {
        let key = normalized(form)
        guard let row = table[key] else { return key }
        return row.lemma ?? row.noun ?? key
    }

    /// The reading of a lone form (no context), nil for a function word.
    nonisolated static func entry(for form: String) -> Entry? {
        let key = normalized(form)
        guard let row = table[key] else { return nil }
        if let lemma = row.lemma { return Entry(lemma: lemma, wordClass: row.wordClass) }
        if let noun = row.noun { return Entry(lemma: noun, wordClass: "noun") }
        return nil
    }

    /// Lowercased, typographic apostrophe folded, and "oe" before u/i written
    /// as the ligature, which is how the table spells it (sœur, œil, cœur).
    nonisolated static func normalized(_ word: String) -> String {
        var w = word.lowercased().replacingOccurrences(of: "’", with: "'")
        if w.contains("oe") {
            w = w.replacingOccurrences(of: "oeu", with: "œu").replacingOccurrences(of: "oei", with: "œi")
        }
        return w
    }

    /// Words of `text`, cut the way the build cut Tatoeba
    /// (`scripts/build-fr-wordlist.py` `words`): a run of letters joined by
    /// apostrophes or hyphens is one word if the table knows it whole,
    /// otherwise it splits after each apostrophe (l' + école), then at
    /// hyphens the table doesn't know whole (dis-moi → dis + moi).
    nonisolated static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
        var out: [(String, Range<String.Index>)] = []
        for run in runs(in: text) {
            if table[normalized(String(text[run]))] != nil {
                out.append((String(text[run]), run))
                continue
            }
            for piece in split(text, run, after: { $0 == "'" || $0 == "’" }, keep: true) {
                let w = String(text[piece])
                if table[normalized(w)] != nil || !w.contains("-") {
                    out.append((w, piece))
                } else {
                    for part in split(text, piece, after: { $0 == "-" }, keep: false) {
                        out.append((String(text[part]), part))
                    }
                }
            }
        }
        return out
    }

    // MARK: - Context

    private static let determiners: Set<String> = [
        "le", "la", "l'", "les", "un", "une", "des", "du", "au", "aux", "ce", "cet",
        "cette", "ces", "mon", "ton", "son", "ma", "ta", "sa", "mes", "tes", "ses",
        "notre", "votre", "nos", "vos", "leur", "leurs", "chaque", "quel", "quelle",
        "quels", "quelles", "d'", "de",
    ]
    private static let avoir: Set<String> = [
        "ai", "as", "a", "avons", "avez", "ont", "avais", "avait", "avions", "aviez",
        "avaient", "aurai", "auras", "aura", "aurons", "aurez", "auront", "aurais",
        "aurait", "aurions", "auriez", "auraient", "eu", "ayant", "avoir", "aie", "ait",
        "ayons", "ayez", "aient", "eus", "eut", "eûmes", "eurent",
    ]

    private static func reading(of key: String, after previous: String?) -> Entry? {
        guard let row = table[key] else { return nil }
        if let noun = row.noun, let p = previous, determiners.contains(p) {
            return Entry(lemma: noun, wordClass: "noun")
        }
        if let verb = row.verb, let p = previous, avoir.contains(p) {
            return Entry(lemma: verb, wordClass: "verb")
        }
        return row.lemma.map { Entry(lemma: $0, wordClass: row.wordClass) }
    }

    // MARK: - Cutting

    private static func runs(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c.isLetter {
                if start == nil { start = i }
            } else if start != nil, c == "'" || c == "’" || c == "-",
                      let next = text.index(i, offsetBy: 1, limitedBy: text.endIndex),
                      next < text.endIndex, text[next].isLetter {
                // joiner between two letters: stays in the run
            } else if let s = start {
                out.append(s..<i)
                start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    /// Cuts `range` at every character `isCut` accepts: after it when `keep`
    /// (the apostrophe stays on l'), dropping it otherwise (the hyphen).
    private static func split(_ text: String, _ range: Range<String.Index>,
                              after isCut: (Character) -> Bool, keep: Bool) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start = range.lowerBound
        var i = range.lowerBound
        while i < range.upperBound {
            if isCut(text[i]) {
                let next = text.index(after: i)
                let end = keep ? next : i
                if start < end { out.append(start..<end) }
                start = next
            }
            i = text.index(after: i)
        }
        if start < range.upperBound { out.append(start..<range.upperBound) }
        return out
    }

    // MARK: - Table

    private static let table: [String: Row] = {
        guard let url = Bundle.main.url(forResource: "fr_forms", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: Row] = [:]
        out.reserveCapacity(95_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard p.count == 5 else { continue }   // the credit line has no tab
            let form = String(p[0])
            let lemma: String? = p[1] == "-" ? nil : (p[1].isEmpty ? form : String(p[1]))
            out[form] = Row(lemma: lemma, wordClass: String(p[2]),
                            noun: p[3].isEmpty ? nil : String(p[3]),
                            verb: p[4].isEmpty ? nil : String(p[4]))
        }
        return out
    }()
}
