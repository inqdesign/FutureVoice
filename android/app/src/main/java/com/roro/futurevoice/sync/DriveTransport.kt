package com.roro.futurevoice.sync

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Google Drive REST v3 over the app's hidden folder (`appDataFolder`) — the
 * only file that sees Drive, as `CloudKitTransport` is the only one that sees
 * `CKRecord` on iOS.
 *
 * Shape on Drive: one folder per app account (`nawana-<userId>`) inside
 * appDataFolder, one FILE per record, named by the record name. Kind,
 * language, schema and the clocks ride in `appProperties` (each pair is
 * capped at 124 bytes, which these fit); the item's own key rides in
 * `description` because a key is a lemma in any script and can be long. The
 * file's CONTENT is the canonical payload (UTF-8 JSON), or the audio bytes
 * for a blob, or empty for a tombstone.
 *
 * Three Drive facts the engine is built around:
 * - **No conditional write.** Drive has no `ifServerRecordUnchanged`; a save
 *   just replaces. That is safe here because every pass PULLS before it
 *   pushes and every merge rule is commutative or newest-wins, so a write
 *   the other device made in between comes back through the merge on the
 *   next pull and the merged result is pushed again.
 * - **Change feed is per SPACE, not per folder.** `changes.list` with
 *   `spaces=appDataFolder` returns every change to the hidden space; the ones
 *   whose parent is not this account's folder are skipped.
 * - **A removed file arrives as an id only**, so `deleted` carries server ids
 *   and the engine maps them through the index.
 */
class DriveTransport(
    private val context: Context,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build(),
) : SyncTransport {

    private val api = "https://www.googleapis.com/drive/v3"
    private val upload = "https://www.googleapis.com/upload/drive/v3"
    private val jsonType = "application/json; charset=UTF-8".toMediaType()
    private val folderMime = "application/vnd.google-apps.folder"
    /** Drive's own guidance is a handful of parallel requests per user. */
    private val gate = Semaphore(6)

    @Volatile private var token: String? = null
    private val zoneIds = HashMap<String, String>()

    /** Downloads of audio follow this unless the learner tapped for a file. */
    @Volatile var allowsMeteredForBlobs: Boolean = false

    override suspend fun accountAvailable(): SyncAccountState =
        when (val o = DriveAuth.authorize(context)) {
            is DriveAuth.Outcome.Token -> { token = o.accessToken; SyncAccountState.AVAILABLE }
            is DriveAuth.Outcome.NeedsConsent, DriveAuth.Outcome.Denied -> SyncAccountState.NEEDS_CONSENT
            is DriveAuth.Outcome.Failed -> SyncAccountState.UNKNOWN
        }

    /** A screen that just ran the consent sheet hands the token over. */
    fun adopt(accessToken: String) { token = accessToken }

    // ── Zone (the account's folder) ─────────────────────────────────────

    private suspend fun findZone(zone: String): String? {
        zoneIds[zone]?.let { return it }
        val url = "$api/files".toHttpUrl().newBuilder()
            .addQueryParameter("spaces", "appDataFolder")
            .addQueryParameter("q", "name = '$zone' and mimeType = '$folderMime' and trashed = false")
            .addQueryParameter("fields", "files(id)")
            .build()
        val body = call(Request.Builder().url(url).get()).jsonObject
        val id = body["files"]?.jsonArray?.firstOrNull()?.jsonObject?.get("id")?.jsonPrimitive?.content
        if (id != null) zoneIds[zone] = id
        return id
    }

    private suspend fun zoneId(zone: String): String = findZone(zone) ?: throw SyncTransportError.ZoneMissing

    override suspend fun ensureZone(zone: String) {
        if (findZone(zone) != null) return
        val meta = buildJsonObject {
            put("name", zone)
            put("mimeType", folderMime)
            putJsonArray("parents") { add(kotlinx.serialization.json.JsonPrimitive("appDataFolder")) }
        }
        val created = call(Request.Builder().url("$api/files?fields=id")
            .post(meta.toString().toRequestBody(jsonType))).jsonObject
        zoneIds[zone] = created["id"]!!.jsonPrimitive.content
    }

    override suspend fun zoneExists(zone: String): Boolean = findZone(zone) != null

    override suspend fun deleteZone(zone: String) {
        val id = findZone(zone) ?: return
        callRaw(Request.Builder().url("$api/files/$id").delete()).close()
        zoneIds.remove(zone)
    }

    // ── Save ────────────────────────────────────────────────────────────

    override suspend fun save(records: List<SyncRecord>, zone: String): Map<String, SyncSaveOutcome> {
        val parent = zoneId(zone)
        return coroutineScope {
            records.map { r ->
                async {
                    gate.withPermit {
                        r.recordName to runCatching { SyncSaveOutcome.Saved(saveOne(r, parent)) as SyncSaveOutcome }
                            .getOrElse { e ->
                                when (e) {
                                    is SyncTransportError.ZoneMissing, is SyncTransportError.NotAuthorized,
                                    is SyncTransportError.Network -> throw e
                                    is SyncTransportError -> SyncSaveOutcome.Failed(e)
                                    else -> SyncSaveOutcome.Failed(SyncTransportError.Other(e.message ?: "save"))
                                }
                            }
                    }
                }
            }.awaitAll().toMap()
        }
    }

    private suspend fun saveOne(r: SyncRecord, parent: String): String {
        val meta = buildJsonObject {
            put("name", r.recordName)
            put("description", r.key)
            if (r.serverId == null) putJsonArray("parents") { add(kotlinx.serialization.json.JsonPrimitive(parent)) }
            putJsonObject("appProperties") {
                put("k", r.kind.raw)
                put("l", r.lang ?: "")
                put("s", r.schema.toString())
                put("m", r.modifiedAt.toString())
                put("d", r.deletedAt?.toString() ?: "")
                put("z", r.size.toString())
            }
        }
        val media: RequestBody = when {
            r.isTombstone -> ByteArray(0).toRequestBody(OCTET)
            r.asset != null -> r.asset.asRequestBody(OCTET)
            else -> (r.payload ?: "").toByteArray().toRequestBody(jsonType)
        }
        val big = (r.asset?.length() ?: 0L) > RESUMABLE_FROM
        val id = r.serverId
        return if (big) resumable(meta, media, id) else multipart(meta, media, id)
    }

    private suspend fun multipart(meta: JsonObject, media: RequestBody, id: String?): String {
        val body = MultipartBody.Builder().setType("multipart/related".toMediaType())
            .addPart(meta.toString().toRequestBody(jsonType))
            .addPart(media)
            .build()
        val req = if (id == null) Request.Builder().url("$upload/files?uploadType=multipart&fields=id").post(body)
                  else Request.Builder().url("$upload/files/$id?uploadType=multipart&fields=id").patch(body)
        return try {
            call(req).jsonObject["id"]!!.jsonPrimitive.content
        } catch (e: NotFound) {
            // The file this device remembered is gone (deleted elsewhere):
            // write it fresh rather than failing the record forever.
            if (id == null) throw SyncTransportError.ZoneMissing
            multipart(meta, media, null)
        }
    }

    private suspend fun resumable(meta: JsonObject, media: RequestBody, id: String?): String {
        val start = if (id == null) Request.Builder().url("$upload/files?uploadType=resumable&fields=id")
                        .post(meta.toString().toRequestBody(jsonType))
                    else Request.Builder().url("$upload/files/$id?uploadType=resumable&fields=id")
                        .patch(meta.toString().toRequestBody(jsonType))
        val location = callRaw(start).use { it.header("Location") }
            ?: throw SyncTransportError.Other("no upload location")
        return call(Request.Builder().url(location).put(media)).jsonObject["id"]!!.jsonPrimitive.content
    }

    // ── Changes ─────────────────────────────────────────────────────────

    private val fileFields = "id,name,description,appProperties,parents,trashed,size,modifiedTime"

    override suspend fun changes(zone: String, token: String?): SyncChangeBatch {
        val parent = zoneId(zone)
        return if (token == null) fullListing(parent) else changeFeed(parent, token)
    }

    /** First pull: the token is taken FIRST, so nothing written while the
     *  listing runs can fall between the two. */
    private suspend fun fullListing(parent: String): SyncChangeBatch {
        val start = call(Request.Builder().url("$api/changes/startPageToken?supportsAllDrives=false")
            .get()).jsonObject["startPageToken"]!!.jsonPrimitive.content
        val files = ArrayList<JsonObject>()
        var page: String? = null
        do {
            val url = "$api/files".toHttpUrl().newBuilder()
                .addQueryParameter("spaces", "appDataFolder")
                .addQueryParameter("q", "'$parent' in parents and trashed = false")
                .addQueryParameter("pageSize", "1000")
                .addQueryParameter("fields", "nextPageToken,files($fileFields)")
                .apply { page?.let { addQueryParameter("pageToken", it) } }
                .build()
            val body = call(Request.Builder().url(url).get()).jsonObject
            body["files"]?.jsonArray?.forEach { files.add(it.jsonObject) }
            page = body["nextPageToken"]?.jsonPrimitive?.content
        } while (page != null)
        return SyncChangeBatch(changed = materialize(dedupe(files)), token = start)
    }

    private suspend fun changeFeed(parent: String, token: String): SyncChangeBatch {
        val files = ArrayList<JsonObject>()
        val removed = ArrayList<String>()
        var page: String? = token
        var next: String? = null
        while (page != null) {
            val url = "$api/changes".toHttpUrl().newBuilder()
                .addQueryParameter("pageToken", page)
                .addQueryParameter("spaces", "appDataFolder")
                .addQueryParameter("pageSize", "1000")
                .addQueryParameter("fields", "nextPageToken,newStartPageToken,changes(fileId,removed,file($fileFields))")
                .build()
            val body = try { call(Request.Builder().url(url).get()).jsonObject }
                       catch (e: NotFound) { throw SyncTransportError.TokenExpired }
            for (c in body["changes"]?.jsonArray.orEmpty()) {
                val o = c.jsonObject
                val file = o["file"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.jsonObject
                val gone = o["removed"]?.jsonPrimitive?.content == "true" ||
                    file?.get("trashed")?.jsonPrimitive?.content == "true"
                if (gone) { o["fileId"]?.jsonPrimitive?.content?.let(removed::add); continue }
                if (file == null) continue
                val parents = file["parents"]?.jsonArray?.map { it.jsonPrimitive.content }.orEmpty()
                if (parent in parents) files.add(file)
            }
            page = body["nextPageToken"]?.jsonPrimitive?.content
            next = body["newStartPageToken"]?.jsonPrimitive?.content ?: next
        }
        return SyncChangeBatch(changed = materialize(dedupe(files)), deleted = removed, token = next ?: token)
    }

    /** Two devices that both created the same record before either pulled
     *  leave two files with one name. Keep the newest; remove the rest. */
    private suspend fun dedupe(files: List<JsonObject>): List<JsonObject> {
        val byName = files.groupBy { it["name"]?.jsonPrimitive?.content ?: "" }
        val keep = ArrayList<JsonObject>()
        for ((_, group) in byName) {
            val sorted = group.sortedByDescending { prop(it, "m")?.toLongOrNull() ?: 0L }
            keep.add(sorted.first())
            for (extra in sorted.drop(1)) {
                runCatching { callRaw(Request.Builder().url("$api/files/${id(extra)}").delete()).close() }
            }
        }
        return keep
    }

    /** Turns file metadata into records, downloading item payloads (small)
     *  and leaving blobs' bytes on the server. */
    private suspend fun materialize(files: List<JsonObject>): List<SyncRecord> = coroutineScope {
        files.mapNotNull { f -> recordShell(f)?.let { f to it } }.map { (f, shell) ->
            async {
                if (shell.kind.isBlob || shell.isTombstone) shell
                // A file deleted while the listing ran is simply gone; any
                // other failure aborts the pull, so the change token never
                // moves past an item that was not applied.
                else gate.withPermit {
                    try { shell.copy(payload = String(download(id(f)))) } catch (_: NotFound) { null }
                }
            }
        }.awaitAll().filterNotNull()
    }

    private fun recordShell(f: JsonObject): SyncRecord? {
        val kind = SyncKind.of(prop(f, "k") ?: return null) ?: return null
        val key = f["description"]?.jsonPrimitive?.content ?: return null
        return SyncRecord(
            kind = kind, key = key,
            lang = prop(f, "l")?.takeIf { it.isNotEmpty() },
            size = prop(f, "z")?.toLongOrNull() ?: 0L,
            schema = prop(f, "s")?.toIntOrNull() ?: SyncSchema.VERSION,
            modifiedAt = prop(f, "m")?.toLongOrNull() ?: 0L,
            deletedAt = prop(f, "d")?.takeIf { it.isNotEmpty() }?.toLongOrNull(),
            serverId = id(f),
        )
    }

    // ── Fetch (blobs) ───────────────────────────────────────────────────

    override suspend fun fetch(records: List<SyncIndex.Entry>, zone: String): Map<String, SyncRecord> = coroutineScope {
        records.filter { it.serverId != null }.map { e ->
            async {
                gate.withPermit {
                    runCatching {
                        val tmp = File.createTempFile("sync", ".blob", context.cacheDir)
                        callRaw(Request.Builder().url("$api/files/${e.serverId}?alt=media").get()).use { resp ->
                            resp.body.byteStream().use { input -> tmp.outputStream().use { input.copyTo(it) } }
                        }
                        e.recordName to SyncRecord(kind = e.syncKind!!, key = e.key, lang = e.lang,
                            asset = tmp, size = tmp.length(), modifiedAt = e.observedAt, serverId = e.serverId)
                    }.getOrElse { err -> if (err is NotFound) null else throw err }
                }
            }
        }.awaitAll().filterNotNull().toMap()
    }

    // ── HTTP ────────────────────────────────────────────────────────────

    private class NotFound : IOException("not found")

    private suspend fun download(id: String): ByteArray =
        callRaw(Request.Builder().url("$api/files/$id?alt=media").get()).use { it.body.bytes() }

    private suspend fun call(b: Request.Builder): kotlinx.serialization.json.JsonElement =
        callRaw(b).use { SyncCanonical.json.parseToJsonElement(it.body.string().ifEmpty { "{}" }) }

    /** One request with the current token; a 401 re-authorizes once. */
    private suspend fun callRaw(b: Request.Builder, retried: Boolean = false): Response = withContext(Dispatchers.IO) {
        val t = token ?: refreshToken()
        val resp = try {
            http.newCall(b.header("Authorization", "Bearer $t").build()).execute()
        } catch (e: IOException) {
            throw SyncTransportError.Network
        }
        if (resp.isSuccessful) return@withContext resp
        val text = runCatching { resp.body.string() }.getOrDefault("")
        resp.close()
        when (resp.code) {
            401 -> {
                if (retried) throw SyncTransportError.NotAuthorized
                token = null
                return@withContext callRaw(b, retried = true)
            }
            404 -> throw NotFound()
            410 -> throw SyncTransportError.TokenExpired
            429 -> throw SyncTransportError.RateLimited(resp.header("Retry-After")?.toLongOrNull() ?: 30)
            403 -> throw when {
                "storageQuotaExceeded" in text || "quotaExceeded" in text && "storage" in text ->
                    SyncTransportError.QuotaExceeded
                "RateLimitExceeded" in text || "rateLimitExceeded" in text ->
                    SyncTransportError.RateLimited(30)
                "insufficientPermissions" in text || "ACCESS_TOKEN_SCOPE_INSUFFICIENT" in text ->
                    SyncTransportError.NotAuthorized
                else -> SyncTransportError.Other("drive 403")
            }
            in 500..599 -> throw SyncTransportError.Network
            else -> throw SyncTransportError.Other("drive ${resp.code}")
        }
    }

    private suspend fun refreshToken(): String =
        when (val o = DriveAuth.authorize(context)) {
            is DriveAuth.Outcome.Token -> o.accessToken.also { token = it }
            is DriveAuth.Outcome.NeedsConsent, DriveAuth.Outcome.Denied -> throw SyncTransportError.NotAuthorized
            is DriveAuth.Outcome.Failed -> throw SyncTransportError.Network
        }

    private fun id(f: JsonObject) = f["id"]!!.jsonPrimitive.content
    private fun prop(f: JsonObject, k: String) =
        (f["appProperties"] as? JsonObject)?.get(k)?.jsonPrimitive?.content

    companion object {
        private val OCTET = "application/octet-stream".toMediaType()
        /** Drive's simple/multipart upload is for files up to 5 MB. */
        private const val RESUMABLE_FROM = 4L * 1024 * 1024
    }
}
