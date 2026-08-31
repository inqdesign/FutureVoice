package com.roro.futurevoice

import android.content.Intent
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // OAuth callback (futurevoice://login) lands here — singleTask means the
        // first delivery can arrive on the original intent.
        Supa.client.handleDeeplinks(intent)
        DailyCallInbox.deliver(intent)
        DeepLinkInbox.deliver(intent)
        setContent {
            FutureVoiceTheme {
                Surface(Modifier.fillMaxSize()) { RootScreen() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        AppUsageLog.begin()
    }

    override fun onPause() {
        super.onPause()
        AppUsageLog.end(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Supa.client.handleDeeplinks(intent)
        DailyCallInbox.deliver(intent)
        DeepLinkInbox.deliver(intent)
    }
}
