package com.roro.futurevoice.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The routine widget's clock. iOS hands WidgetKit one timeline entry at every
 * block's start and end (and midnight), so the face changes with the app
 * closed; a Glance widget has no timeline, so one alarm waits for the next of
 * those moments, redraws the widget and arms the one after it. Nothing here
 * reads a store — only the snapshot the app wrote.
 */
object RoutineWidgetTicker {
    private const val REQUEST = 0x52_0000

    fun arm(context: Context, snapshot: RoutineWidgetSnapshot = RoutineWidgetStore.load(context),
            now: Long = System.currentTimeMillis()) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pi = pending(context)
        am.cancel(pi)
        val next = snapshot.edges(now).firstOrNull() ?: return
        // Inexact is enough: a face that turns a minute late is still right
        // about which block is on.
        runCatching { am.setAndAllowWhileIdle(AlarmManager.RTC, next, pi) }
    }

    private fun pending(context: Context): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST,
            Intent(context, RoutineWidgetTickReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
}

class RoutineWidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val done = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                runCatching { RoutineWidget().updateAll(app) }
                RoutineWidgetTicker.arm(app)
            } finally { done.finish() }
        }
    }
}
