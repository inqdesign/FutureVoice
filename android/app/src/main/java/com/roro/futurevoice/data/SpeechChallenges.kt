package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.time.OffsetDateTime
import kotlin.math.roundToInt

/**
 * Speech challenges — iOS `SpeechChallenges`: scripts the founder publishes
 * for every learner of a target language, each with a leaderboard
 * (`20261010150000_speech_challenges`). A challenge IS a [SpeechScript] whose
 * id is the challenge's id, so the prompter, the takes and the result page
 * need nothing new.
 *
 * Rules held here: a take is entered only when the camera recorded it, and
 * nothing but a name and a score ever leaves the phone.
 */
class SpeechChallenges private constructor(private val context: Context) {

    /** One of the top three on a board, as the list row draws them. */
    @Serializable
    data class Face(
        val display_name: String,
        /** Base64 JPEG (~96 px), only when that learner chose to show a photo. */
        val avatar: String? = null,
    ) {
        fun bitmap(): android.graphics.Bitmap? = avatar?.let {
            runCatching {
                val bytes = android.util.Base64.decode(it, android.util.Base64.DEFAULT)
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }

    /** Where the learner stands on one board. */
    @Serializable
    data class Standing(
        val entrants: Int = 0,
        val topScore: Int? = null,
        val myBest: Int? = null,
        val myRank: Int? = null,
        val myAttempts: Int? = null,
        val topThree: List<Face>? = null,
        /** Set once retired: the board is frozen, nobody can enter. */
        val retiredAt: Long? = null,
    )

    @Serializable
    data class BoardRow(
        val rank: Int,
        val display_name: String,
        val score: Int,
        val is_me: Boolean = false,
        /** Base64 JPEG, only when that learner chose to show a photo. */
        val avatar: String? = null,
    ) {
        val face: Face get() = Face(display_name, avatar)
    }

    /** What a take did on the board — iOS `SpeechChallengeMoment`. */
    data class Moment(
        val kind: Kind,
        val rank: Int,
        val previousRank: Int?,
        val entrants: Int,
        val score: Int,
        /** The row above (if any), the learner's, the row below (if any). */
        val neighbors: List<BoardRow>,
    ) {
        enum class Kind { DEBUT, UP, PODIUM }
        val above: BoardRow? get() = neighbors.lastOrNull { !it.is_me && it.rank < rank }
        val below: BoardRow? get() = neighbors.firstOrNull { !it.is_me && it.rank > rank }

        companion object {
            /** Null when it's not a moment: a sheet only for a first entry,
             *  a climb, or a better take inside the top three. */
            fun make(rank: Int, previousRank: Int?, entrants: Int, best: Int, improved: Boolean,
                     board: List<BoardRow>): Moment? {
                if (!improved) return null
                val kind = when {
                    rank <= 3 -> Kind.PODIUM
                    previousRank == null -> Kind.DEBUT
                    rank < previousRank -> Kind.UP
                    else -> return null
                }
                val i = board.indexOfFirst { it.is_me }
                val neighbors = if (i < 0) emptyList() else listOfNotNull(board.getOrNull(i - 1), board[i], board.getOrNull(i + 1))
                return Moment(kind, rank, previousRank, entrants, best, neighbors)
            }
        }
    }

    /** What became of one take, for its result page. */
    sealed interface Entry {
        data object Submitting : Entry
        data class Entered(val rank: Int, val previousRank: Int?, val entrants: Int,
                           val best: Int, val improved: Boolean) : Entry
        /** The camera was off — the board only takes camera takes. */
        data object CameraOff : Entry
        data object Failed : Entry
    }

    private val _scripts = MutableStateFlow<List<SpeechScript>>(emptyList())
    val scripts: StateFlow<List<SpeechScript>> = _scripts
    private val _standings = MutableStateFlow<Map<String, Standing>>(emptyMap())
    val standings: StateFlow<Map<String, Standing>> = _standings
    /** By take id. In memory: the page that matters is the one the take
     *  opens on; later visits read the standing instead. */
    private val _entries = MutableStateFlow<Map<String, Entry>>(emptyMap())
    val entries: StateFlow<Map<String, Entry>> = _entries
    /** By take id: the sheet a better take raises once, over its result. */
    private val _moments = MutableStateFlow<Map<String, Moment>>(emptyMap())
    val moments: StateFlow<Map<String, Moment>> = _moments
    fun dismissMoment(takeId: String) { _moments.value = _moments.value - takeId }

    @Volatile private var loadedLanguage: String? = null

    private val auth = AuthRepository()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @Serializable
    private data class Cache(val scripts: List<SpeechScript> = emptyList(),
                             val standings: Map<String, Standing> = emptyMap())

    private fun cacheFile(language: String) =
        File(LanguageScope.directory(context, language), "speech_challenges.json")

    fun script(id: String): SpeechScript? = _scripts.value.firstOrNull { it.id == id }

    fun isPast(id: String): Boolean = _standings.value[id]?.retiredAt != null

    /** The last list per language, so a take's result page finds its script
     *  offline and the tab draws before the network answers. */
    @Synchronized
    fun loadCache(language: String) {
        if (loadedLanguage == language) return
        loadedLanguage = language
        val cache = runCatching {
            StoreJson.json.decodeFromString(Cache.serializer(), cacheFile(language).readText())
        }.getOrNull()
        _scripts.value = cache?.scripts.orEmpty()
        _standings.value = cache?.standings.orEmpty()
    }

    // MARK: - Reading

    @Serializable
    private data class ListRow(
        val id: String,
        val title: String,
        val genre: String = "explainer",
        val body: String,
        val summary: String = "",
        val key_terms: List<SpeechKeyTerm>? = null,
        val sources: List<String>? = null,
        val target_seconds: Int = 60,
        val published_at: String,
        val retired_at: String? = null,
        val entrants: Int? = null,
        val top_score: Int? = null,
        val my_best: Int? = null,
        val my_rank: Int? = null,
        val my_attempts: Int? = null,
        val top_three: List<Face>? = null,
    )

    suspend fun refresh(language: String) {
        loadCache(language)
        val rows = runCatching {
            Edge.json.decodeFromString(ListSerializer(ListRow.serializer()),
                rpc("speech_challenge_list", buildJsonObject { put("p_language", language) }))
        }.getOrNull() ?: return
        if (loadedLanguage != language) return
        _scripts.value = rows.map { row ->
            SpeechScript(
                id = row.id, title = row.title,
                genre = SpeechGenre.entries.firstOrNull { it.raw == row.genre } ?: SpeechGenre.EXPLAINER,
                body = row.body, summary = row.summary, keyTerms = row.key_terms.orEmpty(),
                sources = row.sources.orEmpty(), language = language,
                targetSeconds = row.target_seconds,
                createdAt = runCatching { OffsetDateTime.parse(row.published_at).toInstant().toEpochMilli() }
                    .getOrDefault(System.currentTimeMillis()),
                isBuiltIn = false, challengeId = row.id,
            )
        }
        _standings.value = rows.associate { row ->
            row.id to Standing(row.entrants ?: 0, row.top_score, row.my_best, row.my_rank, row.my_attempts, row.top_three,
                row.retired_at?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() })
        }
        writeCache(language)
        importLocalBests()
    }

    // MARK: - Takes made before the board existed

    private val importing = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    /**
     * Takes already on this phone count too — iOS `importLocalBests`. Once
     * the learner has confirmed their name (the consent to be on a board),
     * their best earlier CAMERA take (video still kept) of each challenge
     * goes up if it beats the board. A take of an older text under the same
     * id is never entered: its transcript is re-scored against today's
     * script and must agree with the accuracy it was given.
     */
    suspend fun importLocalBests() {
        val name = displayName(context) ?: return
        val store = SpeechStore.shared(context)
        for (script in _scripts.value) {
            val challengeId = script.challengeId ?: continue
            if (isPast(challengeId)) continue
            if (!importing.add(challengeId)) continue
            try {
                val onBoard = _standings.value[challengeId]?.myBest ?: -1
                val candidates = store.takes(script.id)
                    .filter { it.videoFilename != null && it.metrics.overall > onBoard }
                    .sortedByDescending { it.metrics.overall }
                for (take in candidates) {
                    val accuracy = withContext(Dispatchers.Default) {
                        com.roro.futurevoice.talk.ShadowScore.analyze(script.body,
                            com.roro.futurevoice.talk.SpeechAnalyzer.removingFillers(take.transcript, script.language, script.body),
                            script.language).score
                    }
                    if (kotlin.math.abs(accuracy - take.metrics.accuracy) > 5) continue
                    submit(take, challengeId, name)
                    Analytics.capture("speech_challenge_imported", mapOf("overall" to take.metrics.overall))
                    break
                }
            } finally {
                importing.remove(challengeId)
            }
        }
    }

    suspend fun board(challengeId: String, limit: Int = 10): List<BoardRow>? = runCatching {
        Edge.json.decodeFromString(ListSerializer(BoardRow.serializer()),
            rpc("speech_challenge_board", buildJsonObject {
                put("p_challenge", challengeId); put("p_limit", limit)
            }))
    }.getOrNull()

    // MARK: - Entering a take

    /** Called by the take session once a take on a challenge is scored. */
    fun enter(take: SpeechTake, script: SpeechScript, recordedOnCamera: Boolean) {
        val challengeId = script.challengeId ?: return
        if (!recordedOnCamera) { setEntry(take.id, Entry.CameraOff); return }
        val name = displayName(context) ?: run { setEntry(take.id, Entry.Failed); return }
        setEntry(take.id, Entry.Submitting)
        scope.launch { submit(take, challengeId, name) }
    }

    private fun setEntry(takeId: String, entry: Entry) {
        _entries.value = _entries.value + (takeId to entry)
    }

    @Serializable
    private data class SubmitRow(
        val rank: Int,
        val previous_rank: Int? = null,
        val entrants: Int,
        val best: Int,
        val improved: Boolean,
    )

    private suspend fun submit(take: SpeechTake, challengeId: String, name: String) {
        val m = take.metrics
        try {
            val raw = rpc("submit_speech_challenge_take", buildJsonObject {
                put("p_challenge", challengeId)
                put("p_display_name", name)
                put("p_avatar", avatarPayload(context))
                put("p_overall", m.overall)
                put("p_accuracy", m.accuracy)
                put("p_pace", m.paceScore)
                put("p_pause", m.pauseScore)
                put("p_filler", m.fillerScore)
                put("p_steadiness", m.steadiness)
                put("p_seconds", maxOf(1, take.durationSeconds.roundToInt()))
            })
            val row = Edge.json.decodeFromString(ListSerializer(SubmitRow.serializer()), raw).firstOrNull()
                ?: run { setEntry(take.id, Entry.Failed); return }
            setEntry(take.id, Entry.Entered(row.rank, row.previous_rank, row.entrants, row.best, row.improved))
            if (row.improved) board(challengeId, 50)?.let { b ->
                Moment.make(row.rank, row.previous_rank, row.entrants, row.best, row.improved, b)?.let {
                    _moments.value = _moments.value + (take.id to it)
                }
            }
            val old = _standings.value[challengeId] ?: Standing()
            _standings.value = _standings.value + (challengeId to old.copy(
                entrants = row.entrants, myBest = row.best, myRank = row.rank,
                myAttempts = (old.myAttempts ?: 0) + 1,
                topScore = maxOf(old.topScore ?: 0, row.best),
            ))
            loadedLanguage?.let { writeCache(it) }
            Analytics.capture("speech_challenge_entered", mapOf(
                "overall" to m.overall, "rank" to row.rank, "entrants" to row.entrants,
                "improved" to row.improved,
            ))
        } catch (e: Exception) {
            setEntry(take.id, Entry.Failed)
            Analytics.capture("speech_challenge_failed", mapOf("error" to e.toString().take(160)))
        }
    }

    /** The name sheet was saved: every board shows the new name (and photo
     *  choice) at once, not only after the next take. */
    suspend fun saveProfile() {
        val name = displayName(context) ?: return
        runCatching {
            rpc("set_speech_challenge_profile", buildJsonObject {
                put("p_display_name", name)
                put("p_avatar", avatarPayload(context))
            })
        }
        loadedLanguage?.let { refresh(it) }
    }

    // MARK: - Publishing (admin accounts)

    /** Puts one of the admin's own scripts on every learner's Speech tab. */
    suspend fun publish(script: SpeechScript) {
        rpc("publish_speech_challenge", buildJsonObject {
            put("p_language", script.language)
            put("p_title", script.title)
            put("p_genre", script.genre.raw)
            put("p_body", script.body)
            put("p_summary", script.summary)
            putJsonArray("p_key_terms") {
                script.keyTerms.forEach { t -> addJsonObject { put("term", t.term); put("meaning", t.meaning) } }
            }
            putJsonArray("p_sources") { script.sources.forEach { add(it) } }
            put("p_target_seconds", script.targetSeconds)
        })
        refresh(script.language)
    }

    suspend fun retire(challengeId: String) {
        rpc("retire_speech_challenge", buildJsonObject { put("p_challenge", challengeId) })
        loadedLanguage?.let { refresh(it) }
    }

    private fun writeCache(language: String) {
        runCatching {
            cacheFile(language).writeText(StoreJson.json.encodeToString(Cache.serializer(),
                Cache(_scripts.value, _standings.value)))
        }
    }

    private suspend fun rpc(name: String, body: JsonObject): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            raw
        }
    }

    companion object {
        @Volatile private var instance: SpeechChallenges? = null
        fun shared(context: Context): SpeechChallenges =
            instance ?: synchronized(this) {
                instance ?: SpeechChallenges(context.applicationContext).also { instance = it }
            }

        private const val PREFS = "speech_challenge"
        private const val NAME_KEY = "speech.challenge.displayName"
        const val MAX_NAME_LENGTH = 24

        /** The one name a learner goes by on every board. Null until they
         *  have seen and confirmed it — nothing goes on a public board unasked. */
        fun displayName(context: Context): String? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(NAME_KEY, null)?.trim()?.takeIf { it.isNotEmpty() }

        private const val PHOTO_KEY = "speech.challenge.showPhoto"

        /** Whether the learner's profile photo goes beside their name — asked
         *  in the name sheet, next to the photo itself. */
        fun showsPhoto(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(PHOTO_KEY, true)

        fun setShowsPhoto(context: Context, value: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(PHOTO_KEY, value).apply()
        }

        /** The photo as the board stores it: a ~96 px JPEG, base64. Null when
         *  there is no photo or the learner chose not to show it. */
        fun avatarPayload(context: Context): String? {
            if (!showsPhoto(context)) return null
            val bitmap = AvatarStore.load(context) ?: return null
            val small = android.graphics.Bitmap.createScaledBitmap(bitmap, 96, 96, true)
            val out = java.io.ByteArrayOutputStream()
            small.compress(android.graphics.Bitmap.CompressFormat.JPEG, 70, out)
            return android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
        }

        fun setDisplayName(context: Context, name: String) {
            val clean = name.trim().take(MAX_NAME_LENGTH)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(NAME_KEY, clean.ifEmpty { null }).apply()
        }
    }
}
