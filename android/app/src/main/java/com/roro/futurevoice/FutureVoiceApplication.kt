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
    }
}
