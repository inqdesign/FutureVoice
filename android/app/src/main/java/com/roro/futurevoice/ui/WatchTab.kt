package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.People
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.graphicsLayer
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Symbols

/**
 * A situation idea tapped on a person's page (iOS `ComposerConfig.situation`,
 * 2026-09-30): the People page closes and the Watch tab opens the writing door
 * with that person and that line written in. Parked here because the page and
 * the tab are different branches of the root.
 */
internal object WatchComposeRequest {
    val pending = kotlinx.coroutines.flow.MutableStateFlow<Pair<Counterpart, String>?>(null)
}

/**
 * The Watch header's half of the map (iOS `WatchTab` toolbar): the lens and
 * the saved-situations sheet are chosen up there and drawn down here.
 */
internal object WatchSky {
    val lens = kotlinx.coroutines.flow.MutableStateFlow(PeopleSky.Lens.ALL)
    val showingSaved = kotlinx.coroutines.flow.MutableStateFlow(false)
}

/**
 * Watch — simulate a specific situation BEFORE it happens (iOS `WatchTab`).
 * Since 1.1.8 (iOS fe83c0f1) the tab IS the people map ([PeopleSkyMap]): a
 * saved situation is almost never played again, but the people in a
 * learner's life come back. A tap on someone opens their card; "New
 * situation" opens the writing door; every situation made before the map
 * lives in the header's list sheet.
 *
 * Minting a scenario PLAYS it. A saved scenario is a reusable TEMPLATE:
 * tapping its card opens it in edit mode, whose CTA writes a fresh take.
 */
@Composable
internal fun WatchTabBody(
    language: String,
    enabled: Boolean,
    onWatch: (String) -> Unit,
    meName: String = "",
    /** The learner in the middle — their profile. */
    onOpenProfile: () -> Unit = {},
    /** Someone on the map — their card, with the pool row when they came from it. */
    onOpenPerson: (Counterpart, com.roro.futurevoice.net.PublicPersonaClient.PublicPersona?) -> Unit = { _, _ -> },
) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val store = remember { ScenarioStore.shared(context) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    /** Which door the composer opens on, when it is open. */
    var composing by remember { mutableStateOf<ComposerMode?>(null) }
    /** The person a composed scene is scoped to, if any. */
    var withPerson by remember { mutableStateOf<Counterpart?>(null) }
    /** Everyone on file — own people and strangers met. */
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    /** The saved scenario open in the composer's EDIT mode, if any. */
    var editingScenario by remember { mutableStateOf<Scenario?>(null) }
    /** The line the writing door opens with — an idea picked on a person's page. */
    var situationPrefill by remember { mutableStateOf("") }
    val lens by WatchSky.lens.collectAsStateWithLifecycle()
    val showingSaved by WatchSky.showingSaved.collectAsStateWithLifecycle()
    /** Find-people strangers, for the map's outer ring. */
    var poolRows by remember { mutableStateOf<List<com.roro.futurevoice.net.PublicPersonaClient.PublicPersona>>(emptyList()) }
    /** Talks per person (sessions aren't published). */
    var talksByPerson by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    /** The map is drawn once the pool is in, so nobody shifts when it lands. */
    var skyReady by remember { mutableStateOf(false) }
    val composeRequest by WatchComposeRequest.pending.collectAsStateWithLifecycle()
    LaunchedEffect(composeRequest) {
        val (person, line) = composeRequest ?: return@LaunchedEffect
        WatchComposeRequest.pending.value = null
        editingScenario = null
        withPerson = person; situationPrefill = line; composing = ComposerMode.CUSTOM
    }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        scenarios = store.load(language)
        people = CounterpartStore.shared(context).load()
        talksByPerson = com.roro.futurevoice.data.SessionStore.shared(context).load(language)
            .mapNotNull { it.counterpartId }.groupingBy { it }.eachCount()
    }
    // The map is shown once the pool is IN (or truly failed).
    LaunchedEffect(language) {
        val rows = com.roro.futurevoice.capture.flags.WatchCaptureFlags.samplePool
            ?: runCatching {
                com.roro.futurevoice.net.PublicPersonaClient(com.roro.futurevoice.data.AuthRepository())
                    .fetchPool(language)
            }.getOrNull()
        if (rows != null) {
            poolRows = rows
            val ownStore = CounterpartStore.shared(context)
            if (syncOwnVoices(ownStore, rows)) people = ownStore.load()
        }
        skyReady = true
    }
    LaunchedEffect(Unit) {
        // A pool that never answers must not leave the tab blank.
        kotlinx.coroutines.delay(2500)
        skyReady = true
    }
    val live = scenarios
        .filter { it.archivedAt == null && it.isMeeting != true && it.isTopic != true }
        .sortedByDescending { it.lastUsedAt ?: it.createdAt }

    val metLabel = stringResource(R.string.met_on_nawana)
    val nodes = remember(people, poolRows, scenarios, talksByPerson) {
        skyNodes(people, poolRows, scenarios, talksByPerson, metLabel)
    }

    Box(Modifier.fillMaxSize()) {
        val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
        // Level with the floating tab bar's top, plus iOS's 16 pt.
        val floatBottom = navBottom + 76.dp + 16.dp
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (skyReady) 1f else 0f }) {
            PeopleSkyMap(
                nodes = nodes,
                meName = meName,
                lens = lens,
                onTap = { n ->
                    // A tap is for who they are: their card.
                    val row = n.person.remoteId?.let { rid -> poolRows.firstOrNull { it.id == rid } }
                    onOpenPerson(people.firstOrNull { it.id == n.person.id } ?: n.person, row)
                },
                onTapMe = onOpenProfile,
                backToMeBottom = floatBottom,
            )
        }
        // Writing your own situation is its own button, not a tap on "me":
        // tapping a person opens that person, so tapping me opens me.
        com.roro.futurevoice.ui.brand.IosGlassButton(
            onClick = { withPerson = null; situationPrefill = ""; composing = ComposerMode.CUSTOM },
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = floatBottom).height(50.dp),
        ) {
            Icon(Icons.Filled.EditNote, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.new_situation), style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
        }
    }

    if (showingSaved) {
        SavedScenariosSheet(
            scenarios = live,
            people = people,
            onDismiss = { WatchSky.showingSaved.value = false },
            // Two sheets can't be up at once: the list goes first.
            onOpen = { sc ->
                WatchSky.showingSaved.value = false
                scope.launch { kotlinx.coroutines.delay(450); editingScenario = sc }
            },
        )
    }

    composing?.let { mode ->
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            prefill = situationPrefill,
            person = withPerson,
            // A scene always needs an other person, so this host opens on a
            // character rather than on the fluent self.
            host = ComposerHost.WATCH,
            mode = mode,
            // Minting it plays it — the composer's CTA IS "Watch".
            onCommitted = { sc -> if (enabled) onWatch(sc.id) },
            onDismiss = { composing = null; withPerson = null; situationPrefill = "" },
        )
    }

    editingScenario?.let { sc ->
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            host = ComposerHost.WATCH,
            editing = sc,
            // Saved in place, then a FRESH take into the same book — the
            // scene screen writes a new take whenever the scenario already
            // has one.
            onCommitted = { edited -> if (enabled) onWatch(edited.id) },
            onDelete = {
                scope.launch { store.delete(sc.id, language); StoreEvents.bump() }
            },
            onDismiss = { editingScenario = null },
        )
    }
}

/**
 * The Watch header (iOS `WatchTab` toolbar): the lens — an occasional choice,
 * so a menu rather than a row the map gives up space to, its icon filled
 * while the map is narrowed — the saved situations, and the ONE people page.
 * iOS groups the three in one glass capsule.
 */
@Composable
internal fun WatchHeaderActions(onOpenPeople: () -> Unit) {
    val lens by WatchSky.lens.collectAsStateWithLifecycle()
    var menu by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    val lensLabel = with(PeopleSky) { lens.title() }
    val options = PeopleSky.Lens.entries.map { it to with(PeopleSky) { it.title() } }
    Box(Modifier.padding(end = 12.dp)) {
        GlassCapsule {
            Box {
                androidx.compose.material3.IconButton(onClick = { menu = true },
                    modifier = Modifier.size(40.dp).semantics { contentDescription = lensLabel }) {
                    // line.3.horizontal.decrease.circle(.fill)
                    val narrowed = lens != PeopleSky.Lens.ALL
                    Box(Modifier.size(22.dp).clip(CircleShape)
                        .then(if (narrowed) Modifier.background(accent)
                            else Modifier.border(1.5.dp, accent, CircleShape)),
                        contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null,
                            tint = if (narrowed) Color.White else accent, modifier = Modifier.size(14.dp))
                    }
                }
                com.roro.futurevoice.ui.brand.IosPickerMenu(
                    expanded = menu, onDismissRequest = { menu = false },
                    options = options, selected = lens,
                    onPick = { WatchSky.lens.value = it })
            }
            androidx.compose.material3.IconButton(onClick = { WatchSky.showingSaved.value = true },
                modifier = Modifier.size(40.dp)) {
                // Every situation made before the map still has a home.
                Icon(Icons.Outlined.Layers, contentDescription = stringResource(R.string.your_scenarios),
                    tint = accent, modifier = Modifier.size(22.dp))
            }
            androidx.compose.material3.IconButton(onClick = onOpenPeople, modifier = Modifier.size(40.dp)) {
                // iOS draws `person.2` as an OUTLINE here.
                Icon(Icons.Outlined.People, contentDescription = stringResource(R.string.people),
                    tint = accent, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/**
 * Everyone on the map (iOS `skyNodes`): every person on file, then the pool's
 * strangers not met yet. Seats are dealt in this order, so it must not follow
 * the store's — saving a person reorders it, and the whole map would
 * reshuffle under the learner's finger.
 */
private fun skyNodes(
    people: List<Counterpart>,
    pool: List<com.roro.futurevoice.net.PublicPersonaClient.PublicPersona>,
    scenarios: List<Scenario>,
    talks: Map<String, Int>,
    metLabel: String,
): List<PeopleSky.Node> {
    val practiced = talks.toMutableMap()
    val kept = mutableSetOf<String>()
    for (s in scenarios) {
        val id = s.counterpartId ?: continue
        practiced[id] = (practiced[id] ?: 0) + 1
        val meeting = s.isMeeting == true || s.category == "Meeting"
        if (!meeting && s.isTopic != true) kept += id
    }
    val jobs = pool.associate { it.id to it.occupation }
    val nodes = people.map { c ->
        val job = c.remoteId?.let { jobs[it] }
        PeopleSky.Node(
            id = c.id, name = c.name, person = c, pooled = false,
            ring = PeopleSky.ring(c), isMine = c.remoteId == null,
            practiced = practiced[c.id] ?: 0, hasKept = c.id in kept,
            symbol = PeopleSky.symbol(c, job), eyebrow = PeopleSky.eyebrow(c, job),
        )
    }.toMutableList()
    val metRemote = people.mapNotNull { it.remoteId }.toSet()
    for (row in pool) {
        if (row.id in metRemote) continue
        val c = row.asCounterpart(metLabel)
        nodes += PeopleSky.Node(
            id = c.id, name = c.name, person = c, pooled = true, ring = 2,
            isMine = false, practiced = 0, hasKept = false,
            symbol = PeopleSky.symbol(c, row.occupation), eyebrow = PeopleSky.eyebrow(c, row.occupation),
        )
    }
    return nodes.sortedBy { it.id }
}

/**
 * Every situation made before the map (iOS `savedScenariosPage`): category
 * tabs on top — only the categories the saved situations carry, most used
 * first — and the cards below.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun SavedScenariosSheet(
    scenarios: List<Scenario>,
    people: List<Counterpart>,
    onDismiss: () -> Unit,
    onOpen: (Scenario) -> Unit,
) {
    var category by remember { mutableStateOf<String?>(null) }
    val categories = remember(scenarios) {
        val count = mutableMapOf<String, Int>()
        val icon = mutableMapOf<String, String?>()
        for (s in scenarios) {
            val c = s.category?.trim()?.takeIf { it.isNotEmpty() } ?: continue
            count[c] = (count[c] ?: 0) + 1
            if (icon[c] == null) icon[c] = s.categoryIcon
        }
        count.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key to icon[it.key] }
    }
    val shown = category?.let { c -> scenarios.filter { it.category == c } } ?: scenarios
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null,
        containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.fillMaxSize()) {
            SheetHeader(
                title = stringResource(R.string.your_scenarios),
                leading = {
                    com.roro.futurevoice.ui.brand.IosGlassTextButton(stringResource(R.string.done),
                        onClick = onDismiss)
                },
                modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp),
            )
            if (categories.size > 1) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SoftChip(stringResource(R.string.all), selected = category == null) { category = null }
                    categories.forEach { (name, icon) ->
                        SoftChip(categoryTitle(name), icon = icon, selected = category == name) { category = name }
                    }
                }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                shown.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { sc ->
                            WatchScenarioCard(sc,
                                Modifier.weight(1f).fillMaxHeight(),
                                person = sc.counterpartId?.let { id -> people.firstOrNull { it.id == id } },
                                // Settings sheet first, not straight to
                                // generation: check, tweak or delete, then
                                // Watch a fresh take from there.
                                onClick = { onOpen(sc) })
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(24.dp).windowInsetsPadding(WindowInsets.navigationBars))
            }
        }
    }
}

/**
 * One saved scenario, as a card in the Watch grid. A scenario is a reusable
 * TEMPLATE — a tap writes a FRESH take — so the card shows what the situation
 * IS, not when it last ran.
 */
@Composable
private fun WatchScenarioCard(
    sc: Scenario,
    modifier: Modifier = Modifier,
    person: Counterpart?,
    onClick: () -> Unit,
) {
    val personName = person?.name
    val partner = personName ?: sc.role.trim().takeIf { it.isNotEmpty() }
    val env = sc.environment.trim()
    val blurb = env.takeIf { it.isNotEmpty() && !it.equals(sc.cardTitle.trim(), ignoreCase = true) }
    Column(
        modifier
            .clip(ContinuousShape(16.dp))
            .background(AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            if (person != null) {
                PersonBubble(person.name, person.id, size = 32.dp)
            } else {
                Icon(Symbols.icon(sc.categoryIcon), contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
            }
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.PlayCircleFilled, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (personName == null) sc.category?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(sc.cardTitle, style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            blurb?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.weight(1f))
        val footer = listOfNotNull(
            partner?.let { stringResource(R.string.with, it) },
            sc.lastUsedAt?.let { com.roro.futurevoice.data.Recency.label(it) },
        ).joinToString(" · ")
        if (footer.isNotEmpty()) {
            Text(footer, style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
