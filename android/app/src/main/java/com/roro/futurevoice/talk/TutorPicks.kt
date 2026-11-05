package com.roro.futurevoice.talk

import android.content.Context
import android.content.res.Resources
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.ActivityEventLog
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.NewsShow
import com.roro.futurevoice.data.NewsShowEpisode
import com.roro.futurevoice.data.NewsTopicStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.SpeechChallenges
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.NewsClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.security.MessageDigest
import java.util.Calendar
import java.util.UUID

/**
 * What the tutor picks for today beyond the routine (iOS `TutorPick`,
 * 87bda8d6, founder: "not just the routine: a new episode you haven't heard,
 * a speech if you never tried one, a challenge where you were pushed down,
 * and speaking, listening and reading in turn"). Every line is a fixed
 * sentence in code, so the plan reads alive without a model call.
 */
data class TutorPick(
    val id: String,
    val kind: Kind,
    val title: String,
    val why: String,
    val action: Action,
) {
    enum class Kind(val raw: String) {
        RANK_DROP("rankDrop"), NEW_EPISODE("newEpisode"), FIRST_SPEECH("firstSpeech"),
        READ_SCRIPT("readScript"), READ_NEWS("readNews"), LISTEN("listen"),
        GOAL_READING("goalReading"), GOAL_SPEECH("goalSpeech"), GOAL_DRILL("goalDrill"),
    }

    sealed interface Action {
        data class Listen(val episodeId: String) : Action
        data class ReadScript(val episodeId: String) : Action
        data class ReadNews(val story: SuggestedTopic) : Action
        data class Challenge(val id: String) : Action
        /** Today's preparation for an upcoming goal ([GoalPrep]); a null
         *  part is the tutor drill. */
        data class Goal(val goalId: String, val part: GoalPrep.Part?) : Action
    }

    fun tag(res: Resources): String? = res.getString(when (kind) {
        Kind.RANK_DROP -> R.string.rank
        Kind.NEW_EPISODE -> R.string.new_episode
        Kind.FIRST_SPEECH -> R.string.first_time
        Kind.READ_SCRIPT, Kind.READ_NEWS -> R.string.reading_cffa2a
        Kind.LISTEN -> R.string.listening_dc3534
        Kind.GOAL_READING -> R.string.reading_cffa2a
        Kind.GOAL_SPEECH -> R.string.model_answer
        Kind.GOAL_DRILL -> R.string.tutor_drill
    })

    fun buttonTitle(res: Resources): String = res.getString(when (kind) {
        Kind.RANK_DROP -> R.string.try_again
        Kind.NEW_EPISODE, Kind.LISTEN -> R.string.listen
        Kind.FIRST_SPEECH -> R.string.start
        Kind.READ_SCRIPT, Kind.READ_NEWS, Kind.GOAL_READING -> R.string.read_852b43
        Kind.GOAL_SPEECH -> R.string.open
        Kind.GOAL_DRILL -> R.string.start
    })
}

/** Days this week with each kind of practice — the plan's balance line. */
data class TutorBalance(val speaking: Int = 0, val listening: Int = 0, val reading: Int = 0)

object TutorPicks {
    const val MAX_PICKS = 4
    /** Listening or reading on this many days or fewer this week is "missing". */
    const val MISSING_AT = 1

    private const val HEARD_EPISODES_KEY = "futurevoice.podcast.heardEpisodes"
    private const val SEEN_RANKS_KEY = "futurevoice.tutorBot.seenRanks"
    private const val FIRST_SPEECH_SHOWN_KEY = "futurevoice.tutorBot.firstSpeechShown"

    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    private fun readList(c: Context, key: String): List<String> =
        prefs(c).getString(key, null)?.let { s -> if (s.isEmpty()) emptyList() else s.split('\n') } ?: emptyList()

    // MARK: Heard episodes

    /** Written by the player the first time a line of an episode is heard. */
    fun markHeard(c: Context, episodeId: String) {
        val set = readList(c, HEARD_EPISODES_KEY)
        if (episodeId in set) return
        prefs(c).edit().putString(HEARD_EPISODES_KEY, (set + episodeId).takeLast(200).joinToString("\n")).apply()
    }

    fun wasHeard(c: Context, episodeId: String): Boolean = episodeId in readList(c, HEARD_EPISODES_KEY)

    // MARK: Ranks

    private fun seenRanks(c: Context): MutableMap<String, Int> = runCatching {
        Json.parseToJsonElement(prefs(c).getString(SEEN_RANKS_KEY, null) ?: "{}") as JsonObject
    }.getOrNull()?.mapValues { it.value.jsonPrimitive.int }?.toMutableMap() ?: mutableMapOf()

    private fun writeSeenRanks(c: Context, seen: Map<String, Int>) {
        prefs(c).edit().putString(SEEN_RANKS_KEY,
            JsonObject(seen.mapValues { kotlinx.serialization.json.JsonPrimitive(it.value) }).toString()).apply()
    }

    /** The challenge was opened from its pick: today's place is now the one seen. */
    fun markRankSeen(c: Context, challengeId: String, rank: Int) {
        val seen = seenRanks(c)
        seen[challengeId] = rank
        writeSeenRanks(c, seen)
    }

    private data class Drop(val script: SpeechScript, val from: Int, val to: Int, val best: Int?, val top: Int?)

    /** Challenges whose place went DOWN since it was last seen. A first
     *  sight, or a place that went up, quietly becomes the new mark. */
    private fun rankDrops(c: Context): List<Drop> {
        val ch = SpeechChallenges.shared(c)
        val seen = seenRanks(c)
        val out = ArrayList<Drop>()
        val standings = ch.standings.value
        for (script in ch.scripts.value.filter { !ch.isPast(it.id) }) {
            val s = standings[script.id] ?: continue
            val rank = s.myRank ?: continue
            val was = seen[script.id]
            if (was != null && rank > was) out += Drop(script, was, rank, s.myBest, s.topScore)
            else seen[script.id] = rank
        }
        writeSeenRanks(c, seen)
        return out
    }

    // MARK: Balance

    suspend fun balance(c: Context, now: Long = System.currentTimeMillis()): TutorBalance {
        val start = StudyPlan.addDays(StudyPlan.startOfDay(now), -6)
        val events = ActivityEventLog.events(c, start, now + 1000)
        fun days(kinds: Set<ActivityEventLog.Kind>): Set<Long> =
            events.filter { it.kind in kinds }.map { StudyPlan.startOfDay(it.at) }.toSet()
        val speak = days(setOf(ActivityEventLog.Kind.SHADOW, ActivityEventLog.Kind.SAY_IT_AGAIN,
            ActivityEventLog.Kind.SPEECH)).toMutableSet()
        for (s in runCatching { SessionStore.shared(c).load(LanguageScope.active(c)) }.getOrDefault(emptyList())) {
            if (s.startedAt >= start && s.turns.any { it.role == TurnRole.USER }) speak += StudyPlan.startOfDay(s.startedAt)
        }
        return TutorBalance(speaking = speak.size,
            listening = days(setOf(ActivityEventLog.Kind.LISTEN)).size,
            reading = days(setOf(ActivityEventLog.Kind.READ)).size)
    }

    /** iOS `Calendar.ordinality(of: .day, in: .era)`: the day's number since
     *  1 Jan of year 1 — only ever read modulo a count, so the day's choice
     *  turns over at local midnight. */
    fun dayOrdinal(now: Long): Int {
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        val local = now + cal.get(Calendar.ZONE_OFFSET) + cal.get(Calendar.DST_OFFSET)
        return (Math.floorDiv(local, 86_400_000L) + 719_165L).toInt()
    }

    // MARK: Picks

    data class Loaded(val picks: List<TutorPick>, val episodes: List<NewsShowEpisode>, val balance: TutorBalance)

    /** Today's picks, most time-bound first. Needs the network for the
     *  podcast feed, the challenge list and the news pool; any of them
     *  missing just leaves its pick out. */
    suspend fun load(c: Context, targetLanguage: String, persona: UserPersona?,
                     now: Long = System.currentTimeMillis()): Loaded = coroutineScope {
        val lang = targetLanguage
        val feed = async { runCatching { NewsShow.episodes(c, lang) }.getOrDefault(emptyList()) }
        val challenges = SpeechChallenges.shared(c)
        runCatching { challenges.loadCache(lang); challenges.refresh(lang) }
        val episodes = feed.await()
        val balance = balance(c, now)
        val day = dayOrdinal(now)
        val picks = ArrayList<TutorPick>()

        // 0. The nearest upcoming goal leads: today's reading, model answer
        // and a tutor drill, all about it ([GoalPrep]). Nothing is written
        // until one of them is tapped.
        val goal = com.roro.futurevoice.data.UpcomingGoalStore.active(c, lang, now).firstOrNull()
        if (goal != null) picks += goalPicks(c, goal, now)

        // 1. Pushed down on a challenge.
        rankDrops(c).take(1).forEach { drop ->
            picks += TutorPick("rank-${drop.script.id}", TutorPick.Kind.RANK_DROP, drop.script.title,
                rankWhy(drop.from, drop.to), TutorPick.Action.Challenge(drop.script.id))
        }

        // 2. A new episode not heard yet (out in the last two days).
        val fresh = episodes.firstOrNull { now - it.date < 2 * 86_400_000L && !wasHeard(c, it.id) }
        if (fresh != null) {
            picks += TutorPick("ep-${fresh.id}", TutorPick.Kind.NEW_EPISODE, fresh.title,
                minutesWhy(c.resources, fresh.minutes), TutorPick.Action.Listen(fresh.id))
        }

        // 3. Never tried a speech: once, then a week's rest.
        val firstLive = challenges.scripts.value.firstOrNull { !challenges.isPast(it.id) }
        if (SpeechStore.shared(c).takes.value.isEmpty() && firstLive != null && showFirstSpeech(c, now)) {
            picks += TutorPick("speech-first", TutorPick.Kind.FIRST_SPEECH, firstLive.title,
                "", TutorPick.Action.Challenge(firstLive.id))
        }

        // 4. Reading missing this week: the learner picks, a script or the news.
        if (balance.reading <= MISSING_AT) {
            episodes.firstOrNull()?.let { ep ->
                picks += TutorPick("script-${ep.id}", TutorPick.Kind.READ_SCRIPT, ep.title,
                    "", TutorPick.Action.ReadScript(ep.id))
            }
            // With a goal ahead, its own reading stands in for the news.
            if (goal == null) newsStory(c, targetLanguage, persona, day)?.let { story ->
                picks += TutorPick("news-${story.title}", TutorPick.Kind.READ_NEWS, story.title,
                    story.category ?: "", TutorPick.Action.ReadNews(story))
            }
        }

        // 5. Listening missing and no new episode: the latest one not heard.
        if (fresh == null && balance.listening <= MISSING_AT) {
            episodes.firstOrNull { !wasHeard(c, it.id) }?.let { ep ->
                picks += TutorPick("listen-${ep.id}", TutorPick.Kind.LISTEN, ep.title,
                    minutesWhy(c.resources, ep.minutes), TutorPick.Action.Listen(ep.id))
            }
        }
        Loaded(picks.take(MAX_PICKS + (if (goal == null) 0 else 3)), episodes, balance)
    }

    /** The goal's three for today. Before anything is written the titles are
     *  the goal's own; once it is, the day's. */
    fun goalPicks(c: Context, goal: com.roro.futurevoice.data.UpcomingGoal,
                  now: Long = System.currentTimeMillis()): List<TutorPick> {
        val prep = GoalPrep.today(c, goal, now)
        val countdown = goal.countdown(c, now)?.let { "$it · " } ?: ""
        val res = c.resources
        return listOf(
            TutorPick("goal-read-${goal.id}", TutorPick.Kind.GOAL_READING,
                prep?.reading?.title ?: res.getString(R.string.today_s_reading),
                countdown + (prep?.focus ?: res.getString(R.string.written_for_this_goal_when_you_open_it)),
                TutorPick.Action.Goal(goal.id, GoalPrep.Part.READING)),
            TutorPick("goal-speech-${goal.id}", TutorPick.Kind.GOAL_SPEECH,
                prep?.speech?.question ?: prep?.speech?.title ?: res.getString(R.string.an_answer_you_can_say_on_the_day),
                "", TutorPick.Action.Goal(goal.id, GoalPrep.Part.SPEECH)),
            TutorPick("goal-drill-${goal.id}", TutorPick.Kind.GOAL_DRILL,
                prep?.focus ?: goal.title, "", TutorPick.Action.Goal(goal.id, null)),
        )
    }

    private fun showFirstSpeech(c: Context, now: Long): Boolean {
        val p = prefs(c)
        val first = p.getLong(FIRST_SPEECH_SHOWN_KEY, Long.MIN_VALUE)
        if (first == Long.MIN_VALUE) {
            p.edit().putLong(FIRST_SPEECH_SHOWN_KEY, now).apply()
            return true
        }
        if (StudyPlan.dayKey(first) == StudyPlan.dayKey(now)) return true
        if (now - first >= 7 * 86_400_000L) {
            p.edit().putLong(FIRST_SPEECH_SHOWN_KEY, now).apply()
            return true
        }
        return false
    }

    /** One story from the learner's interests, the same pool the Talk tab
     *  shows: the day's cache first, the network only when there is none. */
    private suspend fun newsStory(c: Context, targetLanguage: String, persona: UserPersona?, day: Int): SuggestedTopic? {
        val interests = persona?.interests ?: emptyList()
        if (interests.isEmpty()) return null
        val store = NewsTopicStore.shared(c)
        var pool = store.valid(interests, targetLanguage) ?: emptyList()
        if (pool.isEmpty()) {
            val fetched = runCatching { NewsClient(AuthRepository()).fetch(interests, targetLanguage) }.getOrNull()
            if (fetched != null) {
                pool = fetched.topics
                if (pool.isNotEmpty()) store.save(pool, interests, targetLanguage)
            }
        }
        if (pool.isEmpty()) pool = store.lastKnown(interests, targetLanguage) ?: emptyList()
        if (pool.isEmpty()) return null
        return pool[Math.floorMod(day, pool.size)]
    }

    // MARK: Copy — fixed

    fun rankWhy(from: Int, to: Int): String = "#$from → #$to"
    fun minutesWhy(res: Resources, minutes: Int): String = res.getString(R.string.lld_min_b61908, minutes)
}

/**
 * A news story as an article to read (iOS `NewsArticle`, `news-article`):
 * written once for everyone the first time it is opened, then kept on this
 * phone too.
 */
object NewsArticle {
    @Serializable
    data class Article(val title: String, val summary: String, val body: String)

    @Serializable
    private data class Body(
        val title: String, val blurb: String, val facts: List<String>,
        val category: String, val language: String, val level: String,
    )

    suspend fun load(c: Context, story: SuggestedTopic, language: String, level: CefrLevel): SpeechScript =
        withContext(Dispatchers.IO) {
            val band = level.code.lowercase().firstOrNull()?.toString() ?: "b"
            val key = "$language|$band|${story.title}"
            val file = cacheFile(c, key)
            val article = runCatching {
                file.takeIf { it.exists() }?.readText()?.let { StoreJson.json.decodeFromString(Article.serializer(), it) }
            }.getOrNull() ?: run {
                val request = Request.Builder()
                    .url(Config.functionUrl("news-article"))
                    .header("Authorization", "Bearer ${AuthRepository().accessToken()}")
                    .post(Edge.json.encodeToString(Body.serializer(), Body(
                        story.title, story.blurb, story.facts ?: emptyList(), story.category ?: "",
                        language, level.code.lowercase()))
                        .toRequestBody("application/json".toMediaType()))
                    .build()
                val fetched = Edge.client.newCall(request).execute().use { resp ->
                    val text = resp.body.string()
                    if (resp.code !in 200..299) throw EdgeError.Http(resp.code, text.take(512))
                    Edge.json.decodeFromString(Article.serializer(), text)
                }
                runCatching { file.writeText(StoreJson.json.encodeToString(Article.serializer(), fetched)) }
                fetched
            }
            // A stable id per article (iOS's rule), so a second "Say it out loud"
            // lands on the script already in My scripts.
            val h = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
            val bb = java.nio.ByteBuffer.wrap(h, 0, 16)
            SpeechScript(id = UUID(bb.long, bb.long).toString().uppercase(), title = article.title, genre = SpeechGenre.NEWS,
                topic = story.category ?: "", body = article.body, summary = article.summary,
                language = language, targetSeconds = 0, createdAt = System.currentTimeMillis())
        }

    private fun cacheFile(c: Context, key: String): File {
        val dir = File(c.cacheDir, "NewsArticles").apply { mkdirs() }
        val name = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(dir, "$name.json")
    }
}
