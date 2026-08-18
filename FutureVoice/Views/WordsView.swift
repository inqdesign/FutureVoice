import SwiftUI

/// The words the app is asking you to study — the page the Practice tile's
/// "To study" number opens, and the word-level twin of `ExpressionsView`
/// (same two lenses, same row grammar, same card-in-a-sheet tap).
///
/// The tile used to push the CEFR word cloud (`VocabularyView`), which shows
/// the whole core vocabulary and titles itself "known / total". Its number and
/// the tile's number were unrelated, so the one thing a learner does with a
/// count — tap it to see what it's made of — didn't work. The cloud is still
/// here, one row down, as what it actually is: a map of the language rather
/// than a list of your homework.
struct WordsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @State private var selected: WordRef?
    @State private var filter: Filter = .toStudy

    private struct WordRef: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Two lenses, exactly the expressions page's: what still needs work
    /// (default) and what's retired.
    enum Filter: String, CaseIterable, Identifiable {
        case toStudy, known
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return explain("To study")
            case .known:   return explain("Known")
            }
        }
    }

    private var entries: [WordCatalog.Item] {
        switch filter {
        case .toStudy: return WordCatalog.toStudy(scenarios: appState.scenarios, store: store)
        case .known:   return WordCatalog.known(store: store)
        }
    }

    var body: some View {
        let items = entries
        return VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                if items.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: "text.book.closed")
                        } description: {
                            Text(emptyMessage)
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
                        }
                    } footer: {
                        Text(filter == .toStudy
                             ? explain("Words you kept from a talk, plus the ones your watched scenes still ask for. Mark the ones you've got down as known.")
                             : explain("Words you've used out loud or marked as known."))
                    }
                }

                // The cloud, demoted to what it is. Kept on the page (not in
                // the toolbar) because it's a place to go, not an action.
                Section {
                    NavigationLink {
                        VocabularyView().environmentObject(appState)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Browse all vocabulary")
                                Text("\(store.knownCount) / \(store.total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "circle.hexagongrid")
                        }
                    }
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selected) { ref in
            WordSheet(initialWord: ref.value, words: items.map(\.text))
                .environmentObject(appState)
        }
    }

    private var navTitle: String {
        let n = WordCatalog.toStudy(scenarios: appState.scenarios, store: store).count
        return explain("\(n) words to study")
    }

    private var emptyTitle: String {
        switch filter {
        case .toStudy: return explain("Nothing to study yet")
        case .known:   return explain("Nothing marked known")
        }
    }
    private var emptyMessage: String {
        switch filter {
        case .toStudy: return explain("Keep a word from a talk, or watch a situation — its words collect here.")
        case .known:   return explain("Words you say in a talk land here on their own; you can also mark one known from its card.")
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
                Text(ExpressionsView.display(item.text))
                    .font(.body)
                    .foregroundStyle(.primary)
                // Where the row came from. A scene word has been said zero
                // times, so it must never borrow the notebook's "used N times".
                switch item.origin {
                case .kept(let count):
                    if count > 0 {
                        Text("Said \(count)×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kept from a talk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .scene(let title):
                    Label(title, systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
