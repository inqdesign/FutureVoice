package com.roro.futurevoice.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.VocabStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Writes the widget snapshots — on every notebook write and at scene-phase
 * edges, exactly as iOS does. The widget itself never reads a store.
 */
object StudyWidgetRefresher {

    private const val MAX_ITEMS = 12
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun schedule(context: Context) {
        val app = context.applicationContext
        scope.launch { refresh(app) }
    }

    suspend fun refresh(context: Context) {
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

        runCatching {
            StudyWidget(StudyWidgetSection.WORDS).updateAll(context)
            StudyWidget(StudyWidgetSection.EXPRESSIONS).updateAll(context)
        }
    }
}
