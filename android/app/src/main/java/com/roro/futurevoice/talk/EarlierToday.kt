package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PronunciationEntry
import com.roro.futurevoice.data.PronunciationLedger
import com.roro.futurevoice.data.SessionStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * What the learner last did with the fluent self EARLIER TODAY — a talk, a
 * tutor lesson, a scene, or a pronunciation drill — as a record for prompts
 * (iOS `EarlierToday`, 98d7ff2a).
 *
 * Founder, 2026-11-04: "I call again the same morning and it says 'did you
 * sleep well?' again. A second call of the day should have more context."
 * The hello for the time of day only ever looked at the hour, so every
 * morning call was the first call of the morning. A friend rung twice in a
 * day picks up where you were, and that includes what you PRACTISED
 * together, since a lesson or a drill is time spent with them too.
 *
 * A talk WITH someone (a cast person, a stranger: `counterpartId`) is not
 * the fluent self's to pick up and is skipped. A pronunciation drill saves
 * no `Session` — its takes are in [PronunciationLedger] under `pron_call`,
 * and that is what is read here.
 *
 * The record is ENGLISH framing around the learner's own words, quoted as
 * said: it is context for a prompt, never material.
 */
data class EarlierToday(
    val kind: Kind,
    /** What is being picked up: the session's id, or `pron:<last take's id>`. */
    val key: String,
    /** When it ended (its last line, or its last take), epoch ms. */
    val endedAt: Long,
    val record: String,
) {
    enum class Kind { TALK, LESSON, SCENE, PRONUNCIATION }

    companion object {
        /** The surface [PronunciationLedger] files a pronunciation call's takes under. */
        const val PRON_SURFACE = "pron_call"
        /** Takes this close to the last one belong to the same drill. */
        const val DRILL_SPAN_MS = 45 * 60 * 1000L

        /** Read from the stores (disk — call off the main thread). */
        suspend fun current(context: Context, language: String, excluding: String? = null,
                    now: Long = System.currentTimeMillis()): EarlierToday? {
            val store = SessionStore.shared(context)
            val langs = (LanguageScope.enrolled(context) + language).distinct()
            val sessions = langs.flatMap { runCatching { store.load(it) }.getOrDefault(emptyList()) }
            val pron = runCatching { PronunciationLedger.shared(context).entries(language) }
                .getOrDefault(emptyList())
            return latest(now, sessions, pron, excluding)
        }

        fun latest(now: Long, sessions: List<Session>, pronEntries: List<PronunciationEntry>,
                   excluding: String? = null, zone: ZoneId = ZoneId.systemDefault()): EarlierToday? {
            val startOfToday = LocalDate.ofInstant(Instant.ofEpochMilli(now), zone)
                .atStartOfDay(zone).toInstant().toEpochMilli()
            // The same rule as `PromptClock.make`: a talk counts only if the
            // learner spoke in it, dated by its last line.
            val talk = sessions.mapNotNull { s ->
                if (s.id == excluding || s.counterpartId != null ||
                    s.turns.none { it.role == TurnRole.USER }) return@mapNotNull null
                val at = s.turns.maxOfOrNull { it.timestamp } ?: s.endedAt ?: s.startedAt
                if (at in startOfToday..now) s to at else null
            }.maxByOrNull { it.second }

            val takes = pronEntries.filter { it.surface == PRON_SURFACE && it.date in startOfToday..now }
            val lastTake = takes.maxByOrNull { it.date }

            if (lastTake != null && (talk == null || lastTake.date > talk.second)) {
                val drill = takes.filter { it.date >= lastTake.date - DRILL_SPAN_MS }
                return EarlierToday(Kind.PRONUNCIATION, "pron:${lastTake.id}", lastTake.date,
                    pronRecord(drill, lastTake.date, now, zone))
            }
            talk ?: return null
            return fromSession(talk.first, talk.second, now, zone)
        }

        private fun fromSession(s: Session, endedAt: Long, now: Long, zone: ZoneId): EarlierToday {
            val gap = PromptClock.gap(endedAt, now, zone)
            val kind: Kind
            var head: String
            val lesson = s.tutorLesson
            if (lesson != null) {
                kind = Kind.LESSON
                val progress = if (lesson.finished) "they finished it"
                    else "${lesson.done.size} of ${lesson.total} challenges cleared, not finished yet"
                head = "A tutor-mode lesson with you on \"${lesson.title}\" that ended $gap — $progress."
                val got = lesson.done.take(3).map { "\"${clip(it.line, 160)}\"" }
                if (got.isNotEmpty()) head += "\nLines they got right: " + got.joinToString(" · ")
            } else if (s.turns.any { it.tutorRole != null }) {
                kind = Kind.LESSON
                head = "A tutor-mode lesson with you that ended $gap."
            } else if (s.origin == SessionOrigin.SCENARIO) {
                kind = Kind.SCENE
                head = "A role-play scene, \"${s.displayTitle ?: "Conversation"}\", that ended $gap. You played a character in it, not yourself."
            } else {
                kind = Kind.TALK
                val about = s.topic?.trim()?.takeIf { it.isNotEmpty() }?.let { " about \"$it\"" } ?: ""
                head = "A talk$about that ended $gap."
            }
            val lines = lastLines(s.turns, if (kind == Kind.TALK) 10 else 6)
            val record = if (lines.isEmpty()) head else head + "\nIts last lines, oldest first:\n" + lines
            return EarlierToday(kind, s.id, endedAt, record)
        }

        /** The tail of a talk, newest kept when the budget runs out. */
        private fun lastLines(turns: List<Turn>, count: Int, budget: Int = 1400): String {
            val out = mutableListOf<String>()
            var used = 0
            for (t in turns.asReversed()) {
                val text = t.transcript.trim()
                if (text.isEmpty()) continue
                val line = "${if (t.role == TurnRole.USER) "them" else "you"}: \"${clip(text, 200)}\""
                if (used + line.length > budget || out.size >= count) break
                out += line
                used += line.length
            }
            return out.asReversed().joinToString("\n")
        }

        private fun pronRecord(drill: List<PronunciationEntry>, endedAt: Long, now: Long, zone: ZoneId): String {
            val gap = PromptClock.gap(endedAt, now, zone)
            // Lowest first; a word below 70 is one Azure did not hear clearly.
            val scores = mutableMapOf<String, MutableList<Int>>()
            for (e in drill) for (w in e.words) if (w.a < 70) scores.getOrPut(w.w.lowercase()) { mutableListOf() } += w.a
            val hard = scores.map { it.key to it.value.sum() / it.value.size }
                .sortedBy { it.second }.take(3).map { "\"${it.first}\"" }
            val n = drill.size
            var record = "A pronunciation drill with you that ended $gap (a reading drill, not counted as a talk): " +
                "they read ${if (n == 1) "1 sentence" else "$n sentences"} aloud and you told them which words weren't clear yet."
            record += if (hard.isEmpty()) " Every word came out clear."
                else " The words that still weren't clear: ${hard.joinToString(", ")}."
            return record
        }

        private fun clip(s: String, max: Int): String =
            if (s.length <= max) s else s.take(max - 1) + "…"
    }
}
