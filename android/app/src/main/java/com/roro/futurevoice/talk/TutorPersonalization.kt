package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/** What this learner keeps getting wrong, for the material written for them
 *  (iOS `LearnerWeakPoints`). Empty leaves both prompts as they were. */
object LearnerWeakPoints {
    private const val MAX_POINTS = 3

    fun lines(profile: LearnerProfile, sessions: List<Session>,
              now: Long = System.currentTimeMillis()): List<String> {
        val proven = GrammarFocus.candidates(profile, sessions, now).map { it.first }
        val chosen = proven.ifEmpty { profile.recurringMistakes.sortedByDescending { it.lastSeenAt } }
        return chosen.take(MAX_POINTS).map { "- \"${it.mistake}\" → \"${it.correction}\" (${it.context})" }
    }

    fun plannerBlock(lines: List<String>): String {
        if (lines.isEmpty()) return ""
        return "\n\nWhat this learner keeps getting wrong, from their own talks:\n" + lines.joinToString("\n") +
            "\nWhere the situation really needs one of these forms, write that challenge so it can't be said without it, and use the right form in its \"example\". Aim for two such challenges. Never bend a sentence to fit one: a form that doesn't belong in natural speech here is left out, and a word from the list above is not a word you have to use. The lesson stays about what they asked for, and \"title\" names that."
    }

    fun goalPrepBlock(lines: List<String>): String {
        if (lines.isEmpty()) return ""
        return "\nWHAT THIS LEARNER KEEPS GETTING WRONG (from their own talks)\n" + lines.joinToString("\n") +
            "\nThe model answer is what they will memorize: where it naturally needs one of these forms, use the right form. Never bend a sentence to fit one. If the answer uses one, the \"summary\" tip names it."
    }
}

/** A second reader for lines a learner will memorize (iOS `MaterialCheck`).
 *  A failed check keeps the lines as written. */
object MaterialCheck {
    @Serializable private data class Fix(val n: Int, val line: String)
    @Serializable private data class Reply(val fixes: List<Fix> = emptyList())

    private fun system(target: String): String =
        "You check lines a $target learner will memorize and say out loud in real life. Numbered lines follow.\n" +
        "For each line: would a native speaker say it exactly like this? Fix a line ONLY if it has a real error (grammar, article, a word that doesn't go with its neighbour) or no native speaker would ever say it. A plain or simple line is fine: never improve style, never make a line fancier or longer, never change a contraction, a speech level or a fact. A word that is right stays, even if another would be nicer: never swap it for a synonym. Make the smallest change that makes it right.\n" +
        "Return STRICT JSON: {\"fixes\": [{\"n\": 1, \"line\": \"the corrected line\"}]}. No fixes: {\"fixes\": []}."

    /** Ignores a fix that names no line, is empty or rewrites far more than
     *  a correction would. */
    fun apply(fixes: List<Pair<Int, String>>, lines: List<String>): List<String> {
        val out = lines.toMutableList()
        for ((n, raw) in fixes) {
            val was = lines.getOrNull(n - 1) ?: continue
            val line = raw.trim()
            if (line.isEmpty() || line.length > was.length + maxOf(12, was.length / 3)) continue
            out[n - 1] = line
        }
        return out
    }

    suspend fun corrected(lines: List<String>, language: String, purpose: String): List<String> {
        if (lines.isEmpty()) return lines
        val numbered = lines.mapIndexed { i, l -> "${i + 1}. $l" }.joinToString("\n")
        val reply = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = system(LanguageCatalog.englishName(language)),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, numbered)),
                    serializer = Reply.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 2048, purpose = purpose,
                    idempotencyKey = "material-check:${StoreJson.newId()}",
                )
            }.getOrNull()
        } ?: return lines
        return apply(reply.fixes.filter { TextScript.isInTargetScript(it.line, language) }.map { it.n to it.line }, lines)
    }

    suspend fun correctedText(text: String, language: String, purpose: String): String {
        val sentences = text.split(Regex("(?<=[.!?。！？])\\s*")).map { it.trim() }.filter { it.isNotEmpty() }
        val fixed = corrected(sentences, language, purpose)
        var out = text
        sentences.zip(fixed).filter { it.first != it.second }.forEach { (old, new) -> out = out.replace(old, new) }
        return out
    }
}
