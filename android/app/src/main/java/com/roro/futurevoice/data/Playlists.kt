package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.talk.nameIn
import com.roro.futurevoice.ui.displayTitle
import java.io.File
import java.util.UUID

/**
 * The situations, as something to LISTEN to (iOS `Playlists.swift`,
 * 2026-10-18).
 *
 * Every scene the learner made is a short conversation between their fluent
 * self (their clone) and the other person (a preset voice). Played whole and
 * one after another, they are a listening playlist made of nothing but the
 * learner's own situations.
 *
 * Every line is audio the app ALREADY made when the scene was watched
 * ([PhraseAudioStore], under the key `WatchSceneScreen` wrote). Nothing is
 * copied and nothing is ever synthesized here — a line never heard has no
 * file and is left out — so listening costs nothing metered and needs no
 * `BillingGate`.
 */
data class PlaylistLine(
    val id: String = UUID.randomUUID().toString(),
    /** The scene's scenario id. */
    val bookId: String,
    val text: String,
    /** The voice the line was made in. The learner's older clones still
     *  resolve through [PhraseAudioStore]'s lineage. */
    val voiceId: String,
    /** Who says it. */
    val speaker: String,
    /** True for the other person's line. */
    val isOther: Boolean,
    val bookTitle: String,
    /** The ids the other person's voice went by before (preset slots were
     *  re-voiced on 2026-09-28 and 2026-10-12), so a scene watched back then
     *  still finds its lines. Empty for the fluent self, whose older clones
     *  resolve through [PhraseAudioStore]'s lineage. */
    val fallbackVoices: List<String> = emptyList(),
    /** The file that plays, resolved once when the list is built: any
     *  speed's take, the file Watch played it from, or a take under an older
     *  voice id. */
    val audioKey: String? = null,
    /** A line that is not one of the app's own takes: a news-show line,
     *  downloaded to the cache ([NewsShow]). Played as is. */
    val localFile: File? = null,
    /** The line's meaning per native language, made once where the line was
     *  (the podcast's publisher), so a thousand listeners don't each ask
     *  for the same translation. Null for a scene line. */
    val translations: Map<String, String>? = null,
    /** A podcast line's episode number and category (the listening record). */
    val episodeNumber: Int? = null,
    val episodeCategory: String? = null,
) {
    val isFluentSelf: Boolean get() = !isOther

    /** A line worth saying back in the "time to say it back" pause: the
     *  fluent self's in a scene (the other person's is answered, not
     *  repeated), and every host line in the podcast. */
    val isToSayBack: Boolean get() = isFluentSelf || localFile != null

    val hasAudio: Boolean get() = localFile?.exists() ?: (audioKey != null)

    fun audioFile(context: Context): File? =
        localFile ?: audioKey?.let { PhraseAudioStore.shared(context).fileForKey(it) }

    /** Word timings measured on the take that plays, if any were kept. */
    fun storedTimings(context: Context): List<WordTiming>? =
        if (localFile != null) null else audioKey?.let { PhraseAudioStore.shared(context).timingsForKey(it) }
}

/** One situation, ready to play. */
data class SceneTrack(
    val id: String,
    val title: String,
    val otherName: String,
    val date: Long,
    val lines: List<PlaylistLine>,
)

object SceneLibrary {
    /**
     * The scene played whole: every line of its dialogue in order, the
     * fluent self in the learner's clone and the other person in the voice
     * the scene was watched with.
     */
    fun dialogue(context: Context, scenario: Scenario, cloneId: String,
                 people: List<Counterpart>, language: String): List<PlaylistLine> {
        val other = otherPerson(scenario, people, language)
        val me = context.getString(R.string.your_fluent_self)
        val otherVoices = VoicePreset.everyVoiceEverUsed(other.voiceId)
        val store = PhraseAudioStore.shared(context)
        return scenario.curriculum?.dialogue.orEmpty().mapNotNull { turn ->
            val mine = turn.speaker == "user"
            val text = turn.text.trim()
            if (text.isEmpty()) return@mapNotNull null
            val voiceId = if (mine) cloneId else other.voiceId
            val fallbacks = if (mine) emptyList() else otherVoices
            PlaylistLine(
                bookId = scenario.id, text = text, voiceId = voiceId,
                speaker = if (mine) me else other.name,
                isOther = !mine,
                bookTitle = scenario.displayTitle,
                fallbackVoices = fallbacks,
                audioKey = store.sceneLineKey(text, voiceId, isOther = !mine, fallbackVoices = fallbacks),
            )
        }
    }

    /**
     * Every situation with something to hear, newest first. A scene with
     * only one side on file isn't a conversation and is left out.
     */
    suspend fun tracks(context: Context, scenarios: List<Scenario>, cloneId: String?,
                       language: String): List<SceneTrack> {
        if (cloneId.isNullOrEmpty()) return emptyList()
        val people = CounterpartStore.shared(context).load()
        return scenarios
            .filter { it.archivedAt == null }
            .mapNotNull { scenario ->
                val lines = dialogue(context, scenario, cloneId, people, language).filter { it.hasAudio }
                if (lines.none { it.isFluentSelf } || lines.none { it.isOther }) return@mapNotNull null
                SceneTrack(id = scenario.id, title = scenario.displayTitle,
                    otherName = otherPerson(scenario, people, language).name,
                    date = scenario.curriculum?.generatedAt ?: scenario.createdAt,
                    lines = lines)
            }
            .sortedByDescending { it.date }
    }

    private data class Other(val name: String, val voiceId: String)

    /** The same person `WatchSceneScreen` casts (`castVoiceId` /
     *  `counterpartName`), so the voice id matches the key the lines were
     *  cached under. */
    private fun otherPerson(scenario: Scenario, people: List<Counterpart>, language: String): Other {
        val person = scenario.counterpartId?.let { id -> people.firstOrNull { it.id == id } }
        val stock = StockPerson.by(scenario.voicePresetId)
        return Other(
            name = person?.name?.takeIf { it.isNotBlank() } ?: stock.nameIn(language),
            voiceId = person?.voicePresetId?.takeIf { it.isNotBlank() } ?: stock.voiceId,
        )
    }
}
