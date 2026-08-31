package com.roro.futurevoice.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
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
    /** First-run answers taken (native/target/level/goal). Gate for SetupFlow. */
    val setupComplete: Boolean = false,
    val email: String? = null,
    val busy: Boolean = false,
    val restoringVoice: Boolean = false,
    /** The whole magic moment lives on this being non-null after sign-in. */
    val voiceId: String? = null,
    val targetLanguage: String = "en",
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
        level = CefrLevel.from(prefs.getString(LEVEL_KEY, null)),
    ))
    val state: StateFlow<AppState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        _state.update {
                            it.copy(
                                resolvingSession = false,
                                signedIn = true,
                                email = auth.email,
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
        _state.update {
            it.copy(setupComplete = true, nativeLanguage = native,
                targetLanguage = target, level = level)
        }
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
        const val LEVEL_KEY = "futurevoice.proficiency"
        const val GOAL_KEY = "futurevoice.dailyGoalMinutes"
    }
}
