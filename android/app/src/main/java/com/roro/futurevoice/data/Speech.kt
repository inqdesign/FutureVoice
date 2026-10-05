package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import kotlin.math.roundToInt

// The Speech tab's data — iOS `Models.swift` "Speech (the read-aloud tab)",
// `SpeechLibrary.swift`, `SpeechStore.swift`, `SpeechGate.swift`
// (`SpeechFormat`). Same JSON keys as iOS, so a file reads the same on both.

/** What a speech script does for its listener. The genre decides the SHAPE
 *  the writer is asked for, never the topic. */
@Serializable
enum class SpeechGenre {
    @SerialName("explainer") EXPLAINER,
    @SerialName("product") PRODUCT,
    @SerialName("person") PERSON,
    @SerialName("briefing") BRIEFING,
    @SerialName("news") NEWS,
    /** The learner's own text, typed or pasted — nothing was written for it. */
    @SerialName("own") OWN;

    val raw: String get() = name.lowercase()

    companion object {
        /** The kinds the script writer can be asked for. */
        val writable: List<SpeechGenre> get() = entries.filter { it != OWN }
    }
}

@Serializable
data class SpeechKeyTerm(val term: String, val meaning: String = "")

/** A script read aloud under the prompter. MATERIAL — title, body and each
 *  key term are in the target language; summary and meanings are NOTES in
 *  the native language. */
@Serializable
data class SpeechScript(
    val id: String,
    val title: String,
    val genre: SpeechGenre,
    /** What the learner asked for, as typed. Empty = the writer chose. */
    val topic: String = "",
    val body: String,
    val summary: String = "",
    val keyTerms: List<SpeechKeyTerm> = emptyList(),
    /** Where the facts came from, by name. */
    val sources: List<String> = emptyList(),
    val language: String,
    val targetSeconds: Int = 60,
    @Serializable(with = IsoDateMillisSerializer::class) val createdAt: Long,
    /** Bundled with the app — the one script every account can practise. */
    val isBuiltIn: Boolean = false,
)

/** Every number on a Speech result, computed in code (`SpeechAnalyzer`). */
@Serializable
data class SpeechMetrics(
    val accuracy: Int,
    val rate: Int,
    val rateLow: Int,
    val rateHigh: Int,
    val paceScore: Int,
    val pausesAtBreaks: Int,
    val breaks: Int,
    val hesitations: Int,
    val pauseScore: Int,
    val fillers: Int,
    val fillerScore: Int,
    val steadiness: Int,
    val missed: List<String> = emptyList(),
    val overall: Int,
)

/** The model's notes on a take, in the NATIVE language. */
@Serializable
data class SpeechCoaching(val headline: String, val tips: List<String> = emptyList())

/** One read of a script. */
@Serializable
data class SpeechTake(
    val id: String,
    val scriptId: String,
    @Serializable(with = IsoDateMillisSerializer::class) val createdAt: Long,
    val durationSeconds: Double,
    /** `files/Speech/<file>` — the learner's own voice, always kept. */
    val audioFilename: String,
    /** The camera take with the voice muxed in. Null once deleted. */
    val videoFilename: String? = null,
    val transcript: String = "",
    val metrics: SpeechMetrics,
    val coaching: SpeechCoaching? = null,
)

/**
 * The bundled script (one per target language) and the per-language numbers
 * the Speech tab measures against — iOS `SpeechLibrary`.
 */
object SpeechLibrary {

    /** Words where spaces mark them; Korean by SYLLABLE (a broadcaster's pace
     *  is quoted in 음절); Japanese by character (NHK's 字/分). */
    enum class RateUnit { WORDS, SYLLABLES, CHARACTERS }

    private fun base(language: String) = language.substringBefore('-')

    fun rateUnit(language: String): RateUnit = when (base(language)) {
        "ko" -> RateUnit.SYLLABLES
        "ja", "zh" -> RateUnit.CHARACTERS
        else -> RateUnit.WORDS
    }

    /** A comfortable presentation pace, low…high, in [rateUnit]s per minute. */
    fun rateBand(language: String): IntRange = when (base(language)) {
        "ko" -> 240..330
        "ja" -> 260..340
        "de" -> 105..140
        "fr", "es", "it", "pt" -> 130..170
        else -> 120..160
    }

    /** The midpoint — what a script's length is written to. */
    fun plannedRate(language: String): Int = rateBand(language).let { (it.first + it.last) / 2 }

    fun plannedUnits(seconds: Int, language: String): Int = plannedRate(language) * seconds / 60

    /** The units in [text], counted the way [rateUnit] says. */
    fun units(text: String, language: String): Int = when (rateUnit(language)) {
        RateUnit.WORDS -> text.split(Regex("\\s+")).count { w -> w.any { it.isLetterOrDigit() } }
        RateUnit.SYLLABLES, RateUnit.CHARACTERS -> text.count { it.isLetterOrDigit() }
    }

    /** Estimated read time, in seconds, at the planned pace. */
    fun estimatedSeconds(text: String, language: String): Int {
        val rate = maxOf(1, plannedRate(language))
        return (units(text, language).toDouble() / rate * 60).roundToInt()
    }

    val lengths = listOf(30, 60, 120, 180)

    /** Hesitation sounds the reader writes down so they can be counted —
     *  only sounds that are never words in a script. */
    fun fillers(language: String): List<String> = when (base(language)) {
        "ko" -> listOf("어", "음", "으음", "어어", "엄", "에")
        "ja" -> listOf("えーと", "ええと", "えっと", "えー", "あのー", "うーん")
        "de" -> listOf("äh", "ähm", "öh", "hm", "hmm")
        "fr" -> listOf("euh", "heu", "bah")
        "es" -> listOf("eh", "em", "este")
        else -> listOf("um", "uh", "er", "erm", "uhm", "hmm", "mm")
    }

    // MARK: - The bundled script

    fun builtIn(language: String): SpeechScript? {
        val code = base(language)
        val body = builtInBodies[code] ?: return null
        val title = builtInTitles[code] ?: return null
        return SpeechScript(
            id = builtInId(code), title = title, genre = SpeechGenre.EXPLAINER,
            body = body, language = code, targetSeconds = 60,
            createdAt = 1_790_000_000_000L, isBuiltIn = true,
        )
    }

    /** Stable per language — iOS's ids, so takes keep pointing at it. */
    private fun builtInId(code: String): String {
        val suffix = when (code) {
            "ko" -> "000000000002"
            "ja" -> "000000000003"
            "de" -> "000000000004"
            else -> "000000000001"
        }
        return "5BEEC000-0000-4000-8000-$suffix"
    }

    // Each language's sample is WRITTEN in that language, not translated
    // (iOS `fedae316` → `a4e617b9`): why practise speaking out loud.
    private val builtInTitles = mapOf(
        "en" to "Why practise out loud?",
        "ko" to "왜 소리 내어 연습해야 할까",
        "ja" to "声に出して話そう",
        "de" to "Sprecht es laut aus",
    )

    private val builtInBodies = mapOf(
        "en" to """
Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?

Speaking is a skill, not just knowledge. You can know the words and the grammar, but if your mouth has never actually built the sentence, it tends to let you down when it matters. That's why practice has to happen out loud.

Saying things aloud also helps them stick. Research suggests we remember what we've said better than what we've only read.

And when you record yourself, you notice things you'd never catch otherwise: how fast you really talk, how often you say "um" and "uh", whether your voice fades at the end of a sentence.

Presentations, interviews, even a first conversation with someone new all get easier with practice. The minute you just spent reading this out loud? That was your first rep.
""".trim(),
        "ko" to """
여러분, 머릿속에서는 완벽했던 문장이 막상 입 밖으로 나오는 순간 엉켜 버린 적, 있으시죠?

말하기는 아는 것과 하는 것이 다른 기술입니다. 단어와 문법을 알아도 입이 그 문장을 직접 만들어 본 적이 없으면, 정작 중요한 순간에 막힙니다. 그래서 연습은 소리 내어 해야 합니다.

소리 내어 말하면 기억에도 더 오래 남습니다. 눈으로만 읽은 내용보다 직접 말해 본 내용을 더 잘 기억한다는 연구도 있습니다.

녹음해서 들어 보면 더 많은 것이 보입니다. 내가 실제로 얼마나 빨리 말하는지, "음", "어" 같은 말을 얼마나 자주 하는지, 문장 끝에서 목소리가 작아지지는 않는지. 혼자서는 잘 모르는 것들이거든요.

발표도, 면접도, 처음 만나는 사람과 나누는 대화도 연습한 만큼 편해집니다. 지금 이 원고를 소리 내어 읽은 일 분이 바로 그 첫 연습입니다.
""".trim(),
        "ja" to """
皆さん、頭の中では完璧だった文が、口に出した瞬間に崩れてしまった経験はありませんか。

話すことは、知識ではなく技術です。単語や文法を知っていても、自分の口で一度も言ったことのない文は、いざという時に出てきません。だから練習は、声に出してするものなんです。

声に出すと、覚えやすくもなります。黙って読んだことより、声に出して言ったことのほうが記憶に残りやすい、という研究もあるそうです。

そして、自分の声を録音してみてください。本当はどのくらいの速さで話しているのか。「えーと」や「あの」を、どれだけ言っているのか。文の終わりで、声が小さくなっていないか。一人では気づけないことが、はっきり聞こえてきます。

発表も、面接も、初めての人との会話も、練習すれば楽になります。今この文章を声に出して読んだ一分間が、皆さんの最初の練習です。
""".trim(),
        "de" to """
Kennt ihr das? Im Kopf ist der Satz perfekt. Und sobald ihr ihn aussprecht, fällt er auseinander.

Sprechen ist eine Fähigkeit, nicht nur Wissen. Ihr könnt alle Wörter und die Grammatik kennen. Wenn euer Mund den Satz aber noch nie gebildet hat, lässt er euch im entscheidenden Moment im Stich. Deshalb müsst ihr laut üben.

Was ihr laut sagt, bleibt außerdem besser hängen. Studien deuten darauf hin, dass wir uns an Ausgesprochenes besser erinnern als an das, was wir nur still gelesen haben.

Nehmt euch dabei auf. Dann hört ihr, was euch allein nicht auffällt: wie schnell ihr wirklich sprecht, wie oft ihr „äh“ oder „ähm“ sagt, und ob eure Stimme am Satzende leiser wird.

Präsentationen, Vorstellungsgespräche, sogar ein Gespräch mit jemand Neuem: Mit Übung wird das alles leichter. Und die Minute, in der ihr das gerade laut gelesen habt? Das war eure erste Übung.
""".trim(),
    )

    /** iOS `SpeechOwnScriptSheet.defaultTitle`: the first sentence, cut to a
     *  title's length. */
    fun defaultTitle(text: String): String {
        val firstLine = text.lines().firstOrNull() ?: text
        val enders = setOf('.', '!', '?', '。', '！', '？')
        val sentence = firstLine.split { it in enders }.firstOrNull { it.isNotEmpty() } ?: firstLine
        val clean = sentence.trim()
        return if (clean.length > 48) clean.take(46) + "…" else clean
    }

    private fun String.split(predicate: (Char) -> Boolean): List<String> {
        val out = mutableListOf<String>()
        val cur = StringBuilder()
        for (ch in this) {
            if (predicate(ch)) { if (cur.isNotEmpty()) out += cur.toString(); cur.clear() } else cur.append(ch)
        }
        if (cur.isNotEmpty()) out += cur.toString()
        return out
    }
}

/**
 * Scripts and takes for the Speech tab — iOS `SpeechStore`. JSON per target
 * language (`files/lang/<code>/speech_*.json`), media global under
 * `files/Speech/`. Local only: a camera take is hundreds of megabytes, and
 * the learner decides what happens to it.
 */
class SpeechStore private constructor(private val context: Context) {

    private val _scripts = MutableStateFlow<List<SpeechScript>>(emptyList())
    val scripts: StateFlow<List<SpeechScript>> = _scripts
    private val _takes = MutableStateFlow<List<SpeechTake>>(emptyList())
    val takes: StateFlow<List<SpeechTake>> = _takes
    /** Takes whose video is still being put together. */
    private val _videoPending = MutableStateFlow<Set<String>>(emptySet())
    val videoPending: StateFlow<Set<String>> = _videoPending
    private var loadedLanguage: String? = null

    private val scriptList = ListSerializer(SpeechScript.serializer())
    private val takeList = ListSerializer(SpeechTake.serializer())

    private fun dir() = LanguageScope.activeDirectory(context)
    private fun scriptsFile() = File(dir(), "speech_scripts.json")
    private fun takesFile() = File(dir(), "speech_takes.json")

    /** Reads the active language's files. Cheap; called on every appearance. */
    @Synchronized
    fun reload() {
        val language = LanguageScope.active(context)
        loadedLanguage = language
        val saved = runCatching { StoreJson.json.decodeFromString(scriptList, scriptsFile().readText()) }
            .getOrDefault(emptyList())
        // The bundled script is never written to disk: a new app version can
        // revise it, and every install reads the revision.
        _scripts.value = listOfNotNull(SpeechLibrary.builtIn(language)) +
            saved.filter { !it.isBuiltIn }.sortedByDescending { it.createdAt }
        _takes.value = runCatching { StoreJson.json.decodeFromString(takeList, takesFile().readText()) }
            .getOrDefault(emptyList()).sortedByDescending { it.createdAt }
    }

    fun reloadIfLanguageChanged() {
        if (loadedLanguage != LanguageScope.active(context)) reload()
    }

    fun markVideoPending(id: String, pending: Boolean) {
        _videoPending.value = if (pending) _videoPending.value + id else _videoPending.value - id
    }

    fun script(id: String): SpeechScript? = _scripts.value.firstOrNull { it.id == id }
    fun takes(scriptId: String): List<SpeechTake> = _takes.value.filter { it.scriptId == scriptId }
    fun take(id: String): SpeechTake? = _takes.value.firstOrNull { it.id == id }
    fun best(scriptId: String): Int? = takes(scriptId).maxOfOrNull { it.metrics.overall }

    @Synchronized
    fun add(script: SpeechScript) {
        val rest = _scripts.value.filter { it.id != script.id }
        _scripts.value = rest.filter { it.isBuiltIn } + script + rest.filter { !it.isBuiltIn }
        writeScripts()
    }

    @Synchronized
    fun deleteScript(id: String) {
        takes(id).forEach { deleteTake(it.id) }
        _scripts.value = _scripts.value.filterNot { it.id == id && !it.isBuiltIn }
        writeScripts()
    }

    @Synchronized
    fun save(take: SpeechTake) {
        _takes.value = listOf(take) + _takes.value.filter { it.id != take.id }
        writeTakes()
    }

    /** Applies a change to a stored take; null when it's gone. */
    @Synchronized
    fun update(id: String, change: (SpeechTake) -> SpeechTake): SpeechTake? {
        val take = take(id) ?: return null
        val next = change(take)
        _takes.value = _takes.value.map { if (it.id == id) next else it }
        writeTakes()
        return next
    }

    @Synchronized
    fun deleteTake(id: String) {
        val take = take(id) ?: return
        mediaFile(context, take.audioFilename).delete()
        take.videoFilename?.let { mediaFile(context, it).delete() }
        _takes.value = _takes.value.filter { it.id != id }
        writeTakes()
    }

    /** Drops the camera take and keeps the voice, the score and the notes. */
    fun deleteVideo(takeId: String) {
        val video = take(takeId)?.videoFilename ?: return
        mediaFile(context, video).delete()
        update(takeId) { it.copy(videoFilename = null) }
    }

    private fun writeScripts() {
        val own = _scripts.value.filter { !it.isBuiltIn }
        runCatching { atomicWrite(scriptsFile(), StoreJson.json.encodeToString(scriptList, own)) }
    }

    private fun writeTakes() {
        runCatching { atomicWrite(takesFile(), StoreJson.json.encodeToString(takeList, _takes.value)) }
    }

    private fun atomicWrite(file: File, text: String) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) { file.writeText(text); tmp.delete() }
    }

    companion object {
        @Volatile private var instance: SpeechStore? = null
        fun shared(context: Context): SpeechStore =
            instance ?: synchronized(this) {
                instance ?: SpeechStore(context.applicationContext).also { it.reload(); instance = it }
            }

        fun mediaDirectory(context: Context): File =
            File(context.filesDir, "Speech").apply { mkdirs() }

        fun mediaFile(context: Context, name: String): File = File(mediaDirectory(context), name)
    }
}
