import SwiftUI

/// What the learner is studying, put in front of them WHILE they talk.
///
/// The notebook has always been a place you go to; a talk is the only place
/// the words can actually be spent. Between the two there was nothing —
/// nobody remembers, mid-sentence, that they saved *commute* on Tuesday. This
/// is that reminder: one line above the transcript, and the chip ticks itself
/// the moment the word comes out of the learner's mouth.
///
/// **The judge is `CarryoverDetector`, not a second rule.** The same matcher
/// decides the wrap-up's "you used what you'd been studying" section at the
/// end of the call, so the chip that ticked live and the line in the summary
/// can never disagree — and a live tick can never be a false positive the
/// summary then quietly drops.
///
/// Nothing here writes to disk. Crediting the word for real is
/// `VocabStore.ingest` + `CarryoverDetector.detect` at session end, on the
/// finished transcript; this row only shows what that pass will find.
struct TalkGoalItem: Identifiable, Equatable {
    /// Normalized — the key the detector matches on, and what the caller
    /// tracks as "already ticked".
    let key: String
    /// What the learner saved, drawn as they saw it.
    let text: String
    /// Single words go by lemma ("I commuted for years" ticks *commute*);
    /// everything else goes through the phrase rules.
    let isWord: Bool
    /// The learner MARKED this known and has never said it in a talk. It is
    /// a claim, and the call is where the claim gets checked — which is why
    /// these lead the row and wear a different empty circle.
    var claimedKnown: Bool = false
    /// For an item that came out of a scenario book: the sentence its scene
    /// uses it in, and the one-line usage hint written beside it. The chip
    /// sheet shows THAT example — a word offered because of this scene is
    /// best explained by this scene, not by a dictionary's generic line.
    var example: String? = nil
    var note: String? = nil

    var id: String { key }
}

@MainActor
enum TalkGoalPicker {

    /// One line, and a chip has to be readable at a glance from a call screen
    /// the learner is not looking at. Past five nobody reads the row.
    static let maxItems = 5

    /// Phrases are long. Two is enough to be worth reaching for without the
    /// short, scannable words being pushed off screen.
    static let maxExpressions = 2

    /// What the call should check first, then what the learner is studying.
    ///
    /// **Items they marked known lead.** "Known" is the learner's own verdict
    /// and a talk is the one place it can be confirmed, so unconfirmed known
    /// words and expressions come before the notebook. They have no schedule
    /// (retiring cleared it), so they rotate by the day like never-scheduled
    /// notebook entries do.
    ///
    /// For studying items, due-ness comes from `StudyScheduleStore` — the same
    /// schedule the daily words/expressions sessions deal from — so an item
    /// snoozed to "3 days" stays out of the row too, and the app never asks
    /// for the same thing in two voices on the same day. Nothing tops the
    /// list up from the core wordlist: this row is about what the learner
    /// CHOSE to study or claimed to know.
    static func pick(limit: Int = maxItems,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> [TalkGoalItem] {
        let store = VocabStore.shared

        // Newest verdict first, which `ordered` then rotates oldest-first.
        let knownPhrases = rotated(
            store.unconfirmedKnownExpressions
                .sorted { (store.expressionRecords[$0]?.lastAt ?? .distantPast)
                        > (store.expressionRecords[$1]?.lastAt ?? .distantPast) },
            now: now, calendar: calendar)
            .filter { CarryoverDetector.isCreditable($0) }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0,
                                isWord: false, claimedKnown: true) }
        let knownWords = rotated(
            store.unconfirmedKnownWords
                .sorted { (store.lastAt(of: $0) ?? .distantPast) > (store.lastAt(of: $1) ?? .distantPast) },
            now: now, calendar: calendar)
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0,
                                isWord: WordSplitter.isSingleWord($0), claimedKnown: true) }
            .filter { $0.isWord || CarryoverDetector.isCreditable($0.text) }

        let studyingPhrases = ordered(store.studyingExpressions.filter { !store.hasUsedExpression($0) },
                                      kind: .expression, now: now, calendar: calendar)
            .filter { CarryoverDetector.isCreditable($0) }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0, isWord: false) }

        let studyingWords = ordered(store.practicedStudyingWords, kind: .word, now: now, calendar: calendar)
            .map { word -> TalkGoalItem in
                // A multi-word entry can land in the notebook (a learner taps a
                // two-word chunk in a transcript); it can't be lemma-matched, so
                // it goes through the phrase rules instead.
                let single = WordSplitter.isSingleWord(word)
                return TalkGoalItem(key: CarryoverDetector.normalized(word),
                                    text: word, isWord: single)
            }
            .filter { $0.isWord || CarryoverDetector.isCreditable($0.text) }

        return merge(words: knownWords + studyingWords,
                     phrases: knownPhrases + studyingPhrases, limit: limit)
    }

    /// The row for a talk ON A SCENARIO BOOK: the book's own material first.
    ///
    /// A learner re-running one scene until they can do it with confidence
    /// wants the words THAT scene taught, not whatever the notebook happens
    /// to deal today — and the book already knows which of its items are
    /// still unmastered (`refreshScenarioMastery` ticks them off from every
    /// talk on the scene, so the loop closes without any new write). Three
    /// sources, in order, then the global row fills whatever is left:
    ///
    /// 1. the book's unmastered words and expressions;
    /// 2. what the fluent self OFFERED in the previous talks on this scene
    ///    (`expressionsOffered`, pickup words) that the learner has never
    ///    said — related by construction, since they came out of this exact
    ///    conversation;
    /// 3. `pick()` — the notebook and the unconfirmed claims, as on any call.
    ///
    /// Book items ignore `StudyScheduleStore` on purpose: the daily deck's
    /// "not twice in one day" rule protects the learner from being asked the
    /// same thing in two voices, but here the learner chose the scene, and
    /// the scene is the reason to ask. The book's lists rotate by how many
    /// talks the scene has had, so the fourth run doesn't lead with the same
    /// five words as the first — unmastered items stay in the pool, they
    /// just take turns at the front.
    static func pick(forScenario scenario: Scenario,
                     previousTalks: [Session],
                     proficiency: CEFRLevel,
                     limit: Int = maxItems,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> [TalkGoalItem] {
        let store = VocabStore.shared
        let runs = previousTalks.count

        func bookItem(_ item: ScenarioCurriculum.Item) -> TalkGoalItem {
            TalkGoalItem(key: CarryoverDetector.normalized(item.text), text: item.text,
                         isWord: WordSplitter.isSingleWord(item.text),
                         example: item.example,
                         note: item.note.isEmpty ? nil : item.note)
        }

        let curriculum = scenario.curriculum
        let bookWords = rotated(by: runs, (curriculum?.words ?? [])
            .filter { $0.masteredAt == nil }.map(bookItem))
            .filter { $0.isWord || CarryoverDetector.isCreditable($0.text) }
        let bookPhrases = rotated(by: runs, (curriculum?.expressions ?? [])
            .filter { $0.masteredAt == nil }.map(bookItem))
            .filter { CarryoverDetector.isCreditable($0.text) }

        // The previous talks, newest first: their offered phrases and pickup
        // words the learner still hasn't produced. The learner's own lemmas
        // are excluded from the pickups the same way the talk book excludes
        // them — a word they said is not one the scene has to teach.
        let talks = previousTalks.sorted { $0.startedAt > $1.startedAt }
        let offered = talks
            .flatMap { $0.summary?.expressionsOffered ?? [] }
            .filter { !store.hasUsedExpression($0) && CarryoverDetector.isCreditable($0) }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0, isWord: false) }
        let fluentTexts = talks.flatMap { $0.turns.filter { $0.role == .fluentSelf }.map(\.transcript) }
        let userLemmas = VocabStore.lemmas(in: talks.flatMap { $0.turns.filter { $0.role == .user }.map(\.transcript) })
        let pickups = fluentTexts.isEmpty ? [] : store
            .pickupCandidates(fromFluentTexts: fluentTexts, atOrAbove: proficiency,
                              excludingLemmas: userLemmas)
            .filter { store.state(of: $0) == nil }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0, isWord: true) }

        // The brief's key expressions lead the phrases: the learner attached
        // the posting for exactly this, and the phrases the reading pulled
        // out of it are the ones the call is there to try. Anything already
        // used in a talk has done its job and is not asked for again.
        let briefPhrases = rotated(by: runs, (scenario.brief?.keyExpressions ?? [])
            .filter { !store.hasUsedExpression($0) && CarryoverDetector.isCreditable($0) }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0,
                                isWord: WordSplitter.isSingleWord($0)) })

        // The scene's own material fills the row first; the notebook only
        // tops up what the scene left empty, so a global phrase can never
        // take a slot from a word this book is still teaching.
        var out = merge(words: bookWords + pickups, phrases: briefPhrases + bookPhrases + offered, limit: limit)
        if out.count < limit {
            var seen = Set(out.map(\.key))
            for item in pick(limit: limit, now: now, calendar: calendar) where out.count < limit {
                guard seen.insert(item.key).inserted else { continue }
                out.append(item)
            }
        }
        return out
    }

    /// Interleave so the row opens with something short: a phrase first
    /// would fill the visible width on its own and the words would only
    /// exist for whoever scrolls. Phrases are capped at `maxExpressions`.
    /// Coach mode's extra pool: notebook words a TALK kept on its own
    /// (`VocabStore.autoKept`) that the chip row leaves out. The row is about
    /// what the learner chose, but most notebooks fill this way, and a coach
    /// with nothing to coach is a switch that does nothing (the first device
    /// test, 2026-09-28: eleven words on file, all auto-kept, no hint ever).
    /// These are words the fluent self taught them — fair to steer toward.
    static func coachExtras(excluding keys: Set<String>,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [TalkGoalItem] {
        let store = VocabStore.shared
        let practiced = Set(store.practicedStudyingWords)
        return ordered(store.studying.filter { !practiced.contains($0) },
                       kind: .word, now: now, calendar: calendar)
            .filter { WordSplitter.isSingleWord($0) }
            .map { TalkGoalItem(key: CarryoverDetector.normalized($0), text: $0, isWord: true) }
            .filter { !keys.contains($0.key) }
    }

    private static func merge(words: [TalkGoalItem], phrases: [TalkGoalItem],
                              limit: Int) -> [TalkGoalItem] {
        let phrases = Array(phrases.prefix(maxExpressions))
        var out: [TalkGoalItem] = []
        var w = words.makeIterator()
        var p = phrases.makeIterator()
        var seen = Set<String>()
        var takeWord = true
        while out.count < limit {
            let next = takeWord ? (w.next() ?? p.next()) : (p.next() ?? w.next())
            guard let item = next else { break }
            takeWord.toggle()
            guard !item.key.isEmpty, seen.insert(item.key).inserted else { continue }
            out.append(item)
        }
        return out
    }

    /// A book list, shifted by how many times the scene has been talked
    /// through — every run leads with a different slice of what's left.
    private static func rotated(by runs: Int, _ items: [TalkGoalItem]) -> [TalkGoalItem] {
        guard items.count > 1 else { return items }
        let offset = runs % items.count
        return Array(items[offset...] + items[..<offset])
    }

    /// Never-scheduled items (a newest-first list), oldest first and rotated
    /// by the day, so a long list doesn't lead with the same five forever.
    private static func rotated(_ newestFirst: [String], now: Date,
                                calendar: Calendar) -> [String] {
        guard !newestFirst.isEmpty else { return [] }
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let oldestFirst = Array(newestFirst.reversed())
        let offset = day % oldestFirst.count
        return Array(oldestFirst[offset...] + oldestFirst[..<offset])
    }

    /// Overdue-scheduled first (earliest return first), then never-scheduled,
    /// oldest save first and rotated by the day so a big notebook doesn't deal
    /// the same five forever. Same ordering as `DailyWordsView.pick`.
    private static func ordered(_ items: [String], kind: StudyScheduleStore.Kind,
                                now: Date, calendar: Calendar) -> [String] {
        let schedule = StudyScheduleStore.shared
        let due = items.filter { schedule.isDue(kind, $0, now: now) }
        let scheduled = due
            .compactMap { item in schedule.nextReview(kind, item).map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let unscheduled = due.filter { schedule.nextReview(kind, $0) == nil }
        guard !unscheduled.isEmpty else { return scheduled }
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let oldestFirst = Array(unscheduled.reversed())   // the store keeps newest-first
        let offset = day % oldestFirst.count
        return scheduled + Array(oldestFirst[offset...] + oldestFirst[..<offset])
    }

    /// Which of `items` this turn just produced. Additive by design — the
    /// caller keeps the ticks it already has, so a later, better transcript of
    /// the same turn can add a tick but never take one back. A check that
    /// disappears mid-call reads as the app changing its mind about the
    /// learner.
    static func hits(in turn: Turn, among items: [TalkGoalItem]) -> Set<String> {
        guard turn.role == .user, !turn.excludedFromScoring,
              !turn.transcript.isEmpty, !items.isEmpty else { return [] }
        var out = Set<String>()
        var lemmas: Set<String>?          // one NLTagger pass per turn, at most
        for item in items {
            if item.isWord {
                let found = lemmas ?? VocabStore.lemmas(in: [turn.transcript])
                lemmas = found
                if found.contains(item.key) { out.insert(item.key) }
            } else if CarryoverDetector.firstMatch(of: item.text, in: [turn]) != nil {
                out.insert(item.key)
            }
        }
        return out
    }
}

/// The row itself: one line, horizontally scrollable, no header.
///
/// The hollow circle is what makes it read as a checklist without spending a
/// label on saying so — and it's the only reason a bare row of words is
/// legible as "things to use" rather than "things the app is telling you".
struct TalkGoalChipsRow: View {
    let items: [TalkGoalItem]
    let used: Set<String>
    /// Tapped chip → the caller opens `TalkGoalSheet`. A chip that only sat
    /// there was asking the learner to use a word they may not remember the
    /// meaning of — the tap is where the row stops being a demand.
    var onTap: (TalkGoalItem) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onTap(item) } label: {
                        chip(item, done: used.contains(item.key))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
        // A call screen scrolls its transcript constantly; the row must not
        // steal that gesture at the top edge.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ item: TalkGoalItem, done: Bool) -> some View {
        HStack(spacing: 5) {
            // Empty circle = studying; empty CHECKED circle = the learner said
            // they know this and the call is about to find out; filled = said.
            Image(systemName: done ? "checkmark.circle.fill"
                              : (item.claimedKnown ? "checkmark.circle" : "circle"))
                .font(.caption2)
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(item.text)
                .font(.footnote)
                .foregroundStyle(done ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .animation(.easeInOut(duration: 0.25), value: done)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.text)
        .accessibilityValue(done ? explain("used")
                            : (item.claimedKnown ? explain("Marked known") : explain("not used yet")))
    }
}

/// What one chip opens: the thing to say, and what it means.
///
/// Deliberately thin. The call is still running behind this sheet — the
/// learner is standing in the middle of a conversation trying to remember
/// whether *hectic* is the word they want, not opening a dictionary. So: the
/// phrase, one meaning, one example sentence they can copy out loud. The full
/// entry (every sense, collocations, their own past sentences) is the
/// notebook's job and stays there.
///
/// The lookup is `WordLore`, the same generated-once-and-shared entry the word
/// and expression cards read. It is free and globally cached, so a tap
/// mid-call costs nothing metered and usually resolves instantly.
struct TalkGoalSheet: View {
    let item: TalkGoalItem
    /// Already said in this call — the sheet leads with that instead of asking
    /// for it again.
    let used: Bool

    @EnvironmentObject private var appState: AppState

    @State private var entry: WordEntry?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        // No nav bar: a title would repeat the word, and an empty bar with a
        // lone Done button is the tallest thing on a sheet this short. The
        // drag indicator is the dismissal — the same one every peek sheet uses.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if loading {
                    LookupProgress()
                } else if failed {
                    LookupFailure { Task { await load() } }
                } else {
                    meaning
                    example
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .padding(.top, 8)
        }
        // Sized to the content it usually holds; a long expression with a
        // usage note can be dragged up rather than scrolled in a letterbox.
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The ask is not "repeat after me" — it's the word they chose to
            // study, and the call is where it gets spent.
            Label(used ? "You used it" : "Use this in the call",
                  systemImage: used ? "checkmark.circle.fill" : "quote.bubble")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(used ? Color.green : Color.secondary)
            Text(item.text)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var meaning: some View {
        // One sense. A word carries several and the card in Practice shows
        // them all; mid-call, the second sense is noise.
        if let sense = entry?.senses.first, !sense.meaning.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !sense.pos.isEmpty {
                    Text(sense.pos)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(sense.meaning)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = sense.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The scene's own sentence when the chip came out of a scenario book
    /// (with its usage hint under it), the dictionary's line otherwise.
    private var exampleLine: (text: String, meaning: String?)? {
        if let ex = item.example, !ex.isEmpty { return (ex, item.note) }
        if let ex = entry?.examples.first, !ex.text.isEmpty { return (ex.text, ex.meaning) }
        return nil
    }

    @ViewBuilder
    private var example: some View {
        if let ex = exampleLine {
            VStack(alignment: .leading, spacing: 6) {
                Text(ex.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = ex.meaning, !m.isEmpty {
                    Text(m)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
    }

    private func load() async {
        loading = true
        failed = false
        let fetched = await WordLore.entry(for: item.text,
                                           native: appState.nativeLanguage,
                                           target: appState.targetLanguage,
                                           kind: item.isWord ? .word : .expression)
        guard !Task.isCancelled else { return }
        entry = fetched
        failed = fetched == nil
        loading = false
    }
}

/// Coach mode's hint: the word, and a tick once it has been said. Worded so
/// the item never needs a particle or an article attached to it ("Try using ·
/// rest"), which no language's grammar can agree with for an arbitrary word.
struct CoachHintLabel: View {
    let item: TalkGoalItem
    let used: Bool

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(used ? "Used it" : "Try using")
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(item.text).bold()
            }
        } icon: {
            Image(systemName: used ? "checkmark.circle.fill" : "lightbulb")
                .foregroundStyle(used ? Color.green : Color.accentColor)
        }
        .font(.subheadline)
    }
}

/// Coach mode's line above the pill, for a call with subtitles off (the
/// hint's home is the listening bubble, which isn't drawn then).
/// Tapping opens the same one-sense sheet a chip does — a beginner handed a
/// word mid-call may need its meaning before they can use it.
struct CoachHintLine: View {
    let item: TalkGoalItem
    let used: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CoachHintLabel(item: item, used: used)
                .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: used)
    }
}
