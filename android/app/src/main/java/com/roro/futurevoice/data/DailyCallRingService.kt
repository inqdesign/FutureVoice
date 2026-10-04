package com.roro.futurevoice.data

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.roro.futurevoice.R

/**
 * The daily call's ring, played on the ALARM stream so it rings through
 * silent mode — iOS gets that from AlarmKit (CLAUDE.md "The daily call":
 * "it's the only thing that rings through silent mode and Focus"). On
 * Android the notification's own sound is a RINGTONE-usage sound, which
 * silent and vibrate modes mute: measured on an A34 2026-10-04, the call
 * notification arrived in silent mode with no sound at all.
 *
 * A foreground service, because a receiver gets ~10 s and a ring outlives
 * that; the ring notification IS the service's notification, so answering,
 * declining or the 60 s cap all end the same way ([stop]). Alarms are
 * allowed through Do Not Disturb by default, which is the Focus half.
 */
class DailyCallRingService : Service() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = pending ?: run { stopSelf(); return START_NOT_STICKY }
        pending = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(DailyCallScheduler.RING_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else startForeground(DailyCallScheduler.RING_ID, n)
        runCatching {
            player?.release()
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                val afd = resources.openRawResourceFd(R.raw.ringtone)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                isLooping = true
                prepare()
                start()
            }
        }
        // A ring nobody answers stops making noise; the notification stays,
        // like a missed call, until it's answered, declined or settled.
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ silence() }, RING_MS)
        return START_NOT_STICKY
    }

    private fun silence() {
        player?.runCatching { stop(); release() }
        player = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        player?.runCatching { stop(); release() }
        player = null
        super.onDestroy()
    }

    companion object {
        private const val RING_MS = 60_000L
        @Volatile private var pending: Notification? = null

        /** Ring with sound through silent mode. False if the system refused
         *  the service (no exact-alarm exemption) — the caller falls back to
         *  the plain notification. */
        fun start(context: Context, n: Notification): Boolean = runCatching {
            pending = n
            val i = Intent(context, DailyCallRingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
            else context.startService(i)
        }.isSuccess

        fun stop(context: Context) {
            context.stopService(Intent(context, DailyCallRingService::class.java))
        }
    }
}
