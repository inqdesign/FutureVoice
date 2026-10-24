package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.VoicePreset

/**
 * A preset the learner CHOSE for their fluent self over their own clone
 * (iOS `AppState.fluentSelfPresetId`, 2026-10-24, founder: some people don't
 * want to hear their own voice). The clone stays the app's `voiceId` — made,
 * owned and kept — so going back is one tap, and nothing that manages the
 * clone (restore, accent, parking, re-record) has to know about this.
 * Everything that SPEAKS as the fluent self reads [speaking]. Not the
 * stand-in: that is the app's preset while no clone can be made, this is the
 * learner's pick. Same defaults key as iOS.
 */
object FluentSelfVoice {
    const val KEY = "futurevoice.fluentSelfPreset"

    private fun prefs(context: Context) = context.getSharedPreferences("futurevoice", 0)

    /** The chosen preset, or null for the learner's own voice. Only a known
     *  preset id survives the read. */
    fun presetId(context: Context): String? =
        prefs(context).getString(KEY, null)?.takeIf { VoicePreset.isPreset(it) }

    fun set(context: Context, presetId: String?) {
        val id = presetId?.takeIf { VoicePreset.isPreset(it) }
        prefs(context).edit().apply { if (id == null) remove(KEY) else putString(KEY, id) }.apply()
    }

    /** The voice the fluent self speaks in, given the app's voice id (the
     *  clone, or the stand-in while the clone is queued): the chosen preset,
     *  else that voice. Null/blank in, unchanged out — no voice is no voice. */
    fun speaking(context: Context, cloneId: String?): String? {
        if (cloneId.isNullOrBlank()) return cloneId
        return presetId(context) ?: cloneId
    }

    /** iOS `Telemetry.callSettings()["voice"]`: preset · standin · own. */
    fun telemetryValue(context: Context): String = when {
        prefs(context).getString(KEY, null) != null -> "preset"
        prefs(context).getBoolean("futurevoice.voiceIsStandIn", false) -> "standin"
        else -> "own"
    }
}
