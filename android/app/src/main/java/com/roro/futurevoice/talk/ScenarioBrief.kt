package com.roro.futurevoice.talk

import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.StoreJson
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The learner's own material for a situation — a posting's link, a CV or
 * portfolio picked from Files, a photo of a letter — and the facts ONE reading
 * of it produced. iOS `ScenarioBrief` (`59c6481`), same `scenarios.json` keys.
 *
 * Two rules, and they are the design:
 *
 *  - **The file is never copied.** A picked document is read where it lives
 *    (Storage Access Framework, a persistable read grant) and the bytes go
 *    straight into the analysis request. Only its NAME and its content URI
 *    stay here, so "Read again" can open the same file, and a file that was
 *    moved or deleted asks to be picked again. Nothing lands in filesDir, in
 *    a backup, or in the usage ledger.
 *  - **Two sides, kept apart.** [counterpartFacts] and [likelyQuestions] are
 *    the OTHER side (the company, what they will ask) and ride into the
 *    counterpart block of every prompt; [learnerFacts] are the learner's own
 *    and ride on the learner's side. Mixing them is how a scene hands the
 *    learner's CV to the interviewer to recite.
 */
@Serializable
data class ScenarioBrief(
    val sources: List<Source> = emptyList(),
    /** One line naming what the material is about. Empty until read. */
    val summary: String = "",
    val counterpartFacts: List<String> = emptyList(),
    /** What the other side is likely to ask or say — a scene uses SOME. */
    val likelyQuestions: List<String> = emptyList(),
    val learnerFacts: List<String> = emptyList(),
    /** Reusable phrases the situation calls for; they lead the call's chips. */
    val keyExpressions: List<String> = emptyList(),
    /** When the sources were last read. null = attached, not read yet. */
    @Serializable(with = IsoDateMillisSerializer::class)
    val readAt: Long? = null,
) {
    @Serializable
    data class Source(
        val id: String = StoreJson.newId(),
        val kind: Kind,
        /** A link's URL, or a file's display name. */
        val label: String,
        /**
         * The picked document's `content://` URI, holding a persistable READ
         * grant — Android's equivalent of iOS's security-scoped bookmark.
         * Its own key, never iOS's `bookmark`: that one is base64 `Data`, and
         * a URI string there would fail the whole scenario's decode on iOS.
         */
        val androidUri: String? = null,
        /** False once a reading reported it could not open this source. */
        val readOK: Boolean = true,
        /** One short line the reading wrote about it ("job posting · Berlin"). */
        val detail: String? = null,
    )

    @Serializable
    enum class Kind {
        @SerialName("link") LINK,
        @SerialName("file") FILE,
        @SerialName("image") IMAGE,
    }

    val hasSources: Boolean get() = sources.isNotEmpty()
    val needsReading: Boolean get() = hasSources && readAt == null
    val hasContent: Boolean
        get() = counterpartFacts.isNotEmpty() || likelyQuestions.isNotEmpty() ||
            learnerFacts.isNotEmpty() || keyExpressions.isNotEmpty()
}
