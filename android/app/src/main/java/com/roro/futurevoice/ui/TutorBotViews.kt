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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.MicExternalOn
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.Add
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
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
import com.roro.futurevoice.talk.TutorAction
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.filled.MoreHoriz
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.QuickQuizStock
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.TutorBot
import com.roro.futurevoice.talk.TutorChat
import com.roro.futurevoice.talk.TutorBalance
import com.roro.futurevoice.talk.TutorPick
import com.roro.futurevoice.talk.TutorReading
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
 * `TutorBotLayer`). While the note is up the page behind it goes soft (the
 * Talk home's own overlay) and a tap outside the note folds it back into the
 * face. [bottom] is where the bottom row's top
 * edge sits over the floating bar.
 */
@Composable
fun TutorBotLayer(state: AppState, onOpenRoutine: () -> Unit) {
    val context = LocalContext.current
    TutorBot.goalPage?.let { goal -> UpcomingGoalPage(goal, state, onDismiss = { TutorBot.goalPage = null }) }
    // The chat shows its own; this one is for a reading opened from the note.
    TutorBot.reading?.let { r -> if (!TutorBot.chatOpen) TutorReadingSheet(r, state) }
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
                enter = scaleIn(tween(300), initialScale = 0.6f, transformOrigin = TransformOrigin(1f, 1f)) +
                    fadeIn(tween(300)),
                exit = scaleOut(tween(350), targetScale = 0.2f, transformOrigin = TransformOrigin(1f, 1f)) +
                    fadeOut(tween(350)),
            ) {
                TutorNoteCard(state, onOpenRoutine,
                    Modifier.padding(start = 12.dp, end = 12.dp, bottom = 80.dp))
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
    val shape = remember { tutorNoteShape() }
    Column(
        modifier
            .widthIn(max = 420.dp)
            .shadow(20.dp, shape, ambientColor = Color.Black.copy(alpha = 0.18f),
                spotColor = Color.Black.copy(alpha = 0.18f))
            .background(AppSurfaces.card, shape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .padding(16.dp)
            .padding(bottom = TUTOR_NOTE_TAIL_HEIGHT),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (TutorBot.introShown) TutorIntro() else TutorPlan(state, onOpenRoutine)
    }
}

private val TUTOR_NOTE_TAIL_HEIGHT = 12.dp

/**
 * The note's card with a tail at the bottom right pointing down at the
 * tutor's face ([TutorBotButton]), so the note reads as the face talking
 * (iOS `TutorNoteShape`, 2ff90516). ONE outline: the tail is unioned into
 * the rounded card (iOS 7a0f3e0f) — two overlapping pieces met along a
 * visible seam. [tailInset] is from the card's trailing edge to the tail's
 * centre: the card sits 12 dp in from the screen edge and the face's centre
 * 47 dp (the row's 21 dp + half of 52; iOS's 38 is its own 12 → ~50 pt).
 */
private fun tutorNoteShape(
    cornerRadius: androidx.compose.ui.unit.Dp = 24.dp,
    tailInset: androidx.compose.ui.unit.Dp = 35.dp,
    tailHalfWidth: androidx.compose.ui.unit.Dp = 11.dp,
) = object : androidx.compose.ui.graphics.Shape {
    override fun createOutline(
        size: androidx.compose.ui.geometry.Size,
        layoutDirection: androidx.compose.ui.unit.LayoutDirection,
        density: androidx.compose.ui.unit.Density,
    ): androidx.compose.ui.graphics.Outline = with(density) {
        val bodyBottom = size.height - TUTOR_NOTE_TAIL_HEIGHT.toPx()
        val r = cornerRadius.toPx()
        val card = androidx.compose.ui.graphics.Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(
                0f, 0f, size.width, bodyBottom, androidx.compose.ui.geometry.CornerRadius(r, r)))
        }
        val x = size.width - tailInset.toPx()
        val half = tailHalfWidth.toPx()
        val tail = androidx.compose.ui.graphics.Path().apply {
            moveTo(x - half, bodyBottom - 2.dp.toPx())
            lineTo(x, size.height)
            lineTo(x + half, bodyBottom - 2.dp.toPx())
            close()
        }
        androidx.compose.ui.graphics.Outline.Generic(
            androidx.compose.ui.graphics.Path.combine(
                androidx.compose.ui.graphics.PathOperation.Union, card, tail))
    }
}

/**
 * The Talk page behind the tutor's note: blurred (API 31+), the blur half of
 * iOS's `ultraThinMaterial` overlay (2ff90516); the Talk home lays the wash
 * over it.
 */
@Composable
fun Modifier.softenedPage(on: Boolean): Modifier {
    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return this
    val t by androidx.compose.animation.core.animateFloatAsState(
        if (on) 1f else 0f, tween(300), label = "softenedPage")
    return if (t > 0f) this.blur((16 * t).dp) else this
}

/**
 * The two other buttons of the Talk home's bottom row while the tutor's note
 * is up: out of focus and out of reach, so only the face stays sharp (iOS
 * `SoftenedBehindNote`). Their taps already land on the note layer's catcher.
 */
@Composable
fun Modifier.softenedBehindNote(on: Boolean): Modifier {
    val t by androidx.compose.animation.core.animateFloatAsState(
        if (on) 1f else 0f, tween(300), label = "softened")
    return this
        .then(if (t > 0f && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S)
            Modifier.blur((6 * t).dp, androidx.compose.ui.draw.BlurredEdgeTreatment.Unbounded)
            else Modifier)
        .graphicsLayer { alpha = 1f - 0.5f * t }
}

/** The first meeting: who this is and what it does. */
@Composable
private fun TutorIntro() {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        // No face in the note: it sits over the tutor's own face (iOS 7a0f3e0f).
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.your_own_nawana_tutor), style = MaterialTheme.typography.titleMedium,
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
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(TutorCopy.greeting(res), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(TutorCopy.opening(res), style = MaterialTheme.typography.bodyMedium)
            TutorCopy.why(res, t)?.let { why ->
                Text(why, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    // The nearest thing they're preparing for, with its countdown.
    com.roro.futurevoice.data.UpcomingGoalStore.active(context, state.targetLanguage).firstOrNull()?.let { goal ->
        Row(Modifier.fillMaxWidth().clickable {
            TutorBot.closeNote(context)
            TutorBot.goalPage = goal
        }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            UpcomingGoalRow(goal, Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
        }
    }
    if (TutorBot.picks.isNotEmpty() || t.items.isNotEmpty()) TutorTodayRows(state)
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
    var addingGoal by remember { mutableStateOf(false) }
    var goalPage by remember { mutableStateOf<com.roro.futurevoice.data.UpcomingGoal?>(null) }
    // A goal added or changed reloads the tutor's picks at once.
    LaunchedEffect(com.roro.futurevoice.data.UpcomingGoalStore.goals) {
        TutorBot.loadPicks(context, latest.targetLanguage, latest.persona)
    }
    LaunchedEffect(Unit) {
        TutorChat.load(context, latest.targetLanguage)
        TutorBot.refresh(context, latest.targetLanguage, latest.nativeLanguage, latest.level, latest.persona,
            visible = { false })
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
    // A day's first message carries its date: the thread is kept, so
    // yesterday's answer must not read as today's.
    val dayFormat = remember(LocalConfiguration.current) {
        java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(
            java.util.Locale.getDefault(), "EEEMMMd"), java.util.Locale.getDefault())
    }
    val rows = TutorChat.messages.flatMapIndexed { i, m ->
        val newDay = i == 0 || com.roro.futurevoice.data.StudyPlan.dayKey(TutorChat.messages[i - 1].at) !=
            com.roro.futurevoice.data.StudyPlan.dayKey(m.at)
        listOfNotNull(if (newDay) ChatRow.Day(m.id, dayFormat.format(Date(m.at))) else null, ChatRow.Msg(m))
    }
    // Three fixed lines lead the thread: the goals, the plan, and the offer to ask.
    LaunchedEffect(TutorChat.messages.size) {
        if (rows.isNotEmpty()) list.animateScrollToItem(3 + rows.size - 1)
    }
    LaunchedEffect(TutorChat.thinking) {
        if (TutorChat.thinking) list.animateScrollToItem(3 + rows.size)
    }
    var menu by remember { mutableStateOf(false) }
    if (TutorBot.callSettingsOpen) StandaloneCallSettings(state, onDismiss = { TutorBot.callSettingsOpen = false })
    if (TutorBot.purposesOpen) PurposesEditor(state.targetLanguage, onDismiss = { TutorBot.purposesOpen = false })
    TutorBot.reading?.let { r -> if (TutorBot.chatOpen) TutorReadingSheet(r, state) }
    if (addingGoal) UpcomingGoalEditor(goal = null, language = state.targetLanguage, onDismiss = { addingGoal = false })
    goalPage?.let { g -> UpcomingGoalPage(g, state, onDismiss = { goalPage = null }) }
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
                trailing = if (TutorChat.messages.isEmpty()) null else ({
                    val more = stringResource(R.string.more)
                    Box {
                        IosGlassButton(onClick = { menu = true }, circle = true,
                            modifier = Modifier.semantics { contentDescription = more }) {
                            Icon(Icons.Filled.MoreHoriz, contentDescription = null, modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurface)
                        }
                        IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            IosMenuItem(stringResource(R.string.clear_this_chat), onClick = {
                                menu = false; TutorChat.clear(context)
                            }, icon = Icons.Outlined.Delete, destructive = true, reserveCheck = false)
                        }
                    }
                }),
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp))
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = list,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item("goals") { TutorGoalLine(state, tutorName, onAdd = { addingGoal = true },
                    onOpen = { goalPage = it }) }
                item("plan") {
                    DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(TutorCopy.opening(res))
                            TutorCopy.why(res, today)?.let { why ->
                                Text(why, style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (TutorBot.picks.isNotEmpty() || today.items.isNotEmpty()) {
                                Box(Modifier.padding(top = 4.dp)) { TutorTodayRows(state) }
                            }
                        }
                    }
                }
                item("ask") {
                    DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                        Text(stringResource(R.string.ask_me_anything_about_your_practice_i_answer_from_your_own_t_674d72))
                    }
                }
                items(rows, key = { it.key }) { row ->
                    when (row) {
                        is ChatRow.Day -> Text(row.label, style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier.fillMaxWidth())
                        is ChatRow.Msg -> {
                            val m = row.message
                            if (m.fromLearner) {
                                DialogueLine(speaker = DialogueSpeaker.USER, name = youName) { Text(m.text) }
                            } else {
                                DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName, accessory = {
                                    if (m.actions.isNotEmpty()) {
                                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            m.actions.forEachIndexed { i, action ->
                                                SoftChip(action.title(res), selected = i == 0, vector = action.icon()) {
                                                    TutorBot.perform(context, action)
                                                }
                                            }
                                        }
                                    }
                                }) {
                                    SelectionContainer { Text(m.text) }
                                }
                            }
                        }
                    }
                }
                if (TutorChat.thinking) {
                    item("thinking") {
                        DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
                            Row(verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                Text(TutorChat.status.ifEmpty { stringResource(R.string.thinking) },
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

    /** The note's and the chat's first line: today's plan in numbers (iOS
     *  19ba732d: the first pick's announcement read wrong as the title — the
     *  pick's own row already says it). With nothing planned but picks to
     *  offer, says so. */
    fun opening(res: Resources): String {
        val t = TutorBot.today
        if (t.items.isEmpty() && !t.restDay && TutorBot.picks.isNotEmpty()) {
            return res.getString(R.string.here_s_what_i_d_pick_for_today)
        }
        return summary(res, t)
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
            // The count is the ROUTINE's: the list under it also holds the
            // tutor's picks, and "2 things" over six rows read as wrong.
            return res.getString(R.string.your_routine_today_lld_things_about_lld_minutes, left, t.minutesLeft)
        }
        return res.getString(R.string.routine_lld_done_lld_to_go_about_lld_minutes, t.items.size - left, left, t.minutesLeft)
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

// MARK: - Picks

/** iOS `TutorPick.symbol`. */
fun pickIcon(kind: TutorPick.Kind): androidx.compose.ui.graphics.vector.ImageVector = when (kind) {
    TutorPick.Kind.RANK_DROP -> Icons.Filled.EmojiEvents
    TutorPick.Kind.NEW_EPISODE, TutorPick.Kind.LISTEN -> Icons.Filled.Headphones
    TutorPick.Kind.FIRST_SPEECH, TutorPick.Kind.GOAL_SPEECH -> Icons.Filled.MicExternalOn
    TutorPick.Kind.READ_SCRIPT, TutorPick.Kind.GOAL_READING -> Icons.AutoMirrored.Filled.MenuBook
    TutorPick.Kind.READ_NEWS -> Icons.Filled.Newspaper
    TutorPick.Kind.GOAL_DRILL -> Icons.Filled.School
}

/** iOS `TutorPickRows.color`: red, cyan, purple, brown — the system colours. */
fun pickColor(kind: TutorPick.Kind): Color = when (kind) {
    TutorPick.Kind.RANK_DROP -> Color(0xFFFF3B30)
    TutorPick.Kind.NEW_EPISODE, TutorPick.Kind.LISTEN -> Color(0xFF32ADE6)
    TutorPick.Kind.FIRST_SPEECH -> Color(0xFFAF52DE)
    TutorPick.Kind.READ_SCRIPT, TutorPick.Kind.READ_NEWS -> Color(0xFFA2845E)
    TutorPick.Kind.GOAL_READING, TutorPick.Kind.GOAL_SPEECH, TutorPick.Kind.GOAL_DRILL -> Color(0xFFAF52DE)
}

/** A reading opened from a pick (iOS `TutorReadingSheet`): the episode's
 *  script at once, or the news article, written the first time anyone opens it. */
@Composable
fun TutorReadingSheet(reading: TutorReading, state: AppState, onDismiss: () -> Unit = { TutorBot.reading = null }) {
    val context = LocalContext.current
    var script by remember(reading.id) { mutableStateOf<com.roro.futurevoice.data.SpeechScript?>(null) }
    var failed by remember(reading.id) { mutableStateOf(false) }
    var attempt by remember(reading.id) { mutableStateOf(0) }
    val close = onDismiss
    LaunchedEffect(reading.id, attempt) {
        if (script != null || reading.script != null) return@LaunchedEffect
        val goal = reading.goal
        val part = reading.part
        if (goal != null && part != null) {
            try {
                val prep = com.roro.futurevoice.talk.GoalPrep.load(context, goal, state.nativeLanguage, state.level,
                    state.persona)
                script = prep.script(part)
                TutorBot.loadPicks(context, state.targetLanguage, state.persona, force = true)
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) {
                failed = true
            }
            return@LaunchedEffect
        }
        val story = reading.story ?: return@LaunchedEffect
        try {
            script = com.roro.futurevoice.talk.NewsArticle.load(context, story, state.targetLanguage, state.level)
            com.roro.futurevoice.data.ActivityEventLog.record(context,
                com.roro.futurevoice.data.ActivityEventLog.Kind.READ)
            Analytics.capture("news_article_opened", mapOf("category" to (story.category ?: "")))
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) {
            failed = true
        }
    }
    val shown = script ?: reading.script
    if (shown != null) {
        com.roro.futurevoice.ui.speech.SpeechScriptSheet(shown, state.nativeLanguage, onEdited = {},
            onDismiss = close, initialStudy = reading.study, shipped = true,
            studyHere = reading.script == null || reading.goal != null,
            canPractice = reading.part == com.roro.futurevoice.talk.GoalPrep.Part.SPEECH)
        return
    }
    com.roro.futurevoice.ui.speech.SpeechSheet(onDismiss = close) {
        val closeLabel = stringResource(R.string.close)
        SheetHeader("", leading = {
            IosGlassButton(onClick = close, circle = true,
                modifier = Modifier.semantics { contentDescription = closeLabel }) {
                Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurface)
            }
        })
        Column(Modifier.fillMaxWidth().padding(top = 160.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (failed) {
                Icon(Icons.Filled.Newspaper, contentDescription = null, modifier = Modifier.size(44.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.couldn_t_open_the_article), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.check_your_connection_and_try_again),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                SoftChip(stringResource(R.string.try_again), selected = true) { failed = false; attempt += 1 }
            } else {
                CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 3.dp)
                Text(stringResource(if (reading.goal == null) R.string.writing_the_article_for_your_level
                    else R.string.writing_today_s_preparation_for_your_goal),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** What the learner is preparing for, first in the chat (iOS `goalLine`,
 *  ec0de1e5): the goals ahead (tap one for its page), or the offer to write
 *  one, right here. */
@Composable
private fun TutorGoalLine(state: AppState, tutorName: String, onAdd: () -> Unit,
                          onOpen: (com.roro.futurevoice.data.UpcomingGoal) -> Unit) {
    val context = LocalContext.current
    val ahead = remember(com.roro.futurevoice.data.UpcomingGoalStore.goals, state.targetLanguage) {
        com.roro.futurevoice.data.UpcomingGoalStore.active(context, state.targetLanguage)
    }
    DialogueLine(speaker = DialogueSpeaker.OTHER, name = tutorName) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (ahead.isEmpty()) {
                Text(stringResource(R.string.preparing_for_something_an_interview_an_exam_a_presentation_47928c))
                SoftChip(stringResource(R.string.add_a_goal), selected = true, vector = Icons.Filled.Add, onClick = onAdd)
            } else {
                ahead.forEach { goal ->
                    Row(Modifier.fillMaxWidth().clickable { onOpen(goal) }, verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        UpcomingGoalRow(goal, Modifier.weight(1f))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
                    }
                }
                SoftChip(stringResource(R.string.add_a_goal), vector = Icons.Filled.Add, onClick = onAdd)
            }
        }
    }
}

/** One line of the chat's thread: a day's date, or a message. */
private sealed interface ChatRow {
    val key: String
    data class Day(val messageId: String, val label: String) : ChatRow { override val key get() = "day-$messageId" }
    data class Msg(val message: TutorChat.Message) : ChatRow { override val key get() = message.id }
}

/** iOS `TutorAction.symbol`. */
fun TutorAction.icon(): androidx.compose.ui.graphics.vector.ImageVector = when (type) {
    TutorAction.Kind.TALK -> Icons.Filled.Phone
    TutorAction.Kind.LESSON -> Icons.Filled.School
    TutorAction.Kind.BOOK -> Icons.Filled.Book
    TutorAction.Kind.GOAL -> Icons.Filled.Flag
    TutorAction.Kind.GOAL_READING -> Icons.AutoMirrored.Filled.MenuBook
    TutorAction.Kind.GOAL_ANSWER -> Icons.Filled.MicExternalOn
    TutorAction.Kind.WORD, TutorAction.Kind.EXPRESSION -> Icons.Filled.Translate
    TutorAction.Kind.REVIEW -> StudyPlan.Kind.REVIEW.icon()
    TutorAction.Kind.SHADOW -> StudyPlan.Kind.SHADOW.icon()
    TutorAction.Kind.SAY_IT_AGAIN -> StudyPlan.Kind.SAY_IT_AGAIN.icon()
    TutorAction.Kind.LISTEN -> StudyPlan.Kind.LISTEN.icon()
    TutorAction.Kind.SPEECH -> StudyPlan.Kind.SPEECH.icon()
    TutorAction.Kind.TEST -> StudyPlan.Kind.TEST.icon()
    TutorAction.Kind.QUIZ -> Icons.AutoMirrored.Outlined.HelpOutline
    TutorAction.Kind.ROUTINE -> Icons.Filled.CalendarMonth
    TutorAction.Kind.SETTINGS -> Icons.Filled.Tune
    TutorAction.Kind.PURPOSES -> Icons.Filled.TrackChanges
}

/** Call settings opened over the chat by a tutor button (iOS
 *  `CallSettingsSheet()` with no call behind it): every switch writes its
 *  setting, read by the next call. */
@Composable
private fun StandaloneCallSettings(state: AppState, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var showsTranscript by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_TRANSCRIPT)) }
    var showsCorrections by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_CORRECTIONS)) }
    var showsGoalChips by remember { mutableStateOf(CallSettings.flag(context, CallSettings.SHOWS_GOAL_CHIPS)) }
    var coachMode by remember {
        mutableStateOf(com.roro.futurevoice.talk.CoachMode.resolve(
            com.roro.futurevoice.talk.CoachMode.choice(context), state.level.code))
    }
    var tutorMode by remember { mutableStateOf(com.roro.futurevoice.talk.TutorMode.isOn(context)) }
    var sendToAnswer by remember {
        mutableStateOf(com.roro.futurevoice.talk.SendToAnswer.resolve(
            com.roro.futurevoice.talk.SendToAnswer.choice(context), state.level.code))
    }
    CallSettingsSheet(
        showsTranscript = showsTranscript, showsCorrections = showsCorrections, showsGoalChips = showsGoalChips,
        coachMode = coachMode,
        onCoachMode = { com.roro.futurevoice.talk.CoachMode.setChoice(context, it); coachMode = it },
        tutorMode = tutorMode,
        onTutorMode = { com.roro.futurevoice.talk.TutorMode.set(context, it); tutorMode = it },
        sendToAnswer = sendToAnswer,
        onSendToAnswer = { com.roro.futurevoice.talk.SendToAnswer.setChoice(context, it); sendToAnswer = it },
        onFlag = { key, value ->
            CallSettings.set(context, key, value)
            when (key) {
                CallSettings.SHOWS_TRANSCRIPT -> showsTranscript = value
                CallSettings.SHOWS_CORRECTIONS -> showsCorrections = value
                CallSettings.SHOWS_GOAL_CHIPS -> showsGoalChips = value
            }
        },
        onSpeedChange = {},
        onDismiss = onDismiss,
    )
}

// MARK: - Today, chosen

/**
 * The note's and the chat's list (iOS `TutorTodayRows`, 57ba9c6f): now,
 * next, and the rest folded under "N more today". The order is
 * [com.roro.futurevoice.talk.TutorToday.ranked], fixed in code.
 */
@Composable
fun TutorTodayRows(state: AppState) {
    val context = LocalContext.current
    val res = context.resources
    var expanded by remember { mutableStateOf(false) }
    val entries = com.roro.futurevoice.talk.TutorToday.ranked(TutorBot.today, TutorBot.picks,
        opened = com.roro.futurevoice.talk.TutorToday.opened(context))
    val open = entries.filter { !it.isDone }
    val now = open.firstOrNull()
    val next = open.drop(1).firstOrNull()
    val rest = entries.filter { it.id != now?.id && it.id != next?.id }
    @Composable fun divider() = HorizontalDivider(Modifier.padding(start = 40.dp),
        color = MaterialTheme.colorScheme.outlineVariant)
    @Composable fun caption(text: String) = Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 40.dp, top = 6.dp))
    Column {
        if (now != null) {
            caption(stringResource(R.string.now))
            TodayRow(now, prominent = true, state)
        }
        if (next != null) {
            divider()
            caption(stringResource(R.string.next))
            TodayRow(next, prominent = false, state)
        }
        if (rest.isNotEmpty()) {
            divider()
            Row(Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(start = 40.dp)
                .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (expanded) stringResource(R.string.show_less)
                    else stringResource(R.string.lld_more_today, rest.size),
                    style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary)
                Icon(if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
            }
            if (expanded) {
                if (TutorBot.picks.isNotEmpty()) {
                    val b = TutorBot.balance
                    Text(res.getString(R.string.this_week_speaking_lld_d_listening_lld_d_reading_lld_d,
                        b.speaking, b.listening, b.reading),
                        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 40.dp, bottom = 4.dp))
                }
                rest.forEachIndexed { i, e ->
                    if (i > 0) divider()
                    TodayRow(e, prominent = false, state)
                }
            }
        }
    }
}

@Composable
private fun TodayRow(e: com.roro.futurevoice.talk.TutorToday.Entry, prominent: Boolean, state: AppState) {
    val context = LocalContext.current
    val res = context.resources
    when (e) {
        is com.roro.futurevoice.talk.TutorToday.Entry.Routine -> {
            val item = e.item
            TodayLine(item.kind.icon(), item.kind.color(), tag = null, title = item.title,
                detail = TutorCopy.whenText(context, item), done = item.done, progress = item.progress,
                prominent = prominent, hint = null) { TutorBot.start(context, item.kind) }
        }
        is com.roro.futurevoice.talk.TutorToday.Entry.Pick -> {
            val pick = e.pick
            TodayLine(pickIcon(pick.kind), pickColor(pick.kind), tag = pick.tag(res), title = pick.title,
                detail = pick.why, done = false, progress = 0.0, prominent = prominent,
                hint = pick.buttonTitle(res)) { TutorBot.start(context, pick, state.nativeLanguage) }
        }
    }
}

@Composable
private fun TodayLine(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, tag: String?,
                      title: String, detail: String, done: Boolean, progress: Double, prominent: Boolean,
                      hint: String?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick)
        .then(if (hint != null) Modifier.semantics { contentDescription = "$title. $hint" } else Modifier)
        .padding(vertical = if (prominent) 10.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(if (prominent) 20.dp else 16.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (tag != null) Text(tag, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                color = color)
            Text(title, style = if (prominent) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.bodyMedium,
                fontWeight = if (prominent) FontWeight.SemiBold else null,
                textDecoration = if (done) TextDecoration.LineThrough else null,
                color = if (done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
            if (detail.isNotEmpty()) {
                Text(detail, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        when {
            done -> Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color(0xFF34C759),
                modifier = Modifier.size(22.dp))
            progress > 0 -> CircularProgressIndicator(progress = { progress.toFloat() }, modifier = Modifier.size(20.dp),
                strokeWidth = 3.dp, trackColor = MaterialTheme.colorScheme.outlineVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = if (prominent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
            modifier = Modifier.size(18.dp))
    }
}
