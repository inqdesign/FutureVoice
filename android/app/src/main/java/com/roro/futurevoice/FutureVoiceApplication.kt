package com.roro.futurevoice

import android.app.Application
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.data.CoreVocabulary

class FutureVoiceApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        InstallSalt.init(this)
        CoreVocabulary.init(this)
        BillingService.shared(this).refresh()
        com.roro.futurevoice.widget.StudyWidgetRefresher.schedule(this)
        // Shadow scoring digit spell-out: the built-in English speller (the
        // launch target). ICU's RuleBasedNumberFormat is absent from the
        // public SDK jar; other languages keep digits un-spelled for now —
        // a token compared symmetrically on both sides, so scores stay fair.
    }
}
