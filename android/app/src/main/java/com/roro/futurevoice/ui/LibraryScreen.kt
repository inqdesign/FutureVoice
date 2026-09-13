package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.ExpressionCatalog
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The Library: everything the app has collected, as a list you can read.
 *
 * The decks DEAL from this material; this is where it can be looked at, and
 * where a widget tap lands. Kept as a plain list rather than iOS's explorable
 * word cloud — the cloud is a visual decision that belongs to whoever is
 * designing the Android look, and shipping an improvised one would settle it
 * by accident.
 *
 * Two states per item, and they mean different things: KEPT is the learner's
 * bookmark (they are still studying it), KNOWN is a retirement. A word they
 * have actually SAID carries its own record and is neither.
 *
 * Three things make it a notebook rather than a dump, all of them ported from
 * `WordsView.swift` / `ExpressionsView.swift`:
 *
 *  - **Lenses**, not a toggle. To study / Known / All words — expressions get
 *    the first two, since every phrase is in exactly one of them. The old
 *    "Show known" chip ADDED the retired words to the pile it was supposed to
 *    separate them from, so the page could never answer "what am I still on
 *    the hook for".
 *  - **Filters and search.** Which pile a word came from, which CEFR band,
 *    and a search that sweeps the WHOLE word list whatever lens is up — a
 *    word you type deserves an answer even if you have never touched it.
 *  - **Rows that say something.** What the term MEANS, in the learner's own
 *    language, with where it came from standing in until the gloss lands.
 */
enum class LibraryKind { WORDS, EXPRESSIONS }

/** Which slice of the pool is on screen. */
private enum class Lens { TO_STUDY, KNOWN, ALL }

/**
 * Where a to-study word entered the list. The pile mixes words kept from
 * talks with words a watched scene asks for, and "which homework is this" is
 * the first cut a long list needs. Known words are all the learner's own, so
 * the picker sleeps on that lens.
 */
private enum class SourceFilter { ALL, TALKS, SCENES }

/**
 * The line under a term while it has no gloss: where it came from.
 *
 * It must never borrow the notebook's "said N times" for material the learner
 * has not spoken — a scene word has been said zero times, and a phrase the
 * fluent self used is the whole class of thing this library exists to teach.
 */
private sealed interface From {
    /** In the notebook. [count] is how often the learner has actually said it. */
    data class Kept(val count: Int) : From
    /** Said in a talk — the expressions page prints the date with it. */
    data class Said(val count: Int, val at: Long) : From
    /** A Watch book's material. [title] is the scene, empty where the source
     *  list doesn't carry one. */
    data class Scene(val title: String) : From
    /** The fluent self used it in a call and the learner didn't. */
    data object Heard : From
    /** Straight out of the core word list — nothing personal about it yet.
     *  Only the All lens and whole-list search mint these. */
    data object Pool : From
}

private data class LibraryRowData(
    val text: String,
    /** Lowercased identity — the list key, the gloss key, what search matches. */
    val key: String,
    val kept: Boolean,
    val known: Boolean,
    val from: From,
    val level: CefrLevel?,
)

/**
 * Everything the page can show, read from disk ONCE per language/revision.
 * Lenses, filters and search then run in memory: a keystroke must never cost
 * a file read, and the All lens holds the whole core word list.
 */
private data class Material(
    val toStudy: List<LibraryRowData> = emptyList(),
    val known: List<LibraryRowData> = emptyList(),
    /** The rest of the core word list, alphabetical. Empty for expressions —
     *  there is no lexicon of phrases to fall back on. */
    val pool: List<LibraryRowData> = emptyList(),
) {
    /** The learner's own words (to study, then retired), then the rest of the
     *  list — the All lens, and what search sweeps. */
    fun union(): List<LibraryRowData> {
        val seen = HashSet<String>()
        return (toStudy + known + pool).filter { seen.add(it.key) }
    }

    fun visible(lens: Lens, source: SourceFilter, level: CefrLevel?, query: String): List<LibraryRowData> {
        // Search reads the WHOLE pool, whatever lens is up.
        var items = if (query.isNotEmpty()) union() else when (lens) {
            Lens.TO_STUDY -> toStudy
            Lens.KNOWN -> known
            Lens.ALL -> union()
        }
        if (query.isEmpty() && lens == Lens.TO_STUDY && source != SourceFilter.ALL) {
            items = items.filter {
                when (it.from) {
                    is From.Scene -> source == SourceFilter.SCENES
                    is From.Kept, is From.Said -> source == SourceFilter.TALKS
                    else -> false
                }
            }
        }
        if (level != null) items = items.filter { it.level == level }
        if (query.isNotEmpty()) {
            // Prefix matches first — "par" should surface "parse" before "spare".
            items = items.filter { it.key.contains(query) }
                .sortedWith(compareBy({ !it.key.startsWith(query) }, { it.key }))
        }
        return items
    }
}

/**
 * A gloss is a network round trip, so rows draw first and fill in after: one
 * is asked for only once a row has been on screen for [GLOSS_SETTLE_MS] (a
 * flick through 8,000 core words must not fire 8,000 lookups), and the screen
 * spends at most [MAX_GLOSSES] of them in total — the same cap `BookGlossary`
 * puts on an export. An empty string means the lookup ran and had nothing to
 * show: the row keeps its provenance line and never asks again.
 */
private const val MAX_GLOSSES = 40
private const val GLOSS_SETTLE_MS = 250L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(kind: LibraryKind, language: String,
                  /** Shadowing runs its own screen; the card hands it one line. */
                  onShadow: (String) -> Unit = {},
                  onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val lore = remember { WordLore(AuthRepository()) }
    // The learner's own language, off the same key the word card reads — this
    // screen is handed only the target language.
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }

    var material by remember(kind, language) { mutableStateOf(Material()) }
    var lens by remember(kind) { mutableStateOf(Lens.TO_STUDY) }
    var source by remember(kind) { mutableStateOf(SourceFilter.ALL) }
    var level by remember(kind) { mutableStateOf<CefrLevel?>(null) }
    var query by remember(kind) { mutableStateOf("") }
    var filterOpen by remember { mutableStateOf(false) }
    /** Gloss per row key; survives scrolling, cleared with the language. */
    val glosses = remember(kind, language) { mutableStateMapOf<String, String>() }
    /** The term whose card is open. A verdict taken on the card rewrites the
     *  list underneath it, so the card walks a SNAPSHOT of the list it was
     *  opened from — otherwise marking something known would drop the row and
     *  slide the next/previous terms out from under the thumb. */
    var openTerm by remember { mutableStateOf<String?>(null) }
    var openList by remember { mutableStateOf<List<String>>(emptyList()) }

    LaunchedEffect(kind, language, revision) {
        material = if (kind == LibraryKind.WORDS) loadWords(context, language)
        else loadExpressions(context, language)
    }

    val trimmed = query.trim().lowercase()
    val rows = remember(material, lens, source, level, trimmed) {
        material.visible(lens, source, level, trimmed)
    }
    // Words only: expressions have no lexicon to search and no CEFR band.
    val searchable = kind == LibraryKind.WORDS
    val filtering = (lens == Lens.TO_STUDY && source != SourceFilter.ALL) || level != null

    Scaffold(
        topBar = {
            androidx.compose.material3.TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(stringResource(
                        if (kind == LibraryKind.WORDS) R.string.words_d26d55
                        else R.string.expressions))
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 16.dp),
        ) {
            if (searchable) {
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    label = { Text(stringResource(R.string.search_words)) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    trailingIcon = {
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { query = "" }) {
                                Icon(Icons.Filled.Close,
                                    contentDescription = stringResource(R.string.clear))
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }

            // The lens picker and the filter menu share one row — filtering
            // belongs beside the thing it filters, not up in the toolbar.
            androidx.compose.foundation.layout.Row(
                Modifier.fillMaxWidth().padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val lenses = if (kind == LibraryKind.WORDS) Lens.entries
                else listOf(Lens.TO_STUDY, Lens.KNOWN)
                SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
                    lenses.forEachIndexed { i, option ->
                        SegmentedButton(
                            selected = lens == option,
                            onClick = { lens = option },
                            shape = SegmentedButtonDefaults.itemShape(i, lenses.size),
                        ) { Text(lensLabel(option), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    }
                }
                if (searchable) {
                    Box {
                        IconButton(onClick = { filterOpen = true }) {
                            Icon(Icons.Filled.FilterList,
                                contentDescription = stringResource(R.string.filter),
                                tint = if (filtering) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        FilterMenu(
                            open = filterOpen, lens = lens, source = source, level = level,
                            onSource = { source = it }, onLevel = { level = it },
                            onDismiss = { filterOpen = false },
                        )
                    }
                }
            }

            LazyColumn(Modifier.fillMaxSize()) {
                if (rows.isEmpty()) {
                    item { EmptyState(kind, lens, searching = trimmed.isNotEmpty() || filtering) }
                } else {
                    item {
                        // What this lens (and any filter or search) adds up to.
                        GroupedSectionHeader(stringResource(
                            if (kind == LibraryKind.WORDS) R.string.lld_words
                            else R.string.lld_expressions, rows.size))
                    }
                }

                items(rows, key = { it.key }) { row ->
                    LibraryRow(row, glosses[row.key], onOpen = {
                        openList = rows.map { it.text }
                        openTerm = row.text
                    })
                    LaunchedEffect(row.key) {
                        if (glosses.containsKey(row.key)) return@LaunchedEffect
                        // Cancelled with the row if it scrolls past before it
                        // settles, so a fast flick asks for nothing.
                        delay(GLOSS_SETTLE_MS)
                        // The budget is read AFTER the wait: a screenful of
                        // rows settles together, and checking on the way in
                        // would let all of them past a nearly spent one.
                        if (glosses.containsKey(row.key) || glosses.size >= MAX_GLOSSES) {
                            return@LaunchedEffect
                        }
                        glosses[row.key] = ""   // claim the slot; also the no-entry answer
                        val entry = try {
                            lore.entry(row.text, nativeLanguage, language,
                                if (kind == LibraryKind.WORDS) WordLore.Kind.WORD
                                else WordLore.Kind.EXPRESSION)
                        } catch (cancelled: kotlinx.coroutines.CancellationException) {
                            throw cancelled   // the row scrolled away; write nothing
                        } catch (failure: Exception) {
                            null              // a dead lookup leaves the provenance line
                        }
                        glosses[row.key] = entry?.senses?.firstOrNull()?.meaning?.trim().orEmpty()
                    }
                }

                if (rows.isNotEmpty() && trimmed.isEmpty()) {
                    footerFor(kind, lens)?.let { item { GroupedFooter(stringResource(it)) } }
                }
                item { GroupedSectionSpacer() }
            }
        }
    }

    openTerm?.let { term ->
        WordCardSheet(
            terms = openList,
            initialTerm = term,
            kind = kind,
            language = language,
            onShadow = { line -> openTerm = null; onShadow(line) },
            onDismiss = { openTerm = null },
        )
    }
}

// ── The material ──

/**
 * The words page's three piles.
 *
 * The "used" half is re-derived from the talks themselves. [VocabStore]
 * exposes no bulk read of its records — only one word at a time, a file read
 * each — so listing the retired words by probing 8,000 core words is not an
 * option. `VocabStore.ingest` builds those records out of exactly this: the
 * core-list lemmas in a finished talk's user turns, counted once per session.
 * Reading them back the same way costs one pass over the sessions file, which
 * the expressions side of this screen already pays. The notebook and the
 * scene books are short enough to probe word by word, as `DailyStudyPick`
 * does.
 */
private suspend fun loadWords(context: Context, language: String): Material =
    withContext(Dispatchers.Default) {
        val vocab = VocabStore.shared(context)
        val core = CoreVocabulary.set(language)

        val saidCount = HashMap<String, Int>()
        val saidAt = HashMap<String, Long>()
        for (session in SessionStore.shared(context).load(language)
            .filter { it.endedAt != null }
            .sortedByDescending { it.rank }) {
            val texts = session.turns.filter { it.role == TurnRole.USER }.map { it.transcript }
            for (word in VocabLemmas.lemmas(texts)) {
                if (word !in core) continue
                saidCount[word] = (saidCount[word] ?: 0) + 1
                saidAt.putIfAbsent(word, session.rank)   // newest session first
            }
        }

        val seen = HashSet<String>()
        val toStudy = ArrayList<LibraryRowData>()
        /** Retired by hand: a record with no talk behind it. */
        val marked = ArrayList<LibraryRowData>()

        val studying = vocab.studying(language)
        val studyingKeys = studying.map { it.trim().lowercase() }.toSet()
        for (word in studying) {
            val key = word.trim().lowercase()
            if (key.isEmpty() || !seen.add(key)) continue
            val record = vocab.state(key, language) != null
            toStudy += LibraryRowData(word, key, kept = true, known = record,
                from = From.Kept(saidCount[key] ?: 0),
                level = CoreVocabulary.level(key, language))
            if (record && key !in saidCount) {
                marked += LibraryRowData(word, key, kept = true, known = true,
                    from = From.Kept(0), level = CoreVocabulary.level(key, language))
            }
        }

        for (scenario in ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
            .sortedByDescending { it.lastUsedAt ?: it.createdAt }) {
            val title = scenario.environment.trim()
            for (item in scenario.curriculum?.words.orEmpty()) {
                if (item.masteredAt != null) continue
                val key = item.text.trim().lowercase()
                if (key.isEmpty() || !seen.add(key)) continue
                val level = CoreVocabulary.level(key, language)
                // A record means the word is already retired — the same rule
                // the Practice tile's count uses.
                if (key in saidCount) continue
                if (vocab.state(key, language) != null) {
                    marked += LibraryRowData(item.text, key, kept = false, known = true,
                        from = From.Scene(title), level = level)
                    continue
                }
                toStudy += LibraryRowData(item.text, key, kept = false, known = false,
                    from = From.Scene(title), level = level)
            }
        }

        val known = saidCount.keys.sortedByDescending { saidAt[it] ?: 0L }
            .map { key ->
                LibraryRowData(key, key, kept = key in studyingKeys, known = true,
                    from = From.Kept(saidCount[key] ?: 0),
                    level = CoreVocabulary.level(key, language))
            } + marked

        val personal = seen + saidCount.keys
        val pool = core.asSequence().filter { it !in personal }.sorted()
            .map {
                LibraryRowData(it, it, kept = false, known = false, from = From.Pool,
                    level = CoreVocabulary.level(it, language))
            }
            .toList()

        Material(toStudy = toStudy, known = known, pool = pool)
    }

/**
 * The expressions page. The MERGED catalog, not the store: a phrase the
 * fluent self used and the learner hasn't said has no record — by design —
 * and reading the store alone dropped exactly the class of expression the
 * library exists to teach.
 */
private suspend fun loadExpressions(context: Context, language: String): Material {
    val rows = ExpressionCatalog.all(context, language).map { item ->
        LibraryRowData(
            text = item.text,
            key = item.text.trim().lowercase(),
            kept = item.bookmarked,
            known = item.known,
            from = when (item.origin) {
                ExpressionCatalog.Origin.HEARD -> From.Heard
                // The catalog doesn't carry which scene taught it, so the row
                // says the shelf instead of inventing a title.
                ExpressionCatalog.Origin.SCENE -> From.Scene("")
                ExpressionCatalog.Origin.SAID -> From.Said(item.count, item.lastAt)
            },
            level = null,
        )
    }
    return Material(toStudy = rows.filter { !it.known }, known = rows.filter { it.known })
}

// ── Pieces ──

@Composable
private fun lensLabel(lens: Lens): String = stringResource(
    when (lens) {
        Lens.TO_STUDY -> R.string.to_study
        Lens.KNOWN -> R.string.known
        Lens.ALL -> R.string.all_words
    }
)

@Composable
private fun FilterMenu(
    open: Boolean, lens: Lens, source: SourceFilter, level: CefrLevel?,
    onSource: (SourceFilter) -> Unit, onLevel: (CefrLevel?) -> Unit, onDismiss: () -> Unit,
) {
    DropdownMenu(expanded = open, onDismissRequest = onDismiss) {
        // Known words are all the learner's own, so the source picker only
        // means something on the study pile.
        if (lens == Lens.TO_STUDY) {
            MenuLabel(stringResource(R.string.source))
            SourceFilter.entries.forEach { option ->
                CheckedMenuItem(
                    label = stringResource(when (option) {
                        SourceFilter.ALL -> R.string.all_sources
                        SourceFilter.TALKS -> R.string.from_talks
                        SourceFilter.SCENES -> R.string.from_scenarios
                    }),
                    checked = source == option,
                ) { onSource(option); onDismiss() }
            }
            HorizontalDivider()
        }
        MenuLabel(stringResource(R.string.level_7c7f5d))
        CheckedMenuItem(stringResource(R.string.all_levels), checked = level == null) {
            onLevel(null); onDismiss()
        }
        CefrLevel.entries.forEach { option ->
            CheckedMenuItem(option.code.uppercase(), checked = level == option) {
                onLevel(option); onDismiss()
            }
        }
    }
}

@Composable
private fun MenuLabel(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 12.dp, top = 8.dp, bottom = 4.dp))
}

@Composable
private fun CheckedMenuItem(label: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = {
            // The column stays reserved whether or not the row is the chosen
            // one, so picking another doesn't shuffle the labels sideways.
            Icon(Icons.Filled.Check, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = if (checked) MaterialTheme.colorScheme.primary else Color.Transparent)
        },
        onClick = onClick,
    )
}

@Composable
private fun EmptyState(kind: LibraryKind, lens: Lens, searching: Boolean) {
    // Three different nothings: nothing matched a search or a filter, and a
    // genuinely empty pile — only the last one should say what to go do.
    val title = when {
        searching -> R.string.no_matching_words
        lens == Lens.KNOWN -> R.string.nothing_marked_known
        else -> R.string.nothing_to_study_yet
    }
    val message = when {
        searching -> null
        kind == LibraryKind.WORDS && lens == Lens.KNOWN ->
            R.string.words_you_say_in_a_talk_land_here_on_their_own_you_can_also_d9bbe4
        kind == LibraryKind.WORDS ->
            R.string.keep_a_word_from_a_talk_or_watch_a_situation_its_words_colle_b07a48
        lens == Lens.KNOWN -> R.string.mark_expressions_you_ve_got_down_as_known
        else -> R.string.expressions_from_your_calls_yours_and_your_fluent_self_s_and_c2c203
    }
    Column(
        Modifier.fillMaxWidth().padding(30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(stringResource(title), style = MaterialTheme.typography.titleSmall,
            textAlign = TextAlign.Center)
        message?.let {
            Text(stringResource(it), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
    }
}

private fun footerFor(kind: LibraryKind, lens: Lens): Int? = when {
    kind == LibraryKind.WORDS && lens == Lens.TO_STUDY ->
        R.string.words_you_kept_from_a_talk_plus_the_ones_your_watched_scenes_c0f27c
    kind == LibraryKind.WORDS && lens == Lens.KNOWN ->
        R.string.words_you_ve_used_out_loud_or_marked_as_known
    kind == LibraryKind.EXPRESSIONS && lens == Lens.TO_STUDY ->
        R.string.captured_from_what_you_say_what_your_fluent_self_says_back_a_5f4946
    else -> null
}

@Composable
private fun LibraryRow(row: LibraryRowData, gloss: String?, onOpen: () -> Unit) {
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // Badge grammar, shared with the card: bookmark = in the notebook,
        // check = retired.
        if (row.kept || row.known) {
            Icon(
                if (row.kept) Icons.Filled.Bookmark else Icons.Filled.Check,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = if (row.kept) MaterialTheme.colorScheme.primary else Color(0xFF34C759),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(row.text, style = MaterialTheme.typography.bodyLarge)
            // The meaning is CONTENT, not metadata — and until it lands (or
            // when there is none) the row says where the term came from.
            if (!gloss.isNullOrEmpty()) {
                Text(gloss, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            } else {
                Provenance(row)
            }
        }
        // The row opens a card now, and a list of bare words gives no sign of
        // it — the chevron is the only thing saying the tap does anything.
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Provenance(row: LibraryRowData) {
    val icon = when (row.from) {
        is From.Scene -> Icons.Filled.Movie
        From.Heard -> Icons.Filled.ChatBubbleOutline
        else -> null
    }
    val text = when (val from = row.from) {
        is From.Kept ->
            if (from.count > 0) stringResource(R.string.said_lld, from.count)
            else stringResource(R.string.kept_from_a_talk)
        is From.Said -> stringResource(R.string.used_lld_time, from.count,
            if (from.count == 1) "" else "s", shortDate(from.at))
        is From.Scene -> from.title.ifEmpty { stringResource(R.string.from_scenarios) }
        From.Heard -> stringResource(R.string.heard_in_a_call)
        From.Pool -> row.level?.code?.uppercase().orEmpty()
    }
    if (text.isEmpty()) return
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        icon?.let {
            Icon(it, contentDescription = null, modifier = Modifier.size(12.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(text, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun shortDate(at: Long): String =
    SimpleDateFormat("d MMM", Locale.getDefault()).format(Date(at))
