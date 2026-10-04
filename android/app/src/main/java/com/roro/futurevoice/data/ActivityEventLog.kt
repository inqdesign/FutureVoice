package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * WHEN each practice rep happened — the routine's "what actually happened"
 * for everything that isn't a talk (a talk has its own start and end). iOS
 * `ActivityEventLog`. [PracticeLog] only counts reps per day, which says how
 * much but not at what time.
 *
 * Fed from the one door every rep walks through ([PracticeLog.record]), plus
 * "say it again" runs, logged when a run finishes. Device-local, pruned to
 * [KEEP_DAYS]; anything older is still counted in [PracticeLog], it just has
 * no time of day.
 */
object ActivityEventLog {

    @Serializable
    enum class Kind {
        @SerialName("drill") DRILL,
        @SerialName("shadow") SHADOW,
        @SerialName("word") WORD,
        @SerialName("expression") EXPRESSION,
        @SerialName("scene") SCENE,
        @SerialName("sayItAgain") SAY_IT_AGAIN;

        companion object {
            fun of(kind: PracticeLog.Kind): Kind = when (kind) {
                PracticeLog.Kind.DRILL -> DRILL
                PracticeLog.Kind.SHADOW -> SHADOW
                PracticeLog.Kind.WORD -> WORD
                PracticeLog.Kind.EXPRESSION -> EXPRESSION
                PracticeLog.Kind.SCENE -> SCENE
            }
        }
    }

    @Serializable
    data class Event(val kind: Kind, val at: Long)

    const val KEEP_DAYS = 60

    private val serializer = ListSerializer(Event.serializer())
    private var cache: List<Event>? = null

    private fun file(c: Context) = File(c.filesDir, "activity_events.json")

    @Synchronized
    private fun all(c: Context): List<Event> = cache ?: runCatching {
        file(c).takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(serializer, it) }
    }.getOrNull().orEmpty().also { cache = it }

    @Synchronized
    fun record(c: Context, kind: Kind, at: Long = System.currentTimeMillis()) {
        val cutoff = at - KEEP_DAYS * 86_400_000L
        val next = (all(c) + Event(kind, at)).filter { it.at >= cutoff }
        cache = next
        runCatching {
            val target = file(c)
            val tmp = File(target.parentFile, target.name + ".tmp")
            tmp.writeText(StoreJson.json.encodeToString(serializer, next))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }

    /** Events within `[start, end)`, oldest first. */
    fun events(c: Context, start: Long, end: Long): List<Event> =
        all(c).filter { it.at in start until end }.sortedBy { it.at }

    /** Capture/test seeding only. */
    @Synchronized
    fun replaceAll(c: Context, events: List<Event>) {
        cache = events
        runCatching { file(c).writeText(StoreJson.json.encodeToString(serializer, events)) }
    }
}
