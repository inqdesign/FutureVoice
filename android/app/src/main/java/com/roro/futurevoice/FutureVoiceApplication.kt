package com.roro.futurevoice

import android.app.Application
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.data.CoreVocabulary

class FutureVoiceApplication : Application() {

    // Notifications and any other app-context string resolve here too.
    override fun attachBaseContext(base: android.content.Context) {
        super.attachBaseContext(com.roro.futurevoice.core.UILanguage.wrap(base))
    }
    override fun onCreate() {
        super.onCreate()
        com.roro.futurevoice.core.Analytics.start(this)
        com.roro.futurevoice.core.Telemetry.start(this)
        InstallSalt.init(this)
        CoreVocabulary.init(this)
        com.roro.futurevoice.data.WordClass.init(this)
        com.roro.futurevoice.data.SpeechSpeed.init(this)
        com.roro.futurevoice.talk.VoicePreset.init(this)
        com.roro.futurevoice.data.VoiceParking.init(this)
        com.roro.futurevoice.net.PublicIntroComposer.init(this)
        // Billing builds the Supabase client, whose HTTP stack pulls in
        // kotlin-reflect (via postgrest-kt) — seconds of class loading on a
        // slow device, and in onCreate that is a startup ANR (seen on the
        // emulator: "failed to complete startup"). Warm the client on a
        // worker; billing starts on the main thread once it exists.
        val app = this
        Thread({
            runCatching { com.roro.futurevoice.data.Supa.client }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                BillingService.shared(app).refresh()
            }
        }, "supabase-warmup").start()
        com.roro.futurevoice.widget.StudyWidgetRefresher.schedule(this)
        // Shadow scoring digit spell-out: the built-in English speller (the
        // launch target). ICU's RuleBasedNumberFormat is absent from the
        // public SDK jar; other languages keep digits un-spelled for now —
        // a token compared symmetrically on both sides, so scores stay fair.
    }
}
