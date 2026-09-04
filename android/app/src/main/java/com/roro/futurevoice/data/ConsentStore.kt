package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.Serializable
import java.io.File

/**
 * The legal gate that stands in front of the voice clone.
 *
 * It lives on ONE screen — the clone flow's consent act, between the narrative
 * and the mic — whose Next stays dead until the box is ticked. There is no age
 * screen of its own: a lone "how old are you?" in front of a language app
 * reads as a form to get past, while the same question beside "here is what
 * happens to your voice" reads as what it is.
 *
 * Two SEPARATE facts, deliberately not collapsed into one flag:
 *
 * - **Age.** ElevenLabs — the sub-processor that builds the voice model —
 *   forbids its Services to anyone under 13, and to 13–17-year-olds without a
 *   guardian's consent, and separately forbids passing them on under less
 *   restrictive terms. There is no in-app way to verify a real parent, so the
 *   minimum is 16: clear of the 13–17 band, and equal to the GDPR Art. 8 age
 *   of digital consent in Germany, where the seller is registered. What is
 *   stored is the declaration, never a birthday.
 * - **Voice.** A model built from someone's voice is biometric data — GDPR
 *   Art. 9 special category, Illinois BIPA "voiceprint", Korean PIPA sensitive
 *   information. All three want consent that is separate from the general
 *   terms, informed, and recorded. So it is its own toggle above its own
 *   plain-language disclosure, and the moment it was given is written down.
 *
 * Storage is the shared preferences under `futurevoice.consent.*` — the same
 * file [BackupService] carries and account deletion wipes — plus a JSON copy
 * in files, which is the retainable written record BIPA asks for and the thing
 * to hand over on a data-access request.
 */
object ConsentStore {

    /** See the type doc for why 16 and not 13 or 18 — a floor derived from the
     *  provider's terms, not a taste. */
    const val MINIMUM_AGE = 16

    /** Bumped when the policy changes materially enough to ask again. Stored
     *  beside each consent so an old record is identifiable rather than
     *  silently treated as current. */
    const val POLICY_VERSION = "2026-08-14"

    const val CONTACT_EMAIL = "hello.dearroroapp@gmail.com"

    private const val PREFS = "futurevoice"
    private const val AGE = "futurevoice.consent.ageConfirmedAt"
    private const val VOICE = "futurevoice.consent.voiceConsentAt"
    private const val POLICY = "futurevoice.consent.policyVersion"

    /**
     * The policy in a language the reader can actually read — a policy you
     * can't parse isn't disclosure. Follows the DEVICE language rather than
     * the app's chrome, same rule the paywall uses.
     */
    fun privacyUrl(): String {
        val korean = java.util.Locale.getDefault().language == "ko"
        return if (korean) "https://nawana.app/privacy-ko.html"
        else "https://nawana.app/privacy.html"
    }

    fun ageConfirmedAt(c: Context): Long? =
        c.getSharedPreferences(PREFS, 0).getLong(AGE, 0L).takeIf { it > 0 }

    fun voiceConsentAt(c: Context): Long? =
        c.getSharedPreferences(PREFS, 0).getLong(VOICE, 0L).takeIf { it > 0 }

    fun hasVoiceConsent(c: Context): Boolean = voiceConsentAt(c) != null

    /**
     * Record the age declaration and the voice consent, taken together on the
     * one screen that states both. A self-declaration, not a proof — which is
     * the honest description of any age check an app can make without
     * demanding ID, and GDPR Art. 8 asks for "reasonable efforts… taking into
     * consideration available technology" rather than certainty.
     *
     * There is no "no" to record: someone under the minimum leaves the box
     * unticked and Next never arms.
     */
    fun record(c: Context, now: Long = System.currentTimeMillis()) {
        val p = c.getSharedPreferences(PREFS, 0)
        val e = p.edit()
        if (p.getLong(AGE, 0L) <= 0) e.putLong(AGE, now)
        if (p.getLong(VOICE, 0L) <= 0) e.putLong(VOICE, now)
        e.putString(POLICY, POLICY_VERSION).apply()
        writeAuditRecord(c)
    }

    /**
     * Withdrawal has to be as easy as consent (GDPR Art. 7(3)). The caller is
     * responsible for actually deleting the voice model — this only forgets
     * the permission, which is what forces the clone flow to ask again.
     */
    fun withdrawVoiceConsent(c: Context) {
        c.getSharedPreferences(PREFS, 0).edit().remove(VOICE).apply()
        writeAuditRecord(c)
    }

    /** Forget everything. Called on account deletion — a warm age flag would
     *  wave the NEXT person who signs in on this phone straight past the gate. */
    fun reset(c: Context) {
        c.getSharedPreferences(PREFS, 0).edit()
            .remove(AGE).remove(VOICE).remove(POLICY).apply()
        runCatching { File(c.filesDir, "consent.json").delete() }
    }

    @Serializable
    private data class Record(
        val ageConfirmedAt: String?,
        val voiceConsentAt: String?,
        val minimumAge: Int,
        val policyVersion: String,
    )

    /**
     * A snapshot BIPA-style retention can point at, and the thing to export on
     * a subject-access request. Best-effort: the preferences above are what
     * the app actually reads, so a failed write never blocks a learner.
     */
    private fun writeAuditRecord(c: Context) {
        runCatching {
            val iso = { t: Long? ->
                t?.let {
                    java.time.format.DateTimeFormatter.ISO_INSTANT.format(
                        java.time.Instant.ofEpochMilli(it)
                            .truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
                }
            }
            val json = StoreJson.json.encodeToString(
                Record.serializer(),
                Record(iso(ageConfirmedAt(c)), iso(voiceConsentAt(c)),
                    MINIMUM_AGE, POLICY_VERSION))
            File(c.filesDir, "consent.json").writeText(json)
        }
    }
}
