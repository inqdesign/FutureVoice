package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.audio.VoicePitch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The gender a learner's sentences take, for the languages whose words
 * change with it (iOS `LearnerGender`, 2026-11-13, founder). French and
 * Spanish make the speaker agree with themselves ("je suis contente", "estoy
 * cansado"), and in this app the fluent self speaks AS the learner, so its
 * lines are lines the learner will say back (Say it again, shadowing, cards).
 * Every other target ignores it.
 *
 * Three answers, all equal: male, female, or prefer not to say, which keeps
 * the fluent self in wording that has no gender, the way natives rephrase
 * ("ça me fait plaisir" for "enchanté(e)"). Nothing asks for it. Two ways in:
 *   - **The learner's own recording** ([guessFromVoiceIfNeeded]): a median
 *     pitch clearly low or clearly high fills it in, marked as a guess. The
 *     band where voices overlap guesses nothing. NEVER the voice they PICKED
 *     (founder: a man may pick a female tutor voice), and nothing at all for
 *     a learner who chose the AI tutor without recording.
 *   - **Me → Profile**, where any answer they choose replaces the guess and
 *     is never guessed over again.
 */
enum class LearnerGender(val raw: String) {
    MALE("male"), FEMALE("female"), UNSAID("unsaid");

    enum class Source(val raw: String) { VOICE("voice"), CHOSEN("chosen") }

    companion object {
        const val VALUE_KEY = "futurevoice.learnerGender"
        const val SOURCE_KEY = "futurevoice.learnerGender.source"

        /** Below this a voice is guessed male, above [FEMALE_ABOVE_HZ] female.
         *  Adult ranges are roughly 85–180 Hz and 165–255 Hz; [VoicePitch]'s
         *  single 165 Hz cut is fine for offering a preset, where a wrong side
         *  costs nothing, and too sharp for saying who someone is. */
        const val MALE_BELOW_HZ = 150.0
        const val FEMALE_ABOVE_HZ = 185.0

        @Volatile private var appContext: Context? = null

        /** The prompt builders have no Context, so the store is reached
         *  through the application's (null in a JVM test: nothing on file). */
        fun init(context: Context) { appContext = context.applicationContext }

        private fun prefs(context: Context) = context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

        fun from(raw: String?): LearnerGender? = entries.firstOrNull { it.raw == raw }

        val current: LearnerGender? get() = appContext?.let { current(it) }

        fun current(context: Context): LearnerGender? = from(prefs(context).getString(VALUE_KEY, null))

        fun source(context: Context): Source? =
            prefs(context).getString(SOURCE_KEY, null)?.let { r -> Source.entries.firstOrNull { it.raw == r } }

        /** Languages whose sentences about the speaker change with it. */
        fun matters(language: String): Boolean = language.substringBefore('-') in setOf("fr", "es")

        fun set(context: Context, value: LearnerGender, source: Source) {
            prefs(context).edit()
                .putString(VALUE_KEY, value.raw)
                .putString(SOURCE_KEY, source.raw)
                .apply()
            com.roro.futurevoice.sync.SyncEngine.noteChanged()
        }

        /** The guess a median pitch allows, null in the overlap. */
        fun guess(fromPitch: Double): LearnerGender? = when {
            fromPitch < MALE_BELOW_HZ -> MALE
            fromPitch > FEMALE_ABOVE_HZ -> FEMALE
            else -> null
        }

        @Volatile private var guessing = false

        /** Fills in a guess from the learner's OWN recording, once: only for a
         *  target that needs it, only when nothing is on file, never for a
         *  tutor-only voice. Off the main thread (it reads 12 s of audio). */
        fun guessFromVoiceIfNeeded(context: Context, scope: CoroutineScope, target: String, tutorOnly: Boolean) {
            val app = context.applicationContext
            // The recording kept for rebuilding the clone (iOS `VoiceSampleStore`).
            val sample = com.roro.futurevoice.ui.VoiceComparison.sampleFile(app.filesDir)
            if (!matters(target) || current(app) != null || tutorOnly || guessing || !sample.exists()) return
            guessing = true
            scope.launch {
                val hz = withContext(Dispatchers.Default) { runCatching { VoicePitch.medianF0(sample) }.getOrNull() }
                guessing = false
                if (current(app) != null || hz == null) return@launch
                val value = guess(hz) ?: return@launch
                set(app, value, Source.VOICE)
            }
        }
    }
}
