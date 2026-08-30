package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.Session
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * Local persistence for talks — the Android twin of `SessionStore.swift`,
 * same file (`lang/<code>/sessions.json`), same shape, same ordering
 * (newest-ended-first). Decoded once per language and cached; every write
 * updates the cache and rewrites the file atomically (temp + rename), so a
 * crash mid-write leaves the previous file intact.
 */
class SessionStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: SessionStore? = null

        /**
         * ONE store per process, like iOS's `SessionStore.shared`. Two
         * instances mean two caches, and a screen reading its own copy never
         * sees what a background job wrote through the other.
         */
        fun shared(context: Context): SessionStore =
            instance ?: synchronized(this) {
                instance ?: SessionStore(context.applicationContext).also { instance = it }
            }

        private const val FILE_NAME = "sessions.json"
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()
    private var cache: MutableList<Session>? = null
    private var cachedLanguage: String? = null

    private fun file(language: String): File =
        File(LanguageScope.directory(appContext, language), FILE_NAME)

    /** All talks in [language], newest-ended-first. */
    suspend fun load(language: String = LanguageScope.active(appContext)): List<Session> =
        mutex.withLock { all(language).toList() }

    /** Insert or overwrite by id. */
    suspend fun save(session: Session) = mutex.withLock {
        val list = all(session.targetLanguage)
        list.removeAll { it.id == session.id }
        list.add(session)
        list.sortByDescending { it.rank }
        write(session.targetLanguage, list)
    }

    suspend fun delete(id: String, language: String = LanguageScope.active(appContext)) = mutex.withLock {
        val list = all(language)
        if (list.removeAll { it.id == id }) write(language, list)
    }

    private suspend fun all(language: String): MutableList<Session> {
        cache?.let { if (cachedLanguage == language) return it }
        val loaded = withContext(Dispatchers.IO) {
            val f = file(language)
            if (!f.exists()) mutableListOf()
            else runCatching {
                StoreJson.json.decodeFromString(ListSerializer(Session.serializer()), f.readText())
                    .sortedByDescending { it.rank }.toMutableList()
            }.getOrElse { mutableListOf() }
        }
        cache = loaded
        cachedLanguage = language
        return loaded
    }

    private suspend fun write(language: String, sessions: List<Session>) = withContext(Dispatchers.IO) {
        val target = file(language)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(ListSerializer(Session.serializer()), sessions))
        if (!tmp.renameTo(target)) {
            target.delete(); tmp.renameTo(target)
        }
    }

}
