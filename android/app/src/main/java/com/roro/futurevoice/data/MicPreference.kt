package com.roro.futurevoice.data

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/**
 * Which mic records the learner when earphones are connected.
 *
 * Framed by SITUATION, not hardware, and honest in both directions: the
 * phone's mic really is the better microphone (wideband, multi-mic), and the
 * earphone's really does sound like a phone call. What the earphone buys is
 * POSITION — it is at the mouth wherever the phone ends up. Which matters
 * more depends on a fact the app cannot see, so it asks about that fact once.
 *
 * Asked ONCE, on the first mic use with a Bluetooth headset connected, then
 * it lives in Me → Voice. Not per session: the answer is the same the second
 * time, and Talk's whole story is one tap from tapping to talking.
 *
 * The VOICE CLONE is the exception and never asks — a clone must be built
 * from the best microphone in the room, so that flow forces the built-in one.
 */
object MicPreference {
    const val EARPHONE = "earphone"   // whatever they're wearing (default)
    const val PHONE = "phone"         // the phone's own mic, output stays in the earphones

    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.micPreference"
    private const val ASKED = "futurevoice.micPreference.asked"

    fun current(c: Context): String =
        c.getSharedPreferences(PREFS, 0).getString(KEY, EARPHONE) ?: EARPHONE

    /** The one thing the audio layer needs to know. */
    fun forcesBuiltInMic(c: Context) = current(c) == PHONE

    fun set(c: Context, value: String) {
        c.getSharedPreferences(PREFS, 0).edit().putString(KEY, value).putBoolean(ASKED, true).apply()
    }

    fun hasChosen(c: Context) = c.getSharedPreferences(PREFS, 0).getBoolean(ASKED, false)

    /** Only worth asking where the answer changes anything. */
    fun shouldAsk(c: Context): Boolean = !hasChosen(c) && headsetConnected(c)

    fun headsetConnected(c: Context): Boolean {
        val am = c.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        return am.getDevices(AudioManager.GET_DEVICES_INPUTS).any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }
    }

    /**
     * Route the INPUT. Android picks the headset mic on its own for a
     * communication recording, so only the "phone mic" choice needs saying —
     * and saying it must not move the OUTPUT, which stays in the earphones.
     */
    fun applyInputRoute(c: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val am = c.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (!forcesBuiltInMic(c)) { runCatching { am.clearCommunicationDevice() }; return }
        val builtIn = am.availableCommunicationDevices
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC } ?: return
        runCatching { am.setCommunicationDevice(builtIn) }
    }

    /** The clone's own recording: the best mic in the room, never a choice. */
    fun forceBuiltInForClone(c: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val am = c.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        am.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            ?.let { runCatching { am.setCommunicationDevice(it) } }
    }
}
