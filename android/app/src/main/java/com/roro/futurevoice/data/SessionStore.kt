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
        TalkTimeLog.noteSpokenDays(appContext, listOf(session))
    }

    suspend fun delete(id: String, language: String = LanguageScope.active(appContext)) = mutex.withLock {
        val list = all(language)
        if (list.removeAll { it.id == id }) write(language, list)
    }

    /** Archiving a talk keeps its book and its mastery; it only leaves the shelf. */
    suspend fun setArchived(id: String, archived: Boolean,
                            language: String = LanguageScope.active(appContext)) = mutex.withLock {
        val sessions = all(language)
        val i = sessions.indexOfFirst { it.id == id }
        if (i >= 0) {
            sessions[i] = sessions[i].copy(
                archivedAt = if (archived) System.currentTimeMillis() else null)
            write(language, sessions)
        }
    }

    /**
     * The learner flagged a turn as misheard (iOS `excludeTurnFromScoring`):
     * the rewrite is [MisheardExclusion.excludeTurn], written through this
     * store's one funnel. Drill cards and the weekly report are the caller's
     * ([MisheardExclusion.excludeTurn] with a context). Null = nothing changed.
     */
    suspend fun excludeTurnFromScoring(sessionId: String, turnId: String,
                                       language: String = LanguageScope.active(appContext)): Session? =
        mutex.withLock {
            val list = all(language)
            val i = list.indexOfFirst { it.id == sessionId }
            if (i < 0) return@withLock null
            val updated = MisheardExclusion.excludeTurn(list[i], turnId) ?: return@withLock null
            list[i] = updated
            write(language, list)
            updated
        }

    /** A grammar slip marked Misheard (iOS `excludeMishearing`): the session
     *  and the turn it was traced to (null = only the slip was dropped). */
    suspend fun excludeMishearing(sessionId: String, issueId: String,
                                  language: String = LanguageScope.active(appContext)): Pair<Session, String?>? =
        mutex.withLock {
            val list = all(language)
            val i = list.indexOfFirst { it.id == sessionId }
            if (i < 0) return@withLock null
            val result = MisheardExclusion.excludeIssue(list[i], issueId) ?: return@withLock null
            list[i] = result.first
            write(language, list)
            result
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
        TalkTimeLog.noteSpokenDays(appContext, loaded)
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
