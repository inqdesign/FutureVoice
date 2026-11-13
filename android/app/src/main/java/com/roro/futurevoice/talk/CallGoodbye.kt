package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.GeminiClient
import com.roro.futurevoice.net.VoiceClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/**
 * The fluent self's spoken goodbye after the learner hangs up (iOS
 * `CallGoodbye`, 5fdc61f8 / 089e7386, founder 2026-11-12). The book takes
 * 10–30 s to build, and that wait was silence; now the fluent self says ~12 s
 * of feedback in the learner's own voice while the board fills underneath.
 *
 * - Feedback on THIS call, and nothing else: one thing done well, one tip if
 *   a slip was left unfixed, a short bye. No "next time" and never a question.
 * - Code decides what may be praised; the model only phrases it.
 * - Only what exists at hang-up (the summary is still being written).
 */
object CallGoodbye {
    data class Facts(
        /** Learner lines the live correction found nothing in. */
        val cleanLines: List<String> = emptyList(),
        /** Slips corrected during the call and then said right later in it. */
        val fixedSlips: List<TurnFix> = emptyList(),
        /** Slips never said right afterwards — the only possible tip. */
        val openSlips: List<TurnFix> = emptyList(),
        /** Notebook items the learner used in the call (the ticked chips). */
        val wordsUsed: List<String> = emptyList(),
    ) {
        /** Something to praise. With nothing earned the goodbye is skipped. */
        val hasPraise: Boolean get() = cleanLines.isNotEmpty() || fixedSlips.isNotEmpty() || wordsUsed.isNotEmpty()
    }

    data class Line(
        val spoken: String,
        /** The same sentences in the native language, for the screen. Empty
         *  when the learner's own language is the one on the call. */
        val translation: String,
    )

    /** Fewer learner turns than this is not a call to give feedback on. */
    const val MIN_LEARNER_TURNS = 3
    /** A clean line shorter than this is "yes" or "okay" — nothing to praise. */
    const val MIN_CLEAN_WORDS = 5
    const val MAX_EACH = 6

    /** What may be said, read off the turns. Lines read off coach mode's
     *  suggestion and lines marked misheard are left out. A turn whose
     *  correction never arrived (`fixes == null`) is neither clean nor a slip. */
    fun facts(turns: List<Turn>, wordsUsed: List<String>, target: String): Facts? {
        val learner = turns.filter { it.role == TurnRole.USER && !it.excludedFromScoring && !it.readFromCoach }
        if (learner.size < MIN_LEARNER_TURNS) return null
        val unspaced = !LanguageCatalog.writesSpaces(target)
        fun key(s: String): String {
            val n = CarryoverDetector.normalized(s)
            return if (unspaced) n.filter { !it.isWhitespace() } else n
        }
        val clean = mutableListOf<String>()
        val fixed = mutableListOf<TurnFix>()
        val open = mutableListOf<TurnFix>()
        val seen = mutableSetOf<String>()
        learner.forEachIndexed { i, turn ->
            val fixes = turn.suggestion?.fixes ?: return@forEachIndexed
            if (fixes.isEmpty()) {
                if (WordSplitter.count(turn.transcript, target) >= MIN_CLEAN_WORDS) clean += turn.transcript
                return@forEachIndexed
            }
            for (fix in fixes) {
                val now = key(fix.now)
                if (now.isEmpty() || !seen.add(now)) continue
                val saidRight = learner.drop(i + 1).any { key(it.transcript).contains(now) }
                if (saidRight) fixed += fix else open += fix
            }
        }
        val facts = Facts(clean.takeLast(MAX_EACH), fixed.takeLast(MAX_EACH), open.takeLast(MAX_EACH),
            wordsUsed.take(MAX_EACH))
        return if (facts.hasPraise) facts else null
    }

    @Serializable
    private data class Payload(val spoken: String? = null, val translation: String? = null)

    /**
     * Writes the goodbye, STREAMED: [onFirstSentence] gets the opening sentence
     * the moment it is written so the voice can start on it while the rest is
     * still coming. A first sentence that asks something or isn't in the
     * target script is never handed over; the caller then speaks the finished
     * line instead.
     */
    suspend fun write(gemini: GeminiClient, facts: Facts, topic: String?, target: String, native: String, level: CefrLevel,
                      sessionId: String, onFirstSentence: (suspend (String) -> Unit)? = null): Line? {
        val payload = runCatching {
            withTimeoutOrNull(15_000) {
                gemini.sendJsonStream(
                    system = system(target, native, level),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content(facts, topic))),
                    serializer = Payload.serializer(),
                    model = GeminiClient.Model.FLASH_36,
                    // Room for thinking: a cut answer loses the whole goodbye.
                    maxTokens = 2000,
                    purpose = "goodbye",
                    idempotencyKey = "goodbye:$sessionId",
                    earlyField = "spoken",
                    onEarlyField = {},
                    onFirstSentence = { text ->
                        if (onFirstSentence != null && !text.any { it == '?' || it == '？' } &&
                            TextScript.isInTargetScript(text, target)) onFirstSentence(text)
                    },
                    // The stream broke after the first sentence went to the
                    // voice: keep what is being heard rather than nothing.
                    fallbackFromEarly = { Payload(spoken = it) },
                )
            }
        }.getOrNull()
        var spoken = payload?.spoken?.trim().orEmpty()
        if (spoken.isEmpty()) return null
        // A question is the one thing a goodbye may not end on.
        if (spoken.any { it == '?' || it == '？' }) {
            spoken = withoutQuestions(spoken)
            if (spoken.isEmpty()) return null
        }
        if (!TextScript.isInTargetScript(spoken, target)) return null
        val translation = if (LanguageCatalog.sameLanguage(target, native)) ""
            else payload?.translation?.trim().orEmpty()
        return Line(spoken, translation)
    }

    /** What is left to say once [first] has been spoken: the line after it, or
     *  "" when the finished line doesn't start with it. */
    fun remainder(spoken: String, first: String): String =
        if (!spoken.startsWith(first)) "" else spoken.substring(first.length).trim()

    /** The text with every sentence that asks something removed. */
    fun withoutQuestions(text: String): String {
        val kept = StringBuilder()
        var current = StringBuilder()
        for (ch in text) {
            current.append(ch)
            if (ch in ".!?。！？") {
                if (ch != '?' && ch != '？') kept.append(current)
                current = StringBuilder()
            }
        }
        if (current.toString().trim { it == ' ' || it == '\t' }.isNotEmpty()) kept.append(current)
        return kept.toString().trim()
    }

    fun content(facts: Facts, topic: String?): String {
        val c = StringBuilder()
        if (!topic.isNullOrEmpty()) c.append("The call was about: $topic\n\n")
        c.append("MAY BE PRAISED (pick ONE):\n")
        for (line in facts.cleanLines) c.append("- a line they said with no mistake: \"$line\"\n")
        for (fix in facts.fixedSlips) {
            c.append("- a slip they fixed during the call: they first said \"${fix.was}\" and later said it right: \"${fix.now}\"\n")
        }
        for (word in facts.wordsUsed) c.append("- a word from their notebook they used: \"$word\"\n")
        if (facts.openSlips.isEmpty()) {
            c.append("\nTIP: none. Skip the tip.\n")
        } else {
            c.append("\nTIP (pick the ONE that matters most, or none):\n")
            for (fix in facts.openSlips) c.append("- they said \"${fix.was}\"; right: \"${fix.now}\" (${fix.why})\n")
        }
        return c.toString()
    }

    fun system(target: String, native: String, level: CefrLevel): String {
        val targetName = LanguageCatalog.englishName(target)
        val nativeName = LanguageCatalog.englishName(native)
        return """
        You are the learner's future self: the same person a few years on, already fluent in $targetName. You just finished a phone call with them and they hung up. In about 12 seconds of speech you give them feedback on THIS call, the way a caring friend would.

        One short spoken paragraph, 2 to 4 sentences, at most 45 words:
        1. ONE thing they did well, taken ONLY from the MAY BE PRAISED list. Name it concretely (quote the words). Nothing else may be praised, and never a generic "great job" or "great vocabulary".
        2. ONE tip, only from the TIP list: say the right way once, kindly. If the TIP list says none, skip it.
        3. A short bye. Nothing about next time, no plans, no suggestions, and NO question mark anywhere: the call is over and they cannot answer.

        Rules:
        - Spoken $targetName only, informal, as to a close friend (${informal(target)}). Words and sentence shapes a ${level.code.uppercase()} learner understands.
        - Every character is spoken aloud. No lists, no brackets, no emojis, no stage directions.
        - A period ends a sentence, a comma only where the voice keeps going.
        - No longing ("I'll miss you", "so good to hear your voice"). Warmth is attention to what they did.
        - No numbers or scores, no app feature names, no names of people, not even theirs.
        - Do not invent anything; use only the lists.

        Reply with JSON only:
        {"spoken": "...", "translation": "exactly the same sentences in casual $nativeName, for the screen; add nothing, drop nothing; quoted $targetName words stay as they are"}
        """.trimIndent()
    }

    /** How the fluent self talks to them in each language. */
    private fun informal(target: String): String = when (target.substringBefore('-')) {
        "ko" -> "반말"
        "ja" -> "plain form, タメ口"
        "de" -> "du"
        "es" -> "tú"
        "fr" -> "tu"
        else -> "casual"
    }
}

/**
 * The goodbye's voice, spoken in pieces on ONE open PCM stream (iOS
 * `CallGoodbyeVoice`): the first sentence the moment it is written, the rest
 * once the line is finished, joined after a short silence ([GAP], the call's
 * 0.42 s).
 */
class CallGoodbyeVoice(
    private val voiceClient: VoiceClient,
    private val voiceId: String,
    private val sessionId: String,
    private val cacheDir: java.io.File,
    volume: Float,
) {
    companion object { const val GAP = 0.42 }

    private val pcm = PcmStreamPlayer(VoiceClient.STREAM_SAMPLE_RATE).apply { this.volume = volume }
    private val mp3 = Mp3Player(cacheDir, source = "call_goodbye").apply { this.volume = volume }
    /** Audio has started (streamed, or the buffered fallback). */
    @Volatile var started = false; private set
    /** The open stream more pieces can join; false after a buffered fallback. */
    private var streaming = false
    private var pieces = 0
    @Volatile private var stopped = false
    var onStart: () -> Unit = {}
    var onFinish: () -> Unit = {}

    /** Speaks [text] after whatever is already playing. True when it produced
     *  audio. Only the FIRST piece may fall back to a whole-file play; a later
     *  one that can't join the open stream is dropped. */
    suspend fun speak(text: String): Boolean {
        if (stopped || text.isEmpty() || (started && !streaming)) return false
        pieces += 1
        val isFirst = !started
        var joined = false
        return try {
            val result = voiceClient.synthesizeStreaming(
                voiceId = voiceId, text = text,
                idempotencyKey = "goodbye-tts:$sessionId:$pieces",
                purpose = "goodbye",
            ) { chunk ->
                if (stopped) return@synthesizeStreaming
                if (!started) {
                    pcm.start()
                    started = true
                    streaming = true
                    joined = true
                    onStart()
                } else if (!joined) {
                    if (!streaming) return@synthesizeStreaming
                    joined = true
                    pcm.write(ByteArray((VoiceClient.STREAM_SAMPLE_RATE * GAP).toInt() * 2))
                }
                pcm.write(chunk)
            }
            if (joined || stopped) return joined
            if (!isFirst || started) return false
            // The stream never opened (a server that answered with the whole
            // file): play what came back in one piece.
            when (result) {
                is VoiceClient.StreamedAudio.Mp3 -> {
                    if (result.data.isEmpty()) return false
                    started = true
                    onStart()
                    runCatching { mp3.play(result.data) }
                    onFinish()
                    true
                }
                else -> false
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            joined
        }
    }

    /** No more pieces are coming: let what is queued play out, then finish. */
    suspend fun finish() {
        if (streaming && !stopped) {
            pcm.drain()
            if (!stopped) onFinish()
        }
    }

    fun stop() {
        stopped = true
        pcm.cutNow()
        pcm.stop()
        mp3.stop()
    }
}
