package com.roro.futurevoice

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * One concept, one word — across the two string files.
 *
 * `strings_catalog.xml` is generated from the iOS catalog and
 * `strings_android.xml` is written by hand, so the same idea can end up with
 * two different words in the same language and nothing notices: the badge
 * said 완료 while the book export said 마스터, and Spanish arrived with
 * Completado beside Dominado. A per-key validator cannot see it, because the
 * two keys are different keys (iOS `2026-09-13`, "one badge, two words").
 */
class StringConsistencyTest {

    /** Pairs that name the SAME thing on screen: catalog key to Android key. */
    private val sameWord = listOf("mastered_550ec5" to "mastered")

    private val languages = listOf(
        "values", "values-ko", "values-ja", "values-zh-rTW",
        "values-es", "values-fr", "values-b+zh+Hans", "values-de")

    @Test fun theSameConceptUsesTheSameWordInEveryLanguage() {
        for (folder in languages) {
            val dir = File("src/main/res", folder)
            if (!dir.exists()) continue
            val catalog = strings(File(dir, "strings_catalog.xml"))
            val android = strings(File(dir, "strings_android.xml"))
            for ((catalogKey, androidKey) in sameWord) {
                val a = catalog[catalogKey] ?: continue
                val b = android[androidKey] ?: continue
                assertEquals("$folder: $catalogKey and $androidKey must read the same", a, b)
            }
        }
    }

    private fun strings(file: File): Map<String, String> {
        if (!file.exists()) return emptyMap()
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate { i ->
            val el = nodes.item(i)
            val name = el.attributes.getNamedItem("name").nodeValue
            name to el.textContent.trim().trim('"')
        }
    }
}
