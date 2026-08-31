package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.Scenario
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/** `ScenarioStore.swift` — `lang/<code>/scenarios.json`, newest first. */
class ScenarioStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: ScenarioStore? = null
        fun shared(context: Context): ScenarioStore =
            instance ?: synchronized(this) {
                instance ?: ScenarioStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "scenarios.json"
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String): File =
        File(LanguageScope.directory(appContext, language), FILE_NAME)

    suspend fun load(language: String = LanguageScope.active(appContext)): List<Scenario> =
        mutex.withLock { loadLocked(language) }

    suspend fun save(scenario: Scenario, language: String = LanguageScope.active(appContext)) =
        mutex.withLock {
            write(language, listOf(scenario) + loadLocked(language).filterNot { it.id == scenario.id })
        }

    /** A tap on a saved scenario is a use — the list stays recency-ordered. */
    suspend fun touch(id: String, language: String = LanguageScope.active(appContext)) =
        mutex.withLock {
            write(language, loadLocked(language).map {
                if (it.id == id) it.copy(lastUsedAt = System.currentTimeMillis()) else it
            })
        }

    private suspend fun loadLocked(language: String): List<Scenario> = withContext(Dispatchers.IO) {
        val f = file(language)
        if (!f.exists()) emptyList()
        else runCatching {
            StoreJson.json.decodeFromString(ListSerializer(Scenario.serializer()), f.readText())
        }.getOrElse { emptyList() }
            .sortedByDescending { it.lastUsedAt ?: it.createdAt }
    }

    private suspend fun write(language: String, scenarios: List<Scenario>) = withContext(Dispatchers.IO) {
        val target = file(language)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(ListSerializer(Scenario.serializer()), scenarios))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
