package com.roro.futurevoice.ui.speech

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.compose.ui.layout.onSizeChanged
import com.roro.futurevoice.data.SpeechStore
import androidx.compose.ui.unit.sp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.SpeechChallenges
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.ui.FormChevron
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.FormTextRow
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.KeyboardCapitalization
import com.roro.futurevoice.ui.NavPageBackHandler
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.BookIconDisc
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.IosOutlinedButton
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.FitButtonLabel
import com.roro.futurevoice.ui.brand.IosDropdownMenu
import com.roro.futurevoice.ui.brand.IosDropdownMenuItem
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

// Speech challenges — iOS `SpeechChallengeViews.swift`.

// MARK: - Card on the Speech tab

/** One challenge as a card, the review page's book card anatomy (iOS
 *  2026-10-16): the trophy in a tinted disc top-left, the learner's standing
 *  top-right, the title large, one quiet line under it, and the board's top
 *  three at the foot. A card standing alone: no row fill, no separator, no
 *  chevron, a 6 pt gap above and below (iOS `speechCardRow`). */
@Composable
internal fun SpeechChallengeRow(script: SpeechScript, standing: SpeechChallenges.Standing?,
                                modifier: Modifier = Modifier, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        modifier.fillMaxWidth().padding(vertical = 6.dp)
            .clip(ContinuousShape(18.dp))
            .background(AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            BookIconDisc(accent = accent) {
                Icon(Icons.Filled.EmojiEvents, contentDescription = null, tint = accent,
                    modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.weight(1f))
            val rank = standing?.myRank
            val best = standing?.myBest
            if (rank != null && best != null) {
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("#$rank", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("$best", style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = scoreColor(best))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(script.title, style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, maxLines = 3, overflow = TextOverflow.Ellipsis)
            val parts = listOf(
                stringResource(R.string.lld_taking_part, standing?.entrants ?: 0),
                lengthLabel(SpeechLibrary.estimatedSeconds(script.body, script.language)),
            )
            Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        val faces = standing?.topThree.orEmpty()
        if (faces.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            SpeechChallengeFaces(faces, size = 30.dp)
        }
    }
}

/** The board's top three as overlapping circles, first place in front: the
 *  photo when they chose to show one, else their initial. */
@Composable
internal fun SpeechChallengeFaces(faces: List<SpeechChallenges.Face>, size: androidx.compose.ui.unit.Dp = 22.dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(-size * 0.32f)) {
        faces.take(3).forEachIndexed { i, face ->
            Box(Modifier.zIndex((3 - i).toFloat()).size(size + 4.dp).clip(CircleShape)
                .background(AppSurfaces.card), contentAlignment = Alignment.Center) {
                SpeechChallengeFace(face, size)
            }
        }
    }
}

@Composable
internal fun SpeechChallengeFace(face: SpeechChallenges.Face, size: androidx.compose.ui.unit.Dp = 22.dp,
                                 localBitmap: android.graphics.Bitmap? = null) {
    val bitmap = localBitmap ?: remember(face.avatar) { face.bitmap() }
    Box(Modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center) {
        if (bitmap != null) {
            androidx.compose.foundation.Image(bitmap.asImageBitmap(), contentDescription = null,
                contentScale = ContentScale.Crop, modifier = Modifier.size(size))
        } else {
            // Without the font's extra top/bottom padding, so the letter sits
            // at the circle's centre (iOS centres the glyph).
            Text(face.display_name.take(1).uppercase(),
                style = TightText.copy(fontSize = (size.value * 0.45f).sp, lineHeight = (size.value * 0.45f).sp),
                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// MARK: - One challenge: its board and the way in

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechChallengeScreen(
    challengeId: String,
    native: String,
    level: CefrLevel,
    suggestedName: String,
    onBack: () -> Unit,
) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val challenges = remember { SpeechChallenges.shared(context) }
    val scripts by challenges.scripts.collectAsStateWithLifecycle()
    val standings by challenges.standings.collectAsStateWithLifecycle()
    val script = scripts.firstOrNull { it.id == challengeId }
    val standing = standings[challengeId]
    /** Retired: the board is frozen and nobody can enter. */
    val isPast = standing?.retiredAt != null
    var board by remember { mutableStateOf<List<SpeechChallenges.BoardRow>?>(null) }
    var loadFailed by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var practicing by remember { mutableStateOf(false) }
    var naming by remember { mutableStateOf(false) }
    var startAfterNaming by remember { mutableStateOf(false) }
    var showingScript by remember { mutableStateOf(false) }
    var showingTakes by remember { mutableStateOf(false) }
    val takes by SpeechStore.shared(context).takes.collectAsStateWithLifecycle()
    val takeCount = takes.count { it.scriptId == challengeId }
    // The bar floats over the board; the board scrolls clear of it.
    var barHeightPx by remember { mutableStateOf(0) }
    val density = androidx.compose.ui.platform.LocalDensity.current
    var menu by remember { mutableStateOf(false) }
    var confirmRetire by remember { mutableStateOf(false) }

    suspend fun reload() {
        val language = script?.language
        val list = scope.async { if (language != null) challenges.refresh(language) }
        val rows = challenges.board(challengeId)
        list.await()
        if (rows != null) { board = rows; loadFailed = false } else if (board == null) loadFailed = true
    }
    LaunchedEffect(challengeId) { reload() }

    // Nothing goes on a public board until the learner has seen the name.
    fun start() {
        if (SpeechChallenges.displayName(context) == null) { startAfterNaming = true; naming = true }
        else practicing = true
    }

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(script?.title.orEmpty(), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
                },
                actions = {
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more))
                        }
                        IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            IosDropdownMenuItem(text = { Text(stringResource(R.string.name_on_the_board)) },
                                leadingIcon = { Icon(Icons.Outlined.Badge, null) },
                                onClick = { menu = false; startAfterNaming = false; naming = true })
                            if (BillingGate.account?.unlimited == true && !isPast) {
                                IosDropdownMenuItem(text = { Text(stringResource(R.string.retire_challenge), color = Color(0xFFFF3B30)) },
                                    leadingIcon = { Icon(Icons.Outlined.Archive, null, tint = Color(0xFFFF3B30)) },
                                    onClick = { menu = false; confirmRetire = true })
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; reload(); refreshing = false } },
            modifier = Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize(),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = with(density) { barHeightPx.toDp() } + 24.dp)) {
                FormSection(
                    stringResource(R.string.leaderboard),
                    footer = if (isPast) stringResource(R.string.this_challenge_has_ended_these_are_the_final_standings)
                        else stringResource(R.string.only_takes_with_the_camera_on_go_on_the_board_and_your_best_d8b2bb),
                ) {
                    val rows = board
                    when {
                        rows != null && rows.isEmpty() -> Text(stringResource(R.string.nobody_s_on_this_board_yet_be_the_first),
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
                        rows != null -> {
                            var previous: Int? = null
                            rows.forEachIndexed { i, row ->
                                if (i > 0) FormDivider()
                                val prev = previous
                                if (prev != null && row.rank > prev + 1 && row.is_me) {
                                    Box(Modifier.fillMaxWidth().padding(vertical = 6.dp), contentAlignment = Alignment.Center) {
                                        Text("…", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    FormDivider()
                                }
                                BoardRow(row)
                                previous = row.rank
                            }
                        }
                        loadFailed -> Text(stringResource(R.string.the_board_couldn_t_load_pull_to_try_again),
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
                        else -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        }
                    }
                }

                val best = standing?.myBest
                val rank = standing?.myRank
                if (best != null && rank != null) {
                    FormSection(stringResource(R.string.you)) {
                        LabeledRow(stringResource(R.string.best)) {
                            Text("$best", fontWeight = FontWeight.SemiBold, color = scoreColor(best))
                        }
                        FormDivider()
                        LabeledRow(stringResource(R.string.place)) {
                            Text(stringResource(R.string.lld_of_lld_8e05fc, rank, standing.entrants.coerceAtLeast(rank)))
                        }
                        standing.myAttempts?.let { attempts ->
                            FormDivider()
                            // Tapping the count lists them (iOS 2026-10-16).
                            LabeledRow(stringResource(R.string.takes),
                                modifier = Modifier.clickable { showingTakes = true }) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("$attempts")
                                    FormChevron()
                                }
                            }
                        }
                    }
                }
            }
        }
        // The board first; the script and the way in together at the foot,
        // floating over the board so it shows through as it scrolls under
        // (iOS 2026-10-17, glass).
        if (script != null) {
            ChallengeActionBar(script, isPast = isPast, hasBest = standing?.myBest != null,
                takeCount = takeCount,
                onTakes = { showingTakes = true },
                onRead = { showingScript = true }, onStart = { start() },
                modifier = Modifier.align(Alignment.BottomCenter)
                    .onSizeChanged { barHeightPx = it.height })
        }
        }
    }

    if (naming) {
        SpeechChallengeNameSheet(suggested = suggestedName, onDismiss = { saved ->
            naming = false
            if (startAfterNaming && saved) practicing = true
            startAfterNaming = false
        })
    }
    if (showingScript && script != null) {
        SpeechScriptSheet(script, native, onEdited = {}, onDismiss = { showingScript = false })
    }
    if (showingTakes) {
        SpeechTakesSheet(scriptId = challengeId, onDismiss = { showingTakes = false })
    }
    if (practicing && script != null) {
        Dialog(
            onDismissRequest = {},
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false,
                dismissOnBackPress = false),
        ) {
            SpeechPrompterScreen(script, native, level, onClose = {
                practicing = false
                scope.launch { reload() }
            })
        }
    }
    if (confirmRetire) {
        AlertDialog(onDismissRequest = { confirmRetire = false },
            title = { Text(stringResource(R.string.retire_this_challenge_it_leaves_everyone_s_speech_tab)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRetire = false
                    scope.launch { runCatching { challenges.retire(challengeId) }; onBack() }
                }) { Text(stringResource(R.string.retire), color = Color(0xFFFF3B30)) }
            },
            dismissButton = { TextButton(onClick = { confirmRetire = false }) { Text(stringResource(R.string.cancel)) } })
    }
}

/** One container at the foot: what the script is, then three buttons — your
 *  takes (the prompter's own clock-and-count, no label), Read the script,
 *  and the start button — iOS `actionBar` (2026-10-17). A past challenge
 *  keeps the takes and Read the script. iOS draws it in Liquid Glass; here a
 *  translucent card, so the board still shows through as it scrolls under. */
@Composable
private fun ChallengeActionBar(script: SpeechScript, isPast: Boolean, hasBest: Boolean,
                               takeCount: Int, onTakes: () -> Unit,
                               onRead: () -> Unit, onStart: () -> Unit,
                               modifier: Modifier = Modifier) {
    val shape = ContinuousShape(28.dp)
    Column(
        modifier.fillMaxWidth().navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, bottom = 8.dp)
            .shadow(12.dp, shape, ambientColor = Color.Black.copy(alpha = 0.08f),
                spotColor = Color.Black.copy(alpha = 0.08f))
            .clip(shape)
            .background(AppSurfaces.card.copy(alpha = 0.8f))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (script.summary.isNotEmpty()) {
                Text(script.summary, style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Text(listOf(lengthLabel(SpeechLibrary.estimatedSeconds(script.body, script.language)),
                script.genre.title()).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
            Box {
                IosOutlinedButton(onClick = onTakes, modifier = Modifier.fillMaxHeight(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 15.dp, vertical = 12.dp)) {
                    Icon(Icons.Outlined.History, contentDescription = stringResource(R.string.takes),
                        modifier = Modifier.size(22.dp))
                }
                if (takeCount > 0) {
                    // The prompter's own count badge (iOS caption2 in an
                    // accent capsule at the top-right).
                    Text("$takeCount", color = Color.White, fontSize = 11.sp, lineHeight = 13.sp,
                        fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        style = androidx.compose.material3.LocalTextStyle.current.copy(fontFeatureSettings = "tnum"),
                        modifier = Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp)
                            .background(MaterialTheme.colorScheme.primary, CircleShape)
                            .padding(horizontal = 5.dp, vertical = 1.dp)
                            .widthIn(min = 7.dp))
                }
            }
            IosOutlinedButton(onClick = onRead, modifier = Modifier.weight(1f),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 12.dp)) {
                Icon(Icons.Outlined.Description, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                FitButtonLabel(stringResource(R.string.read_the_script),
                    MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
            }
            if (!isPast) {
                IosButton(onClick = onStart, modifier = Modifier.weight(1f),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 12.dp)) {
                    FitButtonLabel(stringResource(if (hasBest) R.string.go_again else R.string.take_the_challenge),
                        MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
                }
            }
        }
    }
}

@Composable
private fun LabeledRow(label: String, modifier: Modifier = Modifier, value: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        value()
    }
}

@Composable
private fun BoardRow(row: SpeechChallenges.BoardRow) {
    if (row.rank <= 3) { PodiumRow(row); return }
    val accent = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("${row.rank}", modifier = Modifier.widthIn(min = 28.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        SpeechChallengeFace(row.face, 28.dp)
        // Name and "You" take the leading space; the score sits at the trailing
        // edge (iOS `Spacer()`). Two weights split the row in half, so the score
        // stopped wherever the name's unused half ended.
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(row.display_name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                fontWeight = if (row.is_me) FontWeight.SemiBold else FontWeight.Normal,
                modifier = Modifier.weight(1f, fill = false))
            if (row.is_me) {
                Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = accent)
            }
        }
        Text("${row.score}", fontWeight = FontWeight.SemiBold, color = scoreColor(row.score))
    }
}

/** A top-three line, drawn large: the face with its place on a medal-
 *  coloured tag at the top-right, the name, the score — iOS `SpeechPodiumRow`. */
@Composable
private fun PodiumRow(row: SpeechChallenges.BoardRow) {
    val accent = MaterialTheme.colorScheme.primary
    val medal = when (row.rank) { 1 -> Color(0xFFFFCC00); 2 -> Color(0xFF8E8E93); else -> Color(0xFFA2845E) }
    val size = if (row.rank == 1) 56.dp else 48.dp
    Row(
        Modifier.fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = if (row.rank == 1) 14.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box {
            SpeechChallengeFace(row.face, size)
            // iOS: caption2 heavy on a capsule, 5 × 2 pt padding, a 2 pt ring.
            Text("#${row.rank}", fontWeight = FontWeight.ExtraBold,
                style = TightText.copy(fontSize = 10.sp, lineHeight = 12.sp),
                color = if (row.rank == 1) Color.Black else Color.White,
                modifier = Modifier.align(Alignment.TopEnd).offset(x = 8.dp, y = (-4).dp)
                    .border(2.dp, AppSurfaces.card, RoundedCornerShape(50))
                    .background(medal, RoundedCornerShape(50))
                    .padding(horizontal = 6.dp, vertical = 3.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(row.display_name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = if (row.rank == 1) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            if (row.is_me) {
                Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = accent)
            }
        }
        Text("${row.score}", fontWeight = FontWeight.Bold, color = scoreColor(row.score),
            style = if (row.rank == 1) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.headlineSmall)
    }
}

// MARK: - Every challenge, live and past

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechChallengeListScreen(language: String, onOpen: (SpeechScript) -> Unit, onBack: () -> Unit) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val challenges = remember { SpeechChallenges.shared(context) }
    val scripts by challenges.scripts.collectAsStateWithLifecycle()
    val standings by challenges.standings.collectAsStateWithLifecycle()
    LaunchedEffect(language) { challenges.refresh(language) }
    val live = scripts.filter { standings[it.id]?.retiredAt == null }
    val past = scripts.filter { standings[it.id]?.retiredAt != null }
    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.all_challenges)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            if (live.isNotEmpty()) {
                CardSection(stringResource(R.string.live)) {
                    live.forEach { script ->
                        SpeechChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                    }
                }
            }
            if (past.isNotEmpty()) {
                CardSection(stringResource(R.string.past_challenges),
                    footer = stringResource(R.string.ended_challenges_keep_their_final_standings)) {
                    past.forEach { script ->
                        SpeechChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                    }
                }
            }
        }
    }
}

/** A section of standalone cards: `FormSection`'s header and footer with no
 *  card around the rows, since each row is its own card. */
@Composable
private fun CardSection(header: String, footer: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 20.dp)) {
        Text(header, style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp, bottom = 2.dp))
        content()
        footer?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 1.dp))
        }
    }
}

// MARK: - The name on the boards

@Composable
internal fun SpeechChallengeNameSheet(suggested: String, onDismiss: (saved: Boolean) -> Unit) {
    val context = LocalContext.current
    var name by remember { mutableStateOf(SpeechChallenges.displayName(context) ?: suggested) }
    var showsPhoto by remember { mutableStateOf(SpeechChallenges.showsPhoto(context)) }
    val photo = remember { com.roro.futurevoice.data.AvatarStore.load(context) }
    val scope = rememberCoroutineScope()
    val clean = name.trim()
    // iOS: `.presentationDetents([.medium])` — a NavigationStack Form with
    // Cancel / Save in the toolbar, the field focused on appear.
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    SpeechSheet({ onDismiss(false) }, fullHeight = false, medium = true) {
        SheetHeader(stringResource(R.string.your_name_on_the_board),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = { onDismiss(false) }) },
            trailing = {
                IosGlassTextButton(stringResource(R.string.save), bold = true, enabled = clean.isNotEmpty(), onClick = {
                    SpeechChallenges.setDisplayName(context, clean)
                    SpeechChallenges.setShowsPhoto(context, showsPhoto)
                    val challenges = SpeechChallenges.shared(context)
                    scope.launch { challenges.saveProfile() }
                    onDismiss(true)
                })
            })
        FormSection(null, footer = stringResource(R.string.shown_beside_your_score_on_every_challenge_board)) {
            // A Form row: the face, then a plain TextField (no box) — iOS
            // `HStack(spacing: 12)`.
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SpeechChallengeFace(SpeechChallenges.Face(clean.ifEmpty { "?" }), 44.dp,
                    localBitmap = if (showsPhoto) photo else null)
                FormTextRow(name, { name = it.take(SpeechChallenges.MAX_NAME_LENGTH) },
                    stringResource(R.string.name),
                    capitalization = KeyboardCapitalization.Words, autoCorrect = false,
                    modifier = Modifier.weight(1f).focusRequester(focus))
            }
            if (photo != null) {
                FormDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.show_my_photo), modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    com.roro.futurevoice.ui.brand.IosSwitch(checked = showsPhoto, onCheckedChange = { showsPhoto = it })
                }
            }
        }
    }
}

// MARK: - On a take's result page

@Composable
internal fun SpeechChallengeEntrySection(entry: SpeechChallenges.Entry?, standing: SpeechChallenges.Standing?) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val accent = MaterialTheme.colorScheme.primary
    FormSection(stringResource(R.string.challenge)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            when (entry) {
                SpeechChallenges.Entry.Submitting -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.putting_it_on_the_board), color = secondary)
                }
                is SpeechChallenges.Entry.Entered -> {
                    val prev = entry.previousRank
                    when {
                        entry.improved && prev != null && entry.rank < prev -> EntryLine(Icons.Filled.ArrowCircleUp,
                            stringResource(R.string.up_to_lld_of_lld, entry.rank, entry.entrants), Color(0xFF34C759))
                        entry.improved && prev == null -> EntryLine(Icons.Filled.EmojiEvents,
                            stringResource(R.string.on_the_board_at_lld_of_lld, entry.rank, entry.entrants), accent)
                        entry.improved -> EntryLine(Icons.Filled.Star,
                            stringResource(R.string.new_best_lld_of_lld, entry.rank, entry.entrants), accent)
                        else -> {
                            EntryLine(Icons.Outlined.EmojiEvents,
                                stringResource(R.string.lld_of_lld_8e05fc, entry.rank, entry.entrants),
                                MaterialTheme.colorScheme.onSurface)
                            Text(stringResource(R.string.your_best_stays_at_lld, entry.best),
                                style = MaterialTheme.typography.bodyMedium, color = secondary)
                        }
                    }
                }
                SpeechChallenges.Entry.CameraOff -> EntryLine(Icons.Filled.VideocamOff,
                    stringResource(R.string.the_camera_was_off_so_this_take_isn_t_on_the_board), secondary, bold = false)
                SpeechChallenges.Entry.Failed -> EntryLine(Icons.Filled.Warning,
                    stringResource(R.string.this_take_couldn_t_reach_the_board), secondary, bold = false)
                null -> {
                    val rank = standing?.myRank
                    val best = standing?.myBest
                    if (rank != null && best != null) {
                        EntryLine(Icons.Outlined.EmojiEvents,
                            stringResource(R.string.your_best_on_the_board_lld_lld, best, rank),
                            MaterialTheme.colorScheme.onSurface, bold = false)
                    }
                }
            }
        }
    }
}

@Composable
private fun EntryLine(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, color: Color,
                      bold: Boolean = true) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, color = color, style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal)
    }
}

// MARK: - The moment a take moves up the board

/** The sheet a better take raises once, over its result — iOS
 *  `SpeechChallengeMomentSheet`. */
@Composable
internal fun SpeechChallengeMomentSheet(moment: SpeechChallenges.Moment, onSeeBoard: () -> Unit,
                                        onDismiss: () -> Unit) {
    val view = androidx.compose.ui.platform.LocalView.current
    LaunchedEffect(Unit) { view.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM) }
    val (icon, tint) = when (moment.kind) {
        SpeechChallenges.Moment.Kind.PODIUM -> Icons.Filled.EmojiEvents to when (moment.rank) {
            1 -> Color(0xFFFFCC00); 2 -> Color(0xFF8E8E93); else -> Color(0xFFA2845E)
        }
        SpeechChallenges.Moment.Kind.UP -> Icons.Filled.ArrowCircleUp to Color(0xFF34C759)
        SpeechChallenges.Moment.Kind.DEBUT -> Icons.Outlined.EmojiEvents to MaterialTheme.colorScheme.primary
    }
    val title = when (moment.kind) {
        SpeechChallenges.Moment.Kind.PODIUM ->
            if (moment.rank == 1) stringResource(R.string.you_re_1) else stringResource(R.string.you_re_lld, moment.rank)
        SpeechChallenges.Moment.Kind.UP -> stringResource(R.string.lld_lld_ffbaf7, moment.previousRank ?: moment.rank, moment.rank)
        SpeechChallenges.Moment.Kind.DEBUT -> stringResource(R.string.you_re_on_the_board)
    }
    val above = moment.above
    val below = moment.below
    val subtitle = when {
        moment.rank == 1 && below != null -> stringResource(R.string.ahead_of_2_by_lld, moment.score - below.score)
        moment.rank == 1 -> stringResource(R.string.the_top_score_of_lld_people, moment.entrants)
        moment.kind == SpeechChallenges.Moment.Kind.DEBUT -> stringResource(R.string.lld_of_lld_8e05fc, moment.rank, moment.entrants)
        above != null -> stringResource(R.string.lld_to_go_for_lld, maxOf(1, above.score - moment.score), above.rank)
        else -> stringResource(R.string.lld_of_lld_8e05fc, moment.rank, moment.entrants)
    }
    SpeechSheet(onDismiss, fullHeight = false) {
        Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(64.dp))
            Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyLarge)
        }
        Spacer(Modifier.size(16.dp))
        FormSection(null) {
            moment.neighbors.forEachIndexed { i, row ->
                if (i > 0) FormDivider()
                BoardRow(row)
            }
        }
        Spacer(Modifier.size(16.dp))
        IosButton(onClick = { onDismiss(); onSeeBoard() }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.see_the_leaderboard), fontWeight = FontWeight.SemiBold)
        }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
    }
}

/** Text with no font padding and a centred line box, for a glyph that must sit
 *  exactly in the middle of a small shape. */
private val TightText = androidx.compose.ui.text.TextStyle(
    platformStyle = androidx.compose.ui.text.PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
        alignment = androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center,
        trim = androidx.compose.ui.text.style.LineHeightStyle.Trim.Both),
)
