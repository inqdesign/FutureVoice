package com.roro.futurevoice.talk

import com.roro.futurevoice.data.isClose
import com.roro.futurevoice.data.effectiveMyRegister
import android.content.Context
import android.util.Log
import com.roro.futurevoice.BuildConfig
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.audio.LiveTranscriber
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.ProfileStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.VoiceClient
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class TalkConfig(
    val voiceId: String,
    val targetLanguage: String = "en",
    val nativeLanguage: String = "ko",
    val level: CefrLevel = CefrLevel.B1,
    val topic: String = "",
    /** Context the call is told beside the topic — an exam question's part
     *  and cue card, a field topic's line (iOS `topicBlurb`). Prompt only:
     *  the session's title stays [topic]. */
    val topicBlurb: String = "",
    val persona: UserPersona? = null,
    /** Pool-grounded facts for a news talk — the model's only ground truth. */
    val newsFacts: List<String> = emptyList(),
    /** Set when launched from a saved scenario — the session's provenance. */
    val scenarioId: String? = null,
    /**
     * The call's first spoken line, already written (the daily call's
     * voicemail). Skips the opener request entirely — the caller had
     * something to say, that's why they called.
     */
    val initialOpener: String = "",
    /**
     * A Find-people stranger this call is WITH. Two things change and
     * nothing else: the prompt casts the model AS them, and the voice is
     * their PRESET — never the clone. The person on the other end is a
     * stranger, not the fluent self.
     */
    val cast: ConversationEngine.Cast? = null,
    val castVoiceId: String? = null,
    /**
     * The local `Counterpart` row for that stranger. The talk saves as an
     * ordinary Session carrying it, which is what puts the call on the
     * person's own card — and what lets every existing review, transcript
     * and book mechanism work on it for free.
     */
    val counterpartId: String? = null,
    /**
     * A saved talk this call PICKS UP (iOS `ConversationView(resumeSession:)`):
     * same session id, same start, its turns on screen and sent as history,
     * no opener — the mic opens and the learner carries on. The prompt clock
     * says how long it was paused, and the end saves over the same row and
     * re-summarizes the whole talk, merged with its previous analysis.
     */
    val resume: Session? = null,
) {
    /** iOS `systemPrompt()`'s `composedTopic`. */
    val composedTopic: String get() = if (topicBlurb.isEmpty()) topic else "$topic. $topicBlurb"
}

/**
 * [PAUSED] is the call put DOWN, not away: the mic is closed and nothing
 * bills, but the transcript stays and [TalkViewModel.resume] picks the same
 * session up. Only [ENDED] has consequences (a summary, a book).
 */
enum class TalkPhase { IDLE, CONNECTING, LISTENING, THINKING, SPEAKING, PAUSED, ENDED }

/**
 * Which wall ended the call. A FREE account's spent pool leads to the
 * paywall; a SUBSCRIBER's spent allowance never does — they already paid,
 * the pool refills on its own. Neither is an error, so neither lands in
 * [TalkUiState.error].
 */
/**
 * Which wall ended the call. FAIR_USE is not an allowance: it is the
 * account being checked (a stop far above the fair-use flag), and it must
 * never read as minutes running out — on Plus there is no such thing.
 */
enum class TalkWall { OUT_OF_MINUTES, ALLOWANCE_SPENT, SCENES_SPENT, FAIR_USE }

data class TalkUiState(
    val phase: TalkPhase = TalkPhase.IDLE,
    val turns: List<Turn> = emptyList(),
    val partial: String = "",
    val level: Float = 0f,
    val error: String? = null,
    /**
     * The transport went away mid-call. Not an error and not an end: the
     * transcript stays on screen and the learner chooses — reconnect and
     * carry on, or end the talk and keep what was said.
     */
    val dropped: String? = null,
    val wall: TalkWall? = null,
    /** The free pool's wall arrived before the learner said a word (iOS
     *  `talk_wall_before_speaking`): nothing to wrap up, so the screen leaves
     *  with the plans instead of a board. */
    val wallBeforeSpeaking: Boolean = false,
    /** Null until the first tick lands, and null throughout on a plan that doesn't count down. */
    val minutesRemaining: Int? = null,
    /**
     * True when the idle watchdog was what paused the call — the only
     * difference it makes is the hint, so a learner coming back to a quiet
     * screen reads "paused" instead of wondering what broke.
     */
    val pausedForIdle: Boolean = false,
    /** Send-to-answer: the learner pressed Send and the gateway has not
     *  committed the turn yet (it may be waiting on the last final). */
    val sendPending: Boolean = false,
    /** Set when the call ended with something said — the wrap-up's subject. */
    val endedSessionId: String? = null,
    /** How many of [turns] came from the resumed talk (iOS `isResuming` +
     *  `didSaveCurrentSession`: a resumed talk starts saved, and only a new
     *  turn makes it something closing would lose). */
    val resumedTurnCount: Int = 0,
    val lastTiming: Map<String, String> = emptyMap(),
    /** Coach mode's word for the question just asked (iOS `coachHint`) —
     *  drawn above the pill, under the "try saying" line, while they answer. */
    val coachHint: com.roro.futurevoice.ui.TalkGoalItem? = null,
    /** Coach mode's "try saying" for the line just spoken (iOS `coachReply`,
     *  `CoachSuggester`) — every line, the opener included. */
    val coachReply: CoachReply? = null,
    /** The coach's line belongs to the question just answered, so it goes
     *  when the reply begins — but only from SIGHT (iOS `coachStale`,
     *  30e49b07): the slot keeps its height until the next suggestion
     *  replaces it, so the bar never shrinks as the reply's bubble arrives. */
    val coachStale: Boolean = false,
    /** Coach mode's grammar focus for this call, once named. */
    val grammarFocus: GrammarFocus? = null,
    /** Learner turns whose correction was the focus coming back. */
    val focusRepeatTurns: Set<String> = emptySet(),
)

/**
 * The Talk vertical slice: live STT → structured Gemini turn → cloned-voice TTS
 * → auto VAD turn-taking. This is the make-or-break loop of the whole port
 * (`docs/android-plan.md` Phase C).
 */
class TalkViewModel(context: Context) : ViewModel() {

    private val appContext = context.applicationContext
    private val auth = AuthRepository()
    private val gemini = GeminiClient(auth)
    private val voiceClient = VoiceClient(auth)
    private val live = LiveTranscriber(context)
    private val meter = TalkMeter(auth, viewModelScope, appContext)

    /**
     * The realtime transport — the ONLY call path since 2026-09-05 (iOS
     * `RealtimeMode`). The classic per-turn machine below is kept as the
     * reference it was ported from, not as a fallback: as an escape hatch it
     * turned out to be the worse call (it cut learners off mid-sentence on
     * its own VAD tiers), and a setting whose job is "use this if the new
     * one misbehaves" cannot itself be the worse one.
     */
    private val realtime = RealtimeTalkClient(appContext)
    /** Reply context → the fluent-self turn its deltas patch. */
    private val realtimeReplyTurns = HashMap<String, String>()
    private var realtimeSystem: String = ""
    private val pcm = PcmStreamPlayer(VoiceClient.STREAM_SAMPLE_RATE).apply {
        volume = com.roro.futurevoice.data.AudioPrefs.talkVoiceVolume(appContext)
    }
    private val mp3 = Mp3Player(appContext.cacheDir).apply {
        // The ONE surface the learner can turn down — see Mp3Player.volume.
        volume = com.roro.futurevoice.data.AudioPrefs.talkVoiceVolume(appContext)
    }
    private val sessions = SessionStore.shared(appContext)

    private val _state = MutableStateFlow(TalkUiState())
    val state: StateFlow<TalkUiState> = _state.asStateFlow()

    private var config: TalkConfig? = null
    /** The learner asked for the call to stop — a socket closing after that
     *  is the hang-up itself, never a drop to reconnect from. */
    @Volatile private var endRequested = false
    /** "Close without saving": the call ends and nothing is kept (iOS
     *  `close()` → `tearDown()`, which never reaches `endSession`). */
    @Volatile private var discardOnEnd = false
    /** DEBUG: the current call is a staged wall (no service, no gateway). */
    private var stagedCall = false
    /** When the call last put ITSELF back together after a transport drop. */
    @Volatile private var lastAutoReconnectAt = 0L
    /** The greeting to speak from the phone once the gateway says ready —
     *  (text, mp3). Null when the cache missed and the gateway says it. */
    @Volatile private var localOpener: Pair<String, ByteArray>? = null
    private var sessionId: String = ""
    private var startedAt: Long = 0L

    /**
     * Has the learner said anything yet in this call? The meter and the
     * elapsed clock both wait for it: the opener speaks whether or not it is
     * answered, and a call that was opened, listened to and left behind is
     * not a minute of theirs. Per CALL, not per transcript — Continue reopens
     * a book whose turns were spoken on another day.
     */
    private var learnerSpokeThisCall = false

    // Coach mode (iOS `CoachMode.swift`). The chip row lives on the screen,
    // so the screen hands over what may be steered toward and what has been
    // said; the ration, the steer and the judge live here.
    private var coachOn = false
    private var coachPlan = CoachPlan()
    /** The steer last sent to the gateway ("" = none). */
    private var coachSteerSent = ""
    /** Chip row + talk-kept notebook words, in the row's order. */
    private var coachPool: List<com.roro.futurevoice.ui.TalkGoalItem> = emptyList()
    private var usedGoalKeys: Set<String> = emptySet()
    private var focusJob: Job? = null
    /** Tutor mode as the conversation prompt has it right now (iOS
     *  `tutorThisCall`). It lives in the system prompt, so a flip mid-call
     *  sends the gateway a new one ([setTutorMode], iOS 88cc3b33 — it used
     *  to wait for the next call); the classic path reads the rebuilt prompt
     *  at its next turn. A tutored call is a practice call. */
    private var tutorThisCall = false
    /** Send-to-answer for this call (iOS `SendToAnswer`); a flip mid-call
     *  reaches the gateway ([setSendToAnswer]). */
    private var sendToAnswerOn = false
    private var sendPendingJob: Job? = null
    /** Tutor mode was on at some point in this call — the whole call is then
     *  a practice call (iOS `tutorWasOn`). Coach mode is judged per line. */
    private var tutorWasOn = false
    /** This call's conversation prompt with tutor mode on or off — every
     *  other input pinned when the call opened, so a flip changes the tutor
     *  block and nothing else. Null until the prompt is first built. */
    private var promptForTutor: ((Boolean) -> String)? = null
    /** Where a scenario call takes place and who the other side is, for the
     *  "try saying" — "What can I get you?" only has one natural answer once
     *  it knows it is a café (iOS `coachSituation`). Null on every other call. */
    private var coachSituation: String? = null
    /**
     * How the learner speaks on this call, for the "try saying" (iOS
     * `coachRegister`) — the same level the call prompt gives the other side.
     * With the fluent self it is casual (they are talking to themselves);
     * with a person, what the learner set for them, else what the
     * relationship implies. Null in a scene with no person: the scene
     * decides, and the coach keeps the level of its previous suggestion.
     */
    private var coachRegister: com.roro.futurevoice.data.SpeechRegister? = null

    /**
     * This call's TALK time, phone-style: the seconds the meter counts — the
     * fluent self speaking, a reply being written, the learner talking. It
     * stands still while they think of an answer and while the call is
     * paused, because a clock that runs through those says the call cost
     * more than it did (iOS `a422d2c`).
     *
     * Readable after the call ends, and cleared only by the next call's
     * start: the feedback ask and the rating ask both read it on the way
     * out. It used to return 0 the moment the call was wrapped up, which is
     * why neither of them could ever fire.
     */
    fun elapsedSeconds(): Long = meter.billedSeconds

    /** Mid-call speed change: the gateway applies it from the next line. */
    fun setSpeed(multiplier: Double) {
        if (REALTIME) realtime.setSpeed(multiplier)
    }

    /** Reconnect after a failed reply — the learner spoke and heard nothing. */
    fun retry() {
        val cfg = config ?: return
        _state.update { it.copy(error = null) }
        if (REALTIME) resume() else start(cfg)
    }
    private var systemPrompt: String = ""
    private var endpointJob: Job? = null
    private var callJob: Job? = null
    private var idleWatchJob: Job? = null

    /**
     * The last moment anything real happened. Deliberately OUTSIDE the watch
     * job: the job is re-armed every time the mic opens, and a clock living
     * inside it would be reset by every restart. Only real activity moves it.
     */
    private var lastActivityAt: Long = 0L

    private var lastTranscriptChangeAt: Long? = null
    private var didPreconnectThisTurn = false
    private var turnStartedAt: Long = 0L
    private var turnEndedSpeakingAt: Long = 0L
    private var turnTiming = mutableMapOf<String, String>()

    init {
        viewModelScope.launch {
            meter.minutesRemaining.collect { m -> _state.update { it.copy(minutesRemaining = m) } }
        }
    }

    // MARK: - Lifecycle

    fun start(config: TalkConfig) {
        endRequested = false
        discardOnEnd = false
        stagedCall = false
        if (_state.value.phase != TalkPhase.IDLE && _state.value.phase != TalkPhase.ENDED) return
        // The view model outlives a call, and a greeting parked for a call
        // that ended before the gateway was ready would play on the NEXT
        // call's first LISTENING — on top of that call's own opener (a free
        // talk's "did you sleep well?" over a news story's first line).
        localOpener = null
        this.config = config
        val resume = config.resume
        _state.value = TalkUiState(phase = TalkPhase.CONNECTING,
            turns = resume?.turns.orEmpty(), resumedTurnCount = resume?.turns?.size ?: 0)
        coachOn = CoachMode.resolve(CoachMode.choice(appContext), config.level.code)
        tutorThisCall = TutorMode.isOn(appContext)
        tutorWasOn = tutorThisCall
        sendToAnswerOn = SendToAnswer.resolve(SendToAnswer.choice(appContext), config.level.code)
        promptForTutor = null
        coachPlan = CoachPlan()
        coachSteerSent = ""
        coachSituation = null
        coachRegister = registerFor(config.cast?.person, inScene = config.scenarioId != null)
        config.scenarioId?.let { id ->
            viewModelScope.launch {
                val scenario = runCatching {
                    com.roro.futurevoice.data.ScenarioStore.shared(appContext)
                        .load(config.targetLanguage).firstOrNull { it.id == id }
                }.getOrNull()
                val person = config.cast?.person ?: scenario?.counterpartId?.let { pid ->
                    runCatching {
                        com.roro.futurevoice.data.CounterpartStore.shared(appContext).load().firstOrNull { it.id == pid }
                    }.getOrNull()
                }
                coachRegister = registerFor(person, inScene = scenario != null)
                coachSituation = scenario?.let { sc ->
                    val role = sc.role.trim()
                    val place = if (role.isEmpty()) sc.environment else "${sc.environment} — talking with $role"
                    // The learner's own side, where the starter says it (iOS
                    // 43810e21): "Meeting someone new" answers with a self-
                    // introduction and asks it back.
                    com.roro.futurevoice.data.StarterSituation.of(sc)?.learnerSide
                        ?.let { "$place. $it" } ?: place
                }
            }
        }
        loadGrammarFocus(config)
        // A resumed talk is the SAME session: same id (the meter, the book,
        // the cards all hang off it), same start.
        sessionId = resume?.id ?: StoreJson.newId()
        startedAt = resume?.startedAt ?: System.currentTimeMillis()
        // DEBUG only: a staged wall in place of a real call (see DebugBilling).
        com.roro.futurevoice.data.DebugBilling.consumeCallWall()?.let { staged ->
            startStagedWall(staged); return
        }
        // The meter runs on BOTH paths; on the realtime one the gateway does
        // the charging and this only writes the day's seconds down.
        meter.isBillable = { isBillableMoment() }
        meter.serverMetered = REALTIME
        if (REALTIME) {
            meter.start(sessionId = sessionId, language = config.targetLanguage)
            startRealtime(config)
            return
        }

        // Metering starts with the call, not with the first turn. Silence isn't
        // billed — see `isBillableMoment`; set before start(), the ticker polls
        // it from its first second.
        meter.onWallHit = { wall -> hitWall(wall) }
        meter.start(sessionId = sessionId, language = config.targetLanguage)
        lastActivityAt = System.currentTimeMillis()   // the call starts occupied
        startIdleWatch()

        callJob = viewModelScope.launch {
            try {
                // What past sessions taught rides into this one — the same
                // recurring patterns and weak areas iOS injects
                // (ConversationView.conversationSystemPrompt). Built here, not
                // in the caller: the profile read is a disk hop.
                val profile = ProfileStore.shared(appContext)
                    .load(config.targetLanguage, config.level.code)
                val brief = scenarioBrief(config)
                val clock = pinPromptClock(config)
                // Drawn with the clock, once per call (iOS `FreeTalkCue.random`).
                val freeTalkCue = ConversationPrompt.FreeTalkCue.random(hasRecentNews =
                    config.persona?.currentNotes()?.any { it.kind == PersonaNote.Kind.NOW } ?: false)
                val build = { tutor: Boolean ->
                    ConversationEngine.conversationSystemPrompt(
                        targetLanguage = config.targetLanguage,
                        nativeLanguage = config.nativeLanguage,
                        level = config.level,
                        topPatterns = profile.recurringMistakes,
                        weakVocabAreas = profile.weakVocabAreas,
                        topic = config.composedTopic,
                        persona = config.persona,
                        newsFacts = config.newsFacts,
                        counterpart = config.cast?.person,
                        brief = brief,
                        clock = clock,
                        tutor = tutor,
                        freeTalkCue = freeTalkCue,
                    ) + ConversationEngine.turnOutputInstruction(config.targetLanguage, config.nativeLanguage,
                        counterpart = config.cast?.person, inScene = config.scenarioId != null)
                }
                promptForTutor = build
                systemPrompt = build(tutorThisCall)
                if (BuildConfig.DEBUG) Log.d(TAG, "prompt: patterns=${profile.recurringMistakes.size}" +
                    " weak=${profile.weakVocabAreas} first='${profile.recurringMistakes.firstOrNull()?.mistake}'")
                // Continue from the loaded transcript: open the mic so the
                // learner picks up where they left off (the model already has
                // the prior turns as context).
                if (config.resume != null) beginListening() else openConversation()
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    fun end() {
        if (_state.value.phase == TalkPhase.ENDED || _state.value.phase == TalkPhase.IDLE) return
        endRequested = true
        // The gateway holds the mic and the sockets; putting the call down
        // has to reach it, or the room keeps streaming.
        if (REALTIME) {
            realtime.hangUp(); flushRealtimeReply()
            CallControls.handler = null
            CallForegroundService.stop(appContext)
        }
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel(); endpointJob = null
        callJob?.cancel(); callJob = null
        focusJob?.cancel(); focusJob = null
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        logCoach()
        _state.update { it.copy(phase = TalkPhase.ENDED, partial = "", coachHint = null, coachReply = null) }
        persist()
    }

    /**
     * Every way a call stops lands here once: End, a wall, a failure. Saved
     * only if the LEARNER actually said something (iOS gates its save on
     * `turns.contains { $0.role == .user }`) — an opener nobody answered is
     * not a talk, and saving one would mint an empty book and a summary with
     * nothing to read.
     */
    /** Hang up and keep nothing — "Close without saving". */
    fun discard() {
        discardOnEnd = true
        end()
    }

    private fun persist() {
        if (discardOnEnd) return
        val cfg = config ?: return
        val turns = _state.value.turns
        if (turns.none { it.role == TurnRole.USER }) return
        // Uppercased like every other id: iOS encodes a Swift UUID uppercase,
        // and a backup crossing platforms should not differ by case alone.
        val userId = auth.userId?.uppercase() ?: return
        val session = Session(
            id = sessionId,
            userId = userId,
            targetLanguage = cfg.targetLanguage,
            topic = cfg.topic.takeIf { it.isNotBlank() },
            startedAt = startedAt,
            endedAt = System.currentTimeMillis(),
            turns = turns,
            origin = cfg.resume?.let { r ->
                // A resumed talk keeps its badge (iOS `s.origin ?? (topic ? .news : .free)`).
                r.origin ?: if (r.topic.isNullOrEmpty()) SessionOrigin.FREE else SessionOrigin.NEWS
            } ?: when {
                cfg.scenarioId != null -> SessionOrigin.SCENARIO
                cfg.newsFacts.isNotEmpty() -> SessionOrigin.NEWS
                cfg.topic.isBlank() -> SessionOrigin.FREE
                else -> null
            },
            originScenarioId = cfg.scenarioId,
            counterpartId = cfg.counterpartId,
            // Only a call the learner spoke in says anything about the focus;
            // a silent one must not count as a clean call.
            grammarFocus = if (learnerSpokeThisCall)
                _state.value.grammarFocus?.record(_state.value.focusRepeatTurns.size) else null,
            // Tutor mode on at any point makes the whole call practice (iOS
            // `tutorWasOn || tutorThisCall`); coach mode is judged per line
            // (`Turn.readFromCoach`). A resumed practice call stays one (below).
            coached = if (tutorWasOn || tutorThisCall) true else null,
        )
        // Saved from the app scope on purpose: the ViewModel may be cleared
        // (screen left) before a viewModelScope job gets to run. The summary
        // follows on the same scope and writes onto the same row.
        _state.update { it.copy(endedSessionId = session.id) }
        com.roro.futurevoice.core.Analytics.capture("conversation_ended", mapOf(
            "turns" to turns.count { it.role == TurnRole.USER },
            "seconds" to ((session.endedAt ?: startedAt) - startedAt) / 1000))
        CoroutineScope(Dispatchers.Main).launch {
            // A resumed practice call stays one: its earlier half was coached
            // (iOS `prior?.isPractice`). The row on file under this id is the
            // talk before this sitting.
            val prior = runCatching { sessions.load(cfg.targetLanguage).firstOrNull { it.id == session.id } }.getOrNull()
            val saved = if (prior?.isPractice == true) session.copy(coached = true) else session
            // The draft goes down with no summary (that is what marks the row
            // "needs analysis"), but a resumed talk's previous analysis is
            // handed to the summarizer so it MERGES with it instead of losing
            // it (iOS `toAnalyze.summary = priorSummary`).
            runCatching { sessions.save(saved) }
            StoreEvents.bump()
            SessionSummarizer.summarizeInBackground(appContext, saved, cfg.nativeLanguage, cfg.level,
                priorSummary = prior?.summary)
        }
    }

    // ------------------------------------------------------------------
    // Realtime path

    /** iOS `pinPromptClock`: read once per call, from every language's talks. */
    private suspend fun pinPromptClock(config: TalkConfig): PromptClock = withContext(Dispatchers.IO) {
        val store = com.roro.futurevoice.data.SessionStore.shared(appContext)
        val langs = (com.roro.futurevoice.data.LanguageScope.enrolled(appContext) + config.targetLanguage).distinct()
        val sessions = langs.flatMap { runCatching { store.load(it) }.getOrDefault(emptyList()) }
        // A resumed talk's saved lines are from whenever it paused, so the
        // prompt says how long ago — otherwise a talk from last week is
        // continued as if it never stopped.
        PromptClock.make(sessions = sessions, excluding = sessionId,
            resumedFrom = config.resume?.turns?.lastOrNull()?.timestamp)
    }

    private fun startRealtime(config: TalkConfig) {
        lastActivityAt = System.currentTimeMillis()
        // Nobody-there watch on THIS path too (iOS `f41d045`): it was only
        // armed by the per-turn path, so a quiet realtime call kept the mic
        // open until the gateway's 3-minute drop, which ends the call instead
        // of pausing it.
        startIdleWatch()
        com.roro.futurevoice.core.Analytics.capture("conversation_started", mapOf(
            "origin" to when { config.scenarioId != null -> "scenario"; config.newsFacts.isNotEmpty() -> "news"; config.cast != null -> "person"; else -> "free" },
            "language" to config.targetLanguage, "realtime" to true, "resumed" to (config.resume != null)))
        val freeTalk = config.topic.isBlank() && config.cast == null && config.scenarioId == null
        callJob = viewModelScope.launch {
            try {
                val profile = ProfileStore.shared(appContext)
                    .load(config.targetLanguage, config.level.code)
                // The same prompt the classic path builds, minus the JSON
                // packaging: on this path the reply is PROSE Gemini Live
                // speaks, and the correction is a separate, later request.
                val brief = scenarioBrief(config)
                val clock = pinPromptClock(config)
                // Drawn with the clock, once per call (iOS `FreeTalkCue.random`).
                val freeTalkCue = ConversationPrompt.FreeTalkCue.random(hasRecentNews =
                    config.persona?.currentNotes()?.any { it.kind == PersonaNote.Kind.NOW } ?: false)
                val build = { tutor: Boolean ->
                    ConversationEngine.conversationSystemPrompt(
                        targetLanguage = config.targetLanguage,
                        nativeLanguage = config.nativeLanguage,
                        level = config.level,
                        topPatterns = profile.recurringMistakes,
                        weakVocabAreas = profile.weakVocabAreas,
                        topic = config.composedTopic,
                        persona = config.persona,
                        // Free talk only: a scenario casts the model as the
                        // barista and a Find-people call as a stranger; neither
                        // can run an introduction without breaking what it was
                        // launched as.
                        firstMeeting = freeTalk && config.persona?.metAt == null,
                        newsFacts = config.newsFacts,
                        counterpart = config.cast?.person,
                        brief = brief,
                        clock = clock,
                        tutor = tutor,
                        freeTalkCue = freeTalkCue,
                    ) + ConversationPrompt.REALTIME_STYLE_RULES
                }
                promptForTutor = build
                realtimeSystem = build(tutorThisCall)
                // A resumed talk carries its history so the fluent self knows
                // what was already said, and opens on the learner's mic — no
                // opener, no "you go first".
                if (config.resume != null) {
                    connectRealtime(config, null, historyOf(_state.value.turns))
                    return@launch
                }
                // A ready-made situation the LEARNER opens (asking a stranger
                // the way, iOS `5b0587a`): the other side waits to be spoken
                // to, and the coach's own slot above the pill offers a first
                // line — shown whatever coach mode says, since without it the
                // call is a silence nobody explained. The first reply clears
                // it like any suggestion.
                if (config.initialOpener.isBlank()) {
                    val starter = config.scenarioId?.let { id ->
                        runCatching {
                            com.roro.futurevoice.data.ScenarioStore.shared(appContext)
                                .load(config.targetLanguage).firstOrNull { it.id == id }
                        }.getOrNull()
                    }.let { com.roro.futurevoice.data.StarterSituation.of(it) }
                    val say = starter?.learnerFirstLine(config.targetLanguage)
                    if (starter != null && say != null) {
                        val chrome = com.roro.futurevoice.core.UILanguage.localized(appContext)
                        val meaning = if (LanguageCatalog.sameLanguage(config.targetLanguage, config.nativeLanguage)) ""
                            else starter.learnerFirstMeaning?.let { chrome.getString(it) }.orEmpty()
                        _state.update { it.copy(coachReply = CoachReply(
                            say = say, meaning = meaning, turnId = StoreJson.newId(),
                            heading = chrome.getString(com.roro.futurevoice.R.string.you_go_first))) }
                        connectRealtime(config, null, emptyList())
                        return@launch
                    }
                }
                // The first line, spoken by the fluent self before the learner
                // says anything — spoken BY THE GATEWAY, not the app: two
                // audio engines fighting over one session is how a call goes
                // silent. Canned pools and voicemails arrive as initialOpener;
                // otherwise one request writes it, as the classic path did.
                val opener = config.initialOpener.ifBlank {
                    // A free talk opens on a bundled line, never on a request:
                    // the INTRO line before the two have met (it introduces
                    // itself first), then a friend's hello for the time of
                    // day (iOS `a9a80ed7`).
                    if (freeTalk) {
                        if (config.persona?.metAt == null) FreeTalkOpeners.introOpener(config.targetLanguage)
                        else FreeTalkOpeners.pickUpOpener(config.targetLanguage)
                    } else config.scenarioId?.let { id ->
                        // A scenario with a stored pool (a ready-made
                        // situation's written greetings, or an iOS-made
                        // pool): rotate it — instant, no request (iOS
                        // `nextScenarioOpener`).
                        runCatching {
                            com.roro.futurevoice.data.ScenarioStore.shared(appContext)
                                .nextOpener(id, config.targetLanguage)
                        }.getOrNull()
                    } ?: runCatching {
                        GeminiClient(auth).sendJson(
                            system = realtimeSystem + ConversationEngine.turnOutputInstruction(
                                config.targetLanguage, config.nativeLanguage, counterpart = config.cast?.person,
                                inScene = config.scenarioId != null),
                            messages = listOf(GeminiClient.Message(
                                GeminiClient.Message.Role.USER,
                                "(the call just connected — say your opening line, nothing else)")),
                            serializer = ConversationTurnPayload.serializer(),
                            maxTokens = 512, purpose = "turn",
                            idempotencyKey = "open:${UUID.randomUUID()}",
                        ).reply
                    }.getOrDefault("")
                }
                // The greeting is played from the phone when it is already
                // there. The Talk tab synthesized every opener into the phrase
                // cache when it opened, and asking the gateway to say a line
                // the phone is holding costs a whole ElevenLabs round trip
                // before the first word (iOS `26a246c`).
                //
                // The text still goes up — as HISTORY, so the gateway records
                // what was said and stays silent. No protocol change: a miss
                // is a null and the gateway speaks it exactly as before.
                // A stranger's opener must be the voice the gateway will
                // answer in — never a take cached before their slot got a
                // native voice (iOS `b49e91b`).
                val cached = opener.takeIf { it.isNotBlank() }?.let {
                    com.roro.futurevoice.data.PhraseAudioStore.shared(appContext)
                        .data(it, activeVoiceId, allowLineage = !VoicePreset.isRevoiced(
                            activeVoiceId, config.targetLanguage))
                }
                // NOT appended here on the gateway path: it speaks the opener
                // as a reply with its own context, and audio_start/reply_delta
                // create the turn — appending it locally too printed it twice.
                if (cached != null) {
                    localOpener = opener to cached
                    connectRealtime(config, null, listOf("model" to opener))
                } else {
                    connectRealtime(config, opener, emptyList())
                }
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    /**
     * Put a dropped call back together: same voice, the talk so far as
     * history, no opener. Everything said is already on screen and stays
     * there — a reconnect carries the whole talk.
     */
    fun reconnect() {
        if (!REALTIME || endRequested) return
        _state.update { it.copy(dropped = null, error = null) }
        resumeRealtime()
    }

    private fun resumeRealtime() {
        val cfg = config ?: return
        // A reconnect must not inherit a clock that already ran out.
        lastActivityAt = System.currentTimeMillis()
        startIdleWatch()
        _state.update { it.copy(phase = TalkPhase.CONNECTING, pausedForIdle = false, wall = null) }
        viewModelScope.launch { connectRealtime(cfg, null, historyOf(_state.value.turns)) }
    }

    /** The talk so far as the gateway's history (iOS `history:`). */
    private fun historyOf(turns: List<Turn>): List<Pair<String, String>> =
        turns.map { (if (it.role == TurnRole.USER) "user" else "model") to it.transcript }

    /** Something said since the last save — what closing would lose (iOS
     *  `turns.contains(user) && !didSaveCurrentSession`). */
    val hasUnsavedTalk: Boolean
        get() = _state.value.let { st ->
            st.phase != TalkPhase.ENDED && st.turns.size > st.resumedTurnCount &&
                st.turns.any { it.role == TurnRole.USER }
        }

    private fun callTitle(cfg: TalkConfig): String =
        cfg.cast?.name ?: cfg.topic.ifBlank { appContext.getString(com.roro.futurevoice.R.string.talk) }

    private fun updateCallNotification(cfg: TalkConfig, phase: TalkPhase) {
        // A state change that lands AFTER the call ended (a late socket
        // event, the opener's finally block) must not bring the "in a call"
        // foreground notification back — it outlived the call on device.
        val now = _state.value.phase
        if (now == TalkPhase.ENDED || now == TalkPhase.IDLE) return
        val hint = appContext.getString(when (phase) {
            TalkPhase.PAUSED -> com.roro.futurevoice.R.string.paused
            TalkPhase.SPEAKING -> com.roro.futurevoice.R.string.speaking
            TalkPhase.THINKING -> com.roro.futurevoice.R.string.thinking
            TalkPhase.CONNECTING -> com.roro.futurevoice.R.string.connecting
            else -> com.roro.futurevoice.R.string.listening
        })
        CallForegroundService.start(appContext, callTitle(cfg), hint, phase == TalkPhase.PAUSED)
    }

    private suspend fun connectRealtime(cfg: TalkConfig, opener: String?, history: List<Pair<String, String>>) {
        wireRealtime(cfg)
        CallControls.handler = { a ->
            when (a) {
                CallControls.Action.TOGGLE_PAUSE -> togglePause()
                CallControls.Action.END -> end()
            }
        }
        updateCallNotification(cfg, TalkPhase.CONNECTING)
        // A fresh gateway session holds no steer — send it again.
        coachSteerSent = ""
        val token = auth.accessToken()
        // A cast (Find people) speaks in its preset voice; the fluent self in
        // the learner's own clone. Ownership is enforced by the gateway.
        realtime.connect(
            token = token,
            // A preset slot speaks in the target language's own voice.
            voiceId = VoicePreset.speaking(cfg.castVoiceId ?: cfg.voiceId, cfg.targetLanguage),
            language = cfg.targetLanguage,
            system = realtimeSystem,
            opener = opener,
            history = history,
            native = cfg.nativeLanguage,
            manualTurns = sendToAnswerOn,
        )
        syncCoachSteer()
    }

    private fun wireRealtime(cfg: TalkConfig) {
        realtime.onState = { st ->
            val phase = when (st) {
                RealtimeTalkClient.State.CONNECTING -> TalkPhase.CONNECTING
                RealtimeTalkClient.State.LISTENING, RealtimeTalkClient.State.HEARING -> TalkPhase.LISTENING
                RealtimeTalkClient.State.THINKING -> TalkPhase.THINKING
                RealtimeTalkClient.State.SPEAKING -> TalkPhase.SPEAKING
                RealtimeTalkClient.State.IDLE, RealtimeTalkClient.State.FAILED -> null
            }
            if (st == RealtimeTalkClient.State.LISTENING) speakLocalOpener()
            if (st == RealtimeTalkClient.State.HEARING) markLearnerSpoke()
            val over = _state.value.phase == TalkPhase.ENDED || _state.value.phase == TalkPhase.IDLE
            if (phase != null && !over) {
                lastActivityAt = System.currentTimeMillis()
                _state.update { it.copy(phase = phase, level = realtime.level) }
                updateCallNotification(cfg, phase)
            }
        }
        realtime.onPartial = { text ->
            // An empty partial is also the gateway's "nothing to send".
            _state.update { it.copy(partial = text, level = realtime.level,
                sendPending = it.sendPending && text.isNotEmpty()) }
        }
        realtime.onUserTurn = turn@{ said, wav, ms, fluency, flags ->
            markLearnerSpoke()
            sendPendingJob?.cancel()
            _state.update { it.copy(sendPending = false) }
            // The rest of a turn the gateway re-opened after cutting the
            // learner off (iOS 2026-10-08): it joins the bubble it belongs to
            // — one turn, one take, one correction.
            val last = _state.value.turns.lastOrNull { it.role == TurnRole.USER }
            if (flags.continues && last != null) {
                val joined = last.transcript + (if (com.roro.futurevoice.data.WordSplitter.spaced(cfg.targetLanguage)) " " else "") + said
                val audio = wav?.let { keepTurnAudio(it) } ?: last.audioURL
                _state.update { st ->
                    st.copy(partial = "", turns = st.turns.map {
                        if (it.id == last.id) it.copy(transcript = joined, durationMs = ms,
                            fluency = fluency, audioURL = audio, suggestion = null) else it
                    })
                }
                if (!flags.native) requestRealtimeSuggestion(last.id, joined, cfg)
                return@turn
            }
            // Measured off the take (iOS 55088c28): realtime turns used to
            // carry no fluency, so articulation rate read 0 for every call.
            val turn = Turn(role = TurnRole.USER, transcript = said, durationMs = ms,
                audioURL = wav?.let { keepTurnAudio(it) }, fluency = fluency,
                coachLine = shownCoachLine())
            _state.update { it.copy(turns = it.turns + turn, partial = "") }
            // The learner's first words open the steer (nothing before them).
            viewModelScope.launch { syncCoachSteer() }
            // A line said in their own language was answered with the target
            // way to say it; a correction would be built on the wrong language.
            if (!flags.native) requestRealtimeSuggestion(turn.id, said, cfg)
        }
        realtime.onReplyAudio = { ctx, pcm, rate ->
            realtimeReplyTurns[ctx]?.let { id ->
                writeWav(pcm, rate, id)?.let { wav ->
                    _state.update { st ->
                        st.copy(turns = st.turns.map { if (it.id == id) it.copy(audioURL = wav) else it })
                    }
                }
            }
        }
        realtime.onReplyBegan = { ctx ->
            val turn = Turn(role = TurnRole.FLUENT_SELF, transcript = "")
            realtimeReplyTurns[ctx] = turn.id
            // The hint and the suggestion belonged to the line just answered:
            // hidden, not removed (see `coachStale`).
            _state.update {
                it.copy(turns = it.turns + turn,
                    coachStale = it.coachStale || it.coachHint != null || it.coachReply != null)
            }
        }
        realtime.onReplyEnded = { ctx, full ->
            realtimeReplyTurns[ctx]?.let { id ->
                viewModelScope.launch {
                    // The whole line: the bubble may still be revealing its
                    // last sentences while the voice drains (iOS 1c25820d).
                    val text = full.ifEmpty {
                        _state.value.turns.firstOrNull { it.id == id }?.transcript.orEmpty()
                    }
                    advanceCoach(text, id)
                }
            }
        }
        realtime.onReplyDelta = { ctx, delta ->
            val id = realtimeReplyTurns[ctx]
            if (id != null) _state.update { st ->
                st.copy(turns = st.turns.map { t ->
                    if (t.id != id) t
                    // A NUL-prefixed delta is the authoritative full text.
                    else if (delta.startsWith("\u0000")) t.copy(transcript = delta.drop(1))
                    else t.copy(transcript = t.transcript + delta)
                })
            }
        }
        realtime.onReplyCutIn = { ctx ->
            realtimeReplyTurns[ctx]?.let { id ->
                _state.update { st ->
                    st.copy(turns = st.turns.map { if (it.id == id) it.copy(talkedOver = true) else it })
                }
            }
        }
        realtime.onInterrupted = { _ -> lastActivityAt = System.currentTimeMillis() }
        realtime.onReplyWithdrawn = { ctx ->
            lastActivityAt = System.currentTimeMillis()
            realtimeReplyTurns.remove(ctx)?.let { id ->
                _state.update { st -> st.copy(turns = st.turns.filter { it.id != id }) }
            }
        }
        realtime.onWall = { code ->
            val kind = when (code) {
                "daily_cap_reached" -> TalkWall.ALLOWANCE_SPENT
                "fair_use_limit" -> TalkWall.FAIR_USE
                else -> TalkWall.OUT_OF_MINUTES
            }
            handleWall(kind)
        }
        realtime.onFailed = { message ->
            when {
                // A wall already ended the call with its own sheet.
                realtime.wallCode != null -> Unit
                // Nobody talked and the gateway put the call down. That is a
                // PAUSE, not an end: ending has consequences (a summary, a
                // book), pausing has none — the transcript stays and one tap
                // reconnects with the history. Same rule as the classic path's
                // idle watchdog.
                realtime.lastErrorCode == "idle" -> {
                    flushRealtimeReply()
                    _state.update { it.copy(phase = TalkPhase.PAUSED, pausedForIdle = true,
                        partial = "", level = 0f) }
                }
                // A transport drop: the gateway's Durable Object can be reset
                // under a live call (a deploy, or Cloudflare moving the
                // object), and a reconnect carries the whole talk. So the
                // call puts itself back together without asking, at most once
                // a minute — a second drop inside that is no longer a blip,
                // and gets the question instead.
                realtime.lastErrorCode == "socket" && !endRequested &&
                    System.currentTimeMillis() - lastAutoReconnectAt > AUTO_RECONNECT_SPACING_MS -> {
                    lastAutoReconnectAt = System.currentTimeMillis()
                    com.roro.futurevoice.core.Telemetry.log("talk_rt_reconnect",
                        mapOf("turns" to _state.value.turns.size.toString(), "auto" to "1"))
                    reconnect()
                }
                realtime.lastErrorCode == "socket" && !endRequested -> {
                    flushRealtimeReply()
                    _state.update { it.copy(dropped = message, partial = "", level = 0f) }
                }
                // Anything else is a failure the learner can retry from.
                else -> {
                    _state.update { it.copy(phase = TalkPhase.ENDED, error = message, partial = "") }
                    persist()
                }
            }
        }
    }

    /**
     * The pool ran out mid-call. If the learner SPOKE, the call wraps itself
     * up — draft saved, summary run, book made — instead of raising an alert
     * and waiting for an End nobody presses.
     *
     * Reported 2026-09-17 on iOS: a 42-turn first call hit the wall, the app
     * asked for End, the learner never pressed it, and the whole talk was
     * gone when they closed the app — no summary, no book, and no plans
     * offered, because the pitch hangs off the summary's Done. A wall with no
     * learner turn behind it keeps the old alert: there is nothing to wrap up.
     */
    private fun handleWall(kind: TalkWall) {
        val spoke = _state.value.turns.any { it.role == TurnRole.USER }
        if (kind != TalkWall.OUT_OF_MINUTES) {
            // A SUBSCRIBER's spent pool is its own sheet and fair use its own
            // alert — and neither wraps the call up (iOS `dailyCapReached` /
            // `fairUseHalted`): the gateway has hung up, the transcript stays,
            // and End is what summarizes. Only the free pool's wall puts the
            // call down by itself.
            stopForWall()
            _state.update { it.copy(wall = kind, phase = TalkPhase.PAUSED, pausedForIdle = false,
                partial = "", level = 0f) }
            if (!stagedCall) config?.let { updateCallNotification(it, TalkPhase.PAUSED) }
            return
        }
        if (!spoke) {
            // Nothing was said, so nothing to wrap up — the plans are the
            // honest answer and the call screen leaves with them.
            com.roro.futurevoice.core.Telemetry.log("talk_wall_before_speaking",
                mapOf("turns" to _state.value.turns.size.toString()))
            _state.update { it.copy(wall = kind, wallBeforeSpeaking = true, partial = "") }
            end()
            return
        }
        com.roro.futurevoice.core.Telemetry.log("talk_free_call_spent",
            mapOf("turns" to _state.value.turns.size.toString()))
        _state.update { it.copy(wall = kind, partial = "") }
        end()
    }

    /** Everything a wall stops without ending the talk (iOS `onWallHit`). */
    private fun stopForWall() {
        if (REALTIME) { realtime.hangUp(); flushRealtimeReply() }
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel(); endpointJob = null
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
    }

    /**
     * DEBUG only: two staged lines (or one, for a wall before the learner
     * speaks), then the wall the gateway would have sent — through the same
     * [handleWall]. No gateway, no mic, no meter; never saved or summarized.
     */
    private fun startStagedWall(staged: com.roro.futurevoice.data.DebugBilling.CallWall) {
        if (!BuildConfig.DEBUG) return
        discardOnEnd = true
        stagedCall = true
        val lines = buildList {
            add(Turn(role = TurnRole.FLUENT_SELF, transcript = "Hey, it's you. How was your day?"))
            if (staged.learnerSpoke) add(Turn(role = TurnRole.USER, transcript = "Pretty good, I went to the park."))
        }
        _state.update { it.copy(phase = TalkPhase.LISTENING, turns = lines) }
        viewModelScope.launch {
            kotlinx.coroutines.delay(staged.afterSeconds * 1000L)
            handleWall(when (staged.code) {
                "daily_cap_reached" -> TalkWall.ALLOWANCE_SPENT
                "fair_use_limit" -> TalkWall.FAIR_USE
                else -> TalkWall.OUT_OF_MINUTES
            })
            // The board needs a subject: stand in for the save the staged call skips.
            if (_state.value.phase == TalkPhase.ENDED && staged.learnerSpoke &&
                staged.code == "insufficient_credits") {
                SessionSummarizer.stageBoard(sessionId)
                _state.update { it.copy(endedSessionId = sessionId) }
            }
        }
    }

    /** The reply still in flight when the call was put down — without this
     *  the closing line is the one Replay silently skips. */
    private fun flushRealtimeReply() {
        val (pcm, rate) = realtime.takeReplyAudio()
        if (pcm.isEmpty()) return
        val id = realtimeReplyTurns.values.lastOrNull() ?: return
        val wav = writeWav(pcm, rate, id) ?: return
        _state.update { st ->
            st.copy(turns = st.turns.map { if (it.id == id) it.copy(audioURL = wav) else it })
        }
    }

    /**
     * The correction card, on its own clock. On this path the reply is prose
     * and the correction is a separate, later request — the voice is already
     * playing by the time this fires, so nothing the learner hears ever waits
     * on coaching. Lines under three words are not worth a request.
     */
    private fun correctionErrorKind(e: Exception): String = when (e) {
        is com.roro.futurevoice.net.EdgeError.Truncated -> "truncated"
        is kotlinx.serialization.SerializationException -> "malformed_json"
        is com.roro.futurevoice.net.EdgeError.JsonNotFound -> "json_not_found"
        is com.roro.futurevoice.net.EdgeError.Http -> "http_${e.status}"
        is kotlinx.coroutines.CancellationException -> "cancelled"
        is java.io.IOException -> "io_${e.javaClass.simpleName}"
        else -> e.toString().take(60)
    }

    private fun requestRealtimeSuggestion(turnId: String, said: String, cfg: TalkConfig) {
        // Never count words on " ": Japanese writes none, so every turn
        // measured one word and no Japanese line was ever corrected.
        if (com.roro.futurevoice.data.WordSplitter.count(said, cfg.targetLanguage) < 3) return
        // The line said TO them, so the rewrite is natural in THIS
        // conversation — the whole turn is re-said now, and a turn only reads
        // right against what it answers. Context only; the prompt forbids
        // correcting it (iOS `requestRealtimeSuggestion`).
        val heard = _state.value.turns.lastOrNull { it.role == TurnRole.FLUENT_SELF }
            ?.transcript?.trim().orEmpty()
        val content = if (heard.isEmpty()) "They said: \"$said\""
            else "They were just told: \"$heard\"\nThey said: \"$said\""
        viewModelScope.launch {
            val payload = try {
                GeminiClient(auth).sendJson(
                    system = CorrectionOnlyPrompt.build(cfg.targetLanguage, cfg.nativeLanguage, cfg.level,
                        relationshipLine = ConversationCharacter.relationshipRegisterLine(
                            cfg.targetLanguage, cfg.cast),
                        politeLine = ConversationCharacter.politeSettingLine(
                            cfg.targetLanguage, cfg.cast?.person, inScene = cfg.scenarioId != null)),
                    messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, content)),
                    serializer = ConversationTurnPayload.serializer(),
                    // Headroom, not a length: thinking spends from the same
                    // ceiling, and a long turn's whole rewrite plus its fixes
                    // was cut off at 900 — a truncation loses the WHOLE
                    // correction, and Say it again then reads the turn raw.
                    maxTokens = 2048, purpose = "turn",
                    idempotencyKey = "rt-suggest:$turnId",
                    fastThinking = CorrectionThinking.fast(cfg.targetLanguage),
                )
            } catch (e: Exception) {
                // Was invisible until 2026-10-06 (iOS). One row per failed
                // turn; `words` says whether it is the long turns that fail.
                com.roro.futurevoice.core.Telemetry.log("talk_correction_failed", mapOf(
                    "error" to correctionErrorKind(e),
                    "words" to com.roro.futurevoice.data.WordSplitter.count(said, cfg.targetLanguage).toString(),
                ))
                if (e is kotlinx.coroutines.CancellationException) throw e
                null
            } ?: return@launch
            // A turn since joined with its continuation is corrected as the
            // whole line, not as its first half (iOS `transcript == said`).
            if (_state.value.turns.firstOrNull { it.id == turnId }?.transcript != said) return@launch
            attachSuggestion(turnId, payload)
        }
    }

    /**
     * Say the cached greeting from the phone, the moment the call is up.
     *
     * The mic is HELD while it plays: the gateway gates its own echo because
     * it knows when it is speaking, and a line the app plays itself is
     * invisible to it — without the hold the fluent self's own voice comes
     * back as the learner's first turn.
     */
    private fun speakLocalOpener() {
        val (text, audio) = localOpener ?: return
        localOpener = null
        val turn = Turn(role = TurnRole.FLUENT_SELF, transcript = text)
        _state.update { it.copy(phase = TalkPhase.SPEAKING, turns = it.turns + turn) }
        viewModelScope.launch {
            realtime.micGated = true
            try {
                mp3.volume = com.roro.futurevoice.data.AudioPrefs.talkVoiceVolume(appContext)
                mp3.play(audio)
            } catch (_: Exception) {
                // Nothing played — the learner speaks first, which the call
                // handles exactly as it does after any line.
            } finally {
                realtime.micGated = false
                lastActivityAt = System.currentTimeMillis()
                _state.update { if (it.phase == TalkPhase.ENDED || it.phase == TalkPhase.IDLE) it
                    else it.copy(phase = TalkPhase.LISTENING) }
                // The first answer of a call is the hardest one — the opener
                // gets its "try saying" like every line.
                advanceCoach(text, turn.id)
            }
        }
    }

    /** Move a captured turn's WAV into the app's own store — one copy. */
    private fun keepTurnAudio(tmp: java.io.File): String? = runCatching {
        val dir = java.io.File(appContext.filesDir, "turn-audio").apply { mkdirs() }
        val dst = java.io.File(dir, tmp.name)
        tmp.copyTo(dst, overwrite = true); tmp.delete()
        dst.absolutePath
    }.getOrNull()

    private fun writeWav(pcm: ByteArray, rate: Int, id: String): String? = runCatching {
        val dir = java.io.File(appContext.filesDir, "turn-audio").apply { mkdirs() }
        val f = java.io.File(dir, "$id.wav")
        val h = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVE".toByteArray())
            .put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(rate).putInt(rate * 2).putShort(2).putShort(16)
            .put("data".toByteArray()).putInt(pcm.size)
        f.outputStream().use { it.write(h.array()); it.write(pcm) }
        f.absolutePath
    }.getOrNull()

    /** The one tap: put the call down, or pick it back up. */
    /** Send-to-answer: the pill while it is the learner's turn (iOS
     *  `sendModeActive`). The gateway commits what was said. */
    fun sendHeldTurn() {
        if (!sendToAnswerOn || _state.value.sendPending || _state.value.partial.isBlank()) return
        _state.update { it.copy(sendPending = true) }
        realtime.sendTurn()
        // Never leave the pill spinning on a gateway that answered nothing.
        sendPendingJob?.cancel()
        sendPendingJob = viewModelScope.launch {
            delay(5000)
            _state.update { it.copy(sendPending = false) }
        }
    }

    /** Send-to-answer: throw this turn away and say it again. */
    fun discardTurn() {
        sendPendingJob?.cancel()
        _state.update { it.copy(sendPending = false, partial = "") }
        realtime.discardTurn()
    }

    /** Send-to-answer flipped in the call settings (iOS `onChange(of:
     *  sendToAnswer)`): reaches a live call at once. */
    fun setSendToAnswer(on: Boolean) {
        if (on == sendToAnswerOn) return
        sendToAnswerOn = on
        if (!on) { sendPendingJob?.cancel(); _state.update { it.copy(sendPending = false) } }
        val phase = _state.value.phase
        if (REALTIME && phase != TalkPhase.IDLE && phase != TalkPhase.ENDED && phase != TalkPhase.PAUSED) {
            realtime.setManualTurns(on)
        }
    }

    fun togglePause() {
        if (REALTIME) {
            // Pausing IS hanging up on this path; resuming reconnects with
            // the history so the fluent self knows what was already said.
            when (_state.value.phase) {
                TalkPhase.PAUSED -> resumeRealtime()
                TalkPhase.LISTENING, TalkPhase.THINKING, TalkPhase.SPEAKING -> {
                    realtime.hangUp(); flushRealtimeReply()
                    _state.update { it.copy(phase = TalkPhase.PAUSED, partial = "", level = 0f) }
                    config?.let { updateCallNotification(it, TalkPhase.PAUSED) }
                }
                else -> Unit
            }
            return
        }
        when (_state.value.phase) {
            TalkPhase.PAUSED -> resume()
            TalkPhase.LISTENING, TalkPhase.THINKING, TalkPhase.SPEAKING -> pauseCall(forIdle = false)
            else -> Unit
        }
    }

    /**
     * Put the call DOWN — not away. The mic closes and the meter goes quiet,
     * but the transcript stays and [resume] picks the same session up where
     * it stopped. Nothing is saved or summarized here; only [end] does that.
     * Every "stop" lands here: the tap and the idle watchdog.
     */
    private fun pauseCall(forIdle: Boolean) {
        cancelIdleWatch()
        if (REALTIME) {
            // Pausing IS hanging up on this path — the same as the pill tap;
            // resuming reconnects with the turns so far as history.
            realtime.hangUp(); flushRealtimeReply()
            _state.update { it.copy(phase = TalkPhase.PAUSED, partial = "", level = 0f, pausedForIdle = forIdle) }
            config?.let { updateCallNotification(it, TalkPhase.PAUSED) }
            return
        }
        endpointJob?.cancel(); endpointJob = null
        // Whatever the partial held is discarded, as on iOS — a half-sentence
        // from before a pause is not something to answer later.
        runCatching { live.stop() }
        pcm.stop()
        mp3.stop()
        _state.update { it.copy(phase = TalkPhase.PAUSED, partial = "", level = 0f, pausedForIdle = forIdle) }
    }

    fun resume() {
        // The transcript tap and the lock-screen play both land here; on the
        // realtime path picking the call back up is a reconnect.
        if (REALTIME) { if (_state.value.phase == TalkPhase.PAUSED) resumeRealtime(); return }
        if (_state.value.phase != TalkPhase.PAUSED) return
        lastActivityAt = System.currentTimeMillis()   // a tap is someone being here
        _state.update { it.copy(phase = TalkPhase.LISTENING, pausedForIdle = false) }
        beginListening()
        startIdleWatch()
    }

    // MARK: - Nobody's there

    /**
     * Watch for a call with nobody in it. Not a billing rule — idle seconds
     * already cost nothing. This is about the open mic: a call the learner
     * walked away from keeps listening, and the first voice it hears — a TV,
     * someone else in the room — would be billed AND answered as the learner.
     * The predicate is the one the meter bills on, so the call pauses on
     * exactly the silence it charges nothing for (`behavior.md` §8).
     */
    private fun startIdleWatch() {
        cancelIdleWatch()
        idleWatchJob = viewModelScope.launch {
            while (true) {
                delay(IDLE_WATCH_TICK_SECONDS * 1000L)
                val phase = _state.value.phase
                if (phase == TalkPhase.ENDED || phase == TalkPhase.PAUSED) return@launch
                // NOT the billing rule: that one is zero until the learner
                // first speaks, and read here it paused the call in the
                // middle of the opener or of their first answer (iOS `366266a`).
                if (somethingIsHappening()) { lastActivityAt = System.currentTimeMillis(); continue }
                // Send-to-answer with words held: they are composing, not
                // gone — a longer wait before the call puts itself down.
                val bar = if (sendToAnswerOn && _state.value.partial.isNotBlank())
                    IDLE_PAUSE_HOLDING_SECONDS else IDLE_PAUSE_SECONDS
                if (System.currentTimeMillis() - lastActivityAt < bar * 1000L) continue
                pauseCall(forIdle = true)
                return@launch
            }
        }
    }

    private fun cancelIdleWatch() {
        idleWatchJob?.cancel(); idleWatchJob = null
    }

    override fun onCleared() {
        // The screen is gone; so is anything that could answer the notification.
        CallControls.handler = null
        CallForegroundService.stop(appContext)
        realtime.close()
        end()
        super.onCleared()
    }

    // MARK: - Call flow

    /**
     * The fluent self speaks first. The opener is GENERATED rather than canned
     * so it lands in the right language and in-scene for a scenario topic —
     * iOS pre-synthesizes its greeting in the launcher for latency, which is
     * the obvious next optimization here.
     */
    private suspend fun openConversation() {
        val cfg = config ?: return
        if (cfg.initialOpener.isNotBlank()) {
            appendFluentSelf(cfg.initialOpener)
            speak(cfg.initialOpener)
            beginListening()
            return
        }
        val opener = requestTurn(
            messages = listOf(
                GeminiClient.Message(
                    GeminiClient.Message.Role.USER,
                    "(the call just connected — say your opening line, nothing else)",
                )
            ),
            idempotencyKey = "open:${UUID.randomUUID()}",
            speakEagerly = true,
        )
        appendFluentSelf(opener.reply)
        beginListening()
    }

    private fun beginListening() {
        val cfg = config ?: return
        val phase = _state.value.phase
        if (phase == TalkPhase.PAUSED || phase == TalkPhase.ENDED) return
        didPreconnectThisTurn = false
        lastTranscriptChangeAt = null
        turnStartedAt = System.currentTimeMillis()
        _state.update { it.copy(phase = TalkPhase.LISTENING, partial = "") }
        try {
            live.start(LanguageCatalog.sttLocale(cfg.targetLanguage)) { text ->
                lastTranscriptChangeAt = System.currentTimeMillis()
                _state.update { it.copy(partial = text, level = live.level) }
            }
        } catch (e: Exception) {
            fail(e)
            return
        }
        endpointJob?.cancel()
        endpointJob = viewModelScope.launch { endpointMonitor() }
    }

    /**
     * Energy-based endpointing. Every tick: how long has the mic ACTUALLY been
     * silent (last voiced audio, not last transcript change) against the
     * text-completeness tier. See `docs/contracts/behavior.md` §2.
     */
    private suspend fun endpointMonitor() {
        while (_state.value.phase == TalkPhase.LISTENING) {
            delay((TurnTaking.ENDPOINT_TICK_SECONDS * 1000).toLong())
            if (_state.value.phase != TalkPhase.LISTENING) return

            val transcript = live.transcript
            // Never send an empty turn.
            if (transcript.isBlank()) continue
            val lastVoiced = live.lastVoicedAtMs ?: continue

            val now = System.currentTimeMillis()
            val audioSilence = (now - lastVoiced) / 1000.0
            val sinceTextChange =
                lastTranscriptChangeAt?.let { (now - it) / 1000.0 } ?: Double.MAX_VALUE

            // The user has plausibly finished — spend the rest of the VAD wait
            // warming the network path so the turn fires onto a hot connection.
            if (audioSilence >= TurnTaking.PRECONNECT_AFTER_SILENCE_SECONDS && !didPreconnectThisTurn) {
                didPreconnectThisTurn = true
                viewModelScope.launch { gemini.preconnect() }
            }

            val audioSettled = audioSilence >= TurnTaking.vadWaitSeconds(transcript) &&
                sinceTextChange >= TurnTaking.STT_SETTLE_SECONDS
            val transcriptSettled = sinceTextChange >= TurnTaking.NOISY_ROOM_FALLBACK_SECONDS
            if (!audioSettled && !transcriptSettled) continue

            // `vad_wait_ms` alone hides the worst case: on the noisy fallback the
            // energy meter never saw silence, so it logs a TINY audio gap for a
            // turn that actually sat out the 6s transcript wait.
            turnTiming = mutableMapOf(
                "vad_wait_ms" to (audioSilence * 1000).toInt().toString(),
                "vad_path" to if (audioSettled) "audio" else "noisy",
                "text_quiet_ms" to (minOf(sinceTextChange, 60.0) * 1000).toInt().toString(),
                "noise" to "%.2f".format(live.ambientNoiseLevel),
            )
            turnEndedSpeakingAt = now
            // Hand the turn to its own job: the monitor is done, and a pause
            // cancelling it must not take the in-flight reply down with it.
            callJob = viewModelScope.launch { sendTurn() }
            return
        }
    }

    private suspend fun sendTurn() {
        _state.update { it.copy(phase = TalkPhase.THINKING) }

        val finalizeStart = System.currentTimeMillis()
        val spoken = live.stop().trim()
        val fluency = live.fluencyStats()
        turnTiming["finalize_ms"] = (System.currentTimeMillis() - finalizeStart).toString()

        if (spoken.isBlank()) {
            beginListening()
            return
        }

        val userTurn = Turn(
            role = TurnRole.USER,
            transcript = spoken,
            durationMs = (System.currentTimeMillis() - turnStartedAt).toInt(),
            fluency = fluency,
            coachLine = shownCoachLine(),
        )
        _state.update { it.copy(turns = it.turns + userTurn, partial = "") }

        try {
            val payload = requestTurn(
                messages = ConversationEngine.geminiMessages(_state.value.turns),
                idempotencyKey = "turn:${userTurn.id}",
                speakEagerly = true,
            )
            attachSuggestion(userTurn.id, payload)
            appendFluentSelf(payload.reply)
            beginListening()
        } catch (e: Exception) {
            fail(e)
        }
    }

    /**
     * One structured turn. Streams first so TTS can fire on `reply`'s closing
     * quote; on a stream failure BEFORE that field, retries buffered on the SAME
     * idempotency key — one logical request, one charge.
     */
    private suspend fun requestTurn(
        messages: List<GeminiClient.Message>,
        idempotencyKey: String,
        speakEagerly: Boolean,
    ): ConversationTurnPayload {
        val geminiStart = System.currentTimeMillis()
        var speakJob: Job? = null

        val payload = try {
            gemini.sendJsonStream(
                system = systemPrompt,
                messages = messages,
                serializer = ConversationTurnPayload.serializer(),
                purpose = "turn",
                idempotencyKey = idempotencyKey,
                earlyField = "reply",
                onEarlyField = { reply ->
                    if (speakEagerly && reply.isNotBlank()) {
                        turnTiming["gemini_ms"] =
                            (System.currentTimeMillis() - geminiStart).toString()
                        // Launched, not awaited: blocking here would stall the SSE
                        // read that is still delivering the suggestion + transcript.
                        speakJob = viewModelScope.launch { speak(reply) }
                    }
                },
                fallbackFromEarly = { reply -> ConversationTurnPayload(reply = reply) },
            )
        } catch (e: EdgeError.InsufficientCredits) {
            throw e
        } catch (e: EdgeError.DailyCapReached) {
            throw e
        } catch (e: Exception) {
            gemini.sendJson(
                system = systemPrompt,
                messages = messages,
                serializer = ConversationTurnPayload.serializer(),
                purpose = "turn",
                idempotencyKey = idempotencyKey,
            )
        }

        if (speakJob == null && speakEagerly && payload.reply.isNotBlank()) {
            speak(payload.reply)
        } else {
            speakJob?.join()
        }
        turnTiming["total_ms"] =
            (System.currentTimeMillis() - turnEndedSpeakingAt).toString()
        _state.update { it.copy(lastTiming = turnTiming.toMap()) }
        return payload
    }

    /** A cast stranger speaks in their PRESET voice — never the clone. */
    private val activeVoiceId: String
        get() = config?.let { it.castVoiceId ?: it.voiceId }.orEmpty()

    private suspend fun speak(text: String) {
        val cfg = config ?: return
        val phase = _state.value.phase
        if (phase == TalkPhase.PAUSED || phase == TalkPhase.ENDED) return
        _state.update { it.copy(phase = TalkPhase.SPEAKING) }
        val firstChunkAt = longArrayOf(0L)
        val startedAt = System.currentTimeMillis()
        try {
            pcm.start()
            val result = voiceClient.synthesizeStreaming(
                voiceId = activeVoiceId,
                text = text,
                purpose = "turn",
            ) { chunk ->
                if (firstChunkAt[0] == 0L) {
                    firstChunkAt[0] = System.currentTimeMillis()
                    turnTiming["tts_first_ms"] = (firstChunkAt[0] - startedAt).toString()
                }
                pcm.write(chunk)
            }
            when (result) {
                is VoiceClient.StreamedAudio.Pcm22050 -> {
                    turnTiming["tts"] = "stream"
                    pcm.drain()
                    pcm.stop()
                }
                is VoiceClient.StreamedAudio.Mp3 -> {
                    turnTiming["tts"] = "buffered"
                    pcm.stop()
                    mp3.play(result.data)
                }
            }
        } catch (e: Exception) {
            pcm.stop()
            // A failed synthesis must not kill the call — the user still has the
            // text of the turn; the conversation keeps going.
            _state.update { it.copy(error = humanMessage(e)) }
        }
    }

    // MARK: - State helpers

    private fun appendFluentSelf(reply: String) {
        if (reply.isBlank()) return
        _state.update {
            it.copy(turns = it.turns + Turn(role = TurnRole.FLUENT_SELF, transcript = reply))
        }
    }

    /** The suggestion belongs to the USER turn it corrects, not to the reply. */
    private fun attachSuggestion(userTurnId: String, payload: ConversationTurnPayload) {
        val said = _state.value.turns.firstOrNull { it.id == userTurnId }?.transcript.orEmpty()
        // Dictation EXPANDS contractions, so a learner who said "I'm" is
        // transcribed "I am" — and a suggestion rewriting it back tells them
        // they made a mistake they did not make, in their own voice. The
        // prompt asks the model not to; this is what makes it true.
        val suggestion = payload.turnSuggestion(said, config?.targetLanguage ?: "en")
        val upgraded = payload.transcript?.takeIf { it.isNotBlank() }
        if (suggestion == null && upgraded == null) return
        _state.update { state ->
            state.copy(turns = state.turns.map { turn ->
                if (turn.id != userTurnId) turn
                else turn.copy(
                    suggestion = suggestion ?: turn.suggestion,
                    transcript = upgraded ?: turn.transcript,
                )
            })
        }
        suggestion?.let { checkFocusRepeat(it, userTurnId) }
    }

    // ------------------------------------------------------------------
    // Coach mode

    /**
     * The "try saying" on screen for the line being answered right now (iOS
     * `shownCoachLine`) — kept on the learner's turn so a line read off it
     * isn't scored (`Turn.readFromCoach`). Only while it still belongs to the
     * latest fluent-self line: a late or stale one was not what they were
     * looking at.
     */
    private fun shownCoachLine(): String? {
        val st = _state.value
        val reply = st.coachReply ?: return null
        if (!coachOn) return null
        if (reply.turnId != st.turns.lastOrNull { it.role == TurnRole.FLUENT_SELF }?.id) return null
        return reply.say
    }

    /** The call settings toggle (the learner's flip is saved by the sheet). */
    fun setCoachMode(on: Boolean) {
        if (coachOn == on) return
        coachOn = on
        if (on) config?.let { loadGrammarFocus(it) }
        else _state.update { it.copy(coachHint = null, coachReply = null, coachStale = false) }
        syncCoachSteer()
    }

    /** Tutor mode flipped in the call settings (iOS `onChange(of:
     *  tutorModeChoice)`, 88cc3b33): the prompt is rebuilt with the new
     *  setting. On the realtime path the gateway is sent it (`set.system`)
     *  and remakes its reply cache, so the next reply is already under the
     *  new rules, and a reconnect opens on it too; the classic path reads it
     *  at its next turn. Once on, the call is a practice call. */
    fun setTutorMode(on: Boolean) {
        if (on == tutorThisCall) return
        tutorThisCall = on
        if (on) tutorWasOn = true
        val build = promptForTutor ?: return   // not built yet: it reads tutorThisCall
        if (REALTIME) {
            realtimeSystem = build(on)
            val phase = _state.value.phase
            if (phase != TalkPhase.IDLE && phase != TalkPhase.ENDED) realtime.setSystem(realtimeSystem)
        } else {
            systemPrompt = build(on)
        }
    }

    /** What coach mode may steer toward: the chip row, then the talk-kept
     *  notebook words it leaves out (`TalkGoalPicker.coachExtras`). */
    fun setCoachPool(items: List<com.roro.futurevoice.ui.TalkGoalItem>) {
        coachPool = items
        syncCoachSteer()
    }

    /** The screen's ticks — chips and the hint alike. */
    fun noteUsedGoals(keys: Set<String>) {
        if (keys == usedGoalKeys) return
        usedGoalKeys = keys
        syncCoachSteer()
    }

    /** iOS `coachRegister`. */
    private fun registerFor(person: com.roro.futurevoice.data.Counterpart?, inScene: Boolean) =
        if (person != null) person.effectiveMyRegister
            ?: if (person.isClose) com.roro.futurevoice.data.SpeechRegister.CASUAL
            else com.roro.futurevoice.data.SpeechRegister.POLITE
        else if (inScene) null else com.roro.futurevoice.data.SpeechRegister.CASUAL

    private fun coachCandidates() =
        coachPlan.candidates(coachPool.filter { it.key !in usedGoalKeys })

    /**
     * Put the steer on the gateway — or take it off — to match the ration.
     * Only sent when it changes; the gateway keeps it until told otherwise.
     * Nothing before the learner has spoken: a question built for a word or
     * a structure is an answer to THEM, and the opener is not.
     */
    private fun syncCoachSteer() {
        if (!REALTIME) return
        val open = coachOn && learnerSpokeThisCall && coachPlan.mayHint
        val items = if (open) coachCandidates() else emptyList()
        val focus = if (open) _state.value.grammarFocus else null
        val steer = if (items.isEmpty() && focus == null) "" else ConversationEngine.coachSteer(items, focus)
        if (steer == coachSteerSent) return
        coachSteerSent = steer
        realtime.setSteer(steer)
    }

    /**
     * One step per fluent-self line (iOS `advanceCoach(afterReply:)`): ask
     * [CoachSuggester] for something the learner could say back, every line,
     * the opener included. When a word hint may be drawn (the ration, and
     * only once the learner has spoken) the studied items ride along, and an
     * answer that naturally uses one names it — that is the word hint now.
     * Then re-set the steer for the next line.
     */
    private fun advanceCoach(text: String, turnId: String) {
        val cfg = config ?: return
        if (!coachOn || text.isBlank()) return
        var candidates = emptyList<com.roro.futurevoice.ui.TalkGoalItem>()
        if (learnerSpokeThisCall) {
            val mayHint = coachPlan.mayHint
            coachPlan = coachPlan.replyFinished()
            if (mayHint && CoachPlan.endsInQuestion(text)) candidates = coachCandidates()
        }
        val turns = _state.value.turns
        val learnerSaid = turns.lastOrNull { it.role == TurnRole.USER }?.transcript
        val earlier = turns.lastOrNull { it.role == TurnRole.FLUENT_SELF && it.id != turnId }?.transcript
        val previousSay = _state.value.coachReply?.say
        viewModelScope.launch {
            val result = CoachSuggester.suggest(
                line = text, learnerSaid = learnerSaid,
                earlier = if (learnerSaid == null) null else earlier,
                situation = coachSituation,
                register = coachRegister,
                previousSay = previousSay,
                candidates = candidates,
                target = cfg.targetLanguage, native = cfg.nativeLanguage,
                level = cfg.level, turnId = turnId,
            )
            val st = _state.value
            // Still the line being answered — a late suggestion must never
            // sit under the NEXT one.
            if (!coachOn || st.phase == TalkPhase.ENDED ||
                st.turns.lastOrNull { it.role == TurnRole.FLUENT_SELF }?.id != turnId) return@launch
            val item = result?.second?.takeIf { it.key !in usedGoalKeys }
            if (item != null) coachPlan = coachPlan.hintShown(item)
            // One update: the hidden old line is swapped for the new one in
            // place, so the slot changes height at most once; a failed
            // suggestion empties the hidden slot then (iOS 30e49b07).
            _state.update {
                it.copy(
                    coachReply = result?.first ?: if (it.coachStale) null else it.coachReply,
                    coachHint = item ?: if (it.coachStale) null else it.coachHint,
                    coachStale = false,
                )
            }
            if (item != null) syncCoachSteer()
        }
        if (learnerSpokeThisCall) syncCoachSteer()
    }

    /** Pick this call's grammar focus and name it. Coach mode only. */
    private fun loadGrammarFocus(cfg: TalkConfig) {
        if (!coachOn || _state.value.grammarFocus != null || focusJob?.isActive == true) return
        focusJob = viewModelScope.launch {
            val profile = ProfileStore.shared(appContext).load(cfg.targetLanguage, cfg.level.code)
            val past = runCatching { sessions.load(cfg.targetLanguage) }.getOrDefault(emptyList())
            val focus = GrammarFocus.pick(appContext, profile, past, cfg.targetLanguage, cfg.nativeLanguage)
                ?: return@launch
            if (!coachOn || _state.value.phase == TalkPhase.ENDED) return@launch
            _state.update { it.copy(grammarFocus = focus) }
            syncCoachSteer()
        }
    }

    /** A correction landed: if it is the focus coming back, badge its card
     *  and move the strip's count. Judged off the voice's path. */
    private fun checkFocusRepeat(suggestion: TurnSuggestion, turnId: String) {
        val focus = _state.value.grammarFocus ?: return
        val fixes = suggestion.fixes?.takeIf { it.isNotEmpty() } ?: return
        if (!coachOn) return
        viewModelScope.launch {
            if (!focus.isRepeat(fixes, turnId)) return@launch
            if (_state.value.grammarFocus != focus) return@launch
            _state.update { it.copy(focusRepeatTurns = it.focusRepeatTurns + turnId) }
        }
    }

    /** One row per coached call — how "does it feel forced" gets measured. */
    private fun logCoach() {
        val st = _state.value
        if (coachPlan.hintsShown > 0 || (st.grammarFocus != null && learnerSpokeThisCall)) {
            com.roro.futurevoice.core.Telemetry.log("talk_coach", mapOf(
                "hints" to coachPlan.hintsShown.toString(),
                "used" to coachPlan.hinted.count { it in usedGoalKeys }.toString(),
                "focus" to if (st.grammarFocus == null) "none" else "on",
                "focus_repeats" to st.focusRepeatTurns.size.toString(),
            ))
        }
    }

    private fun fail(e: Exception) {
        if (e is CancellationException) return   // end() cancelling a job is not a failure
        // A 402 from a turn is the same wall the meter reports, and it is not
        // an error — route it to the same place.
        if (e is EdgeError.InsufficientCredits || e is EdgeError.DailyCapReached ||
            e is EdgeError.FairUseLimit) {
            hitWall(e); return
        }
        meter.stop()
        cancelIdleWatch()
        endpointJob?.cancel()
        runCatching { live.stop() }
        pcm.stop()
        _state.update { it.copy(phase = TalkPhase.ENDED, error = humanMessage(e)) }
        persist()
    }

    // MARK: - Metering

    /**
     * Is this second part of the conversation? The fluent self thinking or
     * speaking counts; otherwise only a learner demonstrably talking into the
     * mic does. Silence — a phone put down, a room's babble — bills nothing.
     */
    /** First speech of the call — what opens the meter. */
    private fun markLearnerSpoke() {
        if (learnerSpokeThisCall) return
        learnerSpokeThisCall = true
    }

    private fun isBillableMoment(): Boolean =
        TalkMeter.isBillable(moment(learnerSpoke = learnerSpokeThisCall))

    /** Someone is speaking, being answered or being heard — billing's
     *  predicate without its "not before the first turn" gate. */
    private fun somethingIsHappening(): Boolean {
        val billable = TalkMeter.isBillable(moment(learnerSpoke = true))
        if (BuildConfig.DEBUG && !REALTIME) {
            val now = System.currentTimeMillis()
            Log.d(TAG, "billable=$billable phase=${_state.value.phase} pcm=${pcm.isPlaying} mp3=${mp3.isPlaying} " +
                "voicedAgo=${live.lastVoicedAtMs?.let { now - it }} heardAgo=${lastTranscriptChangeAt?.let { now - it }} " +
                "voicedSec=${"%.1f".format(live.fluencyStats().speakingSeconds)} level=${"%.2f".format(live.level)}")
        }
        return billable
    }

    private fun moment(learnerSpoke: Boolean): TalkMeter.Companion.Moment {
        val now = System.currentTimeMillis()
        val phase = _state.value.phase
        if (REALTIME) return TalkMeter.Companion.Moment(learnerSpoke, phase,
            realtime = realtime.state, realtimeLevel = realtime.level,
            sendToAnswer = sendToAnswerOn)
        return TalkMeter.Companion.Moment(learnerSpoke, phase,
            audioPlaying = pcm.isPlaying || mp3.isPlaying,
            voicedAgoMs = live.lastVoicedAtMs?.let { now - it },
            heardAgoMs = lastTranscriptChangeAt?.let { now - it },
            voicedSeconds = live.fluencyStats().speakingSeconds)
    }

    /**
     * The server said the talking is over. The call ends gracefully: the
     * transcript stays, nothing is billed past this point, and the screen says
     * WHICH wall it was so a subscriber is never shown a paywall.
     */
    private fun hitWall(wall: EdgeError) {
        if (!REALTIME) callJob?.cancel()
        val kind = when (wall) {
            is EdgeError.DailyCapReached -> TalkWall.ALLOWANCE_SPENT
            is EdgeError.SceneCapReached -> TalkWall.SCENES_SPENT
            is EdgeError.FairUseLimit -> TalkWall.FAIR_USE
            else -> TalkWall.OUT_OF_MINUTES
        }
        // The same three answers the gateway's walls get (iOS routes the
        // meter's `onWallHit` and the realtime wall to one place).
        handleWall(kind)
    }

    private fun humanMessage(e: Exception): String = when (e) {
        is EdgeError.Http -> "Server error ${e.status}"
        else -> e.message ?: e::class.java.simpleName
    }

    /** A scenario talk's attached material — the posting, the CV — read once
     *  by Watch and carried on the scenario (iOS `briefBlock`). Null for
     *  every other kind of call, and for a scenario nothing was attached to. */
    private suspend fun scenarioBrief(cfg: TalkConfig): ScenarioBrief? {
        val id = cfg.scenarioId ?: return null
        return runCatching {
            com.roro.futurevoice.data.ScenarioStore.shared(appContext)
                .load(cfg.targetLanguage).firstOrNull { it.id == id }?.brief
        }.getOrNull()
    }

    companion object {
        /** A second drop inside a minute is not a blip; it gets the question
         *  rather than another silent reconnect. */
        private const val AUTO_RECONNECT_SPACING_MS = 60_000L

        /** Realtime is the only call path (iOS `RealtimeMode`, 2026-09-05). */
        const val REALTIME = true
        private const val TAG = "TalkViewModel"
        /** Voiced seconds this turn before a segment counts as a person talking. */

        /**
         * How long a call may hear nothing at all before it puts itself down.
         * 30 s of nothing — no close-mic voice, no reply in flight, no line
         * being spoken — is already a long silence in a conversation (iOS
         * started at three minutes, then one; both were a long time to sit
         * with an open mic). The floor is the learner who thinks a long while
         * and then speaks: the recovery is one tap on a screen that never
         * lost the conversation.
         */
        private const val IDLE_PAUSE_SECONDS = 30
        private const val IDLE_PAUSE_HOLDING_SECONDS = 120

        /** Coarse on purpose — the pause lands within a tick of the bar. */
        private const val IDLE_WATCH_TICK_SECONDS = 5
    }
}

