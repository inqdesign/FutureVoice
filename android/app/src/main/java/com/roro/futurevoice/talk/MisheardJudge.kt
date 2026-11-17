package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/**
 * "That wasn't me" said out loud (iOS `MisheardJudge`, 2026-11-17).
 *
 * A learner's mic picked up a stranger on the street; the call answered it,
 * corrected it, and the next call opened on it. She said twice the line was
 * not hers and nothing could act on that. Now a learner's line that says an
 * earlier line was misheard, or was another voice, flags that line the way
 * the transcript page's swipe does.
 *
 * Two steps: a word check in code picks the few turns worth asking about
 * ([mayRetract]), and one small model call decides which line they mean
 * ([retractedLine]). A wrong yes takes a real line out of the learner's
 * score, so the judge says none when unsure. Measured on iOS with
 * `scripts/misheard-probe.py` (66/66); the prompt and the words are iOS's.
 */
object MisheardJudge {

    /** An earlier line the learner may be pointing at, with the reply it got. */
    data class Candidate(val turnId: String, val sessionId: String, val said: String, val reply: String)

    fun mayRetract(text: String): Boolean {
        val t = text.lowercase()
        return HINTS.any { t.contains(it) }
    }

    private val HINTS = listOf(
        "misheard", "mishear", "heard wrong", "heard me wrong", "heard it wrong", "wasn't me",
        "was not me", "not me ", "not my voice", "didn't say", "did not say", "never said",
        "not what i said", "someone else", "somebody else", "other people", "another person", "background",
        "noise", "잘못 들", "잘못들", "내가 한 말", "내 말이 아니", "내 목소리",
        "소음", "다른 사람", "말 안 했", "말한 적", "그런 말 안", "옆에서",
        "옆 사람", "聞き間違", "言ってない", "言っていない", "言ってません", "私じゃ",
        "僕じゃ", "俺じゃ", "私の声", "雑音", "他の人", "周りの",
        "verhört", "falsch verstanden", "falsch gehört", "nicht gesagt", "nie gesagt", "war ich nicht",
        "nicht meine stimme", "jemand anders", "jemand anderes", "hintergrund", "geräusch", "no dije",
        "no he dicho", "no fui yo", "no era yo", "no es mi voz", "otra persona", "oíste mal",
        "escuchaste mal", "entendiste mal", "ruido", "pas dit", "pas moi", "pas ma voix",
        "quelqu'un d'autre", "mal entendu", "mal compris", "bruit", "没说", "沒說",
        "不是我", "听错", "聽錯", "别人", "別人", "噪音",
        "杂音",
    )

    val SYSTEM = "A language learner is on a voice call. Speech recognition writes down what they say, and it sometimes mishears them or writes down another voice near them (a passer-by, a TV) as if it were theirs.\nYou get numbered earlier lines that were written down as the learner's, each with the reply it got, and then the learner's newest line. Decide whether the newest line says that ONE of the numbered lines was not what they said: misheard, or not their voice at all.\nIt counts only when they are disowning the WORDS: \"I didn't say that\", \"that was someone else\", \"you misheard me\". It does not count when they said it and now think differently (\"I didn't mean it\", \"actually, no\"), when they correct a fact inside something they did say, when they complain that the reply misunderstood their point, or when they talk about noise without disowning a line.\nPick the line by what they point at: its words, its subject, or \"what you just heard\" (the latest numbered line). If they disown a line that is not in the list, or you are not sure which one, answer none.\nReturn {\"line\": <number>} or {\"line\": null}."

    fun content(candidates: List<Candidate>, newest: String): String {
        val lines = candidates.mapIndexed { i, c ->
            "${i + 1}. learner: \"${clip(c.said)}\"\n   reply: \"${clip(c.reply)}\""
        }.joinToString("\n")
        return "Earlier lines, oldest first:\n$lines\n\nNewest line from the learner: \"${clip(newest, 400)}\""
    }

    private fun clip(s: String, max: Int = 220): String {
        val t = s.trim()
        return if (t.length <= max) t else t.take(max - 1) + "…"
    }

    @Serializable
    private data class Verdict(val line: Int? = null)

    /** Which candidate the newest line disowns, or null. Free (`coach`). */
    suspend fun retractedLine(newest: String, candidates: List<Candidate>, turnId: String): Candidate? {
        if (candidates.isEmpty()) return null
        val v = withTimeoutOrNull(8_000) {
            runCatching {
                GeminiClient(AuthRepository()).sendJson(
                    system = SYSTEM,
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content(candidates, newest))),
                    serializer = Verdict.serializer(),
                    model = GeminiClient.Model.FLASH_LITE_31, maxTokens = 100, purpose = "coach",
                    idempotencyKey = "misheard:$turnId", fastThinking = true,
                )
            }.getOrNull()
        }
        return v?.line?.let { candidates.getOrNull(it - 1) }
    }
}
