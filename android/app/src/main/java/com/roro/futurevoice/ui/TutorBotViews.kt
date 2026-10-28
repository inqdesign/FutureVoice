package com.roro.futurevoice.ui

import android.content.res.Resources
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.QuickQuizStock
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.TutorBot
import com.roro.futurevoice.talk.TutorChat
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DialogueLine
import com.roro.futurevoice.ui.brand.DialogueSpeaker
import com.roro.futurevoice.ui.brand.IosDropdownMenu
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosMenuItem
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.Date

// The tutor bot's three surfaces (iOS `TutorBotViews.swift`): the face, the
// note and the bubble float over the Talk home; the chat is a sheet.

/**
 * The face at the bottom right (iOS `TutorBotButton`). Tap = ask; hold =
 * today's plan again, the quiz, or the bot's introduction.
 */
@Composable
fun TutorBotButton(state: AppState) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var menu by remember { mutableStateOf(false) }
    // The quiz the face used to open, still one hold away — and something
    // the tutor can hand you. Prewarmed in the foreground only.
    LaunchedEffect(lifecycle, state.targetLanguage, state.level) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            QuickQuizStock.prewarm(context.applicationContext, state.targetLanguage, state.nativeLanguage, state.level)
        }
    }
    val label = stringResource(R.string.tutor)
    val hint = stringResource(R.string.ask_what_to_do_next)
    Box {
        IosGlassButton(onClick = { TutorBot.openChat(context) },
            modifier = Modifier.size(52.dp).semantics { contentDescription = "$label. $hint" }, circle = true,
            onLongClick = { menu = true }) {
            WeeklyTestCharacter(
                if (TutorBot.bubble != null || TutorBot.noteShown) WeeklyTestHost.Mood.HAPPY else WeeklyTestHost.Mood.WAITING,
                TutorBot.bubbleSince, Modifier.size(30.dp), tile = Color.Transparent)
        }
        IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            IosMenuItem(stringResource(R.string.today_s_plan), onClick = { menu = false; TutorBot.showNote() },
                icon = Icons.AutoMirrored.Filled.List, reserveCheck = false)
            IosMenuItem(stringResource(R.string.quick_quiz), onClick = { menu = false; TutorBot.start(context, null) },
                icon = Icons.AutoMirrored.Outlined.HelpOutline, reserveCheck = false)
            IosMenuItem(stringResource(R.string.what_the_tutor_does),
                onClick = { menu = false; TutorBot.showNote(intro = true) },
                icon = Icons.Outlined.Info, reserveCheck = false)
        }
    }
    if (TutorBot.quizOpen) {
        Dialog(
            onDismissRequest = { TutorBot.quizOpen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            DialogSystemBarsLikeActivity()
            QuickQuizScreen(state.targetLanguage, state.nativeLanguage, state.level,
                onClose = { TutorBot.quizOpen = false })
        }
    }
    if (TutorBot.chatOpen) {
        TutorChatView(state, onDismiss = { TutorBot.chatOpen = false })
    }
}

/**
 * The note and the bubble, laid over the Talk home above the bottom row (iOS
 * `TutorBotLayer`). Nothing is dimmed and nothing blocks: a tap outside the
 * note folds it back into the face. [bottom] is where the bottom row's top
 * edge sits over the floating bar.
 */
@Composable
fun TutorBotLayer(state: AppState, onOpenRoutine: () -> Unit) {
    val context = LocalContext.current
    Box(Modifier.fillMaxSize()) {
        if (TutorBot.noteShown) {
            Box(Modifier.fillMaxSize().clickable(
                interactionSource = remember { MutableInteractionSource() }, indication = null,
            ) { TutorBot.closeNote(context) })
        }
        Box(Modifier.align(Alignment.BottomEnd)
            .windowInsetsPadding(WindowInsets.navigationBars)
            // The bottom row sits 76 + 16 dp over the nav bar, 52 dp tall
            // (iOS: the row's `.padding(16)`, the note 84 and the bubble 82
            // over the home's bottom edge).
            .padding(bottom = 76.dp)) {
            AnimatedVisibility(
                visible = TutorBot.noteShown,
                enter = scaleIn(tween(500), initialScale = 0.2f, transformOrigin = TransformOrigin(1f, 1f)) +
                    fadeIn(tween(500)),
                exit = scaleOut(tween(350), targetScale = 0.2f, transformOrigin = TransformOrigin(1f, 1f)) +
                    fadeOut(tween(350)),
            ) {
                TutorNoteCard(state, onOpenRoutine,
                    Modifier.padding(start = 12.dp, end = 12.dp, bottom = 84.dp))
            }
            val b = TutorBot.bubble
            AnimatedVisibility(
                visible = !TutorBot.noteShown && b != null,
                enter = slideInVertically(tween(350)) { it } + fadeIn(tween(350)),
                exit = slideOutVertically(tween(250)) { it } + fadeOut(tween(250)),
            ) {
                // Keep the last bubble drawn while it leaves.
                var shown by remember { mutableStateOf(b) }
                if (b != null) shown = b
                shown?.let { TutorBubbleView(it, Modifier.padding(end = 16.dp, bottom = 82.dp)) }
            }
        }
    }
}

// MARK: - The note

@Composable
private fun TutorNoteCard(state: AppState, onOpenRoutine: () -> Unit, modifier: Modifier) {
    Column(
        modifier
            .widthIn(max = 420.dp)
            .shadow(20.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(alpha = 0.18f),
                spotColor = Color.Black.copy(alpha = 0.18f))
            .background(AppSurfaces.card, RoundedCornerShape(24.dp))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (TutorBot.introShown) TutorIntro() else TutorPlan(state, onOpenRoutine)
    }
}

@Composable
private fun TutorFace() {
    WeeklyTestCharacter(WeeklyTestHost.Mood.HAPPY, TutorBot.bubbleSince, Modifier.size(40.dp))
}

/** The first meeting: who this is and what it does. */
@Composable
private fun TutorIntro() {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        TutorFace()
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.hi_i_m_your_tutor), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.i_know_your_routine_your_talks_your_mistakes_and_your_cards_651e4d),
                style = MaterialTheme.typography.bodyMedium)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IntroRow(Icons.Outlined.WbSunny, stringResource(R.string.once_a_day_i_leave_you_a_short_note_with_today_s_plan))
        IntroRow(Icons.Outlined.ChatBubbleOutline,
            stringResource(R.string.when_something_is_ready_i_ll_say_so_here_otherwise_i_stay_qu_1457bc))
        IntroRow(Icons.Outlined.TouchApp,
            stringResource(R.string.tap_me_any_time_to_ask_what_to_do_why_a_mistake_keeps_coming_17424f))
    }
    Box(Modifier.fillMaxWidth()) {
        WideSoftChip(stringResource(R.string.show_me_today)) { TutorBot.finishIntro(context) }
    }
}

/** A selected soft chip as wide as the card (iOS `.frame(maxWidth: .infinity)`). */
@Composable
private fun WideSoftChip(label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.Center,
    ) {
        Text(label, style = MaterialTheme.typography.titleSmall.copy(fontSize = androidx.compose.ui.unit.TextUnit(15f, androidx.compose.ui.unit.TextUnitType.Sp)),
            fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.primary, maxLines = 1)
    }
}

@Composable
private fun IntroRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun TutorPlan(state: AppState, onOpenRoutine: () -> Unit) {
    val context = LocalContext.current
    val res = context.resources
    val t = TutorBot.today
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        TutorFace()
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(TutorCopy.greeting(res), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(TutorCopy.summary(res, t), style = MaterialTheme.typography.bodyMedium)
            TutorCopy.why(res, t)?.let { why ->
                Text(why, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    if (t.items.isNotEmpty()) TutorPlanRows(t)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (t.suggested) {
            SoftChip(stringResource(R.string.make_a_routine)) {
                TutorBot.closeNote(context)
                onOpenRoutine()
            }
        } else {
            SoftChip(stringResource(R.string.later)) { TutorBot.closeNote(context) }
        }
        Spacer(Modifier.weight(1f))
        SoftChip(stringResource(R.string.ask_me), selected = true, vector = Icons.Outlined.ChatBubbleOutline) {
            TutorBot.openChat(context)
        }
    }
}

/** Today's items: done ones ticked, the next one with Start. Shared by the
 *  note and the chat's first message (iOS `TutorPlanRows`). */
@Composable
fun TutorPlanRows(today: TutorBot.Today) {
    val context = LocalContext.current
    val next = today.next()
    Column {
        today.items.forEachIndexed { i, item ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 40.dp),
                color = MaterialTheme.colorScheme.outlineVariant)
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
                    Icon(item.kind.icon(), contentDescription = null, tint = item.kind.color(),
                        modifier = Modifier.size(16.dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(item.title, style = MaterialTheme.typography.bodyMedium,
                        textDecoration = if (item.done) TextDecoration.LineThrough else null,
                        color = if (item.done) MaterialTheme.colorScheme.onSurfaceVariant
                            else MaterialTheme.colorScheme.onSurface)
                    Text(TutorCopy.whenText(context, item), style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                when {
                    item.done -> Icon(Icons.Filled.CheckCircle, contentDescription = null,
                        tint = Color(0xFF34C759), modifier = Modifier.size(22.dp))
                    item.id == next?.id -> SoftChip(stringResource(R.string.start), selected = true) {
                        TutorBot.start(context, item.kind)
                    }
                    item.progress > 0 -> CircularProgressIndicator(
                        progress = { item.progress.toFloat() }, modifier = Modifier.size(20.dp),
                        strokeWidth = 3.dp, trackColor = MaterialTheme.colorScheme.outlineVariant)
                    else -> Icon(Icons.Outlined.Circle, contentDescription = null,
                        tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

// MARK: - The bubble

@Composable
private fun TutorBubbleView(bubble: TutorBot.Bubble, modifier: Modifier) {
    val context = LocalContext.current
    val shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomEnd = 6.dp, bottomStart = 18.dp)
    Column(
        modifier
            .widthIn(max = 250.dp)
            .shadow(14.dp, shape, ambientColor = Color.Black.copy(alpha = 0.16f),
                spotColor = Color.Black.copy(alpha = 0.16f))
            .background(AppSurfaces.card, shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(bubble.text, style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (bubble.action != null) {
                SoftChip(bubble.action, selected = true) { TutorBot.start(context, bubble.kind) }
                SoftChip(stringResource(R.string.not_now)) { TutorBot.dismissBubble() }
            } else {
                SoftChip(stringResource(R.string.ok)) { TutorBot.dismissBubble() }
            }
        }
    }
}

// MARK: - The chat

/**
 * The chat (iOS `TutorChatView`) is built from what the app already has:
 * every line is a [DialogueLine] (the call's own surface), the input is
 * Watch's situation box ([SpeakOrTypeField] with the send button inside its
 * row), and every button is a [SoftChip].
 */
@Composable
fun TutorChatView(state: AppState, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val res = context.resources
    val scope = rememberCoroutineScope()
    var draft by remember { mutableStateOf("") }
    var usedVoice by remember { mutableStateOf(false) }
    var dictationLocale by remember { mutableStateOf(state.nativeLanguage) }
    val tutorName = stringResource(R.string.tutor)
    val youName = stringResource(R.string.you)
    val suggestions = listOf(
        stringResource(R.string.what_should_i_do_now),
        stringResource(R.string.why_do_i_keep_making_the_same_mistake),
        stringResource(R.string.i_only_have_5_minutes),
        stringResource(R.string.am_i_getting_better),
        stringResource(R.string.how_do_i_reach_the_next_level),
    )
    val latest by rememberUpdatedState(state)
    LaunchedEffect(Unit) {
        TutorChat.resetIfNewDay()
        TutorBot.refresh(context, latest.targetLanguage, latest.nativeLanguage, latest.level, visible = { false })
        Analytics.capture("tutor_bot_opened")
    }
    fun send(q: String) {
        val text = q.trim()
        if (text.isEmpty()) return
        draft = ""
        usedVoice = false
        scope.launch {
            TutorChat.ask(context, text, latest.targetLanguage, latest.nativeLanguage, latest.level, latest.persona)
        }
    }
    val list = rememberLazyListState()
    val today = TutorBot.today
    // Two fixed lines lead the thread: the plan, and the offer to ask.
    LaunchedEffect(TutorChat.messages.size) {
        if (TutorChat.messages.isNotEmpty()) list.animateScrollToItem(2 + TutorChat.messages.size - 1)
    }
    LaunchedEffect(TutorChat.thinking) {
        if (TutorChat.thinking) list.animateScrollToItem(2 + TutorChat.messages.size)
    }
    PageSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).imePadding()) {
            SheetHeader(stringResource(R.string.personal_tutor),
                leading = {
                    val close = stringResource(R.string.close)
                    IosGlassButton(onClick = onDismiss, circle = true,
                        modifier = Modifier.semantics { contentDescription = close }) {
                        Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurface)
                    }
                },
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp))
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = list,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item("plan") {
                    DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(TutorCopy.summary(res, today))
                            TutorCopy.why(res, today)?.let { why ->
                                Text(why, style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (today.items.isNotEmpty()) {
                                Box(Modifier.padding(top = 4.dp)) { TutorPlanRows(today) }
                            }
                        }
                    }
                }
                item("ask") {
                    DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                        Text(stringResource(R.string.ask_me_anything_about_your_practice_i_answer_from_your_own_t_674d72))
                    }
                }
                items(TutorChat.messages, key = { it.id }) { m ->
                    if (m.fromLearner) {
                        DialogueLine(speaker = DialogueSpeaker.USER, name = youName) { Text(m.text) }
                    } else {
                        DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName, accessory = {
                            val kind = m.action
                            if (kind != null) {
                                SoftChip(TutorCopy.startTitle(res, kind), selected = true, vector = kind.icon()) {
                                    TutorBot.start(context, kind)
                                }
                            } else if (m.quiz) {
                                SoftChip(stringResource(R.string.quick_quiz), selected = true,
                                    vector = Icons.AutoMirrored.Outlined.HelpOutline) {
                                    TutorBot.start(context, null)
                                }
                            }
                        }) {
                            SelectionContainer { Text(m.text) }
                        }
                    }
                }
                if (TutorChat.thinking) {
                    item("thinking") {
                        DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                Text(stringResource(R.string.thinking),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            // Watch's situation box: suggestion chips above, one field whose
            // row carries the mic, the dictation language and the send button.
            // The messages dissolve under it instead of being cut (iOS
            // `fadingBottomBar`, 2026-10-28): a wash of the page colour drawn
            // 36 dp ABOVE the bar, over the list's last lines.
            val surface = MaterialTheme.colorScheme.surface
            Column(Modifier.fillMaxWidth()
                .drawBehind {
                    val fade = 36.dp.toPx()
                    drawRect(androidx.compose.ui.graphics.Brush.verticalGradient(
                        listOf(surface.copy(alpha = 0f), surface), startY = -fade, endY = 0f),
                        topLeft = androidx.compose.ui.geometry.Offset(0f, -fade),
                        size = androidx.compose.ui.geometry.Size(size.width, fade))
                }
                .background(surface)
                .padding(top = 8.dp).windowInsetsPadding(WindowInsets.navigationBars)) {
                if (draft.isBlank()) {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        suggestions.forEach { q ->
                            SoftChip(q, selected = true) { if (!TutorChat.thinking) send(q) }
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                }
                Box(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp)) {
                    SpeakOrTypeField(
                        text = draft,
                        onText = { draft = it },
                        usedVoice = usedVoice,
                        onUsedVoice = { usedVoice = it },
                        placeholder = stringResource(R.string.ask_me_anything),
                        locale = LanguageCatalog.sttLocale(dictationLocale),
                        plainMic = true,
                        trailingControls = {
                            DictationLanguagePill(dictationLocale) { dictationLocale = it }
                        },
                        // The box's own CTA (iOS `ScenarioComposerSheet.inlineCTA`):
                        // a filled accent circle, shown once there is
                        // something to send.
                        endControls = {
                            if (draft.isNotBlank() && !TutorChat.thinking) {
                                val sendLabel = stringResource(R.string.send)
                                Box(
                                    Modifier.size(40.dp).clip(CircleShape)
                                        .background(MaterialTheme.colorScheme.primary)
                                        .clickable(role = androidx.compose.ui.semantics.Role.Button) { send(draft) }
                                        .semantics { contentDescription = sendLabel },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Filled.ArrowUpward, contentDescription = null,
                                        modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onPrimary)
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}

// MARK: - Words

/** What the note and the chat's first message say (iOS `TutorCopy`).
 *  Computed from the day, never asked of a model, so it is instant and
 *  agrees with My routine. */
object TutorCopy {
    fun greeting(res: Resources, now: Long = System.currentTimeMillis()): String {
        val h = Calendar.getInstance().apply { timeInMillis = now }.get(Calendar.HOUR_OF_DAY)
        return when (h) {
            in 5 until 12 -> res.getString(R.string.good_morning)
            in 12 until 18 -> res.getString(R.string.hi_there)
            else -> res.getString(R.string.good_evening)
        }
    }

    fun summary(res: Resources, t: TutorBot.Today): String {
        if (t.restDay) {
            return if (t.dueCards > 0)
                res.getString(R.string.today_is_a_rest_day_in_your_routine_if_you_feel_like_it_lld_47e805, t.dueCards)
            else res.getString(R.string.today_is_a_rest_day_in_your_routine_nothing_you_have_to_do)
        }
        if (t.items.isEmpty()) return res.getString(R.string.nothing_planned_today)
        if (t.allDone) return res.getString(R.string.everything_for_today_is_done_see_you_tomorrow)
        if (t.suggested) return res.getString(R.string.you_don_t_have_a_routine_yet_so_here_s_what_i_d_do_today)
        val left = t.left.size
        if (left == t.items.size) {
            return res.getString(R.string.today_lld_things_about_lld_minutes, left, t.minutesLeft)
        }
        return res.getString(R.string.lld_done_lld_to_go_about_lld_minutes, t.items.size - left, left, t.minutesLeft)
    }

    /** Why today looks like this — one line, only when there is a reason. */
    fun why(res: Resources, t: TutorBot.Today): String? {
        val label = t.focusLabel
        if (label != null && t.focusTalks >= GrammarFocus.MIN_TALKS) {
            return res.getString(R.string.we_re_working_on_it_came_up_in_lld_of_your_talks, label, t.focusTalks)
        }
        val reviewPlanned = t.items.any { it.kind == StudyPlan.Kind.REVIEW }
        if (t.dueCards > 0 && !reviewPlanned) {
            return res.getString(R.string.lld_cards_from_your_own_talks_are_waiting, t.dueCards)
        }
        if (t.streak >= 2) return res.getString(R.string.lld_days_in_a_row_keep_it_going, t.streak)
        return null
    }

    fun whenText(context: android.content.Context, item: TutorBot.Item): String {
        val res = context.resources
        if (item.done) return res.getString(R.string.done)
        if (item.anytime) return res.getString(R.string.anytime)
        return android.text.format.DateFormat.getTimeFormat(context).format(Date(item.start))
    }

    fun startTitle(res: Resources, kind: StudyPlan.Kind): String = res.getString(when (kind) {
        StudyPlan.Kind.TALK -> R.string.start_a_talk
        StudyPlan.Kind.REVIEW, StudyPlan.Kind.WORDS, StudyPlan.Kind.EXPRESSIONS -> R.string.start_review
        StudyPlan.Kind.SHADOW -> R.string.start_shadowing
        StudyPlan.Kind.SAY_IT_AGAIN -> R.string.say_it_again
        StudyPlan.Kind.LISTEN -> R.string.listen
        StudyPlan.Kind.SPEECH -> R.string.open_speech
        StudyPlan.Kind.TEST -> R.string.take_the_test
    })
}
