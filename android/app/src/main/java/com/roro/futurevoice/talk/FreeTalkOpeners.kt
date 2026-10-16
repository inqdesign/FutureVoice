package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.CefrLevel

/**
 * How a no-topic free talk picks up (iOS `FreeTalkOpeners`, `a9a80ed7`): one
 * light hello per language and part of the day, chosen at the moment of the
 * call ("안녕, 잘 잤어?" · "안녕, 지금 뭐해?" · "안녕, 오늘은 어땠어?" ·
 * "안녕, 아직 안 자?"), plus the first-call introduction ([introOpener]). The
 * texts repeat verbatim, so the phrase cache makes every TTS after a line's
 * first play free. Until 2026-10-13 a Gemini call wrote a rotating pool of
 * six per learner (`freetalk_openers_by_language.json`, no longer read).
 */
class FreeTalkOpeners(private val context: Context) {

    companion object {
        private const val BAKED_SPEED_KEY = "futurevoice.freeTalkOpeners.bakedSpeed"
        private const val BAKED_LINES_KEY = "futurevoice.freeTalkOpeners.bakedLines"
        private const val CARTESIA_WHOLE_KEY = "futurevoice.freeTalkOpeners.cartesiaWhole"
        private const val TAG = "FreeTalkOpeners"

        /** iOS `FreeTalkOpeners.warmAhead` — one since 2026-10-09: the
         *  launcher re-warms after every call, so a spare was rarely played. */
        const val WARM_AHEAD = 1

        /** Failures only — one row each, never a success, so the volume is
         *  the number of things that went wrong (iOS `report`). */
        private fun report(event: String, language: String?, error: Throwable) {
            if (error is kotlinx.coroutines.CancellationException) return
            val reason = error.toString().take(200)
            android.util.Log.w(TAG, "$event: $reason")
            com.roro.futurevoice.core.Telemetry.log(
                event, buildMap { put("error", reason); language?.let { put("language", it) } })
        }

        fun introOpener(language: String): String =
            FreeTalkOpenerContent.intro[language.take(2)] ?: FreeTalkOpenerContent.intro.getValue("en")

        /** The hello a free talk placed at [at] opens on (iOS `pickUpLine`):
         *  the part of the day is `PromptClock.partOfDay`, the same split the
         *  call's own prompt is told. */
        fun pickUpOpener(language: String, at: Long = System.currentTimeMillis()): String {
            val lines = FreeTalkOpenerContent.pickUp[language.take(2)] ?: FreeTalkOpenerContent.pickUp.getValue("en")
            val hour = java.time.Instant.ofEpochMilli(at).atZone(java.time.ZoneId.systemDefault()).hour
            return lines[PromptClock.partOfDay(hour)] ?: lines.getValue("afternoon")
        }
    }

    /**
     * The hello a call placed now opens on, then — when asked for more — the
     * next parts of the day's, so a warm-up just before a boundary still has
     * the following hello ready (iOS `upcomingLines`).
     */
    fun upcomingLines(language: String, count: Int = WARM_AHEAD): List<String> {
        val out = mutableListOf<String>()
        var at = System.currentTimeMillis()
        repeat(maxOf(0, count)) {
            val line = pickUpOpener(language, at)
            if (line !in out) out += line
            at += 5 * 3600 * 1000L
        }
        return out
    }

    /**
     * The first call's opener, ready before the tap (iOS `warmFirstCall`):
     * the INTRO line for a learner not yet met (it is what their call opens
     * on), otherwise the hello for the time of day. Cache-checked, so repeat
     * calls cost nothing.
     */
    suspend fun warmFirstCall(language: String, personaName: String?, level: CefrLevel,
                              voiceId: String?, firstMeeting: Boolean) {
        if (!voiceId.isNullOrBlank() && firstMeeting) {
            if (!warmLine(introOpener(language), voiceId)) return
        }
        // An unmet learner's first call opens on the intro, never the hello,
        // so its audio waits for the first call's own re-warm (iOS, 2026-10-09).
        if (firstMeeting) return
        warmAudio(language, personaName, voiceId)
    }

    /**
     * Synthesize the next [WARM_AHEAD] hellos that aren't cached yet, so the
     * call's FIRST word is already on the phone when the learner taps (iOS
     * `26a246c`). Called again after calls and on foreground, so the window
     * follows the clock. A failure aborts the sweep.
     */
    suspend fun warmAudio(language: String, personaName: String?, voiceId: String?) {
        if (voiceId.isNullOrBlank()) return
        for (line in upcomingLines(language)) {
            if (!warmLine(line, voiceId)) return
        }
    }

    /**
     * ONE line into the phrase cache — a no-op when it's already there at the
     * speed in force now. The lineage is deliberately NOT consulted, because a
     * greeting has to be in the CURRENT voice. False on failure.
     */
    private suspend fun warmLine(line: String, voiceId: String): Boolean {
        val store = com.roro.futurevoice.data.PhraseAudioStore.shared(context)
        // The ONE exception to "produced audio is kept": the lines that open
        // a call are re-made whenever the speed moves, or the greeting plays
        // at the old speed and every answer after it at the new one (iOS
        // `needsBake`, 2026-09-25).
        if (store.data(line, voiceId) != null && !needsBake(line, voiceId)) return true
        val audio = try {
            // Whole: a Cartesia line already pauses between its sentences.
            // Billed as "opener", not "turn" (iOS 2026-10-02): priced the
            // same, but a warm-up filed as "turn" read in the ledger as a
            // call's reply.
            com.roro.futurevoice.net.VoiceClient(com.roro.futurevoice.data.AuthRepository())
                .synthesize(voiceId = voiceId, text = line, purpose = "opener")
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            report("opener_audio_failed", null, e)
            return false   // no network, or a wall — try again later
        }
        store.save(audio, line, voiceId)
        markBaked(line)
        return true
    }

    private val bakePrefs get() = context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)

    private fun needsBake(line: String, voiceId: String): Boolean {
        // A Cartesia voice's openers made before 2026-10-13 were split
        // sentence by sentence (`PacedSpeech`): re-made whole, once.
        if (com.roro.futurevoice.net.VoiceClient.isCartesiaVoice(voiceId) && !bakePrefs.getBoolean(CARTESIA_WHOLE_KEY, false)) {
            bakePrefs.edit().putBoolean(CARTESIA_WHOLE_KEY, true).remove(BAKED_LINES_KEY).apply()
            return true
        }
        val current = com.roro.futurevoice.data.SpeechSpeed.currentMultiplier()?.toFloat() ?: return false
        val p = bakePrefs
        if (p.getFloat(BAKED_SPEED_KEY, Float.NaN) != current) {
            // The speed moved (or this build is the first to ask): every
            // line on file was made at some other speed.
            p.edit().putFloat(BAKED_SPEED_KEY, current).remove(BAKED_LINES_KEY).apply()
            return true
        }
        return line !in (p.getString(BAKED_LINES_KEY, null)?.split('\n').orEmpty())
    }

    private fun markBaked(line: String) {
        val lines = bakePrefs.getString(BAKED_LINES_KEY, null)?.split('\n').orEmpty().toMutableList()
        if (line in lines) return
        lines.add(line)
        bakePrefs.edit().putString(BAKED_LINES_KEY, lines.takeLast(60).joinToString("\n")).apply()
    }
}
