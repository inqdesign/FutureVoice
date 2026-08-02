import Foundation

/// The 60–90s read-aloud script for the voice clone — in whichever language
/// the user can actually read WELL.
///
/// Why two languages: ElevenLabs captures a voice, not a language. A learner
/// who stumbles through an English paragraph hands the cloner halting,
/// disfluent speech, and the clone inherits the stumble instead of the
/// person. Beta takes bore this out — reading the native script produced an
/// audibly better clone for anyone not already comfortable reading English
/// aloud, while comfortable readers got the better result from the English
/// one (their own English phonemes, no accent transfer). So the script step
/// offers both and defaults by the learner's self-rated level.
///
/// Sources, in order:
///   1. hand-authored — English (the target) and Korean (the main market);
///   2. one cached Gemini generation per native language, written to the same
///      brief (kept on disk forever, so it's a once-per-device call);
///   3. English, as the floor — a generation that never lands must never
///      block the flow.
final class CloneScriptStore {
    static let shared = CloneScriptStore()

    /// Phonetically varied so the clone has range — short and long vowels,
    /// hard consonants, rising and falling intonation. Read it like you mean
    /// it, not like a school recital.
    ///
    /// Sized so a natural read lands in the 60–90s window: ~180 words at a
    /// careful read-aloud pace ≈ 75–80s. An earlier ~115-word script ran out
    /// near 50s and users understandably tapped "Stop (early)" — every short
    /// sample hurts clone quality more than any prompt tweak can win back.
    static let english = [
        "Hi. I'm recording this so my fluent self can sound like me. I'm curious. I'm patient. I want to sound like me — just a more confident version.",
        "Let me describe a moment from this week. The weather turned cooler than I expected. I was walking and caught myself thinking in two languages at once — one for what I saw, one for what I felt. Funny how that works.",
        "Here's a quick list, just to stretch the sounds: Monday morning, Wednesday afternoon, Friday night. Three, thirteen, thirty-three. A double espresso, a glass of water, and a window seat if you have one, please.",
        "Now a few different shapes: \"Could you actually repeat that?\" \"Wait — that's not quite right.\" \"Honestly, I'm not sure yet, but here's what I think.\" \"Oh, that's brilliant — say more.\"",
        "One more, a little slower this time. When I speak this language a year from now, I want it to feel easy. Not perfect — easy. Like I'm not translating anymore, just talking.",
        "Okay. I think that's enough of my voice for now. If this worked, the next voice you hear should sound a lot like me. Talk to me soon.",
    ]

    /// Korean — hand-authored rather than generated, because it's the main
    /// market and this text is the single input to the whole product. Same
    /// six beats as the English one (intent · a remembered moment · a list
    /// that stretches the sounds · four different intonation shapes · a
    /// slower close · sign-off), sized to the same 75–85s read: Korean runs
    /// ~4.5 syllables a second at a careful pace, so ~350 syllables.
    /// Deliberately spreads 된소리/격음, 장·단모음 and varied 받침.
    static let korean = [
        "안녕하세요. 저와 똑같은 목소리로, 훨씬 더 유창하게 말하는 제가 생긴다니 조금 신기하네요. 저는 궁금한 게 많고, 참을성도 있는 편이에요. 지금보다 조금만 더 당당한 저였으면 좋겠어요.",
        "이번 주에 있었던 일을 하나 이야기해 볼게요. 날씨가 생각보다 쌀쌀해져서 옷깃을 여미고 걸었어요. 걷다가 문득, 눈에 보이는 것과 마음에 떠오르는 생각이 서로 다른 말이라는 걸 느꼈어요.",
        "이번엔 소리를 좀 늘려 볼게요. 월요일 아침, 수요일 오후, 금요일 밤. 셋, 열셋, 서른셋. 따뜻한 커피 한 잔, 시원한 물 한 컵, 그리고 창가 자리 하나 부탁드려요.",
        "말투도 바꿔 볼게요. \"방금 그거 다시 한번 말해 줄래요?\" \"잠깐만요, 그건 좀 아닌 것 같은데요.\" \"솔직히 아직 잘 모르겠어요. 그래도 제 생각은 이래요.\" \"우와, 그거 진짜 좋다. 더 얘기해 줘요.\"",
        "조금만 더 천천히 읽어 볼게요. 일 년 뒤에 이 언어로 말할 때는, 지금보다 훨씬 편했으면 좋겠어요. 완벽하지 않아도 괜찮아요. 번역하지 않고 그냥 말하는 것처럼요.",
        "자, 이 정도면 충분한 것 같아요. 잘 됐다면, 다음에 들리는 목소리는 저와 아주 비슷하게 들릴 거예요. 곧 다시 이야기해요.",
    ]

    /// Bump when the generation brief changes — cached scripts written to the
    /// old brief are then regenerated on next use.
    private static let promptVersion = 1

    private struct Entry: Codable {
        var paragraphs: [String]
        var generatedAt: Date
        var promptVersion: Int
    }
    private struct Payload: Decodable { let paragraphs: [String] }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "clone_scripts.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// The script for a language RIGHT NOW — hand-authored or already cached.
    /// nil means "not on this device yet"; call `ensure` to fetch one.
    func script(for code: String) -> [String]? {
        if let built = Self.handAuthored(code) { return built }
        guard let entry = load()[code],
              entry.promptVersion == Self.promptVersion,
              !entry.paragraphs.isEmpty else { return nil }
        return entry.paragraphs
    }

    static func handAuthored(_ code: String) -> [String]? {
        switch code {
        case "en": return english
        case "ko": return korean
        default:   return nil
        }
    }

    /// Fetch-and-cache. Returns immediately when the script already exists,
    /// so the caller can fire this early (the intro step) and simply read
    /// `script(for:)` later. Failures return nil and are never surfaced — the
    /// script step falls back to English.
    @discardableResult
    func ensure(for code: String) async -> [String]? {
        if let have = script(for: code) { return have }
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: Self.systemPrompt(code: code),
                messages: [GeminiClient.Message(role: .user, content: "Write the script.")],
                model: .flash36,
                maxTokens: 1200,
                purpose: "clone-script",
                idempotencyKey: "clone-script:\(code):v\(Self.promptVersion)"
            )
            let paragraphs = payload.paragraphs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            // A stub of two lines is worse than English — it can't fill 60s.
            guard paragraphs.count >= 4 else { return nil }
            var all = load()
            all[code] = Entry(paragraphs: paragraphs, generatedAt: Date(),
                              promptVersion: Self.promptVersion)
            save(all)
            return paragraphs
        } catch {
            return nil
        }
    }

    // MARK: - Prompt

    /// The brief the hand-authored scripts were written to, stated for the
    /// model. Concrete beats rather than "write a script", because the whole
    /// value of the text is the phonetic range and intonation variety it
    /// forces out of the reader.
    private static func systemPrompt(code: String) -> String {
        let name = LanguageCatalog.englishName(code)
        return """
        Write a read-aloud script in \(name) for someone recording a sample of
        their own voice. The recording trains a voice clone, so the text must
        pull a wide range of sounds and intonations out of an ordinary adult
        reading it once, without rehearsal.

        Six paragraphs, first person, warm and casual, in this exact order:
        1. Why they're recording: they want their fluent self to sound like
           them. Two or three short self-descriptions.
        2. A small remembered moment from this week — weather, a walk, a
           passing thought. Ordinary, not dramatic.
        3. A short list that stretches the sounds: three days-of-week with a
           time of day, three related numbers, and a small everyday order or
           request.
        4. Four quoted lines with clearly DIFFERENT shapes: a question, a
           correction or interruption, an uncertain admission, an excited
           reaction.
        5. A slower, quieter one about wanting this language to feel easy a
           year from now.
        6. A short sign-off saying that's enough, and the next voice they hear
           should sound like them.

        Rules:
        - Length: a careful read-aloud must take 75–85 SECONDS in \(name).
          Judge by that language's own speaking rate, not by word count.
        - Everyday words only. A nervous reader must never hit a word they'd
          stumble on — no literary, technical, or rare vocabulary.
        - Write numbers as WORDS, not digits, so there's no ambiguity in how
          to say them.
        - Vary the consonants, vowel lengths, and sentence endings the
          language offers.
        - Natural spoken \(name), not translated English. Idioms and rhythm
          native to the language.
        - No stage directions, no headings, no numbering in the output text.

        Return STRICT JSON only — no prose, no code fences:
        { "paragraphs": ["...", "...", "...", "...", "...", "..."] }
        """
    }

    // MARK: - Disk

    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let all = try? decoder.decode([String: Entry].self, from: data) else { return [:] }
        return all
    }

    private func save(_ all: [String: Entry]) {
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
