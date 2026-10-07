package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material.icons.filled.Abc
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.BookmarkTab
import com.roro.futurevoice.ui.brand.BookmarkedPage
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueSpeaker
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.LocalMall
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.WorkspacePremium
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BookDocument
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum

/**
 * A scenario BOOK — `ScenarioDetailView`'s spine: one scene + the material
 * to master. Mastery is DETERMINISTIC and never LLM-judged, riding the
 * app's existing tracking (iOS rule): a word is mastered when it's in the
 * vocab pool, an expression on real evidence (used or "I know it"), a
 * shadow line by a whole-line take at the bar (`ScenarioMastery`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScenarioBookScreen(
    scenarioId: String,
    language: String,
    onWatch: (String) -> Unit,
    /** Talk this scenario through — a metered call, gated by the host, and it
     *  carries the scenario id so the call opens from its opener pool and its
     *  chips come from this book (iOS `cb4252b`). */
    onTalk: ((com.roro.futurevoice.talk.Scenario) -> Unit)? = null,
    onShadow: (String) -> Unit,
    onBack: () -> Unit,
    /** Open one of the talks run on this book (the cover's study record). */
    onOpenTalk: ((String) -> Unit)? = null,
) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var scenario by remember { mutableStateOf<Scenario?>(null) }
    var wordMastered by remember { mutableStateOf<Set<String>>(emptySet()) }
    var exprMastered by remember { mutableStateOf<Set<String>>(emptySet()) }
    var shadowMastered by remember { mutableStateOf<Set<String>>(emptySet()) }
    var chapter by remember { mutableStateOf(
        Chapter.entries.firstOrNull { it.name == com.roro.futurevoice.capture.flags.PracticeCaptureFlags.bookChapter } ?: Chapter.INTRO) }
    LaunchedEffect(scenarioId, revision) {
        val sc = com.roro.futurevoice.capture.flags.PracticeCaptureFlags.bookScenario?.takeIf { it.id == scenarioId }
            ?: ScenarioStore.shared(context).load(language).firstOrNull { it.id == scenarioId }
                ?.let { com.roro.futurevoice.data.ScenarioMastery.refresh(context, it, language) }
        scenario = sc
        val vocab = VocabStore.shared(context)
        val cur = sc?.curriculum
        wordMastered = cur?.words.orEmpty()
            .filter { it.masteredAt != null || vocab.isKnownWord(it.text, language) }.map { it.id }.toSet()
        exprMastered = cur?.expressions.orEmpty()
            .filter { it.masteredAt != null || vocab.hasUsedExpression(it.text, language) }.map { it.id }.toSet()
        // A shadow line is mastered by a whole-line take at the bar —
        // written onto the item by `ScenarioMastery.refresh` just above.
        shadowMastered = cur?.shadowLines.orEmpty()
            .filter { it.masteredAt != null }.map { it.id }.toSet()
    }
    // "Read again" on the brief — the same board the scene shows while it
    // reads, drawn in place of the section until the new reading lands.
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var rereading by remember { mutableStateOf(false) }
    var briefProgress by remember { mutableStateOf(com.roro.futurevoice.net.ScenarioBriefEngine.Progress()) }
    var briefError by remember { mutableStateOf<String?>(null) }
    fun rereadBrief() {
        val current = scenario ?: return
        val b = current.brief?.takeIf { it.hasSources } ?: return
        if (rereading) return
        rereading = true; briefError = null
        briefProgress = com.roro.futurevoice.net.ScenarioBriefEngine.Progress(sourcesRead = b.sources.map { false })
        scope.launch {
            try {
                val persona = com.roro.futurevoice.data.PersonaStore.shared(context).load()
                val native = context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
                    .getString("futurevoice.nativeLanguage", null)
                    ?: com.roro.futurevoice.data.LanguageCatalog.defaultNative()
                val read = com.roro.futurevoice.net.ScenarioBriefEngine.read(
                    context, current, persona, language, native, onProgress = { briefProgress = it })
                val saved = current.copy(brief = read)
                ScenarioStore.shared(context).save(saved, language)
                scenario = saved
                StoreEvents.bump()
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                briefError = e.message
            } finally {
                rereading = false
            }
        }
    }
    val sc = scenario ?: return
    val cur = sc.curriculum
    // Say it again — the scene run again with the learner reading their own
    // side (the Shadow chapter, in order, between the counterpart's lines).
    // No gate: the counterpart's lines play from the cache the scene's first
    // watch filled, and nothing is synthesized.
    val sayItAgain = remember(sc, language) { SayItAgainSource.scene(context, sc, language) }
    var sayingAgain by remember(scenarioId) {
        mutableStateOf(com.roro.futurevoice.capture.flags.PracticeCaptureFlags.sayItAgainStage != null)
    }
    if (sayingAgain && sayItAgain != null) {
        // In place of the page — it owns the mic for a whole run.
        SayItAgainScreen(
            source = sayItAgain,
            onClose = { sayingAgain = false; StoreEvents.bump() },
            captureStage = com.roro.futurevoice.capture.flags.PracticeCaptureFlags.sayItAgainStage)
        return
    }
    // The linked person's name, when the scenario is about someone the
    // learner made (iOS `linkedPersonaName`).
    var personName by remember(sc.counterpartId) { mutableStateOf<String?>(null) }
    LaunchedEffect(sc.counterpartId) {
        personName = sc.counterpartId?.let { id ->
            com.roro.futurevoice.data.CounterpartStore.shared(context).load().firstOrNull { it.id == id }?.name
        }
    }
    // The study record: the talks run on this book, newest first (iOS
    // `studyRecordRows`, five at most).
    var record by remember(sc.id) { mutableStateOf<List<com.roro.futurevoice.talk.Session>>(emptyList()) }
    LaunchedEffect(sc.id, revision) {
        record = com.roro.futurevoice.data.SessionStore.shared(context).load(language)
            .filter { it.endedAt != null &&
                (it.originScenarioId == sc.id || it.topic == sc.cardTitle || it.topic == sc.promptBlurb) }
            .sortedByDescending { it.startedAt }
            .take(5)
    }
    var confirmDelete by remember { mutableStateOf(false) }
    if (confirmDelete) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_this_scenario)) },
            text = { Text(stringResource(R.string.the_curriculum_and_its_progress_go_with_it)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    scope.launch {
                        ScenarioStore.shared(context).delete(sc.id, language)
                        StoreEvents.bump()
                        onBack()
                    }
                }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
    fun setArchived(archived: Boolean) {
        scope.launch {
            ScenarioStore.shared(context).setArchived(sc.id, archived, language)
            StoreEvents.bump()
        }
    }
    val archived = sc.archivedAt != null

    Scaffold(
        topBar = {
            // The situation itself is the title, as on iOS — the page is
            // ABOUT that situation; the ⋯ holds export, archive and delete.
            androidx.compose.material3.CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(sc.environment, style = MaterialTheme.typography.titleMedium,
                    maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    BookExportMenu(
                        document = { BookDocument.make(context, sc, counterpartName = personName) },
                        nativeLanguage = com.roro.futurevoice.core.UILanguage.current(context) ?: "en",
                        targetLanguage = language,
                        extra = { close ->
                            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                text = { Text(stringResource(if (archived) R.string.unarchive else R.string.archive)) },
                                leadingIcon = { Icon(if (archived) Icons.Filled.Unarchive else Icons.Filled.Archive,
                                    contentDescription = null) },
                                onClick = { close(); setArchived(!archived) })
                            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
                                text = { Text(stringResource(R.string.delete),
                                    color = MaterialTheme.colorScheme.error) },
                                leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error) },
                                onClick = { close(); confirmDelete = true })
                        })
                },
            )
        }
    ) { padding ->
        // Ribbon bookmarks, not a table of contents: the cover first, then
        // the chapters named by what you DO in them (iOS `allTabs`). The
        // scene itself is behind the cover's Watch button, never a chapter.
        val tabs = buildList {
            add(BookmarkTab(Chapter.INTRO, Icons.Filled.MenuBook, stringResource(R.string.overview)))
            if (cur != null) {
                if (cur.words.isNotEmpty()) add(BookmarkTab(Chapter.WORDS, StudyIcon.words,
                    stringResource(R.string.words_d26d55),
                    done = wordMastered.size, total = cur.words.size))
                if (cur.expressions.isNotEmpty()) add(BookmarkTab(Chapter.EXPRESSIONS, StudyIcon.expressions,
                    stringResource(R.string.expressions),
                    done = exprMastered.size, total = cur.expressions.size))
                if (cur.shadowLines.isNotEmpty()) add(BookmarkTab(Chapter.SHADOW, StudyIcon.shadowing,
                    stringResource(R.string.your_lines),
                    done = shadowMastered.size, total = cur.shadowLines.size))
            }
        }
        val active = if (tabs.any { it.id == chapter }) chapter else Chapter.INTRO
        BookmarkedPage(
            tabs = tabs, selection = active, onSelect = { chapter = it },
            modifier = Modifier.padding(padding).background(AppSurfaces.ground)
                .padding(start = 0.dp, end = 16.dp, top = 8.dp, bottom = 16.dp),
        ) {
            Column(Modifier.fillMaxWidth()) {
                when (active) {
                    Chapter.INTRO -> {
                        val total = cur?.let { it.words.size + it.expressions.size + it.shadowLines.size } ?: 0
                        val done = wordMastered.size + exprMastered.size + shadowMastered.size
                        ScenarioCover(
                            scenario = sc,
                            personName = personName,
                            archived = archived,
                            progress = if (total > 0) done.toFloat() / total else null,
                            progressLabel = stringResource(R.string.lld_of_lld_mastered, done, total),
                            mastered = total > 0 && done == total,
                            onTalk = onTalk?.let { talk -> { talk(sc) } },
                            // Watch is hidden until the scene exists.
                            onWatch = if (cur?.dialogue.isNullOrEmpty()) null else ({ onWatch(sc.id) }),
                            onSayItAgain = if (cur?.dialogue.orEmpty().any { it.speaker == "user" } && sayItAgain != null)
                                ({ sayingAgain = true }) else null,
                        )
                        // The attached material and what reading it gave —
                        // the file itself is still wherever the learner keeps it.
                        sc.brief?.takeIf { it.hasSources }?.let { b ->
                            androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 20.dp))
                            Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                                BriefSection(b, rereading, briefProgress, briefError, onReadAgain = ::rereadBrief)
                            }
                        }
                        if (total > 0 && done == total && !archived) {
                            ScenarioMasteredBanner(onArchive = { setArchived(true) })
                        }
                        if (cur == null) {
                            Text(stringResource(R.string.watch_the_scene_first),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
                        }
                        if (record.isNotEmpty()) {
                            androidx.compose.material3.HorizontalDivider(
                                Modifier.padding(start = 20.dp, top = 8.dp))
                            Row(Modifier.padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Filled.Schedule, contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(stringResource(R.string.study_record),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            val fmt = remember {
                                java.time.format.DateTimeFormatter.ofLocalizedDateTime(
                                    java.time.format.FormatStyle.MEDIUM, java.time.format.FormatStyle.SHORT)
                            }
                            record.forEach { session ->
                                Row(Modifier.fillMaxWidth()
                                    .then(if (onOpenTalk != null) Modifier.clickable { onOpenTalk(session.id) } else Modifier)
                                    .padding(horizontal = 20.dp, vertical = 9.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(java.time.Instant.ofEpochMilli(session.startedAt)
                                            .atZone(java.time.ZoneId.systemDefault()).format(fmt),
                                            style = MaterialTheme.typography.bodyMedium)
                                        Text(stringResource(R.string.lld_turns_spoken_38ecf5,
                                            session.turns.count { it.role == com.roro.futurevoice.talk.TurnRole.USER }),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                                        modifier = Modifier.size(18.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                                }
                            }
                        }
                    }
                    Chapter.WORDS -> cur?.let { c ->
                        ChapterTitle(stringResource(R.string.words_d26d55))
                        c.words.forEach { ItemRow(it, it.id in wordMastered) }
                    }
                    Chapter.EXPRESSIONS -> cur?.let { c ->
                        ChapterTitle(stringResource(R.string.expressions))
                        c.expressions.forEach { ItemRow(it, it.id in exprMastered, showExample = true) }
                    }
                    Chapter.SHADOW -> cur?.let { c ->
                        ChapterTitle(stringResource(R.string.your_lines))
                        c.shadowLines.forEach { line ->
                            ItemRow(line, line.id in shadowMastered, onClick = { onShadow(line.text) })
                        }
                        Text(stringResource(R.string.tap_a_line_to_shadow_it_in_your_own_voice_score_lld_and_it_s_a7e9bd,
                            com.roro.futurevoice.data.TalkCurriculum.SHADOW_MASTERY_SCORE),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 20.dp).padding(top = 10.dp, bottom = 6.dp))
                    }
                }
            }
        }
    }
}

/** The book's chapters — the cover first, then named by what you DO. */
private enum class Chapter { INTRO, WORDS, EXPRESSIONS, SHADOW }

/** The scenario's cover (iOS `introPage`): who and where at the top, the
 *  progress, then Talk beside Watch and Say it again on its own row. */
@Composable
private fun ScenarioCover(
    scenario: Scenario,
    personName: String?,
    archived: Boolean,
    progress: Float?,
    progressLabel: String,
    mastered: Boolean,
    onTalk: (() -> Unit)?,
    onWatch: (() -> Unit)?,
    onSayItAgain: (() -> Unit)?,
) {
    val tonal = androidx.compose.material3.ButtonDefaults.filledTonalButtonColors(
        containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
        contentColor = MaterialTheme.colorScheme.primary)
    val pad = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 10.dp)
    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        // The avatar sits at the TOP of the title block, not centred: a
        // two-line situation with a "with …" line is three lines tall.
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(56.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center) {
                if (personName != null) {
                    Text(initials(personName), style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                } else {
                    Icon(roleIcon(scenario.role), contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(26.dp))
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(scenario.environment, style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                val partner = personName ?: scenario.role.trim().takeIf { it.isNotEmpty() }
                if (partner != null) {
                    Text(stringResource(R.string.with, partner), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (archived) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Filled.Archive, contentDescription = null, modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.archived), style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (scenario.notes.isNotBlank()) {
            Text(scenario.notes, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (progress != null) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth(),
                    color = if (mastered) Books.mastery else MaterialTheme.colorScheme.primary)
                Text(progressLabel, style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (onTalk != null || onWatch != null) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (onTalk != null) {
                    androidx.compose.material3.Button(onClick = onTalk, modifier = Modifier.weight(1f),
                        contentPadding = pad) {
                        Icon(Icons.Filled.Mic, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        com.roro.futurevoice.ui.brand.FitButtonLabel(stringResource(R.string.talk))
                    }
                }
                if (onWatch != null) {
                    androidx.compose.material3.FilledTonalButton(onClick = onWatch,
                        modifier = Modifier.weight(1f), contentPadding = pad, colors = tonal) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        com.roro.futurevoice.ui.brand.FitButtonLabel(stringResource(R.string.watch))
                    }
                }
            }
        }
        // The third door, on its own row as on iOS.
        if (onSayItAgain != null) SayItAgainButton(onSayItAgain)
    }
}

/** iOS `Books.roleIcon` — the counterpart's role as a glyph. */
private fun roleIcon(role: String): androidx.compose.ui.graphics.vector.ImageVector {
    val r = role.lowercase()
    return when {
        "doctor" in r || "nurse" in r -> Icons.Filled.LocalHospital
        "manager" in r || "boss" in r || "colleague" in r -> Icons.Filled.Business
        "teacher" in r -> Icons.Filled.School
        "shop" in r || "service" in r || "agent" in r -> Icons.Filled.LocalMall
        "friend" in r -> Icons.Filled.People
        "family" in r || "kid" in r || "child" in r -> Icons.Filled.FamilyRestroom
        "date" in r || "romantic" in r -> Icons.Filled.Favorite
        "neighbor" in r -> Icons.Filled.Home
        "stranger" in r -> Icons.Filled.PersonSearch
        else -> Icons.Filled.Person
    }
}

/** Everything in the scenario is mastered — and archiving is offered here. */
@Composable
private fun ScenarioMasteredBanner(onArchive: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
            tint = Books.mastery, modifier = Modifier.size(26.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.book_mastered),
                style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.everything_in_this_scenario_is_yours_now),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        androidx.compose.material3.Button(onClick = onArchive,
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = Books.mastery)) {
            Text(stringResource(R.string.archive))
        }
    }
}

@Composable
private fun ChapterTitle(t: String) {
    Text(t, style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(horizontal = 20.dp).padding(top = 18.dp, bottom = 6.dp))
}

@Composable
private fun ItemRow(item: ScenarioCurriculum.Item, mastered: Boolean,
                    showExample: Boolean = false, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth()
        .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (mastered) Icon(Icons.Filled.CheckCircle, contentDescription = null,
            tint = Books.mastery, modifier = Modifier.size(18.dp))
        else Icon(Icons.Outlined.Circle, contentDescription = null,
            tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(item.text, style = MaterialTheme.typography.bodyLarge,
                color = if (mastered) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurface)
            if (item.note.isNotBlank()) {
                Text(item.note, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (showExample && !item.example.isNullOrBlank()) {
                Text("“${item.example}”", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary)
            }
        }
        if (onClick != null) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
    }
}
