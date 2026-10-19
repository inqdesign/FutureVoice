package com.roro.futurevoice.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.exponentialDecay
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Medication
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.ElectricBolt
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EscalatorWarning
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AvatarStore
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartCast
import com.roro.futurevoice.data.cast
import com.roro.futurevoice.data.isClose
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.Symbols
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Watch as a map of people (iOS `PeopleSky`, 7dbd60b4; on for everyone from
 * 1.1.8, fe83c0f1). The learner sits in the middle; everyone they could
 * practise with HANGS around them — still, never drifting — at a distance
 * that IS the relationship: family, partner and friends close, work and
 * neighbourhood further out, strangers at the edge. The map is bigger than
 * the screen and pans like a word cloud.
 *
 * The lens (All · My people · People I know · Strangers) is ONE choice in the
 * header. Every lens uses the same rings: a ring with nobody on it in that
 * lens folds away and the next ring moves in. Nobody changes angle — a person
 * who doesn't belong to the lens fades out where they stand.
 *
 * With the situation dock over it (iOS `PeopleSky.dockEnabled`, on in
 * release from 1.1.8, 418314a0): a person's card, their greeting bubble and
 * voice, and the situation box under the map — see [WatchTabBody].
 */
internal object PeopleSky {

    enum class Lens { ALL, MINE, KNOWN, STRANGERS }

    @Composable
    fun Lens.title(): String = when (this) {
        Lens.ALL -> stringResource(R.string.all)
        Lens.MINE -> stringResource(R.string.watch_sky_lens_mine)
        Lens.KNOWN -> stringResource(R.string.watch_sky_lens_known)
        Lens.STRANGERS -> stringResource(R.string.strangers)
    }

    /** One thing on the map. */
    data class Node(
        val id: String,
        val name: String,
        val person: Counterpart,
        /** Someone from the Find-people pool not met yet. */
        val pooled: Boolean,
        /** 0 close, 1 known, 2 stranger. */
        val ring: Int,
        /** The learner made this person. */
        val isMine: Boolean,
        /** Talks + scenes with them. Drives size and the "People I know" lens. */
        val practiced: Int,
        /** Has a situation the learner kept with them. */
        val hasKept: Boolean,
        /** What the face says when there is no photo (an SF Symbol name). */
        val symbol: String = "person.fill",
        /** The small line over the name. */
        val eyebrow: String? = null,
    ) {
        val isUnmet: Boolean get() = pooled

        fun shows(lens: Lens): Boolean = when (lens) {
            Lens.ALL -> true
            Lens.MINE -> isMine
            Lens.KNOWN -> practiced > 0
            Lens.STRANGERS -> !isMine && practiced == 0
        }

        val size: Float
            get() {
                if (isUnmet) return 64f
                return when (ring) {
                    0 -> 82f + min(practiced, 9) * 3f
                    1 -> 74f + min(practiced, 8) * 3f
                    else -> 68f + min(practiced, 4) * 3f
                }
            }
    }

    data class Seat(val row: Int, val index: Int, val size: Int)

    data class Geometry(
        val radii: List<Float>,
        /** Vertical stretch of the rings (1 = circles). */
        val sy: Float,
        val me: Float,
        /** Whether anyone in the lens sits on each ring. */
        val occupied: List<Boolean>,
        /** The outermost row's radius — how far the map has to reach. */
        val edge: Float,
        val seats: Map<String, Seat>,
    )

    /** Distance between the rows of one crowded ring. */
    const val BAND_STEP = 130f
    /** The arc one person needs along a row. */
    const val SEAT_WIDTH = 150f

    /**
     * The rings for a lens. Rings are SLOTS, filled from the inside: an empty
     * ring collapses onto the one inside it and the next ring with people
     * takes its place. A row holds only as many people as its circumference
     * has room for; the rest sit in a row behind it.
     */
    fun geometry(lens: Lens, nodes: List<Node>): Geometry {
        val counts = (0 until 3).map { r -> nodes.count { it.ring == r && it.shows(lens) } }
        val occupied = counts.map { it > 0 }
        val (slots, me) = when (lens) {
            Lens.MINE -> listOf(150f, 280f, 410f) to 100f
            Lens.KNOWN -> listOf(146f, 276f, 400f) to 96f
            else -> listOf(156f, 286f, 416f) to 104f
        }
        val radii = mutableListOf<Float>()
        val seats = mutableMapOf<String, Seat>()
        var inner = me / 2
        var slot = 0
        for (r in 0 until 3) {
            if (counts[r] == 0) { radii.add(inner); continue }
            var radius = slots[slot]
            if (slot > 0) radius = max(radius, inner + BAND_STEP)
            radii.add(radius)
            val list = nodes.filter { it.ring == r && it.shows(lens) }
            var start = 0
            var row = 0
            while (start < list.size) {
                val around = 2 * PI.toFloat() * (radius + row * BAND_STEP)
                val cap = max(3, (around / SEAT_WIDTH).toInt())
                val rowList = list.subList(start, min(start + cap, list.size))
                rowList.forEachIndexed { i, n -> seats[n.id] = Seat(row, i, rowList.size) }
                start += cap
                row += 1
            }
            inner = radius + max(row - 1, 0) * BAND_STEP
            slot += 1
        }
        return Geometry(radii, 1f, me, occupied, inner, seats)
    }

    fun side(nodes: List<Node>): Float = 2 * (max(geometry(Lens.ALL, nodes).edge, 416f) + 160f)

    /** A stable 0..<1 per id and salt — the map must not rearrange itself between visits. */
    private fun unit(s: String, salt: Long): Float {
        var h = 1469598103934665603uL + salt.toULong()
        for (b in s.toByteArray(Charsets.UTF_8)) {
            h = (h xor b.toUByte().toULong()) * 1099511628211uL
        }
        return (h % 10_000uL).toFloat() / 10_000f
    }

    /**
     * Where everyone sits under a lens: on their ring at their own angle, then
     * pushed apart until no two overlap. People outside the lens don't push;
     * they sit at their ring's new radius so they fade out in place.
     */
    fun solve(nodes: List<Node>, lens: Lens, side: Float): Map<String, Offset> {
        val g = geometry(lens, nodes)
        val c = Offset(side / 2, side / 2)
        val allSeats = geometry(Lens.ALL, nodes).seats
        fun home(n: Node): Offset {
            val b = g.seats[n.id] ?: allSeats[n.id] ?: Seat(0, 0, 1)
            // each row turned a little so rows interleave instead of lining up
            val start = -PI.toFloat() / 2 + n.ring * 0.55f + b.row * 0.37f
            val a = start + b.index * 2 * PI.toFloat() / max(b.size, 1) + (unit(n.id, 1) - 0.5f) * 0.3f
            val k = 1 + (unit(n.id, 2) - 0.5f) * 0.12f
            val r = (g.radii[n.ring] + b.row * BAND_STEP) * k
            return Offset(c.x + cos(a) * r, c.y + sin(a) * r * g.sy)
        }
        val visible = nodes.filter { it.shows(lens) }
        val xs = FloatArray(visible.size)
        val ys = FloatArray(visible.size)
        visible.forEachIndexed { i, n -> val p = home(n); xs[i] = p.x; ys[i] = p.y }
        val tx = xs.copyOf()
        val ty = ys.copyOf()
        val sizes = visible.map { it.size }
        repeat(200) {
            for (i in xs.indices) {
                // the learner, fixed at the centre
                var dx = xs[i] - c.x
                var dy = (ys[i] - c.y) * 0.85f
                var d = max(hypot(dx, dy), 0.01f)
                var minD = (g.me + sizes[i]) / 2 + 22
                if (d < minD) { xs[i] += dx / d * (minD - d); ys[i] += dy / d * (minD - d) }
                for (j in (i + 1) until xs.size) {
                    dx = xs[j] - xs[i]; dy = (ys[j] - ys[i]) * 0.85f
                    d = max(hypot(dx, dy), 0.01f)
                    // the eyebrow and name under a face are wider than the face
                    minD = (max(sizes[i], 120f) + max(sizes[j], 120f)) / 2 + 24
                    if (d < minD) {
                        val push = (minD - d) / 2
                        val ux = dx / d
                        val uy = dy / d
                        xs[i] -= ux * push; ys[i] -= uy * push
                        xs[j] += ux * push; ys[j] += uy * push
                    }
                }
            }
            for (i in xs.indices) {
                xs[i] += (tx[i] - xs[i]) * 0.05f
                ys[i] += (ty[i] - ys[i]) * 0.05f
            }
        }
        val out = mutableMapOf<String, Offset>()
        visible.forEachIndexed { i, n -> out[n.id] = Offset(xs[i], ys[i]) }
        for (n in nodes) if (n.id !in out) out[n.id] = home(n)
        return out
    }

    // MARK: - Faces

    /** The symbol drawn in place of initials: WHO this is to the learner. */
    fun symbol(c: Counterpart, occupation: String? = null): String {
        if (c.cast == CounterpartCast.PUBLIC_FIGURE) {
            val id = (c.publicIdentity ?: c.relationship).lowercase()
            return if (listOf("singer", "rapper", "music", "가수", "歌手", "sänger").any { id.contains(it) })
                "music.mic" else "star.fill"
        }
        if (c.cast == CounterpartCast.STRANGER) {
            // The profile silhouette means a REAL learner, and only that: a
            // learner without a photo wears it, and a character never does —
            // every character gets the icon of what they do.
            if (c.isRealLearner) return "person.fill"
            return jobSymbol(occupation ?: c.intro)
                ?: jobSymbol(c.intro) ?: "bubble.left.and.bubble.right.fill"
        }
        when (c.relationshipKind) {
            "Partner" -> return "heart.fill"
            "Family" -> return "house.fill"
            "Friend" -> return "person.2.fill"
            "Coworker", "Manager" -> return "briefcase.fill"
            "Fellow parent" -> return "figure.and.child.holdhands"
            "Neighbor" -> return "door.left.hand.open"
            "Teacher" -> return "graduationcap.fill"
        }
        // People made before the relationship chip: read the learner's own words.
        // Family words are checked LAST: "친구 엄마" names someone met through a friend.
        val r = c.relationship.lowercase()
        val byWords = listOf(
            listOf("wife", "husband", "partner", "girlfriend", "boyfriend", "아내", "남편", "애인", "여자친구", "남자친구") to "heart.fill",
            listOf("friend", "친구") to "person.2.fill",
            listOf("manager", "boss", "colleague", "coworker", "team", "상사", "팀장", "동료", "부장", "과장") to "briefcase.fill",
            listOf("landlord", "집주인") to "key.fill",
            listOf("neighbor", "neighbour", "이웃") to "door.left.hand.open",
            listOf("teacher", "coach", "선생님", "강사") to "graduationcap.fill",
            listOf("kita", "parent", "학부모") to "figure.and.child.holdhands",
            listOf("mom", "dad", "mother", "father", "sister", "brother", "엄마", "아빠", "어머니", "아버지", "누나", "언니", "형", "오빠", "동생", "family", "가족") to "house.fill",
        )
        return byWords.firstOrNull { (words, _) -> words.any { r.contains(it) } }?.second
            ?: jobSymbol(c.relationship) ?: "person.fill"
    }

    private fun jobSymbol(text: String): String? {
        val t = text.lowercase()
        val jobs = listOf(
            listOf("nurse", "간호", "看護", "pflege", "krankenschwester") to "cross.case.fill",
            listOf("pharmac", "약사", "薬剤", "apothek") to "pills.fill",
            listOf("barista", "cafe", "café", "바리스타", "카페") to "cup.and.saucer.fill",
            listOf("landlord", "vermieter", "중개", "집주인", "大家") to "key.fill",
            listOf("neighbor", "neighbour", "nachbar", "이웃", "隣") to "door.left.hand.open",
            listOf("elektriker", "electrician", "전기") to "bolt.fill",
            listOf("analyst", "data", "분석") to "chart.bar.fill",
            listOf("climb", "클라이밍", "kletter") to "figure.climbing",
            listOf("어머니", "어머님", "mother", "schwieger") to "house.fill",
            listOf("doctor", "physician", "의사", "医師", "arzt", "ärztin") to "stethoscope",
            listOf("design", "디자인", "デザイン") to "paintbrush.pointed.fill",
            listOf("chef", "cook", "요리", "料理", "koch") to "fork.knife",
            listOf("developer", "engineer", "programmer", "개발", "엔지니어", "エンジニア", "entwickler") to "laptopcomputer",
            listOf("teacher", "professor", "교사", "선생", "강사", "教師", "先生", "lehrer", "erzieher") to "graduationcap.fill",
            listOf("student", "학생", "学生", "studi", "ausbildung") to "book.fill",
            listOf("music", "singer", "musician", "음악", "가수", "音楽", "musik") to "music.note",
            listOf("photograph", "사진", "写真", "fotograf") to "camera.fill",
            listOf("writer", "author", "journalist", "작가", "기자", "作家", "autor") to "pencil",
            listOf("market", "sales", "마케팅", "영업", "営業") to "megaphone.fill",
            listOf("parent", "mom", "dad", "엄마", "아빠", "육아", "子育て") to "figure.and.child.holdhands",
            listOf("lead", "manager", "recruit", "선배", "회사", "team", "büro", "amt") to "briefcase.fill",
            listOf("moved", "holiday", "einbürgerung", "seit", "이주", "이민") to "airplane",
        )
        return jobs.firstOrNull { (words, _) -> words.any { t.contains(it) } }?.second
    }

    /** The glyph for one of the map's symbol names. */
    fun icon(symbol: String): ImageVector = when (symbol) {
        "person.fill" -> Icons.Filled.Person
        "heart.fill" -> Icons.Filled.Favorite
        "house.fill" -> Icons.Filled.Home
        "person.2.fill" -> Icons.Filled.People
        "figure.and.child.holdhands" -> Icons.Filled.EscalatorWarning
        "door.left.hand.open" -> Icons.Filled.MeetingRoom
        "graduationcap.fill" -> Icons.Filled.School
        "key.fill" -> Icons.Filled.Key
        "paintbrush.pointed.fill" -> Icons.Filled.Brush
        "laptopcomputer" -> Icons.Filled.Laptop
        "book.fill" -> Icons.AutoMirrored.Filled.MenuBook
        "music.note" -> Icons.Filled.MusicNote
        "camera.fill" -> Icons.Filled.CameraAlt
        "pencil" -> Icons.Filled.Edit
        "megaphone.fill" -> Icons.Filled.Campaign
        "music.mic" -> Icons.Filled.Mic
        "star.fill" -> Icons.Filled.Star
        "pills.fill" -> Icons.Filled.Medication
        "cup.and.saucer.fill" -> Icons.Filled.LocalCafe
        "bolt.fill" -> Icons.Filled.ElectricBolt
        "chart.bar.fill" -> Icons.Filled.BarChart
        "figure.climbing" -> Icons.Filled.Terrain
        "airplane" -> Icons.Filled.Flight
        "briefcase.fill" -> Icons.Filled.Work
        "cross.case.fill" -> Icons.Filled.LocalHospital
        "bubble.left.and.bubble.right.fill" -> Icons.Filled.Forum
        else -> Symbols.icon(symbol)
    }

    /**
     * A stable colour per person, so two friends with the same icon are still
     * two different faces. Indigo is the Core's and is never used. iOS's
     * system colours, light and dark.
     */
    fun faceColor(id: String, dark: Boolean): Color {
        val light = longArrayOf(0xFFFF3B30, 0xFFFF9500, 0xFF34C759, 0xFF00C7BE, 0xFF30B0C7,
            0xFF32ADE6, 0xFF007AFF, 0xFFAF52DE, 0xFFFF2D55, 0xFFA2845E)
        val night = longArrayOf(0xFFFF453A, 0xFFFF9F0A, 0xFF30D158, 0xFF63E6E2, 0xFF40C8E0,
            0xFF64D2FF, 0xFF0A84FF, 0xFFBF5AF2, 0xFFFF375F, 0xFFAC8E68)
        val palette = if (dark) night else light
        return Color(palette[(unit(id, 4) * palette.size).toInt() % palette.size])
    }

    /** Which ring someone belongs on. */
    fun ring(c: Counterpart): Int = when (c.cast) {
        CounterpartCast.PUBLIC_FIGURE, CounterpartCast.STRANGER -> 2
        CounterpartCast.OWN_PERSON -> if (c.isClose) 0 else 1
    }

    /**
     * Over the name on the map: the relationship in the learner's own words
     * for their people, the job (else the city) for a stranger, and who a
     * public figure is.
     */
    fun eyebrow(c: Counterpart, job: String?): String? = when (c.cast) {
        CounterpartCast.OWN_PERSON -> c.relationship
        CounterpartCast.PUBLIC_FIGURE -> c.publicIdentity?.split("·")?.last()?.trim()
        CounterpartCast.STRANGER -> {
            // a label, not a sentence: the job's first phrase, else the city
            fun short(text: String): String? {
                val head = text.split(',', '.', ';', '·', '(').firstOrNull()?.trim().orEmpty()
                return head.takeIf { it.length in 1..18 }
            }
            short(job.orEmpty()) ?: short(c.location)
        }
    }

    /** Where "the middle" is, as a share of the map's height. */
    const val FOCUS_LINE = 0.42f
}

/** Places a child with its centre at ([x], [y]) inside a top-start box. */
private fun Modifier.centerAt(x: Dp, y: Dp) = layout { m, _ ->
    val p = m.measure(Constraints())
    layout(p.width, p.height) {
        p.place(x.roundToPx() - p.width / 2, y.roundToPx() - p.height / 2)
    }
}

/** A pan the host asks for (a pick, a card). [nonce] re-asks for the same person. */
internal data class SkyScroll(val id: String, val nonce: Int)

/**
 * The map itself (iOS `PeopleSkyMap`): rings and their names under the
 * people, the learner in the middle, a 2-D pan with fling. With the situation
 * dock (iOS `PeopleSky.dockEnabled`, on for everyone from 1.1.8, 418314a0)
 * it also says who is in the middle of the screen ([onCenterChange]), rings
 * the one a situation is with ([focusedId]), puts a line over the one
 * speaking ([bubble]) and pans to whoever the host asks for ([scrollTarget]).
 * "Back to me" is drawn by the host, above the map's fade; the map reports
 * [onAwayChange] and comes back on [backToMeRequest].
 */
@Composable
internal fun PeopleSkyMap(
    nodes: List<PeopleSky.Node>,
    meName: String,
    lens: PeopleSky.Lens,
    onTap: (PeopleSky.Node) -> Unit,
    onTapMe: () -> Unit,
    modifier: Modifier = Modifier,
    /** Who the situation is with: ringed, a touch larger. Only a pick changes it — never a scroll. */
    focusedId: String? = null,
    /** Who is in the middle of the screen and says something. */
    bubbleId: String? = null,
    /** What they say while they are in the middle. */
    bubble: String? = null,
    /** The bubble answers: tapping it writes into the box. */
    onTapBubble: () -> Unit = {},
    /** Pan to this person. Scrolling by hand never sets it. */
    scrollTarget: SkyScroll? = null,
    /** Who is nearest the middle of the screen now (null: nobody close). */
    onCenterChange: (String?) -> Unit = {},
    /** Writing a situation: everyone but the one it's with goes soft. */
    softenOthers: Boolean = false,
    onAwayChange: (Boolean) -> Unit = {},
    backToMeRequest: Int = 0,
    /** A tap on the map between the people (they win their own taps). */
    onTapEmpty: () -> Unit = {},
) {
    val density = LocalDensity.current
    val side = remember(nodes) { PeopleSky.side(nodes) }
    val geometry = remember(nodes, lens) { PeopleSky.geometry(lens, nodes) }
    val positions = remember(nodes, lens, side) { PeopleSky.solve(nodes, lens, side) }
    // With the situation dock, a picked person must be able to come to the
    // middle wherever they sit — edge or bottom — with room for their bubble,
    // so the map can be dragged much further. Equal top and bottom, or the
    // centre anchor puts "me" off-centre.
    val marginX = 170f
    val marginY = 280f
    val contentW = side + 2 * marginX
    val contentH = side + 2 * marginY
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val centerChange by rememberUpdatedState(onCenterChange)
    val awayChange by rememberUpdatedState(onAwayChange)

    BoxWithConstraints(modifier.fillMaxSize()) {
        val viewW = with(density) { maxWidth.toPx() }
        val viewH = with(density) { maxHeight.toPx() }
        val cW = with(density) { contentW.dp.toPx() }
        val cH = with(density) { contentH.dp.toPx() }
        val maxX = max(0f, cW - viewW)
        val maxY = max(0f, cH - viewH)
        val sx = remember { Animatable(0f) }
        val sy = remember { Animatable(0f) }
        var moved by remember { mutableStateOf(false) }
        // Nobody is "in the middle" until the learner drags the map: opening
        // the tab, the pool landing and growing the map, a lens change or
        // "Back to me" all leave ME in focus, silent. Only a finger picks
        // someone (a tap still picks through its own path).
        var byHand by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()
        val marginXPx = with(density) { marginX.dp.toPx() }
        val marginYPx = with(density) { marginY.dp.toPx() }
        val focusY = viewH * PeopleSky.FOCUS_LINE

        /** The scroll offset that puts [id] on the focus line, a little above centre. */
        fun offsetFor(id: String): Offset? {
            val p = positions[id] ?: return null
            val px = with(density) { p.x.dp.toPx() } + marginXPx
            val py = with(density) { p.y.dp.toPx() } + marginYPx
            return Offset((px - viewW / 2).coerceIn(0f, maxX), (py - focusY).coerceIn(0f, maxY))
        }

        /** The scroll offset that puts ME on the focus line, so I am the one in the middle. */
        fun meOffset(): Offset {
            val c = side / 2
            val px = with(density) { c.dp.toPx() } + marginXPx
            val py = with(density) { (c + 8).dp.toPx() } + marginYPx
            return Offset((px - viewW / 2).coerceIn(0f, maxX), (py - focusY).coerceIn(0f, maxY))
        }

        // Starts on ME at the focus line; until the learner has moved it, a
        // map that grows stays on me. The pool can land after a pick and
        // grow the map: then it stays on them.
        LaunchedEffect(maxX, maxY) {
            sx.updateBounds(0f, maxX); sy.updateBounds(0f, maxY)
            val held = scrollTarget?.let { offsetFor(it.id) }
            if (held != null) { sx.snapTo(held.x); sy.snapTo(held.y) }
            else if (!moved) { val m = meOffset(); sx.snapTo(m.x); sy.snapTo(m.y) }
        }
        fun toCentre() {
            byHand = false
            val m = meOffset()
            scope.launch { sx.animateTo(m.x, tween(500)) }
            scope.launch { sy.animateTo(m.y, tween(500)) }
        }
        // A new lens brings the map back to the learner.
        var firstLens by remember { mutableStateOf(true) }
        LaunchedEffect(lens) { if (firstLens) firstLens = false else toCentre() }
        LaunchedEffect(backToMeRequest) { if (backToMeRequest > 0) toCentre() }
        // A pick pans to them, a little above centre: the box covers the
        // bottom of the map.
        LaunchedEffect(scrollTarget) {
            val target = scrollTarget?.let { offsetFor(it.id) } ?: return@LaunchedEffect
            moved = true
            launch { sx.animateTo(target.x, tween(500)) }
            launch { sy.animateTo(target.y, tween(500)) }
        }

        val awayPx = with(density) { 160.dp.toPx() }
        LaunchedEffect(viewW, viewH, cW, cH) {
            snapshotFlow {
                val cx = sx.value + viewW / 2 - cW / 2
                val cy = sy.value + viewH / 2 - cH / 2
                hypot(cx, cy) > awayPx
            }.distinctUntilChanged().collect { awayChange(it) }
        }

        // Who sits nearest the focus line as the map scrolls — once the
        // learner has dragged it. "Me" is a candidate too: when I am nearest,
        // nobody else is in the middle.
        val candidates = remember(nodes, lens) { nodes.filter { it.shows(lens) }.map { it.id } }
        LaunchedEffect(candidates, positions, viewW, viewH, side) {
            if (viewW <= 0f) return@LaunchedEffect
            val me = Offset(side / 2, side / 2 + 8)
            snapshotFlow {
                if (!byHand) return@snapshotFlow null
                val fx = with(density) { (sx.value + viewW / 2 - marginXPx).toDp().value }
                val fy = with(density) { (sy.value + focusY - marginYPx).toDp().value }
                var best: String? = null
                var bestD = Float.MAX_VALUE
                for (id in candidates) {
                    val p = positions[id] ?: continue
                    val d = hypot(p.x - fx, p.y - fy)
                    if (d < 130f && d < bestD) { best = id; bestD = d }
                }
                if (best != null && hypot(me.x - fx, me.y - fy) < bestD) null else best
            }.distinctUntilChanged().collect { centerChange(it) }
        }

        val reach = max(min(viewW, viewH) * 0.62f, 1f)

        Box(
            Modifier.fillMaxSize()
                .pointerInput(maxX, maxY) {
                    val tracker = VelocityTracker()
                    detectDragGestures(
                        onDragStart = {
                            moved = true
                            byHand = true
                            tracker.resetTracking()
                            scope.launch { sx.stop() }; scope.launch { sy.stop() }
                        },
                        onDragEnd = {
                            val v = tracker.calculateVelocity()
                            scope.launch { sx.animateDecay(-v.x, exponentialDecay()) }
                            scope.launch { sy.animateDecay(-v.y, exponentialDecay()) }
                        },
                    ) { change, drag ->
                        tracker.addPosition(change.uptimeMillis, change.position)
                        change.consume()
                        scope.launch { sx.snapTo((sx.value - drag.x).coerceIn(0f, maxX)) }
                        scope.launch { sy.snapTo((sy.value - drag.y).coerceIn(0f, maxY)) }
                    }
                }
                // The people are buttons and win their own taps; this only
                // hears the map between them.
                .pointerInput(Unit) { detectTapGestures(onTap = { onTapEmpty() }) }
        ) {
            Box(
                Modifier
                    .wrapContentSize(Alignment.TopStart, unbounded = true)
                    .requiredSize(contentW.dp, contentH.dp)
                    .graphicsLayer {
                        translationX = -sx.value
                        translationY = -sy.value
                    }
            ) {
                // The map proper, inside its margins.
                Box(Modifier.padding(start = marginX.dp, top = marginY.dp).requiredSize(side.dp)) {
                    val c = side / 2
                    // Background: the rings and their names sit UNDER the people.
                    val ringInk = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.22f)
                    val radii = (0 until 3).map { i ->
                        animateFloatAsState(geometry.radii[i], tween(500), label = "ring$i").value
                    }
                    val ringAlpha = (0 until 3).map { i ->
                        animateFloatAsState(if (geometry.occupied[i]) 1f else 0f, tween(500), label = "ringA$i").value
                    }
                    Canvas(Modifier.requiredSize(side.dp)) {
                        val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 6.dp.toPx()))
                        for (i in 0 until 3) {
                            if (ringAlpha[i] <= 0f) continue
                            drawCircle(ringInk.copy(alpha = ringInk.alpha * ringAlpha[i]),
                                radius = radii[i].dp.toPx(),
                                center = Offset(c.dp.toPx(), c.dp.toPx()),
                                style = Stroke(width = 1.dp.toPx(), pathEffect = dash))
                        }
                    }
                    val ringNames = listOf(
                        stringResource(R.string.watch_sky_ring_close),
                        stringResource(R.string.watch_sky_ring_known),
                        stringResource(R.string.strangers),
                    )
                    for (i in 0 until 3) {
                        Text(ringNames[i],
                            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                            color = MaterialTheme.colorScheme.outline,
                            modifier = Modifier
                                .centerAt(c.dp, (c + radii[i] * geometry.sy).dp)
                                .graphicsLayer { alpha = ringAlpha[i] }
                                .background(AppSurfaces.ground)
                                .padding(horizontal = 6.dp))
                    }

                    // The ringed one and the speaking one draw over their
                    // neighbours AND over "me" (iOS `zIndex(1)`; "me" sits at
                    // zIndex 0 after the rest), so a bubble below the middle
                    // is never covered by my face.
                    val front: (PeopleSky.Node) -> Boolean = { it.id == focusedId || it.id == bubbleId }
                    val ordered = nodes.sortedBy { if (front(it)) 1 else 0 }
                    var meDrawn = false
                    for (n in ordered) {
                        if (!meDrawn && front(n)) {
                            meDrawn = true
                            SkyMe(size = geometry.me, name = meName, onClick = onTapMe,
                                modifier = Modifier.centerAt(c.dp, (c + 8).dp))
                        }
                        androidx.compose.runtime.key(n.id) {
                            val on = n.shows(lens)
                            val focused = n.id == focusedId
                            val shown by animateFloatAsState(if (on) 1f else 0f, tween(500), label = "on")
                            val scale by animateFloatAsState(if (!on) 0.6f else if (focused) 1.12f else 1f,
                                tween(if (on) 350 else 500), label = "scale")
                            // Sharp at the height the bubble is triggered at, and
                            // the one speaking is never faded.
                            val sharp = if (softenOthers) focused else (n.id == bubbleId || focused)
                            val soft by animateFloatAsState(if (softenOthers && !sharp) 1f else 0f,
                                tween(350), label = "soft")
                            // A seat never glides: whatever moves it, it is simply there.
                            val p = positions[n.id] ?: Offset(c, c)
                            val px = with(density) { p.x.dp.toPx() } + marginXPx
                            val py = with(density) { p.y.dp.toPx() } + marginYPx
                            val speaking = n.id == (bubbleId ?: focusedId)
                            BubbleAnchor(
                                bubble = if (speaking) bubble else null,
                                onTapBubble = onTapBubble,
                                modifier = Modifier
                                    .centerAt(p.x.dp, p.y.dp)
                                    .graphicsLayer {
                                        alpha = shown
                                        scaleX = scale; scaleY = scale
                                    },
                            ) {
                                SkyNode(
                                    n, dark = dark,
                                    enabled = on,
                                    lit = n.id == bubbleId || focused,
                                    focused = focused,
                                    onClick = { onTap(n) },
                                    modifier = Modifier
                                        .then(if (soft > 0f) Modifier.blur((6 * soft).dp,
                                            BlurredEdgeTreatment.Unbounded) else Modifier)
                                        .graphicsLayer {
                                            // Like a word cloud: sharp across the middle
                                            // of the screen, fading past it. Fade only —
                                            // a shrink by distance made everyone squirm.
                                            val dx = px - sx.value - viewW / 2
                                            val dy = py - sy.value - focusY
                                            val t = min(hypot(dx, dy * 0.8f) / reach, 1.6f)
                                            val depth = if (sharp) 1f else max(0.3f, min(1f, 1.45f - 0.75f * t))
                                            alpha = depth * (1f - 0.45f * soft)
                                        },
                                )
                            }
                        }
                    }
                    if (!meDrawn) SkyMe(size = geometry.me, name = meName, onClick = onTapMe,
                        modifier = Modifier.centerAt(c.dp, (c + 8).dp))
                }
            }
        }
    }
}

/**
 * A node with its bubble hanging over it. The bubble is pinned by its TIP: it
 * sits 10 pt above the node's top and hangs off that point by its bottom
 * edge, so a longer line only grows upward. The node alone sets the size, so
 * the seat never moves when a line appears.
 */
@Composable
private fun BubbleAnchor(
    bubble: String?,
    onTapBubble: () -> Unit,
    modifier: Modifier = Modifier,
    node: @Composable () -> Unit,
) {
    val lift = with(LocalDensity.current) { 14.dp.roundToPx() }
    androidx.compose.ui.layout.Layout(
        content = {
            node()
            Box {
                AnimatedContent(
                    targetState = bubble,
                    transitionSpec = {
                        (fadeIn(tween(350)) + slideInVertically(tween(350)) { lift })
                            .togetherWith(fadeOut(tween(350)))
                    },
                    contentAlignment = Alignment.BottomCenter,
                    label = "bubble",
                ) { text ->
                    if (text != null) {
                        // 168 pt of text + 15 pt padding a side; a short line
                        // still hugs its words.
                        Box(Modifier.width(198.dp), contentAlignment = Alignment.BottomCenter) {
                            SkyBubble(text, onClick = onTapBubble)
                        }
                    }
                }
            }
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val nodeP = measurables[0].measure(Constraints())
        val bubbleP = measurables[1].measure(Constraints())
        layout(nodeP.width, nodeP.height) {
            nodeP.place(0, 0)
            bubbleP.place((nodeP.width - bubbleP.width) / 2, -bubbleP.height - 10.dp.roundToPx())
        }
    }
}

/** A picked person's line, over their face: a rounded bubble with a small tail. */
@Composable
internal fun SkyBubble(text: String, onClick: () -> Unit = {}) {
    val fill = MaterialTheme.colorScheme.surface
    Column(
        Modifier
            .shadow(10.dp, RoundedCornerShape(16.dp), clip = false,
                ambientColor = Color.Black.copy(alpha = 0.14f), spotColor = Color.Black.copy(alpha = 0.14f))
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(text,
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 4, overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .background(fill, com.roro.futurevoice.ui.brand.ContinuousShape(16.dp))
                .padding(horizontal = 15.dp, vertical = 11.dp))
        Canvas(Modifier.size(16.dp, 8.dp)) {
            val path = androidx.compose.ui.graphics.Path().apply {
                moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close()
            }
            drawPath(path, fill)
        }
    }
}

@Composable
private fun SkyMe(size: Float, name: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val revision by AvatarStore.revision.collectAsStateWithLifecycle()
    val avatar = remember(revision) { AvatarStore.load(context)?.asImageBitmap() }
    val accent = MaterialTheme.colorScheme.primary
    Column(
        modifier.clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.size(size.dp)
                .shadow(8.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.12f),
                    spotColor = Color.Black.copy(alpha = 0.12f))
                .clip(CircleShape)
                .background(AppSurfaces.card)
                .border(3.dp, accent, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (avatar != null) {
                Image(avatar, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(size.dp).clip(CircleShape))
            } else {
                Text(initials(name), fontSize = (size * 0.26f).sp, fontWeight = FontWeight.Bold,
                    color = accent)
            }
        }
        Text(stringResource(R.string.me), style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SkyNode(
    n: PeopleSky.Node,
    dark: Boolean,
    enabled: Boolean,
    /** In the middle and speaking (or picked): drawn in their colour even if
     *  not met yet — the quiet grey is for faces passing by. */
    lit: Boolean,
    /** Who the situation is with: an accent ring around the face. */
    focused: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val photo = rememberPersonPhoto(n.person.id)
    val label = listOfNotNull(n.name, n.eyebrow?.takeIf { it.isNotEmpty() }).joinToString(", ")
    val quiet = n.isUnmet && !lit
    val accent = MaterialTheme.colorScheme.primary
    Column(
        modifier
            .then(if (enabled) Modifier.clickable(remember { MutableInteractionSource() },
                indication = null, onClick = onClick) else Modifier)
            .semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            // An opaque face, so the rings and their names behind never show through.
            Box(Modifier.size(n.size.dp).clip(CircleShape).background(
                when {
                    photo != null -> Color.Transparent
                    quiet -> com.roro.futurevoice.ui.brand.iosFill().compositeOver(AppSurfaces.ground)
                    else -> PeopleSky.faceColor(n.id, dark)
                }), contentAlignment = Alignment.Center) {
                if (photo != null) {
                    Image(photo, contentDescription = null, contentScale = ContentScale.Crop,
                        modifier = Modifier.size(n.size.dp).clip(CircleShape))
                } else if (quiet) {
                    // someone not met yet is drawn quietly, so the learner's
                    // own people are the colour on the map
                    Icon(PeopleSky.icon(n.symbol), contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size((n.size * 0.36f).dp))
                } else {
                    Icon(PeopleSky.icon(n.symbol), contentDescription = null, tint = Color.White,
                        modifier = Modifier.size((n.size * 0.38f).dp))
                }
            }
            if (focused) {
                // The ring sits 4 pt outside the face, drawn without moving it.
                Canvas(Modifier.size(n.size.dp)) {
                    val w = 3.dp.toPx()
                    drawCircle(color = accent, radius = size.minDimension / 2 + 4.dp.toPx() - w / 2,
                        style = Stroke(width = w))
                }
            }
            if (n.hasKept) {
                Box(Modifier.size(12.dp).clip(CircleShape).background(AppSurfaces.ground)
                    .padding(2.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            n.eyebrow?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                    modifier = Modifier.width(116.dp))
            }
            Text(n.name, style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp),
                fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                modifier = Modifier.width(116.dp))
        }
    }
}

/** A published learner from the pool, not a character we wrote (iOS
 *  `Counterpart.isRealLearner`). Rows met before `personaKind` existed read
 *  as learners, the pool's default. */
internal val Counterpart.isRealLearner: Boolean
    get() {
        val r = remoteId ?: return false
        if (r.startsWith("builtin:")) return false
        return (personaKind ?: "user") == "user"
    }
