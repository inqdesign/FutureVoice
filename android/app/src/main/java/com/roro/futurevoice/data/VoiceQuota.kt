package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.R
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

/**
 * The account's monthly voice allowance (iOS `VoiceQuota`, 2026-10-10).
 *
 * The server answers `voice_quota_full` (a first voice can't be made: the
 * month is spent) or `voice_quota_reserved` (what is left is kept for first
 * voices), both with `available_at` = when the provider resets the allowance.
 * The date moves every month, so it is always the server's, never a constant.
 */
object VoiceQuota {
    /** Null = not a quota answer; a [Answer] whose [Answer.until] may be null
     *  when the server didn't say when. */
    data class Answer(val until: Long?)

    fun availableAt(body: String): Answer? {
        if (!body.contains("voice_quota_full") && !body.contains("voice_quota_reserved")) return null
        val raw = runCatching {
            (StoreJson.json.parseToJsonElement(body).jsonObject["available_at"] as? JsonPrimitive)?.contentOrNull
        }.getOrNull()
        return Answer(raw?.let { VoiceChangeStatus.parse(it) })
    }

    /** "Oct 12, 6:30 PM" in the app language and this phone's time zone,
     *  rounded UP to the next half hour so the moment named is never early.
     *  No year: the date is always within the month ahead. */
    fun `when`(context: Context, epochMs: Long): String {
        val half = 1_800_000L
        val rounded = ((epochMs + half - 1) / half) * half
        val locale = context.resources.configuration.locales[0]
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMdjmm")
        return java.text.SimpleDateFormat(pattern, locale).format(java.util.Date(rounded))
    }

    /** When a queued voice will be made (onboarding, Me → Voice). */
    fun readyLine(context: Context, until: Long?): String =
        if (until != null) context.getString(R.string.your_voice_will_be_ready_on, `when`(context, until))
        else context.getString(R.string.your_voice_will_be_ready_in_a_few_days)

    /** For a change (re-record, accent) refused while the allowance is spent. */
    fun pausedLine(context: Context, until: Long?): String =
        if (until != null) context.getString(
            R.string.new_voices_can_be_made_again_from_the_voice_you_have_keeps_w_412ed4, `when`(context, until))
        else context.getString(R.string.new_voices_can_be_made_again_in_a_few_days_the_voice_you_hav_81c7eb)
}

/** The monthly voice allowance refused a voice: a date, not a failure. */
class VoiceQuotaFull(val until: Long?) : Exception("voice_quota_full") {
    fun line(context: Context): String = VoiceQuota.pausedLine(context, until)

    companion object {
        fun from(body: String): VoiceQuotaFull? = VoiceQuota.availableAt(body)?.let { VoiceQuotaFull(it.until) }
    }
}
