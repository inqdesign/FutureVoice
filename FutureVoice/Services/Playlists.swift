import Foundation

/// The situations, as something to LISTEN to (2026-10-18).
///
/// Every scene the learner made is a short conversation between their fluent
/// self (their clone) and the other person (a preset voice). Played whole and
/// one after another, they are a listening playlist made of nothing but the
/// learner's own situations. A first cut also collected single fluent-self
/// lines from talks into hand-made playlists; the founder found a lone line
/// loses its context ("a scene is two people talking — that's what's good"),
/// so for now it is situations only.
///
/// Every line is audio the app ALREADY made when the scene was watched
/// (`PhraseAudioStore`, under the key `WatchView` wrote). Nothing is copied
/// and nothing is ever synthesized here — a line never heard has no file and
/// is left out — so listening costs nothing metered and needs no
/// `BillingGate`.
struct PlaylistLine: Hashable, Identifiable {
    var id = UUID()
    /// The scene's scenario id.
    var bookId: UUID
    var text: String
    /// The voice the line was made in. The learner's older clones still
    /// resolve through `PhraseAudioStore`'s lineage.
    var voiceId: String
    /// Who says it.
    var speaker: String
    /// True for the other person's line.
    var isOther: Bool
    var bookTitle: String

    /// The ids the other person's voice went by before (preset slots were
    /// re-voiced on 2026-09-28 and 2026-10-12), so a scene watched back then
    /// still finds its lines. Empty for the fluent self, whose older clones
    /// resolve through `PhraseAudioStore`'s lineage.
    var fallbackVoices: [String] = []

    /// A line that is not one of the app's own takes: a news-show line,
    /// downloaded to the cache (`NewsShow`). Played as is.
    var localFile: URL? = nil

    var isFluentSelf: Bool { !isOther }

    /// The file that plays: any speed's take, the file Watch played it from,
    /// or a take under an older voice id. A scene watched before a speed or
    /// voice change still plays as it was heard.
    var audioKey: String? {
        guard localFile == nil else { return nil }
        return PhraseAudioStore.shared.sceneLineKey(text: text, voiceId: voiceId, isOther: isOther,
                                             fallbackVoices: fallbackVoices)
    }

    var audioURL: URL? {
        if let localFile { return localFile }
        return audioKey.map(PhraseAudioStore.shared.url(forKey:))
    }

    var hasAudio: Bool {
        if let localFile { return FileManager.default.fileExists(atPath: localFile.path) }
        return audioKey != nil
    }

    /// Word timings measured on the take that plays, if any were kept.
    var storedTimings: [WordTiming]? {
        audioKey.flatMap(PhraseAudioStore.shared.timings(forKey:))
    }
}

/// One situation, ready to play.
struct SceneTrack: Identifiable, Hashable {
    let id: UUID
    let title: String
    let otherName: String
    let date: Date
    let lines: [PlaylistLine]
}

enum SceneLibrary {
    /// The scene played whole: every line of its dialogue in order, the
    /// fluent self in the learner's clone and the other person in the voice
    /// the scene was watched with.
    static func dialogue(scenario: Scenario, cloneId: String,
                         people: [Counterpart]) -> [PlaylistLine] {
        let other = otherPerson(for: scenario, in: people)
        let me = explain("Your fluent self")
        let otherVoices = VoicePreset.everyVoiceEverUsed(startingWith: other.voicePresetId)
        return (scenario.curriculum?.dialogue ?? []).compactMap { turn in
            let mine = turn.speaker == "user"
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PlaylistLine(bookId: scenario.id, text: text,
                                voiceId: mine ? cloneId : other.voicePresetId,
                                speaker: mine ? me : other.name,
                                isOther: !mine,
                                bookTitle: scenario.displayTitle,
                                fallbackVoices: mine ? [] : otherVoices)
        }
    }

    /// Every situation with something to hear, newest first. A scene with
    /// only one side on file isn't a conversation and is left out.
    static func tracks(scenarios: [Scenario], cloneId: String?) -> [SceneTrack] {
        guard let cloneId, !cloneId.isEmpty else { return [] }
        let people = CounterpartStore.shared.load()
        return scenarios
            .filter { $0.archivedAt == nil }
            .compactMap { scenario -> SceneTrack? in
                let lines = dialogue(scenario: scenario, cloneId: cloneId, people: people)
                    .filter(\.hasAudio)
                guard lines.contains(where: \.isFluentSelf),
                      lines.contains(where: \.isOther) else { return nil }
                return SceneTrack(id: scenario.id, title: scenario.displayTitle,
                                  otherName: otherPerson(for: scenario, in: people).name,
                                  date: scenario.curriculum?.generatedAt ?? scenario.createdAt,
                                  lines: lines)
            }
            .sorted { $0.date > $1.date }
    }

    /// The same person `ScenarioDetailView` hands the scene to `WatchView`, so
    /// the voice id matches the key the lines were cached under.
    private static func otherPerson(for scenario: Scenario, in people: [Counterpart]) -> Counterpart {
        scenario.counterpartId.flatMap { id in people.first { $0.id == id } }
            ?? ScenarioDetailView.syntheticCounterpart(for: scenario)
    }
}
