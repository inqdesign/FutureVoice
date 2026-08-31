package com.roro.futurevoice.data

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Answering the daily call lands here; RootScreen presents the call from it. */
object DailyCallInbox {
    private val _answered = MutableStateFlow(0)
    val answered: StateFlow<Int> = _answered

    fun deliver(intent: Intent?) {
        if (intent?.getBooleanExtra(DailyCallScheduler.ANSWER_EXTRA, false) == true) {
            intent.removeExtra(DailyCallScheduler.ANSWER_EXTRA)
            _answered.value += 1
        }
    }
}
