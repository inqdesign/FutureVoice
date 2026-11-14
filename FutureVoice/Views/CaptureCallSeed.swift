#if DEBUG
import Foundation

/// The app-language half of the staged screens the store screenshots are
/// taken from (`call-seed-fix`, `call-seed-coach`, `-shadowResult 1`). The
/// practiced lines are English; what explains them follows the app language,
/// so each language's screenshot reads like that learner's own screen.
enum CaptureCallSeed {
    struct Texts {
        let lesson: String
        let goals: [String]
        let reason: String
        let why: String
        let coachMeaning: String
        let shadowPronunciation: String
        let shadowPacing: String
        let shadowFix: String
    }

    static func texts(for language: String) -> Texts {
        let nb = "\u{00A0}"
        switch language {
        case let l where l.hasPrefix("ko"):
            return Texts(lesson: "면접 자기소개",
                         goals: ["지금 하는 일 소개하기", "지원한 이유 말하기", "내 강점이 일에 도움 되는 이유 말하기"],
                         reason: "'stay calm when … come up'이 더 자연스러워요. situation은 복수형으로 써요.",
                         why: "situation은 셀 수 있는 명사라 복수형이어야 해요",
                         coachMeaning: "요즘 [AI 프로젝트]를 하고 있는데, 아주 잘 되고 있어.",
                         shadowPronunciation: "'taking the time'에서 the가 빠졌어요. 세 단어를 한 덩어리로 이어 말해 보세요.",
                         shadowPacing: "속도는 원본과 거의 같아요. appreciate에 힘을 조금 더 주면 더 자연스러워요.",
                         shadowFix: "'taking the time'만 한 번 더 따라 해 보세요.")
        case let l where l.hasPrefix("ja"):
            return Texts(lesson: "面接の自己紹介",
                         goals: ["今の仕事を紹介する", "応募した理由を話す", "自分の強みが仕事に活きる理由を話す"],
                         reason: "「stay calm when … come up」のほうが自然です。situation は複数形にします。",
                         why: "situation は数えられる名詞なので複数形にします",
                         coachMeaning: "今[AIのプロジェクト]をやってて、すごく順調なんだ。",
                         shadowPronunciation: "「taking the time」の the が抜けました。3語をひとかたまりで言ってみましょう。",
                         shadowPacing: "スピードはお手本とほぼ同じです。appreciate をもう少し強く言うと自然です。",
                         shadowFix: "「taking the time」だけもう一度まねしてみましょう。")
        case "zh-Hans":
            return Texts(lesson: "面试自我介绍",
                         goals: ["介绍现在的工作", "说说为什么申请", "说说你的优势怎么帮到这份工作"],
                         reason: "用“stay calm when … come up”更自然，situation 要用复数。",
                         why: "situation 是可数名词，要用复数",
                         coachMeaning: "我现在在做[一个AI项目]，进展很顺利。",
                         shadowPronunciation: "“taking the time”里漏了 the。把这三个词连成一组说。",
                         shadowPacing: "语速和原音差不多。appreciate 再重一点会更自然。",
                         shadowFix: "再跟读一遍“taking the time”。")
        case let l where l.hasPrefix("zh"):
            return Texts(lesson: "面試自我介紹",
                         goals: ["介紹現在的工作", "說說為什麼應徵", "說說你的優勢怎麼幫上這份工作"],
                         reason: "用「stay calm when … come up」更自然，situation 要用複數。",
                         why: "situation 是可數名詞，要用複數",
                         coachMeaning: "我現在在做[一個AI專案]，進展很順利。",
                         shadowPronunciation: "「taking the time」裡漏了 the。把這三個字連成一組說。",
                         shadowPacing: "語速和原音差不多。appreciate 再重一點會更自然。",
                         shadowFix: "再跟讀一次「taking the time」。")
        case let l where l.hasPrefix("es"):
            return Texts(lesson: "Entrevista",
                         goals: ["Di a qué te dedicas", "Di por qué te postulaste", "Di cómo tus fortalezas encajan en el puesto"],
                         reason: "«Stay calm when… come up» suena más natural, y situation va en plural.",
                         why: "Situation es contable: va en plural.",
                         coachMeaning: "Ahora estoy con [un proyecto de IA] y va muy bien.",
                         shadowPronunciation: "Se te fue el «the» de «taking the time». Di las tres palabras de un tirón.",
                         shadowPacing: "Vas al mismo ritmo que el original. Marca un poco más «appreciate».",
                         shadowFix: "Repite solo «taking the time» una vez más.")
        case let l where l.hasPrefix("fr"):
            return Texts(lesson: "Entretien",
                         goals: ["Dire ce que tu fais", "Dire pourquoi tu postules", "Dire en quoi tes points forts collent au poste"],
                         reason: "«\(nb)Stay calm when… come up\(nb)» sonne plus naturel, et situation prend le pluriel.",
                         why: "Situation est dénombrable\(nb): il faut le pluriel.",
                         coachMeaning: "Je bosse sur [un projet d’IA] en ce moment, et ça avance super bien.",
                         shadowPronunciation: "Tu as oublié le «\(nb)the\(nb)» de «\(nb)taking the time\(nb)». Dis les trois mots d’un seul bloc.",
                         shadowPacing: "Ton rythme colle à l’original. Appuie un peu plus sur «\(nb)appreciate\(nb)».",
                         shadowFix: "Répète juste «\(nb)taking the time\(nb)» encore une fois.")
        case let l where l.hasPrefix("de"):
            return Texts(lesson: "Jobinterview",
                         goals: ["Sagen, was du machst", "Sagen, warum du dich bewirbst", "Sagen, warum deine Stärken passen"],
                         reason: "„Stay calm when … come up“ klingt natürlicher, und situation steht im Plural.",
                         why: "Situation ist zählbar, also Plural.",
                         coachMeaning: "Ich arbeite gerade an [einem KI-Projekt], und es läuft richtig gut.",
                         shadowPronunciation: "Bei „taking the time“ fehlt das „the“. Sag die drei Wörter in einem Zug.",
                         shadowPacing: "Dein Tempo passt zum Original. Betone „appreciate“ etwas stärker.",
                         shadowFix: "Sprich nur „taking the time“ noch einmal nach.")
        default:
            return Texts(lesson: "Job interview intro",
                         goals: ["Say what you do now", "Say why you applied", "Say how your strengths fit the job"],
                         reason: "\"Stay calm when … come up\" sounds more natural, and situation needs the plural.",
                         why: "Situation is countable, so it takes the plural.",
                         coachMeaning: "",
                         shadowPronunciation: "You dropped \"the\" in \"taking the time\". Say the three words as one chunk.",
                         shadowPacing: "Your pace matches the original. Lean a little more on \"appreciate\".",
                         shadowFix: "Shadow just \"taking the time\" once more.")
        }
    }
}
#endif
