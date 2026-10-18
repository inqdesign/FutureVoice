package com.roro.futurevoice.audio

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/**
 * The realtime call runs in the phone's COMMUNICATION mode, as iOS's call
 * runs on its voice-processing unit. Reported from two Galaxys (S23 Ultra,
 * a tester's phone): the fluent self's voice came back into the learner's
 * turn. The mic was already a VOICE_COMMUNICATION source with the echo
 * canceller on, but the reply played as MEDIA in normal mode — and the
 * canceller only subtracts what goes out on the call path, so on Samsung it
 * had nothing to cancel against.
 *
 * Communication mode sends that path to the EARPIECE by default, so with no
 * earphones the output is put on the loudspeaker; with earphones the system
 * picks them, and the learner's mic choice ([com.roro.futurevoice.data.MicPreference])
 * is left as it is.
 */
object CallAudioMode {
    private val worn = setOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_HEARING_AID,
    )

    private fun manager(c: Context) = c.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    fun enter(c: Context) {
        val am = manager(c) ?: return
        runCatching { am.mode = AudioManager.MODE_IN_COMMUNICATION }
        routeToSpeakerIfNothingWorn(c)
    }

    /** Again after anything that may have reset the communication device
     *  (the mic route clears it when no choice is forced). */
    fun routeToSpeakerIfNothingWorn(c: Context) {
        val am = manager(c) ?: return
        val wearing = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in worn }
        if (wearing) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.availableCommunicationDevices
                .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                ?.let { runCatching { am.setCommunicationDevice(it) } }
        } else {
            @Suppress("DEPRECATION")
            runCatching { am.isSpeakerphoneOn = true }
        }
    }

    fun exit(c: Context) {
        val am = manager(c) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching { am.clearCommunicationDevice() }
        } else {
            @Suppress("DEPRECATION")
            runCatching { am.isSpeakerphoneOn = false }
        }
        runCatching { am.mode = AudioManager.MODE_NORMAL }
    }
}
