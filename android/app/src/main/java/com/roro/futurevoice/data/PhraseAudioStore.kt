package com.roro.futurevoice.data

import android.content.Context
import java.io.File
import java.security.MessageDigest

/**
 * On-disk cache for TTS audio keyed by `(voiceId, text)` — port of
 * `PhraseAudioStore.swift`, same folder name and same content-addressed
 * key, so a backup written on either platform resolves on the other.
 *
 * It exists for money, not speed. Without it every play of the same word
 * card, drill, shadow target or library line re-bills ElevenLabs for audio
 * the learner already owns — which is exactly what Android was doing on
 * every one of those surfaces.
 *
 * ## Re-recording your voice does NOT throw the old audio away
 *
 * The key includes the voice id, so a re-clone would miss on EVERY cached
 * line and silently re-synthesize the whole library one tap at a time. The
 * store therefore remembers the learner's OWN clone ids ([ownVoiceLineage],
 * newest first) and a lookup falls back through them before declaring a
 * miss. Counterpart preset voices are never in the lineage, so they can
 * never be substituted for one another.
 */
class PhraseAudioStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: PhraseAudioStore? = null
        fun shared(context: Context): PhraseAudioStore =
            instance ?: synchronized(this) {
                instance ?: PhraseAudioStore(context.applicationContext).also { instance = it }
            }

        private const val PREFS = "futurevoice"
        private const val LINEAGE_KEY = "futurevoice.ownVoiceLineage"

        /** How many past clones stay reachable. Someone who re-records often
         *  keeps their oldest material playable, without an unbounded list. */
        private const val MAX_LINEAGE = 6
    }

    private val appContext = context.applicationContext
    private val dir = File(appContext.filesDir, "PhraseAudio").apply { mkdirs() }

    /** The learner's own clone ids, newest first. The head is the live one. */
    val ownVoiceLineage: List<String>
        get() = appContext.getSharedPreferences(PREFS, 0)
            .getString(LINEAGE_KEY, "").orEmpty()
            .split("\n").filter { it.isNotBlank() }

    /** Record the current clone id — the previous one stays in the list so
     *  its audio keeps resolving. */
    fun registerOwnVoice(voiceId: String?) {
        if (voiceId.isNullOrBlank()) return
        val current = ownVoiceLineage
        if (current.firstOrNull() == voiceId) return
        val updated = (listOf(voiceId) + current.filterNot { it == voiceId }).take(MAX_LINEAGE)
        appContext.getSharedPreferences(PREFS, 0).edit()
            .putString(LINEAGE_KEY, updated.joinToString("\n")).apply()
    }

    private fun file(voiceId: String, text: String): File {
        val key = MessageDigest.getInstance("SHA-256")
            // The speed rung is part of the line: the same words at another
            // speed are another take. The default's tag is empty, so every
            // line cached before speeds existed is still found.
            .digest("$voiceId\n${SpeechSpeed.currentCacheTag()}${text.trim()}".toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(dir, "$key.mp3")
    }

    /** Cached audio for this line, or null. A line synthesized under an
     *  EARLIER clone of the learner's own voice still counts as a hit. */
    fun data(text: String, voiceId: String): ByteArray? {
        file(voiceId, text).takeIf { it.exists() }?.let { return it.readBytes() }
        if (voiceId !in ownVoiceLineage) return null
        for (past in ownVoiceLineage) {
            if (past == voiceId) continue
            file(past, text).takeIf { it.exists() }?.let { return it.readBytes() }
        }
        return null
    }

    fun save(data: ByteArray, text: String, voiceId: String) {
        if (data.isEmpty()) return
        runCatching { file(voiceId, text).writeBytes(data) }
    }

    /**
     * Account deletion / local wipe — the next learner inherits no lineage.
     * Scoped hard to this one folder: everything else in `filesDir` is the
     * learner's own record with no server copy, so a wider sweep would
     * destroy what they have done to clear an audio cache.
     */
    fun clearCachedAudio() {
        runCatching { dir.listFiles()?.forEach { it.delete() } }
        appContext.getSharedPreferences(PREFS, 0).edit().remove(LINEAGE_KEY).apply()
    }
}
