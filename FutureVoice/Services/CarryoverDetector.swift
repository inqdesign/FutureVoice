import Foundation

/// Catches the moment a learner PRODUCES something they'd been studying —
/// a correction card from a past talk, or a suggestion given a few turns
/// earlier in this one — inside a real conversation.
///
/// This is the loop closing on itself, and it's invisible from the inside:
/// nobody notices themselves reaching for a phrase they were corrected on
/// last week. The app can, and saying so is worth more than any streak.
///
/// **Deterministic on purpose.** No LLM call is added here — the summary call
/// stays the only one per session (see CLAUDE.md). More importantly, a single
/// false positive ("you used *nevertheless* today!" when they didn't) poisons
/// every number on the page, so every rule below errs toward missing a hit
/// rather than inventing one:
///
///   • the item needs `minContentTokens` non-filler tokens — "thanks a lot"
///     can't score a hit off ordinary small talk;
///   • its tokens must appear **in order**, inside **one** user turn, within a
///     bounded window — words scattered across a minute-long ramble aren't a
///     phrase, they're a coincidence;
///   • only the user's own turns are ever searched, and turns they flagged as
///     misheard are excluded;
///   • every hit carries the learner's own sentence, so the wrap-up shows
///     evidence instead of asserting a claim.
enum CarryoverDetector {

    /// Shortest item worth crediting, in words.
    static let minTokens = 3

    /// …of which at least this many must carry meaning. Together these reject
    /// "how are you" (three words, one of them contentful) while keeping
    /// "it slipped my mind" — idioms are mostly function words, and function
    /// words are exactly what makes an idiom an idiom.
    static let minContentTokens = 2

    /// Share of the item's words that must land, in order.
    static let minCoverage = 0.8

    // MARK: - Detection

    /// - Parameters:
    ///   - turns: the finished conversation, in order.
    ///   - cards: every drill card on disk. Cards born from THIS session are
    ///     filtered out here — a correction minted at the end of a call can't
    ///     have been carried into it.
    ///   - curriculumItems: un-mastered study items from the learner's Watch
    ///     books, flattened by the caller so this stays free of store lookups.
    ///   - studyingExpressions: phrases bookmarked in the notebook
    ///     (`VocabStore.studyingExpressions`), lowercased keys.
    ///   - studyingWords: headwords collected into the notebook
    ///     (`VocabStore.studying`). Matched by lemma, not by string.
    ///   - knownExpressions / knownWords: items the learner MARKED known and
    ///     has never yet said in a talk. "Known" is their own verdict; a hit
    ///     here is the talk confirming it, which is the whole point of the
    ///     Known state existing.
    ///   - sessionStartedAt: cutoff for "the user already had this".
    /// A Watch book's study item, flattened for matching. `isWord` picks the
    /// matcher: single words go by lemma, expressions and shadow lines go
    /// through the phrase rules.
    struct CurriculumItem {
        let id: UUID
        let text: String
        let isWord: Bool
    }

    static func detect(
        in turns: [Turn],
        cards: [DrillCard],
        curriculumItems: [CurriculumItem] = [],
        studyingExpressions: [String] = [],
        studyingWords: [String] = [],
        knownExpressions: [String] = [],
        knownWords: [String] = [],
        sessionId: UUID,
        sessionStartedAt: Date,
        now: Date = Date()
    ) -> [Carryover] {
        let userTurns = turns.filter { $0.role == .user && !$0.excludedFromScoring }
        guard !userTurns.isEmpty else { return [] }

        var out: [Carryover] = []
        // One item is credited once per session, even if it shows up as both a
        // card and a suggestion.
        var claimed = Set<String>()
        // …and one SENTENCE earns at most one credit. Near-duplicate study
        // items ("I'm in a good mood today" / "I'm just in a good mood today")
        // otherwise all match the same utterance and the section turns into
        // three rows quoting one thing the learner said once.
        var creditedTurns = Set<UUID>()

        func claim(_ key: String, _ hit: Hit, source: Carryover.Source,
                   item: String, sourceId: UUID?) {
            claimed.insert(key)
            creditedTurns.insert(hit.turnId)
            out.append(Carryover(
                sessionId: sessionId, source: source, item: item,
                quote: hit.quote, turnId: hit.turnId, sourceId: sourceId, detectedAt: now))
        }

        /// Sources run heaviest-first, so the first claim on a sentence wins.
        func available(_ key: String) -> Bool { !key.isEmpty && !claimed.contains(key) }
        func free(_ hit: Hit) -> Bool { !creditedTurns.contains(hit.turnId) }

        // ── Cards from earlier talks, said unprompted today. The biggest win
        // the app can detect: a correction survived the gap between sessions.
        for card in cards
        where card.sourceSessionId != sessionId && card.createdAt < sessionStartedAt {
            let key = normalized(card.targetPhrase)
            guard available(key),
                  let hit = firstMatch(of: card.targetPhrase, in: userTurns,
                                       rejectingMistake: card.sourcePhrase),
                  free(hit) else { continue }
            claim(key, hit, source: .drillCard, item: card.targetPhrase, sourceId: card.id)
        }

        // ── Material from a Watch book, produced in a live talk. The book's
        // own mastery pass only looks at talks whose topic matches the book
        // title and compares exact strings, so material carried into an
        // unrelated conversation — the better win — goes unnoticed there.
        for item in curriculumItems {
            let key = normalized(item.text)
            guard available(key) else { continue }
            let match = item.isWord
                ? firstLemmaMatch(of: key, in: userTurns)
                : firstMatch(of: item.text, in: userTurns)
            guard let hit = match, free(hit) else { continue }
            claim(key, hit, source: .curriculumItem, item: item.text, sourceId: item.id)
        }

        // ── Phrases they'd deliberately bookmarked to study, then said. The
        // notebook is checked directly, so this doesn't depend on the summary
        // LLM happening to notice the phrase.
        for phrase in studyingExpressions {
            let key = normalized(phrase)
            guard available(key),
                  let hit = firstMatch(of: phrase, in: userTurns),
                  free(hit) else { continue }
            claim(key, hit, source: .studyingExpression, item: phrase, sourceId: nil)
        }

        // ── Expressions they'd declared known, now said for real.
        for phrase in knownExpressions {
            let key = normalized(phrase)
            guard available(key),
                  let hit = firstMatch(of: phrase, in: userTurns),
                  free(hit) else { continue }
            claim(key, hit, source: .knownExpression, item: phrase, sourceId: nil)
        }

        // ── Suggestions from earlier in THIS call, applied later in it.
        // `Turn.suggestion` hangs off the user turn it rewrites, so adoption
        // can only be claimed from a turn AFTER that one.
        //
        // What counts as "the suggestion" depends on when it was written.
        // Since 2026-09-27 `alternative` is the WHOLE turn re-said — nobody
        // says a whole turn again word for word, so matching it would credit
        // nothing ever again. What a learner can adopt is a FIX, and it is
        // matched as the card it became (`DrillStore.cardPair`), rejecting a
        // span that still carries the mistake — the same test the deck's
        // cards get, since `SessionSummarizer` confirms the card by this
        // item's text. A turn from before `fixes` keeps the old rule: its
        // `alternative` was the one-sentence correction.
        for (index, turn) in userTurns.enumerated() {
            guard let suggestion = turn.suggestion else { continue }
            let later = Array(userTurns.dropFirst(index + 1))
            guard !later.isEmpty else { continue }
            let adoptable: [(source: String?, target: String)] = suggestion.fixes.map { fixes in
                fixes.map { fix in
                    let pair = DrillStore.cardPair(for: fix, in: turn.transcript)
                    return (Optional(pair.source), pair.target)
                }
            } ?? [(nil, suggestion.alternative)]
            for item in adoptable {
                let key = normalized(item.target)
                guard available(key) else { continue }
                // If the turn that EARNED the suggestion already matches it,
                // the learner was saying this before the suggestion existed —
                // repeating themselves isn't adopting anything.
                guard firstMatch(of: item.target, in: [turn],
                                 rejectingMistake: item.source) == nil else { continue }
                guard let hit = firstMatch(of: item.target, in: later,
                                           rejectingMistake: item.source),
                      free(hit) else { continue }
                claim(key, hit, source: .suggestion, item: item.target, sourceId: turn.id)
            }
        }

        // ── Notebook words. Single words can't go through the phrase matcher
        // (one token, no order to check), so they're matched by LEMMA — "I
        // commuted for years" credits *commute*. That's `VocabStore`'s job:
        // it knows whether this learner's language wants NLTagger or
        // `KoreanMorph`.
        //
        // A word already sitting inside a credited phrase is skipped: seeing
        // "It slipped my mind" and then "mind" as separate rows reads like the
        // app padding its own scorecard.
        let claimedWords = Set(claimed.flatMap { tokens($0) })
        var wordHits: [(word: String, hit: Hit, rank: Int, source: Carryover.Source)] = []
        var seenWords = Set<String>()
        for (list, source) in [(studyingWords, Carryover.Source.studyingWord),
                               (knownWords, Carryover.Source.knownWord)] {
            for word in list {
                let key = normalized(word)
                guard !key.isEmpty, !claimedWords.contains(key), seenWords.insert(key).inserted,
                      let hit = firstLemmaMatch(of: key, in: userTurns),
                      !creditedTurns.contains(hit.turnId) else { continue }
                let rank = CoreVocabulary.level(of: key).map { CoreVocabulary.levelRank($0) } ?? 0
                wordHits.append((key, hit, rank, source))
            }
        }
        // Hardest words first, then capped: a learner with a big notebook can
        // hit a dozen in one talk, and a dozen rows buries the phrases above.
        // The cap is on DISPLAY, and the count reported alongside it is the
        // real one — see `SessionSummary.carryovers`.
        for entry in wordHits.sorted(by: { $0.rank > $1.rank }).prefix(maxWordCarryovers) {
            out.append(Carryover(
                sessionId: sessionId, source: entry.source, item: entry.word,
                quote: entry.hit.quote, turnId: entry.hit.turnId,
                sourceId: nil, detectedAt: now))
        }

        return out
    }

    /// Words shown per session. Phrases are the headline; words are the
    /// supporting cast and shouldn't outnumber them on screen.
    static let maxWordCarryovers = 5

    // MARK: - Matching

    struct Hit {
        /// The learner's own sentence — the one that corresponds to the item,
        /// not the whole turn (turns run long).
        let quote: String
        let turnId: UUID
    }

    /// First user turn that contains `item`. Earliest turn wins so the quote
    /// points at the moment they reached for it, not a later repetition.
    ///
    /// `rejectingMistake`: for a correction card, the line the card was
    /// minted to FIX. The phrase matcher tolerates inserted words, which is
    /// right for padding ("I'd rather *just* stay in") and wrong for the one
    /// case a card exists for: "give me a feedback" contains every token of
    /// "give me feedback", in order, and was credited as the correction
    /// while being the exact mistake (real talk, 2026-09-16). So the matched
    /// span has to show the fix: every word the correction ADDED must be
    /// there, and no word it REMOVED may be.
    static func firstMatch(of item: String, in userTurns: [Turn],
                           rejectingMistake source: String? = nil) -> Hit? {
        let korean = isKorean
        let politeFree = korean && source == nil
        let needle = tokens(item).map { politeFree ? strippingPolite($0) : $0 }
        let core = politeFree ? needle : contentTokens(item)
        guard needle.count >= minTokensNow, core.count >= minContentTokensNow else { return nil }
        let koreanNeedle = korean ? koreanKey(item, politeFree: politeFree) : ""
        if korean, koreanNeedle.count < minKoreanSyllables { return nil }
        for turn in userTurns {
            let hay = tokens(turn.transcript).map { politeFree ? strippingPolite($0) : $0 }
            if let span = matchedSpan(needle, core: core, in: hay) {
                if let source, !showsTheFix(from: source, to: item, in: span) { continue }
            } else if korean, koreanKey(turn.transcript, politeFree: politeFree).contains(koreanNeedle) {
                // Same syllables, spaced differently. The match is the
                // phrase itself, contiguous — a correction's fix is in it by
                // construction and its mistake cannot be, so there is nothing
                // for `showsTheFix` to reject.
            } else {
                continue
            }
            return Hit(
                quote: DrillStore.relevantFragment(of: turn.transcript, matching: item),
                turnId: turn.id)
        }
        return nil
    }

    /// Does `span` (the learner's matched words) carry the correction and
    /// not the mistake? Tokens the target added must all be present; tokens
    /// it dropped must all be absent. A card with no source line (a suggested
    /// drill) or a source identical to its target has nothing to check.
    static func showsTheFix(from source: String, to target: String, in span: [String]) -> Bool {
        let before = tokens(source), after = tokens(target)
        guard !before.isEmpty, before != after else { return true }
        let added = Set(after).subtracting(before)
        let removed = Set(before).subtracting(after)
        let said = Set(span)
        return added.isSubset(of: said) && removed.isDisjoint(with: said)
    }

    /// Could this phrase EVER be credited? The token bars in `firstMatch`
    /// reject an item before any transcript is looked at, so a phrase that
    /// fails here can never come back as a hit no matter what the learner says.
    ///
    /// Live surfaces need to ask this BEFORE they promise anything: a chip
    /// offering "thanks a lot" as something to use today is a checkbox that
    /// cannot tick, and one of those teaches the learner the whole row is
    /// decorative.
    static func isCreditable(_ phrase: String) -> Bool {
        tokens(phrase).count >= minTokensNow && contentTokens(phrase).count >= minContentTokensNow
            && (!isKorean || koreanKey(phrase, politeFree: false).count >= minKoreanSyllables)
    }

    /// The bars above are written for a spaced language, where a single
    /// word has its own matcher (`firstLemmaMatch`) and three words are the
    /// shortest thing worth calling a phrase. In Japanese a token is a
    /// segment — なるほど, ただいま, 気をつけて are one, one and four — and a
    /// segment has no other way in, so the floor is one word and one
    /// meaning-carrying token. Generic small talk is still bounded by the
    /// order-and-window rule; the genericness gate was English-only anyway.
    ///
    /// Korean is spaced but takes the same floor as Japanese, for a
    /// different reason: an eojeol is a word WITH its particles and endings,
    /// so a two-eojeol phrase is a whole expression (잘 모르겠어, 그럴 리가)
    /// and a three-word bar left most Korean expressions uncreditable. Its
    /// floor is `minKoreanSyllables` instead — and there is no filler list,
    /// so every eojeol must land, in order.
    private static var minTokensNow: Int { WordSplitter.spaced && !isKorean ? minTokens : 1 }
    private static var minContentTokensNow: Int { WordSplitter.spaced && !isKorean ? minContentTokens : 1 }

    /// Shortest Korean phrase worth crediting, in syllables (spaces ignored).
    /// 잘 가 (2) is small talk; 그러게 / 잘 모르겠어 are not.
    static let minKoreanSyllables = 3

    private static var isKorean: Bool { LanguageCatalog.base(LanguageScope.active) == "ko" }

    /// A Korean phrase as one comparable string: tokens joined with NO
    /// space, because 띄어쓰기 is the recognizer's (할수 있어 / 할 수 있어).
    /// `politeFree` also drops the polite 요 at the end of each eojeol, so
    /// 잘 모르겠어 is credited when it comes out as 잘 모르겠어요 — the
    /// speech level is the learner's, the expression is the same. Never for
    /// a correction card: there the speech level can be the fix itself.
    private static func koreanKey(_ text: String, politeFree: Bool) -> String {
        tokens(text).map { politeFree ? strippingPolite($0) : $0 }.joined()
    }

    private static func strippingPolite(_ token: String) -> String {
        token.count > 1 && token.hasSuffix("요") ? String(token.dropLast()) : token
    }

    /// First user turn that used `lemma`. Lemma-based, so the notebook's
    /// headword matches whatever form the learner actually inflected it into.
    static func firstLemmaMatch(of lemma: String, in userTurns: [Turn]) -> Hit? {
        for turn in userTurns {
            guard VocabStore.lemmas(in: [turn.transcript]).contains(lemma) else { continue }
            return Hit(
                quote: DrillStore.relevantFragment(of: turn.transcript, matching: lemma),
                turnId: turn.id)
        }
        return nil
    }

    /// In-order coverage inside a bounded window. The window is what separates
    /// a phrase from a coincidence: the same words scattered across a
    /// minute-long turn are not the learner reaching for what they studied.
    ///
    /// Note how the bar tightens as items get shorter — at 3 or 4 words
    /// `required` rounds up to the whole phrase, so short items must match
    /// exactly, in order. That's deliberate: short items are the ones generic
    /// enough to hit by accident.
    private static func contains(_ needle: [String], core: [String], in hay: [String]) -> Bool {
        matchedSpan(needle, core: core, in: hay) != nil
    }

    /// The learner's words that matched, trimmed to the phrase itself — from
    /// the first token of the item to its last — so a check on what was said
    /// AROUND the phrase can't be fooled by the rest of the window.
    private static func matchedSpan(_ needle: [String], core: [String], in hay: [String]) -> [String]? {
        guard !needle.isEmpty, hay.count >= minTokensNow else { return nil }
        // Room for the learner to pad the phrase out — "I'd rather just stay
        // in tonight, honestly" still counts.
        let window = needle.count * 2 + 4
        let required = Int((Double(needle.count) * minCoverage).rounded(.up))
        guard hay.count >= required else { return nil }
        for start in 0...(hay.count - required) {
            let slice = Array(hay[start..<min(hay.count, start + window)])
            guard lcsLength(needle, slice) >= required else { continue }
            // EVERY meaning-carrying word, in order — no partial credit here.
            //
            // Coverage alone is not enough, and this isn't hypothetical: a card
            // reading "I'm in a SWEET mood today" matched "I'm in a really GOOD
            // mood today", because the one word that made the phrase worth
            // studying was the one allowed to go missing. Function words may
            // slip — that's what `minCoverage` is for. Content words may not.
            guard lcsLength(core, slice.filter { !isFiller($0) }) == core.count
            else { continue }
            // Trim to the phrase: from where the item's first word lands to
            // where its last word does (the function-word ends may have
            // slipped, in which case the whole slice stands).
            let lo = slice.firstIndex(of: needle[0]) ?? 0
            let hi = slice.lastIndex(of: needle[needle.count - 1]).map { max($0, lo) } ?? slice.count - 1
            return Array(slice[lo...hi])
        }
        return nil
    }

    /// Longest common subsequence length — order-preserving overlap that
    /// tolerates one dropped or swapped word without accepting a reordered
    /// sentence.
    private static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var cur = [Int](repeating: 0, count: b.count + 1)
            for j in 1...b.count {
                cur[j] = a[i - 1] == b[j - 1]
                    ? prev[j - 1] + 1
                    : max(prev[j], cur[j - 1])
            }
            prev = cur
        }
        return prev[b.count]
    }

    // MARK: - Tokenizing

    /// Lowercased, punctuation stripped, whitespace collapsed — the same
    /// normalization `DrillStore` matches quotes with, so a card and a
    /// transcript compare on equal terms despite STT casing/punctuation drift.
    static func normalized(_ text: String) -> String {
        // One pass, no intermediate arrays. This runs twice per sentence of
        // every talk-book build (`TalkCurriculum.shadowPicks`), and the
        // filter → lowercased → components → joined chain was most of a
        // warm build's time (2026-09-23). Same output as that chain: letters
        // and digits kept, runs of spaces/tabs collapsed to one, newlines
        // and everything else dropped outright, then lowercased.
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if Self.normalizedKept.contains(scalar) {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else if Self.normalizedSpace.contains(scalar) {
                pendingSpace = true
            }
        }
        return String(out).lowercased()
    }

    private static let normalizedKept = CharacterSet.alphanumerics
    private static let normalizedSpace = CharacterSet.whitespaces

    /// Words, normalized. An unspaced language is segmented FIRST and each
    /// segment normalized after — `normalized` keeps letters and spaces, and
    /// a Japanese sentence has neither space nor case to lose, so the two
    /// orders agree; segmenting the raw text just lets the tokenizer see its
    /// punctuation, which is how it tells clauses apart.
    private static func tokens(_ text: String) -> [String] {
        WordSplitter.spaced
            ? normalized(text).split(separator: " ").map(String.init)
            : JapaneseMorph.segments(in: text).map(normalized).filter { !$0.isEmpty }
    }

    /// Used ONLY to judge whether an item is too generic to be worth
    /// crediting — never to match, because dropping function words would let
    /// "how ARE you" and "how DO you" collapse into the same phrase.
    private static func contentTokens(_ text: String) -> [String] {
        tokens(text).filter { !isFiller($0) }
    }

    private static func isFiller(_ token: String) -> Bool {
        WordSplitter.spaced ? filler.contains(token) : JapaneseMorph.isFunctionToken(token)
    }

    /// Grammatical filler — words whose presence says nothing about whether
    /// the learner studied anything. The list is English-only by design: for
    /// other spaced target languages nothing is dropped, so the genericness
    /// gate is simply easier to clear (Japanese has its own list — the
    /// particles and auxiliaries `JapaneseMorph` already knows). It gates, it
    /// never matches, so the worst case is admitting a short item — the
    /// order and window rules still decide.
    private static let filler: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "if", "of", "to", "in", "on",
        "at", "for", "with", "is", "am", "are", "was", "were", "be", "been",
        "do", "does", "did", "have", "has", "had", "i", "you", "he", "she", "it",
        "we", "they", "me", "him", "her", "them", "my", "your", "its", "that",
        "this", "there", "as", "by", "from", "im", "ive", "id", "ill", "its",
        "dont", "doesnt", "didnt", "youre", "youve", "well", "just", "very",
    ]
}
