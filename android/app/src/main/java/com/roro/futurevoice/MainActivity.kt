package com.roro.futurevoice

import android.content.Intent
import android.os.Bundle
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.roro.futurevoice.data.AppUsageLog
import com.roro.futurevoice.data.DailyCallInbox
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.Supa
import com.roro.futurevoice.ui.FutureVoiceTheme
import com.roro.futurevoice.ui.RootScreen
import io.github.jan.supabase.auth.handleDeeplinks

class MainActivity : ComponentActivity() {

    // The app's own screens follow the language the learner named as theirs.
    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(com.roro.futurevoice.core.UILanguage.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // OAuth callback (futurevoice://login) lands here — singleTask means the
        // first delivery can arrive on the original intent.
        Supa.client.handleDeeplinks(intent)
        DailyCallInbox.deliver(intent, this)
        DeepLinkInbox.deliver(intent)
        // Screenshot harness: only the `capture` build type answers; every
        // other build gets null and starts normally.
        val capture = com.roro.futurevoice.capture.CaptureRouter
            .content(this, intent.getStringExtra("capture"), intent.getStringExtra("lang"))
        if (capture != null) {
            setContent { FutureVoiceTheme { Surface(Modifier.fillMaxSize()) { capture() } } }
            return
        }
        setContent {
            FutureVoiceTheme {
                Surface(Modifier.fillMaxSize()) { RootScreen() }
                // Asks the server once per launch whether this build is
                // behind, and says so only when it is. Hosted beside the root
                // rather than inside it: the notice belongs to the app, not
                // to whichever tab happens to be open.
                com.roro.futurevoice.ui.UpdateGate()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // An untouched ring can't be noticed when it happens — nothing runs.
        com.roro.futurevoice.data.DailyCallStore.settleIfRangOut(this)
        // The routine's own reminders, rebuilt so a past week never lingers.
        com.roro.futurevoice.data.PlanReminder.reschedule(this)
        // Has this phone's voice been PARKED since? Learned here, acted on at
        // the next metered tap (`VoiceRevival`). Throttled inside.
        com.roro.futurevoice.data.VoiceParking.requestRecheck()
        // Friends who joined with my code since last time — polled here
        // because there is no push infrastructure.
        lifecycleScope.launch { com.roro.futurevoice.data.ReferralJoins.announce(this@MainActivity) }
        // A trial can start anywhere — an offer code, the store's own page, a
        // restore on another phone — so the notice is re-armed from what the
        // SERVER knows rather than only at the moment of purchase.
        lifecycleScope.launch {
            runCatching {
                val account = com.roro.futurevoice.data.AccountStatus.load(
                    com.roro.futurevoice.data.AuthRepository())
                com.roro.futurevoice.data.TrialReminder.rearm(
                    this@MainActivity, account.trialEndsAt, account.isTrialing)
            }
        }
        AppUsageLog.begin()
        // Settle yesterday's (and any unsettled past day's) card before the
        // 45-day logs can prune it — iOS `freezePastDays` on `.active`. Off
        // the main thread: it reads every enrolled language's talks.
        val app = applicationContext
        lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            runCatching { com.roro.futurevoice.data.DayCardStore.freezePastDays(app) }
        }
        // Widgets follow the app at its edges too — a drill or a talk minute
        // doesn't bump the store revision the refresher also listens to.
        com.roro.futurevoice.widget.StudyWidgetRefresher.schedule(this)
    }

    override fun onPause() {
        super.onPause()
        AppUsageLog.end(this)
        // The background edge refreshes NOW, not after the coalescing delay:
        // the process may be frozen right after this returns.
        val app = applicationContext
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            com.roro.futurevoice.widget.StudyWidgetRefresher.refresh(app)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Supa.client.handleDeeplinks(intent)
        DailyCallInbox.deliver(intent, this)
        DeepLinkInbox.deliver(intent)
    }
}
