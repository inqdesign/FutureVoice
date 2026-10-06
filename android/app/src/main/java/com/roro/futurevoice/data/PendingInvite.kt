package com.roro.futurevoice.data

import android.content.Context

/**
 * An invite code typed on the Welcome screen BEFORE there is an account (iOS
 * `AuthService.pendingInviteKey`). Redeeming needs an authenticated session,
 * so the code is held here and applied the moment an account owns one. The
 * account act shows it back — an invisible pending code reads as a lost one.
 */
object PendingInvite {
    private const val KEY = "futurevoice.pendingInviteCode"

    fun code(c: Context): String? =
        c.getSharedPreferences("futurevoice", 0).getString(KEY, null)
            ?.trim()?.uppercase()?.takeIf { it.isNotEmpty() }

    fun save(c: Context, raw: String) {
        val clean = raw.trim().uppercase()
        c.getSharedPreferences("futurevoice", 0).edit().apply {
            if (clean.isEmpty()) remove(KEY) else putString(KEY, clean)
        }.apply()
    }

    /**
     * Apply a held code once an account owns the session. A network blip
     * keeps it for the next attempt; a permanent refusal (invalid, self,
     * already redeemed) stops retrying. Returns what was granted, if anything.
     */
    suspend fun redeemIfAny(c: Context, auth: AuthRepository): com.roro.futurevoice.net.ReferralClient.Redeemed? {
        val code = code(c) ?: return null
        return try {
            com.roro.futurevoice.net.ReferralClient(auth).redeem(code).also { save(c, "") }
        } catch (e: com.roro.futurevoice.net.ReferralClient.RedeemFailure) {
            if (e.reason != com.roro.futurevoice.net.ReferralClient.RedeemError.UNKNOWN) save(c, "")
            null
        } catch (e: Exception) {
            null
        }
    }
}
