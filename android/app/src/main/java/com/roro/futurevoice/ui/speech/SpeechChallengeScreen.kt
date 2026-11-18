package com.roro.futurevoice.ui.speech

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.icons.outlined.SmartDisplay
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.material.icons.filled.History
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Science
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
import androidx.compose.foundation.layout.wrapContentWidth
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
import androidx.compose.ui.res.pluralStringResource
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
import com.roro.futurevoice.ui.brand.CoreCubeBadge
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
            .heightIn(min = 220.dp)
            .clip(ContinuousShape(18.dp))
            .background(AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(18.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            // Out within the last week — whether or not this learner has
            // taken it. "New" rides on the trophy's corner, not in the rank's
            // slot: there it vanished the moment the learner had a record
            // (founder, 2026-10-18, as iOS). One word in every language — the
            // translations ran long and wrapped into a ball on large text.
            val isNew = script.createdAt > System.currentTimeMillis() - 7L * 86_400_000L
            Box {
                BookIconDisc(accent = accent) {
                    Icon(Icons.Filled.EmojiEvents, contentDescription = null, tint = accent,
                        modifier = Modifier.size(22.dp))
                }
                if (isNew) {
                    Text("New", style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1, softWrap = false,
                        modifier = Modifier.align(Alignment.BottomEnd).offset(x = 14.dp, y = 4.dp)
                            .wrapContentWidth(unbounded = true)
                            .clip(androidx.compose.foundation.shape.CircleShape)
                            .background(accent).padding(horizontal = 6.dp, vertical = 2.dp))
                }
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
        // The title hangs under the disc; the meta line belongs to the FOOT,
        // just above the faces, so it sits at the same height on every card
        // whatever the title's length. The slack goes between.
        // What kind of challenge it is (iOS SpeechChallengeCategory).
        val category = challengeCategoryLabel(standing?.category)
        if (category != null) {
            Text(category, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary, maxLines = 1,
                modifier = Modifier.padding(top = 14.dp))
        }
        Text(script.title, style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold, maxLines = 3, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = if (category != null) 2.dp else 14.dp))
        Spacer(Modifier.height(16.dp))
        Spacer(Modifier.weight(1f))
        val entrants = standing?.entrants ?: 0
        val tries = standing?.attempts
        val length = lengthLabel(SpeechLibrary.estimatedSeconds(script.body, script.language))
        // Tries, not people (iOS metaLine); a server without the count still
        // has the people. "0 tries" says the same thing as the foot, only sadder.
        val meta = when {
            tries != null -> if (tries > 0) pluralStringResource(R.plurals.speech_challenge_tries, tries, tries) + " · " + length else length
            entrants > 0 -> stringResource(R.string.lld_taking_part, entrants) + " · " + length
            else -> length
        }
        Text(meta, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(bottom = 8.dp))
        // The board's top three, or, on a board nobody is on yet, an
        // invitation in the same slot so every card ends alike.
        val faces = standing?.topThree.orEmpty()
        if (faces.isNotEmpty()) {
            SpeechChallengeFaces(faces, size = 30.dp)
        } else {
            Row(Modifier.height(30.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Flag, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
                Text(stringResource(R.string.be_the_first), style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
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
/**
 * A challenge's page (iOS `SpeechArenaDetail`, bf8c67cf — the speech app's
 * page, which nawana wears too): the picture across the top, edge to edge,
 * fading into the page; the kind, the title and my medal under it; what it
 * is; my best and the next medal; my frozen record from an earlier season; the
 * board; and the way in at the foot (my takes, the fluent reading as a mini
 * player, the start button). The fluent reading's opening fades in the first
 * time a challenge is opened.
 */
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
    val seasonRecords by challenges.seasonRecords.collectAsStateWithLifecycle()
    val script = scripts.firstOrNull { it.id == challengeId }
    val standing = standings[challengeId]
    /** Retired: the board is frozen and nobody can enter. */
    val isPast = standing?.retiredAt != null
    var board by remember { mutableStateOf<List<SpeechChallenges.BoardRow>?>(null) }
    var practicing by remember { mutableStateOf(false) }
    var naming by remember { mutableStateOf(false) }
    var startAfterNaming by remember { mutableStateOf(false) }
    var showingScript by remember { mutableStateOf(false) }
    var showingTakes by remember { mutableStateOf(false) }
    var showingMedals by remember { mutableStateOf(false) }
    val takes by SpeechStore.shared(context).takes.collectAsStateWithLifecycle()
    val takeCount = takes.count { it.scriptId == challengeId }
    val storeBest = takes.filter { it.scriptId == challengeId }.maxOfOrNull { it.metrics.overall }
    val best = listOfNotNull(standing?.myBest, storeBest).maxOrNull()
    var menu by remember { mutableStateOf(false) }
    var confirmRetire by remember { mutableStateOf(false) }
    var confirmWithdraw by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf(false) }
    /** The fluent reading's opening, fading in as the page opens. */
    val intro = remember { SpeechListenModel() }

    // The page's colours: the system's own, so it follows light or dark mode.
    val page = AppSurfaces.ground
    val card = AppSurfaces.card
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    val text = MaterialTheme.colorScheme.onSurface
    val faint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
    val cta = MaterialTheme.colorScheme.onSurface
    val ctaText = MaterialTheme.colorScheme.surface

    suspend fun reload() {
        challenges.board(challengeId)?.let { board = it }
    }
    // The boards load once the page is up.
    LaunchedEffect(challengeId) {
        shown = true
        kotlinx.coroutines.delay(350)
        reload()
    }
    // After the page has opened: a sound under a page still opening reads as
    // the tap making a noise. Only the first time this challenge is opened.
    LaunchedEffect(script?.id) {
        val s = script ?: return@LaunchedEffect
        if (!com.roro.futurevoice.talk.SpeechListenService.available(s)) return@LaunchedEffect
        kotlinx.coroutines.delay(600)
        intro.load(context, s)
        if (!practicing && !showingScript && !showingTakes && intro.phase == SpeechListenModel.Phase.READY &&
            IntroMemory.firstOpening(context, s.id)) intro.playIntro()
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { intro.fadeOut() } }
    LaunchedEffect(practicing) { if (practicing) intro.fadeToPause() }
    LaunchedEffect(showingTakes) { if (showingTakes) intro.fadeToPause() }

    // Nothing goes on a public board until the learner has seen the name.
    fun start() {
        // Practice on an ended challenge puts no name anywhere.
        if (!isPast && SpeechChallenges.displayName(context) == null) { startAfterNaming = true; naming = true }
        else practicing = true
    }

    val arrive = androidx.compose.animation.core.animateFloatAsState(if (shown) 1f else 0f,
        androidx.compose.animation.core.spring(dampingRatio = 0.9f, stiffness = 120f), label = "arrive").value

    Box(Modifier.fillMaxSize().background(page)) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 120.dp)) {
            if (script != null) {
                // The picture across the top, edge to edge and under the
                // status bar, on the card's ground; it bleeds into the page.
                val art = ChallengeArt.image(context, script.id)
                Box(Modifier.fillMaxWidth().height(480.dp).background(ChallengeArt.paper())) {
                    if (art != null) {
                        androidx.compose.foundation.Image(art.asImageBitmap(), null,
                            contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                            alignment = Alignment.TopCenter,
                            modifier = Modifier.fillMaxSize().padding(top = 36.dp))
                    }
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                        0.56f to page.copy(alpha = 0f), 0.64f to page.copy(alpha = 0.1f), 0.73f to page.copy(alpha = 0.3f),
                        0.82f to page.copy(alpha = 0.55f), 0.9f to page.copy(alpha = 0.8f), 0.96f to page.copy(alpha = 0.95f),
                        1f to page)))
                }
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    challengeCategoryLabel(standing?.category)?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = dim)
                    }
                    Text(script.title, style = arenaDisplay(32.sp), color = text, textAlign = TextAlign.Center,
                        maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 20.dp))
                    best?.let { b -> MedalTier.ofScore(b)?.let { tier ->
                        // Tap: how medals work.
                        Box(Modifier.padding(top = 4.dp).clip(CircleShape).clickable { showingMedals = true }) {
                            MedalBadge(tier, "$b", 52.dp)
                        }
                    } }
                }
                Column(Modifier.padding(horizontal = 16.dp).padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
                    // What it is.
                    Column(Modifier.arrives(arrive, 0), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        val introText = standing?.introFor(appLanguageCode())
                        if (introText != null) Text(introText, style = MaterialTheme.typography.bodyLarge, color = text)
                        else if (script.summary.isNotEmpty()) Text(script.summary, style = MaterialTheme.typography.bodyLarge, color = text)
                        val meta = buildList {
                            add(lengthLabel(com.roro.futurevoice.data.SpeechLibrary.estimatedSeconds(script.body, script.language)))
                            add(script.genre.title())
                            standing?.attempts?.takeIf { it > 0 }?.let { add(stringResource(R.string.arena_tries, it)) }
                        }
                        Text(meta.joinToString("  ·  "), style = MaterialTheme.typography.bodySmall, color = dim)
                        standing?.link?.let { link ->
                            Row(Modifier.clickable {
                                runCatching { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(link))) }
                            }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Outlined.SmartDisplay, null, tint = text, modifier = Modifier.size(20.dp))
                                Text(stringResource(R.string.arena_watch_original), fontWeight = FontWeight.SemiBold, color = text)
                            }
                        }
                    }
                    // Me: my best, the next medal, my place.
                    Column(Modifier.arrives(arrive, 1), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(card).padding(18.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Box(Modifier.clip(CircleShape).clickable { showingMedals = true }) {
                                MedalBadge(best?.let { MedalTier.ofScore(it) }, best?.toString().orEmpty(), 56.dp)
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(if (best != null) stringResource(R.string.arena_best, best) else stringResource(R.string.arena_not_tried),
                                    style = arenaDisplay(22.sp), color = text)
                                Text(nextMedal(best), style = MaterialTheme.typography.bodyMedium, color = dim)
                            }
                            standing?.myRank?.let { rank ->
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text("#$rank", style = arenaDisplay(22.sp), color = text)
                                    Text(stringResource(R.string.arena_of, standing.entrants.takeIf { it > 0 } ?: rank),
                                        style = MaterialTheme.typography.labelSmall, color = dim)
                                }
                            }
                        }
                        // A challenge back from an earlier season keeps my score there, frozen.
                        seasonRecords[challengeId.lowercase()]?.let { record ->
                            Text(stringResource(R.string.arena_season_record, record.season, record.score, record.rank, record.entrants),
                                style = MaterialTheme.typography.bodySmall, color = dim, modifier = Modifier.padding(horizontal = 18.dp))
                        }
                    }
                    // The board.
                    Column(Modifier.arrives(arrive, 3), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(R.string.leaderboard), style = arenaDisplay(24.sp), color = text)
                        val rows = board
                        when {
                            rows != null && rows.isEmpty() -> Text(stringResource(R.string.nobody_s_on_this_board_yet_be_the_first),
                                style = MaterialTheme.typography.bodyMedium, color = dim)
                            rows != null -> Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(card)) {
                                rows.forEach { row -> ArenaBoardLine(row, dim) }
                            }
                            else -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = dim)
                            }
                        }
                        Text(stringResource(if (isPast) R.string.this_challenge_has_ended_these_are_the_final_standings
                            else R.string.camera_on_takes_go_on_the_board_and_your_best_one_stands_the_eff4f3),
                            style = MaterialTheme.typography.bodySmall, color = faint)
                    }
                }
            }
        }

        // The way in.
        if (script != null) {
            Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().arrives(arrive, 4)
                .background(Brush.verticalGradient(0f to page.copy(alpha = 0f), 0.5f to page))
                .navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box {
                    Box(Modifier.size(52.dp).clip(CircleShape).background(card).clickable { showingTakes = true },
                        contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.History, stringResource(R.string.arena_takes), tint = text)
                    }
                    if (takeCount > 0) {
                        Text("$takeCount", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = ctaText,
                            modifier = Modifier.align(Alignment.TopEnd).background(cta, CircleShape).padding(horizontal = 5.dp, vertical = 1.dp))
                    }
                }
                // A mini player: the fluent reading's progress fills a ring
                // inside the button, and a tap opens the script with the
                // reading going on from where the intro paused.
                MiniReadingButton(intro, raised = card, track = MaterialTheme.colorScheme.outlineVariant) {
                    intro.playOn()
                    showingScript = true
                }
                Box(Modifier.weight(1f).height(52.dp).clip(CircleShape).background(cta).clickable { start() },
                    contentAlignment = Alignment.Center) {
                    Text(stringResource(when {
                        isPast -> R.string.arena_practice
                        best == null -> R.string.arena_take
                        else -> R.string.arena_again
                    }), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = ctaText)
                }
            }
        }

        // The page draws its own back and ⋯, solid, so they read on the
        // picture and on the page alike.
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            PageButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.arena_back), onBack)
            Spacer(Modifier.weight(1f))
            Box {
                PageButton(Icons.Filled.MoreHoriz, stringResource(R.string.arena_more)) { menu = true }
                IosDropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    IosDropdownMenuItem(text = { Text(stringResource(R.string.name_on_the_board)) },
                        leadingIcon = { Icon(Icons.Outlined.Badge, null) },
                        onClick = { menu = false; startAfterNaming = false; naming = true })
                    if (standing?.myBest != null) {
                        IosDropdownMenuItem(text = { Text(stringResource(R.string.arena_remove_me), color = Color(0xFFFF3B30)) },
                            leadingIcon = { Icon(Icons.Outlined.RemoveCircleOutline, null, tint = Color(0xFFFF3B30)) },
                            onClick = { menu = false; confirmWithdraw = true })
                    }
                    if (BillingGate.account?.unlimited == true && !isPast) {
                        IosDropdownMenuItem(text = { Text(stringResource(R.string.retire_challenge), color = Color(0xFFFF3B30)) },
                            leadingIcon = { Icon(Icons.Outlined.Archive, null, tint = Color(0xFFFF3B30)) },
                            onClick = { menu = false; confirmRetire = true })
                    }
                }
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
        SpeechScriptSheet(script, native, onEdited = {}, onDismiss = { showingScript = false }, reading = intro)
    }
    if (showingMedals) MedalGuideSheet(onDismiss = { showingMedals = false })
    if (showingTakes) {
        SpeechTakesPager(scriptId = challengeId, onDismiss = { showingTakes = false })
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
    if (confirmWithdraw) {
        AlertDialog(onDismissRequest = { confirmWithdraw = false },
            title = { Text(stringResource(R.string.arena_remove_confirm)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmWithdraw = false
                    scope.launch { runCatching { challenges.withdraw(challengeId) }; reload() }
                }) { Text(stringResource(R.string.arena_remove_me), color = Color(0xFFFF3B30)) }
            },
            dismissButton = { TextButton(onClick = { confirmWithdraw = false }) { Text(stringResource(R.string.cancel)) } })
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

/** Comes in after the hero: a short slide up and a fade, one step later per section. */
private fun Modifier.arrives(progress: Float, step: Int): Modifier {
    val p = ((progress * 1.4f) - step * 0.07f).coerceIn(0f, 1f)
    return this.graphicsLayer { alpha = p; translationY = (1 - p) * 26.dp.toPx() }
}

/** The next medal to win (iOS `nextMedal`). */
@Composable
private fun nextMedal(best: Int?): String {
    if (best == null) return stringResource(R.string.arena_gold_at_90)
    if (best >= 90) return stringResource(R.string.arena_gold_won)
    val next = MedalTier.entries.firstOrNull { it.bar > best } ?: return stringResource(R.string.arena_gold_at_90)
    return stringResource(when (next) {
        MedalTier.BRONZE -> R.string.arena_to_bronze
        MedalTier.SILVER -> R.string.arena_to_silver
        MedalTier.GOLD -> R.string.arena_to_gold
    }, next.bar - best)
}

/** A round button that belongs to the page: solid, no glass. */
@Composable
private fun PageButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.92f)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color(0.13f, 0.12f, 0.11f), modifier = Modifier.size(20.dp))
    }
}

/** One board line (iOS `boardLine`): the top three on medals. */
@Composable
private fun ArenaBoardLine(row: SpeechChallenges.BoardRow, dim: Color) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val tier = MedalTier.ofRank(row.rank)
        if (tier != null) MedalBadge(tier, "${row.rank}", 34.dp)
        else Text("${row.rank}", style = MaterialTheme.typography.bodyMedium, color = dim, textAlign = TextAlign.Center,
            modifier = Modifier.width(34.dp))
        SpeechChallengeFace(row.face, 34.dp)
        Text(row.display_name, fontWeight = if (row.is_me) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        // nawana's Core seat rides beside the name.
        row.core_theme?.let { CoreCubeBadge(it) }
        if (row.is_me) {
            Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                color = Color(0.86f, 0.71f, 0.4f))
        }
        Spacer(Modifier.weight(1f))
        Text("${row.score}", style = arenaDisplay(20.sp))
    }
}

/** One container at the foot: what the script is, then three buttons — your
 *  takes (the prompter's own clock-and-count, no label), Read the script,
 *  and the start button — iOS `actionBar` (2026-10-17). A past challenge
 *  keeps the takes and Read the script. iOS draws it in Liquid Glass; here a
 *  translucent card, so the board still shows through as it scrolls under. */
@Composable
private fun ChallengeActionBar(script: SpeechScript, intro: String?, link: String?, isPast: Boolean, hasBest: Boolean,
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
            // What the challenge is and what to keep in mind (iOS actionBar, 2026-11-04).
            if (intro != null) {
                Text(intro, style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(bottom = 4.dp))
            } else if (script.summary.isNotEmpty()) {
                Text(script.summary, style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            // The original, to watch before reading it (iOS, 2026-11-04).
            if (link != null) {
                val uriHandler = androidx.compose.ui.platform.LocalUriHandler.current
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.clickable { runCatching { uriHandler.openUri(link) } }
                        .padding(bottom = 4.dp)) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.watch_the_original), style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                }
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
                    Text("$takeCount", color = MaterialTheme.colorScheme.onPrimary, fontSize = 11.sp, lineHeight = 13.sp,
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
                FitButtonLabel(stringResource(R.string.script),
                    MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
            }
            IosButton(onClick = onStart, modifier = Modifier.weight(1f),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 12.dp)) {
                FitButtonLabel(stringResource(when {
                    isPast -> R.string.speech_challenge_practice
                    hasBest -> R.string.speech_challenge_again
                    else -> R.string.speech_challenge_take
                }), MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold))
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
internal fun BoardRow(row: SpeechChallenges.BoardRow) {
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
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(row.display_name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    fontWeight = if (row.is_me) FontWeight.SemiBold else FontWeight.Normal,
                    modifier = Modifier.weight(1f, fill = false))
                row.core_theme?.let { CoreCubeBadge(it) }
                if (row.is_me) {
                    Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = accent)
                }
            }
            row.challenges?.let { ChallengeCount(it) }
        }
        Text("${row.score}", fontWeight = FontWeight.SemiBold, color = boardScoreColor(row))
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
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(row.display_name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = if (row.rank == 1) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
                row.core_theme?.let { CoreCubeBadge(it, 18.dp) }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (row.is_me) {
                    Text(stringResource(R.string.you), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = accent)
                }
                row.challenges?.let { ChallengeCount(it) }
            }
        }
        Text("${row.score}", fontWeight = FontWeight.Bold, color = boardScoreColor(row),
            style = if (row.rank == 1) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.headlineSmall)
    }
}

/** A board line's score: a challenge's 0–100 take in the scale, an overall
 *  total (a sum) in plain text — iOS `SpeechScoreColor.board`. */
@Composable
private fun boardScoreColor(row: SpeechChallenges.BoardRow): Color =
    if (row.challenges == null) scoreColor(row.score) else MaterialTheme.colorScheme.onSurface

@Composable
private fun ChallengeCount(count: Int) {
    Text(pluralStringResource(R.plurals.speech_overall_challenges, count, count),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

// MARK: - Every challenge on one board

/** The overall ranking on the Speech tab (iOS `SpeechOverallBanner`): the top
 *  three drawn large, second · first · third like a podium; a tap opens the
 *  whole board. */
@Composable
internal fun SpeechOverallBanner(rows: List<SpeechChallenges.BoardRow>, onClick: () -> Unit) {
    val top = rows.take(3)
    val me = rows.firstOrNull { it.is_me }
    Column(
        Modifier.fillMaxWidth().clip(ContinuousShape(18.dp)).background(AppSurfaces.card)
            .clickable(onClick = onClick).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.EmojiEvents, contentDescription = null, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.speech_overall_ranking), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(20.dp))
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(1, 0, 2).forEach { i ->
                Box(Modifier.weight(1f), contentAlignment = Alignment.BottomCenter) {
                    top.getOrNull(i)?.let { OverallPlace(it) }
                }
            }
        }
        if (me != null && me.rank > 3) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.you), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Text("#${me.rank}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${me.score}", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun OverallPlace(row: SpeechChallenges.BoardRow) {
    val first = row.rank == 1
    val medal = when (row.rank) { 1 -> Color(0xFFFFCC00); 2 -> Color(0xFF8E8E93); else -> Color(0xFFA2845E) }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box {
            SpeechChallengeFace(row.face, if (first) 76.dp else 60.dp)
            Text("#${row.rank}", fontWeight = FontWeight.ExtraBold,
                style = TightText.copy(fontSize = 12.sp, lineHeight = 14.sp),
                color = if (first) Color.Black else Color.White,
                modifier = Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-4).dp)
                    .border(2.dp, AppSurfaces.card, RoundedCornerShape(50))
                    .background(medal, RoundedCornerShape(50))
                    .padding(horizontal = 6.dp, vertical = 2.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.display_name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = if (first) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f, fill = false))
            row.core_theme?.let { CoreCubeBadge(it) }
        }
        Text("${row.score}", fontWeight = FontWeight.Bold,
            style = if (first) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleLarge)
    }
}

/** The whole overall board: the top fifty and the learner's own row — iOS
 *  `SpeechOverallBoardView`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechOverallScreen(language: String, onBack: () -> Unit) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val challenges = remember { SpeechChallenges.shared(context) }
    val cached by challenges.overall.collectAsStateWithLifecycle()
    val overallSeason by challenges.overallSeason.collectAsStateWithLifecycle()
    val seasons by challenges.seasons.collectAsStateWithLifecycle()
    var rows by remember { mutableStateOf<List<SpeechChallenges.BoardRow>?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    /** Null until picked: the season the banner showed. */
    var pickedSeason by remember { mutableStateOf<Int?>(null) }
    val season = pickedSeason ?: overallSeason
    val isFinal = season?.let { challenges.seasonEnded(it, seasons) } ?: false
    val boardSeasons = challenges.boardSeasons(seasons)
    val scope = rememberCoroutineScope()
    suspend fun load() {
        // Opened before the challenge list has loaded: without the seasons the
        // board would fall back to Season 1's (iOS 01529ba7).
        if (season == null && challenges.seasons.value.isEmpty()) {
            challenges.refresh(language)
            if (challenges.overallSeason.value != null) return  // the change of season reloads
        }
        if (pickedSeason != null) rows = null
        challenges.overallBoard(language, season, limit = 50)?.let { rows = it }
    }
    LaunchedEffect(language, season) { load() }
    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.speech_overall_ranking)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; load(); refreshing = false } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
                if (boardSeasons.size > 1) {
                    val labels = boardSeasons.map { stringResource(R.string.speech_season, it) }
                    com.roro.futurevoice.ui.brand.IosSegmented(
                        options = labels,
                        selected = boardSeasons.indexOf(season).coerceAtLeast(0),
                        onSelect = { pickedSeason = boardSeasons[it] },
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                    )
                }
                FormSection(if (isFinal) stringResource(R.string.speech_final_standings) else null,
                    footer = stringResource(if (isFinal) R.string.speech_season_over else R.string.speech_overall_footer)) {
                    val shown = rows ?: (if (pickedSeason == null) cached else null)
                    if (shown == null) {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp))
                        }
                    } else {
                        var previous: Int? = null
                        shown.forEachIndexed { i, row ->
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
                }
            }
        }
    }
}

/** "Season N records" (iOS f1b76a39, `SpeechSeasonRecordsView`): the link
 *  opened All challenges, which held only Season 2's cards. English Season 1's
 *  challenges went live again in Season 2 on 2026-11-13, so nothing of that
 *  season is "past": its record is the frozen final standings and the
 *  learner's own frozen score on each challenge. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpeechSeasonRecordsScreen(language: String, season: Int,
                                       onOpen: (SpeechScript) -> Unit, onBack: () -> Unit) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val challenges = remember { SpeechChallenges.shared(context) }
    val scripts by challenges.scripts.collectAsStateWithLifecycle()
    val standings by challenges.standings.collectAsStateWithLifecycle()
    val seasonRecords by challenges.seasonRecords.collectAsStateWithLifecycle()
    var rows by remember { mutableStateOf<List<SpeechChallenges.BoardRow>?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        if (challenges.seasons.value.isEmpty()) challenges.refresh(language)
        rows = challenges.overallBoard(language, season, limit = 50) ?: rows ?: emptyList()
    }
    LaunchedEffect(language, season) { load() }
    // My frozen scores of this season, the best place first.
    val mine = seasonRecords.values
        .filter { it.season == season && challenges.script(it.challenge_id) != null }
        .sortedWith(compareBy<SpeechChallenges.SeasonRecord> { it.rank }.thenByDescending { it.score })
    // Challenges retired inside this season (none for English Season 1).
    val retired = scripts.filter { standings[it.id]?.retiredAt != null && standings[it.id]?.season == season }
    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.speech_season_records, season)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; load(); refreshing = false } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
                FormSection(stringResource(R.string.speech_final_standings),
                    footer = stringResource(R.string.speech_season_over)) {
                    val shown = rows
                    if (shown == null) {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp))
                        }
                    } else {
                        shown.forEachIndexed { i, row ->
                            if (i > 0) FormDivider()
                            BoardRow(row)
                        }
                    }
                }
                if (mine.isNotEmpty()) {
                    FormSection(stringResource(R.string.challenges)) {
                        mine.forEachIndexed { i, record ->
                            if (i > 0) FormDivider()
                            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(challenges.script(record.challenge_id)?.title.orEmpty(), maxLines = 1,
                                    overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.weight(1f))
                                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(stringResource(R.string.speech_rank_of, record.rank, record.entrants),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("${record.score}", style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold, color = scoreColor(record.score))
                                }
                            }
                        }
                    }
                }
                if (retired.isNotEmpty()) {
                    FormSection(null, footer = stringResource(R.string.ended_challenges_keep_their_final_standings)) {
                        retired.forEachIndexed { i, script ->
                            if (i > 0) FormDivider()
                            PastChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                        }
                    }
                }
            }
        }
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
    val seasons by challenges.seasons.collectAsStateWithLifecycle()
    LaunchedEffect(language) { challenges.refresh(language) }
    val live = scripts.filter { standings[it.id]?.retiredAt == null }
    val past = scripts.filter { standings[it.id]?.retiredAt != null }
    val openSeason = challenges.openSeason(seasons)
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
                CardSection(if (openSeason != null && openSeason >= 2) stringResource(R.string.speech_season_live, openSeason)
                    else stringResource(R.string.live)) {
                    live.forEach { script ->
                        SpeechChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                    }
                }
            }
            challenges.pastSeasons(scripts, standings).forEach { season ->
                FormSection(stringResource(R.string.speech_season_ended, season),
                    footer = stringResource(R.string.ended_challenges_keep_their_final_standings)) {
                    past.filter { standings[it.id]?.season == season }.forEachIndexed { i, script ->
                        if (i > 0) FormDivider()
                        PastChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                    }
                }
            }
            // Retired before seasons, or from a server without them.
            val unseasoned = past.filter { standings[it.id]?.season == null }
            if (unseasoned.isNotEmpty()) {
                CardSection(stringResource(R.string.past_challenges),
                    footer = stringResource(R.string.ended_challenges_keep_their_final_standings)) {
                    unseasoned.forEach { script ->
                        SpeechChallengeRow(script, standings[script.id], onClick = { onOpen(script) })
                    }
                }
            }
        }
    }
}

/** An ended challenge is a record: the title and where the reader finished. */
@Composable
private fun PastChallengeRow(script: SpeechScript, standing: SpeechChallenges.Standing?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(script.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
            Text(stringResource(R.string.speech_joined, standing?.entrants ?: 0), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val rank = standing?.myRank
        val best = standing?.myBest
        if (rank != null && best != null) {
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("#$rank", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("$best", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
                    color = scoreColor(best))
            }
        }
        FormChevron()
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
                SpeechChallenges.Entry.NewScoring -> EntryLine(Icons.Outlined.Science,
                    stringResource(R.string.speech_new_scoring_entry), secondary, bold = false)
                SpeechChallenges.Entry.Practice -> EntryLine(Icons.Filled.Mic,
                    stringResource(R.string.speech_practice_entry), secondary, bold = false)
                SpeechChallenges.Entry.Unfinished -> EntryLine(Icons.Filled.Mic,
                    stringResource(R.string.speech_unfinished_entry), secondary, bold = false)
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

/** A challenge's category key, named in the app language; an unknown key draws nothing. */
@Composable
internal fun challengeCategoryLabel(key: String?): String? = when (key) {
    "show_host" -> stringResource(R.string.speech_category_show_host)
    "famous_speech" -> stringResource(R.string.speech_category_famous_speech)
    "movie_scene" -> stringResource(R.string.speech_category_movie_scene)
    "film_review" -> stringResource(R.string.speech_category_film_review)
    "acceptance" -> stringResource(R.string.speech_category_acceptance)
    "product_launch" -> stringResource(R.string.speech_category_product_launch)
    "in_flight" -> stringResource(R.string.speech_category_in_flight)
    "podcast" -> stringResource(R.string.speech_category_podcast)
    "short_talk" -> stringResource(R.string.speech_category_short_talk)
    "wedding" -> stringResource(R.string.speech_category_wedding)
    else -> null
}

/** The app language as the intro map keys it ("ko", "zh-Hant", "zh-Hans", …). */
@Composable
internal fun appLanguageCode(): String {
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    if (locale.language != "zh") return locale.language
    return if (locale.script == "Hant" || locale.country in setOf("TW", "HK", "MO")) "zh-Hant" else "zh-Hans"
}
