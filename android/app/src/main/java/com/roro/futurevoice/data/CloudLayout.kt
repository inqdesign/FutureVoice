package com.roro.futurevoice.data

import android.graphics.Paint
import android.graphics.Typeface
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Packs a set of words into wobbling rows on a large, roughly square canvas,
 * spacing neighbours by each word's real rendered width — so words never
 * collide. Order is hash-scattered (so sizes mix → depth), parallax depth
 * comes from a per-word hash layer.
 *
 * Straight port of `CloudLayout` in iOS's `VocabularyView.swift`. Two things
 * differ, both of them platform rather than design:
 *
 *  - **Everything is in PIXELS, not points.** iOS lays out in points and lets
 *    SwiftUI scale; Compose has no such unit for absolute placement, so the
 *    caller hands in the density and the font scale and gets a pixel canvas
 *    back. The arithmetic is otherwise identical — `sqrt(run * pitch)` is
 *    linear in the density, so the canvas comes out the same SHAPE whatever
 *    the screen.
 *  - **Widths come from `android.graphics.Paint`, not `UIFont`.** Paint is
 *    safe to build and measure off the main thread (a Compose `TextMeasurer`
 *    is not), which is what lets the whole pack run on `Dispatchers.Default`
 *    the way iOS runs it on a detached task. Paint measures the cloud's
 *    medium weight, so the gaps are never narrower than the drawn text.
 *
 * Deterministic by construction: the order, the wobble and the depth layer
 * are all FNV-1a hashes of the word itself, so the same word set on the same
 * screen always produces the same cloud.
 */
object CloudLayout {

    /** One packed word. [x]/[y] are the CENTRE, in canvas pixels. */
    data class Node(
        val word: String,
        val x: Float,
        val y: Float,
        /** Font size in sp — what the view draws it at. */
        val sizeSp: Float,
        /** 0.9 (far) … 1.1 (near). The parallax layer. */
        val depth: Float,
    )

    data class Cloud(
        val nodes: List<Node> = emptyList(),
        val width: Float = 0f,
        val height: Float = 0f,
    )

    /** A word and the size it should be drawn at, in sp. */
    data class Item(val word: String, val sizeSp: Float)

    /**
     * Gaps sized so the wobble below can never close them: horizontal wobble
     * (±8) stays under hGap, and row pitch leaves head-room for the tallest
     * (A1, 28sp) words plus vertical wobble (±12). In dp, as iOS has them in
     * points.
     */
    private const val H_GAP_DP = 34f
    private const val ROW_PITCH_DP = 72f
    private const val MIN_ROW_WIDTH_DP = 800f

    /**
     * @param density  `Density.density` — dp → px.
     * @param fontScale `Density.fontScale` — so a learner on large text gets
     *   gaps that still fit the words.
     */
    fun layout(items: List<Item>, density: Float, fontScale: Float): Cloud {
        if (items.isEmpty()) return Cloud()

        val hGap = H_GAP_DP * density
        val rowPitch = ROW_PITCH_DP * density

        val order = items.sortedWith { a, b ->
            java.lang.Long.compareUnsigned(hash(a.word), hash(b.word))
        }

        // One Paint per distinct size, exactly as iOS caches one UIFont per size.
        val paints = HashMap<Float, Paint>()
        fun width(word: String, sizeSp: Float): Float {
            val paint = paints.getOrPut(sizeSp) {
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = MEDIUM
                    textSize = sizeSp * density * fontScale
                }
            }
            return paint.measureText(word)
        }

        val widths = FloatArray(order.size) { width(order[it].word, order[it].sizeSp) }

        // Row width that makes the canvas roughly square, so panning feels the
        // same in every direction.
        var totalRun = 0f
        for (w in widths) totalRun += w
        totalRun += widths.size * hGap
        val rowWidth = max(MIN_ROW_WIDTH_DP * density, sqrt(totalRun * rowPitch))

        val nodes = ArrayList<Node>(order.size)
        var x = 0f
        var row = 0
        for (i in order.indices) {
            val e = order[i]
            val w = widths[i]
            if (x > 0f && x + w > rowWidth) { row++; x = 0f }
            // Small per-word wobble hides the row structure without being able
            // to close the gaps above.
            val cx = x + w / 2f + jitter(e.word, 0x9E3779B1L, 16f * density)
            val cy = row * rowPitch + rowPitch / 2f + jitter(e.word, 0x85EBCA77L, 24f * density)
            x += w + hGap
            // Per-word depth layer (hash-based) so parallax is visible even when
            // every word on screen is the same size (a single CEFR level).
            // Narrow band: enough for visible parallax, small enough that the
            // depth drift near the screen edges can't cross a row gap.
            val layer = java.lang.Long.remainderUnsigned(hash(e.word), 1000L) / 1000f
            nodes.add(Node(e.word, cx, cy, e.sizeSp, 0.9f + layer * 0.2f))
        }

        // Sorted by y so the view can binary-search the rows it can actually
        // see instead of sweeping all 8,000 nodes on every pan frame. iOS
        // scans the whole array; at this size Compose cannot afford to.
        nodes.sortBy { it.y }

        return Cloud(nodes = nodes, width = rowWidth, height = (row + 1) * rowPitch)
    }

    /**
     * The first node at or after [y]. The list is y-sorted, so a viewport is
     * one slice of it — see `CloudLayout.layout`.
     */
    fun firstIndexAtOrAfter(nodes: List<Node>, y: Float): Int {
        var lo = 0
        var hi = nodes.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (nodes[mid].y < y) lo = mid + 1 else hi = mid
        }
        return lo
    }

    private val MEDIUM: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)

    private fun hash(s: String): Long {
        var h = -0x340d631b7bdddcdbL          // 0xcbf29ce484222325
        for (b in s.toByteArray(Charsets.UTF_8)) {
            h = (h xor (b.toLong() and 0xFF)) * 0x100000001b3L
        }
        return h
    }

    private fun jitter(s: String, salt: Long, span: Float): Float {
        val h = hash(s) xor salt
        return (java.lang.Long.remainderUnsigned(h, 1000L) / 1000f - 0.5f) * span
    }
}
