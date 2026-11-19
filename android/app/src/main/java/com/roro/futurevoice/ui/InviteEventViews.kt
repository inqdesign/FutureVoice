package com.roro.futurevoice.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.InviteEvent
import com.roro.futurevoice.data.InviteEventDemo
import com.roro.futurevoice.data.InviteEventState
import com.roro.futurevoice.data.TrialReportStore
import com.roro.futurevoice.net.ReferralClient
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.iosFill
import com.roro.futurevoice.ui.brand.iosPlaceholder
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The friend-invite event on screen (iOS `InviteEventViews.swift`): the
 * banner under Settings' subscription row, the sheet that explains it, and
 * the sheet that takes a half-price month. Every word is the server's
 * ([InviteEvent.text]), so a line the server does not send is simply not
 * drawn, and nothing here has an entry in strings.xml.
 */

/** Which of the event's two sheets is up. */
enum class InviteEventSheetKind { ABOUT, CLAIM }

/** systemGreen: a semantic literal (something good happened to the plan). */
private val InviteGreen = Color(0xFF34C759)

/** The event's words for whoever is drawing: `words("banner_title")`. */
@Composable
private fun rememberInviteWords(state: InviteEventState): (String) -> String {
    val context = LocalContext.current
    val offer by InviteEvent.offerPrice.collectAsStateWithLifecycle()
    val full by InviteEvent.fullPrice.collectAsStateWithLifecycle()
    return remember(state, offer, full, context) {
        { key: String -> InviteEvent.text(context, key, state, offer, full) }
    }
}

// ── Banner ───────────────────────────────────────────────────────────────

/**
 * Settings, right under the subscription section. Draws its own section
 * (spacer included) and nothing at all while the event is off.
 */
@Composable
fun InviteEventBanner(open: (InviteEventSheetKind) -> Unit) {
    val state by InviteEvent.state.collectAsStateWithLifecycle()
    val words = rememberInviteWords(state)
    when (val phase = InviteEvent.phase(state)) {
        InviteEvent.Phase.Off -> Unit
        InviteEvent.Phase.Claim -> {
            GroupedSectionSpacer()
            ResultCard(kicker = words("claim_kicker"), title = words("claim_title"),
                body = words("claim_body"), button = words("claim_cta"), prominent = true) {
                open(InviteEventSheetKind.CLAIM)
            }
        }
        is InviteEvent.Phase.Applied -> {
            val auto = phase.auto
            GroupedSectionSpacer()
            ResultCard(kicker = words(if (auto) "auto_kicker" else "done_kicker"),
                title = words(if (auto) "auto_title" else "done_title"),
                body = words(if (InviteEvent.monthsWaiting(state) > 0) "done_more"
                    else if (auto) "auto_body" else "done_body"),
                button = words("invite_more"), prominent = false) {
                open(InviteEventSheetKind.ABOUT)
            }
        }
        InviteEvent.Phase.Invited -> {
            GroupedSectionSpacer()
            Promo(kicker = words("invited_kicker"), title = words("invited_title"),
                button = words("invited_cta"), percent = state.percent) { open(InviteEventSheetKind.ABOUT) }
        }
        InviteEvent.Phase.Invite, InviteEvent.Phase.NeedsPlan -> {
            GroupedSectionSpacer()
            Promo(kicker = words("banner_kicker"), title = words("banner_title"),
                button = words("banner_cta"), percent = state.percent) { open(InviteEventSheetKind.ABOUT) }
        }
    }
}

/**
 * The offer: text on the left, the two friends on the right, on the
 * drawing's own paper. The one illustrated block on the Settings page, so
 * nobody misses it.
 */
@Composable
private fun Promo(kicker: String, title: String, button: String, percent: Int, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth()
            .clip(ContinuousShape(22.dp))
            .background(inviteArtPaper())
            .clickable(onClick = onClick)
            .padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (kicker.isNotEmpty()) {
                Text(kicker, style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold, color = accent)
            }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface)
            if (button.isNotEmpty()) {
                Box(Modifier.padding(top = 8.dp).height(34.dp)
                    .background(accent, CircleShape).padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center) {
                    Text(button, style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
                }
            }
        }
        InviteArt(percent = percent, modifier = Modifier.width(176.dp))
    }
}

/** What came of it: a plain card, so it reads as news about the plan. */
@Composable
private fun ResultCard(kicker: String, title: String, body: String, button: String,
                       prominent: Boolean, action: () -> Unit) {
    GroupedCard {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (kicker.isNotEmpty()) Text(kicker, style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold, color = InviteGreen)
            if (title.isNotEmpty()) Text(title, style = MaterialTheme.typography.titleMedium)
            if (body.isNotEmpty()) Text(body, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (button.isNotEmpty()) {
                val accent = MaterialTheme.colorScheme.primary
                // iOS `.controlSize(.regular)` capsule: prominent is the
                // filled accent, the other the light tint of it (`.bordered`).
                androidx.compose.material3.Button(
                    onClick = action,
                    modifier = Modifier.padding(top = 8.dp).heightIn(min = 34.dp),
                    shape = CircleShape,
                    colors = if (prominent) ButtonDefaults.buttonColors()
                        else ButtonDefaults.buttonColors(containerColor = accent.copy(alpha = 0.12f),
                            contentColor = accent),
                    elevation = null,
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 7.dp),
                ) { Text(button, style = MaterialTheme.typography.bodyMedium) }
            }
        }
    }
}

// ── The picture ──────────────────────────────────────────────────────────

/**
 * The drawing is cut out of its paper (transparent around the people), so
 * the card under it follows the theme: the drawing's own cream paper in the
 * light theme, the grouped card in the dark one.
 */
@Composable
private fun inviteArtPaper(): Color =
    if (appIsDark()) AppSurfaces.card else Color(0xFFFCF9F0)

/** Where the two boards are, as fractions of the picture (x, y, width, height). */
private val InviteBoards = listOf(
    floatArrayOf(0.024f, 0.079f, 0.256f, 0.252f),
    floatArrayOf(0.721f, 0.079f, 0.258f, 0.252f),
)

/**
 * Two friends, each holding up a board (`drawable-nodpi/invite_art`, the iOS
 * `InviteArt` asset). The boards are EMPTY in the drawing: the percentage is
 * the event's, so it is drawn here, on top.
 */
@Composable
fun InviteArt(percent: Int, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.aspectRatio(1100f / 870f).clearAndSetSemantics { }) {
        Image(painterResource(R.drawable.invite_art), contentDescription = null,
            contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        val w = maxWidth
        val h = maxHeight
        val density = LocalDensity.current
        InviteBoards.forEach { board ->
            val boardW: Dp = w * board[2]
            val boardH: Dp = h * board[3]
            // A size in the picture's own points: it must not follow the
            // phone's font scale, or the number leaves its board.
            val size = with(density) { (boardH * 0.5f).toSp() }
            Box(Modifier.offset(x = w * board[0], y = h * board[1]).size(boardW, boardH),
                contentAlignment = Alignment.Center) {
                BasicText("$percent%", maxLines = 1, softWrap = false,
                    style = TextStyle(color = Color.White, fontWeight = FontWeight.ExtraBold,
                        fontSize = size, textAlign = TextAlign.Center),
                    autoSize = TextAutoSize.StepBased(minFontSize = size * 0.5f, maxFontSize = size,
                        stepSize = 0.5.sp))
            }
        }
    }
}

// ── The sheet that explains it ───────────────────────────────────────────

private const val PLAY_URL = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

/** The server's share message (it carries the code), then the store link. */
private fun shareInviteEvent(context: Context) {
    val text = InviteEvent.shareMessage(context) + "\n" + PLAY_URL
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "nawana")
        putExtra(Intent.EXTRA_TEXT, text)
    }, null))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InviteEventSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by InviteEvent.state.collectAsStateWithLifecycle()
    val words = rememberInviteWords(state)
    val phase = InviteEvent.phase(state)
    var showingPaywall by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        Analytics.capture("invite_event_sheet", mapOf("phase" to phase.toString()))
    }
    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
    ) {
        Column(Modifier.fillMaxSize().bottomBarInsets()) {
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 16.dp)) {
                // No box: the two people stand on the sheet itself, in both themes.
                Box(Modifier.fillMaxWidth().padding(vertical = 6.dp), contentAlignment = Alignment.Center) {
                    InviteArt(percent = state.percent, modifier = Modifier.widthIn(max = 280.dp))
                }
                Text(words("sheet_title"), style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 20.dp))
                Text(words("sheet_body"), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp))

                // `step1`, `step2`… for as long as the server sends them.
                val accent = MaterialTheme.colorScheme.primary
                Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    lines(words, "step").forEachIndexed { index, step ->
                        Row(verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(Modifier.size(28.dp).background(accent.copy(alpha = 0.12f), CircleShape),
                                contentAlignment = Alignment.Center) {
                                Text("${index + 1}", style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Bold, color = accent)
                            }
                            Text(step, style = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 16.sp, lineHeight = 21.sp))
                        }
                    }
                }

                val rules = lines(words, "rule")
                if (rules.isNotEmpty()) {
                    Column(
                        Modifier.padding(top = 16.dp).fillMaxWidth()
                            .background(
                                // iOS `secondarySystemBackground`.
                                if (appIsDark()) MaterialTheme.colorScheme.surfaceContainerHigh
                                else MaterialTheme.colorScheme.surfaceContainer,
                                ContinuousShape(14.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        rules.forEach { rule ->
                            Text("· $rule", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                if (phase == InviteEvent.Phase.NeedsPlan) {
                    Spacer(Modifier.height(16.dp))
                    CodeEntry(words)
                }
            }

            // The actions, pinned under the scrolling page.
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (phase) {
                    InviteEvent.Phase.Invite, is InviteEvent.Phase.Applied, InviteEvent.Phase.Claim ->
                        Primary(words("sheet_cta")) { shareInviteEvent(context) }
                    InviteEvent.Phase.Invited ->
                        Primary(words("invited_cta")) { showingPaywall = true }
                    InviteEvent.Phase.NeedsPlan -> {
                        val note = words("sheet_free_note")
                        if (note.isNotEmpty()) Text(note, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Primary(words("sheet_cta_free")) { showingPaywall = true }
                    }
                    InviteEvent.Phase.Off -> Unit
                }
                TextButton(onClick = onDismiss, modifier = Modifier.padding(bottom = 4.dp)) {
                    Text(words("later"), style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
    // The sheet owns its own plans page: one raised by the screen underneath
    // would open behind this sheet.
    if (showingPaywall) PaywallDialog(onDismiss = {
        showingPaywall = false
        scope.launch { InviteEvent.refresh(context) }
    })
}

private fun lines(words: (String) -> String, prefix: String): List<String> =
    (1..6).map { words("$prefix$it") }.filter { it.isNotEmpty() }

@Composable
private fun Primary(title: String, onClick: () -> Unit) {
    IosButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Text(title, style = MaterialTheme.typography.labelLarge)
    }
}

/** A friend's code, for someone who did not type it when they joined. */
@Composable
private fun CodeEntry(words: (String) -> String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var codeInput by remember { mutableStateOf("") }
    var codeNote by remember { mutableStateOf<String?>(null) }
    var redeeming by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BasicTextField(
                value = codeInput,
                onValueChange = { codeInput = it.uppercase() },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                cursorBrush = SolidColor(accent),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters,
                    autoCorrectEnabled = false),
                modifier = Modifier.weight(1f).height(40.dp)
                    .background(iosFill(), ContinuousShape(10.dp)).padding(horizontal = 12.dp),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
                        if (codeInput.isEmpty()) Text(words("code_placeholder"),
                            style = MaterialTheme.typography.bodyLarge, color = iosPlaceholder(), maxLines = 1)
                        inner()
                    }
                },
            )
            val enabled = !redeeming && codeInput.isNotBlank()
            androidx.compose.material3.Button(
                onClick = {
                    redeeming = true
                    scope.launch {
                        runCatching { ReferralClient(AuthRepository()).redeem(codeInput) }
                            .onSuccess {
                                codeInput = ""
                                codeNote = null
                                InviteEvent.refresh(context)
                            }
                            .onFailure { e -> codeNote = context.getString(redeemFailureText(e)) }
                        redeeming = false
                    }
                },
                enabled = enabled,
                modifier = Modifier.heightIn(min = 34.dp),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = accent.copy(alpha = 0.12f),
                    contentColor = accent,
                    disabledContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
                    disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)),
                elevation = null,
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 7.dp),
            ) { Text(words("code_cta"), style = MaterialTheme.typography.bodyMedium) }
        }
        codeNote?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ── The sheet that takes the month ───────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InviteClaimSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val state by InviteEvent.state.collectAsStateWithLifecycle()
    val words = rememberInviteWords(state)
    val offer by InviteEvent.offerPrice.collectAsStateWithLifecycle()
    val full by InviteEvent.fullPrice.collectAsStateWithLifecycle()
    val claiming by InviteEvent.claiming.collectAsStateWithLifecycle()
    val error by InviteEvent.claimError.collectAsStateWithLifecycle()
    val busy by rememberUpdatedState(claiming)
    LaunchedEffect(Unit) {
        InviteEvent.clearClaimError()
        Analytics.capture("invite_claim_sheet")
    }
    ModalBottomSheet(
        // Not swiped away while Play's sheet is being answered.
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { !busy }),
        onDismissRequest = { if (!claiming) onDismiss() },
    ) {
        Column(Modifier.sheetBody().padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 24.dp)) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = InviteGreen,
                modifier = Modifier.size(56.dp))
            Text(words("claim_sheet_title"), style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
            val offerPrice = offer
            val fullPrice = full
            if (offerPrice != null && fullPrice != null) {
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(fullPrice, style = MaterialTheme.typography.bodyLarge,
                        textDecoration = TextDecoration.LineThrough,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.alignByBaseline())
                    Text(offerPrice, fontSize = 40.sp, lineHeight = 46.sp, fontWeight = FontWeight.ExtraBold,
                        modifier = Modifier.alignByBaseline())
                }
            }
            Text(words("claim_sheet_body"), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
            error?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            }
            Spacer(Modifier.height(20.dp))
            IosButton(
                onClick = {
                    val activity = context.findActivity() ?: return@IosButton
                    InviteEvent.claim(activity, onTaken = onDismiss)
                },
                enabled = !claiming,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (claiming) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp,
                    color = LocalContentColor.current)
                else Text(words("claim_cta"), style = MaterialTheme.typography.labelLarge)
            }
            TextButton(onClick = { if (!claiming) onDismiss() },
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Text(words("later"), style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}

// ── One line elsewhere ───────────────────────────────────────────────────

/**
 * A line on a screen that is not the event's own (the code field at sign
 * up): the event's words while it is on, the screen's own otherwise.
 */
@Composable
fun inviteEventLine(key: String, fallback: String): String {
    val context = LocalContext.current
    val state by InviteEvent.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.enabled) { InviteEvent.loadPublicIfNeeded(context) }
    val line = if (state.enabled) InviteEvent.text(context, key, state) else ""
    return line.ifEmpty { fallback }
}

// ── Hosting ──────────────────────────────────────────────────────────────

/** The event's two sheets, owned by whichever screen raises them. */
@Composable
fun InviteEventSheets(kind: InviteEventSheetKind?, onDismiss: () -> Unit) {
    when (kind) {
        InviteEventSheetKind.ABOUT -> InviteEventSheet(onDismiss)
        InviteEventSheetKind.CLAIM -> InviteClaimSheet(onDismiss)
        null -> Unit
    }
}

/**
 * The invite event speaks up by itself twice, once each (iOS
 * `RootTabView.offerInviteEvent`): a half-price month that is waiting to be
 * taken, and the announcement (once per `announce_version`). Asked on arrival
 * at the tabs and on every return to the foreground, a beat after the app is
 * up, never over a call or another sheet. `futurevoice://invite` is a tap,
 * which always opens. There is no server push on Android, so the foreground
 * read is also how the inviter learns a friend subscribed.
 */
@Composable
fun InviteEventHost(ready: Boolean, blocked: Boolean) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val asked by InviteEvent.asked.collectAsStateWithLifecycle()
    val demoSheet by InviteEventDemo.sheet.collectAsStateWithLifecycle()
    var sheet by remember { mutableStateOf<InviteEventSheetKind?>(null) }
    var resumes by remember { mutableIntStateOf(0) }
    var handledAsk by remember { mutableIntStateOf(0) }
    val stillBlocked by rememberUpdatedState(blocked)
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { resumes++ }
    }
    LaunchedEffect(ready, resumes, asked) {
        if (!ready) return@LaunchedEffect
        // An ask stays owed until it is answered: a return to the foreground
        // restarts this, and must not swallow the tap that caused it.
        val wasAsked = asked != handledAsk
        InviteEvent.refresh(context)
        delay(if (wasAsked) 300 else 2_500)
        if (wasAsked) handledAsk = asked
        if (InviteEvent.phase == InviteEvent.Phase.Off || sheet != null) return@LaunchedEffect
        if (wasAsked) {
            val claim = InviteEvent.phase == InviteEvent.Phase.Claim
            if (claim) InviteEvent.markClaimOffered(context)
            sheet = if (claim) InviteEventSheetKind.CLAIM else InviteEventSheetKind.ABOUT
            return@LaunchedEffect
        }
        if (stillBlocked || TrialReportStore.isShowing) return@LaunchedEffect
        if (InviteEvent.owesClaimOffer(context)) {
            InviteEvent.markClaimOffered(context)
            sheet = InviteEventSheetKind.CLAIM
        } else if (InviteEvent.owesAnnouncement(context)) {
            InviteEvent.markAnnounced(context)
            sheet = InviteEventSheetKind.ABOUT
        }
    }
    // The debug preview's "raise a sheet at once".
    LaunchedEffect(demoSheet, ready) {
        val raw = demoSheet ?: return@LaunchedEffect
        if (!ready) return@LaunchedEffect
        InviteEventDemo.sheet.value = null
        sheet = if (raw == "claim") InviteEventSheetKind.CLAIM else InviteEventSheetKind.ABOUT
    }
    InviteEventSheets(sheet) { sheet = null }
}
