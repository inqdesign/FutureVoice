package com.roro.futurevoice.sync

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.security.MessageDigest

/**
 * The kinds of thing the sync carries — one per store, or per independently
 * merged PART of a store (VocabStore is nine files and nine rules). iOS
 * `SyncKind`: same names, same rules, so the two engines can be read side by
 * side. The raw value is written into every record, so renaming one is a
 * schema change.
 */
enum class SyncKind(val raw: String, val isLanguageScoped: Boolean, val isBlob: Boolean = false) {
    SESSION("session", true),
    DRILL("drill", true),
    VOCAB_RECORD("vocabRecord", true),
    VOCAB_EXPRESSION("vocabExpression", true),
    VOCAB_STUDYING("vocabStudying", true),
    VOCAB_STUDYING_EXPRESSION("vocabStudyingExpression", true),
    VOCAB_REMOVED_BY_HAND("vocabRemovedByHand", true),
    VOCAB_AUTO_KEPT("vocabAutoKept", true),
    VOCAB_INGESTED("vocabIngested", true),
    VOCAB_EXPRESSION_INGESTED("vocabExpressionIngested", true),
    SCHEDULE("schedule", true),
    SHADOW("shadow", true),
    // Android keeps saved lines at the root, not per language.
    SAVED_LINE("savedLine", false),
    SCENARIO("scenario", true),
    WEEKLY("weekly", true),
    WEEKLY_TEST("weeklyTest", true),
    SPEECH_SCRIPT("speechScript", true),
    SPEECH_TAKE("speechTake", true),
    PRACTICE_DAY("practiceDay", false),
    TALK_DAY("talkDay", false),
    USAGE_DAY("usageDay", false),
    PERSONA("persona", false),
    PERSONA_NOTE("personaNote", false),
    PROFILE("profile", false),
    COUNTERPART("counterpart", false),
    DEFAULTS("defaults", false),
    BLOB_TURN("blobTurn", false, isBlob = true),
    BLOB_RECORDING("blobRecording", false, isBlob = true),
    BLOB_VOICE_SAMPLE("blobVoiceSample", false, isBlob = true),
    BLOB_SPEECH_AUDIO("blobSpeechAudio", false, isBlob = true);

    companion object {
        fun of(raw: String): SyncKind? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * iOS `SyncSchema`: one app-wide version of "what a payload looks like". A
 * record from a newer build is applied if it decodes and FROZEN in the index
 * either way — never pushed back, never tombstoned.
 */
object SyncSchema { const val VERSION = 1 }

/** One record as the transport sees it — the only shape a Drive file is
 *  ever mapped to and from, so every rule above it is testable in memory. */
data class SyncRecord(
    val kind: SyncKind,
    val key: String,
    /** Language code for a scoped kind, null for a global one. */
    val lang: String?,
    /** Canonical JSON (`SyncCanonical`); null on a tombstone and on a blob. */
    val payload: String? = null,
    /** Local file to upload (push) or the downloaded temp file (fetch). */
    val asset: File? = null,
    val size: Long = 0,
    val schema: Int = SyncSchema.VERSION,
    /** When the DEVICE last changed this item — the LWW clock (epoch ms). */
    val modifiedAt: Long,
    val deletedAt: Long? = null,
    /** The server's handle for this record (Drive file id). */
    val serverId: String? = null,
) {
    val isTombstone: Boolean get() = deletedAt != null
    val recordName: String get() = recordName(kind, lang, key)

    companion object {
        /** Kind and language readable, the key hashed: a vocabulary key is a
         *  lemma in whatever script the learner studies. */
        fun recordName(kind: SyncKind, lang: String?, key: String): String =
            "${kind.raw}|${lang ?: ""}|${SyncCanonical.sha256(key).take(32)}"
    }
}

/** What `merge` is told about one side of an item. */
data class SyncSide(
    val payload: String?,
    /** Local: when the diff first saw this exact payload. Remote: the
     *  writer's `modifiedAt`. Tombstone: when it was deleted. */
    val at: Long,
    val deleted: Boolean,
)

data class SyncItem(val payload: String, val at: Long)

/**
 * The ONE encoding every synced payload is written and hashed in: sorted
 * keys, compact. A store's own serializer is never reused — its key order is
 * the class's field order, which a refactor may move, and the diff would
 * then re-push the whole library. Changing this is a one-off full re-push.
 */
object SyncCanonical {
    val json = Json { ignoreUnknownKeys = true; isLenient = true; encodeDefaults = true }

    fun canonical(e: JsonElement): String = buildString { write(e, this) }

    private fun write(e: JsonElement, out: StringBuilder) {
        when (e) {
            is JsonObject -> {
                out.append('{')
                e.keys.sorted().forEachIndexed { i, k ->
                    if (i > 0) out.append(',')
                    out.append(JsonPrimitive(k).toString()).append(':')
                    write(e.getValue(k), out)
                }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                e.forEachIndexed { i, v -> if (i > 0) out.append(','); write(v, out) }
                out.append(']')
            }
            JsonNull -> out.append("null")
            is JsonPrimitive -> out.append(e.toString())
        }
    }

    fun parse(s: String): JsonElement? = runCatching { json.parseToJsonElement(s) }.getOrNull()

    fun sha256(s: String): String = sha256(s.toByteArray())

    fun sha256(b: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    /** Fingerprint of a blob without reading it: audio is written once and
     *  never edited, so size + mtime identify the bytes. */
    fun blobFingerprint(size: Long, modifiedAtMs: Long): String = "$size:${modifiedAtMs / 1000}"
}

@Serializable
data class SyncIndexState(
    val changeToken: String? = null,
    val lastPullAt: Long? = null,
    val lastPushAt: Long? = null,
    val schema: Int = SyncSchema.VERSION,
)
