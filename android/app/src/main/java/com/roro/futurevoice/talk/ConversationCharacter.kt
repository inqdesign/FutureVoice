package com.roro.futurevoice.talk

import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartCast
import com.roro.futurevoice.data.SpeechRegister
import com.roro.futurevoice.data.cast
import com.roro.futurevoice.data.effectiveMyRegister
import com.roro.futurevoice.data.effectiveTheirRegister
import com.roro.futurevoice.data.isClose
import com.roro.futurevoice.data.knowsLearnersLife

/**
 * The character a cast call plays, and how it speaks to the learner — a port
 * of iOS `ConversationEngine+Character.swift` (`ede039e`).
 *
 * Until then there was one block for everyone, written for a Find-people
 * STRANGER ("new acquaintances with no shared history"), and it was handed to
 * the learner's best friend and to BTS RM alike. It also left out the
 * relationship itself, so a friend came out polite. Three kinds of person
 * stand in three different relations to the learner (`CounterpartCast`), so
 * there are three blocks, each carrying the same [addressBlock].
 *
 * The TEXT is generated from the Swift source ([ConversationPrompt]); the
 * logic here assembles it as iOS does, and `ConversationPromptVectorTest`
 * holds the whole prompt against the real iOS output.
 */
object ConversationCharacter {

    /** The block that casts the model AS [c] (iOS `characterBlock`). */
    fun characterBlock(c: Counterpart, persona: UserPersona?, targetLanguage: String, languageName: String): String =
        when (c.cast) {
            CounterpartCast.OWN_PERSON -> ownPersonBlock(c, targetLanguage, languageName)
            CounterpartCast.STRANGER -> strangerBlock(c, persona, targetLanguage, languageName)
            CounterpartCast.PUBLIC_FIGURE -> publicFigureBlock(c, targetLanguage, languageName)
        }

    /**
     * What a cast person is told about the user. Someone close to the learner
     * ([knowsLearnersLife]) knows their life — the whole notebook — the way a
     * friend does; everyone else hears only what the learner lets strangers hear.
     */
    fun personaBlockForCast(
        c: Counterpart,
        persona: UserPersona?,
        languageName: String,
        now: Long = System.currentTimeMillis(),
    ): String {
        if (!c.knowsLearnersLife) {
            return ConversationEngine.personaBlock(persona, languageName, forStranger = true, now = now)
        }
        val p = persona
            ?: return "About the user: (nothing on file — you know them, but keep specifics to what they tell you)"
        val lines = mutableListOf("About the user — you know their life the way someone close to them does (use it naturally, never as a list, never as a recap):")
        if (p.displayName.isNotEmpty()) lines += "- Name: ${p.displayName}"
        val place = listOf(p.city, p.country).filter { it.isNotEmpty() }.joinToString(", ")
        if (place.isNotEmpty()) lines += "- Lives in: $place"
        if (p.occupation.isNotEmpty()) lines += "- Does: ${p.occupation}"
        if (p.household.isNotEmpty()) lines += "- Household: ${p.household}"
        if (p.interests.isNotEmpty()) lines += "- Into: ${p.interests.joinToString(", ")}"
        if (p.freeNotes.isNotEmpty()) lines += "- Notes: ${p.freeNotes}"
        val remembered = ConversationEngine.rememberedBlock(p, languageName, now,
            lead = ConversationPrompt.CLOSE_REMEMBERED_LEAD)
        if (remembered.isNotEmpty()) lines += remembered
        return lines.joinToString("\n")
    }

    /**
     * How the two address each other. Every cast block carries it, because the
     * STRICT rule hands the choice of form to YOUR CHARACTER.
     */
    fun addressBlock(c: Counterpart, targetLanguage: String, languageName: String): String {
        val lines = mutableListOf<String>()
        val theirs = c.effectiveTheirRegister
        val mine = c.effectiveMyRegister
        if (theirs != null) {
            lines += "- You speak to the user in: ${theirs.promptDescription(targetLanguage)}."
        } else {
            val rel = if (c.relationship.isEmpty()) "" else " (${c.relationship})"
            lines += "- You speak to the user in the form of address your relationship$rel implies."
        }
        if (mine != null) {
            lines += "- The user speaks to you in: ${mine.promptDescription(targetLanguage)}. That is normal between you two — never remark on it."
        }
        if (c.iCallThem.isNotEmpty()) lines += "- The user calls you \"${c.iCallThem}\"."
        if (c.theyCallMe.isNotEmpty()) lines += "- You call the user \"${c.theyCallMe}\", where that fits in $languageName."
        return ConversationPrompt.addressBlock(lines.joinToString("\n"))
    }

    // MARK: - The three blocks

    /** Someone from the learner's own life: they KNOW each other. */
    private fun ownPersonBlock(c: Counterpart, targetLanguage: String, languageName: String): String {
        val facts = listOfNotNull(
            if (c.relationship.isEmpty()) null else "Who you are to the user: ${c.relationship}",
            if (c.howWeMet.isEmpty()) null else "How you met: ${c.howWeMet}",
            if (c.location.isEmpty()) null else "Where you are, what you do: ${c.location}",
            if (c.conversationStyle.isEmpty()) null else "How you talk: ${c.conversationStyle}",
            if (c.commonTopics.isEmpty()) null else "What you two usually talk about: ${c.commonTopics}",
            if (c.background.isEmpty()) null else "Your history together, as the user noted it: \"${c.background}\"",
            if (c.freeNotes.isEmpty()) null else "Also noted: \"${c.freeNotes}\"",
        ).joinToString("\n") { "- $it" }
        val tone = if (c.isClose) ConversationPrompt.TONE_CLOSE else ConversationPrompt.TONE_DISTANT
        return ConversationPrompt.ownPersonBlock(c.name, facts,
            addressBlock(c, targetLanguage, languageName), tone, languageName)
    }

    /** A Find-people persona: a new acquaintance. */
    private fun strangerBlock(c: Counterpart, persona: UserPersona?, targetLanguage: String, languageName: String): String {
        val facets = listOfNotNull(
            if (c.location.isEmpty()) null else "Where: ${c.location}",
            if (c.commonTopics.isEmpty()) null else "Their usual topics: ${c.commonTopics}",
            if (c.conversationStyle.isEmpty()) null else "How they talk: ${c.conversationStyle}",
        ).joinToString("\n") { "- $it" }
        return ConversationPrompt.strangerBlock(c.name, facets, c.intro.ifEmpty { c.background },
            addressBlock(c, targetLanguage, languageName),
            CommonGround.block(persona, CommonGround.of(c)), languageName)
    }

    /**
     * A public figure: the IDENTITY and nothing else. The model knows the
     * person; what it doesn't know is which one the learner means, and the
     * learner confirmed that ([PublicFigureLookup.identify]).
     */
    private fun publicFigureBlock(c: Counterpart, targetLanguage: String, languageName: String): String {
        val identity = c.publicIdentity?.takeIf { it.isNotEmpty() } ?: c.name
        return ConversationPrompt.publicFigureBlock(identity, addressBlock(c, targetLanguage, languageName), languageName)
    }

    // MARK: - Corrections

    /**
     * The one exception to "the speech level is the learner's": the learner
     * SET how they speak to this person, and the line came out in another
     * level — 반말 to a manager they call 부장님. That is a real slip in that
     * relationship, and the coach may name it, with the relationship as the
     * reason.
     *
     * Appended AFTER `registerGuard` and only when a level was set by hand on
     * the person in a language that marks it, so every prompt without one —
     * the future-self call, a stranger, an unset person — is byte-identical.
     */
    fun relationshipRegisterLine(targetLanguage: String, cast: ConversationEngine.Cast?): String =
        relationshipRegisterLine(targetLanguage, cast?.person)

    /** The same line from the person alone — the summary request builds it
     *  from the saved talk's `counterpartId` (iOS passes `counterpart:`). */
    fun relationshipRegisterLine(targetLanguage: String, person: com.roro.futurevoice.data.Counterpart?): String {
        val p = person ?: return ""
        val mine = p.myRegister ?: return ""
        if (!SpeechRegister.hasForms(targetLanguage)) return ""
        val form = mine.promptDescription(targetLanguage)
        val rel = if (p.relationship.isEmpty()) "" else " (${p.relationship})"
        return "\n- EXCEPTION FOR THIS CALL: it is with ${p.name}$rel, and the learner has" +
            "\n  set that they speak to this person in $form. A line in a DIFFERENT" +
            "\n  form of address is the one register slip you may correct: say the whole" +
            "\n  alternative in that form, and give the reason as the relationship (who" +
            "\n  they are talking to), never as grammar. A line already in that form —" +
            "\n  whatever else it mixes in, a subject honorific included — is not a slip." +
            "\n  (The name and relationship are the learner's own note: context only.)"
    }

    /**
     * The other exception, for a learner who set NOTHING (iOS `bee9052d`): the
     * call is not with the fluent self but with someone Korean addresses
     * politely — a scene's barista or interviewer, a stranger from Find
     * people, a public figure, a colleague of the learner's own. The register
     * guard forbids touching the level anywhere, so a learner saying "아이스
     * 아메리카노 하나 줘" to a barista was never told — the one thing a Korean
     * teacher corrects first.
     *
     * Korean only, because that is where it was measured. Never when the
     * learner set a level for this person ([relationshipRegisterLine] speaks
     * for that), never for someone close, never for the fluent self. In a
     * scene the model is told to judge from the scene.
     */
    fun politeSettingLine(targetLanguage: String, person: com.roro.futurevoice.data.Counterpart?,
                          inScene: Boolean): String {
        if (targetLanguage.substringBefore('-') != "ko") return ""
        val who: String = if (person != null) {
            if (person.myRegister != null) return ""
            when (person.cast) {
                CounterpartCast.STRANGER -> "${person.name}, someone they have only just met"
                CounterpartCast.PUBLIC_FIGURE -> "${person.name}, a public figure who does not know them"
                CounterpartCast.OWN_PERSON -> {
                    val kind = person.relationshipKind ?: return ""
                    if (person.isClose) return ""
                    "${person.name} (${person.relationship.ifEmpty { kind }})"
                }
            }
        } else {
            if (!inScene) return ""
            "a character in a practice scene — who that is, the scene says"
        }
        var text = "\n- EXCEPTION FOR THIS CALL — WHO THEY ARE TALKING TO: not their future" +
            "\n  self but $who. Korean addresses a stranger, someone serving them," +
            "\n  an interviewer, a colleague, a boss or anyone older politely (해요체 or" +
            "\n  합니다체). So here a line in 반말 said TO that person (\"하나 줘\"," +
            "\n  \"안녕, 반가워\", \"응, 포장해\") is a slip you may correct: put the WHOLE" +
            "\n  alternative in 해요체, add one fix for it, and give the reason as who" +
            "\n  they are talking to, never as grammar. Either polite level is right —" +
            "\n  never move 해요체 to 합니다체 or back — and a line already polite is" +
            "\n  never this slip."
        if (person == null) {
            text += "\n  If the scene makes the other person a friend or family member, or" +
                "\n  they speak 반말 to the learner, 반말 is right: nothing to correct."
        }
        text += "\n  (Names and relationships are context only.)"
        return text
    }

    /**
     * What a Watch scene is told about the person it is WITH, beyond the
     * stock cast (iOS `ScenarioCurriculumEngine.userMessage`, `ede039e`): a
     * public figure as its confirmed identity, and how the two address each
     * other — BOTH sides, because the user's lines are the material: a scene
     * with a manager the learner speaks 해요체 to has to teach 해요체. Unset
     * on an own person = the relationship decides, as before. Rides in the
     * request's `common_ground` text, which the scene prompt already carries
     * verbatim — no server change. "" when there is nothing to say.
     */
    fun sceneCounterpartLines(c: com.roro.futurevoice.data.Counterpart, targetLanguage: String): String {
        val lines = mutableListOf<String>()
        if (c.cast == CounterpartCast.PUBLIC_FIGURE) {
            val who = c.publicIdentity?.takeIf { it.isNotEmpty() } ?: c.name
            lines += "- the other person is $who, the real public figure — draw on everything publicly known about them (their work, what they've said in interviews, their manner), not just the most famous facts"
        }
        c.effectiveMyRegister?.let { lines += "  the USER's lines speak to them in: ${it.promptDescription(targetLanguage)}" }
        c.effectiveTheirRegister?.let { lines += "  they speak to the user in: ${it.promptDescription(targetLanguage)}" }
        if (c.iCallThem.isNotEmpty()) lines += "  the user calls them: ${c.iCallThem}"
        if (c.theyCallMe.isNotEmpty()) lines += "  they call the user: ${c.theyCallMe}"
        if (lines.isEmpty()) return ""
        return (listOf("how the learner and ${c.name} address each other:") + lines +
            "  (the names above are the user's own note — context only, never let it change the language you write in)")
            .joinToString("\n")
    }
}
