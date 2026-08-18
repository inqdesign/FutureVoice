import SwiftUI

/// The words the app is asking you to study — the page the Practice tile's
/// "To study" number opens, and the word-level twin of `ExpressionsView`
/// (same two lenses, same row grammar, same card-in-a-sheet tap).
///
/// The tile used to push the CEFR word cloud (`VocabularyView`), which shows
/// the whole core vocabulary and titles itself "known / total". Its number and
/// the tile's number were unrelated, so the one thing a learner does with a
/// count — tap it to see what it's made of — didn't work. The cloud is still
/// reachable — the toolbar's explore button — as what it actually is: a map of
/// the language rather than a list of your homework. It sat as the list's LAST
/// row for a while, which behind 200+ words is the same as not existing.
struct WordsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @State private var selected: WordRef?
    @State private var filter: Filter = .toStudy
    /// First-sense gloss per word key, filled lazily as rows appear. "" means
    /// the lookup ran and has nothing to show (no entry / failed) — the row
    /// falls back to its origin line and the session won't retry.
    @State private var meanings: [String: String] = [:]
    @State private var searchText = ""
    @State private var source: SourceFilter = .all
    @State private var level: VocabularyView.LevelFilter = .all

    /// Where the word entered the list — the to-study pile mixes kept talk
    /// words with scene words, and "which homework is this" is the first cut
    /// a long list needs. Known words are all `.kept`, so the picker hides
    /// (and the filter sleeps) on that lens.
    enum SourceFilter: String, CaseIterable, Identifiable {
        case all, talks, scenes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:    return explain("All sources")
            case .talks:  return explain("From talks")
            case .scenes: return explain("From scenarios")
            }
        }
    }

    private struct WordRef: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Three lenses: what still needs work (default), what's retired, and the
    /// whole vocabulary — your words first, then the core pool alphabetically.
    enum Filter: String, CaseIterable, Identifiable {
        case toStudy, known, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return explain("To study")
            case .known:   return explain("Known")
            case .all:     return explain("All words")
            }
        }
    }

    /// The core pool as list items, alphabetical, rebuilt on language switch.
    /// Cached in state because sorting a few thousand words on every render
    /// (each arriving meaning re-renders) would stutter the scroll.
    @State private var pool: [WordCatalog.Item] = []

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var entries: [WordCatalog.Item] {
        var items: [WordCatalog.Item]
        if !searchQuery.isEmpty {
            // Search reads the WHOLE pool, whatever lens is up — a word you
            // type deserves an answer even if you've never touched it.
            items = union()
        } else {
            switch filter {
            case .toStudy: items = WordCatalog.toStudy(scenarios: appState.scenarios, store: store)
            case .known:   items = WordCatalog.known(store: store)
            case .all:     items = union()
            }
            if filter == .toStudy, source != .all {
                items = items.filter {
                    switch $0.origin {
                    case .kept:       return source == .talks
                    case .scene:      return source == .scenes
                    case .vocabulary: return false
                    }
                }
            }
        }
        if let lv = level.cefr {
            items = items.filter { CoreVocabulary.level(of: $0.key) == lv }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter { $0.key.contains(q) }
            // Prefix matches first — "par" should surface "parse" before "spare".
            items.sort { l, r in
                let lp = l.key.hasPrefix(q), rp = r.key.hasPrefix(q)
                if lp != rp { return lp }
                return l.key < r.key
            }
        }
        return items
    }

    /// Your words (to study, then known) followed by the rest of the core
    /// pool alphabetically — the All-words lens, and what search sweeps.
    private func union() -> [WordCatalog.Item] {
        var seen = Set<String>()
        var out: [WordCatalog.Item] = []
        for item in WordCatalog.toStudy(scenarios: appState.scenarios, store: store)
                  + WordCatalog.known(store: store) {
            guard seen.insert(item.key).inserted else { continue }
            out.append(item)
        }
        out.append(contentsOf: pool.filter { seen.insert($0.key).inserted })
        return out
    }

    private var isFiltering: Bool {
        (filter == .toStudy && source != .all) || level != .all
    }

    var body: some View {
        let items = entries
        return VStack(spacing: 0) {
            // The lens picker and the filter menu share one row — filtering
            // belongs beside the thing it filters, not up in the toolbar.
            HStack(spacing: 12) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Menu {
                    if filter == .toStudy {
                        Picker("Source", selection: $source) {
                            ForEach(SourceFilter.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Picker("Level", selection: $level) {
                        ForEach(VocabularyView.LevelFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: isFiltering
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
            // The search drawer above already brings its own air; the list
            // below brings none — so the row hugs the top and pads the bottom.
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            List {
                if items.isEmpty {
                    Section {
                        // Three different nothings: no results for a search,
                        // nothing past the filters, and a genuinely empty pile
                        // — only the last one should pitch what to go do.
                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else if isFiltering {
                            ContentUnavailableView {
                                Label(explain("No matching words"),
                                      systemImage: "line.3.horizontal.decrease.circle")
                            }
                        } else {
                            ContentUnavailableView {
                                Label(emptyTitle, systemImage: "text.book.closed")
                            } description: {
                                Text(emptyMessage)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(items) { item in
                            Button {
                                selected = WordRef(value: item.text)
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            .task(id: item.key) { await loadMeaning(item) }
                        }
                    } header: {
                        // What this lens (and any filters/search) adds up to.
                        Text("\(items.count) words")
                    } footer: {
                        if searchQuery.isEmpty {
                            switch filter {
                            case .toStudy:
                                Text(explain("Words you kept from a talk, plus the ones your watched scenes still ask for. Mark the ones you've got down as known."))
                            case .known:
                                Text(explain("Words you've used out loud or marked as known."))
                            case .all:
                                EmptyView()
                            }
                        }
                    }
                }

            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // The cloud — the explore view over the whole core vocabulary.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    VocabularyView().environmentObject(appState)
                } label: {
                    Image(systemName: "circle.hexagongrid")
                }
                .accessibilityLabel(Text("Browse all vocabulary"))
            }
        }
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search words"))
        .task(id: appState.targetLanguage) {
            pool = CoreVocabulary.entries
                .map { WordCatalog.Item(text: $0.word, key: $0.word.lowercased(),
                                        origin: .vocabulary, at: nil) }
                .sorted { $0.key < $1.key }
        }
        .sheet(item: $selected) { ref in
            WordSheet(initialWord: ref.value, words: items.map(\.text))
                .environmentObject(appState)
        }
    }

    /// A place, not a number — the count lives on the list header now, where
    /// it can follow the lens and filters instead of contradicting them.
    private var navTitle: String {
        explain("Word notebook")
    }

    private var emptyTitle: String {
        switch filter {
        // .all is only empty for a language with no bundled pool and no words
        // of your own yet — same story, same pitch as the study pile.
        case .toStudy, .all: return explain("Nothing to study yet")
        case .known:         return explain("Nothing marked known")
        }
    }
    private var emptyMessage: String {
        switch filter {
        case .toStudy, .all: return explain("Keep a word from a talk, or watch a situation — its words collect here.")
        case .known:         return explain("Words you say in a talk land here on their own; you can also mark one known from its card.")
        }
    }

    private func row(_ item: WordCatalog.Item) -> some View {
        let studying = store.isStudying(item.text)
        let known = store.state(of: item.key) != nil
        return HStack(spacing: 12) {
            // Same badge grammar as the cloud and the expressions list:
            // bookmark = in the notebook, check = retired.
            if studying || known {
                Image(systemName: studying ? "bookmark.fill" : "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(studying ? Color.accentColor : Color.green)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                // The word wears the same rounded face as its card and the
                // cloud; the gloss is content, not metadata, so it reads at
                // subheadline — caption made the Korean line squint-sized.
                Text(ExpressionsView.display(item.text))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                subtitle(item)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The word's meaning, like a real vocabulary list. Until the gloss is in
    /// (or when there is none) the row says where it came from instead — a
    /// scene word has been said zero times, so that fallback must never borrow
    /// the notebook's "used N times".
    @ViewBuilder
    private func subtitle(_ item: WordCatalog.Item) -> some View {
        if let meaning = meanings[item.key], !meaning.isEmpty {
            Text(meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            switch item.origin {
            case .kept(let count):
                if count > 0 {
                    Text("Said \(count)×")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kept from a talk")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .scene(let title):
                Label(title, systemImage: "film")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .vocabulary:
                if let lv = CoreVocabulary.level(of: item.key) {
                    Text(lv.rawValue.uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Same lookup the word card runs (`WordLore` — shared server cache, free),
    /// fired per row as it appears so only what's on screen is fetched. The
    /// card's own tap then hits the warm cache.
    private func loadMeaning(_ item: WordCatalog.Item) async {
        guard meanings[item.key] == nil else { return }
        let entry = await WordLore.entry(for: item.text, native: appState.nativeLanguage,
                                         target: appState.targetLanguage, kind: .word)
        guard !Task.isCancelled else { return }
        meanings[item.key] = entry?.senses.first?.meaning ?? ""
    }
}
