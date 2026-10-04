package com.roro.futurevoice

import com.roro.futurevoice.net.GeminiJson
import com.roro.futurevoice.net.IdempotencyKey
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * iOS `GeminiJSONRepairTests`, case for case: the summary's coaching fields
 * quote target-language words as `「"had"」` with the inner quotes unescaped.
 * The repair must read those, and must never touch a body that decodes.
 */
class GeminiJsonRepairTest {
    @Serializable private data class Phrase(val userSaid: String, val reason: String)
    @Serializable private data class Body(val phrases: List<Phrase>, val title: String)

    private val json = Json { ignoreUnknownKeys = true }
    private fun decode(s: String): Body = GeminiJson.decode(Body.serializer(), s, json)

    @Test fun reportedShapesDecode() {
        val cases = listOf(
            "과거 일을 이야기할 때는 「\"had\"」처럼 과거형을 사용해요." to
                "과거 일을 이야기할 때는 「\"had\"」처럼 과거형을 사용해요.",
            "현재완료 시제 「\"have seen\"」으로 표현하는 것이 자연스럽습니다." to
                "현재완료 시제 「\"have seen\"」으로 표현하는 것이 자연스럽습니다.",
            "표준 용어는 「\"research and development\"」입니다." to
                "표준 용어는 「\"research and development\"」입니다.",
        )
        for ((raw, expected) in cases) {
            val text = """
            {
              "phrases": [
                {
                  "userSaid": "I have a good time",
                  "reason": "$raw"
                }
              ],
              "title": "Weekend"
            }
            """.trimIndent()
            val body = decode(text)
            assertEquals(expected, body.phrases.first().reason)
            assertEquals("Weekend", body.title)
            // The tree-walking reader (the summary) repairs the same way.
            assertEquals("Weekend", GeminiJson.parseObject(text)["title"].toString().trim('"'))
        }
    }

    @Test fun bareInteriorQuotesDecode() {
        val text = """{"phrases":[{"userSaid":"x","reason":"say "went" here"}],"title":"t"}"""
        assertEquals("say \"went\" here", decode(text).phrases.first().reason)
    }

    @Test fun validJsonIsUntouched() {
        val text = """{"phrases":[{"userSaid":"a, b","reason":"「\"had\"」 ok: yes"}],"title":"t"}"""
        assertNull(GeminiJson.repairingInteriorQuotes(text))
        assertEquals("「\"had\"」 ok: yes", decode(text).phrases.first().reason)
    }

    @Test fun unrepairableThrowsOriginalError() {
        val text = """{"phrases":[{"userSaid":"x""""
        try {
            decode(text); fail("expected the decoder's own error")
        } catch (e: SerializationException) {
            // the decoder's own error, not a repair artefact
        }
    }

    /** iOS `6a9e866`: a non-ASCII key goes out as its SHA-256; ASCII as is. */
    @Test fun idempotencyKeyIsHeaderSafe() {
        assertEquals("freetalk-openers:v2|en|May", IdempotencyKey.headerSafe("freetalk-openers:v2|en|May"))
        val hashed = IdempotencyKey.headerSafe("freetalk-openers:v2|ko|메이")
        assertTrue(hashed.startsWith("h:") && hashed.length == 66)
        assertTrue(hashed.all { it in ' '..'~' })
        assertEquals(hashed, IdempotencyKey.headerSafe("freetalk-openers:v2|ko|메이"))
    }
}
