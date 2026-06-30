import SwiftUI

/// Dedicated surface for the multi-word expressions the user has actually used
/// across their talks — the phrase-level companion to the word cloud. Rows are
/// collected automatically at the end of each session (verified against the
/// user's own transcript), so everything here is something they really said.
struct ExpressionsView: View {
    @ObservedObject private var store = VocabStore.shared

    private var entries: [VocabStore.ExpressionEntry] { store.expressionEntries() }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No expressions yet", systemImage: "quote.bubble")
                } description: {
                    Text("Expressions you use in your talks will collect here.")
                }
            } else {
                List {
                    Section {
                        ForEach(entries) { entry in
                            NavigationLink {
                                ExpressionDetailView(phrase: entry.text)
                            } label: {
                                row(entry)
                            }
                        }
                    } footer: {
                        Text("Captured automatically from what you say.")
                    }
                }
            }
        }
        .navigationTitle("\(store.expressionCount) expressions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: VocabStore.ExpressionEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.display(entry.text))
                .font(.body)
            Text("Used \(entry.count) time\(entry.count == 1 ? "" : "s") · \(entry.lastAt.formatted(.dateTime.month().day()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Stored keys are lowercased; show with a capitalized first letter.
    static func display(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

/// One expression's detail — the sentences where the user said it, with
/// playback of their own recording when we captured it.
struct ExpressionDetailView: View {
    let phrase: String
    @ObservedObject private var store = VocabStore.shared
    @StateObject private var player = AudioPlayer()
    @State private var sentences: [VocabStore.SourceSentence] = []

    var body: some View {
        List {
            if sentences.isEmpty {
                Text("No example sentences found.")
                    .foregroundStyle(.secondary)
            } else {
                Section("From your talks") {
                    ForEach(sentences) { s in
                        sentenceRow(s)
                    }
                }
            }
        }
        .navigationTitle(ExpressionsView.display(phrase))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sentences = store.sentences(containing: phrase) }
        .onDisappear { player.stop() }
    }

    private func sentenceRow(_ s: VocabStore.SourceSentence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(highlighted(s.text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let url = s.audioURL {
                Button {
                    play(url)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func play(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        try? player.play(data, forceSessionReset: true)
    }

    /// Bold the expression inside the sentence so it stands out.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        if let r = attr.range(of: phrase, options: .caseInsensitive) {
            attr[r].font = .body.bold()
        }
        return attr
    }
}
