package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.DrillCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * iOS `DrillCardEnrichment` — the same JSON shape, so a payload iOS left on a
 * card (`DrillCard.enrichment`) reads here and one written here reads there.
 */
@Serializable
data class DrillCardEnrichment(
    val examples: List<Example> = emptyList(),
    val variants: List<Variant> = emptyList(),
    val memoryHook: String = "",
    /** ISO-8601, as iOS's `.iso8601` date strategy writes it. */
    val generatedAt: String = "",
) {
    @Serializable data class Example(val situation: String = "", val sentence: String = "")
    @Serializable data class Variant(val phrase: String = "", val note: String = "")

    companion object {
        fun now(): String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()
    }
}

/**
 * On-disk cache for [DrillCardEnrichment], keyed by the PHRASE it explains —
 * `(target phrase, target language, native language)` — not by the card it
 * was opened from (iOS `DrillEnrichmentStore`). Files live under
 * `filesDir/DrillEnrichment/{sha256}.json`, iOS's `Documents/DrillEnrichment`.
 *
 * A card isn't a stable thing: a correction opened from a talk book may have
 * no card behind it, and a re-analysis clears untouched cards. Keyed by the
 * content, the same tap never pays twice, and the payload opens instantly the
 * second time instead of sitting on a spinner while it is written again.
 */
class DrillEnrichmentStore private constructor(context: Context) {
    private val dir = File(context.filesDir, "DrillEnrichment").apply { mkdirs() }

    suspend fun enrichment(phrase: String, targetLanguage: String, nativeLanguage: String): DrillCardEnrichment? =
        withContext(Dispatchers.IO) {
            val f = File(dir, "${key(phrase, targetLanguage, nativeLanguage)}.json")
            if (!f.exists()) return@withContext null
            runCatching { json.decodeFromString(DrillCardEnrichment.serializer(), f.readText()) }.getOrNull()
        }

    suspend fun save(value: DrillCardEnrichment, phrase: String, targetLanguage: String, nativeLanguage: String) =
        withContext(Dispatchers.IO) {
            runCatching {
                val f = File(dir, "${key(phrase, targetLanguage, nativeLanguage)}.json")
                val tmp = File(dir, "${f.name}.tmp")
                tmp.writeText(json.encodeToString(DrillCardEnrichment.serializer(), value))
                tmp.renameTo(f)
            }
            Unit
        }

    companion object {
        @Volatile private var instance: DrillEnrichmentStore? = null
        fun shared(context: Context): DrillEnrichmentStore =
            instance ?: synchronized(this) {
                instance ?: DrillEnrichmentStore(context.applicationContext).also { instance = it }
            }

        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        /** What a card carries (iOS writes it there too), read leniently. */
        fun fromCard(card: DrillCard): DrillCardEnrichment? = card.enrichment?.let { el ->
            runCatching { json.decodeFromJsonElement(DrillCardEnrichment.serializer(), el) }.getOrNull()
                ?.takeIf { it.examples.isNotEmpty() || it.variants.isNotEmpty() || it.memoryHook.isNotBlank() }
        }

        fun toJson(value: DrillCardEnrichment): JsonElement =
            json.encodeToJsonElement(DrillCardEnrichment.serializer(), value)

        /**
         * iOS `DrillEnrichmentStore.key` — byte for byte, since it is also the
         * request's idempotency key: a cache miss that races itself is billed
         * once. Casing and punctuation are normalized away.
         */
        fun key(phrase: String, targetLanguage: String, nativeLanguage: String): String {
            val seed = "$targetLanguage\n$nativeLanguage\n${normalized(phrase)}"
            return MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }

        /** `CharacterSet.alphanumerics ∪ .whitespaces`, lowercased, runs of
         *  whitespace collapsed to one space. */
        private fun normalized(text: String): String {
            val kept = StringBuilder()
            var i = 0
            while (i < text.length) {
                val cp = text.codePointAt(i)
                val type = Character.getType(cp)
                val alnum = Character.isLetterOrDigit(cp) ||
                    type == Character.NON_SPACING_MARK.toInt() ||
                    type == Character.COMBINING_SPACING_MARK.toInt() ||
                    type == Character.ENCLOSING_MARK.toInt() ||
                    type == Character.LETTER_NUMBER.toInt() ||
                    type == Character.OTHER_NUMBER.toInt()
                val space = cp == '\t'.code || type == Character.SPACE_SEPARATOR.toInt()
                if (alnum || space) kept.appendCodePoint(cp)
                i += Character.charCount(cp)
            }
            return kept.toString().lowercase()
                .map { if (it.isWhitespace()) ' ' else it }.joinToString("")
                .split(' ').filter { it.isNotEmpty() }.joinToString(" ")
        }
    }
}
