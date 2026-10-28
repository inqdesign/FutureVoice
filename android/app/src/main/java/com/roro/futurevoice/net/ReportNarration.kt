package com.roro.futurevoice.net

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.HabitFinding
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.talk.CoachingLanguage
import com.roro.futurevoice.talk.ConversationPrompt
import com.roro.futurevoice.talk.PacedSpeech
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.security.MessageDigest

/**
 * The report, PRESENTED (iOS `ReportNarration`, 2026-10-27,
 * docs/personal-report-plan.md): the fluent self reads the deck aloud, one or
 * two sentences per card, in the voice the learner picked, and the deck moves
 * on when a line ends.
 *
 * Founder's picks: the TARGET language at the learner's level, with the
 * native-language caption under it — it is listening practice, and it keeps
 * the fluent self fluent; the caption carries the explanation. First home:
 * the free-minutes report, the moment a learner decides.
 *
 * Same rule as the coach note: the script is written FROM the facts the code
 * already put on each card ([ReportNarrator.facts]), never asked for numbers.
 * Written in two halves because the deck fills in two: the counts cards are
 * known the moment it opens, the coach and the level land seconds later.
 */
@Serializable
data class ReportNarration(val lines: List<Line> = emptyList()) {
    @Serializable
    data class Line(
        /** The deck card's iOS name (`WeekRecapSheet.Card`). */
        val card: String,
        /** What the fluent self says — target language, the learner's level. */
        val text: String,
        /** The same line in the native language, for the caption. */
        val caption: String,
    )

    fun line(card: String): Line? = lines.firstOrNull { it.card == card }

    fun merged(more: List<Line>): ReportNarration {
        val out = lines.toMutableList()
        for (line in more) {
            val i = out.indexOfFirst { it.card == line.card }
            if (i >= 0) out[i] = line else out += line
        }
        return ReportNarration(out)
    }
}

object ReportNarrator {
    /** One card the narrator is asked to speak over, with what is on it. */
    data class CardFacts(val card: String, val facts: List<String>)

    /** The ledger tag for both the script and the voice. The voice is free
     *  to the learner (`tts` FREE_PURPOSES): this report is shown to a
     *  learner whose free minutes are spent, and a report that costs them
     *  minutes they don't have would be a wall. */
    const val PURPOSE = "report-narration"

    /** Lines past this length are cut to their first sentences: a card is
     *  looked at for a few seconds, and a paragraph read over it is a lecture. */
    const val MAX_LINE_CHARACTERS = 220

    suspend fun write(
        cards: List<CardFacts>,
        firstTalks: Boolean,
        targetLanguage: String,
        nativeLanguage: String,
        level: CefrLevel,
        learnerName: String?,
    ): List<ReportNarration.Line> {
        if (cards.isEmpty()) return emptyList()
        val target = LanguageCatalog.englishName(targetLanguage)
        val native = LanguageCatalog.englishName(nativeLanguage)
        val span = if (firstTalks) "their first talks with you, the free minutes that just ran out"
            else "the week that just closed"
        val system = "You are the learner's fluent future self — them, a few years on, speaking ${target} with ease, in their own voice. You are presenting their report to them, card by card, like a friend walking them through a few slides about ${span}. Each card is on screen while you speak over it.\n" +
            "\n" +
            "For EVERY card listed, write:\n" +
            "- \"text\": what you say over it, in ${target}. One or two short spoken sentences, at most ~25 words. Pitch it to their level (${level.code.uppercase()}): ${ConversationPrompt.speechVocabulary(level)} They must be able to follow it by ear. Talk TO them (\"you\"), informally, the way you'd talk to yourself. Say what the card means for them, don't read the card out; one number at most per line, only one that is in the facts. The first card opens the report; the last one hands over to what comes next.\n" +
            "- \"caption\": the same line in natural ${native}, the same informal register (Korean: 반말, never 해요체 or 당신; Japanese: タメ口). Always ${native}, whatever language the facts are written in; the words they should say stay in ${target} inside it.\n" +
            "\n" +
            "${CoachingLanguage.selfWarmth}\n" +
            "\n" +
            "${CoachingLanguage.breathPunctuation}\n" +
            "\n" +
            "THEY LEARN FROM YOUR VOICE: never say their mistake out loud — say the RIGHT way (\"next time, try: I've been working here for three years\"), and the caption can name what changed. No grammar terms in what you say (no \"present perfect\", \"article\", \"tense\"); say the words themselves. A word to reach for next goes inside a short sentence of the kind they could use.\n" +
            "\n" +
            "SAY IT THE WAY IT IS SPOKEN: a level is written in \"text\" as the words a person says (English \"A two\", German \"A zwei\", Spanish \"A dos\", Korean \"에이 투\", Japanese \"エーツー\"), never \"A2\" — the synthesizer misreads the code. The caption keeps \"A2\".\n" +
            "\n" +
            "RULES: use only the facts given for each card — never invent a number, a word they said, a level or a plan. A quote may appear only if it is in the facts, copied exactly. No exclamation marks, no slogans, no \"Great job!\" — warmth is in noticing something specific. Never mention cards, slides or the app. ${if (firstTalks) "Never say \"this week\" or \"last week\"." else ""}\n" +
            "\n" +
            "Return JSON only: {\"lines\": [{\"card\": \"...\", \"text\": \"...\", \"caption\": \"...\"}]}, one entry per card, same order, the card names exactly as given."

        var user = learnerName?.let { "Learner's name: $it\n\n" } ?: ""
        user += cards.joinToString("\n\n") { c ->
            "CARD ${c.card}\n" + c.facts.joinToString("\n") { "- $it" }
        }
        val response = GeminiClient(AuthRepository()).sendJson(
            system = system,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
            serializer = Payload.serializer(),
            maxTokens = 4096,
            purpose = PURPOSE,
        )
        val asked = cards.map { it.card }.toSet()
        return response.lines.mapNotNull { raw ->
            val text = trimmed(raw.text)
            if (raw.card !in asked || text.isEmpty()) null
            else ReportNarration.Line(raw.card, text, raw.caption.trim())
        }
    }

    @Serializable
    private data class Payload(val lines: List<Raw>) {
        @Serializable
        data class Raw(val card: String, val text: String, val caption: String)
    }

    private fun count(s: String) = s.codePointCount(0, s.length)

    /** Whole sentences up to [MAX_LINE_CHARACTERS], at least one. */
    fun trimmed(text: String): String {
        val clean = text.trim()
        if (count(clean) <= MAX_LINE_CHARACTERS) return clean
        var out = ""
        for (sentence in PacedSpeech.sentences(clean)) {
            val next = if (out.isEmpty()) sentence else "$out $sentence"
            if (count(next) > MAX_LINE_CHARACTERS && out.isNotEmpty()) break
            out = next
        }
        return out
    }

    // MARK: - What each card shows

    /** Everything the deck knows when it asks for a line. Each card's facts
     *  are the card's own content, in English for the model — the script is
     *  written in the target language and captioned in the native one. */
    data class Context(
        val recap: WeekRecap,
        val isTrial: Boolean,
        val level: CefrLevel?,
        val levelRationale: String?,
        val testScore: Int?,
        val testTotal: Int?,
        val testThin: Boolean = false,
        val routineHeadline: String?,
        val routine: List<String> = emptyList(),
        /** How they used the app ([com.roro.futurevoice.data.HabitAdvisor]), the routine's evidence. */
        val habits: List<HabitFinding> = emptyList(),
        /** The trial's usage card (every feature, how much), which takes the
         *  talk card's place in the trial deck. */
        val usage: List<String> = emptyList(),
    )

    /** The cards whose content is known the moment the deck opens. */
    val earlyCards = setOf("cover", "talk", "used", "review", "fresh", "stumbles")

    fun facts(card: String, c: Context): CardFacts? {
        val r = c.recap
        val f = mutableListOf<String>()
        when (card) {
            "cover" -> when {
                c.isTrial ->
                    f += "Opening card: their free minutes are over. They talked ${r.talkMinutes} min in ${r.talks.size} talk(s)."
                r.hasActivity -> {
                    f += "Opening card: the week. They practised ${r.daysActive} of 7 days, ${r.talkMinutes} min of talk."
                    if (r.streak > 1) f += "Streak: ${r.streak} days."
                }
                else -> f += "Opening card: a quiet week, nothing practised. One talk is enough to start again."
            }
            "talk" -> if (c.isTrial && c.usage.isNotEmpty()) f += c.usage else {
                f += "They talked ${r.talkMinutes} min in ${r.talks.size} talk(s)."
                val titles = r.talks.take(4).map { it.title }
                if (titles.isNotEmpty()) f += "Talks: ${titles.joinToString(" · ")}"
                val previous = r.previousTalkSeconds / 60
                if (previous > 0) f += "The week before: $previous min."
            }
            "used" -> {
                f += "${r.usedCount} thing(s) they had studied, then said themselves in a real talk."
                for (e in r.used.take(3)) f += "Used: ${e.item} — in \"${e.quote}\""
            }
            "review" -> {
                if (r.nowYours.isNotEmpty())
                    f += "${r.nowYours.size} word(s)/phrase(s) became theirs: ${r.nowYours.take(6).joinToString(", ")}."
                if (r.sentencesGot.isNotEmpty()) f += "${r.sentencesGot.size} sentence card(s) learned."
                if (r.shadowTakes > 0)
                    f += "${r.shadowTakes} shadowing take(s)" + (r.shadowAverage?.let { ", average score $it" } ?: "") + "."
                if (r.scenes > 0) f += "${r.scenes} scene(s) watched."
            }
            "fresh" -> {
                if (r.newExpressionCount > 0) {
                    f += "${r.newExpressionCount} phrase(s) YOU (the fluent self) said that they haven't said yet; they are saved for them."
                    for (e in r.newExpressions.take(3)) f += "Phrase: ${e.item}"
                }
                if (r.newCards > 0) f += "${r.newCards} new review card(s) made from their corrections."
            }
            "stumbles" -> {
                if (r.stumbles.isNotEmpty()) {
                    f += "The same correction came back more than once:"
                    for (s in r.stumbles.take(3)) f += "\"${s.was}\" → \"${s.now}\", ${s.count} times"
                } else if (r.shakyLines.isNotEmpty()) {
                    f += "Lines that didn't quite land when they shadowed them:"
                    for (s in r.shakyLines.take(2)) f += "\"${s.now}\" (score ${s.count})"
                }
            }
            "grammar" -> {
                val coach = r.coach ?: return null
                if (coach.grammar.isEmpty()) {
                    f += "No grammar point kept coming back."
                } else {
                    for (p in coach.grammar.take(2)) {
                        f += "Grammar point that slipped in different sentences: ${p.rule}" +
                            (p.examples.firstOrNull()?.let { " — e.g. \"${it.was}\" → \"${it.now}\"" } ?: "")
                    }
                }
            }
            "words" -> {
                val coach = r.coach ?: return null
                if (coach.upgrades.isEmpty()) {
                    f += "No word carried too much of the load."
                } else {
                    for (u in coach.upgrades.take(2))
                        f += "They leaned on \"${u.instead}\" (${u.count} times); a word to reach for next: \"${u.better}\"."
                }
            }
            "coach" -> {
                val coach = r.coach ?: return null
                f += "The coach's headline: ${coach.headline}"
                if (coach.insight.isNotEmpty()) f += "How they speak: ${coach.insight}"
                for (p in coach.plan.take(3)) f += "Next up: $p"
            }
            "trialTest", "trialTestDone" -> {
                val s = c.testScore
                val t = c.testTotal
                if (s != null && t != null) {
                    f += "They took a short test made from their own talks: $s/$t."
                } else if (c.testThin) {
                    f += "Their talks were too short to make a test from; the report goes on without it."
                } else {
                    f += "Next: a short test made from what they said — the words, the phrases, the corrections. They can take it or skip it."
                }
            }
            "level" -> {
                val level = c.level ?: return null
                f += "Their speaking level, read from their talks: ${level.code.uppercase()}."
                c.levelRationale?.takeIf { it.isNotEmpty() }?.let { f += "Why: $it" }
                f += "It moves as they talk."
            }
            "routine" -> {
                for (finding in c.habits.take(3)) {
                    f += "What we saw (${finding.tone.raw}): " + finding.facts.filter { !it.startsWith("Why") }.joinToString(" ")
                    finding.change?.let { f += "So the routine: $it" }
                }
                if (c.habits.isEmpty()) c.routineHeadline?.let { f += "A routine to keep going: $it" }
                for (line in c.routine.take(4)) f += "Routine: $line"
                f += "Last card. The button under it keeps this routine going. Hand over to it; don't mention prices or plans."
            }
            "test" -> f += "Last card: this week's test, made from their week, is ready."
            else -> return null
        }
        return if (f.isEmpty()) null else CardFacts(card, f)
    }
}

// MARK: - Playback

/**
 * Speaks the current card's line and says when it is done, so the deck can
 * move on (iOS `ReportNarrationPlayer`). Every take is kept in
 * [PhraseAudioStore] (keyed by text + voice), so opening the report again
 * replays it without a second synthesis.
 */
class ReportNarrationPlayer(private val context: Context, private val scope: CoroutineScope) {
    /** The learner can silence it from the deck's top bar; the captions stay. */
    var isOn by mutableStateOf(true)
    var speakingCard by mutableStateOf<String?>(null)
        private set
    var loadingCard by mutableStateOf<String?>(null)
        private set

    private val player = Mp3Player(context.cacheDir, source = "report")
    private var voiceId: String? = null
    /** Bumped on every [speak]/[stop], so a take that lands after the
     *  learner swiped on is never played over the next card. */
    private var generation = 0
    private var job: Job? = null
    private val prefetching = mutableSetOf<String>()

    fun configure(voiceId: String?) { this.voiceId = voiceId }

    fun stop() {
        generation += 1
        job?.cancel()
        job = null
        player.stop()
        speakingCard = null
        loadingCard = null
    }

    /** Plays [line]; [finished] runs when it ends on its own (never when it
     *  was stopped or replaced). */
    fun speak(line: ReportNarration.Line, finished: () -> Unit) {
        stop()
        val voiceId = voiceId
        if (!isOn || voiceId == null) return
        val mine = generation
        job = scope.launch {
            loadingCard = line.card
            val data = audio(line.text, voiceId)
            if (mine != generation) return@launch
            loadingCard = null
            if (data == null) return@launch
            speakingCard = line.card
            val played = runCatching { player.play(data) }.isSuccess
            if (mine != generation) return@launch
            speakingCard = null
            if (played) finished()
        }
    }

    /** Makes the takes ahead of time, in deck order, so a swipe doesn't wait
     *  on the network. */
    fun prefetch(lines: List<ReportNarration.Line>) {
        val voiceId = voiceId ?: return
        val store = PhraseAudioStore.shared(context)
        val todo = lines.filter { it.text !in prefetching && store.data(it.text, voiceId, allowLineage = false) == null }
        if (todo.isEmpty()) return
        todo.forEach { prefetching += it.text }
        scope.launch { for (line in todo) audio(line.text, voiceId) }
    }

    private suspend fun audio(text: String, voiceId: String): ByteArray? {
        val store = PhraseAudioStore.shared(context)
        store.data(text, voiceId, allowLineage = false)?.let { return it }
        return try {
            val digest = MessageDigest.getInstance("SHA-256").digest("$voiceId|$text".toByteArray())
            val data = VoiceClient(AuthRepository()).synthesize(
                voiceId = voiceId, text = text,
                idempotencyKey = "report:" + digest.take(16).joinToString("") { "%02x".format(it) },
                purpose = ReportNarrator.PURPOSE)
            store.save(data, text, voiceId)
            data
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Analytics.capture("report_narration_tts_failed", mapOf("error" to e.toString().take(160)))
            null
        }
    }
}
