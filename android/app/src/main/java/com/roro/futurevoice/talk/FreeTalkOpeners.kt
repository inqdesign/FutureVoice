package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Rotating pools of free-talk greeting lines, one per language + persona
 * (`freetalk_openers_by_language.json`, iOS `58d6802`). One Gemini call writes six openers; sessions rotate through them,
 * so the first line of a free talk never waits on the model. Topic, scenario
 * and news openers stay dynamic — this pool is only for the no-topic talk.
 *
 * Keyed to language + persona name and regenerated when either changes.
 * Until a pool exists, [fallbackOpener] speaks; on the very first free talk,
 * before the fluent self has met the learner, [introOpener] outranks both —
 * a rotating "good to hear you" is a greeting between people who already
 * know each other.
 */
class FreeTalkOpeners(private val context: Context) {

    @Serializable
    private data class Pool(
        val key: String,
        val lines: List<String>,
        val cursor: Int = 0,
        @Serializable(with = com.roro.futurevoice.data.IsoDateMillisSerializer::class)
        val generatedAt: Long = System.currentTimeMillis(),
    )

    @Serializable
    private data class Payload(val openers: List<String> = emptyList())

    /**
     * One pool PER language + persona, in one file. Until 2026-09-28 the file
     * held a single pool, so a learner who talked in two languages threw one
     * language's pool away every time they used the other — each switch
     * meant a new Gemini call, the bundled fallback line in the meantime, and
     * new ElevenLabs takes of lines whose audio had already been paid for.
     * The old single-pool file is read once and folded in (never deleted).
     */
    @Serializable
    private data class Store(val pools: Map<String, Pool> = emptyMap())

    companion object {
        private const val BAKED_SPEED_KEY = "futurevoice.freeTalkOpeners.bakedSpeed"
        private const val BAKED_LINES_KEY = "futurevoice.freeTalkOpeners.bakedLines"
        private const val TAG = "FreeTalkOpeners"

        /**
         * Bumped when the pool's PROMPT changes in a way the lines already on
         * phones must not outlive: a pool is otherwise kept until the language
         * or name changes, i.e. forever. v2 (iOS `a212c70`, 2026-09-30):
         * `selfWarmth` — pools held "너무 보고싶어". An old pool is simply not
         * found; its audio stays on disk (produced audio is never deleted).
         */
        private const val POOL_VERSION = 2

        /** Languages × persona names a learner actually uses is a handful; the
         *  cap only stops a long history of renames from growing the file. */
        private const val MAX_POOLS = 8

        private fun key(language: String, personaName: String?) =
            "v$POOL_VERSION|" + language.take(2) + "|" + personaName.orEmpty().trim()

        /** Failures only — one row each, never a success, so the volume is
         *  the number of things that went wrong (iOS `report`). */
        private fun report(event: String, language: String?, error: Throwable) {
            if (error is kotlinx.coroutines.CancellationException) return
            val reason = error.toString().take(200)
            android.util.Log.w(TAG, "$event: $reason")
            com.roro.futurevoice.core.Telemetry.log(
                event, buildMap { put("error", reason); language?.let { put("language", it) } })
        }

        fun introOpener(language: String): String =
            FreeTalkOpenerContent.intro[language.take(2)] ?: FreeTalkOpenerContent.intro.getValue("en")

        fun fallbackOpener(language: String): String =
            FreeTalkOpenerContent.fallback[language.take(2)] ?: FreeTalkOpenerContent.fallback.getValue("en")
    }

    /** The single-pool file from before 2026-09-28 — read for migration only. */
    private val legacyFile = File(context.filesDir, "freetalk_openers.json")
    private val file = File(context.filesDir, "freetalk_openers_by_language.json")

    fun hasPool(language: String, personaName: String?): Boolean =
        load(key(language, personaName))?.lines?.isNotEmpty() == true

    /**
     * Synthesize every line of the pool into the phrase cache, so the call's
     * FIRST word is already on the phone when the learner taps — the greeting
     * used to wait on the gateway's own ElevenLabs round trip for a line that
     * could have been on disk since the tab was opened (iOS `26a246c`).
     *
     * A line already cached costs nothing; the lineage is deliberately NOT
     * consulted, because a greeting has to be in the CURRENT voice.
     */
    suspend fun warmAudio(language: String, personaName: String?, voiceId: String?) {
        if (voiceId.isNullOrBlank()) return
        val store = com.roro.futurevoice.data.PhraseAudioStore.shared(context)
        val lines = buildList {
            add(introOpener(language))
            add(fallbackOpener(language))
            load(key(language, personaName))?.let { addAll(it.lines) }
        }
        for (line in lines.distinct()) {
            // The ONE exception to "produced audio is kept": the lines that
            // open a call are re-made whenever the speed moves, or the
            // greeting plays at the old speed and every answer after it at
            // the new one — on every call (iOS `needsBake`, 2026-09-25).
            if (store.data(line, voiceId) != null && !needsBake(line)) continue
            val audio = try {
                // A line of several sentences is made sentence by sentence so
                // it breathes like the answers after it (see `PacedSpeech`);
                // a one-sentence line, or an edge with no streaming, takes the
                // ordinary single synthesis.
                PacedSpeech.synthesizeWav(
                    voiceId = voiceId, text = line,
                    modelId = com.roro.futurevoice.net.ElevenLabsClient.CONVERSATION_MODEL_ID,
                    purpose = "turn",
                ) ?: com.roro.futurevoice.net.ElevenLabsClient(com.roro.futurevoice.data.AuthRepository())
                    .synthesize(voiceId = voiceId, text = line, purpose = "turn")
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                report("opener_audio_failed", null, e)
                return   // no network, or a wall — try again later
            }
            store.save(audio, line, voiceId)
            markBaked(line)
        }
    }

    private val bakePrefs get() = context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)

    private fun needsBake(line: String): Boolean {
        val current = com.roro.futurevoice.data.SpeechSpeed.currentMultiplier()?.toFloat() ?: return false
        val p = bakePrefs
        if (p.getFloat(BAKED_SPEED_KEY, Float.NaN) != current) {
            // The speed moved (or this build is the first to ask): every
            // line on file was made at some other speed.
            p.edit().putFloat(BAKED_SPEED_KEY, current).remove(BAKED_LINES_KEY).apply()
            return true
        }
        return line !in (p.getString(BAKED_LINES_KEY, null)?.split('\n').orEmpty())
    }

    private fun markBaked(line: String) {
        val lines = bakePrefs.getString(BAKED_LINES_KEY, null)?.split('\n').orEmpty().toMutableList()
        if (line in lines) return
        lines.add(line)
        bakePrefs.edit().putString(BAKED_LINES_KEY, lines.takeLast(60).joinToString("\n")).apply()
    }

    /** The next line in rotation, advancing the cursor; null without a pool. */
    fun next(language: String, personaName: String?): String? {
        val pool = load(key(language, personaName)) ?: return null
        if (pool.lines.isEmpty()) return null
        val line = pool.lines[pool.cursor % pool.lines.size]
        save(pool.copy(cursor = (pool.cursor + 1) % pool.lines.size))
        return line
    }

    suspend fun generatePool(language: String, personaName: String?, level: CefrLevel): List<String> =
        try {
            writePool(language, personaName, level)
        } catch (e: Exception) {
            // Every caller discards this with runCatching, and a pool that is
            // never written is a call that opens on the fallback line forever.
            report("freetalk_openers_failed", language, e)
            throw e
        }

    private suspend fun writePool(language: String, personaName: String?, level: CefrLevel): List<String> {
        val name = personaName?.takeIf { it.isNotBlank() } ?: "the learner"
        val payload = GeminiClient(AuthRepository()).sendJson(
            system = FreeTalkOpenerContent.poolPrompt(
                LanguageCatalog.englishName(language), level.code.uppercase(), name),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "Write the greetings.")),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_LITE_31,
            maxTokens = 512,
            purpose = "freetalk-openers",
            idempotencyKey = "freetalk-openers:" + key(language, personaName),
        )
        val lines = payload.openers.map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isNotEmpty()) save(Pool(key(language, personaName), lines, cursor = 0))
        return lines
    }

    private fun loadStore(): Store {
        runCatching {
            if (file.exists()) return StoreJson.json.decodeFromString(Store.serializer(), file.readText())
        }
        runCatching {
            if (legacyFile.exists()) {
                val legacy = StoreJson.json.decodeFromString(Pool.serializer(), legacyFile.readText())
                return Store(mapOf(legacy.key to legacy))
            }
        }
        return Store()
    }

    private fun load(key: String): Pool? = loadStore().pools[key]?.takeIf { it.key == key }

    private fun save(pool: Pool) {
        var pools = loadStore().pools + (pool.key to pool)
        if (pools.size > MAX_POOLS) {
            pools = pools.values.sortedByDescending { it.generatedAt }.take(MAX_POOLS)
                .associateBy { it.key }
        }
        runCatching { file.writeText(StoreJson.json.encodeToString(Store.serializer(), Store(pools))) }
    }
}
