package com.roro.futurevoice.talk

/**
 * Which part of a drawn script column has been said — iOS
 * `SpeechVideoComposer.Column.lit`: everything above the line being read, and
 * that line up to where the reading has got. Plain numbers, so it is tested
 * off the device.
 */
object SpeechLit {
    data class Box(val left: Float, val top: Float, val right: Float, val bottom: Float)

    /**
     * @param words every word's box in column units, in reading order.
     * @param word every word before this one is said.
     * @param fraction how much of [word] itself is said.
     */
    fun boxes(words: List<Box>, columnWidth: Float, word: Int, fraction: Double): List<Box> {
        if (words.isEmpty() || (word <= 0 && fraction <= 0.0)) return emptyList()
        val index = minOf(word, words.size - 1)
        val part = if (word >= words.size) 1f else fraction.toFloat()
        val at = words[index]
        return listOf(
            Box(0f, 0f, columnWidth, at.top),
            Box(0f, at.top, at.left + (at.right - at.left) * part, at.bottom),
        )
    }
}
