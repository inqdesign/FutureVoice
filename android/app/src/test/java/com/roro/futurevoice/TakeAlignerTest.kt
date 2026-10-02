package com.roro.futurevoice

import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.talk.TakeAligner
import com.roro.futurevoice.talk.WordTiming
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The learner's word onsets come from aligning the take to the model line
 * (`TakeAligner`). These recordings were built word by word with `say`
 * (scripts in plan 2.9), so every onset is KNOWN: the reference is one voice
 * at one rate with no gaps, each take another voice or rate, with pauses
 * dropped in and room noise added. The bar is the rhythm grade's own: a
 * word it calls measured must land within 120 ms (the "on beat" band) —
 * otherwise a dot would be drawn for a beat nobody hit.
 */
class TakeAlignerTest {

    private val truth = Json.parseToJsonElement(
        javaClass.getResourceAsStream("/take-align/truth.json")!!.bufferedReader().readText()
    ).jsonObject

    private fun wav(name: String) =
        WavPcm.parse(javaClass.getResourceAsStream("/take-align/$name.wav")!!.readBytes())!!

    private fun ints(key: String, field: String) =
        truth[key]!!.jsonObject[field]!!.jsonArray.map { it.jsonPrimitive.int }

    @Test fun measuredOnsetsLandOnTheBeat() {
        var measured = 0; var within = 0; var total = 0
        val report = StringBuilder()
        for (lang in listOf("en", "ko", "ja")) {
            val ref = wav("$lang-ref")
            val words = truth["$lang-ref"]!!.jsonObject["words"]!!.jsonArray.map { it.jsonPrimitive.content }
            val on = ints("$lang-ref", "onsets"); val ends = ints("$lang-ref", "ends")
            val timings = words.indices.map { WordTiming(words[it], on[it], ends[it]) }
            for (n in 0..2) {
                val key = "$lang-take$n"
                if (truth[key] == null) continue
                val take = wav(key)
                val expect = ints(key, "onsets")
                val mapped = TakeAligner.map(ref, timings, take)!!
                mapped.forEachIndexed { k, m ->
                    val err = m.onsetMs - expect[k]
                    total += 1
                    if (m.confident) { measured += 1; if (abs(err) <= 120) within += 1 }
                    report.append("%s %-10s err %+5d slope %.2f cost %.2f %s%s\n".format(
                        key, words[k], err, m.slope, m.cost,
                        if (m.confident) "measured" else "-",
                        if (m.confident && abs(err) > 120) "  << WRONG" else ""))
                }
            }
        }
        println(report)
        println("measured $measured/$total, on the beat $within/$measured")
        assertTrue("too few measured: $measured/$total", measured * 2 >= total)
        assertTrue("measured but off: $within/$measured", within * 10 >= measured * 9)
    }
}

/**
 * The same bar on CONNECTED speech: every recording here is ElevenLabs
 * (the synthesizer the model line comes from), so word onsets are its own
 * measured alignment. The reference is one preset voice at speed 1.0; each
 * take is another voice (or the same one slowed to 0.8/0.9), with two
 * hesitations cut in at word boundaries, a 350 ms lead-in like the
 * recorder's, and room noise. English and Korean.
 */
class TakeAlignerConnectedSpeechTest {
    private val truth = Json.parseToJsonElement(
        javaClass.getResourceAsStream("/take-align-el/truth.json")!!.bufferedReader().readText()).jsonObject

    private fun wav(n: String) = WavPcm.parse(javaClass.getResourceAsStream("/take-align-el/$n.wav")!!.readBytes())!!

    @Test fun measuredOnsetsLandOnTheBeat() {
        var measured = 0; var within = 0; var total = 0
        val errs = mutableListOf<Int>()
        val out = StringBuilder()
        for (lang in listOf("en", "ko")) {
            val ref = truth["$lang-ref"]!!.jsonArray.map { it.jsonArray }
            val timings = ref.map { WordTiming(it[0].jsonPrimitive.content, it[1].jsonPrimitive.int, it[2].jsonPrimitive.int) }
            for (key in truth.keys.filter { it.startsWith("$lang-l") }.sorted()) {
                val expect = truth[key]!!.jsonObject["onsets"]!!.jsonArray.map { it.jsonPrimitive.int }
                val mapped = TakeAligner.map(wav("$lang-ref"), timings, wav(key))!!
                mapped.forEachIndexed { k, m ->
                    val err = m.onsetMs - expect[k]
                    total += 1
                    if (m.confident) { measured += 1; errs += abs(err); if (abs(err) <= 120) within += 1 }
                    out.append("%s %-10s err %+5d slope %.2f cost %.2f %s\n".format(key, timings[k].word, err,
                        m.slope, m.cost, if (m.confident) "measured" else "-"))
                }
            }
        }
        println(out)
        errs.sort()
        println("connected: measured $measured/$total, on the beat $within/$measured, " +
            "median ${errs.getOrNull(errs.size / 2)} ms, p90 ${errs.getOrNull(errs.size * 9 / 10)} ms")
        // The truth here is ElevenLabs' own alignment, which is itself off by
        // 100–200 ms on some words (a first word always "starts" at 0, before
        // the voice does), so the bar is lower than on the built fixtures.
        assertTrue(measured * 2 >= total)
        assertTrue("measured but off: $within/$measured", within * 4 >= measured * 3)
        assertTrue("median ${errs[errs.size / 2]}", errs[errs.size / 2] <= 40)
    }
}
