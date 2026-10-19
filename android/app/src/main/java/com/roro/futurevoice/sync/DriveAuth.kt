package com.roro.futurevoice.sync

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Task
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * The learner's grant to the app's OWN hidden folder in their Google Drive —
 * `drive.appdata`, the narrowest Drive scope there is: the app cannot see a
 * single file the learner made, and the learner's Drive shows nothing but
 * the space it takes (Settings → Manage apps). Android's iCloud: their
 * storage, not ours, and nothing they said to their future self lands on our
 * servers.
 *
 * The grant is the Google ACCOUNT's, not the install's: a tablet signed into
 * the same Google account gets a token without asking again, which is what
 * lets the second device's check run without a consent sheet in most cases.
 */
object DriveAuth {
    const val SCOPE = "https://www.googleapis.com/auth/drive.appdata"

    sealed interface Outcome {
        data class Token(val accessToken: String) : Outcome
        /** The learner has to say yes — launch this from a screen. */
        data class NeedsConsent(val intent: PendingIntent) : Outcome
        /** The learner closed the sheet or chose not to allow it. */
        data object Denied : Outcome
        data class Failed(val reason: String) : Outcome
    }

    private fun request() = AuthorizationRequest.builder()
        .setRequestedScopes(listOf(Scope(SCOPE)))
        .build()

    /** A token without UI when the grant exists; otherwise what to launch. */
    suspend fun authorize(context: Context): Outcome = runCatching {
        val result = Identity.getAuthorizationClient(context).authorize(request()).await()
        outcome(result)
    }.getOrElse { Outcome.Failed(it.message ?: it.javaClass.simpleName) }

    /** The consent sheet came back. */
    fun fromConsent(context: Context, data: Intent?): Outcome = runCatching {
        outcome(Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data))
    }.getOrElse { Outcome.Failed(it.message ?: it.javaClass.simpleName) }

    private fun outcome(r: AuthorizationResult): Outcome {
        val pending = r.pendingIntent
        if (r.hasResolution() && pending != null) return Outcome.NeedsConsent(pending)
        val token = r.accessToken ?: return Outcome.Failed("no token")
        return Outcome.Token(token)
    }

    private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { cont ->
        addOnSuccessListener { cont.resume(it) }
        addOnFailureListener { cont.resumeWithException(it) }
        addOnCanceledListener { cont.cancel() }
    }
}
