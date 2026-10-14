package com.roro.futurevoice.ui

import android.icu.text.RelativeDateTimeFormatter
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkRemove
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SavedLine
import com.roro.futurevoice.data.SavedLineStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosSegmented
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * iOS `ShadowBrowserView` — every line the fluent self has ever spoken, from
 * the scenes you WATCHED (first) and from your TALKS, newest first. Tap a line
 * to shadow it. One archive, two doors: lines still waiting for a first
 * attempt ("To study", the default) and lines with ≥1 recorded attempt
 * ("Practiced"); the split only shows once anything has been practiced.
 * Saving is a trailing swipe on a talk's line (`SavedLineStore`); a saved
 * line wears a filled bookmark, nothing more.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShadowBrowserScreen(language: String, onShadow: (Turn) -> Unit, onBack: () -> Unit) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var data by remember { mutableStateOf<Loaded?>(null) }
    val store = remember { SavedLineStore.shared(context) }
    LaunchedEffect(language, revision) {
        val sessions = SessionStore.shared(context).load(language)
        val scenarios = ScenarioStore.shared(context).load(language)
        val attempts = ShadowAttemptStore.shared(context).load(language)
        val saved = store.load().map { it.id }.toSet()
        val withAudio = withContext(Dispatchers.IO) {
            val turns = sessions.flatMap { it.turns }.filter { it.role == TurnRole.FLUENT_SELF } +
                scenarios.flatMap { sc -> sc.curriculum?.shadowLines.orEmpty() }
                    .map { Turn(id = it.id, role = TurnRole.FLUENT_SELF, transcript = it.text) }
            turns.filter { WeeklyTestEngine.turnAudio(context, it) != null }.map { it.id }.toSet()
        }
        data = Loaded(sessions, scenarios, attempts.map { it.turnId }.toSet(),
            attempts.isNotEmpty(), saved, withAudio)
    }
    // 0 = To study, 1 = Practiced.
    var filter by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        topBar = {
            // Pushed from Practice on iOS: back chevron, name centred.
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.shadowing), style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)) {
            val d = data ?: return@Column
            // The split only means something once at least one line has been
            // practiced — until then everything is "to study".
            if (d.anyAttempt) {
                IosSegmented(
                    listOf(stringResource(R.string.to_study), stringResource(R.string.practiced)),
                    filter, { filter = it },
                    Modifier.fillMaxWidth().background(AppSurfaces.topBarColors().containerColor)
                        .padding(horizontal = 16.dp, vertical = 8.dp))
            }
            fun passes(t: Turn) = if (filter == 0) t.id !in d.practiced else t.id in d.practiced

            val totalLines = d.sessions.sumOf { s -> s.turns.count { it.role == TurnRole.FLUENT_SELF } } +
                d.scenarios.sumOf { it.curriculum?.shadowLines?.size ?: 0 }
            if (totalLines == 0) {
                NothingToShadow()
                return@Column
            }
            // A Watch book's scene lines, as shadowable turns — the item id is
            // the turn id, so an attempt here checks the book's line off too.
            val sceneSections = d.scenarios.filter { it.archivedAt == null }.mapNotNull { sc ->
                val at = sc.lastUsedAt ?: sc.createdAt
                val lines = (sc.curriculum?.shadowLines ?: emptyList()).map {
                    Turn(id = it.id, role = TurnRole.FLUENT_SELF, transcript = it.text, timestamp = at)
                }.filter(::passes)
                if (lines.isEmpty()) null else sc to lines
            }.sortedByDescending { (sc, _) -> sc.lastUsedAt ?: sc.createdAt }

            LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
                // Watched scenes first — their lines are the ones a book is
                // currently asking for.
                sceneSections.forEach { (sc, lines) ->
                    item(key = "h-" + sc.id) { SceneHeader(sc) }
                    itemsIndexed(lines, key = { _, t -> "s-" + sc.id + t.id }) { i, t ->
                        CardRow(first = i == 0, last = i == lines.lastIndex) {
                            ShadowRow(t, hasAudio = t.id in d.withAudio, isSaved = t.id in d.saved) { onShadow(t) }
                        }
                    }
                }
                d.sessions.forEach { s ->
                    val lines = s.turns.filter { it.role == TurnRole.FLUENT_SELF && passes(it) }
                    if (lines.isEmpty()) return@forEach
                    item(key = "h-" + s.id) { SessionHeader(s) }
                    itemsIndexed(lines, key = { _, t -> "t-" + s.id + t.id }) { i, t ->
                        val isSaved = t.id in d.saved
                        val action = IosSwipeAction(
                            if (isSaved) Icons.Filled.BookmarkRemove else Icons.Outlined.BookmarkBorder,
                            stringResource(if (isSaved) R.string.unsave else R.string.save),
                            MaterialTheme.colorScheme.primary,
                        ) { scope.launch { store.toggle(SavedLine(id = t.id, text = t.transcript, source = s.topic.orEmpty())) } }
                        CardRow(first = i == 0, last = i == lines.lastIndex) {
                            IosSwipeActions(listOf(action), background = AppSurfaces.card) {
                                ShadowRow(t, hasAudio = t.id in d.withAudio || t.audioURL != null, isSaved = isSaved) { onShadow(t) }
                            }
                        }
                    }
                }
                item { GroupedSectionSpacer() }
            }
        }
    }
}

private class Loaded(
    val sessions: List<Session>,
    val scenarios: List<Scenario>,
    val practiced: Set<String>,
    val anyAttempt: Boolean,
    val saved: Set<String>,
    val withAudio: Set<String>,
)

/** One row inside an inset-grouped card, with iOS's inset separator. */
@Composable
private fun CardRow(first: Boolean, last: Boolean, content: @Composable () -> Unit) {
    val r = com.roro.futurevoice.ui.brand.IosRadius.groupedCard
    val shape = RoundedCornerShape(
        topStart = if (first) r else 0.dp, topEnd = if (first) r else 0.dp,
        bottomStart = if (last) r else 0.dp, bottomEnd = if (last) r else 0.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(AppSurfaces.card)) {
        content()
        if (!last) HorizontalDivider(Modifier.padding(start = 50.dp, end = 16.dp),
            thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
    }
}

/** A scene's header names the book, so a line's origin is never a guess. */
@Composable
private fun SceneHeader(sc: Scenario) {
    HeaderRow(date = sc.lastUsedAt ?: sc.createdAt) {
        Icon(Icons.Outlined.Movie, contentDescription = null, modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(6.dp))
        Text(sc.environment, style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SessionHeader(s: Session) {
    HeaderRow(date = s.endedAt ?: s.startedAt) {
        Text(s.displayTitle ?: stringResource(R.string.conversation), style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f))
    }
}

/** iOS `Section(header: HStack { title; Spacer(); date.secondary })`. */
@Composable
private fun HeaderRow(date: Long, title: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 28.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        title()
        Spacer(Modifier.width(8.dp))
        Text(relativeDate(date), style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

/** Waveform (accent when the line has audio, slashed and grey when not),
 *  the line, a filled bookmark only when saved, a chevron. */
@Composable
private fun ShadowRow(turn: Turn, hasAudio: Boolean, isSaved: Boolean, onTap: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(AppSurfaces.card).clickable(onClick = onTap)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (hasAudio) Icons.Filled.GraphicEq else Icons.AutoMirrored.Outlined.VolumeOff, contentDescription = null,
            tint = if (hasAudio) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(22.dp).size(18.dp))
        Spacer(Modifier.width(12.dp))
        Text(turn.transcript, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        if (isSaved) {
            Icon(Icons.Filled.Bookmark, contentDescription = null, modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(12.dp))
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
    }
}

/** iOS `ContentUnavailableView("Nothing to shadow yet", systemImage: "waveform.badge.mic")`. */
@Composable
private fun NothingToShadow() {
    Column(Modifier.fillMaxSize().padding(30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
        Icon(Icons.Filled.GraphicEq, contentDescription = null, modifier = Modifier.size(44.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.nothing_to_shadow_yet), style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(stringResource(R.string.have_a_conversation_or_watch_a_scene_then_come_back_to_shado_9066e7),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

/** iOS `RelativeDateTimeFormatter` with `.abbreviated` units: the largest
 *  whole unit of the gap ("2 days ago", "3 hr. ago"). */
private fun relativeDate(at: Long, now: Long = System.currentTimeMillis()): String {
    val fmt = RelativeDateTimeFormatter.getInstance(android.icu.util.ULocale.forLocale(Locale.getDefault()), null,
        RelativeDateTimeFormatter.Style.SHORT, android.icu.text.DisplayContext.CAPITALIZATION_NONE)
    val sec = (now - at) / 1000
    val dir = if (sec >= 0) RelativeDateTimeFormatter.Direction.LAST else RelativeDateTimeFormatter.Direction.NEXT
    val m = kotlin.math.abs(sec)
    val (v, unit) = when {
        m < 60 -> m to RelativeDateTimeFormatter.RelativeUnit.SECONDS
        m < 3_600 -> m / 60 to RelativeDateTimeFormatter.RelativeUnit.MINUTES
        m < 86_400 -> m / 3_600 to RelativeDateTimeFormatter.RelativeUnit.HOURS
        m < 7 * 86_400 -> m / 86_400 to RelativeDateTimeFormatter.RelativeUnit.DAYS
        m < 30 * 86_400 -> m / (7 * 86_400) to RelativeDateTimeFormatter.RelativeUnit.WEEKS
        m < 365 * 86_400 -> m / (30 * 86_400) to RelativeDateTimeFormatter.RelativeUnit.MONTHS
        else -> m / (365 * 86_400) to RelativeDateTimeFormatter.RelativeUnit.YEARS
    }
    return fmt.format(v.toDouble(), dir, unit)
}
