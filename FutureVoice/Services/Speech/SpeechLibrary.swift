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
    /// in Korean and stiffly in English). Same points, each its own text.
    /// The topic is the tab's own case — why practise speaking out loud —
    /// so the first thing a learner reads here is also why to keep coming
    /// back (founder's call, replacing a yawning piece).
    private static let builtInTitles: [String: String] = [
        "en": "Why practise out loud?",
        "ko": "왜 소리 내어 연습해야 할까",
        "ja": "声に出して話そう",
        "de": "Sprecht es laut aus",
    ]

    private static let builtInBodies: [String: String] = [
        "en": """
        Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?

        Speaking is a skill, not just knowledge. You can know the words and the grammar, but if your mouth has never actually built the sentence, it tends to let you down when it matters. That's why practice has to happen out loud.

        Saying things aloud also helps them stick. Research suggests we remember what we've said better than what we've only read.

        And when you record yourself, you notice things you'd never catch otherwise: how fast you really talk, how often you say "um" and "uh", whether your voice fades at the end of a sentence.

        Presentations, interviews, even a first conversation with someone new all get easier with practice. The minute you just spent reading this out loud? That was your first rep.
        """,
        "ko": """
        여러분, 머릿속에서는 완벽했던 문장이 막상 입 밖으로 나오는 순간 엉켜 버린 적, 있으시죠?

        말하기는 아는 것과 하는 것이 다른 기술입니다. 단어와 문법을 알아도 입이 그 문장을 직접 만들어 본 적이 없으면, 정작 중요한 순간에 막힙니다. 그래서 연습은 소리 내어 해야 합니다.

        소리 내어 말하면 기억에도 더 오래 남습니다. 눈으로만 읽은 내용보다 직접 말해 본 내용을 더 잘 기억한다는 연구도 있습니다.

        녹음해서 들어 보면 더 많은 것이 보입니다. 내가 실제로 얼마나 빨리 말하는지, "음", "어" 같은 말을 얼마나 자주 하는지, 문장 끝에서 목소리가 작아지지는 않는지. 혼자서는 잘 모르는 것들이거든요.

        발표도, 면접도, 처음 만나는 사람과 나누는 대화도 연습한 만큼 편해집니다. 지금 이 원고를 소리 내어 읽은 일 분이 바로 그 첫 연습입니다.
        """,
        "ja": """
        皆さん、頭の中では完璧だった文が、口に出した瞬間に崩れてしまった経験はありませんか。

        話すことは、知識ではなく技術です。単語や文法を知っていても、自分の口で一度も言ったことのない文は、いざという時に出てきません。だから練習は、声に出してするものなんです。

        声に出すと、覚えやすくもなります。黙って読んだことより、声に出して言ったことのほうが記憶に残りやすい、という研究もあるそうです。

        そして、自分の声を録音してみてください。本当はどのくらいの速さで話しているのか。「えーと」や「あの」を、どれだけ言っているのか。文の終わりで、声が小さくなっていないか。一人では気づけないことが、はっきり聞こえてきます。

        発表も、面接も、初めての人との会話も、練習すれば楽になります。今この文章を声に出して読んだ一分間が、皆さんの最初の練習です。
        """,
        "de": """
        Kennt ihr das? Im Kopf ist der Satz perfekt. Und sobald ihr ihn aussprecht, fällt er auseinander.

        Sprechen ist eine Fähigkeit, nicht nur Wissen. Ihr könnt alle Wörter und die Grammatik kennen. Wenn euer Mund den Satz aber noch nie gebildet hat, lässt er euch im entscheidenden Moment im Stich. Deshalb müsst ihr laut üben.

        Was ihr laut sagt, bleibt außerdem besser hängen. Studien deuten darauf hin, dass wir uns an Ausgesprochenes besser erinnern als an das, was wir nur still gelesen haben.

        Nehmt euch dabei auf. Dann hört ihr, was euch allein nicht auffällt: wie schnell ihr wirklich sprecht, wie oft ihr „äh“ oder „ähm“ sagt, und ob eure Stimme am Satzende leiser wird.

        Präsentationen, Vorstellungsgespräche, sogar ein Gespräch mit jemand Neuem: Mit Übung wird das alles leichter. Und die Minute, in der ihr das gerade laut gelesen habt? Das war eure erste Übung.
        """,
    ]
}
