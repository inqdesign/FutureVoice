package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.URLEncoder

/**
 * The words and expressions learners added that the bundled graded list
 * doesn't carry — one library per target language, shared by everyone who
 * learns it (iOS `SharedLibrary`). `library_terms` is written only by the
 * `library-add` function, which reads every entry first: a typo, a made-up
 * word or a name never goes in.
 *
 * Words join [CoreVocabulary]'s pool with their level; expressions are the
 * Expressions page's All lens. A local copy per language lives in the cache
 * dir and is read when a pool is built; [refresh] pulls only what changed.
 */
object SharedLibrary {

    @Serializable
    data class Term(val term: String, val kind: String, val level: String) {
        val key: String get() = term.lowercase()
        val cefr: CefrLevel? get() = CefrLevel.entries.firstOrNull { it.code == level }
    }

    @Serializable
    private data class Snapshot(
        val terms: List<Term> = emptyList(),
        val since: String? = null,
        val fetchedAt: Long? = null,
    )

    @Serializable
    private data class Row(val term: String, val kind: String, val level: String, val updated_at: String)

    @Volatile private var appContext: Context? = null
    private val snapshots = HashMap<String, Snapshot>()

    fun init(context: Context) { appContext = context.applicationContext }

    private fun file(language: String): File? = appContext?.let {
        File(it.cacheDir, "shared_library").apply { mkdirs() }.resolve("$language.json")
    }

    private fun snapshot(language: String): Snapshot = synchronized(snapshots) {
        snapshots.getOrPut(language) {
            runCatching {
                Edge.json.decodeFromString(Snapshot.serializer(), file(language)!!.readText())
            }.getOrDefault(Snapshot())
        }
    }

    private fun store(s: Snapshot, language: String) {
        synchronized(snapshots) { snapshots[language] = s }
        runCatching { file(language)?.writeText(Edge.json.encodeToString(Snapshot.serializer(), s)) }
    }

    fun words(language: String): List<Term> = snapshot(language).terms.filter { it.kind == "word" }
    fun expressions(language: String): List<Term> = snapshot(language).terms.filter { it.kind == "expression" }

    fun expressionLevel(phrase: String, language: String): CefrLevel? {
        val key = phrase.trim().lowercase()
        return expressions(language).firstOrNull { it.key == key }?.cefr
    }

    private fun merge(incoming: List<Term>, since: String?, language: String, fetched: Boolean) {
        val s = snapshot(language)
        val byKey = LinkedHashMap<String, Term>()
        s.terms.forEach { byKey["${it.kind}|${it.key}"] = it }
        incoming.forEach { byKey["${it.kind}|${it.key}"] = it }
        store(s.copy(
            terms = byKey.values.sortedBy { it.key },
            since = listOfNotNull(s.since, since).maxOrNull(),
            fetchedAt = if (fetched) System.currentTimeMillis() else s.fetchedAt,
        ), language)
        if (incoming.isNotEmpty()) CoreVocabulary.invalidate(language)
    }

    fun adopt(term: Term, language: String) = merge(listOf(term), null, language, false)

    /** Pull what changed since the last pull, at most every few hours. */
    suspend fun refreshIfStale(auth: AuthRepository, language: String) {
        val at = snapshot(language).fetchedAt
        if (at != null && System.currentTimeMillis() - at < 6 * 3600_000L) return
        refresh(auth, language)
    }

    suspend fun refresh(auth: AuthRepository, language: String) = withContext(Dispatchers.IO) {
        val token = runCatching { auth.accessToken() }.getOrNull() ?: return@withContext
        var cursor = snapshot(language).since ?: "1970-01-01T00:00:00Z"
        val all = ArrayList<Term>()
        // Pages of 1,000, oldest change first, so a cut-off pull resumes.
        repeat(20) {
            val path = "library_terms?select=term,kind,level,updated_at" +
                "&target_lang=eq.${enc(language)}&updated_at=gt.${enc(cursor)}" +
                "&order=updated_at.asc&limit=1000"
            val rows = runCatching {
                val req = Request.Builder()
                    .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/$path")
                    .header("Authorization", "Bearer $token")
                    .header("apikey", Config.supabaseAnonKey)
                    .build()
                Edge.client.newCall(req).execute().use { resp ->
                    if (resp.code !in 200..299) null
                    else Edge.json.decodeFromString(ListSerializer(Row.serializer()), resp.body.string())
                }
            }.getOrNull() ?: return@withContext
            all += rows.map { Term(it.term, it.kind, it.level) }
            rows.lastOrNull()?.let { cursor = it.updated_at }
            if (rows.size < 1000) {
                merge(all, cursor, language, true)
                return@withContext
            }
        }
        merge(all, cursor, language, true)
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    sealed interface AddResult {
        /** In the library now (or already was), as its dictionary form. */
        data class Added(val term: Term) : AddResult
        /** Misspelt; this is what was probably meant. */
        data class Typo(val suggestion: String) : AddResult
        /** Not something the library takes (the server's reason). */
        data class Rejected(val reason: String) : AddResult
        data object Failed : AddResult
    }

    @Serializable
    private data class AddResponse(
        val status: String = "",
        val term: String? = null,
        val level: String? = null,
        val suggestion: String? = null,
        val reason: String? = null,
    )

    suspend fun add(auth: AuthRepository, text: String, kind: String,
                    target: String, native: String): AddResult = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("text", text); put("kind", kind); put("target_lang", target); put("native_lang", native)
        }
        val res = runCatching {
            val req = Request.Builder().url(Config.functionUrl("library-add"))
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(req).execute().use { r ->
                if (r.code !in 200..299) null
                else Edge.json.decodeFromString(AddResponse.serializer(), r.body.string())
            }
        }.getOrNull() ?: return@withContext AddResult.Failed
        when (res.status) {
            "ok" -> {
                val term = res.term ?: return@withContext AddResult.Failed
                val level = res.level ?: return@withContext AddResult.Failed
                Term(term, kind, level).also { adopt(it, target) }.let { AddResult.Added(it) }
            }
            "typo" -> res.suggestion?.let { AddResult.Typo(it) } ?: AddResult.Rejected("not_real")
            else -> AddResult.Rejected(res.reason ?: "not_real")
        }
    }
}
