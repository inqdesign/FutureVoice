package com.roro.futurevoice.data

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * How one side of a relationship speaks to the other (iOS `SpeechRegister`,
 * `ede039e`) — an abstract rung that each target language renders its own
 * way (반말 / du / tu, 해요체 / Sie / vous). Abstract because a person is
 * shared by every language the learner practises: "we talk casually" is true
 * of the friendship, and Korean and German only differ in what that sounds
 * like. English has no grammatical form of address, so there the rung is TONE.
 */
enum class SpeechRegister(val raw: String) {
    CASUAL("casual"), POLITE("polite"), FORMAL("formal");

    /**
     * What the rung is CALLED in the target language, where the language has
     * a name for it (반말, du, tu). null where the language has no grammatical
     * form of address — the rung is tone only there.
     */
    fun term(language: String): String? = when (language.substringBefore('-')) {
        "ko" -> listOf("반말", "해요체", "합니다체")[ordinal]
        "ja" -> listOf("タメ口", "です・ます", "敬語")[ordinal]
        "de" -> listOf("du", "Sie", "Sie")[ordinal]
        "fr" -> listOf("tu", "vous", "vous")[ordinal]
        "es" -> listOf("tú", "usted", "usted")[ordinal]
        "it" -> listOf("tu", "Lei", "Lei")[ordinal]
        else -> null
    }

    /** The rung as a prompt line names it: the form, its endings, its tone. */
    fun promptDescription(language: String): String = when (language.substringBefore('-')) {
        "ko" -> listOf(
            "반말 (the informal speech level: -어/-아, -야 endings, never -요) and the loose, easy tone that goes with it",
            "해요체 (the polite speech level: -요 endings)",
            "합니다체 (the formal speech level: -습니다 / -ㅂ니까 endings)",
        )[ordinal]
        "ja" -> listOf(
            "plain form, タメ口 (never です/ます) and the loose, easy tone that goes with it",
            "です・ます form",
            "keigo — 尊敬語 for the other person, 謙譲語 for yourself",
        )[ordinal]
        "de", "fr", "es", "it" -> {
            val form = term(language).orEmpty()
            listOf(
                "$form (informal address) and the loose, easy tone that goes with it",
                "$form (formal address), friendly",
                "$form (formal address) in a formal, professional register",
            )[ordinal]
        }
        else -> listOf(
            "casual — the way close friends talk: contractions, slang, teasing welcome",
            "friendly but polite — the way you'd talk to a colleague or an acquaintance",
            "formal and professional",
        )[ordinal]
    }

    companion object {
        fun from(raw: String?): SpeechRegister? = entries.firstOrNull { it.raw == raw }

        /**
         * True where the target language marks the form of address in
         * grammar, so a line can be said in the WRONG one — the only case a
         * correction may touch it.
         */
        fun hasForms(language: String): Boolean = CASUAL.term(language) != null
    }
}

/**
 * A rung this build doesn't know (a newer build's) reads as "not set" rather
 * than failing the whole person — iOS decodes it with `try?` for the same
 * reason.
 */
object LenientSpeechRegisterSerializer : KSerializer<SpeechRegister?> {
    @OptIn(ExperimentalSerializationApi::class)
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("SpeechRegister", PrimitiveKind.STRING).nullable

    @OptIn(ExperimentalSerializationApi::class)
    override fun serialize(encoder: Encoder, value: SpeechRegister?) {
        if (value == null) encoder.encodeNull() else encoder.encodeString(value.raw)
    }

    @OptIn(ExperimentalSerializationApi::class)
    override fun deserialize(decoder: Decoder): SpeechRegister? =
        if (decoder.decodeNotNullMark()) SpeechRegister.from(decoder.decodeString())
        else decoder.decodeNull()
}

/**
 * Which of the app's three kinds of person this is (iOS `Counterpart.Cast`) —
 * each gets its own character block in a call, because they stand in three
 * different relations to the learner.
 */
enum class CounterpartCast {
    /** Someone from the learner's own life, made by them. They KNOW each other. */
    OWN_PERSON,
    /** A persona from the Find-people pool. A new acquaintance. */
    STRANGER,
    /** A singer, an actor, an athlete. The learner knows them; they don't know the learner. */
    PUBLIC_FIGURE,
}

/** The intake's relationship chips whose default is "we talk casually and know each other's lives". */
val CLOSE_RELATIONSHIP_KINDS: Set<String> = setOf("Friend", "Partner", "Family")

/**
 * What the "How do you two talk?" card starts on for a relationship. A
 * starting point to confirm, never a rule: a family can be formal and a
 * manager can be on first-name terms, which is why the card exists.
 */
fun defaultRegisters(kind: String?): Pair<SpeechRegister, SpeechRegister> =
    if (kind != null && kind in CLOSE_RELATIONSHIP_KINDS) SpeechRegister.CASUAL to SpeechRegister.CASUAL
    else SpeechRegister.POLITE to SpeechRegister.POLITE

/** The default for `knowsMyLife`: close relationships know the learner's life. */
fun knowsMyLifeByDefault(kind: String?): Boolean = kind != null && kind in CLOSE_RELATIONSHIP_KINDS

val Counterpart.cast: CounterpartCast
    get() = when {
        isPublicFigure == true -> CounterpartCast.PUBLIC_FIGURE
        remoteId == null -> CounterpartCast.OWN_PERSON
        else -> CounterpartCast.STRANGER
    }

/**
 * How the learner speaks to them, as the prompts use it. A stranger or a
 * public figure left unset is polite — that is what meeting someone is. An
 * own person left unset returns null: the relationship decides, which is what
 * every person made before this field did.
 */
val Counterpart.effectiveMyRegister: SpeechRegister?
    get() = myRegister ?: if (cast == CounterpartCast.OWN_PERSON) null else SpeechRegister.POLITE

/** How they speak to the learner — same fallbacks as [effectiveMyRegister]. */
val Counterpart.effectiveTheirRegister: SpeechRegister?
    get() = theirRegister ?: if (cast == CounterpartCast.OWN_PERSON) null else SpeechRegister.POLITE

/**
 * Whether a call with this person is handed the learner's whole notebook.
 * Only ever for someone from their own life: a stranger or a public figure
 * never gets past what the learner lets strangers hear.
 */
val Counterpart.knowsLearnersLife: Boolean
    get() = cast == CounterpartCast.OWN_PERSON && (knowsMyLife ?: knowsMyLifeByDefault(relationshipKind))

/** Close in the way that changes how a call SOUNDS. */
val Counterpart.isClose: Boolean
    get() = (relationshipKind != null && relationshipKind in CLOSE_RELATIONSHIP_KINDS) ||
        (myRegister == SpeechRegister.CASUAL && theirRegister == SpeechRegister.CASUAL)
