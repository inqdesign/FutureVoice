package com.roro.futurevoice.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * "Something on disk changed" — a revision counter screens collect so a list
 * rendered from a store redraws when a background job (the summary) writes
 * to it after the screen is already showing.
 */
object StoreEvents {
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision

    /** [fromSync] is the Drive sync laying a pull down: screens redraw, but
     *  it must not ask the sync to push what it just pulled. */
    fun bump(fromSync: Boolean = false) {
        _revision.update { it + 1 }
        if (!fromSync) com.roro.futurevoice.sync.SyncEngine.noteChanged()
    }
}
