package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.LearnerProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * `ProfileStore.swift` — one `LearnerProfile` per target language, all in a
 * single `profile.json` at the files root (the profile file itself is not
 * language-scoped; the rows inside are keyed by language).
 */
class ProfileStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: ProfileStore? = null
        fun shared(context: Context): ProfileStore =
            instance ?: synchronized(this) {
                instance ?: ProfileStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "profile.json"
        private const val LOCAL_USER_KEY = "futurevoice.localUserId"
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    /** Stable anonymous learner id, minted once per install (iOS twin). */
    fun localUserId(): String {
        val prefs = appContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
        prefs.getString(LOCAL_USER_KEY, null)?.let { return it }
        val fresh = StoreJson.newId()
        prefs.edit().putString(LOCAL_USER_KEY, fresh).apply()
        return fresh
    }

    suspend fun load(targetLanguage: String, proficiency: String): LearnerProfile = mutex.withLock {
        loadAll().firstOrNull { it.targetLanguage == targetLanguage }
            ?: LearnerProfile(userId = localUserId(), targetLanguage = targetLanguage,
                proficiencyLevel = proficiency)
    }

    suspend fun save(profile: LearnerProfile) = mutex.withLock {
        val all = loadAll().filterNot { it.targetLanguage == profile.targetLanguage } + profile
        withContext(Dispatchers.IO) {
            val target = File(appContext.filesDir, FILE_NAME)
            val tmp = File(appContext.filesDir, "$FILE_NAME.tmp")
            tmp.writeText(StoreJson.json.encodeToString(ListSerializer(LearnerProfile.serializer()), all))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }

    private suspend fun loadAll(): List<LearnerProfile> = withContext(Dispatchers.IO) {
        val f = File(appContext.filesDir, FILE_NAME)
        if (!f.exists()) emptyList()
        else runCatching {
            StoreJson.json.decodeFromString(ListSerializer(LearnerProfile.serializer()), f.readText())
        }.getOrElse { emptyList() }
    }
}
