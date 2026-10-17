package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.Counterpart

/**
 * A preset id is a SLOT, voiced per target language (iOS `VoicePreset`,
 * `b49e91b`, 2026-09-28).
 *
 * The four presets ([StockPerson.catalog]) are American/British speakers, and
 * reading Korean they sounded like exactly that — every Korean scene partner
 * and stranger was an English speaker reading Korean. So what is STORED (on a
 * Counterpart, a Scenario, a public persona row, a built-in person) stays the
 * English id, and the voice that actually speaks is resolved from it at the
 * network edge, for the language being spoken: the TTS request, the
 * gateway `start`, and the phrase-audio cache key. Nothing stored changes, and
 * a person — shared by every target language — speaks natively in each one.
 *
 * Since 2026-10-12 (iOS `e9fcb2d`) every slot speaks from Cartesia's library
 * in en/de/ko/ja — a native speaker of each. Every id here is in both server
 * allowlists (gateway `PRESET_VOICE_IDS`, `tts`) — already deployed.
 */
object VoicePreset {

    private const val PAIGE = "NDTYOmYEjbDIVCKB35i3"
    private const val MARK = "UgBBYS2sOqTuMpoF3BR0"
    private const val EMMA = "FF59babHL8N8gfTgtBMT"
    private const val JAMES = "L0Dsvb3SLTyegXwtm47J"

    private val voicedBySlot: Map<String, Map<String, String>> = run {
        // Every selectable target language speaks from Cartesia's library
        // since 2026-10-12 (iOS `e9fcb2d`; the earlier provider's voices above
        // are now only the SLOT ids stored on people and scenarios). English
        // keeps the slots' American/British split.
        val english = mapOf(
            PAIGE to "999df508-4de5-40a7-8bd3-8c12f678c284",  // Paige → Layla (F, US)
            MARK to "c961b81c-a935-4c17-bfb3-ba2239de8c2f",   // Mark  → Kyle (M, US)
            EMMA to "e5d4c33a-d8f6-46e8-a10f-b5afecc35648",   // Emma  → Evie (F, GB)
            JAMES to "3d5ce2fb-e56c-42f0-9ed9-4662484063b4",  // James → Toby (M, GB)
        )
        val german = mapOf(
            PAIGE to "1ade29fc-6b82-4607-9e70-361720139b12",  // Lea (F)
            MARK to "dff81230-ff75-49a4-af44-f6b2f43500d8",   // Jonas (M)
            EMMA to "3f4ade23-6eb4-4279-ab05-6a144947c4d5",   // Karin (F)
            JAMES to "afa425cf-5489-4a09-8a3f-d3cb1f82150d",  // Nico (M)
        )
        val korean = mapOf(
            PAIGE to "cac92886-4b7c-4bc1-a524-e0f79c0381be",  // 시안 ← Yuna (F)
            MARK to "537a82ae-4926-4bfb-9aec-aff0b80a12a5",   // 민준 ← Minho (M)
            EMMA to "cd6c48a9-774b-4397-98b4-9948c0a790f0",   // 한별 ← Soojin (F)
            JAMES to "f7755efb-1848-4321-aa22-5e5be5d32486",  // 준호 ← Ryeowook (M)
        )
        val japanese = mapOf(
            PAIGE to "c7eafe22-8b71-40cd-850b-c5a3bbd8f8d2",  // 美咲 ← Emi (F)
            MARK to "b8e1169c-f16a-4064-a6e0-95054169e553",   // 翔太 ← Takashi (M)
            EMMA to "7be83d14-4707-43ad-9774-e24eb38320f0",   // 陽菜 ← Rin (F)
            JAMES to "6b92f628-be90-497c-8f4c-3b035002df71",  // 健太 ← Kenji (M)
        )
        // Spanish (2026-10-15): the four Spanish voices Find people already
        // casts for Spanish-speaking profiles (`ProfileVoice`), slot for slot
        // by gender. Not yet listened to as scene partners.
        val spanish = mapOf(
            PAIGE to "3797b3c0-ab71-40dc-bfa0-a8c6ff9c1e8b",  // Carolina (F)
            MARK to "7b001dff-b8b2-4da7-92e4-5c794798effa",   // Jorge (M)
            EMMA to "727f663b-0e90-4031-90f2-558b7334425b",   // Carmen (F)
            JAMES to "e9f0368b-3662-4a01-b037-e13ca5203c74",  // Javier (M)
        )
        mapOf("en" to english, "de" to german, "ko" to korean, "ja" to japanese, "es" to spanish)
    }

    /**
     * Where a slot speaks in another language's own voice it goes by a name
     * from that language too — a Korean speaker introduced as "Paige" reads
     * as a mistake. MATERIAL, so the TARGET language (the name is said in
     * scenes), never the app language.
     */
    private val localNames: Map<String, Map<String, String>> = mapOf(
        "de" to mapOf(PAIGE to "Lea", MARK to "Jonas", EMMA to "Karin", JAMES to "Nico"),
        "ko" to mapOf(PAIGE to "시안", MARK to "민준", EMMA to "한별", JAMES to "준호"),
        "ja" to mapOf(PAIGE to "美咲", MARK to "翔太", EMMA to "陽菜", JAMES to "健太"),
        "es" to mapOf(PAIGE to "Carolina", MARK to "Jorge", EMMA to "Carmen", JAMES to "Javier"),
    )

    @Volatile private var appContext: Context? = null
    fun init(context: Context) { appContext = context.applicationContext }

    private fun key(language: String) = language.substringBefore('-')

    /** The voice that speaks a stored voice id in [language]. Anything that
     *  isn't a preset slot — the learner's clone, a retired id — passes
     *  through untouched. */
    fun speaking(voiceId: String, language: String): String =
        voicedBySlot[key(language)]?.get(voiceId) ?: voiceId

    /** Same, for the language being practised right now. Every synthesis
     *  runs in the active target language (scenes, strangers and books are
     *  all per-language), which is why the network layer can resolve alone. */
    fun speaking(voiceId: String): String = speaking(voiceId, activeLanguage())

    /** True when [voiceId] is spoken by someone else in [language]. */
    fun isRevoiced(voiceId: String, language: String): Boolean =
        speaking(voiceId, language) != voiceId

    /** The slot's name in [language], or [englishName] where it keeps the
     *  English voice. */
    fun name(voiceId: String, englishName: String, language: String): String =
        localNames[key(language)]?.get(voiceId) ?: englishName

    /**
     * A Cartesia library voice (a UUID): a Find-people person's own voice or a
     * learner's public-profile voice (iOS `VoicePreset.isLibraryVoice`,
     * 2026-10-12). It speaks as itself in every language, has no preset name,
     * and the servers allow it because Cartesia publishes it to everyone.
     */
    fun isLibraryVoice(id: String?): Boolean =
        id != null && LIBRARY_VOICE.matches(id)
    private val LIBRARY_VOICE =
        Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    /** The preset person this id names, or null for anything else (a library
     *  voice) — iOS `VoicePreset.known(id:)`. */
    fun known(id: String?): StockPerson? = StockPerson.catalog.firstOrNull { it.voiceId == id }
    /** One of the four preset SLOTS (iOS `VoicePreset.catalog`). Shared by
     *  every learner, so never deleted, never anyone's own voice. */
    fun isPreset(id: String?): Boolean = id != null && StockPerson.catalog.any { it.voiceId == id }

    /**
     * The picker's caption (iOS `VoicePreset.caption(in:)`). The accent and
     * description are the ENGLISH voice's, so a slot voiced by someone else
     * in [language] shows only what is still true of it: the gender. Drawn
     * in the APP language (2026-10-10, iOS `3205350`): it is chrome describing
     * the voice, while the name and the sample follow the language practised.
     */
    fun caption(context: Context, voiceId: String, language: String): String {
        val male = voiceId == MARK || voiceId == JAMES
        val gender = context.getString(if (male) com.roro.futurevoice.R.string.voicepreset_male
            else com.roro.futurevoice.R.string.voicepreset_female)
        if (isRevoiced(voiceId, language) && !language.startsWith("en")) return gender
        val accent = context.getString(if (voiceId == EMMA || voiceId == JAMES)
            com.roro.futurevoice.R.string.voicepreset_british else com.roro.futurevoice.R.string.voicepreset_american)
        val description = when (voiceId) {
            PAIGE -> context.getString(com.roro.futurevoice.R.string.voicepreset_paige)
            MARK -> context.getString(com.roro.futurevoice.R.string.voicepreset_mark)
            EMMA -> context.getString(com.roro.futurevoice.R.string.voicepreset_emma)
            JAMES -> context.getString(com.roro.futurevoice.R.string.voicepreset_james)
            else -> ""
        }
        return "$gender · $accent · $description"
    }

    /**
     * The preview clip for a preset voice in a target language (iOS
     * `VoicePresetPickerView.previewAudio`, `bd87569`). The clips SHIP with
     * the app (`assets/voice_previews`, the same files iOS bundles, made by
     * `scripts/bundle-voice-previews.sh`): the line and the voice are the
     * same for everyone, so synthesizing them per learner paid for the same
     * few seconds over and over. A clip the bundle lacks falls back to the
     * phone's cache, then to one live synthesis kept in that cache.
     */
    suspend fun previewAudio(context: Context, voiceId: String, language: String): ByteArray {
        val lang = language.substringBefore('-')
        runCatching {
            context.assets.open("voice_previews/preview-$lang-$voiceId.mp3").use { it.readBytes() }
        }.getOrNull()?.let { return it }
        // The voice speaking NOW — never a take an older voice of this slot
        // made before it got a native one.
        return com.roro.futurevoice.data.cachedSynthesis(context, voiceId = voiceId,
            text = previewLine(language), purpose = "voice_preview", allowLineage = false)
    }

    /** One neutral greeting per target language — phrasings that avoid
     *  speaker-gender agreement so any voice can say them (iOS `previewLine`).
     *  The `<break>` is the pause tag: measured on the Korean line, the
     *  period after 반가워요 gave NO pause at all. It is spoken as silence,
     *  never read out; this line is audio only, never drawn as text. */
    fun previewLine(code: String): String = when (code.substringBefore("-")) {
        "es" -> "¡Hola! Qué alegría verte. <break time=\"0.5s\" /> ¿Empezamos?"
        "de" -> "Hallo! Schön, dich zu sehen. <break time=\"0.5s\" /> Sollen wir anfangen?"
        "fr" -> "Bonjour ! Ça me fait plaisir de te voir. <break time=\"0.5s\" /> On commence ?"
        "it" -> "Ciao! Che bello vederti. <break time=\"0.5s\" /> Iniziamo?"
        "pt" -> "Oi! Que bom te ver. <break time=\"0.5s\" /> Vamos começar?"
        "ja" -> "こんにちは！会えてうれしいです。<break time=\"0.5s\" />始めましょうか？"
        "ko" -> "안녕하세요! 만나서 반가워요. <break time=\"0.5s\" /> 시작해 볼까요?"
        "zh" -> "你好！很高兴见到你。<break time=\"0.5s\" />我们开始吧？"
        else -> "Hi! It's good to see you. <break time=\"0.5s\" /> Shall we get started?"
    }

    /** Me → Voice → "Scene partner voice": who plays a Watch scene with no
     *  saved person (iOS `VoicePreset.sceneDefault`, same defaults key).
     *  Null until the learner picks — then the first person, as before. */
    const val SCENE_DEFAULT_KEY = "futurevoice.defaultSceneVoice"
    fun sceneDefaultId(): String? =
        appContext?.getSharedPreferences("futurevoice", 0)?.getString(SCENE_DEFAULT_KEY, null)

    fun activeLanguage(): String =
        appContext?.let { com.roro.futurevoice.data.LanguageScope.active(it) } ?: "en"

    /**
     * A built-in person's saved row, named for [language]. The row is saved
     * the first time the person is picked, under whatever name they had
     * then, and one row serves every target language, so the name and the
     * scene identity are rewritten on read (`CounterpartStore.load`). Any
     * other row passes through untouched.
     */
    fun localized(c: Counterpart, language: String): Counterpart {
        val rid = c.remoteId ?: return c
        if (!rid.startsWith("builtin:")) return c
        val stock = StockPerson.catalog.firstOrNull { "builtin:${it.voiceId}" == rid } ?: return c
        return c.copy(name = stock.nameIn(language), intro = stock.identityIn(language))
    }
}

/** The built-in person's name in [language] (시안 in Korean, Paige in English). */
fun StockPerson.nameIn(language: String): String = VoicePreset.name(voiceId, name, language)

/**
 * The scene identity in [language]. It names the ENGLISH voice's nationality
 * ("Paige — American, …"); where the slot speaks in another native voice that
 * would cast an American speaking Korean, so the nationality is dropped and
 * the name is the one this language gives the slot.
 */
fun StockPerson.identityIn(language: String): String {
    if (!VoicePreset.isRevoiced(voiceId, language) || language.startsWith("en")) return identity
    val rest = identity.replace(Regex("(American|British), "), "")
    if (!rest.startsWith(name)) return rest
    return nameIn(language) + rest.drop(name.length)
}
