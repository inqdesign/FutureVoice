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

    /** The file for the voice that actually SPEAKS this id — a preset slot
     *  resolves to the target language's own voice (`VoicePreset.speaking`). */
    private fun file(voiceId: String, text: String): File =
        rawFile(com.roro.futurevoice.talk.VoicePreset.speaking(voiceId), text)

    /**
     * Keys to try, in order: the voice that actually speaks first, then the
     * learner's older clones (only when the asked-for voice IS their own).
     *
     * A preset SLOT resolves to the target language's own voice (iOS
     * `b49e91b`), and new lines are saved under that voice. Lines made before
     * then were saved under the slot id in the old English voice; they stay
     * reachable as the fallback — produced audio is never orphaned, and a
     * scene already watched replays as it was instead of re-billing.
     * `allowLineage = false` turns this off too, for anything that must be
     * heard in the voice speaking NOW (a preview, a call's opener).
     */
    private fun candidates(voiceId: String, allowLineage: Boolean, text: String): List<File> {
        val speaking = com.roro.futurevoice.talk.VoicePreset.speaking(voiceId)
        if (!allowLineage) return listOf(rawFile(speaking, text))
        if (speaking != voiceId) return listOf(rawFile(speaking, text), rawFile(voiceId, text))
        val lineage = ownVoiceLineage
        if (voiceId !in lineage) return listOf(rawFile(voiceId, text))
        return listOf(rawFile(voiceId, text)) + lineage.filter { it != voiceId }.map { rawFile(it, text) }
    }

    /** The key for exactly this voice id, with no preset resolution. */
    private fun rawFile(voiceId: String, text: String): File {
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
    fun data(text: String, voiceId: String, allowLineage: Boolean = true): ByteArray? =
        existingFile(text, voiceId, allowLineage)?.readBytes()

    fun save(data: ByteArray, text: String, voiceId: String) {
        if (data.isEmpty()) return
        runCatching { file(voiceId, text).writeBytes(data) }
    }

    /** The audio file that answers for this line (own clone lineage
     *  included), or null — the timings beside it describe THAT take. */
    private fun existingFile(text: String, voiceId: String, allowLineage: Boolean = true): File? =
        candidates(voiceId, allowLineage, text).firstOrNull { it.exists() }

    /**
     * The word timings saved with this line's audio — ElevenLabs' measured
     * alignment, kept from the one synthesis that ever bills it (iOS
     * `<key>.timings.json`, same JSON, so a backup reads on either platform).
     * Null when the line was cached without them.
     */
    fun timings(text: String, voiceId: String): List<com.roro.futurevoice.talk.WordTiming>? {
        val audio = existingFile(text, voiceId) ?: return null
        val f = File(audio.parentFile, audio.nameWithoutExtension + ".timings.json")
        if (!f.exists()) return null
        return runCatching {
            StoreJson.json.decodeFromString(
                kotlinx.serialization.builtins.ListSerializer(com.roro.futurevoice.talk.WordTiming.serializer()),
                f.readText())
        }.getOrNull()
    }

    fun saveTimings(timings: List<com.roro.futurevoice.talk.WordTiming>, text: String, voiceId: String) {
        if (timings.isEmpty()) return
        val audio = existingFile(text, voiceId) ?: file(voiceId, text)
        runCatching {
            File(audio.parentFile, audio.nameWithoutExtension + ".timings.json").writeText(
                StoreJson.json.encodeToString(
                    kotlinx.serialization.builtins.ListSerializer(com.roro.futurevoice.talk.WordTiming.serializer()),
                    timings))
        }
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
