package com.roro.futurevoice

import com.roro.futurevoice.data.LibraryBadge
import org.junit.Assert.assertEquals
import org.junit.Test

/** The row badge's state → glyph rule (iOS `WordsView.row`). */
class LibraryBadgeTest {
    @Test fun nothingIsNone() =
        assertEquals(LibraryBadge.NONE, LibraryBadge.of(studying = false, known = false, used = false))

    @Test fun aClaimIsAPlainCheck() =
        assertEquals(LibraryBadge.KNOWN, LibraryBadge.of(studying = false, known = true, used = false))

    @Test fun aTalkIsAFilledCheck() =
        assertEquals(LibraryBadge.USED, LibraryBadge.of(studying = false, known = true, used = true))

    @Test fun usedOutranksKnownEvenWithoutTheClaimFlag() =
        assertEquals(LibraryBadge.USED, LibraryBadge.of(studying = false, known = false, used = true))

    @Test fun theBookmarkWinsOnTheRow() {
        assertEquals(LibraryBadge.STUDYING, LibraryBadge.of(studying = true, known = true, used = true))
        assertEquals(LibraryBadge.STUDYING, LibraryBadge.of(studying = true, known = false, used = false))
    }
}
