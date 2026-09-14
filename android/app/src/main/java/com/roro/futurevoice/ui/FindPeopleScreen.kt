package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.CoreSeal
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/**
 * Find people — the ONE people page (`FindPeopleSheet`). Your own people on
 * top, then STRANGERS you can practise with, like meeting someone at a
 * language school: everyone unmet is shown, because that they're strangers
 * is the point — talking to strangers is what the language is for. There is
 * no daily rotation and no six-a-day handful; a rotation hid most of the
 * pool to manufacture a return visit, and the pool is the reason to come.
 *
 * The pool is split two ways and the two are NOT interchangeable to a
 * learner: a real person who published an introduction, and someone we
 * invented. One list would quietly ask them to guess which is which, and the
 * privacy sentence under the segmented control is only true of one of them.
 *
 * Bookmarks are local only. Nothing a learner does here reaches the
 * persona's author: no notification, no shared record.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FindPeopleScreen(
    language: String,
    onTalk: (PublicPersonaClient.PublicPersona) -> Unit,
    onOpenPerson: (String) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ownStore = remember { CounterpartStore.shared(context) }
    // Your own people, on top — the half that used to be its own sheet, so
    // one page answers every "who can I talk to".
    var own by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    // Strangers already met: they are ordinary Counterparts with `remoteId`
    // set, which is exactly what keeps them OUT of Watch's stories row.
    var met by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var editing by remember { mutableStateOf<Counterpart?>(null) }
    suspend fun reloadOwn() {
        val all = ownStore.load()
        own = all.filter { it.remoteId == null }
        met = all.filter { it.remoteId != null }.sortedByDescending { it.updatedAt }
    }
    LaunchedEffect(Unit) { reloadOwn() }

    var pool by remember { mutableStateOf<List<PublicPersonaClient.PublicPersona>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var loadFailed by remember { mutableStateOf(false) }
    var badges by remember { mutableStateOf<Map<String, CoreClubClient.Badge>>(emptyMap()) }
    var group by remember { mutableStateOf(PoolGroup.USER) }
    var bookmarks by remember { mutableStateOf(bookmarkedIds(context)) }
    /** The stranger whose card is open, if any. */
    var card by remember { mutableStateOf<PublicPersonaClient.PublicPersona?>(null) }
    var reloadToken by remember { mutableStateOf(0) }

    val client = remember { PublicPersonaClient(AuthRepository()) }
    suspend fun loadPool() {
        loading = true
        loadFailed = false
        runCatching { client.fetchPool(language) }
            .onSuccess { pool = it }
            .onFailure { loadFailed = pool.isEmpty() }
        loading = false
        // Badges last and unguarded: the page is fully usable without them,
        // so a Core outage must never keep anyone from meeting people. The
        // badge is public but the membership LIST is not — the server only
        // answers about ids we already name.
        badges = runCatching {
            CoreClubClient(AuthRepository()).badges(pool.mapNotNull { it.owner_user_id }, language)
        }.getOrDefault(emptyMap())
    }
    LaunchedEffect(language, reloadToken) { loadPool() }

    // Back closes the card first — it is a page, not a sheet over this one.
    androidx.activity.compose.BackHandler { if (card != null) card = null else onBack() }

    val open = card
    if (open != null) {
        FindPersonCard(
            person = open,
            language = language,
            seated = badges[open.owner_user_id?.lowercase()]?.seated == true,
            bookmarked = bookmarks.contains(open.id),
            onToggleBookmark = { bookmarks = toggleBookmark(context, open.id) },
            onTalk = { onTalk(it) },
            onPersonSaved = { scope.launch { reloadOwn(); StoreEvents.bump() } },
            onBack = { card = null },
        )
        return
    }

    val groupPool = pool.filter { PoolGroup.of(it) == group }
    val metIds = met.mapNotNull { it.remoteId }.toSet()
    // Each tab stays a complete little world instead of repeating names.
    val metHere = met.filter { PoolGroup.of(it) == group }
    val bookmarkedNewFaces = groupPool.filter { bookmarks.contains(it.id) && it.id !in metIds }
    // Everyone in the pool not met and not bookmarked — the WHOLE list, in
    // the pool's own order.
    val strangers = groupPool.filter { it.id !in metIds && it.id !in bookmarks }
    val searching = query.isNotBlank()
    val results = if (searching) client.search(query, groupPool) else emptyList()

    /** Open a met person's card off the pool row that minted them; a row the
     *  pool no longer carries still opens, rebuilt from what was saved. */
    fun openMet(c: Counterpart) {
        card = pool.firstOrNull { it.id == c.remoteId } ?: c.asPublicPersona(language)
    }

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
                label = { Text(stringResource(R.string.name_interests_place)) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            )
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())

            LazyColumn(Modifier.fillMaxWidth()) {
                if (!searching) {
                    item {
                        GroupedSectionHeader(stringResource(R.string.your_people))
                        GroupedCard {
                            Row(
                                Modifier.fillMaxWidth()
                                    .clickable { editing = Counterpart() }
                                    .padding(horizontal = 16.dp, vertical = 14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Icon(Icons.Filled.AddCircle, contentDescription = null,
                                    modifier = Modifier.size(24.dp),
                                    tint = MaterialTheme.colorScheme.primary)
                                Text(stringResource(R.string.new_person),
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.Medium,
                                    color = MaterialTheme.colorScheme.primary)
                            }
                            own.forEach { c ->
                                GroupedRowDivider(inset = false)
                                PersonListRow(
                                    name = c.name,
                                    caption = c.relationship,
                                    onClick = { onOpenPerson(c.id) },
                                )
                            }
                        }
                    }
                }

                // Which pool: a real learner, or someone we invented.
                item {
                    GroupedSectionSpacer()
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        PoolGroup.entries.forEachIndexed { i, g ->
                            SegmentedButton(
                                selected = group == g,
                                onClick = { group = g },
                                shape = SegmentedButtonDefaults.itemShape(i, PoolGroup.entries.size),
                            ) { Text(stringResource(g.label)) }
                        }
                    }
                    // The privacy sentence. It is not decoration: it says a
                    // talk never reaches the person, and that the voice is a
                    // stock preset read by an AI, never theirs.
                    GroupedFooter(stringResource(group.footer))
                }

                if (searching) {
                    item {
                        GroupedSectionSpacer()
                        GroupedCard {
                            if (results.isEmpty()) {
                                QuietRow(stringResource(
                                    R.string.no_one_matches_yet_try_an_interest_a_job_or_a_city))
                            } else results.forEachIndexed { i, p ->
                                if (i > 0) GroupedRowDivider(inset = false)
                                PoolRow(p, badges, bookmarks) { card = p }
                            }
                        }
                    }
                } else {
                    if (metHere.isNotEmpty()) {
                        item {
                            GroupedSectionHeader(stringResource(R.string.people_you_ve_met))
                            GroupedCard {
                                metHere.forEachIndexed { i, c ->
                                    if (i > 0) GroupedRowDivider(inset = false)
                                    PersonListRow(
                                        name = c.name,
                                        caption = listOf(c.commonTopics, c.location)
                                            .filter { it.isNotBlank() }.joinToString(" · "),
                                        seated = badges[pool.firstOrNull { it.id == c.remoteId }
                                            ?.owner_user_id?.lowercase()]?.seated == true,
                                        bookmarked = c.remoteId != null && bookmarks.contains(c.remoteId),
                                        onClick = { openMet(c) },
                                    )
                                }
                            }
                        }
                    }
                    if (bookmarkedNewFaces.isNotEmpty()) {
                        item {
                            GroupedSectionHeader(stringResource(R.string.bookmarked))
                            GroupedCard {
                                bookmarkedNewFaces.forEachIndexed { i, p ->
                                    if (i > 0) GroupedRowDivider(inset = false)
                                    PoolRow(p, badges, bookmarks) { card = p }
                                }
                            }
                        }
                    }
                    item {
                        // STRANGERS, by name: that they're strangers is the
                        // point — talking to strangers is what the language
                        // is for.
                        GroupedSectionHeader(stringResource(R.string.strangers))
                        GroupedCard {
                            when {
                                loading && pool.isEmpty() -> Row(
                                    Modifier.fillMaxWidth().padding(16.dp),
                                    horizontalArrangement = Arrangement.Center,
                                ) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }

                                loadFailed -> Column(Modifier.padding(16.dp)) {
                                    Text(stringResource(
                                        R.string.couldn_t_load_people_check_your_connection),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    TextButton(onClick = { reloadToken++ },
                                        modifier = Modifier.padding(top = 4.dp)) {
                                        Text(stringResource(R.string.retry))
                                    }
                                }

                                // Loaded fine, but this tab's pool for the
                                // target language has nobody yet — say so
                                // instead of a silent blank.
                                groupPool.isEmpty() -> QuietRow(stringResource(
                                    R.string.no_one_here_yet_for_this_language_check_back_soon))

                                else -> strangers.forEachIndexed { i, p ->
                                    if (i > 0) GroupedRowDivider(inset = false)
                                    PoolRow(p, badges, bookmarks) { card = p }
                                }
                            }
                        }
                    }
                }

                // What the indigo seal on a row means. Drawn only when one is
                // actually on screen: explaining something nobody in this
                // pool has is an ad.
                if (badges.values.any { it.seated }) {
                    item {
                        GroupedSectionSpacer()
                        GroupedCard {
                            Row(Modifier.fillMaxWidth().padding(16.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Box(Modifier.padding(top = 3.dp)) { CoreSeal() }
                                Column {
                                    Text(stringResource(R.string.the_core),
                                        style = MaterialTheme.typography.bodyLarge)
                                    Text(stringResource(
                                        R.string.the_seal_marks_the_100_people_speaking_most_days_right_now_a_7bf2ab),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }

    editing?.let { draft ->
        PersonEditor(
            person = draft,
            onSave = {
                scope.launch { ownStore.save(it); reloadOwn(); StoreEvents.bump() }
                editing = null
            },
            onDismiss = { editing = null },
        )
    }
}

// MARK: - Person card

/**
 * One public persona, full screen: who they are, a bookmark, the voice the
 * LEARNER picked for them, the talks already had with them, and the way in.
 *
 * Their voice is never a clone and never their own — there isn't one to
 * have. The pick is saved onto the Counterpart, so it wins from then on.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FindPersonCard(
    person: PublicPersonaClient.PublicPersona,
    language: String,
    seated: Boolean,
    bookmarked: Boolean,
    onToggleBookmark: () -> Unit,
    onTalk: (PublicPersonaClient.PublicPersona) -> Unit,
    onPersonSaved: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { CounterpartStore.shared(context) }
    val metLabel = stringResource(R.string.met_on_nawana)
    // The SAVED row when one exists — it carries every earlier voice pick,
    // which is what makes the pick stick.
    var saved by remember(person.id) { mutableStateOf<Counterpart?>(null) }
    var talks by remember(person.id) { mutableStateOf<List<Session>>(emptyList()) }
    LaunchedEffect(person.id, language) {
        saved = store.load().firstOrNull { it.remoteId == person.id || it.id == person.id }
        talks = SessionStore.shared(context).load(language)
            .filter { it.counterpartId == person.id && it.endedAt != null }
            .sortedByDescending { it.startedAt }
    }
    val voiceId = saved?.voicePresetId?.takeIf { it.isNotBlank() }
        ?: person.voice_preset_id.takeIf { id -> StockPerson.catalog.any { it.voiceId == id } }
        ?: StockPerson.catalog.first().voiceId

    /** Meeting them persists the person, so sessions can link to a stable
     *  local id and they join "People you've met". Idempotent — the local id
     *  IS the remote one, and the store dedupes on `remoteId`. */
    fun persist(voice: String) {
        val base = saved ?: person.asCounterpart(metLabel)
        val next = base.copy(voicePresetId = voice)
        saved = next
        scope.launch { store.save(next); onPersonSaved() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(onClick = onToggleBookmark) {
                        Icon(
                            if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                            contentDescription = stringResource(R.string.bookmark),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
            )
        },
        bottomBar = {
            Column(Modifier.background(AppSurfaces.ground).bottomBarInsets()
                .padding(horizontal = 20.dp, vertical = 10.dp)) {
                Button(
                    onClick = {
                        persist(voiceId)
                        // The learner's pick wins over the pool's row.
                        onTalk(person.copy(voice_preset_id = voiceId))
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                    Text(stringResource(R.string.talk))
                }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
            .verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            GroupedSectionSpacer()
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    PersonBubble(person.display_name, 64.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(person.display_name, style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold)
                            if (seated) CoreSeal()
                        }
                        if (person.location.isNotBlank()) {
                            Text(person.location, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                // Written characters ARE their intro — that paragraph is the
                // reason to talk to them. A real learner's "intro" is their
                // onboarding profile, written for a different purpose and
                // never meant to be browsed, so their card stays at who and
                // where and what they're into. Everything else still goes to
                // the model, so the conversation is no thinner for it.
                if (!person.isRealUser && person.intro.isNotBlank()) {
                    GroupedRowDivider(inset = false)
                    Text(person.intro, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(16.dp))
                }
            }

            if (person.interests.isNotBlank()) {
                GroupedSectionHeader(stringResource(R.string.topics))
                GroupedCard {
                    Text(person.interests, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(16.dp))
                }
            }

            GroupedSectionHeader(stringResource(R.string.voice))
            GroupedCard {
                StockPerson.catalog.forEachIndexed { i, v ->
                    if (i > 0) GroupedRowDivider(inset = false)
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(selected = voiceId == v.voiceId,
                                onClick = { persist(v.voiceId) })
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        RadioButton(selected = voiceId == v.voiceId, onClick = null)
                        Text(v.identity, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            GroupedFooter(stringResource(
                R.string.not_their_real_voice_an_ai_speaks_their_words_in_a_voice_you_e838ec))

            if (talks.isNotEmpty()) {
                GroupedSectionHeader(stringResource(R.string.your_talks_together))
                GroupedCard {
                    talks.forEachIndexed { i, s ->
                        if (i > 0) GroupedRowDivider(inset = false)
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Text(s.displayTitle ?: stringResource(R.string.conversation),
                                style = MaterialTheme.typography.bodyLarge,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(shortDateTime(s.startedAt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

// MARK: - Rows

/** A pool row: who they are, the seal if they hold a seat, the bookmark. */
@Composable
private fun PoolRow(
    p: PublicPersonaClient.PublicPersona,
    badges: Map<String, CoreClubClient.Badge>,
    bookmarks: Set<String>,
    onClick: () -> Unit,
) {
    PersonListRow(
        name = p.display_name,
        caption = listOf(p.occupation, p.location).filter { it.isNotBlank() }.joinToString(" · "),
        // Characters we wrote ARE their intro; a real learner's row shows the
        // three facets a stranger has any business seeing.
        caption2 = if (p.isRealUser) p.interests else p.intro,
        // The seal is a statement about TODAY, so a row the server no longer
        // describes must draw nothing.
        seated = badges[p.owner_user_id?.lowercase()]?.seated == true,
        bookmarked = bookmarks.contains(p.id),
        onClick = onClick,
    )
}

/** One person, in a card: initials bubble, name, up to two quiet lines. */
@Composable
private fun PersonListRow(
    name: String,
    caption: String = "",
    caption2: String = "",
    seated: Boolean = false,
    bookmarked: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PersonBubble(name, 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(name, style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (seated) CoreSeal()
                if (bookmarked) {
                    Icon(Icons.Filled.Bookmark, contentDescription = null,
                        modifier = Modifier.size(12.dp),
                        tint = MaterialTheme.colorScheme.primary)
                }
            }
            caption.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            caption2.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** iOS `PersonBubble` — initials in a tinted, ringed circle. */
@Composable
private fun PersonBubble(name: String, size: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier.size(size)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape)
            .border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.35f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            initials(name),
            style = if (size >= 56.dp) MaterialTheme.typography.titleMedium
            else MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

/** An explanatory line where a row would be — same insets as a real row. */
@Composable
private fun QuietRow(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(16.dp))
}

// MARK: - The two pools

/**
 * The pools Find people shows behind its tabs. A published learner is a
 * "user" whatever `kind` says — ownership is the fact.
 */
private enum class PoolGroup(val raw: String, val label: Int, val footer: Int) {
    USER("user", R.string.people,
        R.string.other_learners_who_published_an_introduction_talking_with_so_5df6d6),
    CHARACTER("character", R.string.characters,
        R.string.people_we_invented_to_practice_with_each_one_in_the_middle_o_8d542b);

    companion object {
        fun of(p: PublicPersonaClient.PublicPersona) = if (p.isRealUser) USER else CHARACTER
        fun of(c: Counterpart) = if ((c.personaKind ?: "user") == "user") USER else CHARACTER
    }
}

// MARK: - Bookmarks (local only)

/** Bookmarking someone has zero effect on them — no notification, no shared
 *  record. That is the whole social contract of the feature, so the ids never
 *  leave the phone. Same key as iOS. */
private const val BOOKMARKS_KEY = "futurevoice.personaBookmarks"

private fun bookmarkedIds(context: android.content.Context): Set<String> =
    context.getSharedPreferences("futurevoice", 0)
        .getStringSet(BOOKMARKS_KEY, emptySet())?.toSet() ?: emptySet()

private fun toggleBookmark(context: android.content.Context, remoteId: String): Set<String> {
    val next = bookmarkedIds(context).toMutableSet()
    if (!next.add(remoteId)) next.remove(remoteId)
    context.getSharedPreferences("futurevoice", 0).edit()
        .putStringSet(BOOKMARKS_KEY, next).apply()
    return next
}

// MARK: - Materializing a persona

/**
 * A remote persona as a local `Counterpart`, so the whole existing machinery
 * just works. The local id IS the remote one, so minting is idempotent and a
 * re-tap can't file a twin.
 */
private fun PublicPersonaClient.PublicPersona.asCounterpart(metLabel: String) = Counterpart(
    id = id,
    name = display_name,
    relationship = metLabel,
    location = location,
    background = intro,
    conversationStyle = conversation_style,
    commonTopics = interests,
    voicePresetId = voice_preset_id.takeIf { v -> StockPerson.catalog.any { it.voiceId == v } }
        ?: StockPerson.catalog.first().voiceId,
    remoteId = id,
    intro = intro,
    personaKind = if (isRealUser) "user" else "character",
)

/** The reverse, for a met person the pool no longer carries. */
private fun Counterpart.asPublicPersona(language: String) = PublicPersonaClient.PublicPersona(
    id = remoteId ?: id,
    // Ownership is what decides the tab, and a met row remembers its kind.
    owner_user_id = if ((personaKind ?: "user") == "user") (remoteId ?: id) else null,
    display_name = name,
    intro = intro.ifBlank { background },
    location = location,
    occupation = "",
    interests = commonTopics,
    conversation_style = conversationStyle,
    language = language,
    voice_preset_id = voicePresetId,
    kind = personaKind,
)

private fun shortDateTime(at: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
        .format(Date(at))
