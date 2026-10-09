package com.roro.futurevoice.talk

/**
 * Whether the correction call (`CorrectionOnlyPrompt`) may skip thinking.
 * Mirrors iOS `ConversationEngine.correctionThinksFast`: measured 2026-10-09
 * with `scripts/correction-probe.py` (THINKING=low vs minimal) — en, de, ja
 * identical on every count while thinking was ~half the call's cost; a Korean
 * target missed real errors without it, so Korean keeps thinking.
 */
object CorrectionThinking {
    fun fast(targetLanguage: String): Boolean =
        targetLanguage.substringBefore('-').lowercase() != "ko"
}
