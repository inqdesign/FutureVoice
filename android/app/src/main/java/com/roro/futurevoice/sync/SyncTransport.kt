package com.roro.futurevoice.sync

/**
 * iOS `SyncTransport`: everything the engine needs from the cloud, and
 * nothing Drive-shaped. [DriveTransport] is the only conformer that talks to
 * Google Drive; the tests run the whole engine against [InMemorySyncTransport].
 *
 * A "zone" is the account's own folder inside the app's hidden Drive space
 * (`nawana-<supabaseUserId>`), because one Google account can hold two app
 * accounts on a shared tablet, exactly like iOS's one-zone-per-account.
 */
interface SyncTransport {
    suspend fun accountAvailable(): SyncAccountState
    /** Creates the account's folder if it doesn't exist. Idempotent. */
    suspend fun ensureZone(zone: String)
    suspend fun zoneExists(zone: String): Boolean
    /** Deletes the folder and everything in it — "Delete from Google Drive". */
    suspend fun deleteZone(zone: String)
    /** Saves records. Outcomes keyed by record name. Drive has no
     *  conditional write, so there is no conflict outcome: the next pull
     *  merges whatever the other device wrote, and every rule converges. */
    suspend fun save(records: List<SyncRecord>, zone: String): Map<String, SyncSaveOutcome>
    /** Everything changed since [token] (null = from the beginning). Blob
     *  records come back WITHOUT their bytes. */
    suspend fun changes(zone: String, token: String?): SyncChangeBatch
    /** Full records including a blob's bytes (downloaded to a temp file the
     *  caller must move), keyed by record name; a name the server lacks is
     *  absent. */
    suspend fun fetch(records: List<SyncIndex.Entry>, zone: String): Map<String, SyncRecord>
}

enum class SyncAccountState { AVAILABLE, NO_ACCOUNT, NEEDS_CONSENT, UNKNOWN }

sealed interface SyncSaveOutcome {
    data class Saved(val serverId: String) : SyncSaveOutcome
    data class Failed(val error: SyncTransportError) : SyncSaveOutcome
}

data class SyncChangeBatch(
    val changed: List<SyncRecord> = emptyList(),
    /** Record names the server deleted outright (never by this app — it only
     *  writes tombstones — but a folder can be edited elsewhere). */
    val deleted: List<String> = emptyList(),
    val token: String? = null,
)

sealed class SyncTransportError(message: String) : Exception(message) {
    object TokenExpired : SyncTransportError("token expired")
    object ZoneMissing : SyncTransportError("zone missing")
    object QuotaExceeded : SyncTransportError("quota exceeded")
    class RateLimited(val seconds: Long) : SyncTransportError("rate limited")
    object Network : SyncTransportError("offline")
    /** The Google grant was revoked or never given. */
    object NotAuthorized : SyncTransportError("not authorized")
    class Other(message: String) : SyncTransportError(message)
}

/**
 * Two engines over one of these stand in for two devices in a test, as iOS
 * `InMemorySyncTransport` does. Test-only, used from one thread.
 */
class InMemorySyncTransport : SyncTransport {
    private val zones = HashMap<String, LinkedHashMap<String, SyncRecord>>()
    /** Monotone change counter per record — the change token is the counter. */
    private val changedAt = HashMap<String, Long>()
    private var clock = 0L
    private val blobs = HashMap<String, ByteArray>()
    /** Records saved so far — what the no-ping-pong test counts. */
    var saved = 0
        private set

    override suspend fun accountAvailable() = SyncAccountState.AVAILABLE
    override suspend fun ensureZone(zone: String) { zones.getOrPut(zone) { LinkedHashMap() } }
    override suspend fun zoneExists(zone: String) = zones.containsKey(zone)
    override suspend fun deleteZone(zone: String) { zones.remove(zone) }

    override suspend fun save(records: List<SyncRecord>, zone: String): Map<String, SyncSaveOutcome> {
        val z = zones[zone] ?: throw SyncTransportError.ZoneMissing
        val out = HashMap<String, SyncSaveOutcome>()
        for (r in records) {
            val name = r.recordName
            r.asset?.takeIf { it.exists() }?.let { blobs["$zone/$name"] = it.readBytes() }
            z[name] = r.copy(asset = null, serverId = name)
            changedAt["$zone/$name"] = ++clock
            saved++
            out[name] = SyncSaveOutcome.Saved(name)
        }
        return out
    }

    override suspend fun changes(zone: String, token: String?): SyncChangeBatch {
        val z = zones[zone] ?: throw SyncTransportError.ZoneMissing
        val since = token?.toLongOrNull() ?: 0L
        val changed = z.values.filter { (changedAt["$zone/${it.recordName}"] ?: 0) > since }
        return SyncChangeBatch(changed = changed, token = clock.toString())
    }

    override suspend fun fetch(records: List<SyncIndex.Entry>, zone: String): Map<String, SyncRecord> {
        val z = zones[zone] ?: throw SyncTransportError.ZoneMissing
        val out = HashMap<String, SyncRecord>()
        for (e in records) {
            val r = z[e.recordName] ?: continue
            val bytes = blobs["$zone/${e.recordName}"]
            val tmp = bytes?.let { b -> java.io.File.createTempFile("blob", null).apply { writeBytes(b) } }
            out[e.recordName] = r.copy(asset = tmp)
        }
        return out
    }
}
