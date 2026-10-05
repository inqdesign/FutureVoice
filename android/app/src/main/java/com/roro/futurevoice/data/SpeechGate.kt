package com.roro.futurevoice.data

/**
 * Writing new speech scripts is a Plus-and-up feature; the bundled script is
 * everyone's (iOS `SpeechGate.swift`, `d5566b32`). Read off the TIER on
 * purpose — which plan was bought, not a pool — so Max is included and a
 * Light or free account is not. The admin flag passes like everywhere.
 */
val AccountStatus.canWriteSpeechScripts: Boolean
    get() = unlimited || (isEntitled && tier in setOf("plus", "max"))

object SpeechGate {
    /** Same cache rule as the billing gate: a yes from cache, a no only from
     *  a fresh read (a purchase a minute ago must not be refused again). */
    suspend fun allowsSpeechScripts(auth: AuthRepository): Boolean {
        BillingGate.account?.let { if (it.canWriteSpeechScripts) return true }
        if (auth.userId == null) return false
        val fresh = runCatching { AccountStatus.load(auth) }.getOrNull() ?: return false
        BillingGate.remember(fresh)
        return fresh.canWriteSpeechScripts
    }

    /** The cached answer, for drawing (no network). */
    val cachedCanWrite: Boolean get() = BillingGate.account?.canWriteSpeechScripts ?: false
}
