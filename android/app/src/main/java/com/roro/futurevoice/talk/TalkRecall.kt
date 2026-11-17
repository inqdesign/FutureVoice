package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import java.time.ZoneId

/**
 * A free talk remembers the talks before it, and looks one up when it comes
 * up (iOS `TalkRecall.swift`, 27a08569; founder: "keep the memory somewhere
 * and take it out when it is needed").
 *
 * Every talk is on the phone, whole; what was missing is the fetch, and the
 * model cannot do it (the talks are on the phone, and a reply that stops to
 * search is a silence on a call). So the APP fetches: the prompt carries an
 * INDEX, one line per earlier talk (when, and its title), and after each
 * learner line the app asks whether it is about one of those talks
 * ([mayRecall] in code first, then one small model call). A hit puts that
 * talk's lines into the prompt (`set.system`). Nothing waits on it: the line
 * that first mentions the talk is answered from the index, the ones after it
 * from the talk itself. Probe: iOS `scripts/recall-probe.py` (63/66); the
 * prompt and the words are iOS's.
 */
object TalkRecall {

    /** One earlier talk with the fluent self. */
    data class Entry(val session: Session, val endedAt: Long) {
        val id: String get() = session.id
        val title: String get() = session.displayTitle ?: "Conversation"
    }

    /** How many talks the index lists. */
    const val INDEX_SIZE = 12
    /** How many looked-up talks a call's prompt holds at once. */
    const val HELD_AT_ONCE = 2

    /**
     * The talks worth remembering, newest first: with the fluent self (a talk
     * with a cast person is that person's), the learner spoke in it, and it
     * is not this call or the talk the prompt already carries whole
     * ([EarlierToday]).
     */
    fun index(sessions: List<Session>, now: Long, excluding: Set<String>): List<Entry> =
        sessions.mapNotNull { s ->
            if (s.id in excluding || s.counterpartId != null || s.origin == SessionOrigin.SCENARIO ||
                s.turns.none { it.role == TurnRole.USER && !it.excludedFromScoring }) return@mapNotNull null
            val at = s.turns.maxOfOrNull { it.timestamp } ?: s.endedAt ?: s.startedAt
            if (at <= now) Entry(s, at) else null
        }.sortedByDescending { it.endedAt }.take(INDEX_SIZE)

    /** The index as the prompt carries it. */
    fun indexLines(entries: List<Entry>, now: Long, zone: ZoneId = ZoneId.systemDefault()): List<String> =
        entries.map { "${PromptClock.gap(it.endedAt, now, zone)}: \"${clip(it.title, 90)}\"" }

    // ── Is this line about an earlier talk?

    /**
     * Worth asking the judge? A word that points at the past, or a word the
     * line shares with a title. Wide on purpose: a miss here is "I have no
     * record of that".
     */
    fun mayRecall(text: String, entries: List<Entry>, language: String): Boolean {
        if (entries.isEmpty()) return false
        val t = text.lowercase()
        if (CUES.any { t.contains(it) }) return true
        val said = words(t, language)
        return entries.any { e -> words(e.title.lowercase(), language).any { it in said } }
    }

    /** Words long enough to be about something. */
    private fun words(text: String, language: String): Set<String> =
        if (WordSplitter.spaced(language))
            CarryoverDetector.spendTokens(text, language).filter { it.length >= 5 }
                .map { CarryoverDetector.folded(it, language) }.toSet()
        else runCatching { WordSplitter.segments(text, language).filter { it.length >= 2 }.toSet() }
            .getOrDefault(emptySet())

    private val CUES = listOf(
        // en
        "yesterday", "last time", "last week", "last month", "the other day", "remember", "told you",
        "i said", "i mentioned", "we talked", "we spoke", "we discussed", "talked about", "earlier",
        "before", "again", "still ", "ago", "you know the", "you know my",
        // ko
        "어제", "그저께", "지난", "저번", "기억", "말했", "얘기했", "이야기했", "전에", "아까", "그때", "그 때",
        // ja
        "昨日", "おととい", "先週", "先月", "この前", "この間", "覚えて", "言った", "話した", "前に", "さっき", "あの時",
        // de
        "gestern", "vorgestern", "letzte", "letztes", "letzten", "neulich", "erinner", "erzählt", "gesagt",
        "gesprochen", "vorhin", "damals", "weißt du noch",
        // es
        "ayer", "anteayer", "pasada", "pasado", "el otro día", "recuerd", "acuerd", "te dije", "te conté",
        "hablamos", "antes", "otra vez", "todavía",
        // fr
        "hier", "dernier", "dernière", "l'autre jour", "souvien", "rappel", "je t'ai dit", "on a parlé",
        "raconté", "avant", "encore", "toujours",
        // zh
        "昨天", "前天", "上次", "上周", "上週", "上个月", "上個月", "记得", "記得", "说过", "說過", "提到",
        "之前", "那次",
    )

    const val SYSTEM =
        "A language learner is on a voice call with someone they talk to often. You get a numbered " +
        "list of earlier talks between the two (when each was, its title, and some of what the " +
        "learner said in it), then the last line said to the learner and the learner's newest line.\n" +
        "Decide whether the newest line is about something from ONE of the earlier talks: it brings " +
        "that talk up (\"the interview I told you about\"), carries on with its particular subject " +
        "(the same event, person, plan or problem), or asks what was said in it.\n" +
        "A general subject is not enough: two talks about work are not the same talk. A line about " +
        "today, or about something none of the listed talks holds, is none. When two talks fit, " +
        "take the more recent one.\n" +
        "Return {\"talk\": <number>} or {\"talk\": null}."

    fun content(entries: List<Entry>, lastReply: String, newest: String, now: Long,
                zone: ZoneId = ZoneId.systemDefault()): String {
        val list = entries.mapIndexed { i, e ->
            "${i + 1}. ${PromptClock.gap(e.endedAt, now, zone)} — \"${clip(e.title, 90)}\"\n   the learner said: ${gist(e.session)}"
        }.joinToString("\n")
        return "Earlier talks, newest first:\n$list\n\nLast line said to the learner: \"${clip(lastReply, 300)}\"\n" +
            "Newest line from the learner: \"${clip(newest, 400)}\""
    }

    /** Some of what the learner said in a talk, for the judge only. */
    fun gist(session: Session, budget: Int = 420): String {
        var out = ""
        for (turn in session.turns) {
            if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
            val text = turn.transcript.trim()
            if (text.isEmpty()) continue
            val piece = clip(text, 140)
            if (out.length + piece.length > budget) break
            out += (if (out.isEmpty()) "" else " / ") + piece
        }
        return "\"$out\""
    }

    @Serializable
    private data class Verdict(val talk: Int? = null)

    /** The earlier talk the newest line is about, or null. Free (`coach`). */
    suspend fun recalled(newest: String, lastReply: String, entries: List<Entry>, turnId: String,
                         now: Long = System.currentTimeMillis()): Entry? {
        if (entries.isEmpty()) return null
        val v = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = SYSTEM,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                        content(entries, lastReply, newest, now))),
                    serializer = Verdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 100, purpose = "coach",
                    idempotencyKey = "recall:$turnId", fastThinking = true,
                )
            }.getOrNull()
        }
        return v?.talk?.let { entries.getOrNull(it - 1) }
    }

    // ── The talk itself

    /**
     * The looked-up talk as the prompt carries it: when, its title, and its
     * lines around what the learner is talking about now.
     */
    fun record(entry: Entry, about: String, now: Long, language: String,
               zone: ZoneId = ZoneId.systemDefault(), count: Int = 24, budget: Int = 2400): String {
        val gap = PromptClock.gap(entry.endedAt, now, zone)
        // A line flagged as misheard was never theirs, and the reply after it
        // was built on it (`EarlierToday.lastLines`).
        val all = entry.session.turns
        val dropped = HashSet<String>()
        all.forEachIndexed { i, t ->
            if (t.role == TurnRole.USER && t.excludedFromScoring) {
                dropped += t.id
                all.getOrNull(i + 1)?.takeIf { it.role != TurnRole.USER }?.let { dropped += it.id }
            }
        }
        val turns = all.filter { it.id !in dropped && it.transcript.trim().isNotEmpty() }
        if (turns.isEmpty()) return "A talk you two had $gap, \"${clip(entry.title, 90)}\"."

        // Centre on the line that shares the most with what was just said.
        val asked = words(about.lowercase(), language)
        val scores = turns.map { t -> words(t.transcript.lowercase(), language).count { it in asked } }
        val best = scores.maxOrNull() ?: 0
        val centre = if (best > 0) scores.indexOf(best) else 0
        var lo = centre
        var hi = centre
        fun line(t: Turn) = "${if (t.role == TurnRole.USER) "them" else "you"}: \"${clip(t.transcript, 200)}\""
        var used = line(turns[centre]).length
        // Grow forward first: what came after the mention is what it led to.
        while (hi - lo + 1 < count) {
            val next = if (hi + 1 < turns.size) hi + 1 else null
            val prev = if (lo > 0) lo - 1 else null
            val pick = (if (hi - centre <= (centre - lo) * 2) next ?: prev else prev ?: next) ?: break
            val cost = line(turns[pick]).length
            if (used + cost > budget) break
            used += cost
            if (pick > hi) hi = pick else lo = pick
        }
        val whole = lo == 0 && hi == turns.size - 1
        val body = turns.subList(lo, hi + 1).joinToString("\n") { line(it) }
        return "A talk you two had $gap, \"${clip(entry.title, 90)}\".\n" +
            "${if (whole) "All of it" else "Part of it"}, oldest first:\n$body"
    }

    private fun clip(s: String, max: Int): String {
        val t = s.trim()
        return if (t.length <= max) t else t.take(max - 1) + "…"
    }
}
