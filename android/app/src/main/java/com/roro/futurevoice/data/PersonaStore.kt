package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * `PersonaStore.swift` — the persona lives at the files ROOT (identity, not a
 * learning record; it follows the user across languages). `load()` returns
 * null iff persona onboarding never completed, which is what routes there.
 */
class PersonaStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: PersonaStore? = null
        fun shared(context: Context): PersonaStore =
            instance ?: synchronized(this) {
                instance ?: PersonaStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "persona.json"
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    suspend fun load(): UserPersona? = mutex.withLock {
        withContext(Dispatchers.IO) {
            val f = File(appContext.filesDir, FILE_NAME)
            if (!f.exists()) null
            else runCatching {
                StoreJson.json.decodeFromString(UserPersona.serializer(), f.readText())
            }.getOrNull()
        }
    }

    suspend fun save(persona: UserPersona) = mutex.withLock {
        withContext(Dispatchers.IO) {
            val target = File(appContext.filesDir, FILE_NAME)
            val tmp = File(appContext.filesDir, "$FILE_NAME.tmp")
            tmp.writeText(StoreJson.json.encodeToString(
                UserPersona.serializer(), persona.copy(updatedAt = System.currentTimeMillis())))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }
}
