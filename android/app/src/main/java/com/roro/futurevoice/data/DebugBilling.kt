package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.net.EdgeError
import java.time.LocalDate

/**
 * DEBUG-only stand-ins for the billing states nobody can reach on the dev
 * account without spending money: a spent free pool, a Light month used up, a
 * trial, a 402 on the next voice line, a wall in the middle of a call. Every
 * entry point checks [BuildConfig.DEBUG] first, so a release build never reads
 * these keys (and R8 drops the bodies).
 *
 * Set from adb, never from the UI:
 *
 *     am start -n com.roro.futurevoice/.MainActivity --es debugAccount lightspent
 *     am start -n … --es debug402 scene_cap_reached      (the next synthesis)
 *     am start -n … --es debugCallWall 6:insufficient_credits      (next call)
 *     am start -n … --es debugCallWall 3:insufficient_credits:silent
 *
 * `clear` removes a key. The fake call never opens the gateway or the mic and
 * is never saved or summarized: it stages two lines, then drives the SAME
 * wall path a real gateway wall takes (`TalkViewModel.handleWall`).
 */
object DebugBilling {
    private const val ACCOUNT = "futurevoice.debug.account"
    private const val NEXT_402 = "futurevoice.debug.next402"
    private const val CALL_WALL = "futurevoice.debug.callWall"

    @Volatile private var app: Context? = null

    fun init(context: Context) {
        if (BuildConfig.DEBUG) app = context.applicationContext
    }

    private fun prefs() = app?.getSharedPreferences("futurevoice", 0)

    /** Intent extras → keys (MainActivity onCreate / onNewIntent). */
    fun apply(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        val p = prefs() ?: return
        fun put(extra: String, key: String) {
            val v = intent.getStringExtra(extra) ?: return
            if (v == "clear") p.edit().remove(key).apply() else p.edit().putString(key, v).apply()
            BillingGate.invalidate()
        }
        put("debugAccount", ACCOUNT)
        put("debug402", NEXT_402)
        put("debugCallWall", CALL_WALL)
    }

    /** The staged account, read by `AccountStatus.load` in place of the server. */
    fun account(): AccountStatus? {
        if (!BuildConfig.DEBUG) return null
        val preset = prefs()?.getString(ACCOUNT, null) ?: return null
        return preset(preset)
    }

    internal fun preset(name: String): AccountStatus? {
        val end = LocalDate.now().plusDays(18).toString()
        val sale = setOf("light", "plus", "max")
        fun plan(id: String, cap: Int?, used: Int, scenesCap: Int, scenesUsed: Int,
                 status: String = "active", cancel: Boolean = false) = AccountStatus(
            planId = id, subscriptionStatus = status,
            monthlyCapSeconds = cap, secondsUsedPeriod = used,
            monthlyScenesCap = scenesCap, scenesUsedPeriod = scenesUsed,
            periodEnd = end, cancelAtPeriodEnd = cancel,
            trialEndsAt = if (status == "trialing") end else null,
            planMonthlySeconds = if (status == "trialing") 150 * 60 else cap,
            tiersOnSale = sale)
        return when (name) {
            // Free, with the first-call grant still in the pool.
            "free" -> AccountStatus(secondsBalance = 1200, freeScenesCap = 2, tiersOnSale = sale)
            // Free, pool spent — the hard paywall's account.
            "nosub" -> AccountStatus(secondsBalance = 0, freeScenesCap = 2, tiersOnSale = sale)
            // Free with minutes left but both free scenes spent.
            "freescenes" -> AccountStatus(secondsBalance = 1200, freeScenesUsed = 2,
                freeScenesCap = 2, tiersOnSale = sale)
            "light" -> plan("light_monthly", 150 * 60, 40 * 60, 10, 3)
            "lightspent" -> plan("light_monthly", 150 * 60, 150 * 60, 10, 10)
            "lightcancel" -> plan("light_monthly", 150 * 60, 150 * 60, 10, 10, cancel = true)
            "plus" -> plan("plus_monthly", 600 * 60, 120 * 60, 30, 4)
            "plusspent" -> plan("plus_monthly", 600 * 60, 600 * 60, 30, 30)
            "max" -> plan("max_monthly", 1500 * 60, 1500 * 60, 60, 60)
            "trial" -> plan("light_monthly", 35 * 60, 35 * 60, 2, 2, status = "trialing")
            // A grandfathered Plus row: entitled, no talk ceiling.
            "uncapped" -> plan("plus_monthly", null, 0, 60, 2)
            else -> null
        }
    }

    /** A staged 402 for the NEXT synthesis, consumed by the read. */
    fun consume402(): EdgeError? {
        if (!BuildConfig.DEBUG) return null
        val p = prefs() ?: return null
        val code = p.getString(NEXT_402, null) ?: return null
        p.edit().remove(NEXT_402).apply()
        // voice_parked rides on the spent-pool 402, exactly as the server sends it.
        return EdgeError.wall("{\"error\":\"${if (code == "voice_parked") "insufficient_credits" else code}\"}")
    }

    /** A staged mid-call wall for the NEXT call: seconds, gateway code, and
     *  whether the learner had spoken before it. Consumed by the read. */
    data class CallWall(val afterSeconds: Int, val code: String, val learnerSpoke: Boolean)

    fun consumeCallWall(): CallWall? {
        if (!BuildConfig.DEBUG) return null
        val p = prefs() ?: return null
        val raw = p.getString(CALL_WALL, null) ?: return null
        p.edit().remove(CALL_WALL).apply()
        val parts = raw.split(':')
        val secs = parts.getOrNull(0)?.toIntOrNull() ?: return null
        val code = parts.getOrNull(1) ?: "insufficient_credits"
        return CallWall(secs, code, learnerSpoke = parts.getOrNull(2) != "silent")
    }
}
