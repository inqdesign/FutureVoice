package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * The learner's personal line archive — every fluent-self line they
 * bookmarked, newest first. Same on-disk shape and file as iOS
 * (`saved_lines.json`, id = the source Turn's id), so a bookmark survives a
 * backup either way and a shadow attempt made against the line stays attached.
 */
@Serializable
data class SavedLine(
    /** = source Turn.id */
    val id: String,
    val text: String,
    /** Topic or counterpart name; may be empty. */
    val source: String = "",
    @Serializable(with = IsoDateMillisSerializer::class)
    val savedAt: Long = System.currentTimeMillis(),
)

class SavedLineStore private constructor(context: Context) {
    companion object {
        @Volatile private var instance: SavedLineStore? = null
        fun shared(context: Context): SavedLineStore =
            instance ?: synchronized(this) {
                instance ?: SavedLineStore(context.applicationContext).also { instance = it }
            }
    }

    private val file = File(context.filesDir, "saved_lines.json")

    suspend fun load(): List<SavedLine> = withContext(Dispatchers.IO) {
        runCatching {
            if (!file.exists()) emptyList()
            else StoreJson.json.decodeFromString(ListSerializer(SavedLine.serializer()), file.readText())
                .sortedByDescending { it.savedAt }
        }.getOrDefault(emptyList())
    }

    suspend fun isSaved(id: String): Boolean = load().any { it.id == id }

    /** Bookmark / un-bookmark; returns whether it is saved afterwards. */
    suspend fun toggle(line: SavedLine): Boolean = withContext(Dispatchers.IO) {
        val all = load()
        val now = if (all.any { it.id == line.id }) all.filterNot { it.id == line.id } else all + line
        write(now)
        now.any { it.id == line.id }
    }

    suspend fun delete(id: String) = withContext(Dispatchers.IO) { write(load().filterNot { it.id == id }) }

    private fun write(lines: List<SavedLine>) {
        runCatching { file.writeText(StoreJson.json.encodeToString(ListSerializer(SavedLine.serializer()), lines)) }
        StoreEvents.bump()
    }
}
