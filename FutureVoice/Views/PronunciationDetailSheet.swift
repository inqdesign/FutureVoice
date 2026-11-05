import SwiftUI

/// What the pronunciation assessment found, written for the learner — the
/// page behind the red/orange marks (founder, 2026-11-04: "one sheet where
/// the learner can see every piece of information the assessment reports";
/// 2026-11-05: the first cut, six tables of Azure's numbers, was "too hard
/// to understand"). The shape now: ONE number, the sounds to work on with
/// the words of this take that carry them (and a button to hear each word
/// in the fluent self's voice), the line with its marked words — a tap
/// opens that word's sounds — the month in one line, and every other number
/// Azure returned folded under Details. Opened from the shadow result's
/// Pronunciation line, the speech result's Pronunciation row, the
/// pronunciation call's verdict pill, and the scorecard's axis (the
/// standing alone, `results` empty).
struct PronunciationDetailSheet: View {
    /// The take's assessment — a speech take is several pieces, in order.
    /// Empty = the standing alone.
    let results: [PronunciationResult]
    var language: String = LanguageScope.active

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    /// The word whose sounds are open under the line.
    @State private var openWord: Int?
    @State private var speakingWord: String?
    @State private var detailsOpen = false

    private var profile: PronunciationProfile { PronunciationProfile.current(language: language) }
    private var namesSounds: Bool { !results.flatMap(\.namedPhonemes).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                headline
                if !results.isEmpty {
                    workOnSection
                    lineSection
                } else {
                    standingSoundsSection
                }
                monthSection
                detailsSection
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

    // MARK: - The number

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

    private var headlineScore: Int? {
        results.isEmpty ? profile.meanAccuracy : weighted { $0.soundScore }
    }

    private var headline: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let s = headlineScore {
                    Text("\(s)")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(SpeechScoreColor.color(s))
                }
                Text(results.isEmpty
                     ? explain("How closely your sounds matched a native speaker's, over the last 30 days.")
                     : explain("How closely your sounds matched a native speaker's."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sounds to work on (this take)

    private struct WorkItem: Identifiable {
        /// "th /θ/" for a sound; the word itself where no sound is named.
        let title: String
        let detail: String?
        let mean: Int
        /// Words of this take that carry it, worst first.
        let words: [String]
        var id: String { title }
    }

    /// Sounds under the weak bar in this take (English), each with the words
    /// it was low in; elsewhere the marked words themselves.
    private var workItems: [WorkItem] {
        if namesSounds {
            var scores: [String: [Int]] = [:]
            var carriers: [String: [(String, Int)]] = [:]
            for w in results.flatMap(\.judgedWords) {
                for p in w.phonemes where !p.phoneme.isEmpty {
                    guard let a = p.accuracy else { continue }
                    scores[p.phoneme, default: []].append(a)
                    carriers[p.phoneme, default: []].append((w.word, a))
                }
            }
            return scores.compactMap { (p, v) -> WorkItem? in
                let mean = v.reduce(0, +) / v.count
                guard mean < PronunciationProfile.weakBar else { return nil }
                var seen = Set<String>()
                let words = (carriers[p] ?? []).sorted { $0.1 < $1.1 }
                    .compactMap { seen.insert($0.0.lowercased()).inserted ? $0.0 : nil }
                return WorkItem(title: Self.soundName(p, language: language), detail: "/\(p)/",
                                mean: mean, words: Array(words.prefix(3)))
            }
            .sorted { $0.mean == $1.mean ? $0.title < $1.title : $0.mean < $1.mean }
        }
        var seen = Set<String>()
        return results.flatMap(\.weakWords).compactMap { w -> WorkItem? in
            guard seen.insert(w.word.lowercased()).inserted, let a = w.accuracy else { return nil }
            return WorkItem(title: w.word, detail: nil, mean: a, words: [w.word])
        }
    }

    @ViewBuilder
    private var workOnSection: some View {
        let items = workItems
        Section {
            if items.isEmpty {
                Label(explain("Nothing stood out in this take."), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ForEach(items) { item in
                    workRow(item)
                }
            }
        } header: {
            Text(namesSounds ? "Sounds to work on" : "Words to work on")
        } footer: {
            if !items.isEmpty {
                Text(namesSounds
                     ? explain("Tap a word to hear it in your fluent voice. A sound is listed when it averaged under \(PronunciationProfile.weakBar) in this take.")
                     : explain("Tap a word to hear it in your fluent voice."))
            }
        }
    }

    private func workRow(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: item.title).font(.body.weight(.semibold))
                if let d = item.detail {
                    Text(verbatim: d).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Self.verdict(item.mean))
                    .font(.subheadline)
                    .foregroundStyle(Self.verdictColor(item.mean))
            }
            if !item.words.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.words, id: \.self) { word in
                        Button { Task { await speak(word) } } label: {
                            HStack(spacing: 4) {
                                Image(systemName: speakingWord == word ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.caption2)
                                Text(verbatim: word)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appState.speakingVoiceId == nil)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - The line

    private var lineWords: [PronunciationResult.Word] { results.flatMap(\.referenceWords) }

    private var lineSection: some View {
        Section {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(lineWords.enumerated()), id: \.offset) { i, w in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { openWord = openWord == i ? nil : i }
                    } label: {
                        Text(verbatim: w.word)
                            .font(.body)
                            .foregroundStyle(w.isOmission ? .secondary : .primary)
                            .underline(markColor(w) != nil, pattern: .dot, color: markColor(w))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 3)
                            .background(openWord == i ? Color.accentColor.opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            if let i = openWord, lineWords.indices.contains(i) {
                wordDetail(lineWords[i])
            }
        } header: {
            Text("What you read")
        } footer: {
            Text(explain("Red: clearly off. Orange: a bit off. Grey: not heard. Tap a word to see its sounds."))
        }
    }

    private func markColor(_ w: PronunciationResult.Word) -> Color? {
        guard w.isJudged else { return nil }
        switch PronunciationResult.grade(w) {
        case 0:  return .red
        case 1:  return .orange
        default: return nil
        }
    }

    @ViewBuilder
    private func wordDetail(_ w: PronunciationResult.Word) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: w.word).font(.subheadline.weight(.semibold))
                Spacer()
                if w.isOmission {
                    Text("Not heard").font(.subheadline).foregroundStyle(.secondary)
                } else if let a = w.accuracy {
                    Text(Self.verdict(a)).font(.subheadline).foregroundStyle(Self.verdictColor(a))
                    Text("\(a)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if appState.speakingVoiceId != nil, !w.isOmission {
                    Button { Task { await speak(w.word) } } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.borderless)
                }
            }
            let named = w.phonemes.filter { !$0.phoneme.isEmpty && $0.accuracy != nil }
            if !named.isEmpty {
                phonemeLine(named).font(.footnote)
            } else if let label = breakLabel(w) {
                Text(label).font(.footnote).foregroundStyle(.secondary)
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
            out = out + Text(verbatim: "\(p.phoneme) \(score)").foregroundStyle(phonemeColor(score))
            if let heard = p.heard?.first, heard.phoneme != p.phoneme, score < 60 {
                out = out + Text(verbatim: " ") + Text(explain("(sounded like \(heard.phoneme))")).foregroundStyle(.secondary)
            }
        }
        return out
    }

    /// The word bars, applied to one sound: red under 35, orange under 45.
    private func phonemeColor(_ score: Int) -> Color {
        score < 35 ? .red : score < 45 ? .orange : .secondary
    }

    private func breakLabel(_ w: PronunciationResult.Word) -> String? {
        switch w.error {
        case "UnexpectedBreak": return explain("A stop before it")
        case "MissingBreak":    return explain("No pause before it")
        case "Monotone":        return explain("Flat")
        default:                return nil
        }
    }

    // MARK: - The standing alone (scorecard)

    @ViewBuilder
    private var standingSoundsSection: some View {
        let p = profile
        if p.takes > 0 {
            Section {
                if p.weakSounds.isEmpty && p.weakWords.isEmpty {
                    Label(explain("No sound stays low across your takes."), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                ForEach(p.weakSounds, id: \.self) { s in
                    HStack {
                        Text(verbatim: Self.soundName(s.phoneme, language: language)).font(.body.weight(.semibold))
                        Text(verbatim: "/\(s.phoneme)/").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.verdict(s.mean)).font(.subheadline).foregroundStyle(Self.verdictColor(s.mean))
                    }
                }
                ForEach(p.weakWords, id: \.self) { w in
                    HStack {
                        Text(verbatim: w.word).font(.body.weight(.semibold))
                        Spacer()
                        Text(Self.verdict(w.mean)).font(.subheadline).foregroundStyle(Self.verdictColor(w.mean))
                    }
                }
            } header: {
                Text("Sounds to work on")
            }
        } else {
            Section {
                Text(explain("Shadow a line or read a speech and your sounds are measured here."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - The month

    @ViewBuilder
    private var monthSection: some View {
        let p = profile
        if p.takes > 0, let mean = p.meanAccuracy {
            Section("Last 30 days") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(explain("\(p.takes) takes · average \(mean)"))
                    if !p.weakSounds.isEmpty {
                        Text(explain("Still low: ") + p.weakSounds.prefix(4)
                                .map { Self.soundName($0.phoneme, language: language) }
                                .joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if !p.weakWords.isEmpty {
                        Text(explain("Low in several takes: ") + p.weakWords.prefix(4).map(\.word).joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if p.takes >= 3 {
                        Text(explain("Nothing stays low across takes."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Details (every number Azure returned)

    private var detailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $detailsOpen) {
                if !results.isEmpty {
                    if let v = weighted({ $0.fluency }) { numberRow("Flow", v) }
                    if let v = weighted({ $0.completeness }) { numberRow("Completeness", v) }
                    if let v = weighted({ $0.prosody }) { numberRow("Intonation", v) }
                    if let v = weighted({ $0.score }) { numberRow("Overall", v) }
                    if let locale = results.first?.locale {
                        HStack {
                            Text("Judged against")
                            Spacer()
                            Text(verbatim: Self.localeName(locale)).foregroundStyle(.secondary)
                        }
                    }
                    let heard = results.map(\.recognized).filter { !$0.isEmpty }
                    if !heard.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("What the model heard").font(.subheadline)
                            Text(verbatim: heard.joined(separator: " "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(takeSounds) { s in
                        HStack {
                            Text(verbatim: "\(Self.soundName(s.phoneme, language: language)) /\(s.phoneme)/")
                            Text(verbatim: "×\(s.count)").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(s.mean)").font(.body.monospacedDigit()).foregroundStyle(Self.verdictColor(s.mean))
                        }
                    }
                } else {
                    ForEach(profile.sounds, id: \.self) { s in
                        HStack {
                            Text(verbatim: "\(Self.soundName(s.phoneme, language: language)) /\(s.phoneme)/")
                            Text(verbatim: "×\(s.count)").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(s.mean)").font(.body.monospacedDigit()).foregroundStyle(Self.verdictColor(s.mean))
                        }
                    }
                }
            } label: {
                Text("Details")
            }
        } footer: {
            Text(explain("Scores come from Azure's pronunciation assessment against a native model of the language. Sound names are given for English only. Flow is the pauses between words, completeness how much of the line was said, intonation stress and rhythm. A word is red under 50 or with a sound under 35, orange under 70 or with a sound under 45; a native speaker's slip reads orange at most. One take's marks move with where the recording was cut, so what matters is a sound that stays low across takes."))
        }
    }

    private func numberRow(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").font(.body.monospacedDigit()).foregroundStyle(SpeechScoreColor.color(value))
        }
    }

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

    // MARK: - Words

    private func speak(_ word: String) async {
        guard let voiceId = appState.speakingVoiceId else { return }
        speakingWord = word
        defer { speakingWord = nil }
        if let data = PhraseAudioStore.shared.data(text: word, voiceId: voiceId) {
            try? player.play(data, forceSessionReset: true)
            return
        }
        guard let data = try? await VoiceClient.shared.synthesize(voiceId: voiceId, text: word, purpose: "library")
        else { return }
        PhraseAudioStore.shared.save(data, text: word, voiceId: voiceId)
        try? player.play(data, forceSessionReset: true)
    }

    // MARK: - Names and verdicts

    /// "Low" under 50, "A bit off" under 70, "Fine" otherwise — the bars the
    /// marks and the profile use.
    static func verdict(_ score: Int) -> String {
        score < 50 ? explain("Low") : score < PronunciationProfile.weakBar ? explain("A bit off") : explain("Fine")
    }

    static func verdictColor(_ score: Int) -> Color {
        score < 50 ? .red : score < PronunciationProfile.weakBar ? .orange : .green
    }

    /// A sound as a learner reads it: the course's own name where the sound
    /// has a chapter ("th"), a plain spelling otherwise ("sh", "ee"), the
    /// IPA itself as the last resort.
    static func soundName(_ phoneme: String, language: String) -> String {
        if let topic = PronunciationCourse.topics(for: language).first(where: { $0.phonemes == [phoneme] }) {
            return topic.symbol
        }
        return englishNames[phoneme] ?? phoneme
    }

    private static let englishNames: [String: String] = [
        "θ": "th", "ð": "th", "ʃ": "sh", "ʒ": "zh", "tʃ": "ch", "dʒ": "j", "ŋ": "ng",
        "ɹ": "r", "r": "r", "j": "y", "w": "w", "h": "h",
        "æ": "a", "ɪ": "i", "i": "ee", "iː": "ee", "ʊ": "u", "u": "oo", "uː": "oo",
        "ɛ": "e", "e": "e", "ʌ": "u", "ɑ": "ah", "ɑː": "ah", "ɒ": "o", "ɔ": "aw", "ɔː": "aw",
        "ə": "uh", "ɝ": "er", "ɚ": "er", "ɜ": "er", "ɜː": "er",
        "eɪ": "ay", "aɪ": "eye", "oʊ": "oh", "əʊ": "oh", "aʊ": "ow", "ɔɪ": "oy",
    ]

    /// "en-US" → "English (United States)" in the app language.
    static func localeName(_ id: String) -> String {
        let code = id.replacingOccurrences(of: "_", with: "-")
        return Locale(identifier: UILanguage.chromeLanguage).localizedString(forIdentifier: code) ?? id
    }
}
