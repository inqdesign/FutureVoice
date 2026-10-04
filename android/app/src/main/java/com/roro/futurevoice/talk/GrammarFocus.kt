package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.security.MessageDigest

/**
 * Coach mode's GRAMMAR focus (iOS `GrammarFocus.swift`, `45b397e`): the slip
 * this learner keeps making, named once at the top of the call and watched
 * for the rest of it.
 *
 * - [pick] chooses ONE pattern per call — seen at least twice, heard within
 *   [FRESH_DAYS], not retired — highest frequency first.
 * - [describe] names it in the learner's language ("과거 시제") with one line
 *   of what to watch — coaching, so native; the pair stays in the target
 *   language. Cached per pattern, so it is written once.
 * - [isRepeat] judges each live correction: is this the SAME slip again? A
 *   model call, because "the same mistake" is a category no string test
 *   sees. It only answers yes/no; the COUNT is code.
 *
 * Retirement is by evidence: a pattern focused in [RETIRE_AFTER_CLEAN_CALLS]
 * calls with no repeat, and not re-detected by a summary since
 * (`lastSeenAt` would move), steps aside. A re-detection brings it back.
 */
data class GrammarFocus(
    val pattern: LearnerPattern,
    val label: String,
    val tip: String,
) {
    val key: String get() = LearnerProfile.patternKey(pattern)

    fun record(repeats: Int) = GrammarFocusRecord(
        patternKey = key, label = label, mistake = pattern.mistake,
        correction = pattern.correction, repeats = repeats)

    /** Is any of this turn's fixes the same kind of slip as the focus? */
    suspend fun isRepeat(fixes: List<TurnFix>, turnId: String): Boolean {
        if (fixes.isEmpty()) return false
        val list = fixes.joinToString("\n") { "- \"${it.was}\" → \"${it.now}\"" }
        val system = "A language learner is working on one recurring mistake. Decide " +
            "whether any of the new corrections is the SAME KIND of mistake — " +
            "the same grammar point, even with different words (a wrong past " +
            "form is a wrong past form whatever the verb). A different point " +
            "that happens to sit in the same sentence does not count.\n" +
            "Return {\"same\": true} or {\"same\": false}. When unsure, false."
        val content = "Recurring mistake: \"${pattern.mistake}\" → \"${pattern.correction}\" (${pattern.context})\n" +
            "New corrections:\n$list"
        val v = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = system,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                    serializer = RepeatVerdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 100, purpose = "coach",
                    idempotencyKey = "coach-repeat:$turnId", fastThinking = true,
                )
            }.getOrNull()
        }
        return v?.same ?: false
    }

    @Serializable
    private data class RepeatVerdict(val same: Boolean = false)

    @Serializable
    private data class Description(val label: String = "", val tip: String = "")

    companion object {
        const val MIN_FREQUENCY = 2
        const val FRESH_DAYS = 45
        const val RETIRE_AFTER_CLEAN_CALLS = 2

        private const val CACHE_KEY = "futurevoice.coach.focusDescriptions"
        private const val DAY_MS = 86_400_000L

        fun pick(profile: LearnerProfile, sessions: List<Session>,
                 now: Long = System.currentTimeMillis()): LearnerPattern? {
            val fresh = now - FRESH_DAYS * DAY_MS
            return profile.recurringMistakes
                .filter { it.frequency >= MIN_FREQUENCY && it.lastSeenAt >= fresh }
                .filter { !isRetired(it, sessions) }
                .sortedWith(compareByDescending<LearnerPattern> { it.frequency }.thenByDescending { it.lastSeenAt })
                .firstOrNull()
        }

        fun isRetired(pattern: LearnerPattern, sessions: List<Session>): Boolean {
            val key = LearnerProfile.patternKey(pattern)
            val clean = sessions.count {
                val f = it.grammarFocus
                f != null && f.patternKey == key && f.repeats == 0 &&
                    (it.endedAt ?: it.startedAt) > pattern.lastSeenAt
            }
            return clean >= RETIRE_AFTER_CLEAN_CALLS
        }

        /** Name the pattern in [native]. Null when the call fails — the call
         *  then runs without a focus rather than with an unnamed one. */
        suspend fun describe(context: Context, pattern: LearnerPattern, target: String,
                             native: String): GrammarFocus? {
            val key = "${LearnerProfile.patternKey(pattern)}|$native"
            val prefs = context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
            val cache = runCatching {
                Json.parseToJsonElement(prefs.getString(CACHE_KEY, null) ?: "{}").jsonObject
            }.getOrDefault(JsonObject(emptyMap()))
            cache[key]?.let { hit ->
                val o = runCatching { hit.jsonObject }.getOrNull()
                val label = o?.get("label")?.jsonPrimitive?.content
                val tip = o?.get("tip")?.jsonPrimitive?.content
                if (label != null && tip != null) return GrammarFocus(pattern, label, tip)
            }
            val nativeName = LanguageCatalog.englishName(native)
            val targetName = LanguageCatalog.englishName(target)
            val system = "A $targetName learner keeps making one mistake. Name the grammar " +
                "point it belongs to, for a label they read mid-call, and say in one " +
                "short sentence what to watch for.\n\n" +
                "Return {\"label\": \"...\", \"tip\": \"...\"}, both in $nativeName:\n" +
                "- label: the grammar point as a learner would say it, 2–4 words " +
                "(e.g. \"past tense\", \"articles a/the\", \"subject particle\"). Not " +
                "the example, not a sentence.\n" +
                "- tip: one plain sentence, at most 12 words, about WHEN it applies. " +
                "Friendly, never scolding, no grammar jargon beyond the label."
            val content = "They said: \"${pattern.mistake}\"\n" +
                "Fluent: \"${pattern.correction}\"\n" +
                "Note: ${pattern.context}"
            val d = withTimeoutOrNull(8_000) {
                runCatching {
                    GeminiClient(AuthRepository()).sendJson(
                        system = system,
                        messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                        serializer = Description.serializer(),
                        model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 200, purpose = "coach",
                        idempotencyKey = "coach-focus:${digest(key)}", fastThinking = true,
                    )
                }.getOrNull()
            } ?: return null
            val label = d.label.trim()
            val tip = d.tip.trim()
            if (label.isEmpty()) return null
            val updated = JsonObject(cache + (key to buildJsonObject { put("label", label); put("tip", tip) }))
            prefs.edit().putString(CACHE_KEY, updated.toString()).apply()
            return GrammarFocus(pattern, label, tip)
        }

        private fun digest(s: String): String =
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
                .take(12).joinToString("") { "%02x".format(it) }

        /**
         * The learner's slip and its fix, trimmed to the part that CHANGED
         * with [context] units of what they share on each side (iOS
         * `GrammarFocusPair.compact`). Words for a spaced language;
         * characters for one without spaces. Truncating two whole sentences
         * to one line kept their ends and cut the one word that differs.
         */
        fun compact(a: String, b: String, context: Int? = null): Pair<String, String> {
            val spaced = a.contains(' ') || b.contains(' ')
            val x = if (spaced) a.split(' ').filter { it.isNotEmpty() } else a.map { it.toString() }
            val y = if (spaced) b.split(' ').filter { it.isNotEmpty() } else b.map { it.toString() }
            val keep = context ?: if (spaced) 1 else 2
            fun norm(s: String) = s.lowercase().trim { isPunct(it) }
            var head = 0
            while (head < minOf(x.size, y.size) && norm(x[head]) == norm(y[head])) head++
            var tail = 0
            while (tail < minOf(x.size, y.size) - head &&
                norm(x[x.size - 1 - tail]) == norm(y[y.size - 1 - tail])) tail++
            if (head + tail <= 0 || head >= maxOf(x.size, y.size)) return a to b
            val from = maxOf(0, head - keep)
            val cut = maxOf(0, tail - keep)
            val sep = if (spaced) " " else ""
            val xs = x.subList(from, maxOf(from, x.size - cut)).joinToString(sep)
            val ys = y.subList(from, maxOf(from, y.size - cut)).joinToString(sep)
            val lead = if (from > 0) "…" else ""
            val trail = if (cut > 0) "…" else ""
            return (lead + xs + trail) to (lead + ys + trail)
        }

        /** Foundation's `.punctuationCharacters` (Unicode P*). */
        private fun isPunct(c: Char): Boolean = when (Character.getType(c).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION -> true
            else -> false
        }
    }
}
