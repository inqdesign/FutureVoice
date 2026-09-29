package com.roro.futurevoice.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
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
 * Watch — simulate a specific situation BEFORE it happens (iOS `WatchTab`,
 * as of 1.1.1). Three ways in, all landing in the situation composer:
 *
 *  1. the People row — a person opens the WRITING door scoped to them
 *     (`b476527`: you don't browse for the talk you're dreading with a
 *     particular person, you describe it);
 *  2. **Your own situation** — the box: one line, with the posting's link or
 *     a CV attached (`ScenarioBrief`); no person needed;
 *  3. **Common situations** — the category chain, tap-tap-tap, no field.
 *
 * Both doors mint the same `Scenario`, and minting it PLAYS it. A saved
 * scenario is a reusable TEMPLATE: tapping its card writes a fresh take.
 * No caption under any section (`cf4d360`, user decision): each had grown
 * into a paragraph restating what the screen already shows.
 */
@Composable
internal fun WatchTabBody(
    language: String,
    enabled: Boolean,
    onWatch: (String) -> Unit,
) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val store = remember { ScenarioStore.shared(context) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    /** Which door the composer opens on, when it is open. */
    var composing by remember { mutableStateOf<ComposerMode?>(null) }
    /** The person a composed scene is scoped to, if any. */
    var withPerson by remember { mutableStateOf<Counterpart?>(null) }
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var managingPeople by remember { mutableStateOf(false) }
    LaunchedEffect(language, revision) {
        scenarios = store.load(language)
        // Own people only. A stranger met in Find people has `remoteId` set
        // and lives in that sheet's "People you've met".
        people = CounterpartStore.shared(context).load().filter { it.remoteId == null }
    }
    val live = scenarios
        .filter { it.archivedAt == null && it.isMeeting != true && it.isTopic != true }
        .sortedByDescending { it.lastUsedAt ?: it.createdAt }

    Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
        // MARK: People — making a person is pinned to the LEFT, outside the
        // scroller: as the last bubble it slid off the row the moment the
        // learner had a few people.
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WatchSectionHeader(stringResource(R.string.people))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) {
                PersonRowBubble(name = stringResource(R.string.create), person = null,
                    onClick = { managingPeople = true })
                LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    items(people, key = { it.id }) { person ->
                        PersonRowBubble(name = person.name, person = person, onClick = {
                            withPerson = person; composing = ComposerMode.CUSTOM
                        })
                    }
                }
            }
        }

        // MARK: New situation — two doors, side by side, as equals.
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            WatchSectionHeader(stringResource(R.string.new_situation))
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                DoorButton(
                    title = stringResource(R.string.your_own_situation),
                    subtitle = stringResource(R.string.one_line_plus_your_material),
                    icon = Icons.Filled.EditNote, prominent = true,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                ) { withPerson = null; composing = ComposerMode.CUSTOM }
                DoorButton(
                    title = stringResource(R.string.common_situations),
                    subtitle = stringResource(R.string.pick_from_categories),
                    icon = Icons.Filled.GridView, prominent = false,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                ) { withPerson = null; composing = ComposerMode.BROWSE }
            }
        }

        if (live.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                WatchSectionHeader(stringResource(R.string.your_scenarios))
                live.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { sc ->
                            WatchScenarioCard(sc,
                                Modifier.weight(1f).fillMaxHeight(),
                                person = sc.counterpartId?.let { id -> people.firstOrNull { it.id == id } },
                                onClick = if (enabled) ({ onWatch(sc.id) }) else null)
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }

    if (managingPeople) {
        PeopleSheet(onDismiss = { managingPeople = false })
    }

    composing?.let { mode ->
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            person = withPerson,
            // A scene always needs an other person, so this host opens on a
            // character rather than on the fluent self.
            host = ComposerHost.WATCH,
            mode = mode,
            // Minting it plays it — the composer's CTA IS "Watch".
            onCommitted = { sc -> if (enabled) onWatch(sc.id) },
            onDismiss = { composing = null; withPerson = null },
        )
    }
}

/** Big and QUIET: it names the group without competing with its cards. */
@Composable
private fun WatchSectionHeader(title: String) {
    Text(title, style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * One way in. TOP-aligned: the two doors can be different heights (one
 * subtitle wraps), and centring floated one icon down while its neighbour's
 * sat at the top.
 */
@Composable
private fun DoorButton(
    title: String,
    subtitle: String,
    icon: ImageVector,
    prominent: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier.heightIn(min = 72.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(if (prominent) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
            else AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null,
            tint = if (prominent) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * One face in the stories row — the person's photo, or their initials. The
 * ACTION bubble (`person == null`) is a dashed outline instead: an empty
 * slot asking to be filled, not a person.
 */
@Composable
private fun PersonRowBubble(name: String, person: Counterpart?, onClick: () -> Unit) {
    Column(
        Modifier.width(72.dp).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (person == null) {
            val outline = MaterialTheme.colorScheme.outline
            Box(
                Modifier.size(64.dp).drawBehind {
                    drawCircle(
                        color = outline,
                        radius = size.minDimension / 2f - 1.dp.toPx(),
                        style = Stroke(width = 1.5.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx()))),
                    )
                },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Add, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            PersonBubble(person.name, person.id, size = 64.dp)
        }
        Text(name, style = MaterialTheme.typography.labelMedium,
            color = if (person == null) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    onClick: (() -> Unit)?,
) {
    val personName = person?.name
    val partner = personName ?: sc.role.trim().takeIf { it.isNotEmpty() }
    val env = sc.environment.trim()
    val blurb = env.takeIf { it.isNotEmpty() && !it.equals(sc.cardTitle.trim(), ignoreCase = true) }
    Column(
        modifier
            .clip(RoundedCornerShape(16.dp))
            .background(AppSurfaces.card)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
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
