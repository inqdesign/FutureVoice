package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.ui.TalkGoalItem
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/**
 * Coach mode (iOS `CoachMode.swift`, `ede039e` + `45b397e`, 1.1.4 `6e9eb92`): the call's
 * listening moment, used.
 *
 * The learner already studies words; the call is the only place they can be
 * spent, and the chip row above the transcript only waits for that to happen
 * by chance. Coach mode makes it happen on purpose — the fluent self may ask
 * something whose natural answer uses a word the learner is studying, and
 * while they think about their answer the line above the pill says "Try
 * using · *profound*" (under the "try saying" sentence). It ticks the moment
 * they do, by the same matcher the chips use.
 *
 * **The hint comes FROM the question, never from a list.** The steer hands
 * the model the whole CANDIDATE list as permission, and after each line
 * [CoachSuggester] writes an answer to the line that was ACTUALLY said and
 * only names a candidate when that answer naturally uses one — nothing, the
 * ordinary case, draws no word hint (the suggestion itself is drawn every
 * line; it replaced `CoachJudge`, iOS `6e9eb92`). [CoachPlan] rations the
 * word hint in code.
 *
 * ON by default for A1/A2, off above: a beginner is who the steered call is
 * for, and a switch buried in Call settings is one they never find. The
 * learner's own flip always wins — the key is only written by the toggle, so
 * "never touched" is the absence of a value. Realtime path only: the gateway
 * takes the steer on `set` and appends it to the reply's system prompt.
 */
object CoachMode {
    /** Same name as iOS's defaults key. */
    const val KEY = "futurevoice.call.coachMode"

    /** How many studied items the model and the judge are shown at once. */
    const val MAX_CANDIDATES = 8

    fun defaultOn(level: CefrLevel): Boolean = level == CefrLevel.A1 || level == CefrLevel.A2

    /** The learner's choice if they made one, else the level's default. */
    fun resolve(choice: Boolean?, levelRaw: String?): Boolean =
        choice ?: defaultOn(CefrLevel.from(levelRaw?.takeIf { it.isNotBlank() } ?: "b1"))

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    /** nil until the learner flips it. */
    fun choice(context: Context): Boolean? =
        prefs(context).takeIf { it.contains(KEY) }?.getBoolean(KEY, false)

    fun setChoice(context: Context, on: Boolean) = prefs(context).edit().putBoolean(KEY, on).apply()

    fun isOn(context: Context): Boolean {
        val lang = LanguageScope.active(context)
        return resolve(choice(context), LanguageScope.level(context, lang, ""))
    }
}

/** The ration, as a value so it can be reasoned about (and tested) apart from the call. */
data class CoachPlan(
    val hintsShown: Int = 0,
    val hinted: List<String> = emptyList(),
    /** Lines since the last hint (or since the call opened). */
    private val repliesSinceHint: Int = REPLIES_BETWEEN_HINTS,
) {
    /** Whether a hint may be drawn for the NEXT line — and therefore whether
     *  the model should be steered for it. */
    val mayHint: Boolean
        get() = hintsShown < MAX_HINTS && repliesSinceHint >= REPLIES_BETWEEN_HINTS

    /** Items still worth offering, in the caller's order. */
    fun candidates(pending: List<TalkGoalItem>): List<TalkGoalItem> =
        pending.filter { it.key !in hinted }.take(CoachMode.MAX_CANDIDATES)

    /** A fluent-self line has finished. */
    fun replyFinished(): CoachPlan = copy(repliesSinceHint = repliesSinceHint + 1)

    /** The suggestion named [item] and its hint is on screen. */
    fun hintShown(item: TalkGoalItem): CoachPlan =
        copy(hintsShown = hintsShown + 1, hinted = hinted + item.key, repliesSinceHint = 0)

    companion object {
        const val MAX_HINTS = 3
        const val REPLIES_BETWEEN_HINTS = 2

        private val CLOSERS = setOf('"', '\'', '”', '’', '」', '』', ')', '）', ' ', '\n', '\t')

        fun endsInQuestion(text: String): Boolean {
            val trimmed = text.trim { it in CLOSERS }
            return trimmed.endsWith("?") || trimmed.endsWith("？")
        }
    }
}

/**
 * Coach mode's answer for EVERY line (iOS `CoachReply`, `6e9eb92`): one short
 * thing the learner could say back, at their level, with an example in
 * brackets where only they know the answer ("I usually get up at [7].") and
 * its meaning in their own language. The empty hand, not the question, is
 * what stops a beginner talking.
 */
data class CoachReply(
    /** Target language. "[7]" is an example the learner swaps for their own
     *  words — drawn faded (`CoachReplyLabel`). */
    val say: String,
    /** Native language, the same brackets translated. "" when native == target. */
    val meaning: String,
    val turnId: String,
    /** The label above the line — "Try saying", or "You go first" when the
     *  learner opens the call (`StarterSituation.learnerFirst`). Null = "Try
     *  saying". Already localized. */
    val heading: String? = null,
) {
    companion object {
        /**
         * "[7]" is a placeholder for the learner's own words: drawn faded and
         * underlined, brackets dropped, the rest of the line as is. Pairs of
         * (text, isExample), in order; an unclosed "[" is plain text.
         */
        fun segments(line: String): List<Pair<String, Boolean>> {
            val out = ArrayList<Pair<String, Boolean>>()
            var rest = line
            while (true) {
                val open = rest.indexOf('[')
                val close = if (open < 0) -1 else rest.indexOf(']', open)
                if (open < 0 || close < 0) break
                if (open > 0) out += rest.substring(0, open) to false
                out += rest.substring(open + 1, close) to true
                rest = rest.substring(close + 1)
            }
            if (rest.isNotEmpty()) out += rest to false
            return out
        }
    }
}

/**
 * Writes the "try saying" for the line just spoken (iOS `CoachSuggester`,
 * which replaced `CoachJudge` 2026-10-01). One call per fluent-self line, the
 * opener included; when studied items ride along and the answer naturally
 * uses one, it names it — that is the word hint now (one call, not two).
 *
 * The DEFAULT model, not flash-lite (iOS `5b0587a`): the line is what the
 * learner is about to SAY, and flash-lite wrote "I will have a coffee please"
 * under a prompt that forbids it; 3.6 Flash didn't, at the same ~1–1.8 s.
 * Free (`purpose: "coach"`), off the voice's path.
 */
object CoachSuggester {
    @Serializable
    internal data class Payload(val say: String? = null, val meaning: String? = null, val word: String? = null)

    /** iOS builds the user message the same way, line by line. */
    internal fun content(line: String, learnerSaid: String?, earlier: String?, situation: String?,
                         candidates: List<TalkGoalItem>): String {
        var content = ""
        if (!situation.isNullOrEmpty()) content += "Situation: $situation\n"
        if (!earlier.isNullOrEmpty()) content += "Earlier they said: \"$earlier\"\n"
        if (!learnerSaid.isNullOrEmpty()) content += "The learner said: \"$learnerSaid\"\n"
        content += "Now the other speaker says: \"$line\""
        if (candidates.isNotEmpty()) {
            content += "\n\nStudied items:\n" + candidates.joinToString("\n") { "- ${it.text}" }
        }
        return content
    }

    /**
     * The guards, apart from the network so they can be tested. A line can
     * carry another script — the learner's name in Hangul on an English call
     * — and the model followed it and wrote the whole suggestion in Korean;
     * a suggestion they can't say in the call's language is no suggestion.
     * A learner whose own language IS the call's would read the same
     * sentence twice, so the meaning goes.
     */
    internal fun accept(payload: Payload?, candidates: List<TalkGoalItem>, target: String, native: String,
                        turnId: String): Pair<CoachReply, TalkGoalItem?>? {
        val say = payload?.say?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (!TextScript.isInTargetScript(say, target)) return null
        val meaning = if (LanguageCatalog.sameLanguage(target, native)) "" else payload.meaning?.trim().orEmpty()
        val item = payload.word?.trim()?.takeIf { it.isNotEmpty() }?.let { word ->
            val wanted = CarryoverDetector.normalized(word)
            candidates.firstOrNull { it.key == wanted || CarryoverDetector.normalized(it.text) == wanted }
        }
        return CoachReply(say, meaning, turnId) to item
    }

    suspend fun suggest(
        line: String,
        learnerSaid: String?,
        earlier: String?,
        situation: String? = null,
        candidates: List<TalkGoalItem>,
        target: String,
        native: String,
        level: CefrLevel,
        turnId: String,
    ): Pair<CoachReply, TalkGoalItem?>? {
        val payload = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = CoachPrompts.suggesterSystem(
                        LanguageCatalog.englishName(target), LanguageCatalog.englishName(native), level),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                        content(line, learnerSaid, earlier, situation, candidates))),
                    serializer = Payload.serializer(),
                    model = GeminiClient.Model.FLASH_36,
                    // Its thinking needs room, or the JSON comes back cut.
                    maxTokens = 1000,
                    purpose = "coach",
                    idempotencyKey = "coach-reply:$turnId",
                    fastThinking = true,
                )
            }.getOrNull()
        }
        return accept(payload, candidates, target, native, turnId)
    }
}

/**
 * The steer coach mode hands the gateway while a hint may be drawn: the
 * candidate list as PERMISSION, never an assignment. English like every other
 * prompt; items quoted as the learner saved them.
 */
fun ConversationEngine.coachSteer(items: List<TalkGoalItem>, focus: GrammarFocus? = null): String {
    val parts = mutableListOf<String>()
    if (items.isNotEmpty()) {
        val list = items.joinToString(", ") { "\"${it.text}\"" }
        parts += "COACH MODE. The learner is studying: $list. If — and only if — " +
            "one of them fits what you are ALREADY talking about, you may end " +
            "this reply with a question whose most natural answer would use " +
            "it. Do not say that word yourself, do not mention practice, words " +
            "or coaching, and never steer the topic toward a word. Most " +
            "replies should simply continue the conversation as they would " +
            "have."
    }
    // The grammar focus rides the same permission: a question whose natural
    // answer NEEDS the structure is practice the learner gets without being
    // told. The correction itself stays the card's job.
    if (focus != null) {
        parts += "GRAMMAR FOCUS. The learner keeps slipping on this: they say " +
            "\"${focus.pattern.mistake}\" where a fluent speaker says " +
            "\"${focus.pattern.correction}\" (${focus.pattern.context}). If it " +
            "fits the conversation, you may ask something whose natural answer " +
            "needs that structure. Never correct them in your reply, never " +
            "mention grammar, and don't do it every turn."
    }
    return parts.joinToString("\n\n")
}
