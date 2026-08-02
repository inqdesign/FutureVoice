import SwiftUI

/// Five-axis "session nutrition" card. Rendered in the post-session summary
/// and the history detail view. iOS-native components only — no chart libs.
struct ScorecardView: View {
    let scorecard: SessionScorecard
    /// Verified grammar slips backing the grammar score. When present, the
    /// grammar row becomes tappable and opens the full evidence list — a low
    /// score should never be a number the user can't interrogate.
    var grammarIssues: [GrammarIssue] = []
    /// The session's user turns. Lets the grammar review play back the actual
    /// recording behind each quoted slip.
    var userTurns: [Turn] = []
    /// When set, the grammar review lets the user flag a slip as misheard by
    /// speech-to-text — the source turn is excluded from scoring and the
    /// grammar score rescales to the remaining evidence.
    var sessionId: UUID? = nil
    /// Fired after a misheard exclusion persists, with the updated session —
    /// hosts refresh their copy so score and slip count stay live.
    var onSessionUpdated: ((Session) -> Void)? = nil

    @State private var showGrammarReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scorecard.topLine)
                .font(.callout)
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                axisRow(label: "Vocabulary",     axis: scorecard.vocabulary,     icon: "textformat.abc")
                grammarRow
                axisRow(label: "Expressiveness", axis: scorecard.expressiveness, icon: "quote.bubble")
                axisRow(label: "Fluency & pace", axis: scorecard.fluency,        icon: "metronome")
                pronunciationRow
            }
        }
        .sheet(isPresented: $showGrammarReview) {
            GrammarReviewView(axis: scorecard.grammar, issues: grammarIssues,
                              userTurns: userTurns, sessionId: sessionId,
                              onSessionUpdated: onSessionUpdated)
        }
    }

    @ViewBuilder
    private var grammarRow: some View {
        if grammarIssues.isEmpty {
            axisRow(label: "Grammar", axis: scorecard.grammar, icon: "checkmark.seal")
        } else {
            Button {
                showGrammarReview = true
            } label: {
                axisRow(label: "Grammar", axis: scorecard.grammar, icon: "checkmark.seal",
                        detailCount: grammarIssues.count)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func axisRow(label: String, axis: AxisScore, icon: String,
                         detailCount: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .font(.subheadline)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(axis.score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: axis.score))
                    .monospacedDigit()
                if detailCount != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            ProgressView(value: Double(axis.score), total: 100)
                .tint(color(for: axis.score))
            if !axis.note.isEmpty {
                Text(axis.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let n = detailCount {
                Text("Review \(n) grammar \(n == 1 ? "slip" : "slips") from this talk")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
    }

    private var pronunciationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(width: 18)
                Text("Pronunciation")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let axis = scorecard.pronunciation {
                    Text("\(axis.score)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color(for: axis.score))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(scorecard.pronunciation?.note ?? "Practice shadow drills to track this.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }
}

// MARK: - Grammar review (the "why" behind the grammar score)

/// One page collecting every verified grammar slip from the session: what the
/// user literally said, the grammar-only fix, and the grammar point involved.
/// Quotes are hallucination-guarded upstream — everything here appeared
/// verbatim in the user's own turns.
struct GrammarReviewView: View {
    let axis: AxisScore
    let issues: [GrammarIssue]
    /// User turns from the same session — the recordings behind the quotes.
    var userTurns: [Turn] = []
    /// When set, slips can be flagged as misheard — see `ScorecardView`.
    var sessionId: UUID? = nil
    var onSessionUpdated: ((Session) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var playingIssueId: UUID?
    /// Local override after a misheard exclusion — one flag can remove
    /// several slips (all quoted from the same turn) and moves the score.
    @State private var updatedIssues: [GrammarIssue]?
    @State private var updatedAxis: AxisScore?

    private var displayIssues: [GrammarIssue] { updatedIssues ?? issues }
    private var displayAxis: AxisScore { updatedAxis ?? axis }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.tint)
                        Text("Grammar")
                            .font(.headline)
                        Spacer()
                        Text("\(displayAxis.score)")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    if !displayAxis.note.isEmpty {
                        Text(displayAxis.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(explain("Every slip below is quoted from what you actually said this session. The fix changes only the grammar — your words stay yours."))
                }

                Section {
                    ForEach(displayIssues) { issue in
                        let diff = GrammarDiff(quote: issue.quote, correction: issue.correction)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .padding(.top, 3)
                                Text(diff.quoteText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                // Hear the actual recording this quote came from.
                                if let turn = matchingTurn(for: issue), hasAudio(turn) {
                                    Button {
                                        togglePlay(issue, turn: turn)
                                    } label: {
                                        Image(systemName: playingIssueId == issue.id
                                              ? "stop.circle.fill" : "play.circle")
                                            .font(.title3)
                                            .foregroundStyle(.tint)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(playingIssueId == issue.id
                                                        ? "Stop playback" : "Play what you said")
                                }
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.top, 3)
                                Text(diff.correctionText)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !issue.note.isEmpty {
                                Text(issue.note)
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                    .padding(.leading, 22)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if sessionId != nil {
                                Button(role: .destructive) {
                                    markMisheard(issue)
                                } label: {
                                    Label("Misheard", systemImage: "mic.slash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(displayIssues.count) \(displayIssues.count == 1 ? "slip" : "slips") this session")
                } footer: {
                    if sessionId != nil {
                        Text(explain("Not what you said? Swipe a slip left and mark it Misheard — the turn is excluded from scoring and the grammar score is recalculated."))
                    }
                }
            }
            .navigationTitle("Grammar review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { player.stop() }
        }
    }

    // MARK: - Misheard exclusion

    /// Persist the exclusion, then refresh from the stored session — the
    /// authoritative result may drop sibling slips from the same turn and
    /// carries the rescaled grammar score.
    private func markMisheard(_ issue: GrammarIssue) {
        guard let sessionId,
              let updated = SessionStore.shared.excludeMishearing(sessionId: sessionId,
                                                                  issueId: issue.id)
        else { return }
        withAnimation {
            updatedIssues = updated.summary?.grammarIssues ?? []
            if let g = updated.summary?.scorecard?.grammar { updatedAxis = g }
        }
        onSessionUpdated?(updated)
    }

    // MARK: - Playback of the user's own recording

    /// Same normalization as the upstream hallucination guard, so a quote that
    /// passed verification always finds its source turn here.
    private func normalized(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func matchingTurn(for issue: GrammarIssue) -> Turn? {
        let needle = normalized(issue.quote)
        guard !needle.isEmpty else { return nil }
        return userTurns.first { $0.role == .user && normalized($0.transcript).contains(needle) }
    }

    /// Resolve by turnId from the CURRENT container first — the absolute
    /// `audioURL` goes stale when the app container moves on update/reinstall.
    private func hasAudio(_ turn: Turn) -> Bool {
        TurnAudioStore.shared.url(for: turn.id) != nil || turn.audioURL != nil
    }

    // MARK: - Word-level diff highlighting

    /// Deterministic word-level diff between the quote and its correction, so
    /// the review highlights exactly WHICH words were wrong instead of making
    /// the user spot the difference themselves. Wrong words: red strikethrough;
    /// fixed/added words: green bold. Computed in code — never by the LLM.
    private struct GrammarDiff {
        let quoteText: AttributedString
        let correctionText: AttributedString

        init(quote: String, correction: String) {
            let qWords = quote.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let cWords = correction.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let (qKeep, cKeep) = Self.commonIndices(qWords, cWords)

            quoteText = Self.render(qWords, keep: qKeep) { run in
                run.foregroundColor = .red
                run.strikethroughStyle = .single
            }
            correctionText = Self.render(cWords, keep: cKeep) { run in
                run.foregroundColor = .green
                run.inlinePresentationIntent = .stronglyEmphasized
            }
        }

        /// Compare words with punctuation/casing stripped — the same
        /// normalization the hallucination guard uses — so "bank," vs "bank"
        /// never lights up as a change.
        private static func norm(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
                .filter { !$0.isEmpty }
                .joined()
        }

        /// Longest-common-subsequence over normalized words; returns the index
        /// sets of UNCHANGED words on each side. Sentences are short, so the
        /// O(n·m) table is trivial.
        private static func commonIndices(_ a: [String], _ b: [String]) -> (Set<Int>, Set<Int>) {
            let na = a.map(norm), nb = b.map(norm)
            var dp = Array(repeating: Array(repeating: 0, count: nb.count + 1), count: na.count + 1)
            for i in stride(from: na.count - 1, through: 0, by: -1) {
                for j in stride(from: nb.count - 1, through: 0, by: -1) {
                    dp[i][j] = na[i] == nb[j]
                        ? dp[i + 1][j + 1] + 1
                        : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
            var keepA = Set<Int>(), keepB = Set<Int>()
            var i = 0, j = 0
            while i < na.count && j < nb.count {
                if na[i] == nb[j] {
                    keepA.insert(i); keepB.insert(j); i += 1; j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
            return (keepA, keepB)
        }

        private static func render(_ words: [String], keep: Set<Int>,
                                   changed style: (inout AttributedString) -> Void) -> AttributedString {
            var out = AttributedString()
            for (i, word) in words.enumerated() {
                if i > 0 { out += AttributedString(" ") }
                var run = AttributedString(word)
                if !keep.contains(i) { style(&run) }
                out += run
            }
            return out
        }
    }

    private func togglePlay(_ issue: GrammarIssue, turn: Turn) {
        if playingIssueId == issue.id {
            player.stop()
            playingIssueId = nil
            return
        }
        let data = TurnAudioStore.shared.data(for: turn.id)
            ?? turn.audioURL.flatMap { try? Data(contentsOf: $0) }
        guard let data else { return }
        playingIssueId = issue.id
        do {
            try player.play(data, forceSessionReset: true) {
                if playingIssueId == issue.id { playingIssueId = nil }
            }
        } catch {
            playingIssueId = nil
        }
    }
}
