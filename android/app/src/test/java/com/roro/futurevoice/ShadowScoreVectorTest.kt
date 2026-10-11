package com.roro.futurevoice

import com.roro.futurevoice.talk.ShadowScore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/** Golden vectors from the REAL ShadowEngine (`gen-vectors.sh`). */
class ShadowScoreVectorTest {

    @Test fun analyzeMatchesSwift() {
        val v = Json.parseToJsonElement(
            javaClass.getResourceAsStream("/vectors/summary-ingestion.json")!!
                .bufferedReader().readText()
        ).jsonObject["shadow_analyze"]!!.jsonArray
        for (case in v.map { it.jsonObject }) {
            val target = case["target"]!!.jsonPrimitive.content
            val learner = case["learner"]!!.jsonPrimitive.content
            val language = case["language"]!!.jsonPrimitive.content
            // Japanese is scored by SEGMENTER words, and segmentation is the
            // platform's own (BreakIterator vs CFStringTokenizer, unreachable
            // on a JVM — see JapaneseMorphVectorTest). The two cut some lines
            // differently (でも vs で|も), so a ja score can differ by a few
            // points across platforms; checked on a device, not here.
            if (language.startsWith("ja")) continue
            val a = ShadowScore.analyze(target, learner, language)
            val label = "$target / $learner"
            assertEquals(label, case["score"]!!.jsonPrimitive.int, a.score)
            assertEquals(label, case["matches"]!!.jsonPrimitive.int, a.matchCount)
            assertEquals(label, case["targetTokens"]!!.jsonPrimitive.int, a.targetTokenCount)
            assertEquals(label, case["learnerTokens"]!!.jsonPrimitive.int, a.learnerTokenCount)
            assertEquals(label,
                case["ops"]!!.jsonArray.map { it.jsonPrimitive.content },
                a.steps.map { it.op.name.lowercase() })
        }
    }
}
