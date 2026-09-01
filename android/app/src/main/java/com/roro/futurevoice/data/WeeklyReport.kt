package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * The learner's periodic assessment — the same file and shape as iOS
 * (`lang/<code>/weekly-reports.json`).
 *
 * It is the learner's MAIN WRITTEN FEEDBACK, which is why the level here
 * outranks any single talk's read on Progress: it is judged over the whole
 * window's speech pooled together, a far larger sample than one conversation.
 */
@Serializable
data class WeeklyReport(
    val id: String = StoreJson.newId(),
    @Serializable(with = IsoDateMillisSerializer::class) val periodStart: Long,
    @Serializable(with = IsoDateMillisSerializer::class) val periodEnd: Long,
    val sessionCount: Int = 0,
    val targetLanguage: String = "en",
    val newExpressions: List<LearnedExpression> = emptyList(),
    val repeatedMistakes: List<RepeatedMistake> = emptyList(),
    val suggestedExpressions: List<SuggestedExpression> = emptyList(),
    val summary: String = "",
    /** Pooled CEFR estimate over the window. Optional: older reports lack it. */
    val cefrLevel: String? = null,
    /** The judge's own justification, citing the evidence it was given. */
    val levelRationale: String? = null,
    /**
     * Verbatim snapshot of the evidence block the judge received — kept so a
     * surprising verdict can be checked against what it actually saw.
     */
    val levelEvidence: String? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val generatedAt: Long = System.currentTimeMillis(),
)

@Serializable
data class LearnedExpression(
    val id: String = StoreJson.newId(),
    val phrase: String = "",
    /** The learner's actual utterance containing it. */
    val sampleSentence: String = "",
)

@Serializable
data class RepeatedMistake(
    val id: String = StoreJson.newId(),
    val userSaid: String = "",
    val fluentAlternative: String = "",
    val count: Int = 0,
    val note: String = "",
)

@Serializable
data class SuggestedExpression(
    val id: String = StoreJson.newId(),
    val phrase: String = "",
    val whenToUse: String = "",
    val example: String = "",
)

/** JSON-on-disk, language-scoped like every other learning record. */
class WeeklyReportStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: WeeklyReportStore? = null
        fun shared(context: Context): WeeklyReportStore =
            instance ?: synchronized(this) {
                instance ?: WeeklyReportStore(context.applicationContext).also { instance = it }
            }
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()
    private val serializer = ListSerializer(WeeklyReport.serializer())

    private fun file(language: String) =
        File(LanguageScope.directory(appContext, language), "weekly-reports.json")

    /** Newest first. */
    suspend fun load(language: String): List<WeeklyReport> = mutex.withLock { read(language) }

    suspend fun latest(language: String): WeeklyReport? = load(language).firstOrNull()

    suspend fun save(report: WeeklyReport, language: String) = mutex.withLock {
        val all = read(language).filterNot { it.id == report.id }
        write(language, (all + report).sortedByDescending { it.generatedAt })
    }

    private fun read(language: String): List<WeeklyReport> {
        val f = file(language)
        if (!f.exists()) return emptyList()
        return runCatching {
            StoreJson.json.decodeFromString(serializer, f.readText())
        }.getOrElse { emptyList() }.sortedByDescending { it.generatedAt }
    }

    private fun write(language: String, list: List<WeeklyReport>) {
        val target = file(language)
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(StoreJson.json.encodeToString(serializer, list))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
