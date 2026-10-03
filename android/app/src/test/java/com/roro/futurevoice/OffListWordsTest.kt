package com.roro.futurevoice

import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.VocabStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A word the graded list doesn't carry is still a word (iOS `7f6f5ec`).
 * The pool is ~8k content words, so "chore" isn't in it — and being absent
 * used to mean being invisible even when the call was about the word.
 *
 * Only the language-independent half is testable on the JVM: the pool itself
 * is loaded from the app's assets, so a word's POOL membership can't be
 * asked here. What this pins is the filter that stands in for iOS's
 * part-of-speech tagger, which Android has not got.
 */
class OffListWordsTest {

    @Test fun closedClassWordsAreLeftOutOnPurpose() {
        for (w in listOf("the", "and", "with", "of", "but", "is", "have", "would",
                         "something", "yeah", "okay", "just", "really")) {
            assertTrue(w, CoreVocabulary.isUngraded(w, "en"))
        }
    }

    @Test fun ordinaryVocabularyIsNot() {
        for (w in listOf("chore", "sublet", "boiler", "commute", "deadline")) {
            assertFalse(w, CoreVocabulary.isUngraded(w, "en"))
        }
    }

    @Test fun caseDoesNotMatter() {
        assertTrue(CoreVocabulary.isUngraded("The", "en"))
    }

    /** The pool is empty on the JVM (its TSV lives in the app's assets), so
     *  every real word here is "off list" — which is what makes the rest of
     *  the filter visible. */
    @Test fun aWordTheFluentSelfKeptComingBackToLeadsOnEvidence() {
        val counts = VocabStore.offListContentWords(listOf(
            "The chore was mine.", "Another chore, chore, chore today.", "A sublet in Berlin."), "en")
        // TURNS, not occurrences: three "chore" in one sentence is a tic.
        assertEquals(2, counts["chore"])
        assertEquals(1, counts["sublet"])
        // Closed class, a name, and a two-letter token never arrive.
        assertNull(counts["the"])
        assertNull(counts["berlin"])
        assertNull(counts["in"])
    }

    /** A capital anywhere but the start of a sentence is a name. A name that
     *  OPENS one still gets through — iOS asks its name tagger, Android has
     *  none, and the cost is one stray row in a chapter of 24. */
    @Test fun aCapitalAtTheStartOfASentenceIsGrammarNotAName() {
        val counts = VocabStore.offListContentWords(
            listOf("Chores pile up. Berlin is far."), "en")
        assertEquals(1, counts["chores"])
        assertEquals(1, counts["berlin"])
    }

    @Test fun koreanAndJapaneseAreEmptyByConstruction() {
        assertTrue(VocabStore.offListContentWords(listOf("집안일을 했어요"), "ko").isEmpty())
        assertTrue(VocabStore.offListContentWords(listOf("家事をしました"), "ja").isEmpty())
    }

    @Test fun aLanguageWithNoListLosesNothing() {
        // No entry means every word rides along as a candidate, which is the
        // behaviour before this existed.
        assertFalse(CoreVocabulary.isUngraded("the", "ko"))
    }

    @Test fun halvesOfAHyphenatedCompoundAreNotWords() {
        val counts = VocabStore.offListContentWords(listOf(
            "We talked non-stop about my sublet, a self-aware chore list."), "en")
        assertFalse(counts.toString(), "non" in counts)
        assertFalse(counts.toString(), "aware" in counts && "self" in counts)
        assertTrue(counts.toString(), "sublet" in counts)
        assertTrue(counts.toString(), "chore" in counts)
    }
}
