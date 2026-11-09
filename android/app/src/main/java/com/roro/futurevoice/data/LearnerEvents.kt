package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.TutorLessonStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Calendar
import java.util.Locale

/**
 * One fact about what a learner has learned (docs/learner-record.md; iOS
 * `LearnerEvents`). Never the content of a conversation: the server's
 * `learner_events_put` refuses anything outside its list of kinds and keys.
 */
data class LearnerEvent(
    val key: String,
    val language: String,
    val occurredAt: Long,
    val sourceId: String?,
    val kind: String,
    val subject: String,
    val value: Map<String, JsonElement>,
) {
    /** The date is left out: a fact that has not changed is not sent again. */
    val fingerprint: String
        get() = (listOf(kind, subject, sourceId ?: "") +
            value.keys.sorted().map { "$it=${value[it]}" }).joinToString("|")
}

/** Finds what changed by comparing today's facts with what was last sent. */
object LearnerEventDiff {
    @Serializable data class Sent(val fingerprint: String, val sourceId: String? = null)

    data class Plan(val forget: List<String>, val put: List<LearnerEvent>)

    /** A fact that vanished clears its whole source, and the source's facts
     *  that still exist go again in the same pass. */
    fun plan(current: List<LearnerEvent>, sent: Map<String, Sent>): Plan {
        val keys = current.map { it.key }.toSet()
        val forget = sent.filterKeys { it !in keys }.values.mapNotNull { it.sourceId }.toSet()
        val put = current.filter { e ->
            (e.sourceId != null && e.sourceId in forget) || sent[e.key]?.fingerprint != e.fingerprint
        }
        return Plan(forget.sorted(), put)
    }

    fun afterForgetting(sources: List<String>, sent: Map<String, Sent>): Map<String, Sent> =
        sent.filterValues { it.sourceId == null || it.sourceId !in sources }
}

/** Reads the stores and writes down what they say, for one language. */
object LearnerEventBuilder {
    private const val MAX_EXPRESSION_WORDS = 6
    private const val MAX_TYPED = 300
    private const val DAY_WINDOW = 45

    private fun dayKey(at: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date(at))

    private fun i(n: Int) = JsonPrimitive(n)
    private fun s(t: String) = JsonPrimitive(t)
    private fun b(v: Boolean) = JsonPrimitive(v)

    suspend fun build(c: Context, language: String, now: Long = System.currentTimeMillis()): List<LearnerEvent> {
        val out = mutableListOf<LearnerEvent>()
        fun add(key: String, at: Long, source: String?, kind: String, subject: String,
                value: Map<String, JsonElement>) {
            out += LearnerEvent(key, language, at, source, kind, subject, value)
        }
        fun typed(field: String, text: String?) {
            val t = text?.trim()?.take(MAX_TYPED).orEmpty()
            if (t.isNotEmpty()) add("setup:$field", now, null, "setup", field, mapOf("value" to s(t)))
        }

        val prefs = c.getSharedPreferences("futurevoice", 0)
        typed("native_language", prefs.getString("futurevoice.nativeLanguage", null))
        typed("level", prefs.getString("futurevoice.proficiency", null))
        typed("purposes", LearningPurposeStore.purposes(c).joinToString(",") { it.raw })
        PersonaStore.shared(c).load()?.let { p ->
            typed("occupation", p.occupation)
            typed("city", p.city)
            typed("country", p.country)
            typed("interests", p.interests.joinToString(", "))
            typed("situations", p.situations.joinToString(", "))
            typed("future_goals", p.goals.joinToString(", "))
        }

        UpcomingGoalStore.ensureLoaded(c)
        for (g in UpcomingGoalStore.goals.filter { LanguageCatalog.sameLanguage(it.language, language) }) {
            val value = mutableMapOf<String, JsonElement>("kind" to s(g.kind.raw), "title" to s(g.title.take(500)))
            g.date?.let { value["date"] = s(dayKey(it)) }
            if (g.place.isNotEmpty()) value["place"] = s(g.place.take(500))
            if (g.notes.isNotEmpty()) value["notes"] = s(g.notes.take(500))
            add("goal:${g.id}", g.createdAt, g.id, "goal", g.id, value)
        }

        for (t in SessionStore.shared(c).load(language).filter { it.endedAt != null && it.summary != null }) {
            val end = t.endedAt ?: t.startedAt
            val m = ScorecardMetrics.compute(t.turns, language)
            val value = mutableMapOf<String, JsonElement>(
                "minutes" to i(((end - t.startedAt) / 60_000).toInt()),
                "mode" to s(if (t.isPractice) "practice" else "talk"),
                "learner_words" to i(m.userWordCount),
                "turns" to i(m.userTurnCount),
                "wpm" to i(Math.round(m.wordsPerMinute).toInt()),
                "pauses" to i(Math.round(m.pausesPerMinute).toInt()),
            )
            t.summary?.scorecard?.let { card ->
                value["vocabulary"] = i(card.vocabulary.score)
                value["grammar"] = i(card.grammar.score)
                value["expressiveness"] = i(card.expressiveness.score)
                value["fluency"] = i(card.fluency.score)
                card.pronunciation?.let { value["pronunciation"] = i(it.score) }
                card.cefrLevel?.let { value["cefr"] = s(it.take(16)) }
                card.grammarRange?.let { value["grammar_range"] = s(it.take(16)) }
            }
            add("talk:${t.id}", end, t.id, "talk", t.id, value)
        }
        for ((id, tag) in LearnerStateStore.shared(c).state(language).sessions) {
            for (item in tag.items) {
                add("talk:$id:item:${item.id}", tag.talkDate, id, "item", item.id, mapOf(
                    "right" to i(item.right), "wrong" to i(item.wrong),
                    "item_kind" to s(item.kind.name.lowercase())))
            }
        }

        val vocab = VocabStore.shared(c)
        val words = vocab.wordRecords(language)
        for (w in vocab.studying(language).filter { it !in words }) {
            add("word:$w", now, null, "word", w, mapOf("state" to s("studying"), "count" to i(0)))
        }
        for ((w, r) in words) {
            add("word:$w", r.lastAt, null, "word", w, mapOf("state" to s(r.state), "count" to i(r.count)))
        }
        fun phrase(t: String) = WordSplitter.count(t, language) <= MAX_EXPRESSION_WORDS
        val phrases = vocab.expressionRecords(language)
        for (t in vocab.studyingExpressions(language).filter { it !in phrases && phrase(it) }) {
            add("expression:$t", now, null, "expression", t, mapOf("state" to s("studying"), "count" to i(0)))
        }
        for ((t, r) in phrases.filterKeys(::phrase)) {
            add("expression:$t", r.lastAt, null, "expression", t, mapOf("state" to s(r.state), "count" to i(r.count)))
        }

        for (card in DrillStore.shared(c).load(language)) {
            val value = mutableMapOf<String, JsonElement>(
                "box" to i(card.box), "seen" to i(card.timesSeen), "correct" to i(card.timesCorrect))
            card.usedInTalkAt?.let { value["used_at"] = s(dayKey(it)) }
            add("card:${card.id}", card.lastReviewedAt ?: card.createdAt, card.sourceSessionId, "card", card.id, value)
        }
        for (a in ShadowAttemptStore.shared(c).load(language)) {
            val value = mutableMapOf<String, JsonElement>(
                "overall" to i(a.overallScore), "match" to i(a.matchScore), "partial" to b(a.isPartial))
            a.rhythmScore?.let { value["rhythm"] = i(it) }
            add("shadow:${a.id}", a.createdAt, a.id, "shadow", a.turnId, value)
        }

        data class Sound(val at: Long, var total: Int = 0, var samples: Int = 0)
        val sounds = mutableMapOf<Pair<String, String>, Sound>()
        for (e in PronunciationLedger.shared(c).entries(language)) {
            for (p in e.phonemes.filter { it.p.isNotEmpty() }) {
                val row = sounds.getOrPut(dayKey(e.date) to p.p) { Sound(e.date) }
                row.total += p.a
                row.samples += 1
            }
        }
        for ((key, row) in sounds) {
            add("sound:${key.first}:${key.second}", row.at, null, "sound", key.second,
                mapOf("score" to i(row.total / maxOf(row.samples, 1)), "samples" to i(row.samples)))
        }

        for (l in TutorLessonStore.all(c, language)) {
            val value = mutableMapOf<String, JsonElement>(
                "challenges" to i(l.challenges.size),
                "done" to b(l.finishedAt != null),
                "check_passed" to b(l.check?.passedAt != null))
            l.check?.let { value["tries"] = i(it.tries) }
            add("lesson:${l.id}", l.finishedAt ?: l.createdAt, l.id, "lesson", l.topicId ?: "custom", value)
        }
        for (t in WeeklyTestStore.shared(c).load(language).filter { it.isFinished }) {
            val kinds = t.items.associate { it.id to it.kind.name.lowercase() }
            for (a in t.answers) {
                val kind = kinds[a.itemId] ?: continue
                val value = mutableMapOf<String, JsonElement>(
                    "right" to b(a.correct), "appealed" to b(a.appealed == true))
                a.score?.let { value["score"] = i(it) }
                add("test:${t.id}:${a.itemId}", a.at, t.id, "test", kind, value)
            }
        }

        val day = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        repeat(DAY_WINDOW) {
            val at = day.timeInMillis
            val log = PracticeLog.day(c, at) ?: PracticeLog.Day()
            val talk = TalkTimeLog.secondsOn(c, at, language)
            if (talk > 0 || log.didSomething) {
                val date = dayKey(at)
                add("day:$date", at, null, "day", date, mapOf(
                    "talk_seconds" to i(talk), "word_reps" to i(log.wordReps),
                    "expression_reps" to i(log.expressionReps), "drill_reps" to i(log.drillReps),
                    "shadow_reps" to i(log.shadowReps), "scene_reps" to i(log.sceneReps)))
            }
            day.add(Calendar.DAY_OF_MONTH, -1)
        }
        for (block in StudyPlanStore.current(c).blocks) {
            val time = if (block.anytime == true) "anytime" else "%02d:%02d".format(block.hour, block.minute)
            for (weekday in block.weekdays) {
                add("routine:${block.id}:$weekday", now, "routine", "routine", block.kind.raw, mapOf(
                    "weekday" to i(weekday), "time" to s(time), "amount" to i(block.minutes)))
            }
        }
        return out
    }
}

/** Sends what changed, a while after the learner stops doing things. */
object LearnerRecordUploader {
    private const val SETTLE_MS = 20_000L
    private const val BATCH = 400
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pending: Job? = null
    private var running = false
    private val indexSerializer = MapSerializer(String.serializer(), LearnerEventDiff.Sent.serializer())

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

    private suspend fun rpc(auth: AuthRepository, name: String, body: JsonObject): String =
        withContext(Dispatchers.IO) {
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

    private suspend fun run(c: Context) {
        synchronized(this) { if (running) return; running = true }
        try {
            val auth = AuthRepository()
            val userId = auth.userId ?: return
            if (auth.isAnonymous) return
            if (rpc(auth, "learner_record_enabled", JsonObject(emptyMap())).trim() != "true") return

            val language = LanguageScope.active(c).substringBefore('-')
            val file = File(c.filesDir, "learner_record/${userId.lowercase()}/$language.json")
            var sent = load(file)
            val current = LearnerEventBuilder.build(c, language)
            val plan = LearnerEventDiff.plan(current, sent)

            for (source in plan.forget) {
                rpc(auth, "learner_events_forget", JsonObject(mapOf("p_source_id" to JsonPrimitive(source))))
            }
            if (plan.forget.isNotEmpty()) {
                sent = LearnerEventDiff.afterForgetting(plan.forget, sent)
                save(file, sent)
            }
            for (batch in plan.put.chunked(BATCH)) {
                rpc(auth, "learner_events_put", JsonObject(mapOf("p_batch" to JsonArray(batch.map(::payload)))))
                sent = sent + batch.associate { it.key to LearnerEventDiff.Sent(it.fingerprint, it.sourceId) }
                save(file, sent)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Analytics.capture("learner_record_failed", mapOf("error" to e.toString().take(120)))
        } finally {
            synchronized(this) { running = false }
        }
    }

    private fun payload(e: LearnerEvent): JsonElement {
        val o = mutableMapOf<String, JsonElement>(
            "key" to JsonPrimitive(e.key),
            "language" to JsonPrimitive(e.language),
            "occurred_at" to JsonPrimitive(Instant.ofEpochMilli(e.occurredAt).toString()),
            "kind" to JsonPrimitive(e.kind),
            "subject" to JsonPrimitive(e.subject),
            "value" to JsonObject(e.value),
            "platform" to JsonPrimitive("android"),
            "app_version" to JsonPrimitive(BuildConfig.VERSION_NAME),
        )
        e.sourceId?.let { o["source_id"] = JsonPrimitive(it) }
        return JsonObject(o)
    }

    private fun load(f: File): Map<String, LearnerEventDiff.Sent> = runCatching {
        StoreJson.json.decodeFromString(indexSerializer, f.readText())
    }.getOrNull() ?: emptyMap()

    private fun save(f: File, sent: Map<String, LearnerEventDiff.Sent>) {
        runCatching {
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, "${f.name}.tmp")
            tmp.writeText(StoreJson.json.encodeToString(indexSerializer, sent))
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        }
    }
}
