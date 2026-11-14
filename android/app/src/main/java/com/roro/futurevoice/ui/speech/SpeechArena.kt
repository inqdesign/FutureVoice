package com.roro.futurevoice.ui.speech

import androidx.compose.material.icons.outlined.Description
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SpeechChallenges
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// The speech app's challenge cards, pictures and medals, which nawana's Speech
// tab wears too (iOS bf8c67cf, 2026-11-13, founder: one look in both apps).

/** A medal is a score, not a place (iOS `MedalTier`). */
enum class MedalTier(val bar: Int) {
    BRONZE(80), SILVER(85), GOLD(90);

    /** The metal (iOS `metal`). */
    val metal: Color get() = when (this) {
        GOLD -> Color(0.9f, 0.72f, 0.36f)
        SILVER -> Color(0.8f, 0.82f, 0.85f)
        BRONZE -> Color(0.74f, 0.48f, 0.33f)
    }

    companion object {
        fun ofScore(score: Int): MedalTier? = when {
            score >= 90 -> GOLD
            score >= 85 -> SILVER
            score >= 80 -> BRONZE
            else -> null
        }
        fun ofRank(rank: Int): MedalTier? = when (rank) { 1 -> GOLD; 2 -> SILVER; 3 -> BRONZE; else -> null }
    }
}

private fun Color.withBrightness(factor: Float): Color {
    val hsv = FloatArray(3)
    android.graphics.Color.colorToHSV(toArgb(), hsv)
    hsv[2] = (hsv[2] * factor).coerceIn(0f, 1f)
    return Color(android.graphics.Color.HSVToColor(hsv))
}

/**
 * A small medal (iOS `MedalBadge`): a struck medal, its number raised on a
 * frosted field inside a polished rim and a ring of beads, or an empty slot
 * still to win. iOS renders it as a SceneKit 3D still; here it is drawn flat
 * with the same finishes, as there is no SceneKit on Android.
 */
@Composable
internal fun MedalBadge(tier: MedalTier?, label: String = "", size: Dp = 44.dp, modifier: Modifier = Modifier) {
    if (tier == null) {
        // The empty slot follows the page (nawana's light pages too).
        val light = !com.roro.futurevoice.ui.appIsDark()
        Box(modifier.size(size), contentAlignment = Alignment.Center) {
            Box(Modifier.size(size * 0.78f).clip(CircleShape)
                .background(if (light) Color(0.9f, 0.9f, 0.9f) else Color(0.1f, 0.1f, 0.1f))
                .border(1.dp, if (light) Color.Black.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center) {
                androidx.compose.material3.Icon(Icons.Filled.Lock, null,
                    tint = if (light) Color.Black.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.35f),
                    modifier = Modifier.size(size * 0.3f))
            }
        }
        return
    }
    val polished = tier.metal.withBrightness(1.06f)
    val frosted = tier.metal.withBrightness(0.46f)
    val relief = tier.metal.withBrightness(1.2f)
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2 * 0.92f
        val c = Offset(this.size.width / 2, this.size.height / 2)
        // The shadow under it.
        drawCircle(Color.Black.copy(alpha = 0.3f), r * 1.02f, c + Offset(0f, r * 0.1f))
        // The polished rim, lit from the upper left.
        drawCircle(Brush.linearGradient(listOf(polished.withBrightness(1.15f), tier.metal, polished.withBrightness(0.7f)),
            start = c + Offset(-r, -r), end = c + Offset(r, r)), r, c)
        drawCircle(polished.withBrightness(0.8f), r * 0.99f, c, style = Stroke(r * 0.03f))
        // The frosted field.
        drawCircle(Brush.radialGradient(listOf(frosted.withBrightness(1.25f), frosted), center = c + Offset(-r * 0.3f, -r * 0.3f),
            radius = r * 1.2f), r * 0.84f, c)
        // A ring of beads just inside the rim.
        for (i in 0 until 44) {
            val a = i / 44.0 * 2 * Math.PI
            drawCircle(polished, r * 0.028f, c + Offset((cos(a) * r * 0.765).toFloat(), (sin(a) * r * 0.765).toFloat()))
        }
        // The raised number, fitted inside the field.
        if (label.isNotEmpty()) drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
                textAlign = android.graphics.Paint.Align.CENTER
                textSize = r
            }
            val bounds = android.graphics.Rect()
            paint.getTextBounds(label, 0, label.length, bounds)
            val scale = min(r * 1.18f / maxOf(1, bounds.width()), r * 0.92f / maxOf(1, bounds.height()))
            paint.textSize = r * scale
            paint.getTextBounds(label, 0, label.length, bounds)
            val y = c.y - bounds.exactCenterY()
            paint.color = frosted.withBrightness(0.6f).toArgb()
            canvas.nativeCanvas.drawText(label, c.x + r * 0.02f, y + r * 0.03f, paint)
            paint.color = relief.toArgb()
            canvas.nativeCanvas.drawText(label, c.x, y, paint)
        }
    }
}

/**
 * A challenge's picture (iOS `ChallengeArt`), drawn once in the
 * coloured-pencil style: served from R2 (`speech/pictures/<id>.png`), fetched
 * the first time its challenge is drawn, kept in the cache and checked again
 * (ETag) once per launch. The pictures the app was built with stay as the
 * fallback, by the last four of the id.
 */
internal object ChallengeArt {
    /** The cards are cream; in nawana's light mode they are white, like every
     *  other card there (the pictures are transparent). */
    @Composable
    fun paper(): Color = if (com.roro.futurevoice.ui.appIsDark()) CREAM else Color.White
    val CREAM = Color(251 / 255f, 248 / 255f, 240 / 255f)
    val INK_TEXT = Color(0.13f, 0.12f, 0.11f)

    private const val REMOTE_BASE = "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/speech/pictures"
    private val decoded = ConcurrentHashMap<String, Bitmap>()
    private val remote = ConcurrentHashMap<String, Bitmap>()
    private val checked = ConcurrentHashMap.newKeySet<String>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** Read by [image] so a view drawing a picture is drawn again when one arrives. */
    val arrivals = mutableIntStateOf(0)

    private fun cacheDir(context: Context) = File(context.cacheDir, "challenge_art").apply { mkdirs() }

    /** The picture: the downloaded one, else the one the app was built with. A
     *  picture not checked yet this launch is fetched behind it. */
    fun image(context: Context, id: String): Bitmap? {
        @Suppress("UNUSED_VARIABLE") val tick = arrivals.intValue
        val full = id.lowercase()
        val key = id.takeLast(4).uppercase()
        if (checked.add(full)) scope.launch { refresh(context.applicationContext, full) }
        remote[full]?.let { return it }
        cacheFile(context, full).takeIf { it.exists() }?.let { f ->
            BitmapFactory.decodeFile(f.path)?.let { remote[full] = it; return it }
        }
        decoded[key]?.let { return it }
        val bitmap = runCatching {
            context.assets.open("challenge_art/challenge-$key.png").use { BitmapFactory.decodeStream(it) }
        }.getOrNull() ?: return null
        decoded[key] = bitmap
        return bitmap
    }

    private fun cacheFile(context: Context, full: String) = File(cacheDir(context), "$full.png")

    /** Fetches one picture if R2 has a newer one than the cached copy. */
    private fun refresh(context: Context, full: String) {
        val file = cacheFile(context, full)
        val tagFile = File(cacheDir(context), "$full.etag")
        runCatching {
            val conn = (URL("$REMOTE_BASE/$full.png").openConnection() as HttpURLConnection).apply {
                connectTimeout = 20_000; readTimeout = 20_000
                useCaches = false
                if (file.exists() && tagFile.exists()) setRequestProperty("If-None-Match", tagFile.readText())
            }
            try {
                if (conn.responseCode != 200) return
                val data = conn.inputStream.use { it.readBytes() }
                val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return
                file.writeBytes(data)
                conn.getHeaderField("ETag")?.let { tagFile.writeText(it) }
                remote[full] = bitmap
                arrivals.intValue += 1
            } finally {
                conn.disconnect()
            }
        }
    }
}

/** The display face (iOS `Arena.display`: semibold serif). */
internal fun arenaDisplay(size: TextUnit) = androidx.compose.ui.text.TextStyle(
    fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = size)

/**
 * The face every challenge card shares (iOS `ChallengeCardFace`): its figure,
 * its kind and its title, on the card ground, and who is on it.
 */
@Composable
internal fun ChallengeCardFace(script: SpeechScript, category: String?, standing: SpeechChallenges.Standing?,
                               figureHeight: Dp? = null, titleSize: TextUnit = 17.sp, titleLines: Int = 2,
                               modifier: Modifier = Modifier,
                               /** One of the learner's own scripts (iOS 2026-11-13, founder: My
                                *  scripts wears the challenge cards): its kind drawn where a
                                *  challenge has its picture, and its length where a challenge
                                *  says who is on it. */
                               mine: Boolean = false) {
    val context = LocalContext.current
    val large = titleSize.value > 24
    val art = ChallengeArt.image(context, script.id)
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (large) 12.dp else 8.dp)) {
        if (art != null) {
            Image(art.asImageBitmap(), null, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxWidth().then(if (figureHeight != null) Modifier.height(figureHeight) else Modifier.weight(1f)))
        } else if (mine) {
            Box(Modifier.fillMaxWidth().then(if (figureHeight != null) Modifier.height(figureHeight) else Modifier.weight(1f)),
                contentAlignment = Alignment.Center) {
                androidx.compose.material3.Icon(script.genre.icon(), contentDescription = null,
                    tint = ChallengeArt.INK_TEXT.copy(alpha = 0.7f), modifier = Modifier.size(if (large) 84.dp else 52.dp))
            }
        } else {
            Spacer(if (figureHeight != null) Modifier.height(figureHeight) else Modifier.weight(1f))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (large) 6.dp else 3.dp)) {
            // The category as an eyebrow over the title. Every card keeps its
            // line, so titles stay level.
            val eyebrow = if (mine) {
                if (script.isBuiltIn) stringResource(R.string.sample) else script.genre.title()
            } else challengeCategoryLabel(category) ?: " "
            Text(eyebrow.uppercase(),
                style = (if (large) MaterialTheme.typography.labelMedium else MaterialTheme.typography.labelSmall)
                    .copy(letterSpacing = 0.6.sp),
                fontWeight = FontWeight.SemiBold, color = ChallengeArt.INK_TEXT.copy(alpha = 0.45f), maxLines = 1)
            // Every card keeps room for the longest title.
            Text(script.title, style = arenaDisplay(titleSize), color = ChallengeArt.INK_TEXT,
                textAlign = TextAlign.Center, maxLines = titleLines, overflow = TextOverflow.Ellipsis,
                minLines = titleLines, modifier = Modifier.fillMaxWidth())
        }
        if (mine) {
            Box(Modifier.height(if (large) 22.dp else 16.dp), contentAlignment = Alignment.Center) {
                Text(lengthLabel(com.roro.futurevoice.data.SpeechLibrary.estimatedSeconds(script.body, script.language)),
                    style = (if (large) MaterialTheme.typography.bodySmall else MaterialTheme.typography.labelSmall)
                        .copy(fontFeatureSettings = "tnum"),
                    color = ChallengeArt.INK_TEXT.copy(alpha = 0.5f), maxLines = 1)
            }
        } else {
            Crowd(standing, large)
        }
    }
}

/** Who is on it, quietly: the top three's faces and the count. */
@Composable
private fun Crowd(standing: SpeechChallenges.Standing?, large: Boolean) {
    val people = standing?.entrants ?: 0
    val faces = standing?.topThree.orEmpty().take(3)
    val size = if (large) 22.dp else 16.dp
    Row(Modifier.height(size), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (faces.isNotEmpty()) {
            Box(Modifier.width(size + size * 0.7f * (faces.size - 1))) {
                faces.reversed().forEachIndexed { i, face ->
                    val at = faces.size - 1 - i
                    CardLeaderFace(face, size, Modifier.offset(x = size * 0.7f * at))
                }
            }
        }
        Text(if (people > 0) stringResource(R.string.arena_taking_part, people) else stringResource(R.string.arena_be_first),
            style = if (large) MaterialTheme.typography.bodySmall else MaterialTheme.typography.labelSmall,
            color = ChallengeArt.INK_TEXT.copy(alpha = 0.5f), maxLines = 1)
    }
}

/** A leader's face on a card: their photo, or their initial. */
@Composable
private fun CardLeaderFace(face: SpeechChallenges.Face, size: Dp, modifier: Modifier = Modifier) {
    val bitmap = remember(face.avatar) { face.bitmap() }
    val paper = ChallengeArt.paper()
    Box(modifier.size(size).clip(CircleShape).border(1.5.dp, paper, CircleShape)
        .background(Color(0.90f, 0.87f, 0.80f)), contentAlignment = Alignment.Center) {
        if (bitmap != null) {
            Image(bitmap.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Text(face.display_name.firstOrNull()?.uppercase().orEmpty(), fontSize = (size.value * 0.5f).sp,
                fontWeight = FontWeight.SemiBold, color = ChallengeArt.INK_TEXT.copy(alpha = 0.6f))
        }
    }
}

/** One challenge in the grid (iOS `ArenaTile`): the figure filling the card,
 *  the title under it, and the medal I hold. */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun ArenaTile(script: SpeechScript, standing: SpeechChallenges.Standing?, best: Int?, ended: Boolean,
                       onClick: () -> Unit, modifier: Modifier = Modifier,
                       mine: Boolean = false, onLongClick: (() -> Unit)? = null) {
    Box(modifier.alpha(if (ended) 0.75f else 1f)) {
        ChallengeCardFace(script, standing?.category, standing, titleSize = 17.sp,
            modifier = Modifier.fillMaxWidth().aspectRatio(0.66f)
                .clip(RoundedCornerShape(30.dp)).background(ChallengeArt.paper())
                .combinedClickable(onClick = onClick, onLongClick = onLongClick)
                .padding(top = 20.dp, start = 10.dp, end = 10.dp, bottom = 14.dp),
            mine = mine)
        if (best != null) {
            val tier = MedalTier.ofScore(best)
            Box(Modifier.align(Alignment.TopEnd).padding(8.dp)) {
                if (tier != null) {
                    MedalBadge(tier, "$best", 34.dp)
                } else {
                    // A score short of a medal is a disc the medal's size, in
                    // the medal's place.
                    Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(30.dp).background(ChallengeArt.INK_TEXT.copy(alpha = 0.6f), CircleShape),
                            contentAlignment = Alignment.Center) {
                            Text("$best", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                                color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

/** How medals work (iOS `MedalGuideSheet`): a medal is your own best score, so
 *  anyone can win gold; the rank is the board, and the two are separate. */
@Composable
internal fun MedalGuideSheet(onDismiss: () -> Unit) {
    SpeechSheet(onDismiss, medium = true) {
        SheetHeader(stringResource(R.string.arena_how_medals_work),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            FormSection(null, footer = stringResource(R.string.arena_medal_footer)) {
                MedalTier.entries.forEachIndexed { i, tier ->
                    if (i > 0) FormDivider()
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        MedalBadge(tier, "${tier.bar}", 40.dp)
                        Text(stringResource(when (tier) {
                            MedalTier.BRONZE -> R.string.arena_bronze
                            MedalTier.SILVER -> R.string.arena_silver
                            MedalTier.GOLD -> R.string.arena_gold
                        }), modifier = Modifier.weight(1f))
                        Text("${tier.bar}+", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            FormSection(stringResource(R.string.arena_rank)) {
                Text(stringResource(R.string.arena_rank_body), color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp))
            }
        }
    }
}

/** Which challenges have played their intro on this phone: it plays on the
 *  first opening only (iOS `IntroMemory`). */
internal object IntroMemory {
    private const val KEY = "speech.introHeard"

    /** True once per challenge: the first call records it. */
    fun firstOpening(context: Context, id: String): Boolean {
        val prefs = context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
        val heard = prefs.getStringSet(KEY, emptySet())!!.toMutableSet()
        if (!heard.add(id.uppercase())) return false
        prefs.edit().putStringSet(KEY, heard).apply()
        return true
    }
}

/** The page's fluent reading as a mini player (iOS `MiniReadingButton`): its
 *  progress fills a ring inside the button, and a tap opens the script with
 *  the reading playing on in it. */
@Composable
internal fun MiniReadingButton(model: SpeechListenModel, raised: Color, track: Color, open: () -> Unit) {
    val ready = model.phase == SpeechListenModel.Phase.READY
    val accent = Color(0.93f, 0.45f, 0.3f)
    val progress = model.progress.toFloat()
    Box(Modifier.size(52.dp).clip(CircleShape).background(raised).clickable(onClick = open)
        .drawBehind {
            if (!ready) return@drawBehind
            val inset = 4.dp.toPx() + 1.25.dp.toPx()
            val stroke = 2.5.dp.toPx()
            val box = androidx.compose.ui.geometry.Size(size.width - inset * 2, size.height - inset * 2)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), box, style = Stroke(stroke))
            drawArc(accent, -90f, 360f * progress, false, Offset(inset, inset), box,
                style = Stroke(stroke, cap = androidx.compose.ui.graphics.StrokeCap.Round))
        }, contentAlignment = Alignment.Center) {
        androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Outlined.Description,
            stringResource(R.string.arena_script), modifier = Modifier.size(22.dp))
    }
}
