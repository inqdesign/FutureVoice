package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.DisplayFace
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.CoreClubColor
import com.roro.futurevoice.ui.brand.CoreSeal
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * iOS `CoreWelcomeStore`: whether this device has celebrated the learner's
 * seat yet, per account and per club. Shown whenever the learner is SEATED
 * and this device hasn't celebrated it, never "when the entering tick
 * happened" — the nightly settlement seats people too.
 */
object CoreWelcomeStore {
    data class Seat(val userId: String, val language: String, val index: Int, val seats: Int,
                    val streak: Int, val othersThemes: List<Int>) {
        val number get() = index + 1
        val isPreview get() = userId == "preview"
    }

    /** Me → Developer's Core welcome preview (iOS `DailyCallInbox.debugCoreWelcome`). */
    val debug = kotlinx.coroutines.flow.MutableStateFlow<Seat?>(null)

    private fun key(userId: String, language: String) =
        "futurevoice.core.welcomed.${userId.lowercase()}.${language.lowercase()}"

    fun markWelcomed(context: Context, seat: Seat) {
        context.getSharedPreferences("futurevoice", 0).edit().putBoolean(key(seat.userId, seat.language), true).apply()
    }

    suspend fun due(context: Context, language: String): Seat? {
        val auth = AuthRepository()
        val uid = auth.userId?.lowercase() ?: return null
        if (context.getSharedPreferences("futurevoice", 0).getBoolean(key(uid, language), false)) return null
        val client = CoreClubClient(auth)
        val map = client.seatMap(language) ?: return null
        val mine = map.mine ?: return null
        val progress = client.progress(language)
        val others = map.themes.toMutableList().also { if (mine < it.size) it.removeAt(mine) }
        return Seat(uid, language, mine, map.seats, progress?.entry_streak ?: 30, others)
    }

    /** Debug: the first seat of an empty club, nothing remembered. */
    val preview get() = preview("en")

    /** Me → Developer: seat 24 of a club where 23 already sit, in the
     *  learner's own language. Nothing it picks is saved ([Seat.isPreview]). */
    fun preview(language: String): Seat {
        val palettes = FutureselfTheme.entries.map { it.ordinal }
        val others = (0 until 23).map { palettes[(it * 5 + 2) % palettes.size] }
        return Seat("preview", language, 23, 100, 30, others)
    }
}

private enum class Stage { ARRIVING, PICKING, ENGRAVING, PLACING, PLACED }

/**
 * iOS `CoreWelcomeView`: the moment a learner takes a seat in the Core.
 * A cube arrives; they pick its colour (the app theme: the seat grid draws
 * every member in the palette their app wears); they engrave it, the name
 * on one face and a hope on another; it flies into their cell.
 */
@Composable
fun CoreWelcome(seat: CoreWelcomeStore.Seat, initialName: String, onDone: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    var theme by remember { mutableStateOf(FutureselfTheme.stored(context)) }
    var stage by remember { mutableStateOf(Stage.ARRIVING) }
    var name by remember { mutableStateOf("") }
    var hope by remember { mutableStateOf("") }
    var typing by remember { mutableStateOf(false) }
    var flying by remember { mutableStateOf(false) }
    var landed by remember { mutableStateOf(false) }
    var cubeRect by remember { mutableStateOf(Rect.Zero) }
    var cellRect by remember { mutableStateOf(Rect.Zero) }
    val flight = remember { Animatable(0f) }
    // The welcome is always night: the bright variants, whatever the phone is set to.
    val color = theme.tint(dark = true)
    val sky by animateColorAsState(color, tween(450), label = "sky")
    val density = LocalDensity.current
    val today = remember {
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
    }

    LaunchedEffect(Unit) {
        HapticEngine.success(context)
        delay(1500)
        stage = Stage.PICKING
    }

    fun place() {
        HapticEngine.medium(context)
        focus.clearFocus()
        stage = Stage.PLACING
        val language = seat.language
        // A preview is not a seat: nothing it picks may reach the account.
        if (!seat.isPreview) {
            scope.launch {
                val client = CoreClubClient(AuthRepository())
                client.publishTheme(theme.ordinal)
                client.setEngraving(language, name, hope)
            }
        }
        scope.launch {
            // The cube turns square to the learner first, then the face it
            // became flies to its cell.
            delay(550)
            flying = true
            flight.snapTo(0f)
            flight.animateTo(1f, spring(dampingRatio = 0.82f, stiffness = 120f))
            landed = true; flying = false
            HapticEngine.rigid(context)
            stage = Stage.PLACED
        }
    }
    fun pickAgain() {
        HapticEngine.medium(context)
        stage = Stage.PLACING
        scope.launch {
            landed = false; flying = true
            flight.animateTo(0f, tween(600, easing = FastOutSlowInEasing))
            flying = false
            stage = Stage.PICKING
        }
    }

    Dialog(onDismissRequest = {}, properties = DialogProperties(
        usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            // The sky: a wide ellipse centred above the top edge so only its
            // lower half comes down, in the colour being picked.
            Canvas(Modifier.fillMaxSize()) {
                val r = size.height * 0.62f
                scale(1.2f, 1f, pivot = Offset(size.width / 2, -size.height * 0.06f)) {
                    drawCircle(Brush.radialGradient(
                        0f to sky, 0.22f to sky.copy(alpha = 0.78f), 0.48f to sky.copy(alpha = 0.42f),
                        0.74f to sky.copy(alpha = 0.14f), 1f to Color.Transparent,
                        center = Offset(size.width / 2, -size.height * 0.06f), radius = r),
                        r, Offset(size.width / 2, -size.height * 0.06f))
                }
                drawRect(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.9f),
                    0.06f to Color.Black.copy(alpha = 0.45f), 0.2f to Color.Transparent))
            }

            // The grid, over the top of the screen; tapping it before Done
            // takes the cube back out to the colours.
            val gridShown = stage == Stage.PLACING || stage == Stage.PLACED
            val gridAlpha by animateFloatAsState(if (gridShown) 1f else 0f, tween(400), label = "grid")
            Box(Modifier.fillMaxWidth().statusBarsPadding().padding(top = 96.dp), contentAlignment = Alignment.TopCenter) {
                val gap = with(density) { 3.dp.toPx() }
                val tints = FutureselfTheme.entries.map { it.tint(dark = true) }
                Canvas(Modifier.width(200.dp).height(200.dp).alpha(gridAlpha)
                    .onGloballyPositioned { coords ->
                        val b = coords.boundsInRoot()
                        cellRect = coreCellRect(seat.index, b.size, 10, gap).translate(b.topLeft)
                    }
                    .pointerInput(stage) { detectTapGestures { if (stage == Stage.PLACED) pickAgain() } }) {
                    for (i in 0 until seat.seats) {
                        val other = when {
                            i == seat.index -> null
                            i > seat.index -> seat.othersThemes.getOrNull(i - 1)
                            else -> seat.othersThemes.getOrNull(i)
                        }
                        val c = when {
                            i == seat.index && landed -> color
                            other != null -> tints.getOrNull(other) ?: Color.Gray
                            else -> null
                        }
                        drawCoreBlock(coreCellRect(i, size, 10, gap), c, i == seat.index && landed, true)
                    }
                }
            }

            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()
                .padding(horizontal = 24.dp).padding(bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Spacer(Modifier.height(if (typing) 4.dp else if (stage == Stage.ENGRAVING) 56.dp else 200.dp))
                val cubeScale by animateFloatAsState(if (typing) 1.35f else 1f, tween(300), label = "cube")
                Box(Modifier.fillMaxWidth().height(CoreCubeUnit * (if (typing) 1.8f else 2.4f))
                    .offset(y = if (typing) (-70).dp else 0.dp)
                    .pointerInput(Unit) { detectTapGestures { focus.clearFocus() } },
                    contentAlignment = Alignment.Center) {
                    CoreCube(color, name, hope,
                        Modifier.size(CoreCubeUnit * 2.2f)
                            .alpha(if (flying || landed) 0f else 1f)
                            .scale(cubeScale)
                            .onGloballyPositioned { cubeRect = it.boundsInRoot() },
                        since = today, days = 1,
                        flatten = stage == Stage.PLACING || stage == Stage.PLACED)
                }

                if (!typing) WelcomeText(stage, seat, hope)
                Spacer(Modifier.weight(1f))
                Controls(stage, theme, name, hope, typing,
                    onTheme = { theme = it; FutureselfTheme.pick(context, it); HapticEngine.selection(context) },
                    onName = { name = it.take(24) }, onHope = { hope = it.take(60) },
                    onTyping = { typing = it },
                    onBack = { focus.clearFocus(); stage = Stage.PICKING },
                    onPrimary = {
                        when (stage) {
                            Stage.PICKING -> {
                                HapticEngine.selection(context)
                                if (name.isEmpty()) name = initialName.take(24)
                                stage = Stage.ENGRAVING
                            }
                            Stage.ENGRAVING -> place()
                            else -> {
                                HapticEngine.light(context)
                                CoreWelcomeStore.markWelcomed(context, seat)
                                com.roro.futurevoice.core.Analytics.capture("core_welcome_done",
                                    mapOf("number" to seat.number, "theme" to theme.ordinal))
                                onDone()
                            }
                        }
                    })
            }

            // The flight: the cube's front face, from the middle of the screen
            // to its cell (and back, on "pick again").
            if (flying && cubeRect != Rect.Zero && cellRect != Rect.Zero) {
                val unitPx = with(density) { CoreCubeUnit.toPx() }
                val from = Rect(cubeRect.center - Offset(unitPx / 2, unitPx / 2), Size(unitPx, unitPx))
                val p = flight.value
                val r = Rect(
                    Offset(from.left + (cellRect.left - from.left) * p, from.top + (cellRect.top - from.top) * p),
                    Size(from.width + (cellRect.width - from.width) * p, from.height + (cellRect.height - from.height) * p))
                Box(Modifier.offset(with(density) { r.left.toDp() }, with(density) { r.top.toDp() })
                    .size(with(density) { r.width.toDp() }, with(density) { r.height.toDp() })
                    .background(color, RoundedCornerShape((18 - 15 * p).dp)))
            }
        }
    }
}

@Composable
private fun WelcomeText(stage: Stage, seat: CoreWelcomeStore.Seat, hope: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.alpha(if (stage == Stage.ARRIVING) 0f else 1f),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CoreSeal(size = 16.dp)
            Text(stringResource(R.string.the_core), color = CoreClubColor, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        }
        val title = when (stage) {
            Stage.PLACED -> stringResource(R.string.seat_lld_of_lld, seat.number, seat.seats)
            Stage.ENGRAVING -> stringResource(R.string.engrave_your_cube)
            else -> stringResource(R.string.you_re_core_member_no_lld, seat.number)
        }
        Text(title, color = Color.White, textAlign = TextAlign.Center,
            style = TextStyle(fontFamily = DisplayFace.family(title), fontSize = 26.sp))
        when (stage) {
            Stage.PLACED -> {
                val shown = hope.trim()
                if (shown.isNotEmpty()) {
                    Text(stringResource(R.string.keep_this_seat_until_comes_true, shown), color = Color.White,
                        fontWeight = FontWeight.SemiBold, fontSize = 16.sp, textAlign = TextAlign.Center)
                }
                Text(stringResource(R.string.miss_one_day_a_month_and_the_seat_stays_yours_miss_more_and_21a3b6),
                    color = Color.White.copy(alpha = 0.65f), fontSize = 14.sp, textAlign = TextAlign.Center)
            }
            Stage.ENGRAVING -> Text(stringResource(R.string.your_name_goes_on_one_face_your_hope_on_another),
                color = Color.White.copy(alpha = 0.65f), fontSize = 14.sp, textAlign = TextAlign.Center)
            Stage.PLACING -> {}
            else -> Text(stringResource(R.string.lld_days_in_a_row_without_missing_one, seat.streak),
                color = Color.White.copy(alpha = 0.65f), fontSize = 14.sp, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun Controls(
    stage: Stage, theme: FutureselfTheme, name: String, hope: String, typing: Boolean,
    onTheme: (FutureselfTheme) -> Unit, onName: (String) -> Unit, onHope: (String) -> Unit,
    onTyping: (Boolean) -> Unit, onBack: () -> Unit, onPrimary: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().heightIn(min = 170.dp), verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.Bottom),
        horizontalAlignment = Alignment.CenterHorizontally) {
        AnimatedVisibility(stage == Stage.PICKING, enter = fadeIn(), exit = fadeOut()) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.this_cube_is_your_seat_in_the_core_pick_its_colour),
                    color = Color.White.copy(alpha = 0.65f), fontSize = 13.sp, textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    FutureselfTheme.entries.forEach { option ->
                        val tint = option.tint(dark = true)
                        Box(Modifier.size(44.dp).then(if (option == theme) Modifier.border(2.5.dp, Color.White, CircleShape) else Modifier)
                            .padding(5.dp).background(tint, CircleShape).clickable { onTheme(option) })
                    }
                }
                Text(stringResource(R.string.your_app_takes_this_colour_too),
                    color = Color.White.copy(alpha = 0.45f), fontSize = 12.sp)
            }
        }
        AnimatedVisibility(stage == Stage.ENGRAVING, enter = fadeIn(), exit = fadeOut()) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                EngraveBox(name, stringResource(R.string.your_name), onName, onTyping)
                EngraveBox(hope, stringResource(R.string.your_hope_in_one_line), onHope, onTyping)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Lock, null, Modifier.size(12.dp), tint = Color.White.copy(alpha = 0.55f))
                    Text(stringResource(R.string.only_core_members_can_see_your_hope_anyone_can_see_your_name),
                        color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp)
                }
                Text(stringResource(R.string.back_to_colours), color = Color.White.copy(alpha = 0.7f),
                    fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.clickable { onBack() })
            }
        }
        if (stage == Stage.PICKING || stage == Stage.ENGRAVING || stage == Stage.PLACED) {
            Button(onPrimary, Modifier.fillMaxWidth().height(54.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black)) {
                Text(when (stage) {
                    Stage.PICKING -> stringResource(R.string.next)
                    Stage.ENGRAVING -> stringResource(R.string.put_it_in_my_seat)
                    else -> stringResource(R.string.done)
                }, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
private fun EngraveBox(value: String, prompt: String, onChange: (String) -> Unit, onTyping: (Boolean) -> Unit) {
    BasicTextField(value, onChange, singleLine = true,
        textStyle = TextStyle(color = Color.White, fontSize = 16.sp),
        cursorBrush = SolidColor(Color.White),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        modifier = Modifier.fillMaxWidth().onFocusChanged { onTyping(it.isFocused) }
            .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        decorationBox = { inner ->
            Box { if (value.isEmpty()) Text(prompt, color = Color.White.copy(alpha = 0.4f), fontSize = 16.sp); inner() }
        })
}
