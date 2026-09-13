package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable

/**
 * The composer's drill-down chips — iOS `TopicEngine.suggestForPath`.
 * One step at a time: a category, then a narrowing, then a specific moment.
 * Level 1 of a preset category is shipped (`PathIdeasContent.seeds`), so the
 * first tap never waits on the model; persona-tilted specifics come from it
 * one level down.
 */
object PathIdeas {
    @Serializable private data class Item(val title: String = "", val blurb: String = "")
    @Serializable private data class Payload(val topics: List<Item> = emptyList())

    suspend fun suggest(
        path: List<String>,
        persona: UserPersona?,
        counterpart: Counterpart?,
        targetLanguage: String,
        count: Int = 6,
    ): List<SuggestedTopic> {
        val system = PathIdeasContent.systemPrompt(
            languageName = LanguageCatalog.englishName(targetLanguage),
            count = count, depth = path.size,
            personName = counterpart?.name, relationship = counterpart?.relationship ?: "")
        val lines = mutableListOf("path: ${path.joinToString(" > ")}")
        if (persona != null && persona.isMinimallyComplete) {
            if (persona.occupation.isNotEmpty()) lines += "persona work: ${persona.occupation}"
            if (persona.household.isNotEmpty()) lines += "persona household: ${persona.household}"
            val place = listOf(persona.city, persona.country).filter { it.isNotEmpty() }.joinToString(", ")
            if (place.isNotEmpty()) lines += "persona lives in: $place"
        }
        counterpart?.let { c ->
            lines += ""
            lines += "COUNTERPART (the scene is WITH this person):"
            lines += "- name: ${c.name}"
            if (c.relationship.isNotEmpty()) lines += "- relationship: ${c.relationship}"
            if (c.howWeMet.isNotEmpty()) lines += "- how they met: ${c.howWeMet}"
            if (c.background.isNotEmpty()) lines += "- shared context: ${c.background}"
            if (c.commonTopics.isNotEmpty()) lines += "- common topics: ${c.commonTopics}"
        }
        return GeminiClient(AuthRepository()).sendJson(
            system = system,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, lines.joinToString("\n"))),
            serializer = Payload.serializer(),
            // Chips are short and output length IS the latency here, but a
            // tight ceiling only cuts the JSON in half and loses the whole
            // call; the prompt is what keeps chips short.
            maxTokens = 1200,
            purpose = "topics",
        ).topics.filter { it.title.isNotBlank() }.map { SuggestedTopic(title = it.title, blurb = it.blurb) }
    }
}
