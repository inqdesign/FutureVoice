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

    /**
     * The voice is heard BEFORE the sign-up (iOS, 2026-08-18): what the
     * server needs to clone is a SESSION, not an account. "Get started"
     * opens an anonymous one; the account step comes AFTER the clone, asking
     * to KEEP a voice already in the learner's ears. Unclaimed clones are
     * collected nightly server-side.
     */
    suspend fun startAnonymousSession() {
        Supa.client.auth.signInAnonymously()
    }

    /** A session is not an account — every gate must ask THIS, never `session != null`. */
    val isAnonymous: Boolean
        get() = Supa.client.auth.currentUserOrNull()?.let { user ->
            user.identities.isNullOrEmpty()
        } ?: false

    suspend fun signInWithApple() {
        Supa.client.auth.signInWith(Apple)
    }

    /**
     * Google, the PRIMARY provider on Android (roadmap §1.2): Credential
     * Manager hands us a Google ID token minted against the WEB client id,
     * and Supabase verifies it natively — no browser round trip. Available
     * only once the owner's OAuth clients exist (`GOOGLE_WEB_CLIENT_ID` in
     * local.properties); [isGoogleConfigured] gates the button.
     */
    val isGoogleConfigured: Boolean
        get() = com.roro.futurevoice.BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

    suspend fun signInWithGoogle(context: android.content.Context) {
        val option = com.google.android.libraries.identity.googleid.GetGoogleIdOption.Builder()
            .setServerClientId(com.roro.futurevoice.BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)
            .build()
        val request = androidx.credentials.GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()
        val result = androidx.credentials.CredentialManager.create(context)
            .getCredential(context, request)
        val credential = com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
            .createFrom(result.credential.data)
        Supa.client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.IDToken) {
            idToken = credential.idToken
            provider = io.github.jan.supabase.auth.providers.Google
        }
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

    /**
     * Bearer token for every Edge Function call.
     *
     * Refreshes FIRST when the token is within [refreshSkewMs] of expiry. The
     * SDK's own auto-refresh is a timer armed from the clock at load time; a
     * phone that slept through it, or an emulator whose clock jumped, wakes
     * with a token the server has already retired — every call then 401s
     * until something forces a refresh. `Edge.client`'s authenticator is the
     * second line: a 401 that still gets through refreshes and retries once.
     */
    suspend fun accessToken(): String {
        val session = Supa.client.auth.currentSessionOrNull()
            ?: throw AuthError("No Supabase session — sign in first.")
        val expiresInMs = session.expiresAt.toEpochMilliseconds() - System.currentTimeMillis()
        if (expiresInMs < refreshSkewMs) {
            runCatching { Supa.client.auth.refreshCurrentSession() }
        }
        return Supa.client.auth.currentAccessTokenOrNull()
            ?: throw AuthError("No Supabase session — sign in first.")
    }

    /**
     * Forced refresh after a server-side 401. Returns the NEW token, or null
     * if the session can't be refreshed (signed out, refresh token revoked) —
     * in which case the 401 stands and the UI shows it.
     */
    suspend fun refreshAfterUnauthorized(): String? {
        val before = Supa.client.auth.currentAccessTokenOrNull()
        runCatching { Supa.client.auth.refreshCurrentSession() }
        val after = Supa.client.auth.currentAccessTokenOrNull()
        return after?.takeIf { it != before }
    }

    private companion object {
        /** Refresh when less than this is left — one minute covers clock skew and a slow request. */
        const val refreshSkewMs = 60_000L
    }

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
