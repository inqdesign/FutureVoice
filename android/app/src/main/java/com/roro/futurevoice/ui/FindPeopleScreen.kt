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
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import com.roro.futurevoice.ui.brand.IosButton as Button
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
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.CheckCircle
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
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.nameIn
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.CoreSeal
import kotlinx.coroutines.async
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
    /** For the profile page behind the learner's own row. */
    persona: com.roro.futurevoice.talk.UserPersona? = null,
    /** The profile editor, opened from that page (the host's cover). */
    onEditProfile: () -> Unit = {},
    /** Talk on a card. [meet] persists the person — called by the host only
     *  once its gate has passed (iOS `start { onTalk(savedPerson()) }`). */
    onTalk: (person: PublicPersonaClient.PublicPersona, meet: () -> Counterpart) -> Unit,
    /** "Continue the last talk" on a card (iOS `onPickUp`), same contract as [onTalk]. */
    onPickUp: ((person: PublicPersonaClient.PublicPersona, meet: () -> Counterpart) -> Unit)? = null,
    /** Watch on a person's card: a scene of the two of them, in THEIR preset
     *  voice (iOS `FindPeopleSheet(onWatch:)`). The host gates it as a scene
     *  and calls [meet] only after the gate (iOS `startScene { onWatch(savedPerson()) }`). */
    onWatch: (meet: () -> Counterpart) -> Unit = {},
    onOpenPerson: (String) -> Unit,
    /** "Make a situation" on a card (iOS `FindPeopleSheet(onCompose:)`): the
     *  host closes this page and opens Watch's composer with the person. */
    onCompose: ((Counterpart) -> Unit)? = null,
    /** A row under "Your talks together" — the regular talk book (iOS
     *  `NavigationLink { ConversationDetailView(session:) }`). */
    onOpenTalk: (String) -> Unit = {},
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
    /** "New person" opens the guided intake first (iOS
     *  `CounterpartVoiceIntakeView`); its draft lands in the form. */
    var intake by remember { mutableStateOf(false) }
    var intakePhoto by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    /** iOS titles the form "New persona" only for the plain-form escape. */
    var editingIsNew by remember { mutableStateOf(false) }
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
    // Saveable: a talk opened from the card is a page pushed above this one,
    // and back from it must land on the card again (iOS pops to it), not on
    // the list — plain `remember` is dropped while the page is covered.
    var card by androidx.compose.runtime.saveable.rememberSaveable(
        stateSaver = androidx.compose.runtime.saveable.Saver<PublicPersonaClient.PublicPersona?, String>(
            save = { it?.let { p -> com.roro.futurevoice.net.Edge.json.encodeToString(
                PublicPersonaClient.PublicPersona.serializer(), p) } ?: "" },
            restore = { raw -> if (raw.isEmpty()) null else runCatching {
                com.roro.futurevoice.net.Edge.json.decodeFromString(
                    PublicPersonaClient.PublicPersona.serializer(), raw) }.getOrNull() },
        ),
    ) { mutableStateOf<PublicPersonaClient.PublicPersona?>(null) }
    var reloadToken by remember { mutableStateOf(0) }
    /** The learner's OWN published row. The pool leaves it out on purpose —
     *  you don't meet yourself — but this page is the only place the pool is
     *  looked at, so without it a learner could never see what they
     *  published. Null (no section at all) when unpublished OR when the read
     *  failed: "not published" and "couldn't ask" must never look alike. */
    var mine by remember { mutableStateOf<PublicPersonaClient.PublicPersona?>(null) }
    /** Your own row's page (iOS `MyProfileView`). Saveable: the profile
     *  editor covers this page, and back from it lands here again. */
    var editingProfile by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    val client = remember { PublicPersonaClient(AuthRepository()) }
    suspend fun loadPool() {
        // Capture only: a sample pool, never the network (signed out, offline).
        com.roro.futurevoice.capture.flags.WatchCaptureFlags.samplePool?.let {
            pool = it; loading = false; loadFailed = false; return
        }
        loading = true
        loadFailed = false
        // Alongside the pool, never in front of it.
        val mineRow = scope.async { runCatching { client.fetchMine(language) }.getOrNull() }
        runCatching { client.fetchPool(language) }
            .onSuccess { rows ->
                pool = rows
                syncOwnVoices(ownStore, rows)
            }
            .onFailure { loadFailed = pool.isEmpty() }
        loading = false
        mine = mineRow.await()
        // Badges last and unguarded: the page is fully usable without them,
        // so a Core outage must never keep anyone from meeting people. The
        // badge is public but the membership LIST is not — the server only
        // answers about ids we already name.
        badges = runCatching {
            // The learner's own id rides along, so their row wears the seal a
            // stranger would see on it.
            CoreClubClient(AuthRepository()).badges(
                pool.mapNotNull { it.owner_user_id } + listOfNotNull(mine?.owner_user_id), language)
        }.getOrDefault(emptyMap())
    }
    LaunchedEffect(language, reloadToken) { loadPool() }
    /** iOS `loadMine`: back from your profile page re-reads your own row
     *  only — publishing or taking down changed it, nothing else did. */
    fun refreshMine() { scope.launch { mine = runCatching { client.fetchMine(language) }.getOrNull() } }

    // Back on the list closes the page; a card or the intro is a PUSH (iOS
    // `navigationDestination` in FindPeopleSheet), popped by the host.
    NavPageBackHandler(onBack = onBack)

    if (intake) {
        CounterpartIntakeScreen(
            nativeLanguage = com.roro.futurevoice.core.UILanguage.current(context) ?: "en",
            targetLanguage = language,
            onDraft = { draft, photo ->
                intake = false
                intakePhoto = photo
                editingIsNew = draft == null
                editing = draft ?: Counterpart()
            },
            onCancel = { intake = false },
        )
        return
    }

    // The card stays drawable while it slides away after `card` is cleared.
    var lastCard by remember { mutableStateOf<PublicPersonaClient.PublicPersona?>(null) }
    card?.let { lastCard = it }
    val peopleStack: List<String> = buildList {
        add("list")
        if (editingProfile) add("profile")
        card?.let { add("card:${it.id}") }
    }
    IosNavStack(stack = peopleStack, onPop = {
        if (card != null) card = null
        else if (editingProfile) { editingProfile = false; refreshMine() }
    }) { page ->
    if (page == "profile") {
        // Your profile page, where the profile the paragraph is written
        // from sits above it (iOS `MyProfileView(onPublicChange:)`).
        MyProfileScreen(
            persona = persona,
            targetLanguage = language,
            // Publishing or taking down changes the row — re-read it on the
            // way back so the page doesn't keep the old face.
            onBack = { editingProfile = false; refreshMine() },
            onEditProfile = onEditProfile,
            onPublicChange = { refreshMine() },
        )
        return@IosNavStack
    }
    val open = lastCard
    if (page.startsWith("card:") && open != null) {
        FindPersonCard(
            person = open,
            language = language,
            bookmarked = bookmarks.contains(open.id),
            onToggleBookmark = { bookmarks = toggleBookmark(context, open.id) },
            onTalk = onTalk,
            onPickUp = onPickUp,
            onWatch = onWatch,
            onPersonSaved = { scope.launch { reloadOwn(); StoreEvents.bump() } },
            onBack = { card = null },
            onCompose = onCompose,
            onOpenTalk = onOpenTalk,
        )
        return@IosNavStack
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

    // iOS: an inset-grouped List in a sheet — "People" centred in the
    // display face with Done as a glass capsule, and `.searchable` as a
    // floating capsule at the BOTTOM that the list scrolls under.
    Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
        LazyColumn(
            Modifier.fillMaxSize().padding(horizontal = 16.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 64.dp,
                bottom = 110.dp),
        ) {
            val me = mine
            if (!searching) {
                // You, as the pool has you — the same row everyone else
                // gets, so this can't drift from what a stranger sees. Not
                // published is a state too and says so (iOS `mineSection`):
                // the section used to vanish, leaving no way to publish.
                item {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.you).uppercase(), style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        if (me != null) {
                            Icon(Icons.Filled.CheckCircle, null, tint = Color(0xFF34C759), modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(stringResource(R.string.published), style = MaterialTheme.typography.labelMedium,
                                color = Color(0xFF34C759))
                        } else {
                            Icon(Icons.Filled.VisibilityOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(stringResource(R.string.not_published), style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    FormSection(null,
                        footer = if (me != null) stringResource(R.string.this_is_how_other_learners_find_you_tap_to_change_it_or_take_211599)
                            else stringResource(R.string.publish_a_short_introduction_and_other_learners_can_practise_862528)) {
                        if (me != null) {
                            PoolRow(me, badges, emptySet(), isMine = true, onClick = { editingProfile = true })
                        } else {
                            Row(Modifier.fillMaxWidth().clickable { editingProfile = true }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                ProfileAvatar(persona?.displayName.orEmpty(), 40.dp)
                                Column(Modifier.weight(1f)) {
                                    Text(persona?.displayName.orEmpty(), style = MaterialTheme.typography.bodyLarge)
                                    Text(stringResource(R.string.other_learners_can_t_find_you_yet),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            if (!searching) {
                item {
                    FormSection(stringResource(R.string.your_people)) {
                        Row(
                            Modifier.fillMaxWidth()
                                .clickable { intake = true }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Icon(Icons.Filled.AddCircle, contentDescription = null,
                                modifier = Modifier.size(26.dp),
                                tint = MaterialTheme.colorScheme.primary)
                            Text(stringResource(R.string.new_person),
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.primary)
                        }
                        own.forEach { c ->
                            FormDivider(inset = 60.dp)
                            OwnPersonRow(c) { onOpenPerson(c.id) }
                        }
                    }
                }
            }

            // Which pool: a real learner, or someone we invented.
            item {
                Spacer(Modifier.height(36.dp))
                com.roro.futurevoice.ui.brand.IosSegmented(PoolGroup.entries.map { stringResource(it.label) },
                    PoolGroup.entries.indexOf(group), { group = PoolGroup.entries[it] },
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp))
                // The privacy sentence. It is not decoration: it says a
                // talk never reaches the person, and that the voice is a
                // stock preset read by an AI, never theirs.
                Text(stringResource(group.footer), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp))
            }

            if (searching) {
                item {
                    FormSection(null) {
                        if (results.isEmpty()) {
                            QuietRow(stringResource(
                                R.string.no_one_matches_yet_try_an_interest_a_job_or_a_city))
                        } else results.forEachIndexed { i, p ->
                            if (i > 0) RowDivider()
                            PoolRow(p, badges, bookmarks) { card = p }
                        }
                    }
                }
            } else {
                if (metHere.isNotEmpty()) {
                    item {
                        FormSection(stringResource(R.string.people_you_ve_met)) {
                            metHere.forEachIndexed { i, c ->
                                if (i > 0) RowDivider()
                                PersonListRow(
                                    name = c.name,
                                    caption = listOf(c.commonTopics, c.location)
                                        .filter { it.isNotBlank() }.joinToString(" · "),
                                    seated = badges[pool.firstOrNull { it.id == c.remoteId }
                                        ?.owner_user_id?.lowercase()]?.seated == true,
                                    bookmarked = c.remoteId != null && bookmarks.contains(c.remoteId),
                                    photoId = c.id,
                                    onClick = { openMet(c) },
                                )
                            }
                        }
                    }
                }
                if (bookmarkedNewFaces.isNotEmpty()) {
                    item {
                        FormSection(stringResource(R.string.bookmarked)) {
                            bookmarkedNewFaces.forEachIndexed { i, p ->
                                if (i > 0) RowDivider()
                                PoolRow(p, badges, bookmarks) { card = p }
                            }
                        }
                    }
                }
                item {
                    // STRANGERS, by name: that they're strangers is the
                    // point — talking to strangers is what the language
                    // is for.
                    FormSection(stringResource(R.string.strangers)) {
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
                                if (i > 0) RowDivider()
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
                    FormSection(null) {
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
        }

        // The navigation bar, over a fade of the page ground so rows slide
        // under it the way iOS's scroll edge does.
        Box(
            Modifier.fillMaxWidth().align(Alignment.TopCenter)
                .background(androidx.compose.ui.graphics.Brush.verticalGradient(
                    0.75f to AppSurfaces.ground, 1f to AppSurfaces.ground.copy(alpha = 0f)))
                .statusBarsPadding().padding(bottom = 4.dp),
        ) {
            PageSheetHeader(stringResource(R.string.people), onDone = onBack)
        }

        // The list dissolves under the capsule, the same feather the tab bar
        // sits on (iOS's scroll edge effect behind a bottom bar).
        ScrollEdgeFeather(color = AppSurfaces.ground, modifier = Modifier.align(Alignment.BottomCenter),
            ramp = 56.dp, solid = 36.dp)
        // `.searchable` on iOS 26: a floating white capsule at the bottom.
        SearchCapsule(
            query = query, onQuery = { query = it },
            placeholder = stringResource(R.string.name_interests_place),
            modifier = Modifier.align(Alignment.BottomCenter).bottomBarInsets()
                .padding(start = 28.dp, end = 28.dp, bottom = 12.dp),
        )
    }

    editing?.let { draft ->
        PersonEditor(
            person = draft,
            onSave = {
                scope.launch { ownStore.save(it); reloadOwn(); StoreEvents.bump() }
                editing = null; intakePhoto = null
            },
            onDismiss = { editing = null; intakePhoto = null },
            initialPhoto = intakePhoto,
            isNew = editingIsNew,
        )
    }
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
internal fun FindPersonCard(
    person: PublicPersonaClient.PublicPersona,
    language: String,
    bookmarked: Boolean,
    onToggleBookmark: () -> Unit,
    onTalk: (PublicPersonaClient.PublicPersona, () -> Counterpart) -> Unit,
    onPickUp: ((PublicPersonaClient.PublicPersona, () -> Counterpart) -> Unit)? = null,
    onWatch: (() -> Counterpart) -> Unit,
    onPersonSaved: () -> Unit,
    onBack: () -> Unit,
    /** Build a situation with this person (iOS `onCompose`): every person
     *  gets it from Watch. null hides the row. */
    onCompose: ((Counterpart) -> Unit)? = null,
    /** iOS shows the bookmark only for someone from the pool (`remoteId`). */
    showsBookmark: Boolean = true,
    /** A past talk's row opens its book. */
    onOpenTalk: (String) -> Unit = {},
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
    // Their own voice — the row's, never the learner's pick (iOS 2026-10-12).
    val voiceId = person.voice_preset_id.takeIf { id ->
        StockPerson.catalog.any { it.voiceId == id } || VoicePreset.isLibraryVoice(id) }
        ?: saved?.voicePresetId?.takeIf { it.isNotBlank() }
        ?: StockPerson.catalog.first().voiceId

    /** Meeting them persists the person, so sessions can link to a stable
     *  local id and they join "People you've met". Idempotent — the local id
     *  IS the remote one, and the store dedupes on `remoteId`. */
    fun persist(voice: String): Counterpart {
        val base = saved ?: person.asCounterpart(metLabel)
        val next = base.copy(voicePresetId = voice)
        saved = next
        // Not the card's scope: the gate's action usually closes this page
        // in the same frame, and a save launched on a scope being disposed
        // never runs.
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            store.save(next); onPersonSaved()
        }
        return next
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
                    if (showsBookmark) IconButton(onClick = onToggleBookmark) {
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
                // Same weight on both (iOS: two `.bordered` buttons, Watch
                // first): watching and talking are two ways in, not a main
                // action and a lesser one. Both spend, so both are gated by
                // the host — Watch as a scene, Talk as a call.
                val last = talks.firstOrNull()
                if (onPickUp != null && last != null) {
                    PickUpTalkButton(last.displayTitle ?: stringResource(R.string.conversation)) {
                        onPickUp(person.copy(voice_preset_id = voiceId)) { persist(voiceId) }
                    }
                    Spacer(Modifier.size(10.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    com.roro.futurevoice.ui.brand.IosTonalButton(
                        onClick = { onWatch { persist(voiceId) } },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text(stringResource(R.string.watch))
                    }
                    com.roro.futurevoice.ui.brand.IosTonalButton(
                        onClick = {
                            // The learner's pick wins over the pool's row.
                            onTalk(person.copy(voice_preset_id = voiceId)) { persist(voiceId) }
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Filled.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text(stringResource(R.string.talk))
                    }
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
                    // The pool's photo, adopted under the person's id (iOS
                    // `PersonBubble(name:photoId:)`) — initials only without one.
                    com.roro.futurevoice.ui.PersonBubble(person.display_name, person.id, size = 64.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(person.display_name, style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold)
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

            // Every character has its own voice — shown, not chosen.
            GroupedSectionHeader(stringResource(R.string.voice))
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.voice), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    // iOS `displayName`: the slot's name in this language.
                    Text(VoicePreset.known(voiceId)?.nameIn(language) ?: stringResource(R.string.their_own),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            GroupedFooter(stringResource(
                R.string.their_own_voice_chosen_with_their_introduction_not_a_recordi_ac2731))

            if (onCompose != null) {
                GroupedSectionSpacer()
                GroupedCard {
                    Row(Modifier.fillMaxWidth()
                        .clickable { onCompose(saved ?: person.asCounterpart(metLabel)) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.EditNote, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                        Text(stringResource(R.string.make_a_situation), style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
                GroupedFooter(stringResource(
                    R.string.something_specific_coming_up_with_them_a_talk_you_re_dreadin_18800f))
            }

            if (talks.isNotEmpty()) {
                GroupedSectionHeader(stringResource(R.string.your_talks_together))
                GroupedCard {
                    talks.forEachIndexed { i, s ->
                        if (i > 0) GroupedRowDivider(inset = false)
                        Row(Modifier.fillMaxWidth().clickable { onOpenTalk(s.id) }
                            .padding(start = 16.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(s.displayTitle ?: stringResource(R.string.conversation),
                                style = MaterialTheme.typography.bodyLarge,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(shortDateTime(s.startedAt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        FormChevron()
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
    /** Your own row wears your own face, the one the Watch map and the
     *  profile page show; a name bubble there read as a photo gone missing. */
    isMine: Boolean = false,
    onClick: () -> Unit,
) {
    PersonListRow(
        name = p.display_name,
        isMine = isMine,
        photoId = p.id,
        caption = listOf(p.occupation, p.location).filter { it.isNotBlank() }.joinToString(" · "),
        // Characters we wrote ARE their intro; a real learner's row shows the
        // three facets a stranger has any business seeing.
        caption2 = if (p.isRealUser) p.interests else p.intro,
        caption2Lines = if (p.isRealUser) 1 else 2,
        // The seal is a statement about TODAY, so a row the server no longer
        // describes must draw nothing.
        seated = badges[p.owner_user_id?.lowercase()]?.seated == true,
        bookmarked = bookmarks.contains(p.id),
        onClick = onClick,
    )
}

/** One person in a card, as iOS's `NavigationLink` row: a 44 pt initials
 *  bubble, the name, up to two `.caption` lines, and the list's chevron. */
@Composable
private fun PersonListRow(
    name: String,
    caption: String = "",
    caption2: String = "",
    caption2Lines: Int = 1,
    seated: Boolean = false,
    bookmarked: Boolean = false,
    isMine: Boolean = false,
    /** The pool's learner photo, adopted under the person's id. */
    photoId: String? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(start = 16.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (isMine) ProfileAvatar(name, 44.dp)
        else com.roro.futurevoice.ui.PersonBubble(name, photoId, size = 44.dp)
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
                Text(it, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            caption2.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = caption2Lines, overflow = TextOverflow.Ellipsis)
            }
        }
        FormChevron()
    }
}

/** One of the learner's own people: their photo (or initials) at 40 pt,
 *  name and relationship — iOS `ownSection`'s row. */
@Composable
private fun OwnPersonRow(c: Counterpart, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(start = 16.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PersonBubble(c.name, c.id, size = 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(c.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            if (c.relationship.isNotBlank()) Text(c.relationship, style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        FormChevron()
    }
}

/** iOS 26's separator between person rows: starts under the bubble's
 *  centre-right and stops short of the trailing edge. */
@Composable
private fun RowDivider() {
    androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 33.dp, end = 16.dp),
        thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
}

/** iOS 26 `.searchable` in a sheet: a white capsule floating over the list,
 *  a magnifier, the prompt as placeholder, a soft shadow. */
@Composable
private fun SearchCapsule(query: String, onQuery: (String) -> Unit, placeholder: String,
                          modifier: Modifier = Modifier) {
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
    Row(
        modifier.fillMaxWidth().height(48.dp)
            .shadow(if (dark) 0.dp else 14.dp, CircleShape,
                ambientColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.12f),
                spotColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.12f))
            .background(if (dark) androidx.compose.ui.graphics.Color(0xFF2C2C2E)
                else androidx.compose.ui.graphics.Color.White, CircleShape)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(22.dp),
            tint = MaterialTheme.colorScheme.onSurface)
        androidx.compose.foundation.text.BasicTextField(
            value = query, onValueChange = onQuery, singleLine = true, textStyle = style,
            cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
            modifier = Modifier.weight(1f),
            decorationBox = { inner ->
                Box {
                    if (query.isEmpty()) Text(placeholder, style = style,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f), maxLines = 1)
                    inner()
                }
            },
        )
        if (query.isNotEmpty()) {
            Icon(Icons.Filled.Cancel, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                modifier = Modifier.size(20.dp).clip(CircleShape).clickable { onQuery("") })
        }
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

/**
 * Every character speaks in its OWN voice (iOS `syncOwnVoices`): a met
 * stranger the learner once re-voiced goes back to the voice its author
 * picked (and takes the row's greeting when theirs is empty). True when a
 * row on file changed.
 */
internal suspend fun syncOwnVoices(ownStore: CounterpartStore, rows: List<PublicPersonaClient.PublicPersona>): Boolean {
    val byId = rows.associateBy { it.id }
    var changed = false
    for (c in ownStore.load()) {
        val row = c.remoteId?.let { byId[it] } ?: continue
        val v = row.voice_preset_id
        if (StockPerson.catalog.none { it.voiceId == v } && !VoicePreset.isLibraryVoice(v)) continue
        var fixed = c.copy(voicePresetId = v)
        val g = row.greeting.orEmpty()
        if (g.isNotEmpty() && fixed.greeting(row.language).isEmpty()) fixed = fixed.withGreeting(g, row.language)
        if (fixed.voicePresetId == c.voicePresetId &&
            fixed.greeting(row.language) == c.greeting(row.language)) continue
        ownStore.save(fixed)
        changed = true
    }
    return changed
}

// MARK: - Bookmarks (local only)

/** Bookmarking someone has zero effect on them — no notification, no shared
 *  record. That is the whole social contract of the feature, so the ids never
 *  leave the phone. Same key as iOS. */
private const val BOOKMARKS_KEY = "futurevoice.personaBookmarks"

internal fun bookmarkedIds(context: android.content.Context): Set<String> =
    context.getSharedPreferences("futurevoice", 0)
        .getStringSet(BOOKMARKS_KEY, emptySet())?.toSet() ?: emptySet()

internal fun toggleBookmark(context: android.content.Context, remoteId: String): Set<String> {
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
internal fun PublicPersonaClient.PublicPersona.asCounterpart(metLabel: String) = Counterpart(
    id = id,
    name = display_name,
    relationship = metLabel,
    location = location,
    background = intro,
    conversationStyle = conversation_style,
    commonTopics = interests,
    voicePresetId = voice_preset_id.takeIf { v ->
        StockPerson.catalog.any { it.voiceId == v } || VoicePreset.isLibraryVoice(v) }
        ?: StockPerson.catalog.first().voiceId,
    remoteId = id,
    intro = intro,
    personaKind = if (isRealUser) "user" else "character",
    greetingByLanguage = greeting?.trim()?.takeIf { it.isNotEmpty() }?.let { mapOf(language to it) }.orEmpty(),
)

/** The reverse, for a met person the pool no longer carries. */
internal fun Counterpart.asPublicPersona(language: String) = PublicPersonaClient.PublicPersona(
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
