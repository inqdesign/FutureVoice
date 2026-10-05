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

    /// Each language's sample is WRITTEN in that language, not translated
    /// (2026-10-05, founder: the translated headphones explainer read badly
    /// in Korean and stiffly in English). Same topic and facts, each its own
    /// text.
    private static let builtInTitles: [String: String] = [
        "en": "Why yawns are contagious",
        "ko": "하품은 왜 옮을까",
        "ja": "あくびはなぜうつるの？",
        "de": "Warum Gähnen ansteckt",
    ]

    private static let builtInBodies: [String: String] = [
        "en": """
        Quick question: how many times have you yawned today? Don't be surprised if that number goes up in the next minute.

        Yawns are contagious. See someone yawn, and there's a good chance you'll follow. In some studies, about half the people tested did. You don't even have to see it. Hearing a yawn, or just reading about one, like you're doing right now, can be enough.

        So why does it spread? Many scientists think it comes down to empathy. We catch yawns more easily from family and close friends than from strangers.

        Here's the surprising part. Babies don't catch yawns at all. It usually starts around age four or five, right about when children begin to understand how other people feel.

        So the next time a yawn ripples through a meeting, don't take it personally. It may just mean everyone in the room is tuned in to each other.
        """,
        "ko": """
        여러분, 오늘 하품 몇 번 하셨나요? 이 이야기를 듣다 보면 아마 한 번 더 하시게 될 겁니다.

        하품은 옮습니다. 옆 사람이 하품하는 걸 보면 나도 모르게 따라 하게 되죠. 실제로 한 실험에서는 참가자의 절반 가까이가 하품을 따라 했습니다. 꼭 눈으로 볼 필요도 없습니다. 하품 소리를 듣거나, 지금처럼 하품 이야기를 읽기만 해도 하품이 나옵니다.

        과학자들은 그 이유를 공감에서 찾습니다. 하품은 모르는 사람보다 가족이나 친한 친구에게서 더 잘 옮거든요.

        재미있는 건 아기들은 하품이 옮지 않는다는 점입니다. 하품이 옮기 시작하는 건 네다섯 살 무렵, 아이가 다른 사람의 마음을 헤아리기 시작할 때쯤이라고 합니다.

        그러니 회의 시간에 하품이 번져도 너무 서운해하지 마세요. 서로에게 마음을 쓰고 있다는 뜻일지도 모르니까요.
        """,
        "ja": """
        皆さん、誰かのあくびを見て、つられてあくびをしたことはありませんか。実はこれ、とてもよくあることなんです。ある研究では、およそ半分の人があくびをうつされました。

        しかも、見なくてもうつります。あくびの音を聞いたり、あくびについて読んだりするだけで十分なんです。もしかしたら今、皆さんもあくびが出そうになっていませんか。

        多くの研究者は、これを共感や人とのつながりに結びつけています。知らない人より、家族や親しい友だちのあくびのほうが、ずっとうつりやすいからです。そして、赤ちゃんや小さな子どもには、あくびはうつりません。始まるのは四歳か五歳ごろ。ちょうど、人の気持ちがわかり始めるころです。

        だから次にあくびがうつったら、恥ずかしがらなくて大丈夫です。それは、誰かとつながっているしるしなんです。
        """,
        "de": """
        Habt ihr schon mal gegähnt, nur weil jemand neben euch gegähnt hat? Dann seid ihr in guter Gesellschaft. In manchen Studien hat sich ungefähr die Hälfte der Leute anstecken lassen.

        Und man muss es nicht einmal sehen. Ein Gähnen zu hören reicht oft schon, sogar darüber zu lesen kann genügen. Und, merkt ihr es gerade selbst?

        Viele Forschende sehen darin ein Zeichen von Empathie. Bei Familie und engen Freunden steckt man sich nämlich leichter an als bei Fremden. Babys und kleine Kinder gähnen übrigens nicht mit. Das beginnt meist erst mit vier oder fünf Jahren, ungefähr dann, wenn Kinder verstehen, was andere fühlen.

        Wenn ihr also das nächste Mal mitgähnt, dann nehmt es als gutes Zeichen. Ihr seid mit jemandem verbunden.
        """,
    ]
}
