package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.ui.TalkGoalItem
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/**
 * Coach mode (iOS `CoachMode.swift`, `ede039e` + `45b397e`): the call's
 * listening moment, used.
 *
 * The learner already studies words; the call is the only place they can be
 * spent, and the chip row above the transcript only waits for that to happen
 * by chance. Coach mode makes it happen on purpose — the fluent self may ask
 * something whose natural answer uses a word the learner is studying, and
 * while they think about their answer their own "Listening…" bubble says
 * "Try using · *profound*". It ticks the moment they do, by the same
 * matcher the chips use.
 *
 * **The hint comes FROM the question, never from a list.** The steer hands
 * the model the whole CANDIDATE list as permission, and after each line
 * [CoachJudge] reads the question that was ACTUALLY asked and returns the
 * candidate a natural answer would use — or nothing, the ordinary answer.
 * [CoachPlan] rations it in code.
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

    /** The judge matched a question to [item] and it is on screen. */
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
 * Reads the question the fluent self just asked and names the studied item a
 * natural answer to it would use. Free (`purpose: "coach"`, flash-lite), off
 * the voice's path — it runs while the learner is already thinking.
 */
object CoachJudge {
    @Serializable
    private data class Verdict(val word: String? = null)

    suspend fun pick(
        question: String,
        learnerSaid: String?,
        candidates: List<TalkGoalItem>,
        key: String,
    ): TalkGoalItem? {
        if (candidates.isEmpty()) return null
        val list = candidates.joinToString("\n") { "- ${it.text}" }
        var content = ""
        if (!learnerSaid.isNullOrEmpty()) content += "The learner had said: \"$learnerSaid\"\n"
        content += "They were then asked: \"$question\"\n\nStudied items:\n$list"
        val verdict = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = SYSTEM,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                    serializer = Verdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31,
                    maxTokens = 200,
                    purpose = "coach",
                    idempotencyKey = "coach:$key",
                    fastThinking = true,
                )
            }.getOrNull()
        }
        val word = verdict?.word?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val wanted = CarryoverDetector.normalized(word)
        return candidates.firstOrNull { it.key == wanted || CarryoverDetector.normalized(it.text) == wanted }
    }

    private const val SYSTEM =
        "A language learner is on a spoken call and has just been asked a " +
        "question. They are studying the items listed. Decide whether a " +
        "natural, honest answer to THAT question would use one of those items.\n\n" +
        "Return {\"word\": \"<the item exactly as listed>\"} only when the fit is " +
        "obvious: the item would carry what the answer MEANS — the thing the " +
        "question is about — in its usual sense. A reaction word that could " +
        "end any answer (\"awesome\", \"sure\") or a small word that could appear " +
        "in any sentence does not count. If the learner would have to force " +
        "it in, if the line asks nothing, or if nothing fits, return " +
        "{\"word\": null}. null is the usual answer. Never return a word that " +
        "is not listed."
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
