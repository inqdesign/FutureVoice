package com.roro.futurevoice.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * The on-disk JSON contract shared with iOS's JSON-on-disk stores
 * (`SessionStore.swift` et al.): pretty-printed, dates as ISO-8601 UTC with
 * second precision (`2026-08-30T07:12:33Z` — Swift's `.iso8601` strategy),
 * absent optionals OMITTED rather than `null`, unknown keys ignored so a file
 * written by a newer build still loads.
 */
object StoreJson {
    val json: Json = Json {
        prettyPrint = true
        prettyPrintIndent = "  "
        ignoreUnknownKeys = true
        // A value this build doesn't know (an enum case a newer iOS or Android
        // build added, a null where a default stands) falls back to the
        // field's default instead of failing the whole file.
        coerceInputValues = true
        explicitNulls = false
        encodeDefaults = true
    }

    /** Swift's `Date.distantFuture`: the farthest date iOS writes, and the
     *  farthest it can READ back with `.iso8601` (`+292278994-…` fails). */
    const val DISTANT_FUTURE_MS = 64_092_211_200_000L
    const val DISTANT_FUTURE_ISO = "4001-01-01T00:00:00Z"

    /** iOS writes UUIDs uppercase; matching it keeps ids byte-identical across a backup. */
    fun newId(): String = UUID.randomUUID().toString().uppercase()
}

/** Epoch millis ↔ `2026-08-30T07:12:33Z`, the way Swift's `.iso8601` writes a `Date`. */
object IsoDateMillisSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("IsoDateMillis", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Long) {
        // Nothing past Swift's distantFuture is ever written: iOS can't read it.
        val ms = minOf(value, StoreJson.DISTANT_FUTURE_MS)
        encoder.encodeString(
            DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(ms).truncatedTo(ChronoUnit.SECONDS))
        )
    }

    override fun deserialize(decoder: Decoder): Long =
        Instant.parse(decoder.decodeString()).toEpochMilli()
}
