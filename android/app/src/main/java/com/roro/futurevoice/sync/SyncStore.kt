package com.roro.futurevoice.sync

import android.content.Context

/**
 * iOS `SyncStore`: the sync's own settings, per APP ACCOUNT where it matters
 * (a shared tablet can hold two). Same keys as iOS, so a backup moved between
 * the two platforms means the same thing — though a backup never carries
 * them (sync state is per install, see `BackupService`).
 */
object SyncStore {
    private const val PREFS = "futurevoice"
    private fun p(c: Context) = c.getSharedPreferences(PREFS, 0)

    fun isEnabled(c: Context, userId: String) = p(c).getBoolean("futurevoice.sync.enabled.$userId", false)
    fun setEnabled(c: Context, userId: String, on: Boolean) =
        p(c).edit().putBoolean("futurevoice.sync.enabled.$userId", on).apply()

    /** "Continue from your other device?" asked once per account per install. */
    fun wasOffered(c: Context, userId: String) = p(c).getBoolean("futurevoice.sync.offered.$userId", false)
    fun setOffered(c: Context, userId: String) =
        p(c).edit().putBoolean("futurevoice.sync.offered.$userId", true).apply()

    /** Audio is the gigabyte; items are kilobytes. Off by default so a month
     *  of talks never goes out over mobile data unasked. */
    fun cellularForAudio(c: Context) = p(c).getBoolean("futurevoice.sync.cellularAudio", false)
    fun setCellularForAudio(c: Context, on: Boolean) =
        p(c).edit().putBoolean("futurevoice.sync.cellularAudio", on).apply()

    fun lastUser(c: Context): String? = p(c).getString("futurevoice.sync.lastUserId", null)
    fun setLastUser(c: Context, id: String?) = p(c).edit().putString("futurevoice.sync.lastUserId", id).apply()

    fun lastSyncAt(c: Context, userId: String?): Long? =
        userId?.let { p(c).getLong("futurevoice.sync.lastAt.$it", 0L).takeIf { v -> v > 0 } }
    fun setLastSyncAt(c: Context, userId: String?, at: Long) {
        userId ?: return
        p(c).edit().putLong("futurevoice.sync.lastAt.$userId", at).apply()
    }

    fun quotaHitAt(c: Context, userId: String): Long? =
        p(c).getLong("futurevoice.sync.quota.$userId", 0L).takeIf { it > 0 }
    fun setQuotaHitAt(c: Context, userId: String, at: Long?) {
        val e = p(c).edit()
        if (at == null) e.remove("futurevoice.sync.quota.$userId") else e.putLong("futurevoice.sync.quota.$userId", at)
        e.apply()
    }
}

/** What the engine needs to remember, behind an interface so the tests can
 *  run two engines as two devices without an Android context. */
interface SyncSettings {
    fun isEnabled(userId: String): Boolean
    fun setEnabled(userId: String, on: Boolean)
    fun lastUser(): String?
    fun setLastUser(id: String?)
    fun setLastSyncAt(userId: String, at: Long)
    fun quotaHitAt(userId: String): Long?
    fun setQuotaHitAt(userId: String, at: Long?)
}

class PrefsSyncSettings(private val c: Context) : SyncSettings {
    override fun isEnabled(userId: String) = SyncStore.isEnabled(c, userId)
    override fun setEnabled(userId: String, on: Boolean) = SyncStore.setEnabled(c, userId, on)
    override fun lastUser() = SyncStore.lastUser(c)
    override fun setLastUser(id: String?) = SyncStore.setLastUser(c, id)
    override fun setLastSyncAt(userId: String, at: Long) = SyncStore.setLastSyncAt(c, userId, at)
    override fun quotaHitAt(userId: String) = SyncStore.quotaHitAt(c, userId)
    override fun setQuotaHitAt(userId: String, at: Long?) = SyncStore.setQuotaHitAt(c, userId, at)
}
