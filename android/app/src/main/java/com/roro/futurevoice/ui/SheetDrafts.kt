package com.roro.futurevoice.ui

/**
 * What a learner typed into a sheet they closed without finishing — iOS
 * `SheetDrafts`. Reported by a tester: a tap outside a bottom sheet (or a
 * swipe down) threw the words away, because every input sheet held its text
 * in composition state.
 *
 * In memory only, on purpose: it keeps a draft across closing and reopening
 * the sheet, which is the complaint, without leaving half-written text on
 * disk for weeks. A draft is cleared the moment its sheet finishes (sent,
 * saved, started).
 */
object SheetDrafts {
    private val texts = mutableMapOf<String, String>()

    fun text(key: String): String? = texts[key]

    /** Blank text clears the draft — an emptied field is not a draft. */
    fun set(key: String, value: String) {
        if (value.isBlank()) texts.remove(key) else texts[key] = value
    }

    fun clear(vararg keys: String) { keys.forEach { texts.remove(it) } }
}
