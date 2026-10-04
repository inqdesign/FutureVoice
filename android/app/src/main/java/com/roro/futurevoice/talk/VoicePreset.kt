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
 * network edge, for the language being spoken: the ElevenLabs request, the
 * gateway `start`, and the phrase-audio cache key. Nothing stored changes, and
 * a person — shared by every target language — speaks natively in each one.
 *
 * Korean voices picked by ear by the founder; Japanese uses the same four;
 * German and English keep the originals. Every id here is in both server
 * allowlists (gateway `PRESET_VOICE_IDS`, `elevenlabs-tts`) — already deployed.
 */
object VoicePreset {

    private const val PAIGE = "NDTYOmYEjbDIVCKB35i3"
    private const val MARK = "UgBBYS2sOqTuMpoF3BR0"
    private const val EMMA = "FF59babHL8N8gfTgtBMT"
    private const val JAMES = "L0Dsvb3SLTyegXwtm47J"

    private val voicedBySlot: Map<String, Map<String, String>> = run {
        val korean = mapOf(
            PAIGE to "5n5gqmaQi9Ewevrz7bOS",  // Paige → Sian (F)
            MARK to "L4az9Gb378GIycFl2nAB",   // Mark  → "KO - Calm, Friendly, Warm" (M)
            EMMA to "8jHHF8rMqMlg8if2mOUe",   // Emma  → Han (F)
            JAMES to "AKF7f2y1L8ktV5vxXILw",  // James → Joon (M)
        )
        mapOf("ko" to korean, "ja" to korean)
    }

    /**
     * Where a slot speaks in another language's own voice it goes by a name
     * from that language too — a Korean speaker introduced as "Paige" reads
     * as a mistake. MATERIAL, so the TARGET language (the name is said in
     * scenes), never the app language.
     */
    private val localNames: Map<String, Map<String, String>> = mapOf(
        "ko" to mapOf(PAIGE to "시안", MARK to "민준", EMMA to "한별", JAMES to "준호"),
        "ja" to mapOf(PAIGE to "美咲", MARK to "翔太", EMMA to "陽菜", JAMES to "健太"),
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
    if (!VoicePreset.isRevoiced(voiceId, language)) return identity
    val rest = identity.replace(Regex("(American|British), "), "")
    if (!rest.startsWith(name)) return rest
    return nameIn(language) + rest.drop(name.length)
}

/** The picker's caption — everything after the name, capitalized. */
fun StockPerson.captionIn(language: String): String =
    identityIn(language).substringAfter("— ").replaceFirstChar { it.uppercase() }
