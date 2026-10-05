package com.roro.futurevoice

import com.roro.futurevoice.data.VocabStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Save to expressions" is a BOOKMARK (iOS `addExpression`, 2026-09-21): it
 * may leave a zero-count row so the phrase is listed, but it is never a
 * "known" verdict and never evidence of use — so it can't tick a book.
 */
class ExpressionBookmarkTest {
    private val now = 1_700_000_000_000L

    @Test fun bookmarkOnANewPhraseLeavesAZeroCountRow() {
        val row = VocabStore.bookmarkedExpressionRecord(null, now)!!
        assertEquals("used", row.state)
        assertEquals(0, row.count)
        assertFalse(VocabStore.isMasteredExpression(row))
    }

    @Test fun bookmarkNeverRewritesAnExistingRow() {
        val known = VocabStore.Record("known", now - 1000, now - 1000, 0)
        val said = VocabStore.Record("used", now - 1000, now - 1000, 3)
        assertNull(VocabStore.bookmarkedExpressionRecord(known, now))
        assertNull(VocabStore.bookmarkedExpressionRecord(said, now))
    }

    @Test fun onlyEvidenceMastersAnExpression() {
        assertFalse(VocabStore.isMasteredExpression(null))
        assertTrue(VocabStore.isMasteredExpression(VocabStore.Record("known", now, now, 0)))
        assertTrue(VocabStore.isMasteredExpression(VocabStore.Record("used", now, now, 1)))
    }
}
