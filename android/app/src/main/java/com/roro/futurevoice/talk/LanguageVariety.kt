package com.roro.futurevoice.talk

import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.VoiceAccentCatalog

/**
 * iOS `VoiceAccentCatalog.writingVariety` + `ConversationEngine.varietyGuard`
 * (2026-10-20): the variety of the target language the learner's WORDS
 * follow, from the accent their voice speaks in. Picking British only
 * changed the sound; the model wrote American words in a British voice, and
 * could "fix" a learner's "flat" to "apartment". Empty for the language's
 * default accent and for no accent, so those prompts are byte-identical.
 */
object LanguageVariety {

    /** The voice's accent (`futurevoice.voiceAccentId`), mirrored by
     *  `AppViewModel` — the prompt builders have no Context. */
    @Volatile var accentId: String? = null

    data class Variety(val name: String, val examples: String, val others: String)

    private val varieties = mapOf(
        "en-GB" to Variety("British English",
            "flat, lift, mobile, queue, holiday, rubbish, colour, \"have got\"",
            "apartment, elevator, store, gotten, color"),
        "en-AU" to Variety("Australian English",
            "mobile, petrol, footpath, uni, holiday, colour, \"no worries\"",
            "apartment, cell phone, gas, gotten, color, flat, lift"),
        "es-ES" to Variety("Castilian Spanish as spoken in Spain",
            "vosotros for \"you all\", ordenador, coche, móvil, zumo, vale",
            "ustedes, computadora, carro, celular, jugo"),
    )

    fun writingVariety(language: String, accentId: String? = this.accentId): Variety? {
        val options = VoiceAccentCatalog.options(language)
        if (accentId == null || options.firstOrNull()?.id == accentId ||
            options.none { it.id == accentId }) return null
        return varieties[accentId]
    }

    fun guard(targetLanguage: String, accentId: String? = this.accentId): String {
        val variety = writingVariety(targetLanguage, accentId) ?: return ""
        val languageName = LanguageCatalog.englishName(targetLanguage)
        return "\n- LANGUAGE VARIETY: the learner speaks ${variety.name}, and their voice" +
            "\n  has that accent. Wherever YOU choose a word (your own lines, examples," +
            "\n  expressions, a word you add to a rewrite), choose the ${variety.name}" +
            "\n  one (${variety.examples}). The learner's OWN words are theirs: a word," +
            "\n  spelling or form from another variety of $languageName" +
            "\n  (${variety.others}) is NEVER a mistake. Never put it in \"fixes\", never" +
            "\n  swap it for the ${variety.name} word in a rewrite of their line, and" +
            "\n  never mention the difference."
    }
}
