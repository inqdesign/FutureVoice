import SwiftUI

/// Full read-back of a past conversation: the whole transcript (You / Future
/// self), the session's score + note, with per-line "meaning" and audio replay.
/// Review cards are one tap away at the bottom — but the default, expected view
/// is the conversation itself, not the drill deck.
struct ConversationDetailView: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    @StateObject private var player = AudioPlayer()
    // Observed so chips restyle live when the word card marks a word
    // known / studying.
    @ObservedObject private var vocab = VocabStore.shared
    @State private var showingContinue = false
    @State private var wordSheet: WordSheetItem?
    /// Core-list words the fluent self used that the user hasn't yet — their
    /// natural next words, computed on appear.
    @State private var fluentSelfNewWords: [String] = []

    private struct WordSheetItem: Identifiable {
        let word: String
        var id: String { word }
    }

    private enum WordsTab { case you, futureSelf }
    @State private var wordsTab: WordsTab = .you

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let sc = session.summary?.scorecard { scorecardCard(sc) }
                if let note = session.summary?.overallNote, !note.isEmpty { noteCard(note) }
                if let sum = session.summary { highlights(sum) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript").font(.headline)
                    Text("Tap any word your future self said to look it up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                ForEach(session.turns) { turn in
                    TranscriptRow(turn: turn,
                                  nativeLanguage: appState.nativeLanguage,
                                  targetLanguage: appState.targetLanguage,
                                  player: player,
                                  onWordTap: { wordSheet = WordSheetItem(word: $0) })
                }
            }
            .padding(20)
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DrillView(source: .session(session.id))
                        .navigationTitle("Review")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Review", systemImage: "rectangle.stack")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear {
            fluentSelfNewWords = VocabStore.shared.pickupWords(
                fromFluentTexts: session.turns.filter { $0.role == .fluentSelf }.map(\.transcript),
                atOrAbove: appState.proficiency)
        }
        .onDisappear { player.stop() }
        .fullScreenCover(isPresented: $showingContinue) {
            ConversationView(resumeSession: session)
                .environmentObject(appState)
        }
        .sheet(item: $wordSheet) { item in
            NavigationStack {
                WordCard(word: item.word, currentWord: .constant(item.word))
            }
            .environmentObject(appState)
        }
    }

    // MARK: - Session highlights (what you learned in this talk)

    /// The summary already knows the session's new words, verified expressions
    /// and key corrections — surface them instead of leaving them buried in
    /// the transcript.
    @ViewBuilder
    private func highlights(_ sum: SessionSummary) -> some View {
        if !sum.newWordsUsed.isEmpty || !fluentSelfNewWords.isEmpty {
            newWordsCard(sum)
        }
        if !sum.expressionsUsed.isEmpty {
            card("Expressions you used", icon: "quote.bubble") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sum.expressionsUsed, id: \.self) { e in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                                .padding(.top, 3)
                            Text(e).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        if !sum.phrasesUsed.isEmpty {
            card("Say it better", icon: "sparkles") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sum.phrasesUsed) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.userSaid)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                                .fixedSize(horizontal: false, vertical: true)
                            Text(highlightedCorrection(p.fluentAlternative, original: p.userSaid, baseFont: .subheadline))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// One compact card for both word sources, switched by a segmented tab —
    /// two stacked cards ate half the screen.
    private func newWordsCard(_ sum: SessionSummary) -> some View {
        let mine = sum.newWordsUsed
        let theirs = Array(fluentSelfNewWords.prefix(24))
        let tab: WordsTab = mine.isEmpty ? .futureSelf : (theirs.isEmpty ? .you : wordsTab)
        return card("New words", icon: "text.book.closed") {
            VStack(alignment: .leading, spacing: 12) {
                if !mine.isEmpty, !theirs.isEmpty {
                    Picker("Source", selection: $wordsTab) {
                        Text("You · \(mine.count)").tag(WordsTab.you)
                        Text("Future self · \(theirs.count)").tag(WordsTab.futureSelf)
                    }
                    .pickerStyle(.segmented)
                }
                if tab == .you {
                    levelGroupedChips(mine)
                } else {
                    Text("Your future self used these; you haven't yet. Tap one to study it — or mark it as known.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    levelGroupedChips(theirs)
                }
            }
        }
    }

    /// Word chips grouped by CEFR level (same grouping as the post-talk
    /// summary sheet) — each chip opens the word's dictionary card.
    private func levelGroupedChips(_ words: [String]) -> some View {
        let grouped = Dictionary(grouping: words) { CoreVocabulary.level(of: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(CEFRLevel.allCases, id: \.self) { lv in
                if let ws = grouped[lv], !ws.isEmpty {
                    levelChipRow(lv.rawValue.uppercased(), ws)
                }
            }
            if let other = grouped[nil], !other.isEmpty {
                levelChipRow("Other", other)
            }
        }
    }

    private func levelChipRow(_ label: String, _ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(words, id: \.self) { w in wordChip(w) }
            }
        }
    }

    /// One word chip, styled by the user's relationship to the word so the
    /// three states read at a glance — the state lives in the ICON, on a calm
    /// neutral capsule (matching the word card's "I know it" button, where
    /// only the checkmark is green):
    /// green ✓ = known/used · accent bookmark = studying · outline = untouched.
    /// Tapping opens the word card, whose "I know it" / "Keep studying"
    /// actions restyle the chip live.
    private func wordChip(_ w: String) -> some View {
        let studying = vocab.isStudying(w)
        let known = !studying && vocab.state(of: w) != nil
        return Button { wordSheet = WordSheetItem(word: w) } label: {
            HStack(spacing: 5) {
                if studying {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                } else if known {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text(w).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                if studying || known {
                    Capsule().fill(Color(.tertiarySystemFill))
                } else {
                    Capsule().strokeBorder(Color(.separator))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func card(_ title: String, icon: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var header: some View {
        Text((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func scorecardCard(_ sc: SessionScorecard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(overall(sc))").font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(color(overall(sc)))
            }
            axis("Vocabulary", sc.vocabulary.score)
            axis("Grammar", sc.grammar.score)
            axis("Fluency", sc.fluency.score)
            axis("Expressiveness", sc.expressiveness.score)
            if let p = sc.pronunciation { axis("Pronunciation", p.score) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func axis(_ name: String, _ score: Int) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color(score))
                            .frame(width: max(0, geo.size.width * CGFloat(score) / 100))
                    }
            }
            .frame(height: 6)
            Text("\(score)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
        }
    }

    private func noteCard(_ note: String) -> some View {
        Text(note)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var bottomBar: some View {
        Button {
            showingContinue = true
        } label: {
            Label("Continue this conversation", systemImage: "phone.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func overall(_ sc: SessionScorecard) -> Int {
        var s = [sc.vocabulary.score, sc.grammar.score, sc.expressiveness.score, sc.fluency.score]
        if let p = sc.pronunciation { s.append(p.score) }
        return s.isEmpty ? 0 : s.reduce(0, +) / s.count
    }

    private func color(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }
}

/// All past conversations → each opens its full transcript.
struct ConversationsListView: View {
    @State private var sessions: [Session] = []

    var body: some View {
        List(sessions) { s in
            NavigationLink {
                ConversationDetailView(session: s)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.displayTitle).font(.body).lineLimit(1)
                    Text((s.endedAt ?? s.startedAt).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            sessions = SessionStore.shared.load()
                .filter { $0.endedAt != nil }
                .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        }
    }
}

/// One transcript line — role, text, optional audio replay, "meaning" toggle,
/// and (for the user's lines) the more-natural suggestion.
private struct TranscriptRow: View {
    @EnvironmentObject private var appState: AppState
    let turn: Turn
    let nativeLanguage: String
    let targetLanguage: String
    @ObservedObject var player: AudioPlayer
    /// Called with the notebook lookup key when the user taps a word in a
    /// fluent-self line.
    let onWordTap: (String) -> Void

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false
    @State private var reasonNative: String?
    @State private var reasonShowing = false
    @State private var reasonLoading = false
    @State private var showingShadow = false
    @State private var showingSuggestionShadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.role == .user ? "You" : "Future self")
                .font(.caption).foregroundStyle(.secondary)

            if turn.role == .fluentSelf {
                // Word-by-word so any word is tappable → its dictionary card.
                // Same look as the plain line; FlowLayout wraps like text.
                FlowLayout(spacing: 4, lineSpacing: 5) {
                    ForEach(Array(turn.transcript.split(separator: " ").enumerated()),
                            id: \.offset) { _, token in
                        Text(token)
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .onTapGesture {
                                let key = VocabStore.lookupKey(for: String(token))
                                if !key.isEmpty { onWordTap(key) }
                            }
                    }
                }
            } else {
                Text(turn.transcript)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // One action row per line. Listen works for the user's own turns
            // too (their mic audio is kept from the conversation); Shadow and
            // Meaning only make sense on the fluent self's lines — translating
            // the user's own words back at them says nothing.
            if hasAudio || turn.role == .fluentSelf {
                HStack(spacing: 8) {
                    if hasAudio {
                        Button { playTurn() } label: {
                            Label("Listen", systemImage: "play.circle")
                        }
                    }
                    if turn.role == .fluentSelf, hasAudio {
                        Button { showingShadow = true } label: {
                            Label("Shadow", systemImage: "waveform.badge.mic")
                        }
                    }
                    if turn.role == .fluentSelf {
                        Button(action: toggleMeaning) {
                            HStack(spacing: 4) {
                                if loading { ProgressView().controlSize(.mini) }
                                else { Image(systemName: "character.bubble") }
                                Text(showing ? "Hide meaning" : "Meaning")
                            }
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
            }

            if turn.role == .fluentSelf, showing, let t = translation {
                Text(t).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if turn.role == .user, let s = turn.suggestion {
                suggestionBox(s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .sheet(isPresented: $showingShadow) {
            ShadowDrillView(turn: turn, targetLanguage: targetLanguage)
                .environmentObject(appState)
        }
    }

    /// The correction — the part of the session that actually teaches. Changed
    /// words are emphasized, and it's shadowable like any fluent-self line
    /// (ShadowDrillView synthesizes the audio in the user's cloned voice).
    private func suggestionBox(_ s: TurnSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("More natural", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(highlightedCorrection(s.alternative, original: turn.transcript, baseFont: .callout))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.reason).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showingSuggestionShadow = true } label: {
                Label("Shadow", systemImage: "waveform.badge.mic")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            Button { toggleReason(s) } label: {
                HStack(spacing: 4) {
                    if reasonLoading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "character.bubble") }
                    Text(reasonShowing ? "Hide" : "Explain in my language")
                }
                .font(.caption2).foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            if reasonShowing, let r = reasonNative {
                Text(r).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
        .sheet(isPresented: $showingSuggestionShadow) {
            ShadowDrillView(turn: suggestionTurn(s), targetLanguage: targetLanguage)
                .environmentObject(appState)
        }
    }

    /// A synthetic fluent-self turn for shadowing the suggestion. The id is
    /// derived from the real turn's id so repeated shadow sessions reuse the
    /// same cached audio instead of synthesizing/duplicating it every time.
    private func suggestionTurn(_ s: TurnSuggestion) -> Turn {
        var bytes = turn.id.uuid
        bytes.0 ^= 0xFF
        return Turn(id: UUID(uuid: bytes), role: .fluentSelf, audioURL: nil,
                    transcript: s.alternative, durationMs: 0,
                    timestamp: turn.timestamp, suggestion: nil)
    }

    /// Audio exists if TurnAudioStore still has it (resolved from the CURRENT
    /// Documents path by turnId — survives the app-container path changing on
    /// reinstall/update, which would have invalidated the stored absolute URL).
    private var hasAudio: Bool {
        TurnAudioStore.shared.url(for: turn.id) != nil || turn.audioURL != nil
    }

    private func playTurn() {
        let data = TurnAudioStore.shared.data(for: turn.id)
            ?? turn.audioURL.flatMap { try? Data(contentsOf: $0) }
        guard let data else { return }
        try? player.play(data, forceSessionReset: true)
    }

    private func toggleMeaning() {
        if showing { showing = false; return }
        showing = true
        guard translation == nil else { return }
        if let c = Translator.cached(turn.transcript, to: nativeLanguage) { translation = c; return }
        loading = true
        Task {
            let t = await Translator.translate(turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }

    /// "Explain in my language": a real native-language explanation of what
    /// changed between the user's line and the suggestion — not a translation
    /// of the generic English reason string, which explains nothing.
    private func toggleReason(_ s: TurnSuggestion) {
        if reasonShowing { reasonShowing = false; return }
        reasonShowing = true
        guard reasonNative == nil else { return }
        if let c = Translator.cachedExplanation(original: turn.transcript, alternative: s.alternative,
                                                to: nativeLanguage) {
            reasonNative = c
            return
        }
        reasonLoading = true
        Task {
            let t = await Translator.explainCorrection(original: turn.transcript, alternative: s.alternative,
                                                       to: nativeLanguage)
            reasonNative = t
            reasonLoading = false
            if t == nil { reasonShowing = false }
        }
    }
}

/// Word-level emphasis for a correction: returns the alternative with the
/// words that differ from what the user actually said in accent + semibold,
/// so the fixed parts are visible at a glance. LCS over normalized words —
/// case/punctuation differences alone don't count as changes.
func highlightedCorrection(_ alternative: String, original: String, baseFont: Font) -> AttributedString {
    func norm(_ s: Substring) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
    let altWords = alternative.split(separator: " ", omittingEmptySubsequences: true)
    let a = altWords.map(norm)
    let o = original.split(separator: " ", omittingEmptySubsequences: true).map(norm)
    let m = a.count, n = o.count

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in stride(from: m - 1, through: 0, by: -1) {
        for j in stride(from: n - 1, through: 0, by: -1) {
            dp[i][j] = a[i] == o[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
        }
    }
    var kept = Array(repeating: false, count: m)
    var i = 0, j = 0
    while i < m, j < n {
        if a[i] == o[j] { kept[i] = true; i += 1; j += 1 }
        else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 }
        else { j += 1 }
    }

    var out = AttributedString()
    for (idx, word) in altWords.enumerated() {
        var piece = AttributedString(String(word))
        // Punctuation-only tokens (a lone dash) normalize to "" — never worth
        // highlighting on their own.
        if !kept[idx], !a[idx].isEmpty {
            piece.foregroundColor = .accentColor
            piece.font = baseFont.weight(.semibold)
        }
        out += piece
        if idx < altWords.count - 1 { out += AttributedString(" ") }
    }
    return out
}
