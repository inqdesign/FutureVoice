package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
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

/**
 * The ONE feedback modal — shown at milestone moments (first conversation
 * ended, first Watch listen-through), always the same shape: the question,
 * a text box, send. No star row: a score right after the first call reads
 * like a store-review prompt and tells us nothing actionable; the sentence
 * is what we need. Raw values are the `context` column in `beta_reviews` —
 * never rename one, it would split the history of a question that didn't
 * change.
 */
enum class FeedbackContext(val raw: String, val title: Int, val subtitle: Int) {
    FIRST_TALK("first_talk", R.string.how_was_your_first_conversation,
        R.string.you_just_talked_with_your_future_voice_what_felt_right_and_w_7a6d31),
    FIRST_WATCH("first_watch", R.string.how_was_your_first_watch,
        R.string.you_just_heard_yourself_handle_a_real_situation_did_it_sound_ed28b5),
}

/** Once per milestone. Key prefix is the beta-era one on purpose — it is the
 *  record of who has already been asked. */
object FeedbackPrompt {
    private fun key(c: FeedbackContext) = "futurevoice.betaFeedback.${c.raw}"
    fun shouldShow(context: Context, c: FeedbackContext) =
        !context.getSharedPreferences("futurevoice", 0).getBoolean(key(c), false)
    fun markShown(context: Context, c: FeedbackContext) =
        context.getSharedPreferences("futurevoice", 0).edit().putBoolean(key(c), true).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackSheet(context: FeedbackContext, onDismiss: () -> Unit) {
    val app = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var sendError by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(false) }

    if (sent) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.thank_you)) },
            text = { Text(stringResource(R.string.your_feedback_goes_straight_to_the_person_building_this)) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
        )
        return
    }
    ModalBottomSheet(onDismissRequest = { if (!sending) onDismiss() }) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(context.title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(stringResource(context.subtitle), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(value = text, onValueChange = { text = it },
                label = { Text(stringResource(R.string.your_feedback)) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 110.dp))
            sendError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onDismiss, enabled = !sending, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.not_now)) }
                Button(onClick = {
                    sending = true; sendError = null
                    scope.launch {
                        runCatching { send(context, text.trim()) }
                            .onSuccess { sent = true }
                            .onFailure { sendError = app.getString(R.string.feedback_couldnt_send, it.message ?: "") }
                        sending = false
                    }
                }, enabled = !sending && text.isNotBlank(), modifier = Modifier.weight(1f)) {
                    if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.send))
                }
            }
            Spacer(Modifier.size(4.dp))
        }
    }
}

/** No `rating` — the column is nullable and the sheet doesn't ask for a score. */
private suspend fun send(context: FeedbackContext, body: String) = withContext(Dispatchers.IO) {
    val auth = AuthRepository()
    val uid = auth.userId ?: throw IllegalStateException("signed out")
    val row = buildJsonObject { put("user_id", uid); put("context", context.raw); put("body", body) }
    val req = Request.Builder().url(Config.supabaseUrl.trimEnd('/') + "/rest/v1/beta_reviews")
        .header("Authorization", "Bearer ${auth.accessToken()}").header("apikey", Config.supabaseAnonKey)
        .header("Prefer", "return=minimal")
        .post(Edge.json.encodeToString(JsonObject.serializer(), row).toRequestBody("application/json".toMediaType()))
        .build()
    Edge.client.newCall(req).execute().use { r -> if (r.code !in 200..299) throw IllegalStateException("HTTP ${r.code}") }
}
