package com.roro.futurevoice.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.VoiceCloneRepository
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

data class AppState(
    val resolvingSession: Boolean = true,
    val signedIn: Boolean = false,
    /** Session without an account — data dies with the install until linked. */
    val isAnonymous: Boolean = false,
    /** First-run answers taken (native/target/level/goal). Gate for SetupFlow. */
    val setupComplete: Boolean = false,
    /** Null iff persona onboarding never completed — routes to the intake. */
    val persona: com.roro.futurevoice.talk.UserPersona? = null,
    val personaResolved: Boolean = false,
    val email: String? = null,
    val busy: Boolean = false,
    val restoringVoice: Boolean = false,
    /** The whole magic moment lives on this being non-null after sign-in. */
    val voiceId: String? = null,
    /** The accent the live clone was remixed with, if any. */
    val voiceAccentId: String? = null,
    /** Set when a MEASURED assessment raised the level; the sheet clears it. */
    val levelUp: Pair<CefrLevel, CefrLevel>? = null,
    val targetLanguage: String = "en",
    /** Every target the learner has enrolled, in enrollment order. */
    val enrolledLanguages: List<String> = emptyList(),
    val nativeLanguage: String = "ko",
    val level: CefrLevel = CefrLevel.B1,
    val error: String? = null,
)

class AppViewModel(private val appContext: android.content.Context) : ViewModel() {

    private val auth = AuthRepository()
    private val voices = VoiceCloneRepository()

    private val prefs = appContext.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(AppState(
        setupComplete = prefs.getBoolean(SETUP_COMPLETE_KEY, false),
        targetLanguage = prefs.getString("futurevoice.targetLanguage", null) ?: "en",
        // A bare "zh" was stored before Chinese was split by script.
        nativeLanguage = prefs.getString(NATIVE_KEY, null)
            ?.let { LanguageCatalog.normalizedNative(it) } ?: LanguageCatalog.defaultNative(),
        // Per-language, falling back to the one-and-only level a pre-
        // multi-language install stored.
        level = CefrLevel.from(
            prefs.getString(
                "futurevoice.level." + (prefs.getString("futurevoice.targetLanguage", null) ?: "en"),
                null) ?: prefs.getString(LEVEL_KEY, null)),
        enrolledLanguages = LanguageScope.enrolled(appContext),
        voiceAccentId = prefs.getString(ACCENT_KEY, null),
    ))
    val state: StateFlow<AppState> = _state.asStateFlow()

    /**
     * Re-read everything a restore just overwrote.
     *
     * The stores hold whatever they read BEFORE the import, and the state
     * flow was built from preferences that have since changed — without this
     * a restored install keeps pointing at the old language, so every file
     * lands correctly and the screen shows nothing.
     */
    fun adoptRestoredData() {
        // No store repointing to do: every scoped store resolves
        // `lang/<code>/` on each call rather than caching a handle, which is
        // exactly why a language switch needs no flush here.
        val target = prefs.getString("futurevoice.targetLanguage", null)
        val native = prefs.getString(NATIVE_KEY, null)
        val enrolled = LanguageScope.enrolled(appContext)
        viewModelScope.launch {
            val persona = PersonaStore.shared(appContext).load()
            _state.update {
                it.copy(
                    setupComplete = prefs.getBoolean(SETUP_COMPLETE_KEY, it.setupComplete),
                    targetLanguage = target ?: it.targetLanguage,
                    nativeLanguage = native ?: it.nativeLanguage,
                    enrolledLanguages = enrolled.ifEmpty { it.enrolledLanguages },
                    level = CefrLevel.from(
                        prefs.getString("futurevoice.level.${target ?: it.targetLanguage}", null)
                            ?: prefs.getString(LEVEL_KEY, null)),
                    persona = persona,
                    personaResolved = true,
                )
            }
            StoreEvents.bump()
        }
    }

    init {
        viewModelScope.launch {
            val persona = PersonaStore.shared(appContext).load()
            _state.update { it.copy(persona = persona, personaResolved = true) }
        }
        // The streak's bar is a server figure the whole app draws offline, so
        // it is mirrored once per launch and read from disk everywhere else.
        // A failure keeps the last known value — never a guess mid-session.
        viewModelScope.launch {
            val target = appContext.getSharedPreferences("futurevoice", 0)
                .getString("futurevoice.targetLanguage", null) ?: "en"
            com.roro.futurevoice.net.CoreClubClient(auth).progress(target)
                ?.let { com.roro.futurevoice.data.CoreBar.remember(appContext, it.bar_seconds) }
        }
        // Someone taking a seat is the club's only public event. There is no
        // push, so the app notices on launch and says so quietly.
        viewModelScope.launch {
            runCatching {
                com.roro.futurevoice.data.CoreArrivals.poll(
                    appContext, auth.accessToken(), auth.userId)
            }
        }
        // The summarizer writes to the persona behind this screen's back —
        // learned notes, and the metAt stamp that retires the first-call
        // framing. Without a re-read the next free talk still opens with the
        // introduction. persona.json is tiny; a read per store bump is fine.
        viewModelScope.launch {
            StoreEvents.revision.drop(1).collect {
                PersonaStore.shared(appContext).load()?.let { p -> _state.update { it.copy(persona = p) } }
            }
        }
        // Foreground / purchase asks to re-read the parked state (see
        // `VoiceParking`); the throttle lives in `refreshParkedVoice`.
        viewModelScope.launch {
            com.roro.futurevoice.data.VoiceParking.recheck.collect { force -> refreshParkedVoice(force) }
        }
        // A parked mark belongs to ONE voice: once the app holds another (a
        // re-record here or on another device), the mark is stale.
        viewModelScope.launch {
            _state.collect { st ->
                val parked = com.roro.futurevoice.data.VoiceParking.parkedId.value
                if (st.voiceId != null && parked != null && parked != st.voiceId)
                    com.roro.futurevoice.data.VoiceParking.set(null)
            }
        }
        viewModelScope.launch {
            auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        _state.update {
                            it.copy(
                                resolvingSession = false,
                                signedIn = true,
                                email = auth.email,
                                isAnonymous = auth.isAnonymous,
                                // Set HERE, not first inside the restore —
                                // a frame of voiceId == null with no restore
                                // running would flash the clone flow.
                                restoringVoice = true,
                            )
                        }
                        auth.userId?.let { com.roro.futurevoice.core.Analytics.identify(it) }
                        // An account now owns the session: a linked anonymous
                        // user keeps its id and its voice is off the clock.
                        if (!auth.isAnonymous) com.roro.futurevoice.data.VoiceReclaim.clear(appContext)
                        restoreVoiceClone()
                    }

                    is SessionStatus.Initializing ->
                        _state.update { it.copy(resolvingSession = true) }

                    else -> _state.update {
                        it.copy(
                            resolvingSession = false,
                            signedIn = false,
                            email = null,
                            voiceId = null,
                        )
                    }
                }
            }
        }
    }

    fun signIn() {
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            runCatching { auth.signInWithApple() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(busy = false) }
        }
    }

    val isGoogleConfigured: Boolean get() = auth.isGoogleConfigured

    /** "Get started": onboard account-free; sign-up comes after the clone. */
    fun startAnonymous() {
        com.roro.futurevoice.core.Analytics.capture("onboarding_started")
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            runCatching { auth.startAnonymousSession() }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(busy = false) }
        }
    }

    /** Needs an ACTIVITY context — Credential Manager shows UI from it. */
    fun signInWithGoogle(activityContext: android.content.Context) {
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            runCatching { auth.signInWithGoogle(activityContext) }
                .onFailure { e ->
                    // Backing out of Google's sheet is not an error. Anything
                    // else gets one line in the app language — the raw
                    // exception text is English and names Android internals.
                    if (e is androidx.credentials.exceptions.GetCredentialCancellationException) return@onFailure
                    android.util.Log.w("Auth", "google sign-in failed", e)
                    _state.update { it.copy(error = activityContext.getString(com.roro.futurevoice.R.string.google_sign_in_failed)) }
                }
            _state.update { it.copy(busy = false) }
        }
    }

    fun signOut() {
        com.roro.futurevoice.core.Analytics.reset()   // drop identity so the next user isn't merged in
        viewModelScope.launch {
            runCatching { auth.signOut() }
        }
    }

    /** Debug-only — see [AuthRepository.devSignIn]. */
    fun devSignIn(email: String, password: String) {
        _state.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            runCatching { auth.devSignIn(email.trim(), password) }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(busy = false) }
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    /** Cross-stage Back from the persona cards: reopen the quick-answer setup. */
    fun reopenSetup() {
        prefs.edit().putBoolean(SETUP_COMPLETE_KEY, false).apply()
        _state.update { it.copy(setupComplete = false) }
    }

    fun savePersona(persona: com.roro.futurevoice.talk.UserPersona) {
        _state.update { it.copy(persona = persona) }
        viewModelScope.launch {
            PersonaStore.shared(appContext).save(persona)
            // Keep the learner's Find-people presence in step with their
            // profile (a no-op once they manage their intro by hand).
            syncPublicPersona()
        }
    }

    /**
     * Mirror the onboarding profile into the shared Find-people pool, so an
     * existing learner appears without doing anything.
     *
     * Called at app start and whenever the profile changes. Never throws into
     * the caller: a pool the learner cannot reach is not a reason to break
     * the app they opened.
     */
    /**
     * A fresh assessment measured the learner's level.
     *
     * The measurement REPLACES the self-reported setting: from here scoring
     * calibration, pickup-word difficulty and the talk-card label all track
     * what was measured rather than what someone guessed about themselves in
     * onboarding. A manual change in Me still wins until the next assessment.
     *
     * Only a RISE is announced. Being told you dropped a band is not news
     * anyone asked for, and the number is an estimate — it moves both ways
     * for reasons that have nothing to do with the learner getting worse.
     */
    /**
     * A level the learner set BY HAND, for a language that may not be the
     * active one. No level-up banner and no analytics: nothing rose, they
     * corrected a setting. The write goes to [LanguageScope] like every
     * other level, and the in-memory copy follows only when it is the
     * language currently being practised — otherwise the app would run the
     * next talk at another language's band.
     */
    fun setLevel(language: String, level: CefrLevel) {
        LanguageScope.setLevel(appContext, language, level.code)
        if (language == _state.value.targetLanguage) {
            _state.update { it.copy(level = level) }
            mirrorSetup()
        }
    }

    fun applyMeasuredLevel(raw: String) {
        val measured = CefrLevel.from(raw)
        val current = _state.value.level
        if (measured == current) return
        val target = _state.value.targetLanguage
        LanguageScope.setLevel(appContext, target, measured.code)
        val rose = measured.ordinal > current.ordinal
        if (rose) com.roro.futurevoice.core.Analytics.capture("level_up", mapOf("from" to current.code, "to" to measured.code))
        _state.update {
            it.copy(level = measured, levelUp = if (rose) current to measured else it.levelUp)
        }
    }

    fun clearLevelUp() {
        _state.update { it.copy(levelUp = null) }
    }

    /** Whether the learner still owes the pool a yes or a no (the Watch-tab preview). */
    fun needsIntroDecision(): Boolean {
        val s = _state.value
        if (!s.signedIn || s.isAnonymous) return false
        return com.roro.futurevoice.net.PublicPersonaClient.needsIntroDecision(
            com.roro.futurevoice.net.PublicPersonaClient.prefs(appContext), s.persona)
    }

    /**
     * The preview's Publish: the mirror goes up, and from here on follows
     * profile edits — that is what was approved. Runs on the view model's
     * scope so dismissing the sheet can't cancel a write half-done.
     */
    suspend fun publishIntroMirror(): Boolean {
        val s = _state.value
        val p = s.persona ?: return false
        val ok = viewModelScope.async {
            com.roro.futurevoice.net.PublicPersonaClient(auth).publishMirror(p, s.targetLanguage)
        }.await()
        if (ok) {
            com.roro.futurevoice.net.PublicPersonaClient.prefs(appContext).edit()
                .putBoolean(com.roro.futurevoice.net.PublicPersonaClient.AUTO_APPROVED_KEY, true).apply()
        }
        return ok
    }

    /**
     * The preview's Not now: an explicit no, so the mirror never publishes on
     * its own — and a row an earlier build put up unasked comes down with it.
     */
    fun declinePublicIntro() {
        com.roro.futurevoice.net.PublicPersonaClient.prefs(appContext).edit()
            .putBoolean(com.roro.futurevoice.net.PublicPersonaClient.MANUAL_INTRO_KEY, true).apply()
        val language = _state.value.targetLanguage
        viewModelScope.launch {
            runCatching { com.roro.futurevoice.net.PublicPersonaClient(auth).withdrawMine(language) }
        }
    }

    fun syncPublicPersona() {
        viewModelScope.launch {
            val s = _state.value
            runCatching {
                com.roro.futurevoice.net.PublicPersonaClient(auth)
                    .autoSyncMyPersona(appContext, s.persona, s.targetLanguage)
            }
        }
    }

    /**
     * A remixed take was promoted to the live voice.
     *
     * The outgoing clone is deleted upstream — a voice slot we pay for, and
     * there is no way back to it except rebuilding from the saved recording.
     * That is why applying a take is an explicit choice on its own button and
     * never a side effect of auditioning one.
     */
    fun adoptRemixedVoice(newId: String, accentId: String) {
        com.roro.futurevoice.core.Analytics.capture("voice_accent_applied")
        val old = _state.value.voiceId
        if (newId == old) return
        _state.update { it.copy(voiceId = newId, voiceAccentId = accentId) }
        prefs.edit().putString(ACCENT_KEY, accentId).apply()
        viewModelScope.launch {
            if (old != null) {
                runCatching { com.roro.futurevoice.data.AccountEraser.deleteVoice(old) }
            }
        }
    }

    /** A clone just landed on this device — the server row already exists. */
    fun onVoiceCloned(voiceId: String) {
        // A fresh recording replaces whatever was parked or dropped.
        com.roro.futurevoice.data.VoiceParking.set(null)
        com.roro.futurevoice.data.VoiceParking.markDropped(null)
        _state.update { it.copy(voiceId = voiceId) }
    }

    /** Last time the server was asked whether this phone's voice is parked. */
    private var parkedCheckedAt: Long? = null

    /**
     * Is this phone's voice PARKED (see `VoiceParking`)? Asks the server at
     * most every 10 minutes (`force` skips that — sign-in, a purchase). Only
     * LEARNS the state: bringing the voice back is the call tap's job
     * (`VoiceRevival`), because rebuilding it is something the learner should
     * see happen, with the speed and accent to set again.
     */
    fun refreshParkedVoice(force: Boolean = false) {
        val st = _state.value
        val voiceId = st.voiceId ?: return
        if (!st.signedIn || st.isAnonymous) return
        val parking = com.roro.futurevoice.data.VoiceParking
        val already = parking.isParked(voiceId)
        if (!parking.shouldCheck(already, force, parkedCheckedAt, System.currentTimeMillis())) return
        viewModelScope.launch {
            // Offline, or a database without the column yet: whatever was
            // known stays known.
            val row = runCatching { voices.parkedAt(voiceId) }.getOrElse { return@launch }
            parkedCheckedAt = System.currentTimeMillis()
            if (row == null) return@launch
            // The voice may have moved on while the query ran.
            if (_state.value.voiceId != voiceId) return@launch
            val next = parking.nextParkedId(voiceId, row.parkedAt)
            if (next == parking.parkedId.value) return@launch
            parking.set(next)
            if (next != null) {
                com.roro.futurevoice.core.Analytics.capture("voice_parked_notice")
                com.roro.futurevoice.core.Telemetry.log("voice_parked_notice")
                // The daily call stands down while parked.
                com.roro.futurevoice.data.DailyCallScheduler.cancel(appContext)
            } else if (com.roro.futurevoice.data.DailyCallStore.isEnabled(appContext)) {
                com.roro.futurevoice.data.DailyCallScheduler.schedule(appContext)
            }
        }
    }

    /**
     * Rebuild a parked voice from the recording on this phone (the revival
     * screen's first stage). The parked id stays in the lineage so audio made
     * with it keeps playing. The accent died with the old voice, so it is
     * cleared — the screen offers it again. Failure leaves the voice parked.
     */
    suspend fun reviveParkedVoice(): Result<String> {
        val sample = VoiceComparison.sampleFile(appContext.filesDir)
        val result = runCatching {
            if (!sample.exists() || sample.length() == 0L) error("no_sample")
            com.roro.futurevoice.net.VoiceCloneClient(auth).cloneVoice(
                name = "Future Self",
                sample = sample,
                removeBackgroundNoise = false,
            )
        }
        result.onSuccess { newId ->
            com.roro.futurevoice.data.PhraseAudioStore.shared(appContext).registerOwnVoice(newId)
            // The parked voice is already gone upstream; its row went inactive
            // when the clone function inserted this one. Nothing to delete.
            com.roro.futurevoice.data.VoiceParking.set(null)
            prefs.edit().remove(ACCENT_KEY).apply()
            _state.update { it.copy(voiceId = newId, voiceAccentId = null) }
            if (com.roro.futurevoice.data.DailyCallStore.isEnabled(appContext))
                com.roro.futurevoice.data.DailyCallScheduler.schedule(appContext)
            com.roro.futurevoice.core.Analytics.capture("voice_parked_revive", mapOf("result" to "ok"))
            com.roro.futurevoice.core.Telemetry.log("voice_parked_revive", mapOf("result" to "ok"))
        }.onFailure { e ->
            com.roro.futurevoice.core.Analytics.capture("voice_parked_revive", mapOf("result" to "failed"))
            com.roro.futurevoice.core.Telemetry.log("voice_parked_revive",
                mapOf("result" to "failed", "error" to e.toString().take(200)))
        }
        return result
    }

    /**
     * A parked voice with no recording on this phone (a reinstall, another
     * device) can't be rebuilt here: the "let's make your voice again" clone
     * flow, the same one a reclaimed voice gets.
     */
    fun parkedVoiceNeedsRecording() {
        com.roro.futurevoice.core.Analytics.capture("voice_parked_revive", mapOf("result" to "no_sample"))
        val parking = com.roro.futurevoice.data.VoiceParking
        parking.markDropped(_state.value.voiceId)
        parking.set(null)
        _state.update { it.copy(voiceId = null) }
    }

    /**
     * First-run setup answers. Persisted locally (the same keys the stores
     * read: `LanguageScope` resolves directories from the target key) and the
     * gate opens. Server-profile sync arrives with the account work.
     */
    /**
     * The learner's own language, changed after setup. It decides the app's
     * screens AND the language coaching comes back in, so the activity is
     * recreated by the caller — resources are resolved from a context that
     * was built when it was attached.
     */
    fun setNativeLanguage(code: String) {
        prefs.edit().putString(NATIVE_KEY, code).apply()
        _state.update { it.copy(nativeLanguage = code) }
        com.roro.futurevoice.core.Analytics.capture("app_language_changed", mapOf("language" to code))
    }

    fun completeSetup(native: String, target: String, level: CefrLevel, goalMinutes: Int) {
        prefs.edit()
            .putBoolean(SETUP_COMPLETE_KEY, true)
            .putString(NATIVE_KEY, native)
            .putString(LEVEL_KEY, level.code)
            .putInt(GOAL_KEY, goalMinutes)
            .apply()
        LanguageScope.setActive(appContext, target)
        LanguageScope.enroll(appContext, target)
        LanguageScope.setLevel(appContext, target, level.code)
        _state.update {
            it.also { com.roro.futurevoice.core.Analytics.capture("setup_completed") }.copy(setupComplete = true, nativeLanguage = native,
                targetLanguage = target, level = level,
                enrolledLanguages = LanguageScope.enrolled(appContext))
        }
        mirrorSetup()
    }

    /**
     * Leave what they CHOSE on the server. Nothing has ever written
     * `profiles`' three setup columns, so every row carries the column
     * defaults and a console reading them would report every learner as an
     * English learner. Called wherever a session and a completed setup can
     * both be true — setup, a language switch, a level move, and each launch.
     */
    private fun mirrorSetup() {
        val st = _state.value
        if (!st.setupComplete) return
        com.roro.futurevoice.data.LearnerSetupSync.push(
            appContext, target = st.targetLanguage, native = st.nativeLanguage,
            level = st.level.code)
    }

    /**
     * Move to another enrolled language. Nothing is copied or cleared: every
     * store already takes the language as a parameter, so switching is only a
     * change of which one they are handed.
     *
     * The LEVEL moves with it. Someone at C1 in English starting German is
     * not a C1 German speaker, and carrying one level across would pitch
     * every reply and every scene at the wrong band from the first turn.
     */
    fun switchLanguage(code: String) {
        com.roro.futurevoice.core.Analytics.capture("language_switched")
        LanguageScope.setActive(appContext, code)
        LanguageScope.enroll(appContext, code)
        val level = CefrLevel.from(LanguageScope.level(appContext, code, _state.value.level.code))
        _state.update {
            it.copy(targetLanguage = code, level = level,
                enrolledLanguages = LanguageScope.enrolled(appContext))
        }
        mirrorSetup()
        StoreEvents.bump()
    }

    /**
     * Enroll a new target and switch to it.
     *
     * Deliberately NOT gated on a plan: every pool the server keeps is per
     * ACCOUNT with no language in it, so a second language adds no cost.
     * Someone splitting five minutes across three languages is spending their
     * own time, and the day's cap is what converts them.
     */
    fun addLanguage(code: String, level: CefrLevel) {
        com.roro.futurevoice.core.Analytics.capture("language_added")
        LanguageScope.enroll(appContext, code)
        LanguageScope.setLevel(appContext, code, level.code)
        switchLanguage(code)
    }

    /**
     * Restore, never re-clone. A user who cloned on iPhone must hear their own
     * voice here immediately — see `docs/contracts/data-model.md`.
     */
    private fun restoreVoiceClone() {
        val uid = auth.userId ?: return
        _state.update { it.copy(restoringVoice = true) }
        viewModelScope.launch {
            // A swallowed failure here walks a paying learner into re-cloning
            // a voice they already own — say what went wrong, every time.
            val serverVoiceId = runCatching { voices.activeVoiceId(uid) }
                .onFailure { android.util.Log.w("AppViewModel", "voice restore failed", it) }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
                .getOrNull()
            // A parked voice dropped for want of a recording keeps an active
            // row; restoring it would skip the re-record it was dropped for.
            val voiceId = com.roro.futurevoice.data.VoiceParking.restoredVoiceId(
                serverVoiceId, com.roro.futurevoice.data.VoiceParking.droppedId())
            // The lineage is what keeps already-synthesized audio reachable
            // after a re-clone — without it a new voice id misses on every
            // cached line and the whole library re-bills itself.
            com.roro.futurevoice.data.PhraseAudioStore.shared(appContext).registerOwnVoice(voiceId)
            // A session exists now, which is the first moment the onboarding
            // choices have anywhere to go.
            mirrorSetup()
            val profile = runCatching { voices.profile(uid) }.getOrNull()
            _state.update {
                // The device's OWN answers outrank the server row: an Android
                // user who just picked German must not be flipped back by a
                // profile written on an iPhone last month. The server fills
                // gaps only (fresh install restoring an account).
                val localSetup = it.setupComplete
                it.copy(
                    restoringVoice = false,
                    voiceId = voiceId,
                    targetLanguage = if (localSetup) it.targetLanguage
                        else profile?.targetLanguage ?: it.targetLanguage,
                    nativeLanguage = if (localSetup) it.nativeLanguage
                        else profile?.nativeLanguage ?: it.nativeLanguage,
                    level = if (localSetup) it.level else CefrLevel.from(profile?.proficiency),
                )
            }
            // Sign-in: was this voice parked while the app was away?
            refreshParkedVoice(force = true)
        }
    }

    private companion object {
        const val SETUP_COMPLETE_KEY = "futurevoice.setupComplete"
        const val NATIVE_KEY = "futurevoice.nativeLanguage"
        /** Same key name as iOS's defaults key. */
        const val ACCENT_KEY = "futurevoice.voiceAccentId"
        const val LEVEL_KEY = "futurevoice.proficiency"
        const val GOAL_KEY = "futurevoice.dailyGoalMinutes"
    }
}
