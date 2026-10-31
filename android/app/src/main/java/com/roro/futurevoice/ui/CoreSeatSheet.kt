package com.roro.futurevoice.ui

import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.CoreClubClient
import com.roro.futurevoice.ui.brand.FutureselfTheme
import com.roro.futurevoice.ui.brand.CoreClubColor
import com.roro.futurevoice.ui.brand.CoreSeal
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

/**
 * iOS `CoreSeatDetailSheet`: one member's cube, opened by tapping their seat.
 * The cube stays put at the top; under it the name card, the hope (veiled
 * for anyone the server didn't send it to), and the cheers scroll.
 * The sheet wears the member's colour, strongest at the top.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CoreSeatSheet(language: String, index: Int, onDismiss: () -> Unit,
                  preview: Pair<CoreClubClient.SeatDetail, CoreClubClient.Cheers>? = null,
                  /** Opened as the news of a new member (`core_new_member`): the
                   *  sheet leads with "member no. N is here" and, for a reader
                   *  without a seat, ends with their own way in. `onTalk` starts
                   *  today's talk from there. */
                  news: CoreClubClient.NewMember? = null,
                  onTalk: (() -> Unit)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember { CoreClubClient(AuthRepository()) }
    var detail by remember { mutableStateOf<CoreClubClient.SeatDetail?>(null) }
    var cheers by remember { mutableStateOf<CoreClubClient.Cheers?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var hope by remember { mutableStateOf("") }
    var draft by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var rising by remember { mutableStateOf<Pair<Long, CoreClubClient.Cheers.Note>?>(null) }
    val hearts = remember { mutableStateListOf<Long>() }
    var bigHeart by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf<CoreClubClient.Progress?>(null) }
    val someone = stringResource(R.string.someone)
    val meLabel = stringResource(R.string.me)

    suspend fun load() {
        if (preview != null) { detail = preview.first; cheers = preview.second; loaded = true; return }
        detail = client.seatDetail(language, index)
        cheers = client.cheers(language, index)
        loaded = true
        if (cheers?.mine == true) client.markCheersSeen(language)
    }
    LaunchedEffect(index) { load() }
    LaunchedEffect(news) {
        if (news == null || news.viewer_seated) return@LaunchedEffect
        progress = client.progress(language)
    }

    // Notes rise over the cube strictly one at a time, round and round.
    LaunchedEffect(Unit) {
        var i = 0
        while (true) {
            val notes = cheers?.notes.orEmpty()
            if (notes.isNotEmpty() && rising == null) {
                rising = System.nanoTime() to notes[i % notes.size]; i++
            }
            delay(RISE_MS + 400)
        }
    }

    fun burst() { repeat(7) { hearts.add(System.nanoTime() + it) } }
    fun toggleHeart() {
        val c = cheers ?: return
        val on = !c.hearted
        HapticEngine.medium(context)
        cheers = c.copy(hearted = on, hearts = (c.hearts + if (on) 1 else -1).coerceAtLeast(0))
        if (on) burst()
        scope.launch { client.setHeart(language, index, on)?.let { n -> cheers = cheers?.copy(hearts = n) } }
    }
    fun send() {
        val body = draft.trim()
        if (body.isEmpty() || sending) return
        sending = true
        HapticEngine.medium(context)
        scope.launch {
            val id = client.leaveNote(language, index, body)
            sending = false
            if (id == null) { HapticEngine.error(context); return@launch }
            val note = CoreClubClient.Cheers.Note(id, body, meLabel, by_me = true)
            cheers = cheers?.copy(notes = cheers!!.notes + note)
            draft = ""
            rising = System.nanoTime() to note   // yours goes up right away
        }
    }

    val tint = detail?.let { FutureselfTheme.from(it.theme).tint() } ?: Color.Transparent
    val ground = MaterialTheme.colorScheme.surfaceContainerLow
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = ground,
        dragHandle = null,
    ) {
        Column(Modifier.fillMaxSize().background(Brush.verticalGradient(
            0f to tint.copy(alpha = 0.45f), 0.35f to tint.copy(alpha = 0.12f), 1f to Color.Transparent))) {
            // Bar: Edit (own seat) · The Core · Done.
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp)) {
                if (editing) {
                    TextButton({ editing = false }, Modifier.align(Alignment.CenterStart)) { Text(stringResource(R.string.cancel)) }
                    TextButton({
                        scope.launch {
                            HapticEngine.medium(context)
                            client.setEngraving(language, name, hope); load(); editing = false
                        }
                    }, Modifier.align(Alignment.CenterEnd)) { Text(stringResource(R.string.save)) }
                } else {
                    if (detail?.mine == true) {
                        TextButton({ name = detail?.name.orEmpty(); hope = detail?.hope.orEmpty(); editing = true },
                            Modifier.align(Alignment.CenterStart)) { Text(stringResource(R.string.edit)) }
                    }
                    TextButton(onDismiss, Modifier.align(Alignment.CenterEnd)) { Text(stringResource(R.string.done)) }
                }
                Box(Modifier.align(Alignment.Center)) {
                    com.roro.futurevoice.ui.brand.IosNavTitle(stringResource(R.string.the_core))
                }
            }

            val d = detail
            if (d != null) {
                // The member's block stays put; only what is under it scrolls.
                Box(Modifier.fillMaxWidth().height(CoreCubeUnit * 2.2f)
                    .pointerInput(Unit) {
                        detectTapGestures(onDoubleTap = {
                            bigHeart = true
                            scope.launch { delay(600); bigHeart = false }
                            if (cheers?.hearted != true) toggleHeart() else { burst(); HapticEngine.light(context) }
                        })
                    }) {
                    CoreCube(FutureselfTheme.from(d.theme).tint(), d.name.orEmpty(),
                        if (d.can_read_hope) d.hope.orEmpty() else "",
                        Modifier.fillMaxSize(), since = d.seated_since, days = d.days_held)
                    BigHeart(bigHeart, Modifier.align(Alignment.Center))
                    rising?.let { (key, note) ->
                        RisingNote(key, note.name ?: someone, note.body,
                            Modifier.align(Alignment.BottomStart).padding(start = 20.dp, bottom = 8.dp)) {
                            if (rising?.first == key) rising = null
                        }
                    }
                    hearts.forEach { key ->
                        RisingHeart(key, Modifier.align(Alignment.BottomEnd).padding(end = 36.dp)) { hearts.remove(key) }
                    }
                }
            }

            Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
                if (d == null) {
                    if (loaded) GroupedFooter(stringResource(R.string.this_seat_couldn_t_be_opened_try_again_in_a_moment))
                    return@Column
                }
                if (news != null) NewsSection(news)
                GroupedCard {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        if (!d.name.isNullOrEmpty()) Text(d.name, style = MaterialTheme.typography.titleMedium)
                        else Text(stringResource(R.string.no_name_engraved), style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.seat_lld, d.index + 1), style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        d.days_held?.let {
                            Text(stringResource(R.string.day_lld_in_this_seat, it),
                                style = MaterialTheme.typography.bodyMedium, color = CoreClubColor)
                        }
                    }
                }

                if (editing) {
                    GroupedSectionHeader("")
                    GroupedCard {
                        EngraveField(name, stringResource(R.string.your_name), 24) { name = it }
                        TextRowDivider()
                        EngraveField(hope, stringResource(R.string.your_hope_in_one_line), 60) { hope = it }
                    }
                    GroupedFooter(stringResource(R.string.only_core_members_can_see_your_hope_anyone_can_see_your_name))
                } else {
                    GroupedSectionHeader(stringResource(R.string.hope))
                    GroupedCard {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
                            when {
                                !d.can_read_hope -> HopeVeil()
                                !d.hope.isNullOrEmpty() -> Text(d.hope, style = MaterialTheme.typography.bodyLarge)
                                else -> Text(stringResource(R.string.no_hope_engraved_yet),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    GroupedFooter(stringResource(R.string.only_core_members_can_see_this))
                }

                // After the hope: the cheers can run long.
                GroupedSectionHeader(stringResource(R.string.cheers))
                GroupedCard {
                    Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        IconButton({ toggleHeart() }) {
                            Icon(if (cheers?.hearted == true) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                stringResource(R.string.heart),
                                tint = if (cheers?.hearted == true) Color.Red else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text("${cheers?.hearts ?: 0}", style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary)
                        TextField(draft, { draft = it.take(40) }, Modifier.weight(1f),
                            placeholder = { Text(stringResource(R.string.leave_a_short_cheer)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                            keyboardActions = KeyboardActions(onSend = { send() }),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent))
                        IconButton({ send() }, enabled = draft.isNotBlank() && !sending) {
                            Icon(Icons.AutoMirrored.Filled.Send, null)
                        }
                    }
                    cheers?.notes?.reversed()?.forEach { note ->
                        TextRowDivider()
                        var menu by remember(note.id) { mutableStateOf(false) }
                        Box {
                            Column(Modifier.fillMaxWidth()
                                .combinedClickable(onClick = {}, onLongClick = {
                                    if (note.by_me || cheers?.mine == true) menu = true })
                                .padding(horizontal = 16.dp, vertical = 10.dp)) {
                                Text(note.name ?: someone, style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(note.body, style = MaterialTheme.typography.bodyLarge)
                            }
                            DropdownMenu(menu, { menu = false }) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = {
                                    menu = false
                                    cheers = cheers?.copy(notes = cheers!!.notes.filter { it.id != note.id })
                                    scope.launch { client.deleteNote(note.id) }
                                })
                            }
                        }
                    }
                }
                if (news != null && !news.viewer_seated) {
                    YourTurnSection(progress, onTalk?.let { talk -> { onDismiss(); talk() } })
                }
            }
        }
    }
}

// MARK: - News of a new member

@Composable
private fun NewsSection(news: CoreClubClient.NewMember) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(R.string.core_member_no_lld_is_here, news.number),
            style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
            textAlign = TextAlign.Center)
        Text(stringResource(R.string.s_30_days_in_a_row_without_missing_one_leave_a_heart_or_a_sh_0d416d),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center)
    }
}

/** The reader's own way in: where their streak stands, and today's talk. */
@Composable
private fun YourTurnSection(progress: CoreClubClient.Progress?, onTalk: (() -> Unit)?) {
    GroupedSectionHeader(stringResource(R.string.your_turn))
    GroupedCard {
        if (progress != null) {
            Text(
                if (progress.streak > 0) stringResource(R.string.you_re_on_day_lld_lld_more_days_to_the_core,
                    progress.streak, maxOf(0, progress.entry_streak - progress.streak))
                else stringResource(R.string.talk_lld_minutes_a_day_lld_days_in_a_row_and_a_seat_is_yours,
                    maxOf(1, progress.bar_seconds / 60), progress.entry_streak),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp))
        }
        if (onTalk != null) {
            if (progress != null) TextRowDivider()
            Row(Modifier.fillMaxWidth().clickable(onClick = onTalk)
                .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.Phone, null, tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp))
                Text(stringResource(R.string.talk_today), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

private const val RISE_MS = 4400L

@Composable
private fun EngraveField(value: String, prompt: String, limit: Int, onChange: (String) -> Unit) {
    TextField(value, { onChange(it.take(limit)) }, Modifier.fillMaxWidth(),
        placeholder = { Text(prompt) }, singleLine = true,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent))
}

/** One note on its way up, alone: fades in as it rises, drifts, fades out. */
@Composable
private fun RisingNote(key: Long, who: String, body: String, modifier: Modifier, onDone: () -> Unit) {
    val y = remember(key) { Animatable(8f) }
    val a = remember(key) { Animatable(0f) }
    LaunchedEffect(key) {
        launch { a.animateTo(1f, tween(800, easing = FastOutSlowInEasing)) }
        y.animateTo(-6f, tween(800, easing = FastOutSlowInEasing))
        y.animateTo(-30f, tween(2600, easing = LinearEasing))
        launch { a.animateTo(0f, tween(900)) }
        y.animateTo(-46f, tween(900))
        onDone()
    }
    Row(modifier.offset(y = y.value.dp).alpha(a.value)
        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.82f), RoundedCornerShape(50))
        .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(who, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold))
        Text(body, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun RisingHeart(key: Long, modifier: Modifier, onDone: () -> Unit) {
    val drift = remember(key) { Random.nextInt(-34, 24).toFloat() }
    val size = remember(key) { Random.nextInt(16, 26) }
    val delayMs = remember(key) { (key % 7) * 80 }
    val p = remember(key) { Animatable(0f) }
    LaunchedEffect(key) {
        delay(delayMs); p.animateTo(1f, tween(1600, easing = FastOutSlowInEasing)); onDone()
    }
    Icon(Icons.Filled.Favorite, null, modifier
        .offset(x = (drift * p.value).dp, y = (-180f * p.value).dp)
        .scale(0.4f + 0.75f * p.value).alpha(1f - p.value).size(size.dp), tint = Color.Red)
}

@Composable
private fun BigHeart(on: Boolean, modifier: Modifier) {
    val s = remember { Animatable(0.3f) }
    LaunchedEffect(on) {
        if (on) s.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium))
        else s.animateTo(0.3f, tween(250))
    }
    Icon(Icons.Filled.Favorite, null, modifier.size(96.dp).scale(s.value)
        .alpha(if (on) 0.95f else ((s.value - 0.3f) / 0.7f).coerceIn(0f, 1f)), tint = Color.White)
}

/**
 * A hope the reader may not see, under a veil that never lifts: blurred
 * placeholder lettering under drifting, twinkling specks. The server sent no
 * text, so there is nothing under it. A tap shivers it.
 */
@Composable
private fun HopeVeil() {
    val context = LocalContext.current
    val shake = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var t by remember { mutableStateOf(0f) }
    LaunchedEffect(Unit) {
        val start = System.nanoTime()
        while (true) { androidx.compose.runtime.withFrameNanos { t = (it - start) / 1e9f } }
    }
    val ink = MaterialTheme.colorScheme.onSurface
    Box(Modifier.fillMaxWidth().heightIn(min = 24.dp)
        .offset(x = (5f * kotlin.math.sin(shake.value * Math.PI.toFloat() * 6)).dp)
        .pointerInput(Unit) {
            detectTapGestures {
                HapticEngine.light(context)
                scope.launch { shake.snapTo(0f); shake.animateTo(1f, tween(350, easing = LinearEasing)) }
            }
        }) {
        Text("Hidden words under the veil here", style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.alpha(0.5f).then(
                if (Build.VERSION.SDK_INT >= 31) Modifier.blur(7.dp) else Modifier.alpha(0.3f)))
        Canvas(Modifier.matchParentSize()) {
            val rng = Random(7)
            repeat(170) {
                val x0 = rng.nextFloat() * size.width; val y0 = rng.nextFloat() * size.height
                val speed = 4 + rng.nextFloat() * 8; val phase = rng.nextFloat() * 6.28f
                val x = (x0 + t * speed * density) % size.width
                val y = y0 + kotlin.math.sin(t * 1.3f + phase) * 2.5f * density
                val alpha = 0.35f + 0.65f * (0.5f + 0.5f * kotlin.math.sin(t * 3 + phase))
                val r = (0.6f + rng.nextFloat() * 0.9f) * density
                drawCircle(ink.copy(alpha = alpha), r, Offset(x, y))
            }
        }
    }
}

/**
 * Which new member's news this install has already shown, per account and
 * club, so each arrival is offered once (iOS `CoreNewsStore`). iOS also asks
 * again from a push tap; Android has no server push, so it only asks on
 * arrival and on coming back to the foreground.
 */
object CoreNewsStore {
    private fun key(userId: String, language: String) =
        "futurevoice.core.newsSeen.${userId.lowercase()}.${language.lowercase()}"

    suspend fun due(context: android.content.Context, language: String,
                    fromLink: Boolean = false): CoreClubClient.NewMember? {
        val auth = AuthRepository()
        val uid = auth.userId ?: return null
        val after = if (fromLink) 0 else context.getSharedPreferences("futurevoice", 0).getInt(key(uid, language), 0)
        return CoreClubClient(auth).newMember(language, after)
    }

    fun markShown(context: android.content.Context, news: CoreClubClient.NewMember, language: String) {
        val uid = AuthRepository().userId ?: return
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val k = key(uid, language)
        prefs.edit().putInt(k, maxOf(news.event_id, prefs.getInt(k, 0))).apply()
    }

    /** Debug `--ei corenews 1|2`: a sample arrival, no server (1 = no seat yet, 2 = seated). */
    fun preview(seated: Boolean) = CoreClubClient.NewMember(event_id = 1, index = 0, name = "민지", theme = 4,
        viewer_seated = seated)
}
