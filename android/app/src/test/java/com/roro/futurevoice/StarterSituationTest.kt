package com.roro.futurevoice

import com.roro.futurevoice.data.StarterSituation
import com.roro.futurevoice.net.ScenarioLinkReader
import com.roro.futurevoice.talk.Scenario
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Talk's Everyday situations (iOS `StarterSituation`, `5b0587a`) and the
 * phone-side link reader (iOS `ScenarioLinkReader`, `c06a5cf`). A starter is
 * an ordinary scenario stamped with its id: the first tap mints it, every
 * later tap refreshes the SAME row from the catalog.
 */
class StarterSituationTest {
    private val cafe = StarterSituation.all.first { it.id == "order-cafe" }
    private val street = StarterSituation.all.first { it.id == "ask-directions" }

    @Test fun firstTapMintsAStampedScenarioWithTheWrittenGreetings() {
        val s = cafe.scenario(emptyList(), "en", "At a café", "a barista")
        assertEquals("order-cafe", s.starterId)
        assertEquals("At a café", s.environment)
        assertEquals("a barista", s.role)
        assertEquals("At a café", s.summary)
        assertEquals(listOf("Hi! What can I get you?", "Hey! What are you having?"), s.openers)
        assertEquals(0, s.openerCursor)
        assertTrue(s.notes.contains("Never push a task"))
    }

    @Test fun laterTapRefreshesTheSameRowAndKeepsItsHistory() {
        val first = cafe.scenario(emptyList(), "en", "At a café", "a barista")
            .copy(lastUsedAt = 42L, openerCursor = 1, environment = "old title")
        val again = cafe.scenario(listOf(first), "en", "At a café", "a barista")
        assertEquals(first.id, again.id)
        assertEquals(42L, again.lastUsedAt)
        // Same pool → the rotation carries on where it was.
        assertEquals(1, again.openerCursor)
        assertEquals("At a café", again.environment)
    }

    @Test fun aNewLanguagesPoolResetsTheCursor() {
        val first = cafe.scenario(emptyList(), "en", "At a café", "a barista").copy(openerCursor = 1)
        val ko = cafe.scenario(listOf(first), "ko", "카페에서", "바리스타")
        assertEquals("안녕하세요, 뭐 드릴까요?", ko.openers?.first())
        assertEquals(0, ko.openerCursor)
        // No written lines in this language → the call writes its own.
        assertNull(cafe.scenario(emptyList(), "fr", "Au café", "un barista").openers)
    }

    @Test fun theLearnerOpensOnTheStreet() {
        val s = street.scenario(emptyList(), "de", "Auf der Straße", "einem Passanten")
        assertNull(s.openers)
        assertEquals("Entschuldigung, wie komme ich zum [Bahnhof]?", street.learnerFirstLine("de"))
        assertEquals("Excuse me, how do I get to the [station]?", street.learnerFirstLine("es"))
        assertNull(cafe.learnerFirstLine("en"))
        assertEquals(street, StarterSituation.of(s))
        assertNull(StarterSituation.of(Scenario(environment = "mine")))
    }

    @Test fun everyStarterHasFourLanguagesOfAWayIn() {
        assertEquals(10, StarterSituation.all.size)
        assertEquals(StarterSituation.all.size, StarterSituation.all.map { it.id }.toSet().size)
        for (st in StarterSituation.all) {
            val lines = st.learnerFirst ?: st.openers.mapValues { it.value.first() }
            assertEquals(st.id, setOf("en", "ko", "ja", "de"), lines.keys)
        }
    }

    @Test fun linkReaderKeepsTitleDescriptionAndTextNotMarkup() {
        val html = """
            <html><head><title>Senior Designer &amp; Lead</title>
            <meta property="og:description" content="Join us in Berlin">
            <script>var x = "<p>nope</p>";</script><style>p{color:red}</style></head>
            <body><nav>Jobs</nav><!-- hidden --><h1>About the role</h1>
            <ul><li>Figma</li><li>Five&nbsp;years &#8211; or more</li></ul><p>Apply&#x21;</p></body></html>
        """.trimIndent()
        val text = ScenarioLinkReader.readable(html)
        val lines = text.lines()
        assertEquals("Title: Senior Designer & Lead", lines[0])
        assertEquals("Description: Join us in Berlin", lines[1])
        assertTrue(text.contains("About the role"))
        assertTrue(text.contains("• Figma"))
        assertTrue(text.contains("• Five years – or more"))
        assertTrue(text.contains("Apply!"))
        assertFalse(text.contains("nope"))
        assertFalse(text.contains("color:red"))
        assertFalse(text.contains("hidden"))
        assertFalse(text.contains("<"))
    }
}
