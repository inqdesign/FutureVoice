package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * "Meet other learners" — the one look at the mirrored intro before anything
 * about this learner reaches the Find-people pool (`PublicIntroPreviewSheet`).
 *
 * The onboarding profile was written for the learner's OWN fluent self, and
 * until this sheet it was published as-is on every launch, family line and
 * free notes included, without the author ever seeing the paragraph. Now the
 * paragraph is shown first, exactly as a stranger's phone would speak it, and
 * one of three things happens:
 *  - **Publish** — the mirror goes up, and from then on follows profile edits
 *    (`AUTO_APPROVED_KEY`).
 *  - **Edit first** — the public-intro editor, seeded with this paragraph;
 *    publishing there makes the row hand-managed (`MANUAL_INTRO_KEY`).
 *  - **Not now** — nothing is published, and a row an older build put up
 *    unasked comes down (`MANUAL_INTRO_KEY` + withdraw).
 *
 * Raised from the Watch tab — the place where the pool is met — never on the
 * first landing after setup.
 *
 * [onPublish] runs the publish on a scope that outlives the sheet and answers
 * whether the row is up; [onDecline] likewise owns the withdraw, which must
 * not be cancelled by the sheet going away.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublicIntroPreviewSheet(
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    onPublish: suspend () -> Boolean,
    onEditFirst: () -> Unit,
    onDecline: () -> Unit,
    onDismiss: () -> Unit,
) {
    val p = persona ?: UserPersona()
    val intro = remember(p) { PublicPersonaClient.composedIntro(p) }
    val languageName = LanguageCatalog.ownName(targetLanguage, nativeLanguage)
    val scope = rememberCoroutineScope()
    var publishing by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    // A publish in flight can't be swiped away half-done.
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { !publishing },
    )
    LaunchedEffect(Unit) { Analytics.capture("public_intro_preview_shown") }

    ModalBottomSheet(
        onDismissRequest = { if (!publishing) onDismiss() },
        sheetState = sheetState,
        containerColor = AppSurfaces.ground,
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                .bottomBarInsets().padding(horizontal = 16.dp).padding(bottom = 24.dp),
        ) {
            Text(
                stringResource(R.string.meet_other_learners),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )

            GroupedSectionHeader(stringResource(R.string.what_they_d_hear))
            GroupedCard {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    ProfileAvatar(initials = p.displayName, size = 44.dp)
                    Column {
                        Text(p.displayName, style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold)
                        val place = listOf(p.city, p.country).filter { it.isNotEmpty() }.joinToString(", ")
                        if (place.isNotEmpty()) {
                            Text(place, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                GroupedRowDivider(inset = false)
                Text(intro, style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp))
            }
            GroupedFooter(stringResource(
                R.string.other_learners_could_practice_with_an_ai_playing_this_in_a_s_5732d4,
                languageName))

            GroupedSectionSpacer()
            Button(
                onClick = {
                    publishing = true; failed = false
                    scope.launch {
                        val ok = onPublish()
                        publishing = false
                        if (ok) {
                            Analytics.capture("public_intro_preview_published")
                            onDismiss()
                        } else failed = true
                    }
                },
                enabled = !publishing,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (publishing) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary)
                } else Text(stringResource(R.string.publish))
            }
            OutlinedButton(
                onClick = onEditFirst,
                enabled = !publishing,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) { Text(stringResource(R.string.edit_first)) }
            TextButton(
                onClick = {
                    Analytics.capture("public_intro_preview_declined")
                    onDecline()
                },
                enabled = !publishing,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) { Text(stringResource(R.string.not_now)) }
            if (failed) {
                Text(
                    stringResource(R.string.couldn_t_publish_check_your_connection_and_try_again),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 6.dp),
                )
            } else {
                GroupedFooter(stringResource(R.string.you_can_change_or_take_this_down_any_time_in_me_find_people))
            }
        }
    }
}
