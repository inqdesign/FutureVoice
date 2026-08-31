package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * A person from the learner's real life, used as the other side of a Watch
 * scene or a call. Same file and shape as iOS `Counterpart`
 * (`files/counterparts.json`).
 *
 * The person is GLOBAL, not language-scoped — nobody should re-enter their own
 * life once per language — but the scenario ideas written about them are in
 * the language being practiced, so those are keyed by it. Keying rather than
 * clearing on a switch keeps both pools alive, so moving back and forth never
 * re-bills Gemini.
 */
@Serializable
data class Counterpart(
    val id: String = StoreJson.newId(),

    // Who
    val name: String = "",
    val relationship: String = "",

    // About them
    val location: String = "",

    // Your history together
    val howWeMet: String = "",
    /** Shared context, recurring topics, inside jokes. */
    val background: String = "",

    // Communication
    val conversationStyle: String = "",
    val commonTopics: String = "",

    /** ElevenLabs voice id. Never a clone — this is someone else. */
    val voicePresetId: String = "",

    val freeNotes: String = "",

    /**
     * Set when this person came from the shared `public_personas` pool (a
     * stranger met via Find people); null = someone the learner made. Remote
     * personas are hidden from Watch's stories row — they live in the Find
     * sheet's "People you've met" section instead, so strangers never crowd
     * out people you actually know.
     */
    val remoteId: String? = null,
    /**
     * The self-introduction the persona's author wrote, verbatim, in the
     * target language. Kept alongside the parsed fields because it IS the
     * conversational substance — prompts quote it directly.
     */
    val intro: String = "",
    /** "user" (a real learner) or "character" (an invented seed). */
    val personaKind: String? = null,

    val scenariosByLanguage: Map<String, List<String>> = emptyMap(),

    @Serializable(with = IsoDateMillisSerializer::class)
    val createdAt: Long = System.currentTimeMillis(),
    @Serializable(with = IsoDateMillisSerializer::class)
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val isMinimallyComplete: Boolean
        get() = name.isNotBlank() && relationship.isNotBlank()

    /** How the row reads in a list: who they are to you, then where. */
    val caption: String
        get() = listOf(relationship, location).filter { it.isNotBlank() }.joinToString(" · ")
}

/** JSON-on-disk, same pattern as every other store here. */
class CounterpartStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: CounterpartStore? = null
        fun shared(context: Context): CounterpartStore =
            instance ?: synchronized(this) {
                instance ?: CounterpartStore(context.applicationContext).also { instance = it }
            }
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()
    private val serializer = ListSerializer(Counterpart.serializer())

    private val file: File get() = File(appContext.filesDir, "counterparts.json")

    /** Newest-touched first — the order the stories row reads in. */
    suspend fun load(): List<Counterpart> = mutex.withLock { read() }

    private fun read(): List<Counterpart> {
        val f = file
        if (!f.exists()) return emptyList()
        return runCatching {
            StoreJson.json.decodeFromString(serializer, f.readText())
        }.getOrElse { emptyList() }.sortedByDescending { it.updatedAt }
    }

    suspend fun save(counterpart: Counterpart) = mutex.withLock {
        val all = read().toMutableList()
        all.removeAll { it.id == counterpart.id }
        // A Find-people persona is ONE person however many times it gets
        // materialized — dedupe on the remote id too, so a row written before
        // ids became remote-derived can't survive as a twin.
        counterpart.remoteId?.let { rid -> all.removeAll { it.remoteId == rid } }
        all.add(counterpart.copy(updatedAt = System.currentTimeMillis()))
        write(all)
    }

    suspend fun delete(id: String) = mutex.withLock {
        val all = read()
        if (all.none { it.id == id }) return
        write(all.filterNot { it.id == id })
    }

    private fun write(list: List<Counterpart>) {
        val target = file
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(StoreJson.json.encodeToString(serializer, list))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
