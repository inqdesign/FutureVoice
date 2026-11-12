package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import java.util.Locale

/**
 * One LOCAL day of a 100-day challenger (iOS `ChallengeDays`): how long they
 * talked and how many speech takes they finished. A day counts with 4+
 * minutes of talk AND one speech, by the date where they live; the server
 * knows talk only, so the phone says both.
 *
 * These two counts, the date, the time zone id, the platform and the app
 * version are ALL that leaves the phone here. No text, no audio, no score.
 */
data class ChallengeDay(val day: String, val talkSeconds: Int, val speechTakes: Int)

/** The pure half: which days are sent, and whether anything changed. */
object ChallengeDayPlan {
    const val WINDOW_DAYS = 14
    /** A learner who is not in the program is asked about again this often. */
    const val ASK_AGAIN_MS = 24 * 3_600_000L
    /** After a failed call nothing is tried for this long: the RPC may not
     *  exist yet, and every store write lands on the trigger. */
    const val RETRY_AFTER_FAILURE_MS = 6 * 3_600_000L
    /** Someone known to be in the program is retried sooner. */
    const val PARTICIPANT_RETRY_MS = 30 * 60_000L

    /**
     * The last [WINDOW_DAYS] local days that have either number, oldest
     * first. [talkByDay] is keyed `yyyy-MM-dd` in the phone's own calendar;
     * [speechAt] are the moments speech takes were saved.
     */
    fun days(now: Long, zone: ZoneId, talkByDay: Map<String, Int>, speechAt: List<Long>): List<ChallengeDay> {
        val takes = speechAt.groupingBy { Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }.eachCount()
        val today: LocalDate = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        return (WINDOW_DAYS - 1 downTo 0).mapNotNull { back ->
            val d = today.minusDays(back.toLong())
            val talk = maxOf(0, talkByDay[d.toString()] ?: 0)
            val speech = takes[d] ?: 0
            if (talk > 0 || speech > 0) ChallengeDay(d.toString(), talk, speech) else null
        }
    }

    /** What the server was last told. */
    fun fingerprint(days: List<ChallengeDay>, timeZone: String): String =
        (listOf(timeZone) + days.map { "${it.day}:${it.talkSeconds}:${it.speechTakes}" }).joinToString("|")

    enum class Step { WAIT, ASK, SEND }

    fun step(participant: Boolean?, askedAt: Long?, failedAt: Long?, sentFingerprint: String?,
             fingerprint: String, now: Long): Step {
        // A clock set back must not silence the uploader for good.
        fun within(at: Long?, ms: Long) = at != null && (now - at) in 0 until ms
        if (participant == true) {
            if (within(failedAt, PARTICIPANT_RETRY_MS)) return Step.WAIT
            return if (fingerprint == sentFingerprint) Step.WAIT else Step.SEND
        }
        if (within(failedAt, RETRY_AFTER_FAILURE_MS)) return Step.WAIT
        if (participant == false && within(askedAt, ASK_AGAIN_MS)) return Step.WAIT
        return Step.ASK
    }
}

/**
 * Tells the server each local day's two numbers, for a challenger only.
 * Nothing on screen, nothing waits on it, and every failure is silent: the
 * RPC does not exist until the server's migration is applied.
 */
object ChallengeDays {
    private const val SETTLE_MS = 20_000L
    private const val PREFS = "futurevoice"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pending: Job? = null
    private var running = false

    @Serializable
    private data class State(
        val participant: Boolean? = null,
        val askedAt: Long? = null,
        val failedAt: Long? = null,
        val sentFingerprint: String? = null,
        /** The local day a failure was last reported to analytics. */
        val failureReportedDay: String? = null,
    )

    @Serializable
    private data class Answer(val participant: Boolean = false, val accepted: Int? = null,
                              val starts_on: String? = null)

    /** Called beside `LearnerRecordUploader.schedule`: after a call ends,
     *  after a speech take is saved, and when the app comes forward. */
    @Synchronized
    fun schedule(context: Context) {
        if (BuildConfig.BUILD_TYPE == "capture") return
        val app = context.applicationContext
        pending?.cancel()
        pending = scope.launch {
            delay(SETTLE_MS)
            run(app)
        }
    }

    private fun stateKey(userId: String) = "futurevoice.challengeDays.$userId"

    private fun loadState(c: Context, userId: String): State = runCatching {
        c.getSharedPreferences(PREFS, 0).getString(stateKey(userId), null)
            ?.let { StoreJson.json.decodeFromString(State.serializer(), it) }
    }.getOrNull() ?: State()

    private fun save(c: Context, userId: String, state: State) {
        c.getSharedPreferences(PREFS, 0).edit()
            .putString(stateKey(userId), StoreJson.json.encodeToString(State.serializer(), state))
            .apply()
    }

    private fun dayKey(at: Long): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(at))

    private fun current(c: Context, now: Long, zone: ZoneId): List<ChallengeDay> {
        // Every language's metered seconds per local day: the ring's rows.
        val talk = TalkTimeLog.recentSeconds(c, ChallengeDayPlan.WINDOW_DAYS + 1, now)
            .associate { (at, seconds) -> dayKey(at) to seconds }
        val speech = ActivityEventLog
            .events(c, now - (ChallengeDayPlan.WINDOW_DAYS + 1) * 86_400_000L, now + 1)
            .filter { it.kind == ActivityEventLog.Kind.SPEECH }.map { it.at }
        return ChallengeDayPlan.days(now, zone, talk, speech)
    }

    private suspend fun put(auth: AuthRepository, days: List<ChallengeDay>, timeZone: String): Answer =
        withContext(Dispatchers.IO) {
            val body = JsonObject(mapOf("p_days" to JsonArray(days.map { d ->
                JsonObject(mapOf(
                    "day" to JsonPrimitive(d.day),
                    "talk_seconds" to JsonPrimitive(d.talkSeconds),
                    "speech_takes" to JsonPrimitive(d.speechTakes),
                    "time_zone" to JsonPrimitive(timeZone),
                    "platform" to JsonPrimitive("android"),
                    "app_version" to JsonPrimitive(BuildConfig.VERSION_NAME),
                ))
            })))
            val request = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/challenge_days_put")
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("apikey", Config.supabaseAnonKey)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                val raw = resp.body.string()
                if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
                StoreJson.json.decodeFromString(Answer.serializer(), raw)
            }
        }

    private suspend fun run(c: Context) {
        synchronized(this) { if (running) return; running = true }
        var userId: String? = null
        var state = State()
        val now = System.currentTimeMillis()
        try {
            val auth = AuthRepository()
            userId = auth.userId?.lowercase() ?: return
            if (auth.isAnonymous) return
            state = loadState(c, userId)
            val zone = ZoneId.systemDefault()
            val days = current(c, now, zone)
            val fingerprint = ChallengeDayPlan.fingerprint(days, zone.id)

            val step = ChallengeDayPlan.step(state.participant, state.askedAt, state.failedAt,
                                             state.sentFingerprint, fingerprint, now)
            if (step == ChallengeDayPlan.Step.WAIT) return
            if (step == ChallengeDayPlan.Step.ASK) {
                val answer = put(auth, emptyList(), zone.id)
                state = state.copy(participant = answer.participant, askedAt = now, failedAt = null)
                save(c, userId, state)
                if (!answer.participant || fingerprint == state.sentFingerprint) return
            }
            // Nothing to say yet is still "sent": the call would be the
            // question again.
            if (days.isNotEmpty()) {
                val answer = put(auth, days, zone.id)
                state = state.copy(participant = answer.participant, askedAt = now)
            }
            state = state.copy(failedAt = null,
                               sentFingerprint = if (state.participant == true) fingerprint else null)
            save(c, userId, state)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            val id = userId ?: return
            // At most one event a day per account, whatever the trigger rate.
            val today = dayKey(now)
            if (state.failureReportedDay != today) {
                Analytics.capture("challenge_days_failed", mapOf("error" to e.toString().take(120)))
            }
            save(c, id, state.copy(failedAt = now, failureReportedDay = today))
        } finally {
            synchronized(this) { running = false }
        }
    }
}
