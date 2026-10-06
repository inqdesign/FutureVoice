package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.ElevenLabsClient

/**
 * Say a line in a voice, paying for it at most once — the one door every
 * repeatable spoken line goes through (word cards, drills, shadow targets,
 * library rows, scene lines).
 *
 * The cache ([PhraseAudioStore]) is asked first; only genuinely new text
 * reaches ElevenLabs, and what comes back is kept. A surface that calls the
 * client directly re-bills the learner for audio they already own.
 */
suspend fun cachedSynthesis(
    context: Context,
    voiceId: String,
    text: String,
    modelId: String = ElevenLabsClient.CONVERSATION_MODEL_ID,
    purpose: String? = null,
    sceneKey: String? = null,
    idempotencyKey: String? = null,
    /** False for anything that must be heard in the voice speaking NOW (a
     *  voice preview): no fallback to a take an older voice made. */
    allowLineage: Boolean = true,
): ByteArray {
    // DEBUG only: a staged 402 for the next line, ahead of the cache so a
    // replay of owned audio can still stage the wall (see [DebugBilling]).
    DebugBilling.consume402()?.let { throw it }
    val store = PhraseAudioStore.shared(context)
    store.data(text, voiceId, allowLineage)?.let { return it }
    val audio = ElevenLabsClient(AuthRepository()).synthesize(
        voiceId = voiceId, text = text, modelId = modelId,
        idempotencyKey = idempotencyKey, purpose = purpose, sceneKey = sceneKey)
    store.save(audio, text, voiceId)
    return audio
}
