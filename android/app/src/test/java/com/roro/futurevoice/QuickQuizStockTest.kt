package com.roro.futurevoice

import com.roro.futurevoice.data.QuickQuizStock
import com.roro.futurevoice.data.WeeklyTestEngine
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `QuickQuizStock`'s reading (02aff591): one bad item never sinks the
 *  batch, and code keeps only one blank with four distinct choices. */
class QuickQuizStockTest {
    private fun parse(text: String) = QuickQuizStock.parsePayload(Json.parseToJsonElement(text))

    @Test fun oneBadItemDoesNotSinkTheBatch() {
        val items = parse("""{"items":[
            {"type":"grammar","point":"past","tip":"t","sentence":"I ___ there yesterday.","answer":"went","wrong":["go","goes","going"]},
            "{\"type\":\"expression\",\"point\":\"m\",\"question\":\"Let's ___ tonight.\",\"correct\":\"eat out\",\"options\":[\"eat out\",\"give up\",\"run into\",\"look after\"]}",
            42,
            {"type":"grammar","sentence":"no answer here"}
        ]}""")
        assertEquals(2, items.size)
        assertEquals(QuickQuizStock.Kind.expression, items[1].kind)
        assertEquals("eat out", items[1].answer)
        assertEquals(listOf("give up", "run into", "look after"), items[1].wrong)
    }

    @Test fun questionsKeyIsRead() {
        assertEquals(1, parse("""{"questions":[{"sentence":"a ___ b","answer":"x","wrong":["y","z","w"]}]}""").size)
    }

    @Test fun validationKeepsOneBlankAndFourDistinctChoices() {
        val ok = parse("""{"items":[{"type":"grammar","sentence":"I ___ there yesterday.","answer":"went","wrong":["go","goes","going"]}]}""").single()
        val v = QuickQuizStock.validated(ok, "en")
        assertNotNull(v)
        assertEquals("I ${WeeklyTestEngine.BLANK_MARK} there yesterday.", v!!.sentence)
        val dup = parse("""{"items":[{"sentence":"I ___ there.","answer":"went","wrong":["went","goes","going"]}]}""").single()
        assertNull(QuickQuizStock.validated(dup, "en"))
        val twoBlanks = parse("""{"items":[{"sentence":"I ___ there ___.","answer":"went","wrong":["go","goes","going"]}]}""").single()
        assertNull(QuickQuizStock.validated(twoBlanks, "en"))
    }
}
