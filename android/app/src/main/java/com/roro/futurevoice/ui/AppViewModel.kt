package com.roro.futurevoice.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
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

class AppViewModel : ViewModel() {

    private val auth = AuthRepository()
    private val voices = VoiceCloneRepository()

    private val _state = MutableStateFlow(AppState())
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

    fun dismissError() = _state.update { it.copy(error = null) }

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
                it.copy(
                    restoringVoice = false,
                    voiceId = voiceId,
                    targetLanguage = profile?.targetLanguage ?: it.targetLanguage,
                    nativeLanguage = profile?.nativeLanguage ?: it.nativeLanguage,
                    level = CefrLevel.from(profile?.proficiency),
                )
            }
        }
    }
}
