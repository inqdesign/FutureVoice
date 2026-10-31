package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.io.InputStream

/**
 * The level map for one target language: what each spoken step needs
 * (docs/personal-report-plan.md, part 1; iOS `LevelMap`, 465331f6). The same
 * for every learner; [LearnerState] is where one learner stands on it.
 *
 * Read from `assets/level_map/level_map_<code>.json` (copied from iOS by
 * `scripts/android/gen-level-tag-prompt.py`). Only English exists
 * (2026-10-27); every other language returns null, and everything built on
 * the map — the tagging call, the learner state, the prompt block — stands
 * down for it without a word. Grammar differs per language, so a map is
 * written and probed per language (plan step 6), never translated.
 */
@Serializable
data class LevelMap(
    val language: String,
    val version: Int,
    val grammar: List<Grammar>,
    val functions: List<Function>,
) {
    /** A grammar structure, tagged right/wrong per talk. */
    @Serializable
    data class Grammar(
        val id: String,
        /** The step at which the item should be SOLID. */
        @Serializable(with = StrictCefrSerializer::class)
        val level: CefrLevel,
        val name: String,
        /** What counts as a use — read by the tagging prompt. */
        val counts: String,
        val example: String,
        val error: String,
        /** Items this one builds on (past simple before present perfect). */
        val requires: List<String>,
    )

    /** Something a speaker DOES with the language (tell a story in order,
     *  give a reason). Tagged when the learner did it; there is no "wrong". */
    @Serializable
    data class Function(
        val id: String,
        @Serializable(with = StrictCefrSerializer::class)
        val level: CefrLevel,
        val name: String,
        val counts: String,
    )

    /** Every item id, grammar and function — the tagger drops anything else. */
    val itemIds: Set<String> get() = (grammar.map { it.id } + functions.map { it.id }).toSet()

    companion object {
        @Volatile private var appContext: Context? = null

        /** Where a map's bytes come from. The app reads its assets; a JVM
         *  test points this at `src/main/assets` instead. */
        @Volatile var opener: ((String) -> InputStream?)? = null

        fun init(context: Context) { appContext = context.applicationContext }

        private val json = Json { ignoreUnknownKeys = true }

        /** Decoded once per language per launch; null cached too, so a
         *  language with no map costs one asset lookup, not one per talk. */
        private val cache = HashMap<String, LevelMap?>()

        /** The map for [code] ("en", "en-GB" → "en"), or null when the
         *  language has none. */
        fun load(code: String): LevelMap? {
            val base = code.substringBefore('-')
            synchronized(cache) {
                if (cache.containsKey(base)) return cache[base]
                val name = "level_map_$base.json"
                val stream = opener?.invoke(name)
                    ?: appContext?.let { c -> runCatching { c.assets.open("level_map/$name") }.getOrNull() }
                val map = stream?.let { s ->
                    runCatching { json.decodeFromString(serializer(), s.bufferedReader().use { it.readText() }) }
                        .getOrNull()
                }
                // A test with no opener yet must not freeze "no map" for the run.
                if (stream != null || appContext != null) cache[base] = map
                return map
            }
        }
    }
}

/** `"a1"` … `"c2"`; anything else fails the decode, as Swift's
 *  `CEFRLevel` does (a broken map is no map, never a map at B1). */
object StrictCefrSerializer : KSerializer<CefrLevel> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("StrictCefr", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: CefrLevel) = encoder.encodeString(value.code)

    override fun deserialize(decoder: Decoder): CefrLevel {
        val raw = decoder.decodeString()
        return CefrLevel.entries.firstOrNull { it.code == raw }
            ?: throw kotlinx.serialization.SerializationException("not a CEFR level: $raw")
    }
}
