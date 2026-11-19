package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.flow.MutableStateFlow
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * The invite event's screens on a made-up account (iOS `InviteEventDemo`),
 * for looking at every state before the server has the event. DEBUG ONLY:
 * every entry point checks [BuildConfig.DEBUG] first, and the words it shows
 * (`invite-event-texts.json`, a copy of iOS `scripts/invite-event-texts.json`)
 * are an asset of the debug and capture builds alone, so a release build has
 * neither the switch nor the text.
 *
 * From adb (the debug app):
 *
 *     am start -n com.roro.futurevoice/.MainActivity --es inviteDemo invite
 *         invite | needsPlan | invited | claim | applied | auto | off
 *     am start -n … --es inviteDemo claim --es inviteDemoSheet claim
 *         about | claim        (raise a sheet at once)
 *
 * or Settings → Developer → Preview invite event. The state is held across
 * refreshes and launches until `off`.
 */
object InviteEventDemo {
    val phases = listOf("invite", "needsPlan", "invited", "claim", "applied", "auto")

    private const val PHASE_KEY = "futurevoice.debug.inviteDemoPhase"
    private const val TEXTS_ASSET = "invite-event-texts.json"

    /** A sheet the preview asked for ("about" / "claim"); the root raises it. */
    val sheet = MutableStateFlow<String?>(null)

    private fun held(context: Context): String? {
        if (!BuildConfig.DEBUG) return null
        return context.getSharedPreferences("futurevoice", 0).getString(PHASE_KEY, null)
            ?.takeIf { it != "off" }
    }

    fun isHeld(context: Context): Boolean = held(context) != null

    /** True when a preview state is held (and has just been put back). */
    fun reseedIfHeld(context: Context): Boolean {
        val phase = held(context) ?: return false
        seed(context, phase)
        return true
    }

    /** Intent extras → the preview (MainActivity onCreate / onNewIntent). */
    fun apply(intent: Intent?, context: Context) {
        if (!BuildConfig.DEBUG || intent == null) return
        intent.getStringExtra("inviteDemo")?.let { hold(context, it) }
        intent.getStringExtra("inviteDemoSheet")?.let { sheet.value = it }
    }

    /** Keeps a preview state across refreshes and launches; "off" ends it
     *  (the next refresh reads the server again). */
    fun hold(context: Context, phase: String) {
        if (!BuildConfig.DEBUG) return
        context.getSharedPreferences("futurevoice", 0).edit().putString(PHASE_KEY, phase).apply()
        if (phase == "off") InviteEvent.seedDemo(InviteEventState.off, null, null)
        else seed(context, phase)
    }

    /** Puts a made-up account in the shared state, so the real Settings page
     *  draws the banner for it. */
    fun seed(context: Context, phase: String) {
        if (!BuildConfig.DEBUG) return
        val texts = runCatching {
            context.assets.open(TEXTS_ASSET).bufferedReader().use { it.readText() }
        }.getOrNull()?.let { raw ->
            runCatching { InviteEventState.texts(Edge.json.parseToJsonElement(raw)) }.getOrNull()
        }.orEmpty()
        fun reward(status: String) = InviteEventState.Reward(
            id = UUID.randomUUID().toString(), role = "inviter", status = status, percent = 50, months = 1)
        val base = InviteEventState(
            enabled = true, announceVersion = 1, code = "K3MQ9F",
            renewsAt = Instant.now().plus(25, ChronoUnit.DAYS), texts = texts)
        val state = when (phase) {
            "needsPlan" -> base
            "invited" -> base.copy(invited = true)
            "claim" -> base.copy(canInvite = true, store = "google", googleProductId = "light_monthly",
                googleOfferId = "friend-50", claimable = UUID.randomUUID().toString(),
                rewards = listOf(reward("ready")))
            "applied" -> base.copy(canInvite = true, store = "google",
                rewards = listOf(reward("claimed"), reward("ready")))
            "auto" -> base.copy(canInvite = true, store = "stripe", rewards = listOf(reward("claimed")))
            else -> base.copy(canInvite = true, store = "google")
        }
        InviteEvent.seedDemo(state, offerPrice = "₩7,500", fullPrice = "₩15,000")
    }
}
