import Foundation

/// The read-aloud script for voice cloning, per TARGET language.
///
/// The sample must be in the language the clone will SPEAK: ElevenLabs keeps
/// far more of a speaker's identity when the sample and the output share a
/// language, and the fluent self only ever speaks the target. A learner
/// reading their target aloud is also the gentlest possible first contact
/// with it — reading is easier than speaking, and nothing is graded here.
///
/// Every script follows the same six-beat shape so the clone gets the same
/// phonetic range in any language:
///   1. who I am / why I'm recording — plain declaratives
///   2. a small remembered moment — longer, flowing sentences
///   3. a list: weekdays, numbers, an order — clipped rhythm, digits
///   4. spoken shapes — question, correction, hesitation, delight
///   5. a slower, warmer close — sustained vowels
///   6. a sign-off — falling intonation
///
/// Sized for a careful read-aloud of 75–80s (the recorder wants ≥ 60s).
/// Adding a target language means adding an entry here; `paragraphs(for:)`
/// falls back to English so a new catalog entry can never leave the step blank.
enum VoiceCloneScript {

    static func paragraphs(for language: String) -> [String] {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return byLanguage[code] ?? byLanguage["en"]!
    }

    /// The clone's first words, spoken back in the user's own voice the moment
    /// it exists. Short on purpose — one TTS call per onboarding.
    static func greeting(for language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return greetings[code] ?? greetings["en"]!
    }

    /// The words BOTH sides of `VoiceComparisonSheet` say: the opening of the
    /// script the learner actually read.
    ///
    /// Cut at a sentence boundary near 120 characters — long enough to hear a
    /// voice, short enough that the single synthesis it costs stays small and
    /// the recording's own opening still covers the same ground.
    ///
    /// `scriptLanguage` is what the sample was READ in, which is not always
    /// the target: a learner may take the native-script option, and then the
    /// recording holds Korean while the app teaches English. Handing back the
    /// target script there would have the clone say words the recording never
    /// contains, and the comparison stops being a comparison.
    static func comparisonOpening(scriptLanguage: String?, targetLanguage: String) -> String {
        let paragraphs: [String]
        if let scriptLanguage,
           LanguageCatalog.language(scriptLanguage)?.code != LanguageCatalog.language(targetLanguage)?.code,
           let native = CloneScriptStore.shared.script(for: scriptLanguage)
            ?? CloneScriptStore.handAuthored(scriptLanguage) {
            paragraphs = native
        } else {
            paragraphs = self.paragraphs(for: targetLanguage)
        }
        let text = paragraphs.first ?? ""
        guard text.count > 120 else { return text }
        let head = text.prefix(160)
        if let stop = head.lastIndex(where: { ".?!。？！".contains($0) }),
           head.distance(from: head.startIndex, to: stop) > 40 {
            return String(head[...stop])
        }
        return String(text.prefix(120))
    }

    private static let byLanguage: [String: [String]] = [
        "en": [
            "Hi. I'm recording this so my fluent self can sound like me. I'm curious. I'm patient. I want to sound like me — just a more confident version.",
            "Let me describe a moment from this week. The weather turned cooler than I expected. I was walking and caught myself thinking in two languages at once — one for what I saw, one for what I felt. Funny how that works.",
            "Here's a quick list, just to stretch the sounds: Monday morning, Wednesday afternoon, Friday night. Three, thirteen, thirty-three. A double espresso, a glass of water, and a window seat if you have one, please.",
            "Now a few different shapes: \"Could you actually repeat that?\" \"Wait — that's not quite right.\" \"Honestly, I'm not sure yet, but here's what I think.\" \"Oh, that's brilliant — say more.\"",
            "One more, a little slower this time. When I speak this language a year from now, I want it to feel easy. Not perfect — easy. Like I'm not translating anymore, just talking.",
            "Okay. I think that's enough of my voice for now. If this worked, the next voice you hear should sound a lot like me. Talk to me soon.",
        ],
        "de": [
            "Hallo. Ich nehme das auf, damit mein fließendes Ich wie ich klingen kann. Ich bin neugierig. Ich bin geduldig. Ich möchte nach mir klingen — nur nach einer selbstsichereren Version.",
            "Ich beschreibe kurz einen Moment aus dieser Woche. Das Wetter wurde kühler, als ich erwartet hatte. Ich ging spazieren und ertappte mich dabei, wie ich in zwei Sprachen gleichzeitig dachte — eine für das, was ich sah, eine für das, was ich fühlte. Komisch, wie das funktioniert.",
            "Hier eine kurze Liste, nur um die Laute zu dehnen: Montagmorgen, Mittwochnachmittag, Freitagabend. Drei, dreizehn, dreiunddreißig. Einen doppelten Espresso, ein Glas Wasser und einen Platz am Fenster, wenn Sie einen haben, bitte.",
            "Jetzt ein paar andere Formen: „Könnten Sie das bitte wiederholen?\" „Moment — das stimmt nicht ganz.\" „Ehrlich gesagt bin ich mir noch nicht sicher, aber ich denke Folgendes.\" „Oh, das ist großartig — erzähl mehr.\"",
            "Noch einmal, diesmal etwas langsamer. Wenn ich diese Sprache in einem Jahr spreche, soll sie sich leicht anfühlen. Nicht perfekt — leicht. Als würde ich nicht mehr übersetzen, sondern einfach reden.",
            "Gut. Ich glaube, das reicht erst mal von meiner Stimme. Wenn das geklappt hat, sollte die nächste Stimme, die du hörst, ziemlich nach mir klingen. Bis gleich.",
        ],
        "ko": [
            "안녕하세요. 유창한 제 목소리가 저처럼 들리도록 이걸 녹음하고 있어요. 저는 호기심이 많아요. 참을성도 있고요. 저처럼 들리면 좋겠어요 — 조금 더 자신 있는 버전으로요.",
            "이번 주에 있었던 순간을 하나 이야기해 볼게요. 날씨가 생각보다 쌀쌀해졌어요. 걷다가 문득 두 가지 언어로 동시에 생각하고 있는 저를 발견했어요. 하나는 눈에 보이는 것들을 위해, 하나는 마음에 느껴지는 것들을 위해서요. 참 신기하죠.",
            "소리를 골고루 내보려고 간단한 목록을 읽어볼게요. 월요일 아침, 수요일 오후, 금요일 밤. 셋, 열셋, 서른셋. 에스프레소 더블 한 잔, 물 한 잔, 그리고 창가 자리가 있으면 부탁드려요.",
            "이번엔 결이 다른 문장들이에요. \"다시 한번 말씀해 주시겠어요?\" \"잠깐만요 — 그건 좀 아닌 것 같아요.\" \"솔직히 아직 잘 모르겠지만, 제 생각은 이래요.\" \"오, 그거 정말 좋네요 — 더 얘기해 주세요.\"",
            "하나만 더, 이번엔 조금 천천히요. 일 년 뒤에 제가 이 언어를 말할 때, 그게 편하게 느껴지면 좋겠어요. 완벽하지 않아도 돼요 — 그냥 편하게요. 더 이상 번역하지 않고, 그저 말하는 것처럼요.",
            "좋아요. 제 목소리는 이 정도면 충분한 것 같네요. 잘 됐다면, 다음에 들리는 목소리는 저와 꽤 비슷할 거예요. 곧 얘기해요.",
        ],
        "ja": [
            "こんにちは。流暢な自分が私らしく聞こえるように、これを録音しています。私は好奇心があります。忍耐強くもあります。自分らしく聞こえてほしいんです — ただ、もう少し自信のあるバージョンで。",
            "今週あった出来事を少し話してみますね。天気が思ったより涼しくなりました。歩いていて、ふと二つの言葉で同時に考えている自分に気づいたんです。一つは目に見えるもののため、もう一つは心に感じるもののため。不思議なものですね。",
            "音を広げるために、簡単なリストを読みます。月曜日の朝、水曜日の午後、金曜日の夜。三、十三、三十三。ダブルのエスプレッソ、お水を一杯、それと窓際の席が空いていればお願いします。",
            "今度は少し違う形の文です。「もう一度言っていただけますか。」「ちょっと待って — それは少し違う気がします。」「正直まだ分かりませんが、私はこう思います。」「へえ、それはすごいですね — もっと聞かせてください。」",
            "もう一つだけ、今度は少しゆっくり。一年後にこの言葉を話すとき、楽に感じられたらいいなと思います。完璧じゃなくていい — 楽であってほしい。もう翻訳していなくて、ただ話しているように。",
            "はい。私の声はこれくらいで十分だと思います。うまくいっていれば、次に聞こえる声はかなり私に似ているはずです。またすぐ話しましょう。",
        ],
        "es": [
            "Hola. Estoy grabando esto para que mi yo fluido pueda sonar como yo. Soy curioso. Soy paciente. Quiero sonar como yo — solo que en una versión más segura.",
            "Déjame describir un momento de esta semana. El tiempo se puso más fresco de lo que esperaba. Iba caminando y me sorprendí pensando en dos idiomas a la vez — uno para lo que veía, otro para lo que sentía. Es curioso cómo funciona eso.",
            "Aquí va una lista rápida, solo para estirar los sonidos: lunes por la mañana, miércoles por la tarde, viernes por la noche. Tres, trece, treinta y tres. Un espresso doble, un vaso de agua y una mesa junto a la ventana, si tienen, por favor.",
            "Ahora unas formas distintas: «¿Podrías repetir eso, por favor?» «Espera — eso no está del todo bien.» «La verdad, todavía no estoy seguro, pero esto es lo que pienso.» «Ah, qué bueno — cuéntame más.»",
            "Una más, esta vez un poco más despacio. Cuando hable este idioma dentro de un año, quiero que se sienta fácil. No perfecto — fácil. Como si ya no estuviera traduciendo, solo hablando.",
            "Bien. Creo que con eso basta de mi voz por ahora. Si esto funcionó, la próxima voz que oigas debería parecerse bastante a la mía. Hablamos pronto.",
        ],
        "fr": [
            "Bonjour. J'enregistre ceci pour que mon moi qui parle couramment puisse sonner comme moi. Je suis curieux. Je suis patient. Je veux sonner comme moi — juste une version plus sûre d'elle-même.",
            "Laisse-moi décrire un moment de cette semaine. Le temps s'est rafraîchi plus que je ne l'attendais. Je marchais et je me suis surpris à penser dans deux langues à la fois — une pour ce que je voyais, une pour ce que je ressentais. C'est drôle, non ?",
            "Voici une petite liste, juste pour étirer les sons : lundi matin, mercredi après-midi, vendredi soir. Trois, treize, trente-trois. Un double espresso, un verre d'eau, et une place près de la fenêtre si vous en avez une, s'il vous plaît.",
            "Maintenant quelques formes différentes : « Pourriez-vous répéter, s'il vous plaît ? » « Attends — ce n'est pas tout à fait ça. » « Honnêtement, je ne suis pas encore sûr, mais voilà ce que j'en pense. » « Ah, c'est génial — raconte-moi. »",
            "Encore une, un peu plus lentement cette fois. Quand je parlerai cette langue dans un an, je veux que ce soit facile. Pas parfait — facile. Comme si je ne traduisais plus, comme si je parlais, tout simplement.",
            "Voilà. Je crois que ça suffit pour ma voix. Si ça a marché, la prochaine voix que tu entendras devrait beaucoup me ressembler. À très vite.",
        ],
        "it": [
            "Ciao. Sto registrando questo perché il mio io fluente possa suonare come me. Sono curioso. Sono paziente. Voglio suonare come me — solo in una versione più sicura.",
            "Ti descrivo un momento di questa settimana. Il tempo si è fatto più fresco di quanto mi aspettassi. Camminavo e mi sono accorto di stare pensando in due lingue insieme — una per quello che vedevo, una per quello che sentivo. Strano come funziona.",
            "Ecco una lista veloce, solo per allargare i suoni: lunedì mattina, mercoledì pomeriggio, venerdì sera. Tre, tredici, trentatré. Un espresso doppio, un bicchiere d'acqua e un posto vicino alla finestra, se ce l'avete, per favore.",
            "Ora qualche forma diversa: «Potresti ripetere, per favore?» «Aspetta — non è proprio così.» «Sinceramente non sono ancora sicuro, ma ecco cosa penso.» «Oh, che bello — raccontami di più.»",
            "Un'ultima, questa volta un po' più lentamente. Quando parlerò questa lingua tra un anno, voglio che mi venga facile. Non perfetta — facile. Come se non stessi più traducendo, ma solo parlando.",
            "Bene. Credo che della mia voce basti così. Se ha funzionato, la prossima voce che sentirai dovrebbe assomigliarmi parecchio. A presto.",
        ],
        "pt": [
            "Oi. Estou gravando isto para que o meu eu fluente possa soar como eu. Sou curioso. Sou paciente. Quero soar como eu — só que numa versão mais confiante.",
            "Deixa eu descrever um momento desta semana. O tempo ficou mais frio do que eu esperava. Eu estava caminhando e me peguei pensando em duas línguas ao mesmo tempo — uma para o que eu via, outra para o que eu sentia. Engraçado como isso acontece.",
            "Aqui vai uma lista rápida, só para esticar os sons: segunda de manhã, quarta à tarde, sexta à noite. Três, treze, trinta e três. Um espresso duplo, um copo d'água e uma mesa perto da janela, se tiver, por favor.",
            "Agora algumas formas diferentes: “Você poderia repetir, por favor?” “Espera — isso não está bem certo.” “Sinceramente, ainda não tenho certeza, mas é isso que eu acho.” “Ah, que ótimo — me conta mais.”",
            "Mais uma, dessa vez um pouco mais devagar. Quando eu falar esta língua daqui a um ano, quero que pareça fácil. Não perfeito — fácil. Como se eu não estivesse mais traduzindo, só conversando.",
            "Pronto. Acho que já basta da minha voz por enquanto. Se isso funcionou, a próxima voz que você ouvir deve se parecer bastante comigo. Até logo.",
        ],
        "zh": [
            "你好。我正在录这段话，好让流利的我听起来像我自己。我很好奇，也很有耐心。我希望它听起来像我 — 只是更自信的那个版本。",
            "我来说说这周的一个片刻。天气比我预想的要凉。我走在路上，忽然发现自己在同时用两种语言思考 — 一种用来描述看见的，一种用来描述感受到的。挺有意思的。",
            "我读一个简单的清单，把各种音都带一带：周一早上，周三下午，周五晚上。三，十三，三十三。一杯双份浓缩，一杯水，如果有靠窗的位子，麻烦给我留一个。",
            "现在换几种不同的语气：「可以再说一遍吗？」「等一下 — 好像不太对。」「老实说我还不确定，不过我是这么想的。」「哦，这个真好 — 再多讲一点。」",
            "再来一段，这次慢一点。等一年以后我说这门语言的时候，我希望它是轻松的。不用完美 — 轻松就好。就像我不再翻译了，只是在说话。",
            "好了。我的声音大概就录到这里。如果一切顺利，你接下来听到的声音应该会很像我。我们很快再聊。",
        ],
    ]

    private static let greetings: [String: String] = [
        "en": "Hey — it's you. Just more fluent. Pick a color that feels like us.",
        "de": "Hey — das bist du. Nur fließender. Such dir eine Farbe aus, die zu uns passt.",
        "ko": "안녕 — 너야. 조금 더 유창한. 우리한테 어울리는 색을 골라봐.",
        "ja": "やあ — 君だよ。ただ、もっと流暢な。僕たちらしい色を選んでみて。",
        "es": "Oye — eres tú. Solo que más fluido. Elige un color que nos represente.",
        "fr": "Salut — c'est toi. En plus fluide. Choisis une couleur qui nous ressemble.",
        "it": "Ehi — sei tu. Solo più fluente. Scegli un colore che ci somigli.",
        "pt": "Ei — é você. Só que mais fluente. Escolha uma cor com a nossa cara.",
        "zh": "嘿 — 是你。只是更流利了。挑一个像我们的颜色吧。",
    ]
}
