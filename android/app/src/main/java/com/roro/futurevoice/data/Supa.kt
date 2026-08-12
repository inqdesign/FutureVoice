package com.roro.futurevoice.data

import com.roro.futurevoice.core.Config
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Apple
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Single shared Supabase client — the Android sibling of `SupabaseProvider`.
 *
 * Never put the service_role key here; it lives only as a Function secret.
 */
object Supa {
    val client: SupabaseClient by lazy {
        createSupabaseClient(Config.supabaseUrl, Config.supabaseAnonKey) {
            install(Auth) {
                // OAuth callback target — must match the manifest intent-filter
                // and the redirect URL allow-list in the Supabase dashboard.
                scheme = "futurevoice"
                host = "login"
            }
            install(Postgrest)
        }
    }
}

class AuthError(message: String) : Exception(message)

/**
 * Auth is Apple-only on purpose.
 *
 * The Supabase user identity MUST match iOS or the voice clone can't be
 * restored — and that restore is the whole magic moment (`docs/contracts/data-model.md`).
 * Apple has no native Android SDK, so this is the web OAuth flow: a Custom Tab
 * that lands back on `futurevoice://login`.
 */
class AuthRepository {

    val sessionStatus: Flow<SessionStatus> = Supa.client.auth.sessionStatus

    val userId: String?
        get() = Supa.client.auth.currentUserOrNull()?.id

    val email: String?
        get() = Supa.client.auth.currentUserOrNull()?.email

    suspend fun signInWithApple() {
        Supa.client.auth.signInWith(Apple)
    }

    /**
     * DEBUG BUILDS ONLY (enforced at the call site — the UI for this exists
     * only behind `BuildConfig.DEBUG`). Email+password sign-in for the
     * dedicated test account, so the emulator can run the Talk loop while
     * Apple's web-OAuth setup (Services ID + secret) is still pending.
     * Production accounts are Apple-only; email auth reaches nothing real.
     */
    suspend fun devSignIn(email: String, password: String) {
        Supa.client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signOut() {
        Supa.client.auth.signOut()
    }

    /** Bearer token for every Edge Function call. */
    suspend fun accessToken(): String =
        Supa.client.auth.currentAccessTokenOrNull()
            ?: throw AuthError("No Supabase session — sign in first.")

    /** Cheap token refresh, used by the pre-connect warm-up. */
    suspend fun warmToken() {
        runCatching { Supa.client.auth.currentAccessTokenOrNull() }
    }
}

@Serializable
data class VoiceCloneRow(
    @SerialName("elevenlabs_voice_id") val elevenlabsVoiceId: String,
)

@Serializable
data class ProfileRow(
    @SerialName("native_language") val nativeLanguage: String = "ko",
    @SerialName("target_language") val targetLanguage: String = "en",
    val proficiency: String = "b1",
)

/**
 * The magic moment: a user who cloned on iPhone signs in here and the FIRST
 * thing they hear is their own voice. Restore, never re-clone — the DB enforces
 * one active clone per user and ElevenLabs voices are language-agnostic.
 */
class VoiceCloneRepository {

    suspend fun activeVoiceId(userId: String): String? =
        Supa.client.from("voice_clones")
            .select {
                filter {
                    eq("user_id", userId)
                    eq("is_active", true)
                }
                limit(1)
            }
            .decodeSingleOrNull<VoiceCloneRow>()
            ?.elevenlabsVoiceId

    suspend fun profile(userId: String): ProfileRow? =
        Supa.client.from("profiles")
            .select {
                filter { eq("id", userId) }
                limit(1)
            }
            .decodeSingleOrNull<ProfileRow>()
}
