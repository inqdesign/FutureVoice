package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder

/**
 * A word or phrase's meaning, in the learner's own language.
 *
 * A dictionary entry is the same for everybody who shares a (native, target)
 * pair, so it is a GLOBAL shared cache and is never metered: the read hits the
 * `word_entry` table directly, and only a miss wakes the `word-entry`
 * function, which generates the entry and publishes the row for whoever asks
 * next. Both halves already exist server-side (iOS `WordLore`), so this is a
 * client and nothing more — no prompt here, and none wanted.
 */
class WordLore(private val auth: AuthRepository) {

    @Serializable
    data class Sense(val pos: String = "", val meaning: String = "", val note: String? = null)

    @Serializable
    data class Phrase(val phrase: String = "", val meaning: String = "")

    @Serializable
    data class Example(val text: String = "", val meaning: String? = null)

    @Serializable
    data class Entry(
        val pos: String? = null,
        val senses: List<Sense> = emptyList(),
        val examples: List<Example> = emptyList(),
        val phrases: List<Phrase> = emptyList(),
        val properNoun: String? = null,
    )

    enum class Kind(val raw: String) { WORD("word"), EXPRESSION("expression") }

    @Serializable private data class Row(val data: Entry)
    @Serializable private data class LookupResponse(val data: Entry)

    companion object {
        private val cache = HashMap<String, Entry>()
    }

    suspend fun entry(word: String, native: String, target: String,
                      kind: Kind = Kind.WORD): Entry? {
        val key = listOf(native, target, kind.raw, word).joinToString("|")
        synchronized(cache) { cache[key] }?.let { return it }
        return cached(word, native, target, kind) ?: generate(word, native, target, kind)
    }

    /** The shared table. Free, and skips a function cold start on a hit. */
    private suspend fun cached(word: String, native: String, target: String,
                               kind: Kind): Entry? = withContext(Dispatchers.IO) {
        runCatching {
            fun q(v: String) = URLEncoder.encode(v, "UTF-8")
            val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/word_entry?select=data" +
                "&word=eq.${q(word)}&native_lang=eq.${q(native)}" +
                "&target_lang=eq.${q(target)}&kind=eq.${q(kind.raw)}&limit=1"
            val request = Request.Builder().url(url)
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                if (resp.code !in 200..299) return@runCatching null
                Edge.json.decodeFromString(ListSerializer(Row.serializer()), resp.body.string())
                    .firstOrNull()?.data
            }
        }.getOrNull()?.also { remember(native, target, kind, word, it) }
        // A DECODE failure here looks exactly like a miss, and falling through
        // to generation is the right answer anyway: it republishes the row,
        // where returning null would fail this word forever, silently.
    }

    private suspend fun generate(word: String, native: String, target: String,
                                 kind: Kind): Entry? = withContext(Dispatchers.IO) {
        runCatching {
            val body = buildJsonObject {
                put("word", word); put("native_lang", native)
                put("target_lang", target); put("kind", kind.raw)
            }
            val request = Request.Builder()
                .url(Config.functionUrl("word-entry"))
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                val raw = resp.body.string()
                if (resp.code !in 200..299) return@runCatching null
                Edge.json.decodeFromString(LookupResponse.serializer(), raw).data
            }
        }.getOrNull()?.also { remember(native, target, kind, word, it) }
    }

    private fun remember(native: String, target: String, kind: Kind, word: String, e: Entry) {
        synchronized(cache) { cache[listOf(native, target, kind.raw, word).joinToString("|")] = e }
    }
}
