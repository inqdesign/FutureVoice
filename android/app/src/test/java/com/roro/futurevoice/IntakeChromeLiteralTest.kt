package com.roro.futurevoice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * UI text has ONE language — the app's (iOS CLAUDE.md). The new-person intake
 * and the Welcome heroes both shipped every line as an English literal under a
 * Korean screen, so this is a cheap tripwire: a `Text(…)`, `IntakeStepHeader(…)`
 * or `NarrativeCard(…)` handed a capitalised string literal fails here.
 * Sample MATERIAL (the Welcome demo's English titles and lines) is passed
 * through variables and named parameters, never these calls, so it is not
 * caught; chip VALUES stay English on purpose and live in `listOf(…)`.
 */
class IntakeChromeLiteralTest {

    private val files = listOf(
        "src/main/java/com/roro/futurevoice/ui/CounterpartIntakeScreen.kt",
        "src/main/java/com/roro/futurevoice/ui/brand/WelcomeHeroes.kt",
    )

    private val literal = Regex("""\b(Text|IntakeStepHeader|NarrativeCard)\(\s*(if\s*\([^)]*\)\s*)?"[A-Z]""")

    @Test fun noEnglishChromeLiterals() {
        for (path in files) {
            val file = File(path)
            assertTrue("$path not found (run from android/app)", file.exists())
            val hits = file.readLines().withIndex()
                .filter { (_, line) -> literal.containsMatchIn(line) }
                .map { (i, line) -> "${path.substringAfterLast('/')}:${i + 1}: ${line.trim()}" }
            assertTrue("English UI literals — use a string resource:\n" + hits.joinToString("\n"),
                hits.isEmpty())
        }
    }
}
