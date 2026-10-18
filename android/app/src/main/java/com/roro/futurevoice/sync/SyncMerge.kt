package com.roro.futurevoice.sync

import kotlinx.serialization.json.JsonElement

/**
 * iOS `SyncMerge`: the four shapes every kind's rule is built from. Add a kind
 * by picking one, not by writing a fifth.
 */
object SyncMerge {
    /** Newest side wins, deletion included. Equal payloads keep the local
     *  bytes; ties go to the remote — deterministic on both devices. */
    fun lww(local: SyncSide?, remote: SyncSide): String? {
        if (local == null) return if (remote.deleted) null else remote.payload
        if (remote.deleted) return if (remote.at >= local.at) null else local.payload
        if (local.deleted) return if (remote.at >= local.at) remote.payload else null
        if (local.payload == remote.payload) return local.payload
        return if (remote.at >= local.at) remote.payload else local.payload
    }

    /** A remote deletion always deletes (a talk deleted is deleted, however
     *  much the other device reviewed its cards). Both present → combine. */
    fun tombstoneWins(local: SyncSide?, remote: SyncSide, combine: (String, String) -> String): String? {
        if (remote.deleted) return null
        val lp = local?.payload
        if (local == null || lp == null || local.deleted) return remote.payload
        val rp = remote.payload ?: return lp
        return if (lp == rp) lp else combine(lp, rp)
    }

    /** Both present → combine; a deletion wins only if newer than the other
     *  side's last change (a word re-bookmarked elsewhere comes back). */
    fun combineOrNewerDelete(local: SyncSide?, remote: SyncSide, combine: (String, String) -> String): String? {
        val lp = local?.payload
        if (local == null || lp == null || local.deleted) return if (remote.deleted) null else remote.payload
        if (remote.deleted) return if (remote.at >= local.at) null else lp
        val rp = remote.payload ?: return lp
        return if (lp == rp) lp else combine(lp, rp)
    }

    /** Never deletes; both present → combine. */
    fun union(local: SyncSide?, remote: SyncSide, combine: (String, String) -> String): String? {
        val lp = local?.payload
        if (local == null || lp == null || local.deleted) return if (remote.deleted) local?.payload else remote.payload
        val rp = remote.payload
        if (remote.deleted || rp == null) return lp
        return if (lp == rp) lp else combine(lp, rp)
    }

    /** Lifts a combine over parsed payloads. A payload that doesn't parse (a
     *  newer build's shape) yields the OTHER side rather than losing the item. */
    fun typed(f: (JsonElement, JsonElement) -> JsonElement): (String, String) -> String = { a, b ->
        val x = SyncCanonical.parse(a)
        val y = SyncCanonical.parse(b)
        when {
            x == null -> b
            y == null -> a
            else -> runCatching { SyncCanonical.canonical(f(x, y)) }.getOrDefault(b)
        }
    }
}
