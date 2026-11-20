import SwiftUI

/// "Before you go" — the one screen shown right after a talk, before its
/// book. One item from each chapter (a word, an expression, a corrected
/// sentence, a line to shadow), chosen by code, so a learner who closes the
/// app now still leaves with the talk's four most useful things. Nothing to
/// do and nothing to tick: it is read, then closed, and the book underneath
/// is the same book as always (founder, 2026-11-17: the book piled up unread,
/// and this is the moment to hold them once more).
struct TalkTakeaway: Equatable {
    struct Entry: Equatable {
        let text: String
        /// The line from the talk it came from, if one was found.
        let example: String?
    }
    struct Fix: Equatable {
        let original: String?
        let fluent: String
        let reason: String
    }
    struct Line: Equatable {
        let turnId: UUID
        let text: String
    }

    var word: Entry?
    var expression: Entry?
    var fix: Fix?
    var line: Line?

    var isEmpty: Bool { word == nil && expression == nil && fix == nil && line == nil }

    /// Analytics: which of the four were there.
    var parts: String {
        [word != nil ? "word" : nil, expression != nil ? "expression" : nil,
         fix != nil ? "fix" : nil, line != nil ? "line" : nil]
            .compactMap { $0 }.joined(separator: ",")
    }

    /// The picks: one item per chapter, chosen for THIS learner's level
    /// (2026-11-20, founder: the screen showed "that", and expressions the
    /// learner already had). The chapters list what the talk taught; this
    /// picks the one worth holding on to.
    ///
    /// - Word: a graded word at the learner's level or one band above, the
    ///   one the fluent self came back to in the most turns (ties: the
    ///   higher band). Then any other graded word at or above the level,
    ///   then a word the list doesn't grade that the call kept returning to.
    ///   Never a word the list grades below the level.
    /// - Expression: one the fluent self OFFERED (a phrase the learner said
    ///   is already theirs), rated at or above the level by
    ///   `QuickQuizStock`'s cached rating (`levels`). A phrase rated below
    ///   the level or "none" is never shown; an unrated one is shown only
    ///   when no rated one qualifies (the rating call failed or ran late).
    @MainActor static func make(session: Session,
                     curriculum: TalkCurriculum.Snapshot,
                     proficiency: CEFRLevel,
                     expressionLevels: [String: String],
                     fix: Fix?) -> TalkTakeaway {
        let fluentText = session.turns
            .filter { $0.role == .fluentSelf }
            .map(\.transcript)
        func firstOpen(_ items: [ScenarioCurriculum.Item]) -> ScenarioCurriculum.Item? {
            items.first { $0.masteredAt == nil } ?? items.first
        }
        func example(for text: String) -> String? {
            let needle = text.lowercased()
            for turn in fluentText {
                for s in TalkCurriculum.sentences(in: turn)
                where s.lowercased().contains(needle) {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }
        var t = TalkTakeaway()
        if let w = pickWord(curriculum.words, fluentTurns: fluentText, proficiency: proficiency) {
            t.word = Entry(text: w.text, example: example(for: w.text))
        }
        if let e = pickExpression(curriculum.expressions,
                                  offered: session.summary?.expressionsOffered ?? [],
                                  levels: expressionLevels, proficiency: proficiency) {
            t.expression = Entry(text: ExpressionsView.display(e.text),
                                 example: example(for: e.text))
        }
        t.fix = fix
        if let l = firstOpen(curriculum.shadowLines) {
            t.line = Line(turnId: l.id, text: l.text)
        }
        return t
    }

    static func pickWord(_ items: [ScenarioCurriculum.Item], fluentTurns: [String],
                         proficiency: CEFRLevel) -> ScenarioCurriculum.Item? {
        let open = items.filter { $0.masteredAt == nil }
        guard !open.isEmpty else { return nil }
        let base = CoreVocabulary.levelRank(proficiency)
        let turnLemmas = fluentTurns.map { VocabStore.lemmas(in: [$0]) }
        func turns(_ w: String) -> Int {
            let key = w.lowercased()
            return turnLemmas.filter { $0.contains(key) }.count
        }
        func rank(_ w: String) -> Int? { CoreVocabulary.level(of: w).map(CoreVocabulary.levelRank) }
        func best(_ pool: [ScenarioCurriculum.Item]) -> ScenarioCurriculum.Item? {
            pool.max { a, b in
                let (ta, tb) = (turns(a.text), turns(b.text))
                return ta == tb ? (rank(a.text) ?? 0) < (rank(b.text) ?? 0) : ta < tb
            }
        }
        let graded = open.filter { rank($0.text).map { $0 >= base } ?? false }
        if let w = best(graded.filter { rank($0.text)! <= base + 1 }) { return w }
        if let w = best(graded) { return w }
        // Off the graded list: only a word the call kept coming back to.
        return best(open.filter { rank($0.text) == nil && turns($0.text) > 1 })
    }

    @MainActor static func pickExpression(_ items: [ScenarioCurriculum.Item], offered: [String],
                               levels: [String: String],
                               proficiency: CEFRLevel) -> ScenarioCurriculum.Item? {
        let offeredKeys = Set(offered.map(CarryoverDetector.normalized))
        let open = items.filter {
            $0.masteredAt == nil && offeredKeys.contains(CarryoverDetector.normalized($0.text))
        }
        let rated = open.map { ($0, levels[ExpressionCatalog.normalizedKey($0.text)]) }
        if let hit = rated.first(where: { QuickQuizStock.atLevel($0.1, proficiency) }) { return hit.0 }
        return rated.first { $0.1 == nil }?.0
    }
}

struct TalkTakeawayView: View {
    let takeaway: TalkTakeaway
    /// Called once, when the screen goes away — by the button or the ✕.
    let onClose: (_ how: String) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var wordMeaning: String?
    @State private var expressionMeaning: String?
    @State private var closed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before you go")
                            .font(.largeTitle.bold())
                        Text("One thing from each part of this talk")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                    if let w = takeaway.word {
                        entryCard(label: "Word", icon: "book.closed", tint: .purple,
                                  entry: w, meaning: wordMeaning)
                    }
                    if let e = takeaway.expression {
                        entryCard(label: "Expression", icon: "quote.bubble", tint: .pink,
                                  entry: e, meaning: expressionMeaning)
                    }
                    if let f = takeaway.fix { fixCard(f) }
                    if let l = takeaway.line { lineCard(l) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    close("book")
                } label: {
                    Text("Open the book")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        close("close")
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task { await loadMeanings() }
        .onDisappear {
            player.stop()
            // A swipe down closes it too; count that once.
            if !closed { closed = true; onClose("swipe") }
        }
    }

    private func close(_ how: String) {
        guard !closed else { return }
        closed = true
        player.stop()
        onClose(how)
        dismiss()
    }

    // MARK: - Cards

    private func kindLabel(_ title: LocalizedStringKey, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func entryCard(label: LocalizedStringKey, icon: String, tint: Color,
                           entry: TalkTakeaway.Entry, meaning: String?) -> some View {
        card {
            kindLabel(label, icon: icon, tint: tint)
            Text(entry.text)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ex = entry.example {
                Text(Self.emphasized(ex, entry.text))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func fixCard(_ f: TalkTakeaway.Fix) -> some View {
        card {
            kindLabel("Fixed sentence", icon: "pencil", tint: .orange)
            if let original = f.original, !original.isEmpty {
                Text(original)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(highlightedCorrection(f.fluent, original: f.original ?? "",
                                       baseFont: .title3.weight(.semibold)))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !f.reason.isEmpty {
                Text(f.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func lineCard(_ l: TalkTakeaway.Line) -> some View {
        let audio = TurnAudioStore.shared.data(for: l.turnId)
        return card {
            HStack {
                kindLabel("A line to say after it", icon: "waveform", tint: .yellow)
                Spacer()
                if let audio {
                    Button {
                        if player.isPlaying {
                            player.stop()
                        } else {
                            try? player.play(audio, source: "takeaway")
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    .accessibilityLabel(player.isPlaying ? "Stop" : "Play")
                }
            }
            Text(l.text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The word set in bold where it sits in its sentence.
    static func emphasized(_ sentence: String, _ word: String) -> AttributedString {
        var s = AttributedString("\u{201C}\(sentence)\u{201D}")
        if let r = s.range(of: word, options: .caseInsensitive) {
            s[r].font = .subheadline.weight(.semibold)
            s[r].foregroundColor = .primary
        }
        return s
    }

    /// One sense each, from the same free, shared dictionary the word card
    /// uses. A miss just leaves the line out.
    private func loadMeanings() async {
        let native = appState.nativeLanguage
        let target = appState.targetLanguage
        async let w: WordEntry? = takeaway.word == nil ? nil
            : WordLore.entry(for: takeaway.word!.text, native: native, target: target, kind: .word)
        async let e: WordEntry? = takeaway.expression == nil ? nil
            : WordLore.entry(for: takeaway.expression!.text, native: native, target: target, kind: .expression)
        let (we, ee) = await (w, e)
        wordMeaning = we?.senses.first?.meaning
        expressionMeaning = ee?.senses.first?.meaning
    }
}
