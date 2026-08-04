package com.roro.futurevoice

import android.app.Application
import com.roro.futurevoice.core.InstallSalt

class FutureVoiceApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        InstallSalt.init(this)
    }
}
