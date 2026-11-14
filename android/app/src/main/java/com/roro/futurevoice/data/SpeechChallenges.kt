package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.talk.SpeechReadingScore
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
        /** Every take anyone has put up — what the card counts. Null from a server that doesn't send it. */
        val attempts: Int? = null,
        /** What kind of challenge it is ("show_host", …); the card names it. Null on older ones. */
        val category: String? = null,
        /** What it is and what to keep in mind, per app language ("ko", "zh-Hant", …). */
        val intro: Map<String, String>? = null,
        /** The original (a video of the speech), opened outside the app. */
        val link: String? = null,
        /** Which season it belongs to. Null from a server without seasons, or
         *  a cache written before them. */
        val season: Int? = null,
    ) {
        /** The intro in the app's language, then English (iOS `SpeechChallenges.intro`). */
        fun introFor(appLanguage: String): String? {
            val map = intro ?: return null
            return (map[appLanguage] ?: map[appLanguage.substringBefore('-')] ?: map["en"])
                ?.takeIf { it.isNotBlank() }
        }
    }

    /** One of a language's seasons, as this account sees them. */
    @Serializable
    data class SeasonStatus(val season: Int, val min_scoring: Int, val is_open: Boolean, val ended: Boolean)

    /** My score on a challenge as a past season froze it (iOS 01529ba7: English
     *  Season 1's challenges went live again in Season 2, their old results
     *  kept apart so Season 1's standings never move). */
    @Serializable
    data class SeasonRecord(val challenge_id: String, val season: Int, val score: Int, val rank: Int, val entrants: Int)

    @Serializable
    data class BoardRow(
        val rank: Int,
        val display_name: String,
        val score: Int,
        val is_me: Boolean = false,
        /** Base64 JPEG, only when that learner chose to show a photo. */
        val avatar: String? = null,
        /** Their cube's colour (theme index) when seated in the Core of this
         *  challenge's language today; null otherwise (iOS `core_theme`). */
        val core_theme: Int? = null,
        /** On the overall board: how many challenges the total is made of
         *  (iOS `challenges`); null on a challenge's own board. */
        val challenges: Int? = null,
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
        /** Scored by Season 2's rules on a board that doesn't take them. */
        data object NewScoring : Entry
        /** On a challenge that has ended: the board is frozen, so this was practice. */
        data object Practice : Entry
    }

    private val _scripts = MutableStateFlow<List<SpeechScript>>(emptyList())
    val scripts: StateFlow<List<SpeechScript>> = _scripts
    private val _standings = MutableStateFlow<Map<String, Standing>>(emptyMap())
    val standings: StateFlow<Map<String, Standing>> = _standings
    /** The overall board's top of the loaded language (and the learner's own
     *  row), for the Speech tab's banner — iOS `overall`. Null until it loads. */
    private val _overall = MutableStateFlow<List<BoardRow>?>(null)
    val overall: StateFlow<List<BoardRow>?> = _overall
    /** The season [overall] is the board of. Null: a server without seasons. */
    private val _overallSeason = MutableStateFlow<Int?>(null)
    val overallSeason: StateFlow<Int?> = _overallSeason
    /** The loaded language's seasons; empty from a server without them. */
    private val _seasons = MutableStateFlow<List<SeasonStatus>>(emptyList())
    val seasons: StateFlow<List<SeasonStatus>> = _seasons
    /** By challenge id: my frozen score from an earlier season of it. */
    private val _seasonRecords = MutableStateFlow<Map<String, SeasonRecord>>(emptyMap())
    val seasonRecords: StateFlow<Map<String, SeasonRecord>> = _seasonRecords
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

    fun season(id: String): Int? = _standings.value[id]?.season

    /** The newest season taking entries. */
    fun openSeason(seasons: List<SeasonStatus> = _seasons.value): Int? =
        seasons.filter { it.is_open }.maxOfOrNull { it.season }

    /** The newest season that has ended. */
    fun lastEndedSeason(seasons: List<SeasonStatus> = _seasons.value): Int? =
        seasons.filter { it.ended }.maxOfOrNull { it.season }

    /** Seasons with past challenges, newest first. */
    fun pastSeasons(scripts: List<SpeechScript> = _scripts.value,
                    standings: Map<String, Standing> = _standings.value): List<Int> =
        scripts.filter { standings[it.id]?.retiredAt != null }
            .mapNotNull { standings[it.id]?.season }.distinct().sortedDescending()

    /** Every season that has a board, newest first: open and ended. */
    fun boardSeasons(seasons: List<SeasonStatus> = _seasons.value): List<Int> =
        seasons.filter { it.is_open || it.ended }.map { it.season }.sortedDescending()

    fun seasonEnded(season: Int, seasons: List<SeasonStatus> = _seasons.value): Boolean =
        seasons.firstOrNull { it.season == season }?.ended == true

    /** The last list per language, so a take's result page finds its script
     *  offline and the tab draws before the network answers. */
    @Synchronized
    fun loadCache(language: String) {
        if (loadedLanguage == language) return
        loadedLanguage = language
        _overall.value = null
        _overallSeason.value = null
        _seasons.value = emptyList()
        _seasonRecords.value = emptyMap()
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
        val attempts: Int? = null,
        val category: String? = null,
        val intro: Map<String, String>? = null,
        val link: String? = null,
        val season: Int? = null,
    )

    private suspend fun seasonStatus(language: String): List<SeasonStatus> = runCatching {
        Edge.json.decodeFromString(ListSerializer(SeasonStatus.serializer()),
            rpc("speech_season_status", buildJsonObject { put("p_language", language) }))
    }.getOrDefault(emptyList())

    private suspend fun mySeasonRecords(language: String): List<SeasonRecord> = runCatching {
        Edge.json.decodeFromString(ListSerializer(SeasonRecord.serializer()),
            rpc("my_speech_season_records", buildJsonObject { put("p_language", language) }))
    }.getOrDefault(emptyList())

    /** The list that knows seasons, or the old one from a server without it. */
    private suspend fun listRows(language: String): List<ListRow> {
        val serializer = ListSerializer(ListRow.serializer())
        runCatching {
            Edge.json.decodeFromString(serializer, rpc("speech_challenge_list_v2", buildJsonObject {
                put("p_language", language)
                put("p_scoring", SpeechReading.VERSION)
            }))
        }.getOrNull()?.let { return it }
        return Edge.json.decodeFromString(serializer,
            rpc("speech_challenge_list", buildJsonObject { put("p_language", language) }))
    }

    suspend fun refresh(language: String) {
        loadCache(language)
        val (statuses, rows, frozen) = coroutineScope {
            val status = async { seasonStatus(language) }
            val records = async { mySeasonRecords(language) }
            val list = runCatching { listRows(language) }.getOrNull()
            Triple(status.await(), list, records.await())
        }
        if (rows == null || loadedLanguage != language) return
        _seasons.value = statuses
        _seasonRecords.value = frozen.groupBy { it.challenge_id.lowercase() }
            .mapValues { (_, list) -> list.maxBy { it.season } }
        if (statuses.isNotEmpty()) {
            SpeechReading.setSeasonOpen(context,
                statuses.any { it.is_open && it.min_scoring >= SpeechReading.READING_SCORING_FROM }, language)
        }
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
                row.retired_at?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() },
                row.attempts, row.category, row.intro, row.link, row.season)
        }
        writeCache(language)
        val boardSeason = openSeason() ?: lastEndedSeason()
        overallBoard(language, boardSeason)?.let {
            if (loadedLanguage == language) {
                _overall.value = it
                _overallSeason.value = boardSeason
            }
        }
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
            // Season 1 takes never go on a Season 2 board, and a learner who
            // took themselves off a board doesn't get an earlier take filed.
            if (isPast(challengeId) || (season(challengeId) ?: 1) >= 2 || challengeId in removedFromBoard()) continue
            if (!importing.add(challengeId)) continue
            try {
                val onBoard = _standings.value[challengeId]?.myBest ?: -1
                val candidates = store.takes(script.id)
                    .filter { it.videoFilename != null && it.metrics.overall > onBoard &&
                        (it.metrics.scoring ?: 1) >= com.roro.futurevoice.talk.SpeechAnalyzer.SCORING_WITHOUT_PRONUNCIATION &&
                        (it.metrics.scoring ?: 1) < SpeechReading.READING_SCORING_FROM }
                    .sortedByDescending { it.metrics.overall }
                // Re-scored with today's weighting (iOS): only the number sent
                // changes, the take on the phone stays as it was.
                var best: Pair<SpeechTake, Int>? = null
                for (take in candidates) {
                    val diff = withContext(Dispatchers.Default) {
                        com.roro.futurevoice.talk.ShadowScore.analyze(script.body,
                            com.roro.futurevoice.talk.SpeechAnalyzer.removingFillers(take.transcript, script.language, script.body),
                            script.language)
                    }
                    if (kotlin.math.abs(com.roro.futurevoice.talk.SpeechAnalyzer.accuracy(diff) - take.metrics.accuracy) > 5) continue
                    val m = take.metrics
                    val overall = com.roro.futurevoice.talk.SpeechAnalyzer.overall(m.accuracy, m.paceScore,
                        m.pauseScore, m.fillerScore, m.steadiness,
                        com.roro.futurevoice.talk.SpeechAnalyzer.coverage(diff.steps), m.pronunciation)
                    if (overall > onBoard && overall > (best?.second ?: -1)) best = take to overall
                }
                best?.let { (take, overall) ->
                    submit(take, challengeId, name, overall)
                    Analytics.capture("speech_challenge_imported", mapOf("overall" to overall))
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

    /** Every challenge of a language on one board (iOS 2026-11-05): each
     *  learner's best score per challenge, added up, so the way to the top is
     *  to take more of them. Past challenges count. */
    suspend fun overallBoard(language: String, season: Int? = null, limit: Int = 10): List<BoardRow>? = runCatching {
        // Per season when the server has seasons (null: it doesn't).
        val raw = if (season != null) rpc("speech_overall_board_v2", buildJsonObject {
            put("p_language", language); put("p_season", season); put("p_limit", limit)
        }) else rpc("speech_overall_board", buildJsonObject {
            put("p_language", language); put("p_limit", limit)
        })
        Edge.json.decodeFromString(ListSerializer(BoardRow.serializer()), raw)
    }.getOrNull()

    // MARK: - Entering a take

    /** Called by the take session once a take on a challenge is scored. */
    fun enter(take: SpeechTake, script: SpeechScript, recordedOnCamera: Boolean) {
        val challengeId = script.challengeId ?: return
        val season = season(challengeId)
        keptOff(isPast(challengeId), season, take.metrics.scoring, take.metrics.reading != null,
            recordedOnCamera, take.metrics.overall)?.let { setEntry(take.id, it); return }
        val name = displayName(context) ?: run { setEntry(take.id, Entry.Failed); return }
        setEntry(take.id, Entry.Submitting)
        val seasonTwo = (season ?: 1) >= 2
        scope.launch { if (seasonTwo) submitReading(take, challengeId, name) else submit(take, challengeId, name) }
    }

    /** Off this board: the score is deleted on the server. The next take goes
     *  on it again like any other; only filing an EARLIER take is stopped
     *  ([importLocalBests]), or the score would be back at the next refresh. */
    suspend fun withdraw(challengeId: String) {
        rpc("withdraw_speech_challenge_entry", buildJsonObject { put("p_challenge", challengeId) })
        val old = _standings.value[challengeId] ?: Standing()
        _standings.value = _standings.value + (challengeId to old.copy(
            entrants = if (old.myBest != null) maxOf(0, old.entrants - 1) else old.entrants,
            myBest = null, myRank = null, myAttempts = null,
        ))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(REMOVED_KEY, removedFromBoard() + challengeId).apply()
        loadedLanguage?.let { writeCache(it) }
        Analytics.capture("speech_challenge_withdrawn", emptyMap())
    }

    private fun removedFromBoard(): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(REMOVED_KEY, null).orEmpty()

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

    /** `overall` is the take's own unless the caller re-scored it. */
    private suspend fun submit(take: SpeechTake, challengeId: String, name: String, overall: Int = take.metrics.overall) {
        val m = take.metrics
        try {
            val raw = rpc("submit_speech_challenge_take", buildJsonObject {
                put("p_challenge", challengeId)
                put("p_display_name", name)
                put("p_avatar", avatarPayload(context))
                put("p_overall", overall)
                put("p_accuracy", m.accuracy)
                put("p_pace", m.paceScore)
                put("p_pause", m.pauseScore)
                put("p_filler", m.fillerScore)
                put("p_steadiness", m.steadiness)
                // Always sent, null when not assessed: the call names the
                // eleven-argument function (iOS 2026-11-04).
                put("p_pronunciation", m.pronunciation)
                put("p_seconds", maxOf(1, take.durationSeconds.roundToInt()))
            })
            apply(raw, take, challengeId, overall)
        } catch (e: Exception) {
            setEntry(take.id, Entry.Failed)
            Analytics.capture("speech_challenge_failed", mapOf("error" to e.toString().take(160)))
        }
    }

    /** Season 2: the server rechecks the total from these parts. */
    private suspend fun submitReading(take: SpeechTake, challengeId: String, name: String) {
        val r = take.metrics.reading ?: run { setEntry(take.id, Entry.Failed); return }
        try {
            // The price list (scoring 8): the server recomputes the total from
            // the same counts (`submit_speech_reading_take_v8`, iOS 01529ba7).
            val counts = r.deductions.associate { it.part to it.count }
            val raw = rpc(if (r.version >= 8) "submit_speech_reading_take_v8" else "submit_speech_reading_take", buildJsonObject {
                put("p_challenge", challengeId)
                put("p_display_name", name)
                put("p_avatar", avatarPayload(context))
                put("p_overall", r.total)
                put("p_speed", r.parts.speed)
                put("p_rhythm", r.parts.rhythm)
                put("p_pauses", r.parts.pauses)
                put("p_accuracy", r.parts.accuracy)
                put("p_pronunciation", r.parts.pronunciation)
                put("p_coverage", r.coverage)
                put("p_seconds", maxOf(1, take.durationSeconds.roundToInt()))
                put("p_scoring", take.metrics.scoring ?: SpeechReading.VERSION)
                if (r.version >= 8) {
                    put("p_stops", counts[SpeechReadingScore.Part.PAUSES] ?: 0)
                    put("p_words", counts[SpeechReadingScore.Part.ACCURACY] ?: 0)
                    put("p_sounds", counts[SpeechReadingScore.Part.PRONUNCIATION] ?: 0)
                    put("p_rhythm_point", r.rhythmPoint)
                    put("p_speed_point", r.speedPoint)
                }
            })
            apply(raw, take, challengeId, r.total)
        } catch (e: Exception) {
            setEntry(take.id, Entry.Failed)
            Analytics.capture("speech_challenge_failed", mapOf("error" to e.toString().take(160)))
        }
    }

    private suspend fun apply(raw: String, take: SpeechTake, challengeId: String, overall: Int) {
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
            attempts = old.attempts?.plus(1),
            topScore = maxOf(old.topScore ?: 0, row.best),
        ))
        loadedLanguage?.let { writeCache(it) }
        Analytics.capture("speech_challenge_entered", mapOf(
            "overall" to overall, "rank" to row.rank, "entrants" to row.entrants,
            "improved" to row.improved,
        ))
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

    /** The caller's token; a signed-out capture run reads the boards as the
     *  public would (capture build only, `SpeechCaptureFlags.anonymousReads`). */
    private suspend fun readToken(): String =
        if (com.roro.futurevoice.capture.flags.SpeechCaptureFlags.anonymousReads)
            runCatching { auth.accessToken() }.getOrElse { Config.supabaseAnonKey }
        else auth.accessToken()

    private suspend fun rpc(name: String, body: JsonObject): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/$name")
            .header("Authorization", "Bearer ${readToken()}")
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
        // No score bar (2026-11-12, founder: every camera-on take goes up;
        // a take nobody meant to enter is taken off the board by its owner).
        private const val REMOVED_KEY = "speech.challenge.removedFromBoard"

        /** Why a scored take stays off the board, in iOS `enter`'s order; null
         *  when it goes up. */
        fun keptOff(past: Boolean, season: Int?, scoring: Int?, hasReading: Boolean,
                    onCamera: Boolean, overall: Int): Entry? {
            // An ended challenge can still be practised; its board is frozen.
            if (past) return Entry.Practice
            val seasonTwo = (season ?: 1) >= 2
            val scoredByReading = (scoring ?: 0) >= SpeechReading.READING_SCORING_FROM
            if (!seasonTwo && scoredByReading) return Entry.NewScoring
            // A Season 2 board only takes a reading score: no reference
            // reading (offline) means no entry.
            if (seasonTwo && (!scoredByReading || !hasReading)) return Entry.Failed
            if (!onCamera) return Entry.CameraOff
            return null
        }
        /** The overall board is drawn as soon as one person is on it (iOS
         *  `overallMinEntrants`, founder 2026-11-10: a new season's board is
         *  there from its first day). */
        const val OVERALL_MIN_ENTRANTS = 1

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
