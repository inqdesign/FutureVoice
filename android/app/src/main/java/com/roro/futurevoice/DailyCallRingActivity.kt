package com.roro.futurevoice

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.data.DailyCallScheduler
import com.roro.futurevoice.data.DailyCallStore
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first

/**
 * The daily call ringing on a dark or locked screen — the full-screen intent
 * of the ring notification. It used to BE the answer: the system fires a
 * full-screen intent the moment the screen is off, so a locked phone opened
 * the call by itself, the fluent self started talking and the mic was live
 * with nobody holding the phone (found on an emulator, 2026-10-08).
 *
 * iOS rings an AlarmKit alert: the caller's name, Decline and Answer, and
 * nothing happens until one is pressed. This is that screen. Answer goes
 * through the same door as the notification's Answer (MainActivity with
 * [DailyCallScheduler.ANSWER_EXTRA]); on a secure lock screen the learner
 * unlocks first, as a phone app's answer does. Decline is the decline
 * receiver's work, and the app never opens for a no.
 */
class DailyCallRingActivity : ComponentActivity() {

    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(com.roro.futurevoice.core.UILanguage.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        // Always dark, whatever the app's appearance: light bar icons.
        val clear = android.graphics.Color.TRANSPARENT
        enableEdgeToEdge(
            statusBarStyle = androidx.activity.SystemBarStyle.dark(clear),
            navigationBarStyle = androidx.activity.SystemBarStyle.dark(clear),
        )
        val caller = getString(R.string.your_future_self)
        val app = getString(R.string.app_name)
        setContent {
            // Answered or declined somewhere else (the notification shade):
            // this screen has nothing left to ask.
            LaunchedEffect(Unit) {
                DailyCallScheduler.ringEnded.drop(1).first()
                finish()
            }
            RingScreen(
                caller = caller,
                app = app,
                declineLabel = getString(R.string.can_t_talk_now),
                answerLabel = getString(R.string.answer),
                onDecline = ::decline,
                onAnswer = ::answer,
            )
        }
    }

    private fun decline() {
        DailyCallScheduler.dismissRing(this)
        DailyCallStore.onDeclined(this)
        com.roro.futurevoice.core.Analytics.capture("daily_call_declined")
        finish()
    }

    private fun answer() {
        val open = {
            startActivity(Intent(this, MainActivity::class.java)
                .putExtra(DailyCallScheduler.ANSWER_EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
        }
        val km = getSystemService(KeyguardManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && km?.isKeyguardLocked == true) {
            km.requestDismissKeyguard(this as Activity, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = open()
                // Cancelled unlock: keep ringing, the choice is still theirs.
            })
        } else open()
    }
}

@Composable
private fun RingScreen(
    caller: String,
    app: String,
    declineLabel: String,
    answerLabel: String,
    onDecline: () -> Unit,
    onAnswer: () -> Unit,
) {
    Box(
        Modifier.fillMaxSize().background(Color(0xFF1C1C1E)).safeDrawingPadding()
            .padding(horizontal = 24.dp, vertical = 48.dp),
    ) {
        Column(
            Modifier.align(Alignment.TopCenter).padding(top = 64.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(caller, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Normal,
                textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Text(app, color = Color.White.copy(alpha = 0.6f), fontSize = 17.sp)
        }
        Row(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = 24.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            RingButton(Icons.Filled.CallEnd, declineLabel, Color(0xFFFF3B30), onDecline)
            RingButton(Icons.Filled.Call, answerLabel, Color(0xFF34C759), onAnswer)
        }
    }
}

@Composable
private fun RingButton(icon: ImageVector, label: String, tint: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        FilledIconButton(
            onClick = onClick,
            modifier = Modifier.size(76.dp),
            shape = CircleShape,
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = tint,
                contentColor = Color.White),
        ) { Icon(icon, contentDescription = label, modifier = Modifier.size(34.dp)) }
        Spacer(Modifier.height(10.dp))
        Text(label, color = Color.White, fontSize = 15.sp)
    }
}
