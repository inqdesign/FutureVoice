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

    suspend fun suggest(persona: UserPersona?, counterpart: Counterpart, targetLanguage: String, count: Int = 5): List<SuggestedTopic> {
        val system = CounterpartIdeasContent.systemPrompt(LanguageCatalog.englishName(targetLanguage), count)
        return runCatching {
            GeminiClient(AuthRepository()).sendJson(
                system = system,
                messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, userMessage(persona, counterpart))),
                serializer = Payload.serializer(),
                maxTokens = 1500,
                purpose = "topics",
            ).topics.filter { it.title.isNotBlank() }.map { SuggestedTopic(title = it.title, blurb = it.blurb) }
        }.getOrNull()?.takeIf { it.isNotEmpty() } ?: fallback(counterpart, targetLanguage)
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
