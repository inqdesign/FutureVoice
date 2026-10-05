package com.roro.futurevoice.ui.speech

import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.RoundedCorner
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The take screen — iOS `SpeechPrompterView`: the script rolls up on top like
 * a teleprompter, the camera (or a quiet mic panel) fills the bottom half,
 * one red button. No header row: every point above the camera card is
 * prompter, so the line being read sits right under the lens (iOS
 * `e66c11ea`). When the take is scored, the same screen turns into its result.
 */
@Composable
internal fun SpeechPrompterScreen(
    script: SpeechScript,
    native: String,
    level: CefrLevel,
    onClose: () -> Unit,
    /** Captures only: a take caught mid-read, without a mic. */
    previewCursor: Int? = null,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val session = remember {
        SpeechTakeSession(context.applicationContext, script, native, level).also { s ->
            previewCursor?.let { s.preview(it) }
        }
    }
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false; session.tearDown() }
    }
    val phase by session.phase.collectAsStateWithLifecycle()
    val prefs = remember { context.getSharedPreferences("futurevoice", 0) }
    var textSize by remember { mutableFloatStateOf(prefs.getFloat("speech.textSize", 28f)) }

    fun close() { session.tearDown(); onClose() }

    val done = phase as? SpeechTakeSession.Phase.Done
    if (done != null) {
        BackHandler { close() }
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
            SpeechResultScreen(takeId = done.take.id, live = done.take, onBack = { close() },
                onAgain = { session.reset() })
        }
        return
    }

    val recording = phase == SpeechTakeSession.Phase.Recording
    BackHandler { if (recording) session.cancelTake() else close() }
    SpeechTakeLayout(session, phase, textSize, onTextSize = {
        textSize = it; prefs.edit().putFloat("speech.textSize", it).apply()
    }, onClose = { close() }, native = native)
}

@Composable
private fun SpeechTakeLayout(
    session: SpeechTakeSession,
    phase: SpeechTakeSession.Phase,
    textSize: Float,
    onTextSize: (Float) -> Unit,
    onClose: () -> Unit,
    native: String,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val density = LocalDensity.current
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val track by session.track.collectAsStateWithLifecycle()
    val script by session.script.collectAsStateWithLifecycle()
    val cursor by session.cursor.collectAsStateWithLifecycle()
    val elapsed by session.elapsed.collectAsStateWithLifecycle()
    val cameraOn by session.cameraOn.collectAsStateWithLifecycle()
    val follow by session.followVoice.collectAsStateWithLifecycle()
    val speed by session.speed.collectAsStateWithLifecycle()
    val cameraRunning by session.camera.running.collectAsStateWithLifecycle()
    val takes by SpeechStore.shared(context).takes.collectAsStateWithLifecycle()
    val recording = phase == SpeechTakeSession.Phase.Recording
    val capturing = com.roro.futurevoice.BuildConfig.BUILD_TYPE == "capture"
    var holding by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }
    var showScript by remember { mutableStateOf(false) }
    var showTakes by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
    var cameraDenied by remember { mutableStateOf(false) }
    var micDenied by remember { mutableStateOf(false) }
    var prompterWidthPx by remember { mutableFloatStateOf(0f) }
    val ground = AppSurfaces.ground
    val ink = MaterialTheme.colorScheme.onSurface

    // The camera: asked for only when it is on.
    fun hasCamera() = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        cameraDenied = !ok
        if (ok && session.cameraOn.value) session.camera.start(owner)
    }
    LaunchedEffect(cameraOn) {
        if (capturing) return@LaunchedEffect   // a capture run shoots the screen, not a camera prompt
        if (!cameraOn) { session.camera.stop(); return@LaunchedEffect }
        if (hasCamera()) { cameraDenied = false; session.camera.start(owner) }
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }
    val cameraShowing = cameraOn && cameraRunning

    fun begin() {
        // The video's script, drawn from the same layout the screen draws.
        if (cameraShowing && prompterWidthPx > 0) {
            val w = prompterWidthPx
            val h = Math.round(w * 16 / 9f).toFloat()
            val half = h / 2
            val dp = density.density
            val layout = SpeechVideoComposer.Layout(
                canvasW = w, canvasH = h,
                prompter = android.graphics.RectF(0f, 0f, w, half - 6 * dp),
                card = android.graphics.RectF(12 * dp, half + 6 * dp, w - 12 * dp, h - 12 * dp),
                cardRadius = 24 * dp, background = ground.toArgb())
            val column = PrompterColumn(track, script.language, w, with(density) { textSize.sp.toPx() },
                24 * dp, ink.toArgb())
            session.composer.prepare(layout, column)
        } else session.composer.prepare(
            SpeechVideoComposer.Layout(0f, 0f, android.graphics.RectF(), android.graphics.RectF(), 0f, 0), null)
        scope.launch { session.start() }
    }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) begin() else micDenied = true
    }
    fun record() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED) begin()
        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
    }
    // Countdown and go: a tick per number, as iOS's haptics.
    LaunchedEffect(phase) {
        if (phase is SpeechTakeSession.Phase.Countdown || phase == SpeechTakeSession.Phase.Recording) {
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }

    fun flash(text: String) {
        toast = text
        scope.launch {
            delay(1300)
            if (toast == text) toast = null
        }
    }

    Box(
        Modifier.fillMaxSize().background(ground)
            // Steady speed: press and hold ANYWHERE to stop the text, let go
            // to carry on (iOS `8b788fb8`). Following already stops when the
            // reader does.
            .pointerInput(recording, follow) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    if (recording && !follow) {
                        holding = true; session.holding = true
                        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                    }
                    do {
                        val event = awaitPointerEvent()
                    } while (event.changes.any { it.pressed })
                    if (holding) { holding = false; session.holding = false }
                }
            },
    ) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Box(Modifier.weight(1f).fillMaxWidth()
                .onGloballyPositioned { prompterWidthPx = it.size.width.toFloat() }) {
                Teleprompter(session, track, cursor, script.language, textSize, recording, follow, speed, holding)
                if (holding) {
                    Row(Modifier.align(Alignment.TopCenter).padding(top = 4.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Pause, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(4.dp))
                        Text(stringResource(R.string.paused), color = Color.White,
                            style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            // The camera card: runs to the bottom of the glass (iOS
            // `440ad90e`), its bottom corners concentric with the display's.
            val inset = 8.dp
            val bottomRadius = displayCornerRadius() - inset
            val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp,
                bottomStart = maxOf(24.dp, bottomRadius), bottomEnd = maxOf(24.dp, bottomRadius))
            Box(Modifier.weight(1f).fillMaxWidth().padding(start = inset, end = inset, bottom = inset)) {
                Box(Modifier.fillMaxSize().clip(shape)) {
                    if (cameraShowing) {
                        AndroidView(factory = { session.camera.previewView }, modifier = Modifier.fillMaxSize())
                    } else if (capturing && com.roro.futurevoice.capture.flags.SpeechCaptureFlags.fakeCamera) {
                        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(
                            Color(0xFFBFBFBF), Color(0xFF8C6B59), Color(0xFF333333)))))
                    } else {
                        MicPanel(session, recording, denied = cameraOn && cameraDenied)
                    }
                }
                val onCamera = cameraShowing || (capturing && com.roro.futurevoice.capture.flags.SpeechCaptureFlags.fakeCamera)
                // The top row: close · whole script · takes · settings. Out of
                // sight while recording, the space kept.
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp)
                    .align(Alignment.TopCenter),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.hiddenWhile(recording)) {
                        ChromeButton(Icons.Filled.Close, stringResource(R.string.close), onCamera, size = 36.dp,
                            onClick = onClose)
                    }
                    Spacer(Modifier.weight(1f))
                    Row(Modifier.hiddenWhile(recording), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ChromeButton(Icons.AutoMirrored.Outlined.Article, stringResource(R.string.whole_script),
                            onCamera, size = 36.dp) { showScript = true }
                        Box {
                            ChromeButton(Icons.Filled.History, stringResource(R.string.takes), onCamera,
                                size = 36.dp) { showTakes = true }
                            val count = takes.count { it.scriptId == script.id }
                            if (count > 0) {
                                Text("$count", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp)
                                        .background(MaterialTheme.colorScheme.primary, CircleShape)
                                        .padding(horizontal = 5.dp, vertical = 1.dp))
                            }
                        }
                        Box {
                            ChromeButton(Icons.Filled.TextFields, stringResource(R.string.prompter_settings),
                                onCamera, size = 36.dp) { settings = true }
                            PrompterSettingsMenu(settings, { settings = false }, follow, speed, textSize,
                                onFollow = { session.setFollowVoice(it) }, onSpeed = { session.setSpeed(it) },
                                onTextSize = onTextSize)
                        }
                    }
                }
                if (recording) {
                    Row(Modifier.align(Alignment.TopCenter).padding(top = 14.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.9f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.FiberManualRecord, null, tint = Color(0xFFFF3B30), modifier = Modifier.size(14.dp))
                        Spacer(Modifier.size(6.dp))
                        Text(clockLabel(elapsed.toDouble()), color = Color(0xFFFF3B30),
                            style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                            fontFamily = FontFamily.Monospace)
                    }
                }
                // The count-in sits on the camera card, where the reader is
                // looking to get ready (iOS `01afc3f0`).
                (phase as? SpeechTakeSession.Phase.Countdown)?.let { c ->
                    Text("${c.n}", fontSize = 96.sp, fontWeight = FontWeight.Bold,
                        color = if (onCamera) Color.White else MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.align(Alignment.Center))
                }
                Column(Modifier.align(Alignment.BottomCenter)
                    .padding(bottom = maxOf(20.dp, navBarInset())),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    AnimatedVisibility(toast != null, enter = fadeIn(), exit = fadeOut()) {
                        Text(toast.orEmpty(), color = Color.White, style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 14.dp)
                                .background(Color.Black.copy(alpha = 0.55f), CircleShape)
                                .padding(horizontal = 14.dp, vertical = 8.dp))
                    }
                    Controls(
                        recording = recording, onCamera = onCamera, cameraOn = cameraOn, follow = follow,
                        onCameraToggle = { session.setCameraOn(!cameraOn) },
                        onCancel = { session.cancelTake() },
                        onRecord = { if (recording) scope.launch { session.stop() } else record() },
                        onRestart = { session.restartTake() },
                        onFollowToggle = {
                            session.setFollowVoice(!follow)
                            flash(context.getString(if (!follow) R.string.follows_your_voice else R.string.steady_speed))
                        },
                    )
                }
            }
        }

        // Analyzing / failed, over everything.
        when (phase) {
            SpeechTakeSession.Phase.Analyzing -> OverlayCard {
                CircularProgressIndicator()
                Text(stringResource(R.string.listening_to_your_take), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            is SpeechTakeSession.Phase.Failed -> OverlayCard {
                Text(phase.message, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                com.roro.futurevoice.ui.brand.IosButton(onClick = { session.reset() }) {
                    Text(stringResource(R.string.try_again))
                }
            }
            else -> if (micDenied) OverlayCard {
                Text(stringResource(R.string.microphone_and_speech_recognition_are_needed_to_record_turn_a72cd7),
                    style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                com.roro.futurevoice.ui.brand.IosButton(onClick = { micDenied = false }) {
                    Text(stringResource(R.string.ok))
                }
            }
        }
    }

    if (showScript) {
        SpeechScriptSheet(script, native, onEdited = { session.replaceScript(it) }, onDismiss = { showScript = false })
    }
    if (showTakes) SpeechTakesSheet(script.id, onDismiss = { showTakes = false })
}

/**
 * The rolling script — iOS `SpeechTeleprompter` + `PrompterScroller`. A
 * TELEPROMPTER: the text flows up at a steady speed every frame, and the
 * reader's voice only changes that SPEED — never jumps the text to where
 * they are (iOS `14928855` `8c6b8ea4`).
 */
@Composable
private fun Teleprompter(
    session: SpeechTakeSession,
    track: com.roro.futurevoice.talk.SpeechPrompterTrack,
    cursor: Int,
    language: String,
    textSize: Float,
    recording: Boolean,
    follow: Boolean,
    speed: Float,
    held: Boolean,
) {
    val density = LocalDensity.current
    val ink = MaterialTheme.colorScheme.onSurface.toArgb()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val widthPx = constraints.maxWidth.toFloat()
        val textPx = with(density) { textSize.sp.toPx() }
        val side = with(density) { 24.dp.toPx() }
        val column = remember(track, widthPx, textPx, ink) {
            PrompterColumn(track, language, widthPx, textPx, side, ink)
        }
        // Where the line being read sits: it enters as the SECOND row and
        // rises to the top row as the reader crosses it (iOS `574a4dda`).
        val readingLine = with(density) { 6.dp.toPx() } + textPx * 1.55f
        val motion = remember(column) { com.roro.futurevoice.talk.PrompterMotion() }
        var position by remember(column) { mutableFloatStateOf(0f) }
        LaunchedEffect(column) {
            val perWord = column.height / maxOf(1, track.words.size)
            motion.plannedPace = track.wordsPerSecond(language).toFloat() * perWord
        }
        // The voice gives the motion a target; a change under a pixel is
        // not movement (iOS: an endless re-rounding loop).
        LaunchedEffect(column, cursor) {
            val (y, top, advance) = column.target(cursor) ?: return@LaunchedEffect
            val snap = cursor == 0
            if (kotlin.math.abs(y - motion.target) >= 1f || (snap && kotlin.math.abs(y - motion.position) >= 1f)) {
                motion.setTarget(y, top, advance)
                if (snap) { motion.snap(); position = motion.position }
            }
        }
        LaunchedEffect(recording) {
            if (!recording && cursor == 0) { motion.snap(); position = motion.position }
        }
        LaunchedEffect(column, recording, follow, speed, held) {
            var last = 0L
            while (true) {
                withFrameNanos { now ->
                    if (last != 0L) {
                        val dt = ((now - last) / 1e9f).coerceAtMost(0.05f)
                        motion.step(dt, com.roro.futurevoice.talk.PrompterMotion.Input(
                            recording, follow, speed, session.voiceActive(), held))
                        if (kotlin.math.abs(motion.position - position) > 0.01f) position = motion.position
                        // The video scrolls with the prompter the reader saw.
                        session.composer.offset = motion.position - readingLine
                    }
                    last = now
                }
            }
        }
        Canvas(
            Modifier.fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.015f to Color.Black,
                        0.86f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                },
        ) {
            val top = position - readingLine
            drawContext.canvas.nativeCanvas.apply {
                save()
                clipRect(0f, 0f, size.width, size.height)
                translate(0f, -top)
                column.draw(this, top - column.lineHeight, top + size.height + column.lineHeight)
                restore()
            }
        }
    }
}

@Composable
private fun PrompterSettingsMenu(
    expanded: Boolean, onDismiss: () -> Unit, follow: Boolean, speed: Float, textSize: Float,
    onFollow: (Boolean) -> Unit, onSpeed: (Float) -> Unit, onTextSize: (Float) -> Unit,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        MenuHeader(stringResource(R.string.scrolling))
        CheckItem(stringResource(R.string.follow_my_voice), follow) { onFollow(true) }
        CheckItem(stringResource(R.string.steady_speed), !follow) { onFollow(false) }
        if (!follow) {
            HorizontalDivider()
            MenuHeader(stringResource(R.string.speed))
            CheckItem(stringResource(R.string.slower), speed == 0.8f) { onSpeed(0.8f) }
            CheckItem(stringResource(R.string.normal), speed == 1f) { onSpeed(1f) }
            CheckItem(stringResource(R.string.faster), speed == 1.2f) { onSpeed(1.2f) }
        }
        HorizontalDivider()
        MenuHeader(stringResource(R.string.text_size))
        CheckItem(stringResource(R.string.small), textSize == 22f) { onTextSize(22f) }
        CheckItem(stringResource(R.string.medium), textSize == 28f) { onTextSize(28f) }
        CheckItem(stringResource(R.string.large), textSize == 34f) { onTextSize(34f) }
    }
}

@Composable
private fun MenuHeader(text: String) {
    Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

@Composable
private fun CheckItem(text: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(text) }, onClick = onClick,
        trailingIcon = if (checked) ({ Icon(Icons.Filled.Check, null) }) else null)
}

@Composable
private fun Controls(
    recording: Boolean, onCamera: Boolean, cameraOn: Boolean, follow: Boolean,
    onCameraToggle: () -> Unit, onCancel: () -> Unit, onRecord: () -> Unit,
    onRestart: () -> Unit, onFollowToggle: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(36.dp), verticalAlignment = Alignment.CenterVertically) {
        if (recording) {
            // Drop this take: nothing saved, back to the top.
            ChromeButton(Icons.Filled.Close, stringResource(R.string.cancel_this_take), onCamera, onClick = onCancel)
        } else {
            ChromeButton(if (cameraOn) Icons.Filled.Videocam else Icons.Filled.VideocamOff,
                stringResource(if (cameraOn) R.string.turn_camera_off else R.string.turn_camera_on),
                onCamera, onClick = onCameraToggle)
        }
        val recordLabel = stringResource(if (recording) R.string.stop else R.string.record)
        Box(
            Modifier.size(76.dp).clip(CircleShape)
                .border(4.dp, if (onCamera) Color.White else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f), CircleShape)
                .clickable(role = androidx.compose.ui.semantics.Role.Button, onClick = onRecord)
                // iOS `.accessibilityLabel(isRecording ? "Stop" : "Record")` —
                // without it TalkBack read the take's main button as nothing.
                .then(Modifier.semantics { contentDescription = recordLabel }),
            contentAlignment = Alignment.Center,
        ) {
            if (recording) Box(Modifier.size(30.dp).background(Color(0xFFFF3B30), RoundedCornerShape(6.dp)))
            else Box(Modifier.size(62.dp).background(Color(0xFFFF3B30), CircleShape))
        }
        if (recording) {
            // Start over: this take is dropped and a new one counts in.
            ChromeButton(Icons.Filled.Refresh, stringResource(R.string.record_again), onCamera, onClick = onRestart)
        } else {
            ChromeButton(if (follow) Icons.Filled.GraphicEq else Icons.Filled.Speed,
                stringResource(if (follow) R.string.scrolling_follows_your_voice else R.string.scrolling_at_a_steady_speed),
                onCamera, onClick = onFollowToggle)
        }
    }
}

/** The round buttons on the camera card. Over the camera they go NEUTRAL —
 *  a white glyph on dark glass — so they read on any picture (iOS
 *  `SpeechChromeButtonStyle`); without the camera they are tinted circles. */
@Composable
private fun ChromeButton(icon: ImageVector, label: String, onCamera: Boolean, size: Dp = 52.dp,
                         onClick: () -> Unit) {
    val tint = if (onCamera) Color.White else MaterialTheme.colorScheme.primary
    val fill = if (onCamera) Color.Black.copy(alpha = 0.4f) else MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
    Box(Modifier.size(size).clip(CircleShape).background(fill).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(if (size > 40.dp) 24.dp else 20.dp))
    }
}

/** The quiet panel where the camera would be: a mic that breathes with the
 *  voice (iOS `SpeechMicGlyph`). */
@Composable
private fun MicPanel(session: SpeechTakeSession, recording: Boolean, denied: Boolean) {
    var level by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(recording) {
        while (recording) { level = session.micLevel; delay(60) }
        level = 0f
    }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer),
        contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(bottom = 70.dp)) {
            Icon(if (denied) Icons.Filled.VideocamOff else Icons.Filled.Mic, null,
                tint = if (recording) Color(0xFFFF3B30) else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp).scale(1f + level * 0.35f))
            if (denied) {
                Text(stringResource(R.string.camera_access_is_off_turn_it_on_in_settings_or_practise_with_527914),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
            }
        }
    }
}

@Composable
private fun OverlayCard(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 320.dp)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(16.dp))
            .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

/** Out of sight and out of reach while recording — the space is kept. */
private fun Modifier.hiddenWhile(hidden: Boolean): Modifier =
    this.alpha(if (hidden) 0f else 1f).then(
        if (hidden) Modifier.pointerInput(Unit) { awaitEachGesture { awaitFirstDown().consume() } } else Modifier)

@Composable
private fun navBarInset(): Dp = with(LocalDensity.current) {
    WindowInsets.navigationBars.getBottom(this).toDp()
}

/** The glass's own corner radius — Android reports it (API 31+); iOS keeps a
 *  table of panels (`574a4dda`) because it has no API. */
@Composable
private fun displayCornerRadius(): Dp {
    val view = LocalView.current
    val density = LocalDensity.current
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 24.dp
    val px = view.rootWindowInsets?.getRoundedCorner(RoundedCorner.POSITION_BOTTOM_LEFT)?.radius ?: return 24.dp
    return with(density) { px.toDp() }
}
