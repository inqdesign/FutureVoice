package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.SoundEffects
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.QuickQuizEngine
import com.roro.futurevoice.data.QuickQuizItem
import com.roro.futurevoice.data.QuickQuizStock
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassButton
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The quick quiz's door on the Talk tab (iOS `QuickQuizButton`): the test
 * host's face and nothing else, at the right of "Find a topic" (2026-10-18,
 * founder).
 */
@Composable
fun QuickQuizButton(language: String, native: String, level: CefrLevel) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var showing by remember { mutableStateOf(false) }
    // Only in the foreground: a launch nobody sees would be suspended
    // mid-request (iOS `.task(id: scenePhase == .active)`).
    LaunchedEffect(lifecycle, language, level) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            QuickQuizStock.prewarm(context.applicationContext, language, native, level)
        }
    }
    val label = stringResource(R.string.quiz)
    IosGlassButton(onClick = { showing = true },
        modifier = Modifier.size(52.dp).semantics { contentDescription = label }, circle = true) {
        WeeklyTestCharacter(WeeklyTestHost.Mood.WAITING, 0L, Modifier.size(30.dp), tile = Color.Transparent)
    }
    if (showing) {
        Dialog(
            onDismissRequest = { showing = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            DialogSystemBarsLikeActivity()
            QuickQuizScreen(language, native, level, onClose = { showing = false })
        }
    }
}

private enum class QuizStage { LOADING, EMPTY, ASKING, DONE }

private val QUIZ_GREEN = Color(0xFF34C759)
private val QUIZ_RED = Color(0xFFFF3B30)
private val QUIZ_GRAY = Color(0xFF8E8E93)

/**
 * Ten one-tap questions on what is being studied now ([QuickQuizEngine]),
 * then the score and what was missed (iOS `QuickQuizView`). Nothing is saved.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickQuizScreen(language: String, native: String, level: CefrLevel, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var stage by remember { mutableStateOf(QuizStage.LOADING) }
    val items = remember { mutableStateListOf<QuickQuizItem>() }
    var index by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<String?>(null) }
    val missed = remember { mutableStateListOf<QuickQuizItem>() }
    var mood by remember { mutableStateOf(WeeklyTestHost.Mood.THINKING) }
    var moodSince by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var advance by remember { mutableStateOf<Job?>(null) }

    fun setMood(m: WeeklyTestHost.Mood) { mood = m; moodSince = System.currentTimeMillis() }

    DisposableEffect(Unit) {
        SoundEffects.prepare(context)
        onDispose { advance?.cancel() }
    }
    LaunchedEffect(Unit) {
        val built = QuickQuizEngine.build(context.applicationContext, language, native, level)
        items.clear(); items.addAll(built)
        setMood(WeeklyTestHost.Mood.WAITING)
        stage = if (built.isEmpty()) QuizStage.EMPTY else QuizStage.ASKING
        Analytics.capture("quick_quiz_started", mapOf("items" to built.size))
    }

    fun next() {
        chosen = null
        if (index + 1 < items.size) {
            index += 1
            setMood(WeeklyTestHost.Mood.WAITING)
        } else {
            val ratio = (items.size - missed.size).toDouble() / maxOf(items.size, 1)
            setMood(if (ratio >= 0.8) WeeklyTestHost.Mood.HAPPY else WeeklyTestHost.Mood.WAITING)
            SoundEffects.play(context, SoundEffects.Cue.DONE)
            stage = QuizStage.DONE
            Analytics.capture("quick_quiz_finished", mapOf("items" to items.size, "missed" to missed.size))
        }
    }

    fun pick(option: String, item: QuickQuizItem) {
        if (chosen != null) return
        chosen = option
        val correct = option == item.answer
        scope.launch { QuickQuizEngine.apply(context.applicationContext, item, correct, language) }
        if (correct) {
            HapticEngine.success(context)
            SoundEffects.play(context, SoundEffects.Cue.RIGHT)
            setMood(WeeklyTestHost.Mood.HAPPY)
        } else {
            missed += item
            HapticEngine.error(context)
            SoundEffects.play(context, SoundEffects.Cue.WRONG)
            setMood(WeeklyTestHost.Mood.SAD)
        }
        // An item with a note waits on its Next button, under the note.
        if (item.note != null) return
        advance = scope.launch {
            delay(if (correct) 700 else 1_400)
            next()
        }
    }

    fun retryMissed() {
        val again = missed.map { it.copy(options = it.options.shuffled(), stockId = null,
            id = java.util.UUID.randomUUID().toString()) }
        items.clear(); items.addAll(again)
        missed.clear()
        index = 0
        chosen = null
        setMood(WeeklyTestHost.Mood.WAITING)
        stage = QuizStage.ASKING
    }

    val ground = if (stage == QuizStage.DONE) AppSurfaces.ground else AppSurfaces.card
    Scaffold(
        containerColor = ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = ground, scrolledContainerColor = ground),
                title = { com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.quiz)) },
                navigationIcon = {
                    val close = stringResource(R.string.close)
                    IosGlassButton(onClick = onClose,
                        modifier = Modifier.padding(start = 8.dp).semantics { contentDescription = close },
                        circle = true) {
                        Icon(Icons.Filled.Close, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
                    }
                },
                actions = {
                    if (stage == QuizStage.ASKING) {
                        Text("${index + 1} / ${items.size}",
                            style = PT.subheadline.copy(fontFeatureSettings = "tnum"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(end = 16.dp))
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (stage) {
                QuizStage.LOADING -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    QuizFace(mood, moodSince, AppSurfaces.ground)
                    Spacer(Modifier.height(16.dp))
                    Text(stringResource(R.string.getting_your_quiz_ready),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                QuizStage.EMPTY -> Column(Modifier.fillMaxSize().padding(horizontal = 32.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    QuizFace(mood, moodSince, AppSurfaces.ground)
                    Text(stringResource(R.string.not_much_to_quiz_yet), style = PT.headline)
                    Text(stringResource(R.string.save_a_few_words_or_have_another_talk_and_the_quiz_fills_up),
                        style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center)
                    Button(onClick = onClose, modifier = Modifier.padding(top = 8.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                            contentColor = MaterialTheme.colorScheme.primary),
                        elevation = null) { Text(stringResource(R.string.close)) }
                }
                QuizStage.ASKING -> items.getOrNull(index)?.let { item ->
                    Question(item, index, items.size, chosen, mood, moodSince,
                        onPick = { pick(it, item) }, onNext = { next() })
                }
                QuizStage.DONE -> Result(items.size, missed, mood, moodSince,
                    onRetry = { retryMissed() }, onDone = onClose)
            }
        }
    }
}

@Composable
private fun QuizFace(mood: WeeklyTestHost.Mood, since: Long, tile: Color) {
    WeeklyTestCharacter(mood, since, Modifier.size(56.dp), tile = tile)
}

@Composable
private fun Question(item: QuickQuizItem, index: Int, total: Int, chosen: String?,
                     mood: WeeklyTestHost.Mood, moodSince: Long,
                     onPick: (String) -> Unit, onNext: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        LinearProgressIndicator(
            progress = { index.toFloat() / maxOf(total, 1) },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            drawStopIndicator = {},
        )
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.padding(top = 16.dp)) { QuizFace(mood, moodSince, AppSurfaces.ground) }
            Text(heading(item), style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (item.prompt.isNotEmpty()) {
                Text(item.prompt,
                    style = if (item.kind == QuickQuizItem.Kind.WORD)
                        androidx.compose.ui.text.TextStyle(fontSize = 22.sp, lineHeight = 28.sp,
                            fontWeight = FontWeight.SemiBold)
                    else PT.title3,
                    textAlign = TextAlign.Center)
            }
            Column(Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item.options.forEach { option -> OptionButton(option, item, chosen) { onPick(option) } }
            }
            // A note (why, or what it means) waits to be read.
            if (chosen != null && item.note != null) {
                Text(item.note, style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
                Button(onClick = onNext, modifier = Modifier.heightIn(min = 50.dp),
                    shape = androidx.compose.foundation.shape.CircleShape,
                    contentPadding = PaddingValues(horizontal = 24.dp)) {
                    Text(stringResource(R.string.next), style = PT.headline)
                }
            }
        }
    }
}

@Composable
private fun heading(item: QuickQuizItem): String = when (item.kind) {
    QuickQuizItem.Kind.WORD -> stringResource(R.string.what_s_the_word)
    QuickQuizItem.Kind.EXPRESSION -> stringResource(R.string.fill_in_the_blank)
    QuickQuizItem.Kind.GRAMMAR -> item.heading ?: stringResource(R.string.grammar)
}

/** iOS `.bordered` + `.roundedRectangle(radius: 14)` + `.controlSize(.large)`:
 *  a tinted fill, accent until answered, then green / red / grey. */
@Composable
private fun OptionButton(option: String, item: QuickQuizItem, chosen: String?, onClick: () -> Unit) {
    val tint = when {
        chosen == null -> MaterialTheme.colorScheme.primary
        option == item.answer -> QUIZ_GREEN
        option == chosen -> QUIZ_RED
        else -> QUIZ_GRAY
    }
    Button(
        onClick = { if (chosen == null) onClick() },
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
        shape = RoundedCornerShape(14.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
        colors = ButtonDefaults.buttonColors(containerColor = tint.copy(alpha = 0.15f), contentColor = tint),
        elevation = null,
    ) {
        Text(option, style = PT.body, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun Result(total: Int, missed: List<QuickQuizItem>, mood: WeeklyTestHost.Mood, moodSince: Long,
                   onRetry: () -> Unit, onDone: () -> Unit) {
    val right = total - missed.size
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
    ) {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // On the grouped page the plain tile would vanish.
            QuizFace(mood, moodSince, AppSurfaces.card)
            Text("$right / $total", style = PT.largeTitle.copy(fontFeatureSettings = "tnum"))
            if (missed.isNotEmpty()) {
                Text(stringResource(R.string.the_ones_you_missed_are_back_in_your_review),
                    style = PT.subheadline, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
            }
        }
        if (missed.isNotEmpty()) {
            GroupedSectionHeader(stringResource(R.string.missed))
            GroupedCard {
                missed.forEachIndexed { i, item ->
                    if (i > 0) GroupedRowDivider(inset = false)
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(if (item.kind == QuickQuizItem.Kind.WORD) item.answer else item.solved,
                            style = PT.body.copy(fontWeight = FontWeight.Medium))
                        Text(if (item.kind == QuickQuizItem.Kind.WORD) item.prompt else (item.heading ?: item.answer),
                            style = PT.footnote, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            GroupedSectionSpacer()
            GroupedCard {
                ListButtonRow(onClick = onRetry) {
                    Icon(Icons.Filled.Refresh, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.try_the_missed_ones), style = PT.body,
                        color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        GroupedSectionSpacer()
        GroupedCard {
            ListButtonRow(onClick = onDone) {
                Text(stringResource(R.string.done), style = PT.body, color = MaterialTheme.colorScheme.primary)
            }
        }
        Spacer(Modifier.height(24.dp).windowInsetsPadding(WindowInsets.navigationBars))
    }
}

@Composable
private fun ListButtonRow(onClick: () -> Unit, content: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}
