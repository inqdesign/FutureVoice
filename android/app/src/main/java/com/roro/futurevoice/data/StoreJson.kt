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
        explicitNulls = false
        encodeDefaults = true
    }

    /** iOS writes UUIDs uppercase; matching it keeps ids byte-identical across a backup. */
    fun newId(): String = UUID.randomUUID().toString().uppercase()
}

/** Epoch millis ↔ `2026-08-30T07:12:33Z`, the way Swift's `.iso8601` writes a `Date`. */
object IsoDateMillisSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("IsoDateMillis", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Long) {
        encoder.encodeString(
            DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(value).truncatedTo(ChronoUnit.SECONDS))
        )
    }

    override fun deserialize(decoder: Decoder): Long =
        Instant.parse(decoder.decodeString()).toEpochMilli()
}
