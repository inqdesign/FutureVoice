package com.roro.futurevoice.sync

import android.content.Context
import com.roro.futurevoice.core.Analytics
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Keeps this device's practice and the learner's other devices' practice the
 * same, through their own Google Drive — opt-in, per app account. A port of
 * iOS `SyncEngine`, rule for rule; only the transport differs.
 *
 * Shape, in one paragraph: the stores stay exactly what they are (JSON files
 * rewritten whole); the engine DIFFS them against [SyncIndex] to find what
 * changed, pushes those items one record each, pulls the other devices'
 * records through one merge rule per kind ([SyncKindRegistry]), and lays the
 * merged set back into the file. Audio rides as file content, items first so
 * a second device is useful within a minute. A deletion is a tombstone
 * record, never a missing one, so the two sides can't resurrect each other's
 * deletions.
 *
 * The loop guard is in [apply]: the index is updated to the MERGED result
 * before the file is written, so the next diff sees nothing to push unless
 * the merge produced something the server doesn't have (`needsPush`).
 */
class SyncEngine(
    private val settings: SyncSettings,
    var transport: SyncTransport,
    private val registry: SyncRegistry,
    private val filesDir: File,
    /** Sync went on / off here — the app (re)arms or stops background work. */
    private val onEnabledChange: (Boolean) -> Unit = {},
    /** Whether audio may move now — Wi-Fi, or mobile data the learner allowed
     *  (iOS `SyncStore.cellularForAudio`). Items always move. */
    private val audioAllowed: () -> Boolean = { true },
    /** A pull's `onApplied` is delivered here (the main thread in the app). */
    private val deliver: suspend (() -> Unit) -> Unit = { withContext(Dispatchers.Main) { it() } },
) {
    sealed interface Status {
        data object Off : Status
        data object Idle : Status
        data object Syncing : Status
        data class Paused(val pause: Pause) : Status
        data class Failed(val reason: String) : Status
    }

    enum class Pause { NO_ACCOUNT, NEEDS_CONSENT, QUOTA_EXCEEDED, ZONE_MISSING, OFFLINE }

    data class Progress(val phase: Phase, val done: Int, val total: Int) {
        enum class Phase { PUSHING, PULLING, UPLOADING_AUDIO, DOWNLOADING_AUDIO }
    }

    enum class Scope { ITEMS, EVERYTHING }

    private val _status = MutableStateFlow<Status>(Status.Off)
    val status: StateFlow<Status> = _status
    private val _progress = MutableStateFlow<Progress?>(null)
    val progress: StateFlow<Progress?> = _progress
    private val _lastSyncAt = MutableStateFlow<Long?>(null)
    val lastSyncAt: StateFlow<Long?> = _lastSyncAt
    data class Counts(val items: Int = 0, val audioUp: Int = 0, val audioDown: Int = 0)
    private val _counts = MutableStateFlow(Counts())
    val counts: StateFlow<Counts> = _counts
    /** iOS `quotaFull`: what Drive refused for lack of space. */
    private val _quotaFull = MutableStateFlow<Boolean>(false)
    val quotaFull: StateFlow<Boolean> = _quotaFull

    /** Fired after a pull wrote files, with the kinds it touched. */
    var onApplied: ((Set<SyncKind>) -> Unit)? = null

    var userId: String? = null
        private set
    private var index: SyncIndex? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    /** Every pass, and every touch of the index outside one, is on this
     *  single thread — the main actor of the iOS engine. */
    private val lane = Dispatchers.IO.limitedParallelism(1)
    private var dirty = HashSet<SyncKind>()
    private var debounce: Job? = null
    private var running: Job? = null
    private var rerunRequested = false
    private var rerunScope = Scope.ITEMS
    private var forceRetry = false
    private var quotaHitAt: Long? = null
    private val requestedBlobs = ArrayList<String>()

    val zoneName: String? get() = userId?.let { "nawana-$it" }

    val isEnabled: Boolean get() = userId?.let { settings.isEnabled(it) } ?: false

    // ── Account ─────────────────────────────────────────────────────────

    /** The signed-in app account, or null (signed out / anonymous). */
    @Synchronized
    fun setUser(id: String?) {
        settings.setLastUser(id)
        if (id == userId) return
        running?.cancel(); running = null
        userId = id
        index = null
        dirty = HashSet()
        if (id == null || !settings.isEnabled(id)) { _status.value = Status.Off; return }
        index = SyncIndex(SyncIndex.directory(filesDir, id))
        _status.value = Status.Idle
        loadQuota()
        refreshCounts()
        requestSync(null)
    }

    /** A background launch has no auth observer yet. */
    fun restoreLastUserIfNeeded() {
        if (userId == null) settings.lastUser()?.let { setUser(it) }
    }

    /** Whether the account already has practice in Drive — the second
     *  device's question. Null when it can't be answered without asking. */
    suspend fun cloudHasData(): Boolean? {
        val zone = zoneName ?: return null
        if (transport.accountAvailable() != SyncAccountState.AVAILABLE) return null
        return runCatching { transport.zoneExists(zone) }.getOrNull()
    }

    // ── Enable / disable ────────────────────────────────────────────────

    class EnableError(val reason: Reason, message: String? = null) : Exception(message ?: reason.name) {
        enum class Reason { NOT_SIGNED_IN, NEEDS_CONSENT, NO_ACCOUNT, TRANSPORT }
    }

    /** Turns sync on: creates the folder, then runs the first ITEMS pass —
     *  the caller's screen is waiting — and leaves audio to a pass nobody
     *  waits on. Resumable: a killed first pass picks up on the next launch. */
    suspend fun enable() {
        val uid = userId ?: throw EnableError(EnableError.Reason.NOT_SIGNED_IN)
        val zone = zoneName!!
        when (transport.accountAvailable()) {
            SyncAccountState.AVAILABLE -> {}
            SyncAccountState.NEEDS_CONSENT -> throw EnableError(EnableError.Reason.NEEDS_CONSENT)
            else -> throw EnableError(EnableError.Reason.NO_ACCOUNT)
        }
        try { transport.ensureZone(zone) } catch (e: SyncTransportError) {
            throw EnableError(EnableError.Reason.TRANSPORT, describe(e))
        }
        settings.setEnabled(uid, true)
        withContext(lane) {
            index = SyncIndex(SyncIndex.directory(filesDir, uid))
            _status.value = Status.Idle
            loadQuota()
        }
        Analytics.capture("sync_enabled", mapOf("transport" to "drive"))
        syncAndWait(null, Scope.ITEMS)
        if (hasBackgroundWork()) requestSync(null)
        onEnabledChange(true)
    }

    /** Stops syncing. Nothing is deleted anywhere. */
    @Synchronized
    fun disable() {
        val uid = userId ?: return
        running?.cancel(); running = null
        debounce?.cancel()
        settings.setEnabled(uid, false)
        index = null
        _status.value = Status.Off
        _progress.value = null
        onEnabledChange(false)
        Analytics.capture("sync_disabled")
    }

    /** Removes the account's folder — every synced record and file. Local
     *  data is untouched; other devices notice (`ZoneMissing`) and switch
     *  themselves off. */
    suspend fun deleteFromCloud() {
        val zone = zoneName ?: return
        val uid = userId
        disable()
        transport.deleteZone(zone)
        if (uid != null) SyncIndex(SyncIndex.directory(filesDir, uid)).removeAll()
        Analytics.capture("sync_deleted_cloud")
    }

    // ── Triggers ────────────────────────────────────────────────────────

    /** A store's write funnel calls this; a forgotten hook self-heals,
     *  because the foreground pass diffs everything anyway. */
    @Synchronized
    fun markDirty(kind: SyncKind) {
        if (!isEnabled) return
        dirty.add(kind)
        debounce?.cancel()
        debounce = scope.launch {
            delay(DEBOUNCE_MS)
            val kinds: Set<SyncKind>
            synchronized(this@SyncEngine) { kinds = dirty; dirty = HashSet() }
            requestSync(kinds)
        }
    }

    @Synchronized
    fun markDirtyAll() {
        if (!isEnabled) return
        debounce?.cancel()
        debounce = scope.launch {
            delay(DEBOUNCE_MS)
            synchronized(this@SyncEngine) { dirty = HashSet() }
            requestSync(null)
        }
    }

    fun foregrounded() { if (isEnabled) requestSync(null) }

    @Synchronized
    fun backgrounded() {
        if (!isEnabled || dirty.isEmpty()) return
        debounce?.cancel()
        val kinds = dirty; dirty = HashSet()
        requestSync(kinds)
    }

    /** "Sync now" in settings — retries even inside the quota backoff. */
    fun syncNow() { if (isEnabled) { forceRetry = true; requestSync(null) } }

    /** One pass at a time; a request during a pass runs once more after it. */
    @Synchronized
    fun requestSync(kinds: Set<SyncKind>?, scope: Scope = Scope.EVERYTHING) {
        if (!isEnabled) return
        if (running != null) {
            rerunRequested = true
            if (scope == Scope.EVERYTHING) rerunScope = Scope.EVERYTHING
            kinds?.let { dirty.addAll(it) }
            return
        }
        running = this.scope.launch(lane) {
            runSync(kinds, scope)
            SyncIndex.flush()
            val again: Pair<Set<SyncKind>?, Scope>?
            synchronized(this@SyncEngine) {
                running = null
                again = if (rerunRequested) {
                    rerunRequested = false
                    val more = dirty; dirty = HashSet()
                    val s = rerunScope; rerunScope = Scope.ITEMS
                    (more.ifEmpty { null }) to s
                } else null
            }
            again?.let { requestSync(it.first, it.second) }
        }
    }

    suspend fun syncAndWait(kinds: Set<SyncKind>?, scope: Scope = Scope.EVERYTHING) {
        requestSync(kinds, scope)
        waitUntilIdle()
    }

    suspend fun waitUntilIdle() {
        while (true) { (synchronized(this) { running } ?: return).join() }
    }

    fun cancelRunning() { synchronized(this) { running }?.cancel() }

    fun hasBackgroundWork(): Boolean {
        refreshCounts()
        val c = _counts.value
        return c.items + c.audioUp + c.audioDown > 0
    }

    // ── The pass ────────────────────────────────────────────────────────

    /** pull → push (items) → push audio → fetch wanted audio. */
    suspend fun runSync(kinds: Set<SyncKind>?, scope: Scope = Scope.EVERYTHING) {
        val index = index ?: return
        val zone = zoneName ?: return
        when (transport.accountAvailable()) {
            SyncAccountState.AVAILABLE -> {}
            SyncAccountState.NEEDS_CONSENT -> { _status.value = Status.Paused(Pause.NEEDS_CONSENT); return }
            else -> { _status.value = Status.Paused(Pause.OFFLINE); return }
        }
        _status.value = Status.Syncing
        val holding = quotaHolds()
        try {
            pull(index, zone)
            val itemKinds = (kinds ?: SyncKind.entries.toSet()).filter { !it.isBlob }.toSet()
            if (!holding) push(itemKinds, index, zone)
            if (scope == Scope.EVERYTHING && audioAllowed()) {
                if (!holding) {
                    val blobKinds = (kinds ?: SyncKind.entries.toSet()).filter { it.isBlob }.toSet()
                    push(blobKinds, index, zone)
                    clearQuota()
                }
                downloadWanted(index, zone)
            }
            index.save()
            _lastSyncAt.value = System.currentTimeMillis()
            userId?.let { settings.setLastSyncAt(it, _lastSyncAt.value!!) }
            _status.value = if (_quotaFull.value) Status.Paused(Pause.QUOTA_EXCEEDED) else Status.Idle
        } catch (e: CancellationException) {
            index.save()
            _status.value = Status.Idle
            throw e
        } catch (e: SyncTransportError.QuotaExceeded) {
            index.save()
            noteQuota()
            _status.value = Status.Paused(Pause.QUOTA_EXCEEDED)
        } catch (e: SyncTransportError) {
            index.save()
            handle(e)
        } catch (e: Exception) {
            index.save()
            _status.value = Status.Failed(e.message ?: e.javaClass.simpleName)
            Analytics.capture("sync_error", mapOf("reason" to (e.message ?: e.javaClass.simpleName)))
        } finally {
            _progress.value = null
            refreshCounts()
            forceRetry = false
        }
    }

    private fun handle(e: SyncTransportError) {
        when (e) {
            SyncTransportError.ZoneMissing -> {
                // Deleted from another device: stop, forget the server, keep
                // every local file.
                index?.forgetServer()
                userId?.let { settings.setEnabled(it, false) }
                index = null
                _status.value = Status.Paused(Pause.ZONE_MISSING)
            }
            SyncTransportError.Network -> _status.value = Status.Paused(Pause.OFFLINE)
            SyncTransportError.NotAuthorized -> _status.value = Status.Paused(Pause.NEEDS_CONSENT)
            is SyncTransportError.RateLimited -> {
                _status.value = Status.Idle
                scope.launch { delay(e.seconds * 1000); requestSync(null) }
            }
            SyncTransportError.TokenExpired -> {
                index?.let { it.state = it.state.copy(changeToken = null); it.save() }
                _status.value = Status.Idle
                scope.launch { requestSync(null) }
            }
            SyncTransportError.QuotaExceeded -> _status.value = Status.Paused(Pause.QUOTA_EXCEEDED)
            is SyncTransportError.Other -> _status.value = Status.Failed(describe(e))
        }
        Analytics.capture("sync_error", mapOf("reason" to describe(e)))
    }

    // ── Pull ────────────────────────────────────────────────────────────

    private suspend fun pull(index: SyncIndex, zone: String) {
        _progress.value = Progress(Progress.Phase.PULLING, 0, 0)
        val batch = try {
            transport.changes(zone, index.state.changeToken)
        } catch (e: SyncTransportError.TokenExpired) {
            index.state = index.state.copy(changeToken = null)
            transport.changes(zone, null)
        }
        coroutineContextActive()

        // Files the server lost outright (never by this app): the index
        // forgets their handles so a re-push writes a fresh file.
        if (batch.deleted.isNotEmpty()) {
            val gone = batch.deleted.toSet()
            for (e in index.all()) if (e.serverId in gone) {
                e.serverId = null; e.pushedAt = null; e.needsPush = !e.isDeleted
                index.put(e)
            }
        }

        val groups = batch.changed.groupBy { "${it.kind.raw}|${it.lang ?: ""}" }
        val applied = HashSet<SyncKind>()
        val cascades = ArrayList<SyncCascade>()
        var skipped = false
        val now = System.currentTimeMillis()
        for (handler in registry.all()) {
            for (groupKey in groups.keys.filter { it.startsWith(handler.kind.raw + "|") }.sorted()) {
                val records = groups[groupKey] ?: continue
                val lang = records.first().lang
                if (handler.kind.isBlob) { applyBlobChanges(records, handler as BlobKind, index, now); continue }
                val local = handler.read(lang)
                if (local == null) { skipped = true; continue }
                val outcome = apply(records, local, handler, lang, index, now)
                if (outcome.first) applied.add(handler.kind)
                cascades += outcome.second
            }
        }
        for (c in cascades) run(c, index)
        index.state = index.state.copy(
            changeToken = if (skipped) index.state.changeToken else batch.token,
            lastPullAt = now)
        index.save()
        if (applied.isNotEmpty()) {
            onApplied?.let { cb -> deliver { cb(applied) } }
            Analytics.capture("sync_pull", mapOf("records" to batch.changed.size, "kinds" to applied.size))
        }
    }

    /** Merges one (kind, lang) group into the local file. The index entry is
     *  written BEFORE the file — see the class note. */
    private fun apply(records: List<SyncRecord>, local: Map<String, String>, handler: SyncKindHandler,
                      lang: String?, index: SyncIndex, now: Long): Pair<Boolean, List<SyncCascade>> {
        val merged = HashMap<String, SyncItem>()
        for ((key, payload) in local) {
            merged[key] = SyncItem(payload, index.entry(handler.kind, lang, key)?.observedAt ?: now)
        }
        var wrote = false
        val cascades = ArrayList<SyncCascade>()
        for (record in records) {
            val key = record.key
            val previous = local[key]
            val existing = index.entry(handler.kind, lang, key)
            // Edited HERE since the index last looked: newer than anything the
            // server can hand back (iOS 2026-09-29, the summary that a stale
            // draft overwrote).
            val editedHere = previous?.let { p ->
                existing?.let { it.isDeleted || it.hash != SyncCanonical.sha256(p) } ?: true
            } ?: false
            val localAt = if (editedHere) now else (existing?.observedAt ?: now)
            val localSide = previous?.let { SyncSide(it, localAt, false) }
                ?: existing?.takeIf { it.isDeleted }?.let { SyncSide(null, it.deletedAt ?: 0L, true) }
            val remoteSide = SyncSide(record.payload, record.deletedAt ?: record.modifiedAt, record.isTombstone)
            val frozen = record.schema > SyncSchema.VERSION
            val result = handler.merge(localSide, remoteSide)
            val matchesServer = if (record.isTombstone) result == null else result == record.payload
            index.put(SyncIndex.Entry(
                kind = handler.kind.raw, lang = lang, key = key,
                hash = result?.let(SyncCanonical::sha256) ?: "",
                observedAt = maxOf(localSide?.at ?: 0L, remoteSide.at),
                pushedAt = if (matchesServer) now else null,
                needsPush = !matchesServer && !frozen,
                deletedAt = if (result == null) (record.deletedAt ?: now) else null,
                serverId = record.serverId ?: existing?.serverId,
                frozen = frozen,
                size = record.size,
            ))
            if (result != null) {
                if (previous != result) {
                    merged[key] = SyncItem(result, maxOf(localSide?.at ?: 0L, remoteSide.at))
                    wrote = true
                }
            } else if (previous != null) {
                merged.remove(key)
                wrote = true
                cascades += handler.cascade(key, lang, previous)
            }
        }
        if (wrote) handler.write(merged, lang)
        return wrote to cascades
    }

    /** A blob's bytes never merge: a file this device has is the file; one
     *  it lacks is wanted; a tombstone removes it. */
    private fun applyBlobChanges(records: List<SyncRecord>, blob: BlobKind, index: SyncIndex, now: Long) {
        val local = blob.read(null) ?: emptyMap()
        for (record in records) {
            val key = record.key
            val entry = index.entry(blob.kind, null, key)
                ?: SyncIndex.Entry(kind = blob.kind.raw, key = key, hash = "", observedAt = now)
            entry.serverId = record.serverId ?: entry.serverId
            entry.size = record.size
            entry.needsPush = false
            entry.pushedAt = now
            when {
                record.isTombstone -> {
                    if (local[key] != null) blob.file(key).delete()
                    entry.deletedAt = record.deletedAt ?: now
                    entry.wanted = false
                    entry.hash = ""
                }
                local[key] != null -> {
                    entry.hash = local[key]!!
                    entry.deletedAt = null
                    entry.wanted = false
                }
                else -> {
                    entry.deletedAt = null
                    entry.wanted = true
                    // When the audio was made — the download queue is sorted
                    // on this so the newest talk's audio lands first.
                    entry.observedAt = record.modifiedAt
                }
            }
            index.put(entry)
        }
    }

    private fun run(cascade: SyncCascade, index: SyncIndex) {
        when (cascade) {
            is SyncCascade.SessionDeleted -> {
                val drill = registry.handler(SyncKind.DRILL)
                val cards = drill?.read(cascade.lang)
                if (drill != null && cards != null) {
                    val kept = HashMap<String, SyncItem>()
                    var removed = false
                    for ((key, payload) in cards) {
                        if (registry.cardSessionId(payload) == cascade.sessionId) { removed = true; continue }
                        kept[key] = SyncItem(payload, index.entry(SyncKind.DRILL, cascade.lang, key)?.observedAt
                            ?: System.currentTimeMillis())
                    }
                    if (removed) { drill.write(kept, cascade.lang); dirty.add(SyncKind.DRILL) }
                }
                registry.deleteTurnAudio(cascade.turnIds)
                if (cascade.turnIds.isNotEmpty()) dirty.add(SyncKind.BLOB_TURN)
            }
            is SyncCascade.DeleteFile -> {
                (registry.handler(cascade.kind) as? BlobKind)?.file(cascade.key)?.delete()
                dirty.add(cascade.kind)
            }
        }
    }

    // ── Push ────────────────────────────────────────────────────────────

    private suspend fun push(kinds: Set<SyncKind>, index: SyncIndex, zone: String) {
        val records = ArrayList<SyncRecord>()
        val now = System.currentTimeMillis()
        for (handler in registry.all().filter { it.kind in kinds }) {
            val langs: List<String?> = if (handler.kind.isLanguageScoped)
                (registry.enrolledLanguages() + index.languages(handler.kind)).toSortedSet().toList()
            else listOf(null)
            for (lang in langs) {
                coroutineContextActive()
                val snapshot = handler.read(lang) ?: continue
                diff(snapshot, handler, lang, index, now)
                for (entry in index.entries(handler.kind, lang)) {
                    if (!entry.needsPush || entry.frozen) continue
                    var record = SyncRecord(kind = handler.kind, key = entry.key, lang = entry.lang,
                        modifiedAt = entry.observedAt, deletedAt = entry.deletedAt, serverId = entry.serverId)
                    if (!entry.isDeleted) {
                        record = if (handler is BlobKind) {
                            val f = handler.file(entry.key)
                            record.copy(asset = f, size = f.length())
                        } else {
                            val payload = snapshot[entry.key] ?: continue
                            record.copy(payload = payload, size = payload.length.toLong())
                        }
                    }
                    records.add(record)
                }
            }
        }
        if (records.isEmpty()) return
        val blobs = records.first().kind.isBlob
        val phase = if (blobs) Progress.Phase.UPLOADING_AUDIO else Progress.Phase.PUSHING
        _progress.value = Progress(phase, 0, records.size)
        var done = 0
        for (slice in records.chunked(if (blobs) BLOB_BATCH else ITEM_BATCH)) {
            coroutineContextActive()
            val outcomes = transport.save(slice, zone)
            var quota = false
            for (r in slice) {
                val entry = index[r.recordName] ?: continue
                when (val o = outcomes[r.recordName]) {
                    is SyncSaveOutcome.Saved -> {
                        entry.serverId = o.serverId
                        entry.pushedAt = now
                        entry.needsPush = false
                        index.put(entry)
                    }
                    is SyncSaveOutcome.Failed -> if (o.error == SyncTransportError.QuotaExceeded) quota = true
                    null -> {}
                }
            }
            done += slice.size
            _progress.value = Progress(phase, done, records.size)
            index.save()
            if (quota) throw SyncTransportError.QuotaExceeded
        }
        index.state = index.state.copy(lastPushAt = now)
        // Only the big pushes are worth an event (iOS 2026-09-26: a pass per
        // change made one learner 427 events a day).
        if (records.size >= REPORT_PUSH_FROM) {
            Analytics.capture("sync_push", mapOf("records" to records.size, "blobs" to blobs))
        }
    }

    /** New and changed items are marked for push; anything the index knows
     *  that the file no longer holds becomes a tombstone. */
    private fun diff(snapshot: Map<String, String>, handler: SyncKindHandler, lang: String?,
                     index: SyncIndex, now: Long) {
        for ((key, payload) in snapshot) {
            val hash = if (handler.kind.isBlob) payload else SyncCanonical.sha256(payload)
            val entry = index.entry(handler.kind, lang, key)
            if (entry != null) {
                if (entry.frozen) continue
                if (entry.hash != hash || entry.isDeleted) {
                    entry.hash = hash; entry.observedAt = now; entry.deletedAt = null
                    entry.wanted = false; entry.needsPush = true
                    index.put(entry)
                }
            } else {
                index.put(SyncIndex.Entry(kind = handler.kind.raw, lang = lang, key = key, hash = hash,
                    observedAt = now, needsPush = true))
            }
        }
        for (entry in index.entries(handler.kind, lang)) {
            if (snapshot[entry.key] == null && !entry.isDeleted && !entry.frozen && !entry.wanted) {
                entry.deletedAt = now; entry.observedAt = now; entry.hash = ""; entry.needsPush = true
                index.put(entry)
            }
        }
    }

    // ── Audio downloads ─────────────────────────────────────────────────

    private suspend fun downloadWanted(index: SyncIndex, zone: String) {
        val requested = synchronized(requestedBlobs) { requestedBlobs.toSet() }
        val wanted = index.wantedBlobs.sortedWith(compareBy<SyncIndex.Entry> { it.recordName !in requested }
            .thenByDescending { it.observedAt })
        if (wanted.isEmpty()) return
        var done = 0
        for (slice in wanted.chunked(BLOB_FETCH_BATCH)) {
            coroutineContextActive()
            _progress.value = Progress(Progress.Phase.DOWNLOADING_AUDIO, done, wanted.size)
            val fetched = transport.fetch(slice, zone)
            for (entry in slice) {
                land(fetched[entry.recordName], entry, index)
                done++
            }
            index.save()
            refreshCounts()
        }
    }

    private fun land(record: SyncRecord?, entry: SyncIndex.Entry, index: SyncIndex) {
        val blob = entry.syncKind?.let { registry.handler(it) } as? BlobKind ?: return
        val temp = record?.asset
        if (temp == null) { entry.wanted = false; index.put(entry); return }
        val dest = blob.file(entry.key)
        dest.parentFile?.mkdirs()
        runCatching { temp.copyTo(dest, overwrite = true); temp.delete() }.onFailure { return }
        entry.wanted = false
        entry.needsPush = false
        entry.pushedAt = System.currentTimeMillis()
        entry.hash = SyncCanonical.blobFingerprint(dest.length(), dest.lastModified())
        index.put(entry)
        synchronized(requestedBlobs) { requestedBlobs.remove(entry.recordName) }
    }

    enum class BlobState { LOCAL, QUEUED, ABSENT }

    fun blobState(kind: SyncKind, key: String): BlobState {
        val blob = registry.handler(kind) as? BlobKind
        if (blob != null && blob.file(key).exists()) return BlobState.LOCAL
        return if (index?.entry(kind, null, key)?.wanted == true) BlobState.QUEUED else BlobState.ABSENT
    }

    /** Move one blob to the front of the download queue. */
    fun requestBlob(kind: SyncKind, key: String) {
        val name = SyncRecord.recordName(kind, null, key)
        synchronized(requestedBlobs) { requestedBlobs.remove(name); requestedBlobs.add(0, name) }
        requestSync(emptySet())
    }

    /** The voice recording from Drive, now — for a phone that has to rebuild a
     *  voice and holds no recording of its own (iOS `fetchVoiceSample`). */
    suspend fun fetchVoiceSample(timeoutMs: Long = 25_000): File? {
        if (!isEnabled) return null
        fun newestWanted() = index?.wantedBlobs?.filter { it.kind == SyncKind.BLOB_VOICE_SAMPLE.raw }
            ?.map { it.key }?.maxOrNull()
        if (newestWanted() == null) syncAndWait(emptySet(), Scope.ITEMS)
        val key = newestWanted() ?: return registry.newestVoiceSample()
        requestBlob(SyncKind.BLOB_VOICE_SAMPLE, key)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (blobState(SyncKind.BLOB_VOICE_SAMPLE, key) == BlobState.LOCAL) return registry.newestVoiceSample()
            delay(500)
        }
        return null
    }

    // ── Quota (iOS `quotaFull`) ─────────────────────────────────────────

    private fun loadQuota() {
        val at = userId?.let { settings.quotaHitAt(it) }
        quotaHitAt = at
        _quotaFull.value = at != null
    }

    private fun noteQuota() {
        val first = !_quotaFull.value
        quotaHitAt = System.currentTimeMillis()
        _quotaFull.value = true
        userId?.let { settings.setQuotaHitAt(it, quotaHitAt) }
        if (first) Analytics.capture("sync_error", mapOf("reason" to "quota exceeded"))
    }

    private fun clearQuota() {
        if (!_quotaFull.value) return
        _quotaFull.value = false
        quotaHitAt = null
        userId?.let { settings.setQuotaHitAt(it, null) }
        Analytics.capture("sync_quota_cleared")
    }

    private fun quotaHolds(): Boolean {
        val at = quotaHitAt ?: return false
        return !forceRetry && System.currentTimeMillis() - at < QUOTA_BACKOFF_MS
    }

    private fun refreshCounts() {
        val index = index ?: run { _counts.value = Counts(); return }
        val pending = index.pendingPush
        _counts.value = Counts(
            items = pending.count { it.syncKind?.isBlob == false },
            audioUp = pending.count { it.syncKind?.isBlob == true },
            audioDown = index.wantedBlobs.size)
    }

    private suspend fun coroutineContextActive() = kotlin.coroutines.coroutineContext.ensureActive()

    companion object {
        const val DEBOUNCE_MS = 3_000L
        const val ITEM_BATCH = 60
        const val BLOB_BATCH = 12
        const val BLOB_FETCH_BATCH = 10
        const val REPORT_PUSH_FROM = 20
        const val QUOTA_BACKOFF_MS = 6 * 3600 * 1000L

        fun describe(e: SyncTransportError): String = e.message ?: "error"

        @Volatile private var instance: SyncEngine? = null
        fun shared(context: Context): SyncEngine = instance ?: synchronized(this) {
            instance ?: run {
                val app = context.applicationContext
                SyncEngine(PrefsSyncSettings(app), DriveTransport(app), SyncKindRegistry(app), app.filesDir,
                    onEnabledChange = { on -> if (on) SyncBackground.schedule(app) else SyncBackground.cancel(app) },
                    audioAllowed = {
                        val cm = app.getSystemService(android.net.ConnectivityManager::class.java)
                        SyncStore.cellularForAudio(app) || cm?.isActiveNetworkMetered == false
                    })
            }.also { instance = it }
        }
        /** A store's write funnel — never builds the engine just to say no.
         *  Which kind moved doesn't matter: the pass diffs, and a debounced
         *  burst of writes (a talk ending) is one pass. */
        fun noteChanged() { instance?.markDirtyAll() }
    }
}
