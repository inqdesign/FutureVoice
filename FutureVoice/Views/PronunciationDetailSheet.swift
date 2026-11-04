import SwiftUI

/// Everything the pronunciation assessment reported on ONE take, and the
/// learner's standing across takes — the page behind the red/orange marks
/// (founder, 2026-11-04: "one sheet where the learner can see every piece of
/// information the assessment reports"). Opened from the shadow result's
/// Pronunciation line, the speech result's Pronunciation row, the
/// pronunciation call's verdict pill, and the scorecard's axis (profile
/// only). A plain `List`: every number here is Azure's as it came back
/// (`PronunciationResult`), with the app's own bars explained at the foot.
struct PronunciationDetailSheet: View {
    /// The take's assessment — a speech take is several pieces, in order.
    /// Empty = the standing alone (the scorecard's row).
    let results: [PronunciationResult]
    var language: String = LanguageScope.active

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    takeSection
                    wordsSection
                    soundsSection
                    heardSection
                }
                profileSection
                legendSection
            }
            .navigationTitle("Pronunciation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - This take

    /// The pieces' scores weighted by the words each judged — the same
    /// weighting `PronunciationEntry` records.
    private func weighted(_ value: (PronunciationResult) -> Int?) -> Int? {
        var sum = 0, total = 0
        for r in results {
            guard let v = value(r) else { continue }
            let w = max(1, r.judgedWords.count)
            sum += v * w; total += w
        }
        return total == 0 ? nil : sum / total
    }

    private var takeSection: some View {
        Section {
            if let v = weighted({ $0.soundScore }) {
                scoreRow("Sounds", value: v, bar: .score)
            }
            if let v = weighted({ $0.fluency }) {
                scoreRow("Flow", value: v, bar: .score)
            }
            if let v = weighted({ $0.completeness }) {
                scoreRow("Completeness", value: v, bar: .score)
            }
            if let v = weighted({ $0.prosody }) {
                scoreRow("Intonation", value: v, bar: .score)
            }
            if let v = weighted({ $0.score }) {
                scoreRow("Overall", value: v, bar: .score)
            }
            if let locale = results.first?.locale {
                HStack {
                    Text("Judged against")
                    Spacer()
                    Text(verbatim: Self.localeName(locale))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("This take")
        } footer: {
            Text(explain("Sounds — how closely each sound matched a native speaker — is the number shown everywhere else in the app. Flow is the pauses between words, completeness is how much of the line was said, intonation is stress and rhythm (English only)."))
        }
    }

    // MARK: - Words

    private var wordsSection: some View {
        Section {
            ForEach(Array(results.flatMap(\.words).enumerated()), id: \.offset) { _, word in
                wordRow(word)
            }
        } header: {
            Text("Words")
        } footer: {
            Text(explain("Each word with its score and the sounds in it. A word not heard or added is listed but never marked."))
        }
    }

    private func wordRow(_ w: PronunciationResult.Word) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: w.word)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(wordColor(w))
                if let label = errorLabel(w) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if w.isJudged, let a = w.accuracy {
                    Text("\(a)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(wordColor(w))
                } else {
                    Text(verbatim: "—").foregroundStyle(.tertiary)
                }
            }
            if w.isJudged {
                let named = w.phonemes.filter { !$0.phoneme.isEmpty && $0.accuracy != nil }
                if !named.isEmpty {
                    phonemeLine(named)
                        .font(.footnote)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "θ 32 (sounded like s) · ɪ 95 · ŋ 88", each sound in its own colour.
    private func phonemeLine(_ phonemes: [PronunciationResult.Phoneme]) -> Text {
        var out = Text(verbatim: "")
        for (i, p) in phonemes.enumerated() {
            if i > 0 { out = out + Text(verbatim: " · ").foregroundStyle(.tertiary) }
            let score = p.accuracy ?? 100
            var piece = Text(verbatim: "\(p.phoneme) \(score)")
            piece = piece.foregroundStyle(phonemeColor(score))
            out = out + piece
            if let heard = p.heard?.first, heard.phoneme != p.phoneme, score < 60 {
                out = out + Text(verbatim: " ") + Text(explain("(sounded like \(heard.phoneme))")).foregroundStyle(.secondary)
            }
        }
        return out
    }

    private func wordColor(_ w: PronunciationResult.Word) -> Color {
        guard w.isJudged else { return .secondary }
        switch PronunciationResult.grade(w) {
        case 0:  return .red
        case 1:  return .orange
        default: return .primary
        }
    }

    /// The word bars, applied to one sound: red under 35, orange under 45.
    private func phonemeColor(_ score: Int) -> Color {
        score < 35 ? .red : score < 45 ? .orange : .secondary
    }

    private func errorLabel(_ w: PronunciationResult.Word) -> String? {
        switch w.error {
        case "Omission":        return explain("not heard")
        case "Insertion":       return explain("extra word")
        case "Mispronunciation": return explain("flagged by the model")
        case "UnexpectedBreak": return explain("a stop before it")
        case "MissingBreak":    return explain("no pause before it")
        case "Monotone":        return explain("flat")
        default:                return nil
        }
    }

    // MARK: - Sounds in this take

    private struct SoundMean: Identifiable {
        let phoneme: String
        let mean: Int
        let count: Int
        var id: String { phoneme }
    }

    private var takeSounds: [SoundMean] {
        var by: [String: [Int]] = [:]
        for p in results.flatMap(\.namedPhonemes) { by[p.phoneme, default: []].append(p.accuracy ?? 100) }
        return by.map { SoundMean(phoneme: $0.key, mean: $0.value.reduce(0, +) / $0.value.count, count: $0.value.count) }
            .sorted { $0.mean == $1.mean ? $0.phoneme < $1.phoneme : $0.mean < $1.mean }
    }

    @ViewBuilder
    private var soundsSection: some View {
        let sounds = takeSounds
        if !sounds.isEmpty {
            Section {
                ForEach(sounds) { s in
                    HStack {
                        Text(verbatim: s.phoneme).font(.body.weight(.semibold))
                        Text(verbatim: "×\(s.count)").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(s.mean)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(soundColor(s.mean))
                    }
                }
            } header: {
                Text("Sounds in this take")
            } footer: {
                Text(explain("Every sound heard in this take, averaged over the words it was in, lowest first. The accent lives here: a word can score well while one sound in it is far off."))
            }
        }
    }

    /// The take line's bar (60) and the profile's weak bar (70), shown the
    /// same way: under 50 red, under 70 orange.
    private func soundColor(_ mean: Int) -> Color {
        mean < 50 ? .red : mean < PronunciationProfile.weakBar ? .orange : .primary
    }

    // MARK: - What was heard

    @ViewBuilder
    private var heardSection: some View {
        let heard = results.map(\.recognized).filter { !$0.isEmpty }
        if !heard.isEmpty {
            Section {
                Text(verbatim: heard.joined(separator: " "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What the model heard")
            }
        }
    }

    // MARK: - Across takes

    @ViewBuilder
    private var profileSection: some View {
        let profile = PronunciationProfile.current(language: language)
        if profile.takes > 0 {
            Section {
                if let mean = profile.meanAccuracy {
                    HStack {
                        Text("Sounds")
                        Text(explain("over \(profile.takes) takes")).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(mean)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(soundColor(mean))
                    }
                }
                ForEach(profile.sounds, id: \.self) { s in
                    HStack {
                        Text(verbatim: s.phoneme).font(.body.weight(.semibold))
                        Text(verbatim: "×\(s.count)").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(s.mean)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(soundColor(s.mean))
                    }
                }
                ForEach(profile.weakWords, id: \.self) { w in
                    HStack {
                        Text(verbatim: w.word).font(.body.weight(.semibold))
                        Text(explain("in \(w.takes) takes")).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(w.mean)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(soundColor(w.mean))
                    }
                }
            } header: {
                Text("Last 30 days")
            } footer: {
                Text(explain("One take's marks move with where the recording was cut. What holds is a sound that stays low across takes — listed here once it has been heard \(PronunciationProfile.minSamples) times — and a word low in several takes."))
            }
        }
    }

    // MARK: - Legend

    private var legendSection: some View {
        Section {
            Label {
                Text(explain("A word scored under 50, or with a sound under 35."))
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(.red)
            }
            Label {
                Text(explain("A word scored under 70, or with a sound under 45."))
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(.orange)
            }
        } header: {
            Text("The marks")
        } footer: {
            Text(explain("Set so a native speaker's slip reads orange at most. Scores come from Azure's pronunciation assessment against a native model of the language; sound names are given for English only."))
        }
    }

    // MARK: - Helpers

    private enum Bar { case score }

    private func scoreRow(_ title: LocalizedStringKey, value: Int, bar: Bar) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .font(.body.monospacedDigit())
                .foregroundStyle(SpeechScoreColor.color(value))
        }
    }

    /// "en-US" → "English (United States)" in the app language.
    static func localeName(_ id: String) -> String {
        let code = id.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: UILanguage.chromeLanguage)
        return locale.localizedString(forIdentifier: code) ?? id
    }
}
