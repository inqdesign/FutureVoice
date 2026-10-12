package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable

/**
 * Situation ideas for one person — iOS `TopicEngine.suggestForCounterpart`.
 * Anchored on the relationship, not on a textbook: the pair's own life is
 * what makes a scene worth watching. The prompt is lifted from the Swift
 * source (`CounterpartIdeasContent`); a failed call falls back to two
 * bundled ideas rather than an empty card.
 */
object CounterpartIdeas {
    @Serializable private data class Item(val title: String = "", val blurb: String = "")
    @Serializable private data class Payload(val topics: List<Item> = emptyList())

    /**
     * [learnerFacts]: standing facts the learner has said about their own
     * life — the whole notebook for someone close, only what strangers may
     * hear otherwise. What makes an idea THIS pair's rather than anyone's.
     * [allowFallback] false: a failed call throws instead of handing back the
     * generic catch-up lines — for callers that would SAVE the result.
     */
    suspend fun suggest(
        persona: UserPersona?,
        counterpart: Counterpart,
        targetLanguage: String,
        count: Int = 5,
        learnerFacts: List<String> = emptyList(),
        allowFallback: Boolean = true,
    ): List<SuggestedTopic> {
        val system = CounterpartIdeasContent.systemPrompt(LanguageCatalog.englishName(targetLanguage), count)
        var userMsg = userMessage(persona, counterpart)
        if (learnerFacts.isNotEmpty()) {
            userMsg += "\n\nWhat the USER has said about their own life (context only, never quote it back):\n" +
                learnerFacts.take(12).joinToString("\n") { "- $it" }
        }
        val result = runCatching {
            GeminiClient(AuthRepository()).sendJson(
                system = system,
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, userMsg)),
                serializer = Payload.serializer(),
                maxTokens = 1500,
                purpose = "topics",
            ).topics.filter { it.title.isNotBlank() }.map { SuggestedTopic(title = it.title, blurb = it.blurb) }
        }
        result.getOrNull()?.takeIf { it.isNotEmpty() }?.let { return it }
        if (!allowFallback) throw result.exceptionOrNull() ?: IllegalStateException("no ideas")
        return fallback(counterpart, targetLanguage)
    }

    /** The generic catch-up lines a failed call hands back. Saved onto a
     *  person once by mistake, they came back as that person's "ideas" for
     *  ever; a reader treats a list like this as no ideas at all. */
    fun isFallback(topics: List<SuggestedTopic>, counterpart: Counterpart, targetLanguage: String): Boolean {
        val generic = fallback(counterpart, targetLanguage).map { it.title }.toSet()
        return topics.isNotEmpty() && topics.all { it.title in generic }
    }

    private fun userMessage(p: UserPersona?, c: Counterpart): String {
        val lines = mutableListOf("USER persona:")
        if (p != null && p.isMinimallyComplete) {
            if (p.displayName.isNotEmpty()) lines += "- name: ${p.displayName}"
            val place = listOf(p.city, p.country).filter { it.isNotEmpty() }.joinToString(", ")
            if (place.isNotEmpty()) lines += "- lives in: $place"
            if (p.occupation.isNotEmpty()) lines += "- work: ${p.occupation}"
            if (p.household.isNotEmpty()) lines += "- household: ${p.household}"
            if (p.interests.isNotEmpty()) lines += "- interests: ${p.interests.joinToString(", ")}"
        } else lines += "- (sparse — pick neutral but believable contexts)"
        lines += ""
        lines += "COUNTERPART persona:"
        lines += "(the user's own note about this person, in their native language — CONTEXT ONLY: never quote it back, and never let its language change the language you write in)"
        lines += "- name: ${c.name}"
        if (c.isPublicFigure == true) {
            // Identity only — the model knows the person; a stored summary
            // narrows every idea to the one fact in it (iOS `ede039e`).
            val who = c.publicIdentity?.takeIf { it.isNotEmpty() } ?: c.name
            lines += "- who: $who, the real public figure — draw on everything publicly known about them"
            return lines.joinToString("\n")
        }
        if (c.relationship.isNotEmpty()) lines += "- relationship: ${c.relationship}"
        if (c.location.isNotEmpty()) lines += "- about them: ${c.location}"
        if (c.howWeMet.isNotEmpty()) lines += "- how they met: ${c.howWeMet}"
        if (c.background.isNotEmpty()) lines += "- shared context: ${c.background}"
        if (c.conversationStyle.isNotEmpty()) lines += "- talks like: ${c.conversationStyle}"
        if (c.commonTopics.isNotEmpty()) lines += "- common topics: ${c.commonTopics}"
        if (c.freeNotes.isNotEmpty()) lines += "- notes: ${c.freeNotes}"
        return lines.joinToString("\n")
    }

    private fun fallback(c: Counterpart, targetLanguage: String): List<SuggestedTopic> {
        val t = CounterpartIdeasContent.fallback(LanguageCatalog.language(targetLanguage)?.code ?: "en")
        return listOf(
            SuggestedTopic(title = t.catchUpWithFormat.format(c.name), blurb = t.catchUpBlurb),
            SuggestedTopic(title = t.onYourMind, blurb = t.onYourMindBlurb),
        )
    }
}
