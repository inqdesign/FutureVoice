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
import kotlinx.coroutines.flow.update
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
        nativeLanguage = prefs.getString(NATIVE_KEY, null) ?: LanguageCatalog.defaultNative(),
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
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
            _state.update { it.copy(busy = false) }
        }
    }

    fun signOut() {
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
        _state.update { it.copy(voiceId = voiceId) }
    }

    /**
     * First-run setup answers. Persisted locally (the same keys the stores
     * read: `LanguageScope` resolves directories from the target key) and the
     * gate opens. Server-profile sync arrives with the account work.
     */
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
            it.copy(setupComplete = true, nativeLanguage = native,
                targetLanguage = target, level = level,
                enrolledLanguages = LanguageScope.enrolled(appContext))
        }
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
        LanguageScope.setActive(appContext, code)
        LanguageScope.enroll(appContext, code)
        val level = CefrLevel.from(LanguageScope.level(appContext, code, _state.value.level.code))
        _state.update {
            it.copy(targetLanguage = code, level = level,
                enrolledLanguages = LanguageScope.enrolled(appContext))
        }
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
            val voiceId = runCatching { voices.activeVoiceId(uid) }
                .onFailure { e -> _state.update { it.copy(error = e.message) } }
                .getOrNull()
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
