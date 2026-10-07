package com.roro.futurevoice.data

import android.content.Context

/**
 * What the clone is called, here and on ElevenLabs (iOS `voiceName` /
 * `voiceDisplayName` / `defaultVoiceName`, same defaults keys).
 *
 * The learner's own name if they set one, otherwise "Future <persona name>",
 * and — with no persona name yet — "Future Self (<token>)" with a stable
 * per-install token, so the voice library never fills with identical
 * "Future Self" entries. The default is DERIVED, never stored: storing it
 * would freeze it against a later persona rename.
 */
object VoiceName {
    private const val KEY = "futurevoice.voiceName"
    private const val TOKEN_KEY = "futurevoice.voiceNameToken"

    private fun prefs(context: Context) = context.getSharedPreferences("futurevoice", 0)

    fun custom(context: Context): String = prefs(context).getString(KEY, "")?.trim().orEmpty()

    fun default(context: Context, personaName: String?): String {
        val name = personaName?.trim().orEmpty()
        if (name.isNotEmpty()) return "Future $name"
        val p = prefs(context)
        val token = p.getString(TOKEN_KEY, null) ?: java.util.UUID.randomUUID().toString()
            .take(6).lowercase().also { p.edit().putString(TOKEN_KEY, it).apply() }
        return "Future Self ($token)"
    }

    fun display(context: Context, personaName: String?): String =
        custom(context).ifEmpty { default(context, personaName) }

    /** Saves locally FIRST (the name sticks even when upstream fails — it is
     *  applied on the next clone), then renames the live clone. Throws on an
     *  upstream failure so the caller can say the two are out of sync. */
    suspend fun rename(context: Context, draft: String, personaName: String?, voiceId: String?) {
        val trimmed = draft.trim()
        // Typing the unchanged default means "use the default".
        val next = if (trimmed == default(context, personaName)) "" else trimmed
        prefs(context).edit().putString(KEY, next).apply()
        voiceId ?: return
        com.roro.futurevoice.net.VoiceCloneClient(AuthRepository())
            .renameVoice(voiceId, display(context, personaName))
    }
}
