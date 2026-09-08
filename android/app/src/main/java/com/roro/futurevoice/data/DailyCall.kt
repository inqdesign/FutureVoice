package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R
import java.util.Calendar

/**
 * The daily call — the habit anchor, Android half (`android-launch-roadmap`
 * §1.8). Unlike iOS, Android CAN draw a real incoming-call surface: an exact
 * alarm fires a BroadcastReceiver that posts a CATEGORY_CALL full-screen
 * notification ringing the SAME bundled two-tone warble iOS ships
 * (`res/raw/ringtone.wav` — never the learner's voice; the voice arrives the
 * moment they answer, which is what a phone call is anyway).
 *
 * v1: one time a day, Answer opens a free talk. Voicemail scripts, callbacks
 * and outcome history ride in with the VoicemailEngine brain-lift.
 */
object DailyCallStore {
    private const val PREFS = "futurevoice"
    private const val ENABLED = "futurevoice.dailyCall.enabled"
    private const val HOUR = "futurevoice.dailyCall.hour"
    private const val MINUTE = "futurevoice.dailyCall.minute"

    fun isEnabled(c: Context) = c.getSharedPreferences(PREFS, 0).getBoolean(ENABLED, false)
    fun hour(c: Context) = c.getSharedPreferences(PREFS, 0).getInt(HOUR, 8)
    fun minute(c: Context) = c.getSharedPreferences(PREFS, 0).getInt(MINUTE, 0)

    private const val SCRIPT = "futurevoice.dailyCall.script"

    /** Tomorrow's opening words, written at session end; cleared on answer. */
    fun script(c: Context): String? = c.getSharedPreferences(PREFS, 0).getString(SCRIPT, null)
    fun setScript(c: Context, script: String?) {
        c.getSharedPreferences(PREFS, 0).edit().putString(SCRIPT, script).apply()
    }

    fun set(c: Context, enabled: Boolean, hour: Int, minute: Int) {
        c.getSharedPreferences(PREFS, 0).edit()
            .putBoolean(ENABLED, enabled).putInt(HOUR, hour).putInt(MINUTE, minute).apply()
        if (enabled) DailyCallScheduler.schedule(c) else DailyCallScheduler.cancel(c)
    }
}

object DailyCallScheduler {
    const val CHANNEL_ID = "daily_call"
    const val ANSWER_EXTRA = "dailyCallAnswer"
    private const val REQUEST = 4801

    /** Arm the next occurrence of the chosen time (today if still ahead). */
    fun schedule(context: Context) {
        ensureChannel(context)
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, DailyCallStore.hour(context))
            set(Calendar.MINUTE, DailyCallStore.minute(context))
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // `setAlarmClock` rings through Doze and shows in the status bar,
        // which is what a call at a chosen time needs.
        //
        // It requires an exact-alarm permission, and WHICH one matters for
        // shipping: `USE_EXACT_ALARM` is granted without asking but Play
        // restricts it to alarm-clock, timer and calendar apps — a language
        // app declaring it gets the release rejected. So we hold
        // `SCHEDULE_EXACT_ALARM` instead, which the learner grants, and fall
        // back to an inexact window when they haven't.
        //
        // The fallback is not a degraded feature so much as a later one: the
        // system may drift the fire by minutes to batch it. A call that rings
        // at 08:04 is still the call; a call that never rings because the
        // permission was refused would be the app breaking over something the
        // learner never saw.
        if (canScheduleExact(am)) {
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(cal.timeInMillis, contentIntent(context)),
                firePendingIntent(context))
        } else {
            am.setWindow(
                AlarmManager.RTC_WAKEUP, cal.timeInMillis, INEXACT_WINDOW_MS,
                firePendingIntent(context))
        }
    }

    /** Whether an exact alarm can be armed right now. Always true below
     *  Android 12, where the permission did not exist. */
    fun canScheduleExact(
        am: AlarmManager? = null,
        context: Context? = null,
    ): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return true
        val manager = am ?: (context?.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)
        return manager?.canScheduleExactAlarms() == true
    }

    /** How far the system may drift an inexact call. Ten minutes: late enough
     *  for the OS to batch it with other work, early enough that the learner
     *  still reads it as "my 8 o'clock call". */
    private const val INEXACT_WINDOW_MS = 10L * 60 * 1000

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(firePendingIntent(context))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(REQUEST)
    }

    private fun firePendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST,
            Intent(context, DailyCallReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun contentIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(context, REQUEST,
            Intent(context, MainActivity::class.java).putExtra(ANSWER_EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val sound = Uri.parse("android.resource://${context.packageName}/${R.raw.ringtone}")
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Daily call", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(sound, AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            enableVibration(true)
        })
    }

    /** The ring: a call-style, full-screen, insistent notification. */
    fun ring(context: Context) {
        ensureChannel(context)
        val answer = contentIntent(context)
        val n: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(context.getString(R.string.your_future_self))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setFullScreenIntent(answer, true)
            .setOngoing(true)
            .setAutoCancel(true)
            .addAction(0, context.getString(R.string.answer), answer)
            .setContentIntent(answer)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(REQUEST, n)
        // Tomorrow's call arms the moment today's rings.
        if (DailyCallStore.isEnabled(context)) schedule(context)
    }
}

class DailyCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("DailyCall", "receiver fired")
        DailyCallScheduler.ring(context)
        android.util.Log.d("DailyCall", "ring posted")
    }
}
