import Foundation

/// The glossary at the back of an exported book: every word and expression it
/// teaches, with its part of speech, meanings, and one example.
///
/// The entries are NOT generated for the export. They come from `WordLore`,
/// which reads the shared `word_entry` table — the same dictionary the
/// Vocabulary screen shows, already written for most terms because some
/// learner (often this one) tapped them. So a glossary usually costs a few
/// cached reads and nothing else.
///
/// Failure is silent by design: a book that exports without a glossary is
/// still the book. Nothing here may block the file from being written.
@MainActor
enum BookGlossary {

    /// Never look up more than this many terms for one book. A long Talk book
    /// can list dozens of words, and an export that fans out to all of them
    /// turns a share sheet into a network operation with no ceiling.
    static let maxTerms = 40

    /// Give up after this long in total. The export must stay a
    /// press-and-get-a-file action; a slow dictionary can cost the glossary,
    /// never the book.
    static let budget: Duration = .seconds(8)

    /// Builds the section, or nil when nothing could be looked up.
    ///
    /// The budget is enforced HERE, by racing the whole lookup against a
    /// sleep. It has to be: `WordLore` talks to the network and nothing in
    /// that path promises to return, so an unenforced budget means an export
    /// that never reaches the file write — which is exactly what happened.
    static func section(for doc: BookDocument,
                        native: String,
                        target: String) async -> BookDocument.Section? {
        await withTaskGroup(of: BookDocument.Section?.self) { race in
            race.addTask { @MainActor in
                await build(for: doc, native: native, target: target)
            }
            race.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            // Whichever finishes first decides; the loser is cancelled and
            // its result discarded.
            let first = await race.next() ?? nil
            race.cancelAll()
            return first
        }
    }

    private static func build(for doc: BookDocument,
                              native: String,
                              target: String) async -> BookDocument.Section? {
        // De-duplicate case-insensitively but keep the first spelling: the
        // book should gloss the word as the learner met it.
        var seen = Set<String>()
        let terms = doc.terms.filter { term in
            let key = term.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }.prefix(maxTerms)
        guard !terms.isEmpty else { return nil }

        let entries = await withTaskGroup(of: (Int, BookDocument.Entry?).self) { group in
            for (i, term) in terms.enumerated() {
                group.addTask { @MainActor in
                    let entry = await WordLore.entry(
                        for: term.text, native: native, target: target,
                        kind: term.isExpression ? .expression : .word)
                    return (i, entry.map { render(term: term.text, $0) })
                }
            }
            // Keep the book's order, not the order the network answered in.
            var out = [(Int, BookDocument.Entry)]()
            for await (i, entry) in group {
                if let entry { out.append((i, entry)) }
            }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }

        guard !entries.isEmpty else { return nil }
        return BookDocument.Section(title: chrome("Glossary"), entries: entries)
    }

    /// One dictionary entry flattened into the book's `Entry` shape: the
    /// senses become the note, and the first example (with its translation)
    /// becomes the example line. The book model stays two fields wide on
    /// purpose — every section renders through the same two renderers.
    private static func render(term: String, _ entry: WordEntry) -> BookDocument.Entry {
        var parts: [String] = []
        for sense in entry.senses {
            let pos = sense.pos.trimmingCharacters(in: .whitespaces)
            let meaning = sense.meaning.trimmingCharacters(in: .whitespaces)
            guard !meaning.isEmpty else { continue }
            parts.append(pos.isEmpty ? meaning : "\(pos) \(meaning)")
        }
        // No senses is a malformed entry — gloss it with the headline part of
        // speech rather than emitting a bare word with an empty note.
        if parts.isEmpty, let pos = entry.pos, !pos.isEmpty { parts.append(pos) }

        var example = ""
        if let first = entry.examples.first {
            example = first.text
            if let meaning = first.meaning?.trimmingCharacters(in: .whitespaces), !meaning.isEmpty {
                example += " — \(meaning)"
            }
        } else if let phrase = entry.phrases.first {
            example = "\(phrase.phrase) — \(phrase.meaning)"
        }

        return BookDocument.Entry(text: term,
                                  note: parts.joined(separator: " · "),
                                  example: example)
    }
}
