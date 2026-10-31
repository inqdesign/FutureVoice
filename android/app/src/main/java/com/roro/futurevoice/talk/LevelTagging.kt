package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.LearnerState
import com.roro.futurevoice.data.LearnerStateStore
import com.roro.futurevoice.data.LevelMap
import com.roro.futurevoice.data.SessionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Runs [LevelTagger] in the background and files the result in
 * [LearnerStateStore] (docs/personal-report-plan.md, step 3; iOS
 * `LevelTagging`, 465331f6).
 *
 * Two doors: every talk right after its summary is saved ([afterSummary]),
 * and once per launch a backfill of the learner's recent talks that were
 * never tagged ([backfillSoon]). Never on a critical path: nothing waits on
 * it, the wrap-up board doesn't know it exists, and a failure is one
 * `level_tag_failed` event and otherwise silent — the next summary or launch
 * tries again, up to [LearnerState.MAX_FAILURES] per talk.
 *
 * ONE call at a time: each job waits for the one before it, so a backfill of
 * fifteen talks is fifteen calls in a row, never a burst.
 */
object LevelTagging {
    /** How many recent talks the launch backfill looks at. */
    const val BACKFILL_COUNT = 15
    /** After launch, so the first frames (the Talk ring, the widget refresh)
     *  never share the main thread or the network with it. */
    const val BACKFILL_DELAY_MS = 20_000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private var tail: Job? = null
    private val queued = HashSet<String>()
    @Volatile private var didBackfill = false

    /** A talk worth tagging: its language has a map and the learner said at
     *  least one line that counts (not a practice call). */
    fun isTaggable(session: Session): Boolean =
        LevelMap.load(session.targetLanguage) != null && session.isLevelEvidence

    /** Right after [SessionSummarizer] saved the talk with its summary. */
    fun afterSummary(context: Context, session: Session) {
        enqueue(context.applicationContext, session, source = "summary")
    }

    /** Tags the learner's recent untagged talks in the active language, once
     *  per launch. Already-tagged talks cost nothing (the store says so before
     *  any call), so "once" across launches falls out of the store. */
    fun backfillSoon(context: Context) {
        if (didBackfill || isQuietRun) return
        didBackfill = true
        val app = context.applicationContext
        scope.launch {
            delay(BACKFILL_DELAY_MS)
            backfill(app)
        }
    }

    private suspend fun backfill(context: Context) {
        val store = LearnerStateStore.shared(context)
        val language = LanguageScope.active(context)
        val map = LevelMap.load(language) ?: return
        val all = SessionStore.shared(context).load(language).filter {
            LanguageCatalog.sameLanguage(it.targetLanguage, language)
        }
        // A deleted talk's verdicts go with it.
        store.forgetSessions(notIn = all.map { it.id }.toSet(), language = language)
        val recent = all
            .filter { it.endedAt != null && it.summary != null && isTaggable(it) }
            .sortedByDescending { it.endedAt ?: it.startedAt }
            .take(BACKFILL_COUNT)
        for (session in recent) {
            if (store.needsTagging(sessionId = session.id, fingerprint = LevelTagger.fingerprint(session.turns),
                    mapVersion = map.version, language = language)) {
                enqueue(context, session, source = "backfill")
            }
        }
    }

    private fun enqueue(context: Context, session: Session, source: String) {
        if (!isTaggable(session) || isQuietRun) return
        val map = LevelMap.load(session.targetLanguage) ?: return
        val store = LearnerStateStore.shared(context)
        val language = session.targetLanguage
        if (!store.needsTagging(sessionId = session.id, fingerprint = LevelTagger.fingerprint(session.turns),
                mapVersion = map.version, language = language)) return
        synchronized(lock) {
            if (session.id in queued) return
            queued += session.id
            val previous = tail
            tail = scope.launch {
                previous?.join()
                run(session, source, store)
                synchronized(lock) { queued -= session.id }
            }
        }
    }

    private suspend fun run(session: Session, source: String, store: LearnerStateStore) {
        val started = System.currentTimeMillis()
        try {
            val outcome = LevelTagger.tag(session) ?: return
            store.record(outcome.tag, sessionId = session.id, language = session.targetLanguage)
            Analytics.capture("level_tagged", mapOf(
                "source" to source,
                "items" to outcome.tag.items.size,
                "dropped" to outcome.dropped,
                "ms" to (System.currentTimeMillis() - started).toInt(),
            ))
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Throwable) {
            store.recordFailure(sessionId = session.id, language = session.targetLanguage)
            Analytics.capture("level_tag_failed", mapOf(
                "source" to source,
                "error" to e.toString().take(120),
            ))
        }
    }

    /** Capture runs launch the app too; they should not spend a call or
     *  write a learner file. */
    private val isQuietRun: Boolean get() = BuildConfig.BUILD_TYPE == "capture"
}
