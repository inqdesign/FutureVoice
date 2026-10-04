package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.BuildConfig
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.net.Edge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.Calendar

/**
 * The ONE feedback modal, asked ONCE: two scores and a sentence, after a call
 * that actually happened, from someone who came back to have it.
 *
 * **It used to fire on the first call and the first Watch, and that was the
 * wrong moment twice over** (iOS changed this 2026-09-14). It interrupted the
 * single experience the whole product is selling, at the exact second the
 * learner had just done the thing — and it asked for a verdict from someone
 * who had nothing to compare it to. A first impression is not an opinion.
 * What replaces both is one ask at the first moment a learner has actually
 * decided something: they had a call, they left, they CAME BACK, and they
 * have just finished another real one ([FeedbackPrompt.shouldShowReturningTalk]).
 *
 * **Stars, on [FeedbackContext.RETURNING_TALK] only.** A 1–5 row right after
 * someone's very first call reads as a store-review prompt, and a score given
 * before there is anything to score tells us nothing. By the second call on a
 * return visit it doesn't: they have used the thing, and two numbers across
 * many people is the one signal a pile of sentences cannot give. They are
 * asked separately — the APP and the CALLS — because someone can love the
 * calls and find everything around them confusing, which is precisely the
 * feedback worth having, and a single score blurs it.
 *
 * Raw values are the `context` column in `beta_reviews` — never rename one,
 * it would split the history of a question that didn't change. The retired
 * pair keep their rows under their own names.
 */
enum class FeedbackContext(
    val raw: String,
    val title: Int,
    val subtitle: Int,
    /** Only the returning-talk ask carries scores — see the type doc. */
    val rated: Boolean,
) {
    /** A learner who came BACK and had another real call. The only ask there is. */
    RETURNING_TALK("returning_talk", R.string.feedback_returning_title,
        R.string.feedback_returning_subtitle, true),
}

/** Once per milestone. Key prefix is the beta-era one on purpose — it is the
 *  record of who has already been asked, and a new prefix would re-prompt
 *  every existing learner. */
object FeedbackPrompt {
    private fun key(c: FeedbackContext) = "futurevoice.betaFeedback.${c.raw}"

    fun shouldShow(context: Context, c: FeedbackContext) =
        !context.getSharedPreferences("futurevoice", 0).getBoolean(key(c), false)

    fun markShown(context: Context, c: FeedbackContext) =
        context.getSharedPreferences("futurevoice", 0).edit().putBoolean(key(c), true).apply()

    /**
     * The one moment worth asking a learner what they think: they had a call,
     * they came BACK, and they have just finished another real one.
     *
     * Three conditions, and each rules out a kind of answer that would be
     * noise:
     *
     *  - **A minute of call.** Under that nothing happened — an accidental
     *    tap, a call abandoned on the greeting — and an opinion about it is an
     *    opinion about nothing.
     *  - **At least their second finished call**, counted ACROSS LANGUAGES
     *    (the current one is already saved by the time this is asked, so two
     *    means this one plus an earlier one).
     *  - **They came back.** The first call has to be on an EARLIER DAY than
     *    today. Two calls in one sitting is still a first impression; coming
     *    back tomorrow is the first evidence the thing is worth returning to.
     *
     * Asked once, ever — the same record as the rest.
     */
    suspend fun shouldShowReturningTalk(context: Context, callSeconds: Long): Boolean {
        if (callSeconds < 60) return false
        if (!shouldShow(context, FeedbackContext.RETURNING_TALK)) return false
        val store = SessionStore.shared(context)
        val ended = LanguageScope.enrolled(context)
            .flatMap { store.load(it) }
            .filter { it.endedAt != null }
        if (ended.size < 2) return false
        val first = ended.minByOrNull { it.startedAt } ?: return false
        return !isToday(first.startedAt)
    }

    private fun isToday(millis: Long): Boolean {
        val a = Calendar.getInstance().apply { timeInMillis = millis }
        val b = Calendar.getInstance()
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackSheet(context: FeedbackContext, onDismiss: () -> Unit) {
    val app = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var appRating by remember { mutableIntStateOf(0) }
    var callRating by remember { mutableIntStateOf(0) }
    var sending by remember { mutableStateOf(false) }
    var sendError by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(false) }

    // A score on its own is a complete answer, and so is a sentence on its
    // own. Demanding both is how a form gets neither.
    val canSend = text.isNotBlank() || appRating > 0 || callRating > 0

    if (sent) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.thank_you)) },
            text = { Text(stringResource(R.string.your_feedback_goes_straight_to_the_person_building_this)) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
        )
        return
    }
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = { if (!sending) onDismiss() }) {
        Column(Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(context.title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(stringResource(context.subtitle), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (context.rated) {
                StarRow(stringResource(R.string.feedback_the_app_overall), appRating) { appRating = it }
                StarRow(stringResource(R.string.feedback_talking_to_your_future_self), callRating) { callRating = it }
            }
            OutlinedTextField(value = text, onValueChange = { text = it },
                label = { Text(stringResource(R.string.feedback_anything_you_want_to_say)) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 110.dp))
            sendError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onDismiss, enabled = !sending, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.not_now)) }
                Button(onClick = {
                    sending = true; sendError = null
                    scope.launch {
                        runCatching { send(context, text.trim(), appRating, callRating) }
                            .onSuccess { sent = true }
                            .onFailure { sendError = app.getString(R.string.feedback_couldnt_send, it.message ?: "") }
                        sending = false
                    }
                }, enabled = !sending && canSend, modifier = Modifier.weight(1f)) {
                    if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.send))
                }
            }
            Spacer(Modifier.size(4.dp))
        }
    }
}

/**
 * One line of the rating section: a label and five taps.
 *
 * Tapping the star you already chose clears it: a score given by accident
 * must be takeable back, and both scores are optional.
 */
@Composable
private fun StarRow(title: String, rating: Int, onChange: (Int) -> Unit) {
    val value = if (rating == 0) stringResource(R.string.feedback_not_rated)
    else stringResource(R.string.feedback_lld_out_of_5, rating)
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = title
            stateDescription = value
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        for (star in 1..5) {
            IconButton(onClick = { onChange(if (rating == star) 0 else star) },
                modifier = Modifier.size(34.dp)) {
                Icon(
                    if (star <= rating) Icons.Filled.Star else Icons.Outlined.StarOutline,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = if (star <= rating) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * `rating` is the APP score and `call_rating` the CALLS score; both are
 * omitted when unset, so the column keeps its null. The retired
 * `first_talk` / `first_watch` rows carry neither, exactly as before.
 */
private suspend fun send(
    context: FeedbackContext,
    body: String,
    appRating: Int,
    callRating: Int,
) = withContext(Dispatchers.IO) {
    val auth = AuthRepository()
    val uid = auth.userId ?: throw IllegalStateException("signed out")
    val row = buildJsonObject {
        put("user_id", uid)
        put("context", context.raw)
        put("body", body)
        if (appRating > 0) put("rating", appRating)
        if (callRating > 0) put("call_rating", callRating)
        put("app_version", BuildConfig.VERSION_NAME)
        put("app_build", BuildConfig.VERSION_CODE.toString())
    }
    val req = Request.Builder().url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/beta_reviews")
        .header("Authorization", "Bearer ${auth.accessToken()}").header("apikey", Config.supabaseAnonKey)
        .header("Prefer", "return=minimal")
        .post(Edge.json.encodeToString(JsonObject.serializer(), row).toRequestBody("application/json".toMediaType()))
        .build()
    Edge.client.newCall(req).execute().use { r -> if (r.code !in 200..299) throw IllegalStateException("HTTP ${r.code}") }
}
