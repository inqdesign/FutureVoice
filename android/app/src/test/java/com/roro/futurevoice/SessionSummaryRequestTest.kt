package com.roro.futurevoice

import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.SessionSummaryClient
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.UserPersona
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Plan 2.29: what the Android client sends `session-summary`, so the server
 * can build iOS 1.1.1's `summarySystemPrompt` — the typed facts as "already
 * on file", the notebook numbered and dated (what `replaces` points into),
 * the learner's share-rung moves, and the expression budget — and the
 * `about_user` parse matching iOS `ClaudeSummaryPayload.AboutUser`.
 */
class SessionSummaryRequestTest {

    private val learned = 1_758_000_000_000L   // 2025-09-16T05:20:00Z

    private val persona = UserPersona(
        displayName = "A", city = "Berlin", country = "Germany", occupation = "designer",
        learnedNotes = listOf(
            PersonaNote(id = "N1", text = "two kids, kindergarten age", learnedAt = learned,
                kind = PersonaNote.Kind.FACT),
            PersonaNote(id = "N2", text = "trip to Seoul next week", learnedAt = learned + 1_234,
                kind = PersonaNote.Kind.NOW),
        ),
        shareCorrections = listOf(
            UserPersona.ShareCorrection("two kids, kindergarten age",
                PersonaNote.Share.ALL, PersonaNote.Share.GIST, learned)),
    )

    private fun session(fluentTurns: Int) = Session(
        userId = "u", targetLanguage = "ko", startedAt = learned,
        turns = (0 until fluentTurns).flatMap {
            listOf(Turn(role = TurnRole.FLUENT_SELF, transcript = "안녕 $it"),
                Turn(role = TurnRole.USER, transcript = "응 $it"))
        },
    )

    private fun body(fluentTurns: Int = 3, p: UserPersona? = persona) = SessionSummarizer.requestBody(
        session = session(fluentTurns), nativeLanguage = "en", profile = JsonObject(emptyMap()),
        persona = p, rememberedNotes = p?.learnedNotes.orEmpty(), metrics = JsonObject(emptyMap()),
    )

    private fun wire(b: SessionSummaryClient.RequestBody): JsonObject =
        Json.parseToJsonElement(Edge.json.encodeToString(SessionSummaryClient.RequestBody.serializer(), b)).jsonObject

    @Test fun sendsTypedFactsNotTheNotebookAsAlreadyOnFile() {
        assertEquals(listOf("Lives in Berlin, Germany", "designer"), body().known_about_user)
    }

    @Test fun rememberedNotesAreNumberedInOrderWithTheirDate() {
        val w = wire(body())
        val notes = w["remembered_notes"]!!.jsonArray.map { it.jsonObject }
        assertEquals(listOf("two kids, kindergarten age", "trip to Seoul next week"),
            notes.map { it["text"]!!.jsonPrimitive.content })
        assertEquals(listOf("fact", "now"), notes.map { it["kind"]!!.jsonPrimitive.content })
        // ISO-8601, whole seconds — the server writes the age from it.
        assertEquals("2025-09-16T05:20:00Z", notes[0]["learned_at"]!!.jsonPrimitive.content)
        assertEquals("2025-09-16T05:20:01Z", notes[1]["learned_at"]!!.jsonPrimitive.content)
    }

    @Test fun shareCorrectionsGoOutAsRungNames() {
        val c = wire(body())["share_corrections"]!!.jsonArray.single().jsonObject
        assertEquals("all", c["from"]!!.jsonPrimitive.content)
        assertEquals("gist", c["to"]!!.jsonPrimitive.content)
        assertEquals("two kids, kindergarten age", c["text"]!!.jsonPrimitive.content)
    }

    @Test fun expressionBudgetFollowsFluentTurns() {
        assertEquals(6, body(fluentTurns = 2).expression_budget)
        assertEquals(9, body(fluentTurns = 9).expression_budget)
        assertEquals(14, body(fluentTurns = 30).expression_budget)
    }

    @Test fun noPersonaStillSendsEveryField() {
        val w = wire(body(p = null))
        for (k in listOf("known_about_user", "remembered_notes", "share_corrections"))
            assertTrue(k, w[k]!!.jsonArray.isEmpty())
        assertEquals("true", w["stream"]!!.jsonPrimitive.content)
    }

    @Test fun aboutUserReadsTextAndReplacesByTypeLikeIOS() {
        val payload = Json.parseToJsonElement("""{"about_user":[
            {"text":"moved to Hamburg","kind":"fact","share":"all","replaces":1},
            {"text":"a number where a number belongs","replaces":"2"},
            {"text":5},
            {"text":"unknown rung","share":"some","kind":"soon"}
        ]}""").jsonObject
        val a = SessionSummarizer.aboutUser(payload)
        assertEquals(3, a.size)
        assertEquals(1, a[0].replaces)
        assertNull(a[1].replaces)                      // a string is not an Int
        assertEquals(PersonaNote.Share.NOTHING, a[2].share) // unreadable rung → hidden
        assertEquals(PersonaNote.Kind.FACT, a[2].kind)
    }
}
