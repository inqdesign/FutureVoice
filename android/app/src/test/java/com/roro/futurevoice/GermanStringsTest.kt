package com.roro.futurevoice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * German is a FULLY translated UI language (iOS `d3175f8`, 2026-09-28): it
 * sits under "Everything you read in the app", so a key the hand-written
 * Android file adds in English only would break that promise silently —
 * Android falls back to values/ without a word. The generated catalog follows
 * the iOS column; this guards the half written by hand.
 */
class GermanStringsTest {

    @Test fun everyAndroidOnlyKeyHasAGermanValue() {
        val english = translatableNames(File("src/main/res/values/strings_android.xml"))
        val german = translatableNames(File("src/main/res/values-de/strings_android.xml"))
        val missing = english - german
        assertTrue("values-de/strings_android.xml is missing: ${missing.sorted()}", missing.isEmpty())
    }

    @Test fun germanIsAnAppLanguage() {
        assertTrue("de" in com.roro.futurevoice.core.UILanguage.translated)
        val config = File("src/main/res/xml/locales_config.xml").readText()
        assertTrue("locales_config.xml must list de", "android:name=\"de\"" in config)
    }

    private fun translatableNames(file: File): Set<String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val out = mutableSetOf<String>()
        for (tag in listOf("string", "plurals", "string-array")) {
            val nodes = doc.getElementsByTagName(tag)
            for (i in 0 until nodes.length) {
                val attrs = nodes.item(i).attributes
                if (attrs.getNamedItem("translatable")?.nodeValue == "false") continue
                out += attrs.getNamedItem("name").nodeValue
            }
        }
        return out
    }
}
