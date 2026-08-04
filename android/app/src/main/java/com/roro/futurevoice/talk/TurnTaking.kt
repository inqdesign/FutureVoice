package com.roro.futurevoice.talk

/**
 * The three-tier end-of-turn threshold, measured against TRUE AUDIO SILENCE —
 * the same hybrid modern realtime voice stacks use: acoustic VAD picks the
 * endpoint, text completeness modulates how long to wait.
 *
 * These numbers are the contract (`docs/contracts/behavior.md` §2). A client
 * that picks its own is a different product. History worth keeping: under
 * TRANSCRIPT-quiet timing the avatar cut in during natural mid-thought breaths,
 * because the timer measured the recognizer, not the speaker. Energy-based
 * silence can't misfire on a breath (breaths are ~0.5–1.5s and unvoiced).
 */
object TurnTaking {

    /** They wrapped up cleanly — terminal punctuation. */
    const val VAD_SHORT_SECONDS = 1.2

    /** No clear signal either way. */
    const val VAD_DEFAULT_SECONDS = 2.2

    /**
     * Clearly mid-thought. Stays at 5s on purpose: it only fires on a hanging
     * conjunction or filler, where cutting in is exactly the failure mode this
     * whole scheme exists to avoid.
     */
    const val VAD_LONG_SECONDS = 5.0

    /** Don't send while the partial is still moving (STT lag is 0.3–0.5s). */
    const val STT_SETTLE_SECONDS = 0.7

    /** Monitor tick — worst-case added latency ≤ one tick. */
    const val ENDPOINT_TICK_SECONDS = 0.2

    /**
     * Noisy-room fallback: constant background noise can keep the energy meter
     * reading "voiced" forever. If the TRANSCRIPT has been still this long,
     * send regardless of energy.
     */
    const val NOISY_ROOM_FALLBACK_SECONDS = 6.0

    /** Warm the network path while the user is plausibly finished. */
    const val PRECONNECT_AFTER_SILENCE_SECONDS = 0.6

    private val fillerWords = setOf(
        "uh", "um", "er", "ah", "hmm", "mm", "well",
        "음", "어", "그", "그러니까", "에",
    )

    private val trailingConjunctions = setOf(
        "and", "but", "or", "so", "because", "cause",
        "if", "when", "while", "that", "which", "though", "although",
    )

    private val trailingFunctionWords = setOf(
        "the", "a", "an", "to", "in", "on", "at", "of",
        "for", "with", "by", "from", "into", "about",
    )

    /** Required TRUE-SILENCE duration for the transcript as it stands. */
    fun vadWaitSeconds(transcript: String): Double {
        val trimmed = transcript.trim()
        if (isLikelyIncomplete(trimmed)) return VAD_LONG_SECONDS
        val last = trimmed.lastOrNull()
        if (last != null && last in ".!?") return VAD_SHORT_SECONDS
        return VAD_DEFAULT_SECONDS
    }

    fun isLikelyIncomplete(text: String): Boolean {
        val trimmed = text.trim().lowercase()
        if (trimmed.isEmpty()) return true
        val words = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val last = words.lastOrNull() ?: return true
        // Very short transcripts are almost always still being formed.
        if (words.size <= 2 &&
            !last.endsWith("?") && !last.endsWith(".") && !last.endsWith("!")
        ) return true
        val stripped = last.trim { !it.isLetterOrDigit() && it != '\'' }
        return stripped in fillerWords ||
            stripped in trailingConjunctions ||
            stripped in trailingFunctionWords
    }
}
