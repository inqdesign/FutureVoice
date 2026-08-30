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

    fun bump() = _revision.update { it + 1 }
}
