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

    /**
     * A public figure — a singer, an athlete, an author — added as someone
     * NOT in the learner's life (iOS `isPublicFigure`, `59c6481`). Their
     * profile is filled from PUBLIC coverage rather than the learner's own
     * notes, and the voice is a preset like any stranger's — never a clone.
     * Optional so rows saved before this decode unchanged.
     */
    val isPublicFigure: Boolean? = null,
    /** Who the grounded lookup settled on ("BTS Jimin · singer"), shown for
     *  the learner to confirm. null for anyone else. */
    val publicIdentity: String? = null,
    /** When public facts were last looked up. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val factsRefreshedAt: Long? = null,

    /** Situation ideas per target language — title + blurb, the blurb is the scene's seed. */
    val scenariosByLanguage: Map<String, List<com.roro.futurevoice.talk.SuggestedTopic>> = emptyMap(),

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
    /** Built-in people take the active language's name
     *  (`VoicePreset.localized`) — one row serves every target language. */
    suspend fun load(): List<Counterpart> = mutex.withLock {
        val language = LanguageScope.active(appContext)
        read().map { com.roro.futurevoice.talk.VoicePreset.localized(it, language) }
    }

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
        // Their photo goes with them — it is nobody's once they are gone.
        CounterpartPhotoStore.delete(appContext, id)
    }

    private fun write(list: List<Counterpart>) {
        val target = file
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(StoreJson.json.encodeToString(serializer, list))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
