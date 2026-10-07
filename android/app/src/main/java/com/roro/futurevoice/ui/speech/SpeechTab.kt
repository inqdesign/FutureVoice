package com.roro.futurevoice.ui.speech

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.AccountBox
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Newspaper
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechGate
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.SpeechScriptEngine
import com.roro.futurevoice.ui.FormCard
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.GroupedCard
import com.roro.futurevoice.ui.GroupedFooter
import com.roro.futurevoice.ui.GroupedRowDivider
import com.roro.futurevoice.ui.GroupedSectionHeader
import com.roro.futurevoice.ui.IosSwipeAction
import com.roro.futurevoice.ui.IosSwipeActions
import com.roro.futurevoice.ui.PaywallScreen
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.bottomBarInsets
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.IosSegmented
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * The Speech tab — iOS `SpeechTab`: read a script aloud like a presenter,
 * under a prompter that follows your voice, camera on or off, and get the
 * take scored. Nothing here synthesizes speech; the only voice is the
 * learner's.
 */

/** What the header's + asked for — the header and the page are composed
 *  apart (the root's top bar vs the tab body), so they meet here. */
internal object SpeechTabRequests {
    enum class Kind { WRITE, OWN, UPSELL }
    val pending = MutableStateFlow<Kind?>(null)
}

/** The header's one action (iOS `.topBarTrailing` + / its Menu). */
@Composable
internal fun SpeechHeaderAction() {
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.padding(end = 12.dp)) {
        IosGlassButton(onClick = {
            if (SpeechGate.cachedCanWrite) menu = true
            // Not known to be Plus: ask fresh. A purchase a minute ago must
            // not be met with the upsell again.
            else scope.launch {
                if (SpeechGate.allowsSpeechScripts(AuthRepository())) menu = true
                else SpeechTabRequests.pending.value = SpeechTabRequests.Kind.UPSELL
            }
        }, circle = true) {
            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.new_script),
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
        }
        com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.write_with_ai)) },
                leadingIcon = { Icon(Icons.Filled.AutoAwesome, null) },
                onClick = { menu = false; SpeechTabRequests.pending.value = SpeechTabRequests.Kind.WRITE })
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(text = { Text(stringResource(R.string.add_my_own_script)) },
                leadingIcon = { Icon(Icons.Outlined.EditNote, null) },
                onClick = { menu = false; SpeechTabRequests.pending.value = SpeechTabRequests.Kind.OWN })
        }
    }
}

/** The tab's page: the scripts, newest after the bundled sample. Tapping a
 *  script opens its prompter straight away — picking one IS starting to
 *  practise it (iOS `2ec50658`). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun SpeechTabBody(language: String, native: String, level: CefrLevel) {
    val context = LocalContext.current
    val store = remember { SpeechStore.shared(context) }
    val scripts by store.scripts.collectAsStateWithLifecycle()
    val takes by store.takes.collectAsStateWithLifecycle()
    var practicing by remember { mutableStateOf<SpeechScript?>(null) }
    var editing by remember { mutableStateOf<SpeechScript?>(null) }
    val request by SpeechTabRequests.pending.collectAsStateWithLifecycle()
    LaunchedEffect(language) { store.reload() }
    LaunchedEffect(Unit) { store.reloadIfLanguageChanged() }
    val canWrite = SpeechGate.cachedCanWrite

    Column {
        GroupedSectionHeader(stringResource(R.string.scripts))
        GroupedCard {
            scripts.forEachIndexed { i, script ->
                if (i > 0) GroupedRowDivider()
                // iOS `.swipeActions(edge: .trailing)`: Delete (not the
                // bundled sample) outermost, then Edit (own scripts, accent);
                // a full swipe deletes.
                val deleteLabel = stringResource(R.string.delete)
                val editLabel = stringResource(R.string.edit)
                val accent = MaterialTheme.colorScheme.primary
                val actions = buildList {
                    if (!script.isBuiltIn) add(IosSwipeAction(Icons.Filled.Delete, deleteLabel, Color(0xFFFF3B30)) {
                        store.deleteScript(script.id)
                    })
                    if (script.genre == SpeechGenre.OWN) add(IosSwipeAction(Icons.Filled.Edit, editLabel, accent) {
                        editing = script
                    })
                }
                IosSwipeActions(actions, background = AppSurfaces.card) {
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable { practicing = script }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(script.genre.icon(), contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(script.title, style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            val parts = listOfNotNull(
                                lengthLabel(SpeechLibrary.estimatedSeconds(script.body, script.language)),
                                script.genre.title(),
                                if (script.isBuiltIn) stringResource(R.string.sample) else null,
                            )
                            Text(parts.joinToString("  ·  "), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        val best = takes.filter { it.scriptId == script.id }.maxOfOrNull { it.metrics.overall }
                        if (best != null) {
                            Spacer(Modifier.width(8.dp))
                            Text("$best", style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold, color = scoreColor(best))
                        }
                    }
                }
            }
        }
        if (!canWrite) GroupedFooter(stringResource(R.string.write_scripts_on_any_topic_or_add_your_own_with_plus))
    }

    when (request) {
        SpeechTabRequests.Kind.WRITE -> SpeechComposerSheet(language, native, level,
            onWritten = { s -> store.add(s); practicing = s },
            onDismiss = { SpeechTabRequests.pending.value = null })
        SpeechTabRequests.Kind.OWN -> SpeechOwnScriptSheet(existing = null, language = language, native = native,
            onSave = { s -> store.add(s); practicing = s },
            onDismiss = { SpeechTabRequests.pending.value = null })
        SpeechTabRequests.Kind.UPSELL -> SpeechPlusSheet(
            isLight = BillingGate.account?.isLightPlan ?: false,
            onDismiss = { SpeechTabRequests.pending.value = null })
        null -> Unit
    }
    editing?.let { s ->
        SpeechOwnScriptSheet(existing = s, language = s.language, native = native,
            onSave = { store.add(it) }, onDismiss = { editing = null })
    }
    practicing?.let { s ->
        Dialog(
            onDismissRequest = {},
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false,
                dismissOnBackPress = false),
        ) {
            SpeechPrompterScreen(s, native, level, onClose = { practicing = null })
        }
    }
}

// MARK: - Shared bits

internal fun SpeechGenre.icon(): ImageVector = when (this) {
    SpeechGenre.EXPLAINER -> Icons.Outlined.Lightbulb
    SpeechGenre.PRODUCT -> Icons.Outlined.Inventory2
    SpeechGenre.PERSON -> Icons.Outlined.AccountBox
    SpeechGenre.BRIEFING -> Icons.Outlined.Info
    SpeechGenre.NEWS -> Icons.Outlined.Newspaper
    SpeechGenre.OWN -> Icons.Outlined.EditNote
}

@Composable
internal fun SpeechGenre.title(): String = stringResource(when (this) {
    SpeechGenre.EXPLAINER -> R.string.speech_genre_explain
    SpeechGenre.PRODUCT -> R.string.speech_genre_product
    SpeechGenre.PERSON -> R.string.speech_genre_person
    SpeechGenre.BRIEFING -> R.string.speech_genre_briefing
    SpeechGenre.NEWS -> R.string.speech_genre_news
    SpeechGenre.OWN -> R.string.speech_genre_own
})

@Composable
private fun SpeechGenre.blurb(): String = stringResource(when (this) {
    SpeechGenre.EXPLAINER -> R.string.how_or_why_something_works
    SpeechGenre.PRODUCT -> R.string.present_a_real_product_or_invention
    SpeechGenre.PERSON -> R.string.introduce_someone_worth_knowing
    SpeechGenre.BRIEFING -> R.string.useful_information_clearly_told
    SpeechGenre.NEWS -> R.string.read_the_news_like_an_anchor
    SpeechGenre.OWN -> R.string.your_own_text
})

@Composable
private fun SpeechGenre.topicPlaceholder(): String = when (this) {
    SpeechGenre.EXPLAINER -> stringResource(R.string.e_g_why_the_sky_is_blue)
    SpeechGenre.PRODUCT -> stringResource(R.string.e_g_the_first_iphone)
    SpeechGenre.PERSON -> stringResource(R.string.e_g_marie_curie)
    SpeechGenre.BRIEFING -> stringResource(R.string.e_g_how_to_sleep_better_on_a_long_flight)
    SpeechGenre.NEWS -> stringResource(R.string.e_g_space_news_this_month)
    SpeechGenre.OWN -> ""
}

/** iOS `SpeechFormat.length`. */
@Composable
internal fun lengthLabel(seconds: Int): String =
    if (seconds < 60) stringResource(R.string.lld_sec, seconds)
    else stringResource(R.string.lld_min_b61908, seconds / 60)

/** iOS `SpeechFormat.duration`: m:ss. */
internal fun clockLabel(seconds: Double): String {
    val s = Math.round(seconds).toInt()
    return "%d:%02d".format(s / 60, s % 60)
}

/** iOS `SpeechScoreColor`. */
internal fun scoreColor(score: Int): Color =
    if (score >= 85) Color(0xFF34C759) else if (score >= 65) Color(0xFFFF9500) else Color(0xFFFF3B30)

/**
 * A sheet on the page ground. iOS presents these with `.sheet` and no
 * detents — the LARGE detent, the whole screen below the status bar — so
 * [fullHeight] fills the screen however short the content; only the Plus
 * sheet (iOS `.height(560)`) hugs its content. Capture runs draw it inline,
 * as iOS's harness returns the view itself rather than presenting it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechSheet(onDismiss: () -> Unit, dismissible: Boolean = true, fullHeight: Boolean = true,
                         content: @Composable ColumnScope.() -> Unit) {
    val body: @Composable (Modifier) -> Unit = { m ->
        Column(
            m.fillMaxWidth().then(if (fullHeight) Modifier.fillMaxHeight() else Modifier)
                .bottomBarInsets().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
            content = content,
        )
    }
    if (com.roro.futurevoice.capture.flags.SpeechCaptureFlags.inlineSheets) {
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) { body(Modifier.statusBarsPadding()) }
        return
    }
    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { dismissible }),
        onDismissRequest = { if (dismissible) onDismiss() },
        containerColor = AppSurfaces.ground, dragHandle = null,
    ) { body(Modifier) }
}

// MARK: - Composer

/** Writing a new script: what kind, about what (optional), how long — iOS
 *  `SpeechComposerSheet`. Plus and up; the caller checked. */
@Composable
internal fun SpeechComposerSheet(language: String, native: String, level: CefrLevel,
                                onWritten: (SpeechScript) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE) }
    var genre by remember {
        mutableStateOf(SpeechGenre.writable.firstOrNull { it.raw == prefs.getString("speech.composer.genre", null) }
            ?: SpeechGenre.EXPLAINER)
    }
    var seconds by remember { mutableStateOf(prefs.getInt("speech.composer.seconds", 60)) }
    var topic by remember { mutableStateOf("") }
    var writing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val failed = stringResource(R.string.the_script_couldn_t_be_written_try_again)

    fun write() {
        writing = true
        prefs.edit().putString("speech.composer.genre", genre.raw).putInt("speech.composer.seconds", seconds).apply()
        val avoid = SpeechStore.shared(context).scripts.value.map { it.title }
        scope.launch {
            try {
                val script = SpeechScriptEngine.write(genre, topic, seconds, language, native, level, avoid)
                Analytics.capture("speech_script_written", mapOf(
                    "genre" to genre.raw, "seconds" to seconds, "topic" to topic.isNotBlank()))
                writing = false
                onDismiss()
                onWritten(script)
            } catch (_: Exception) {
                writing = false
                error = failed
            }
        }
    }

    SpeechSheet(onDismiss, dismissible = !writing) {
        SheetHeader(stringResource(R.string.new_script),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = { if (!writing) onDismiss() }) },
            trailing = { IosGlassTextButton(stringResource(R.string.write), onClick = { if (!writing) write() }, bold = true) })
        Box {
            Column {
                FormSection(stringResource(R.string.type)) {
                    SpeechGenre.writable.forEachIndexed { i, g ->
                        if (i > 0) FormDivider(inset = 56.dp)
                        Row(Modifier.fillMaxWidth().clickable(enabled = !writing) { genre = g }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Icon(g.icon(), null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f)) {
                                Text(g.title(), style = MaterialTheme.typography.bodyLarge)
                                Text(g.blurb(), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            // iOS's inline Picker: a trailing check on the chosen one.
                            if (g == genre) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                FormSection(stringResource(R.string.topic),
                    footer = stringResource(R.string.leave_it_empty_and_we_ll_pick_something_worth_knowing)) {
                    PlainField(topic, { topic = it }, genre.topicPlaceholder(), enabled = !writing, minLines = 1, maxLines = 3)
                }
                FormSection(stringResource(R.string.length)) {
                    Box(Modifier.padding(12.dp)) {
                        val options = SpeechLibrary.lengths.map { lengthLabel(it) }
                        IosSegmented(options, SpeechLibrary.lengths.indexOf(seconds).coerceAtLeast(0),
                            onSelect = { if (!writing) seconds = SpeechLibrary.lengths[it] },
                            modifier = Modifier.fillMaxWidth())
                    }
                }
            }
            if (writing) {
                Column(Modifier.align(Alignment.Center)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(16.dp))
                    .padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator()
                    Text(stringResource(R.string.writing_your_script), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
    error?.let { msg ->
        AlertDialog(onDismissRequest = { error = null },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.couldn_t_write_the_script)) },
            text = { Text(msg) })
    }
}

/** A borderless text field inside a form card. */
@Composable
private fun PlainField(value: String, onChange: (String) -> Unit, placeholder: String,
                       enabled: Boolean = true, minLines: Int = 1, maxLines: Int = 1,
                       modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = value, onValueChange = onChange, enabled = enabled,
        placeholder = { Text(placeholder) }, minLines = minLines, maxLines = maxLines,
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent,
            disabledBorderColor = Color.Transparent,
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent),
        modifier = modifier.fillMaxWidth(),
    )
}

// MARK: - Your own script

/** Type or paste a text to practise — iOS `SpeechOwnScriptSheet`. Nothing is
 *  generated; the text is saved as given. Editing keeps what the script
 *  already was (an AI script stays one, with its summary and sources). */
@Composable
internal fun SpeechOwnScriptSheet(existing: SpeechScript?, language: String, native: String,
                                  onSave: (SpeechScript) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var title by remember { mutableStateOf(existing?.title.orEmpty()) }
    var text by remember { mutableStateOf(existing?.body.orEmpty()) }
    val lang = existing?.language ?: language.substringBefore('-')
    val trimmed = text.trim()

    fun save() {
        val given = title.trim()
        val script = SpeechScript(
            id = existing?.id ?: StoreJson.newId(),
            title = given.ifEmpty { SpeechLibrary.defaultTitle(trimmed) },
            genre = existing?.genre ?: SpeechGenre.OWN,
            topic = existing?.topic.orEmpty(),
            body = trimmed,
            summary = existing?.summary.orEmpty(),
            keyTerms = existing?.keyTerms.orEmpty().filter { trimmed.contains(it.term, ignoreCase = true) },
            sources = existing?.sources.orEmpty(),
            language = lang,
            targetSeconds = SpeechLibrary.estimatedSeconds(trimmed, lang),
            createdAt = existing?.createdAt ?: System.currentTimeMillis(),
            isBuiltIn = false,
        )
        if (existing == null) Analytics.capture("speech_script_added", mapOf("seconds" to script.targetSeconds))
        onDismiss()
        onSave(script)
    }

    SpeechSheet(onDismiss) {
        SheetHeader(stringResource(if (existing == null) R.string.my_script else R.string.edit_script),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onDismiss) },
            trailing = {
                IosGlassTextButton(stringResource(R.string.save), onClick = { save() },
                    bold = trimmed.isNotEmpty(), enabled = trimmed.isNotEmpty())
            })
        FormSection(null) {
            PlainField(title, { title = it }, stringResource(R.string.title_optional))
        }
        Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.script), style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                // iOS's system PasteButton, icon-only: a filled accent circle
                // with a white glyph, not a glass button.
                androidx.compose.foundation.layout.Box(
                    Modifier.size(36.dp)
                        .background(MaterialTheme.colorScheme.primary, androidx.compose.foundation.shape.CircleShape)
                        .clickable {
                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            val pasted = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
                                ?.coerceToText(context)?.toString().orEmpty()
                            if (pasted.isNotEmpty()) text = if (text.isEmpty()) pasted else text + "\n\n" + pasted
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.ContentPaste, contentDescription = null,
                        tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(18.dp))
                }
            }
            FormCard {
                PlainField(text, { text = it }, stringResource(R.string.type_or_paste_the_text_you_want_to_practise),
                    minLines = 10, maxLines = Int.MAX_VALUE, modifier = Modifier.heightIn(min = 260.dp))
            }
            val footer = if (trimmed.isNotEmpty())
                stringResource(R.string.about_to_read_leave_a_blank_line_between_paragraphs,
                    lengthLabel(maxOf(1, SpeechLibrary.estimatedSeconds(trimmed, lang))))
            else stringResource(R.string.write_it_in, LanguageCatalog.ownName(lang, native))
            Text(footer, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
        }
    }
}

// MARK: - Plus only

/** What a free or Light account sees on "+": the feature, said first, and
 *  the way to it — iOS `SpeechPlusSheet` (`d5566b32`). The paywall opens only
 *  from here, on purpose. */
@Composable
internal fun SpeechPlusSheet(isLight: Boolean, onDismiss: () -> Unit) {
    var paywall by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { Analytics.capture("speech_plus_sheet", mapOf("light" to isLight)) }
    SpeechSheet(onDismiss, fullHeight = false) {
        SheetHeader("", leading = {
            IosGlassButton(onClick = onDismiss, circle = true) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close),
                    tint = MaterialTheme.colorScheme.onSurface)
            }
        })
        Column(Modifier.padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Lock, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.plus_and_max), style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                }
                Text(stringResource(R.string.new_scripts_are_a_plus_feature),
                    style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.the_sample_script_stays_free_to_practise_with_plus_or_max_pr_9a1a82),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                PlusFeature(Icons.Filled.AutoAwesome, stringResource(R.string.write_with_ai),
                    stringResource(R.string.explainers_products_people_briefings_and_news_true_and_at_yo_43f83e))
                PlusFeature(Icons.Outlined.EditNote, stringResource(R.string.add_your_own_script),
                    stringResource(R.string.a_presentation_a_pitch_a_speech_you_have_to_give))
            }
            Spacer(Modifier.heightIn(min = 40.dp))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                IosButton(onClick = { paywall = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(if (isLight) R.string.upgrade_to_plus else R.string.see_plans),
                        fontWeight = FontWeight.SemiBold)
                }
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.not_now))
                }
            }
        }
    }
    if (paywall) {
        Dialog(onDismissRequest = { paywall = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)) {
            PaywallScreen(onDismiss = {
                paywall = false
                // Bought Plus in the paywall: this sheet has nothing left to say.
                scope.launch {
                    BillingGate.invalidate()
                    if (SpeechGate.allowsSpeechScripts(AuthRepository())) onDismiss()
                }
            }, preselectTier = "plus")
        }
    }
}

@Composable
private fun PlusFeature(icon: ImageVector, title: String, detail: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// MARK: - The whole script

/** The full text with its notes, opened from the prompter's script button —
 *  iOS `SpeechScriptSheet`. Editable unless it is the bundled sample (iOS
 *  `67e60a53`); an edit is handed back so the prompter reads it at once. */
@Composable
internal fun SpeechScriptSheet(script: SpeechScript, native: String, onEdited: (SpeechScript) -> Unit,
                               onDismiss: () -> Unit) {
    val context = LocalContext.current
    var shown by remember { mutableStateOf(script) }
    var editing by remember { mutableStateOf(false) }
    SpeechSheet(onDismiss) {
        SheetHeader(stringResource(R.string.script),
            leading = if (!shown.isBuiltIn) ({
                IosGlassTextButton(stringResource(R.string.edit), onClick = { editing = true })
            }) else null,
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        FormCard {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(shown.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                if (shown.summary.isNotEmpty()) {
                    Text(shown.summary, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                SelectionContainer {
                    Text(shown.body, style = MaterialTheme.typography.bodyLarge.copy(
                        lineHeight = MaterialTheme.typography.bodyLarge.lineHeight * 1.2f),
                        modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        Text(listOf(shown.genre.title(), lengthLabel(SpeechLibrary.estimatedSeconds(shown.body, shown.language)))
            .joinToString("  ·  "), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp, top = 7.dp))
        if (shown.keyTerms.isNotEmpty()) {
            FormSection(stringResource(R.string.key_terms)) {
                shown.keyTerms.forEachIndexed { i, t ->
                    if (i > 0) FormDivider()
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Text(t.term, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                        if (t.meaning.isNotEmpty()) Text(t.meaning, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (shown.sources.isNotEmpty()) {
            FormSection(stringResource(R.string.sources)) {
                Text(shown.sources.joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
            }
        }
    }
    if (editing) {
        SpeechOwnScriptSheet(existing = shown, language = shown.language, native = native,
            onSave = { updated ->
                SpeechStore.shared(context).add(updated)
                shown = updated
                onEdited(updated)
            }, onDismiss = { editing = false })
    }
}

// MARK: - Takes

/** Every take of one script, newest first, each opening its result — iOS
 *  `SpeechTakesSheet`. */
@Composable
internal fun SpeechTakesSheet(scriptId: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val store = remember { SpeechStore.shared(context) }
    val all by store.takes.collectAsStateWithLifecycle()
    val takes = all.filter { it.scriptId == scriptId }
    var open by remember { mutableStateOf<SpeechTake?>(null) }
    if (open != null) {
        Dialog(onDismissRequest = { open = null },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
                SpeechResultScreen(takeId = open!!.id, live = null, onBack = { open = null }, onAgain = null)
            }
        }
    }
    SpeechSheet(onDismiss) {
        SheetHeader(stringResource(R.string.takes),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        if (takes.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(vertical = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.RadioButtonChecked, null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(40.dp))
                Text(stringResource(R.string.no_takes_yet), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.your_recordings_of_this_script_will_be_here),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            FormCard {
                takes.forEachIndexed { i, take ->
                    if (i > 0) FormDivider()
                    // iOS `.onDelete`: swipe left for Delete, a full swipe deletes.
                    IosSwipeActions(listOf(IosSwipeAction(Icons.Filled.Delete, stringResource(R.string.delete),
                        Color(0xFFFF3B30)) { store.deleteTake(take.id) }), background = AppSurfaces.card) {
                    Row(Modifier.fillMaxWidth()
                        .clickable { open = take }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(takeDateLabel(take.createdAt), style = MaterialTheme.typography.bodyLarge)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(clockLabel(take.durationSeconds), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (take.videoFilename != null) {
                                    Spacer(Modifier.width(6.dp))
                                    Icon(Icons.Filled.Videocam, null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                        Text("${take.metrics.overall}", style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold, color = scoreColor(take.metrics.overall))
                    }
                    }
                }
            }
        }
    }
}

/** iOS `.dateTime.month().day().hour().minute()`: month-day and time in the
 *  learner's locale, no year ("10월 5일 오후 9:17"). */
internal fun takeDateLabel(at: Long): String {
    val locale = java.util.Locale.getDefault()
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMdjmm")
    return java.text.SimpleDateFormat(pattern, locale).format(Date(at))
}
