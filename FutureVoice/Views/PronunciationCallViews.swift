import SwiftUI

/// The pronunciation call's card, pinned above the transcript
/// (`PronunciationCall`): today's sound, the five sentences as dots, and the
/// sentence to read in big letters. The words that carry the sound are in
/// the accent colour until a take is judged; after a take, a word that
/// wasn't clear yet is underlined in red (or orange), the same marks the
/// shadow screen uses. The tip under it is in the learner's own language.
struct PronunciationCard: View {
    let round: PronunciationRound?
    let topic: PronunciationCourse.Topic?
    let planning: Bool
    /// The learner leaves the sentence — the only way one is left unpassed.
    var onSkip: () -> Void = {}
    /// The learner leaves the word drill for the sentence.
    var onLeaveWord: () -> Void = {}
    /// The last take's whole assessment, behind the verdict pill.
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if planning || round == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(explain("Preparing your sentences…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let round, let i = round.current {
                let line = round.lines[i]
                if let c = round.carried {
                    // What the last sentence left, and when it comes back.
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                        if let w = c.word {
                            Text(verbatim: c.sound.map { "\(w) /\($0)/" } ?? w).fontWeight(.semibold)
                        } else {
                            Text(explain("Flow")).fontWeight(.semibold)
                        }
                        Text(c.laterInRound ? explain("Again at the end of this round")
                                            : explain("Again in the next round"))
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                if let word = line.drillWord {
                    // The word on its own; the sentence waits below it.
                    Text(word.contains(" ") ? explain("Say just this part") : explain("Say just this word"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.themeAccent)
                    Text(verbatim: word)
                        .font(.system(size: 52, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: line.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.marked(line))
                        .font(.system(.title, design: .default).weight(.bold))
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(line.text)
                }
                if let fb = line.feedback {
                    if let result = line.lastResult {
                        Button { showingDetail = true } label: {
                            PronunciationFeedbackPill(feedback: fb)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingDetail) {
                            PronunciationDetailSheet(results: [result])
                        }
                    } else {
                        PronunciationFeedbackPill(feedback: fb)
                    }
                }
                if let word = line.heardWord, let heard = line.heardAs {
                    Text(explain("“\(word)” sounded like “\(heard)”"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                if line.notSmooth {
                    Text(explain("Read it in one go, without stopping"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                // Nothing moves on by itself: these are the learner's ways on.
                if line.drillWord != nil {
                    Button(action: onLeaveWord) {
                        Label(explain("Back to the sentence"), systemImage: "arrow.uturn.backward")
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                } else if line.tries > 0 {
                    Button(action: onSkip) {
                        Label(explain("Next sentence"), systemImage: "forward.end")
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                if !round.tip.isEmpty {
                    Label(round.tip, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let round {
                VStack(alignment: .leading, spacing: 4) {
                    Label(explain("Round done"), systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(explain("\(round.passedCount) of \(round.sentenceCount) sentences passed"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: round)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "mouth.fill")
                .foregroundStyle(Color.themeAccent)
            if let topic {
                Text(verbatim: topic.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: topic.examples)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let round {
                HStack(spacing: 5) {
                    ForEach(Array(round.lines.enumerated()), id: \.element.id) { i, line in
                        Circle()
                            .fill(dotColor(line, current: round.current == i))
                            .frame(width: 8, height: 8)
                            .overlay {
                                if round.current == i {
                                    Circle().strokeBorder(Color.themeAccent, lineWidth: 2)
                                        .frame(width: 12, height: 12)
                                }
                            }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(explain("\(round.doneCount) of \(round.lines.count)")))
            }
        }
    }

    private func dotColor(_ line: PronunciationRound.Line, current: Bool) -> Color {
        if line.passed { return .green }
        if line.skipped { return Color(.systemGray3) }
        return current ? Color.themeAccent : Color(.systemGray5)
    }

    /// The sentence with its sound words in the accent colour, or — once a
    /// take has been judged — the words Azure marked underlined.
    static func marked(_ line: PronunciationRound.Line) -> AttributedString {
        var text = AttributedString(line.text)
        let plain = line.text
        if let word = line.heardWord,
           let r = plain.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]),
           let ar = Range(r, in: text) {
            text[ar].foregroundColor = .red
            text[ar].underlineStyle = .single
        }
        if let result = line.lastResult {
            var from = plain.startIndex
            for word in result.referenceWords {
                guard let r = plain.range(of: word.word, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: from..<plain.endIndex) else { continue }
                from = r.upperBound
                let grade = PronunciationResult.grade(word)
                guard grade < 2, let ar = Range(r, in: text) else { continue }
                let color: Color = grade == 0 ? .red : .orange
                text[ar].foregroundColor = color
                text[ar].underlineStyle = .single
            }
        } else {
            for focus in line.focus {
                var from = plain.startIndex
                while let r = plain.range(of: focus, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: from..<plain.endIndex) {
                    if let ar = Range(r, in: text) { text[ar].foregroundColor = .themeAccent }
                    from = r.upperBound
                }
            }
        }
        return text
    }
}

/// The last take's verdict on the card: the word and its sound, the score
/// that decided it, and "Nice" / "Not yet".
struct PronunciationFeedbackPill: View {
    let feedback: PronunciationRound.Feedback

    private var color: Color {
        feedback.ok ? .green : (feedback.score < 50 ? .red : .orange)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let word = feedback.word {
                Text(verbatim: word).fontWeight(.semibold)
                if let sound = feedback.sound {
                    Text(verbatim: "/\(sound)/").foregroundStyle(.secondary)
                    switch feedback.heardAs {
                    case .sound(let other):
                        Text(verbatim: "→ /\(other)/").foregroundStyle(color)
                    case .vowelAdded:
                        Text(explain("+ vowel")).foregroundStyle(color)
                    case nil:
                        EmptyView()
                    }
                }
            } else {
                Text(explain("Flow")).fontWeight(.semibold)
            }
            Text(verbatim: "\(feedback.score)")
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(feedback.ok ? explain("Nice") : explain("Not yet"))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// The pronunciation course ("교재"): every sound of the target language by
/// chapter, with how each went last time. Picking one starts a round on it
/// in the running call.
struct PronunciationTopicSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let currentId: String?
    let onPick: (PronunciationCourse.Topic) -> Void

    @State private var progress: [String: PronunciationTopicProgress] = [:]

    var body: some View {
        NavigationStack {
            List {
                if let next = PronunciationCourse.next(language: appState.targetLanguage,
                                                       level: appState.proficiency,
                                                       excluding: currentId) {
                    Section(explain("Next up")) {
                        Button { pick(next) } label: { row(next, leading: "play.circle.fill") }
                    }
                }
                ForEach(PronunciationCourse.chapters(for: appState.targetLanguage)) { chapter in
                    Section {
                        ForEach(chapter.topics) { topic in
                            Button { pick(topic) } label: { row(topic, leading: nil) }
                        }
                    } header: {
                        Label(chapter.title, systemImage: chapter.icon)
                    }
                }
            }
            .navigationTitle(explain("Sounds to practice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton() { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { progress = PronunciationProgressStore.all(language: appState.targetLanguage) }
    }

    private func row(_ topic: PronunciationCourse.Topic, leading: String?) -> some View {
        let p = progress[topic.id]
        return HStack(spacing: 12) {
            if let leading {
                Image(systemName: leading)
                    .font(.title2)
                    .foregroundStyle(Color.themeAccent)
            }
            Text(verbatim: topic.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: topic.examples)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                if let missed = p?.missedWords, !missed.isEmpty {
                    Text(explain("To redo: \(missed.joined(separator: ", "))"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if topic.id == currentId {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.themeAccent)
            } else if let score = p?.lastScore, score > 0 {
                Text(verbatim: "\(score)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(score >= PronunciationJudge.passBar ? .green : .orange)
            } else if let p, p.rounds > 0 {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }

    private func pick(_ topic: PronunciationCourse.Topic) {
        onPick(topic)
        dismiss()
    }
}
