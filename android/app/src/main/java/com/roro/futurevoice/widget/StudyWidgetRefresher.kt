package com.roro.futurevoice.widget

import android.content.Context
import androidx.glance.appwidget.updateAll
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.data.VocabStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield

/**
 * Writes the widget snapshots (`StudyWidgetRefresher.swift`) — on store
 * writes and at the app's foreground/background edges. The widgets never
 * read a store.
 *
 * COALESCED, as on iOS: one "I know" writes several files and each asks for
 * a refresh, and a refresh rebuilds every talk book. [schedule] runs ONE
 * refresh [COALESCE_MS] after the last request; only the background edge
 * calls [refresh] directly, because the process may be frozen right after.
 */
object StudyWidgetRefresher {

    private const val MAX_ITEMS = 12
    private const val COALESCE_MS = 400L
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pending: Job? = null
    private var observing = false

    @Synchronized
    fun schedule(context: Context) {
        val app = context.applicationContext
        observe(app)
        pending?.cancel()
        pending = scope.launch {
            delay(COALESCE_MS)
            refresh(app)
        }
    }

    /**
     * Every store write that bumps [StoreEvents] is a reason to redraw — a
     * talk, a book page, a deck — so the widgets follow the app without each
     * store having to know they exist. Started by the first [schedule]
     * (the Application's `onCreate`).
     */
    private fun observe(app: Context) {
        if (observing) return
        observing = true
        scope.launch { StoreEvents.revision.collect { schedule(app) } }
    }

    suspend fun refresh(context: Context) {
        // Today's promise standing follows the day as it moves (iOS does this
        // here too), so the streak the widget prints is today's.
        runCatching { com.roro.futurevoice.data.PromiseJudge.refresh(context) }
        val language = LanguageScope.active(context)
        val vocab = VocabStore.shared(context)

        // ONLY the words the learner deliberately collected (the notebook),
        // newest first — the widget mirrors what they're actively studying,
        // not every word they've ever used.
        val words = vocab.studying(language)
        StudyWidgetSnapshotStore.save(context, StudyWidgetSnapshot(
            updatedAt = System.currentTimeMillis(),
            total = words.size,
            items = words.take(MAX_ITEMS).map {
                StudyWidgetItem(it, CoreVocabulary.level(it, language)?.code?.uppercase().orEmpty())
            },
        ), StudyWidgetSection.WORDS)

        val phrases = vocab.studyingExpressions(language)
        StudyWidgetSnapshotStore.save(context, StudyWidgetSnapshot(
            updatedAt = System.currentTimeMillis(),
            total = phrases.size,
            items = phrases.take(MAX_ITEMS).map {
                StudyWidgetItem(it.replaceFirstChar { c -> c.uppercase() })
            },
        ), StudyWidgetSection.EXPRESSIONS)

        runCatching { refreshProgress(context, language, words.size, phrases.size) }
        runCatching { refreshBook(context, language) }

        runCatching {
            StudyWidget(StudyWidgetSection.WORDS).updateAll(context)
            StudyWidget(StudyWidgetSection.EXPRESSIONS).updateAll(context)
            ProgressWidget().updateAll(context)
            StreakWidget().updateAll(context)
            BookWidget().updateAll(context)
            // No data of its own, but it wears the theme — a palette pick
            // repaints it like the others.
            FreeTalkWidget().updateAll(context)
        }
    }

    /**
     * Today's goal + streak + review/study counts — the SAME numbers the app
     * shows, from the same functions: the ring's metered seconds, the Home
     * streak and its own "does today count" predicate.
     */
    private suspend fun refreshProgress(context: Context, language: String,
                                        studyingWords: Int, studyingExpressions: Int) {
        val goal = context.getSharedPreferences("futurevoice", 0)
            .getInt("futurevoice.dailyGoalMinutes", 10)
        StudyWidgetSnapshotStore.saveProgress(context, StudyProgressSnapshot(
            updatedAt = System.currentTimeMillis(),
            todaySeconds = TalkTimeLog.secondsToday(context),
            goalMinutes = if (goal > 0) goal else 10,
            streakDays = TalkTimeLog.streakDays(context),
            dueCount = DrillStore.shared(context).dueCount(language),
            studyingWords = studyingWords,
            studyingExpressions = studyingExpressions,
            // The streak's rule, not the ring's.
            metToday = TalkTimeLog.studied(context),
        ))
    }

    /**
     * The most recently studied book that is started but not mastered, across
     * Talk and Watch — the book the Practice shelf would point at. Progress is
     * derived (TalkCurriculum for talks, the scenario's own curriculum for
     * Watch books), never stored.
     */
    private suspend fun refreshBook(context: Context, language: String) {
        data class Candidate(val date: Long, val snapshot: StudyBookSnapshot)
        val candidates = ArrayList<Candidate>()
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val level = CefrLevel.from(LanguageScope.level(context, language,
            prefs.getString("futurevoice.proficiency", null) ?: "b1"))
        val vocab = VocabStore.shared(context)
        val attempts = ShadowAttemptStore.shared(context).load(language)
        val cards = DrillStore.shared(context).load(language)
        val now = System.currentTimeMillis()

        for (session in SessionStore.shared(context).load(language)) {
            if (session.endedAt == null || session.archivedAt != null) continue
            // Each book is a full curriculum build; give the rest of the app
            // a turn between them.
            yield()
            val cur = runCatching {
                TalkCurriculum.build(session, level, language, vocab, attempts, cards)
            }.getOrNull() ?: continue
            if (cur.masteredCount == 0 || cur.isMastered) continue
            candidates.add(Candidate(cur.lastStudiedAt ?: session.endedAt,
                StudyBookSnapshot(
                    updatedAt = now, hasBook = true, kind = "talk", id = session.id,
                    title = session.displayTitle
                        ?: StudyWidgetSnapshotStore.chrome(context, R.string.conversation),
                    // DATA by the time the widget sees it — resolved here, in
                    // the app language.
                    subtitle = StudyWidgetSnapshotStore.chrome(context, R.string.talk),
                    mastered = cur.masteredCount, total = cur.totalCount)))
        }

        for (sc in ScenarioStore.shared(context).load(language)) {
            if (sc.archivedAt != null || sc.isMeeting == true) continue
            val cur = sc.curriculum ?: continue
            val items = cur.words + cur.expressions + cur.shadowLines
            val total = items.size
            val mastered = items.count { it.masteredAt != null }
            if (mastered == 0 || mastered == total) continue
            val subtitle = when {
                sc.role.isNotBlank() -> StudyWidgetSnapshotStore.chrome(context, R.string.with, sc.role)
                sc.isTopic == true -> StudyWidgetSnapshotStore.chrome(context, R.string.news_topic)
                else -> StudyWidgetSnapshotStore.chrome(context, R.string.situation)
            }
            candidates.add(Candidate(
                items.mapNotNull { it.masteredAt }.maxOrNull() ?: sc.lastUsedAt ?: sc.createdAt,
                StudyBookSnapshot(
                    updatedAt = now, hasBook = true, kind = "watch", id = sc.id,
                    title = sc.cardTitle, subtitle = subtitle,
                    mastered = mastered, total = total)))
        }

        StudyWidgetSnapshotStore.saveBook(context,
            candidates.maxByOrNull { it.date }?.snapshot ?: StudyBookSnapshot(updatedAt = now))
    }
}
