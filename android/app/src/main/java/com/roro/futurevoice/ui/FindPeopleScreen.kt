package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.ui.brand.CoreSeal
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.DiscoverRow

/**
 * Find people — the ONE people page (`FindPeopleSheet`). Below your own
 * people sit STRANGERS you can practise with, like meeting someone at a
 * language school: everyone unmet is shown, because that they're strangers
 * is the point — talking to strangers is what the language is for.
 *
 * Bookmarks are local only. Nothing a learner does here reaches the
 * persona's author: no notification, no shared record.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FindPeopleScreen(
    language: String,
    onTalk: (PublicPersonaClient.PublicPersona) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    var pool by remember { mutableStateOf<List<PublicPersonaClient.PublicPersona>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var badges by remember { mutableStateOf<Map<String, CoreClubClient.Badge>>(emptyMap()) }
    var error by remember { mutableStateOf<String?>(null) }
    val client = remember { PublicPersonaClient(AuthRepository()) }
    LaunchedEffect(language) {
        loading = true
        runCatching { client.fetchPool(language) }
            .onSuccess { pool = it }
            .onFailure { error = it.message }
        loading = false
        // The badge is public but the membership LIST is not — the server
        // only answers about ids we already name.
        badges = CoreClubClient(AuthRepository())
            .badges(pool.mapNotNull { it.owner_user_id }, language)
    }
    val shown = if (query.isBlank()) pool else client.search(query, pool)

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.people)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
            .padding(horizontal = 20.dp)) {
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                label = { Text(stringResource(R.string.find_people)) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            )
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            Text(stringResource(R.string.strangers),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(vertical = 8.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(shown.size) { i ->
                    val p = shown[i]
                    DiscoverRow(
                        title = p.display_name,
                        // A real learner's intro is whatever they typed into
                        // onboarding, for onboarding's purposes — it is not a
                        // profile, and putting it on a browsable card exposes
                        // things like who lives in their house. Their row
                        // shows the three facets a stranger has any business
                        // seeing; the rest still reaches the model, so the
                        // conversation loses nothing. Characters we wrote ARE
                        // their intro.
                        caption = listOf(p.occupation, p.location)
                            .filter { it.isNotBlank() }.joinToString(" · "),
                        caption2 = if (p.isRealUser) p.interests else p.intro,
                        icon = Icons.Filled.Person,
                        accent = Books.talks,
                        onClick = { onTalk(p) },
                        // The seal is a statement about TODAY, so a row the
                        // server no longer describes must draw nothing.
                        trailing = if (badges[p.owner_user_id?.lowercase()]?.seated == true) {
                            @Composable { CoreSeal() }
                        } else null,
                    )
                }
            }
        }
    }
}
