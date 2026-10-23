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
 * earphones the output is put on the loudspeaker; wired earphones the system
 * picks itself, and Bluetooth (earbuds, a car) is named by [routeOutput].
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
        routeOutput(c)
    }

    /**
     * Where the call is heard. Reported 2026-10-23 from a tester driving to
     * work: with the car's Bluetooth connected and "earphone" picked, the
     * call came out of the phone. In communication mode Bluetooth is heard
     * only over its CALL link (SCO / LE audio), and on Android 12+ nothing
     * opens that link unless the app names the device — clearing the choice
     * leaves the earpiece. A wired headset needs nothing: the system picks it.
     * The "phone mic" choice keeps the old behaviour.
     */
    fun routeOutput(c: Context) {
        // Bluetooth first, and never by way of a cleared choice: the mic route
        // clears it, and clearing then naming the car again within a moment
        // drops the call link and rebuilds it under the opener.
        if (!com.roro.futurevoice.data.MicPreference.forcesBuiltInMic(c) && routeToBluetooth(c)) return
        com.roro.futurevoice.data.MicPreference.applyInputRoute(c)
        routeToSpeakerIfNothingWorn(c)
    }

    private val bluetoothCall = listOf(
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    )

    private fun routeToBluetooth(c: Context): Boolean {
        val am = manager(c) ?: return false
        val wired = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }
        if (wired) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = bluetoothCall.firstNotNullOfOrNull { type ->
                am.availableCommunicationDevices.firstOrNull { it.type == type }
            } ?: return false
            if (am.communicationDevice?.id == device.id) return true
            return runCatching { am.setCommunicationDevice(device) }.getOrDefault(false)
        }
        val sco = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        if (!sco) return false
        @Suppress("DEPRECATION")
        if (!am.isBluetoothScoOn) runCatching { am.startBluetoothSco(); am.isBluetoothScoOn = true }
        return true
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
            @Suppress("DEPRECATION")
            if (am.isBluetoothScoOn) runCatching { am.isBluetoothScoOn = false; am.stopBluetoothSco() }
        }
        runCatching { am.mode = AudioManager.MODE_NORMAL }
    }
}
