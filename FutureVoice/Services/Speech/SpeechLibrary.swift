import Foundation

/// The bundled script (one per target language — the one every account can
/// practise) and the per-language numbers the Speech tab measures against.
enum SpeechLibrary {

    // MARK: - Speaking rate

    /// What a rate is counted in. Words where spaces mark them; Korean by
    /// SYLLABLE, because 어절 vary from one to six syllables and a
    /// broadcaster's pace is quoted in 음절; Japanese by character (NHK's
    /// 字/分).
    enum RateUnit { case words, syllables, characters }

    static func rateUnit(_ language: String) -> RateUnit {
        switch LanguageCatalog.base(language) {
        case "ko": return .syllables
        case "ja", "zh": return .characters
        default: return .words
        }
    }

    /// A comfortable presentation pace, low…high, in `rateUnit`s per minute.
    /// Broadcast pace sits at the top of each band; a learner reading for
    /// clarity is right anywhere inside it.
    static func rateBand(_ language: String) -> ClosedRange<Int> {
        switch LanguageCatalog.base(language) {
        case "ko": return 240...330
        case "ja": return 260...340
        case "de": return 105...140
        case "fr", "es", "it", "pt": return 130...170
        default: return 120...160
        }
    }

    /// The midpoint — what a script's length is written to.
    static func plannedRate(_ language: String) -> Int {
        let band = rateBand(language)
        return (band.lowerBound + band.upperBound) / 2
    }

    /// How many units a script of `seconds` should hold.
    static func plannedUnits(seconds: Int, language: String) -> Int {
        plannedRate(language) * seconds / 60
    }

    /// The units in `text`, counted the way `rateUnit` says.
    static func units(in text: String, language: String) -> Int {
        switch rateUnit(language) {
        case .words:
            return text.split(whereSeparator: { $0.isWhitespace }).filter {
                $0.contains(where: { $0.isLetter || $0.isNumber })
            }.count
        case .syllables, .characters:
            return text.filter { $0.isLetter || $0.isNumber }.count
        }
    }

    /// Estimated read time, in seconds, at the planned pace.
    static func estimatedSeconds(_ text: String, language: String) -> Int {
        let rate = max(1, plannedRate(language))
        return Int((Double(units(in: text, language: language)) / Double(rate) * 60).rounded())
    }

    static let lengths: [Int] = [30, 60, 120, 180]

    // MARK: - Fillers

    /// Hesitation sounds the reader writes down so they can be counted. Only
    /// sounds that are never words in a script: Korean 그 / 저 are fillers in
    /// speech and demonstratives in text, so they are left out rather than
    /// miscounted.
    static func fillers(_ language: String) -> [String] {
        switch LanguageCatalog.base(language) {
        case "ko": return ["어", "음", "으음", "어어", "엄", "에"]
        case "ja": return ["えーと", "ええと", "えっと", "えー", "あのー", "うーん"]
        case "de": return ["äh", "ähm", "öh", "hm", "hmm"]
        case "fr": return ["euh", "heu", "bah"]
        case "es": return ["eh", "em", "este"]
        default: return ["um", "uh", "er", "erm", "uhm", "hmm", "mm"]
        }
    }

    // MARK: - The bundled script

    static func builtIn(for language: String) -> SpeechScript? {
        let code = LanguageCatalog.base(language)
        guard let body = builtInBodies[code], let title = builtInTitles[code] else { return nil }
        return SpeechScript(
            id: builtInId(code),
            title: title,
            genre: .explainer,
            topic: "",
            body: body,
            summary: "",
            keyTerms: [],
            sources: [],
            language: code,
            targetSeconds: 60,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            isBuiltIn: true
        )
    }

    /// Stable per language, so takes keep pointing at the script across
    /// launches and revisions of its text.
    private static func builtInId(_ code: String) -> UUID {
        let suffix: String
        switch code {
        case "ko": suffix = "000000000002"
        case "ja": suffix = "000000000003"
        case "de": suffix = "000000000004"
        default:   suffix = "000000000001"
        }
        return UUID(uuidString: "5BEEC000-0000-4000-8000-\(suffix)")!
    }

    private static let builtInTitles: [String: String] = [
        "en": "How noise-cancelling headphones work",
        "ko": "노이즈 캔슬링 헤드폰의 원리",
        "ja": "ノイズキャンセリングの仕組み",
        "de": "Wie Geräuschunterdrückung funktioniert",
    ]

    private static let builtInBodies: [String: String] = [
        "en": """
        Good evening. Tonight, a question most of us never stop to ask: how do noise-cancelling headphones actually work?

        Sound is a wave. It travels through the air as tiny changes in pressure, rising and falling many times a second.

        Inside each ear cup, a small microphone listens to the noise around you. A chip studies that wave and, in a fraction of a millisecond, creates its mirror image. Where the noise rises, the new wave falls.

        When the two waves meet, they cancel each other out. What reaches your ear is close to silence.

        This works best on steady, low sounds, like the hum of a plane's engine. Sudden, high sounds, like a voice, are harder to predict, which is why you can still hear them.

        So the next time the world goes quiet, remember: you are not hearing less sound. You are hearing two sounds erasing each other.
        """,
        "ko": """
        안녕하세요. 오늘은 우리가 매일 쓰지만 원리는 잘 모르는 기술 하나를 소개해 드리겠습니다. 바로 노이즈 캔슬링 헤드폰입니다.

        소리는 파동입니다. 공기의 압력이 1초에도 여러 번 높아졌다 낮아지면서, 우리 귀에 전달됩니다.

        헤드폰 안에는 작은 마이크가 있어서, 주변의 소음을 계속 듣고 있습니다. 칩이 그 파동을 분석하고, 순식간에 정반대 모양의 파동을 만들어 냅니다. 소음이 올라갈 때, 새 파동은 내려가는 것이죠.

        두 파동이 만나면 서로를 지워 버립니다. 그래서 귀에는 거의 고요함만 남습니다.

        이 기술은 비행기 엔진처럼 낮고 일정한 소리에 특히 강합니다. 반대로 사람 목소리처럼 갑자기 바뀌는 높은 소리는 예측하기 어려워서, 여전히 조금 들립니다.

        다음에 세상이 조용해지면 기억해 보세요. 소리가 줄어든 것이 아니라, 두 소리가 서로를 지우고 있는 것입니다.
        """,
        "ja": """
        こんばんは。今日は、毎日使っているのに、仕組みはあまり知られていない技術をご紹介します。ノイズキャンセリングヘッドホンです。

        音は波です。空気の圧力が一秒間に何度も上がったり下がったりして、私たちの耳に届きます。

        ヘッドホンの中には小さなマイクがあり、周りの騒音をずっと聞いています。チップがその波を分析し、一瞬で正反対の形の波を作り出します。騒音が上がるとき、新しい波は下がるのです。

        二つの波が出会うと、お互いを打ち消し合います。その結果、耳にはほとんど静けさだけが残ります。

        この技術は、飛行機のエンジンのように低くて一定の音に特に強いです。一方、人の声のように急に変わる高い音は予測しにくいので、まだ少し聞こえます。

        次に世界が静かになったら、思い出してください。音が減ったのではなく、二つの音が消し合っているのです。
        """,
        "de": """
        Guten Abend. Heute geht es um eine Technik, die viele von uns täglich benutzen, ohne sie wirklich zu kennen: Kopfhörer mit Geräuschunterdrückung.

        Schall ist eine Welle. Der Luftdruck steigt und fällt viele Male pro Sekunde, und so erreicht er unser Ohr.

        In jeder Ohrmuschel sitzt ein kleines Mikrofon, das die Umgebung belauscht. Ein Chip analysiert diese Welle und erzeugt in Sekundenbruchteilen ihr Spiegelbild. Wo das Geräusch steigt, fällt die neue Welle.

        Treffen die beiden Wellen aufeinander, löschen sie sich gegenseitig aus. Am Ohr kommt fast nur Stille an.

        Am besten funktioniert das bei tiefen, gleichmäßigen Tönen, etwa dem Brummen eines Flugzeugtriebwerks. Plötzliche, hohe Töne wie eine Stimme sind schwerer vorherzusagen. Deshalb hört man sie noch.

        Wenn es also das nächste Mal still wird, denken Sie daran: Sie hören nicht weniger Schall. Sie hören zwei Geräusche, die sich gegenseitig auslöschen.
        """,
    ]
}
