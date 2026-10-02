package com.roro.futurevoice.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.roro.futurevoice.R

/**
 * The display label for a preset chip. The STORED value stays English — it is
 * prompt material and the selection key, so localizing it would un-select
 * every saved chip — but on screen it reads in the app language, as iOS's
 * `Text(LocalizedStringKey(tag))` does. A learner's own typed tag has no
 * entry and is shown as written.
 */
private val PRESET_LABELS: Map<String, Int> = mapOf(
    "AI / tech" to R.string.ai_tech, "parenting" to R.string.parenting,
    "language learning" to R.string.language_learning, "music" to R.string.music,
    "podcasts" to R.string.podcasts, "cooking" to R.string.cooking,
    "travel" to R.string.travel_f7956b, "sports" to R.string.sports,
    "fashion" to R.string.fashion, "finance" to R.string.finance,
    "science" to R.string.science, "art" to R.string.art,
    "Work meetings" to R.string.work_meetings, "Client calls" to R.string.client_calls,
    "Kita / school" to R.string.kita_school, "Doctor / clinic" to R.string.doctor_clinic,
    "Travel" to R.string.travel_22fb76, "Online shopping" to R.string.online_shopping,
    "Customer service" to R.string.customer_service, "Streaming / shows" to R.string.streaming_shows,
    "Reading articles" to R.string.reading_articles, "Daily small talk" to R.string.daily_small_talk,
)

@Composable
internal fun presetLabel(tag: String): String = PRESET_LABELS[tag]?.let { stringResource(it) } ?: tag
