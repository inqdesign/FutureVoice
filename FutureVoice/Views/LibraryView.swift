import SwiftUI

/// The three dictionaries, behind one door.
///
/// They used to sit as a three-tile band under the Practice tab's mastery
/// card, directly below the Today card's Words / Expressions / Shadowing
/// rows — the same three nouns twice on one screen, with numbers that don't
/// mean the same thing (words KEPT to study vs expressions EVER collected vs
/// shadow lines SAVED). Two of those numbers were being read as progress.
///
/// Here each one gets a line saying what it counts, which is only affordable
/// once they're on their own page.
struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var vocab = VocabStore.shared

    var body: some View {
        List {
            Section {
                NavigationLink {
                    VocabularyView()
                } label: {
                    row("text.book.closed.fill", "Words",
                        count: vocab.studying.count,
                        note: explain("Words you're keeping to study"))
                }
                NavigationLink {
                    ExpressionsView()
                        .navigationTitle("Expressions")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    row("quote.bubble.fill", "Expressions",
                        count: vocab.expressionEntries().count,
                        note: explain("Phrases picked up from your talks"))
                }
                NavigationLink {
                    ShadowBrowserView()
                        .navigationTitle("Shadowing")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    row("waveform.badge.mic", "Shadowing",
                        count: appState.savedLines.count,
                        note: explain("Lines you saved to say out loud"))
                }
            } footer: {
                Text(explain("Everything you've collected, whenever you want to browse it. Today's practice is on the Practice tab."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func row(_ icon: String, _ title: LocalizedStringKey,
                     count: Int, note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
