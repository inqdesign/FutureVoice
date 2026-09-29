package com.roro.futurevoice.talk

import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable
import java.time.LocalDate

/**
 * A public figure's profile from PUBLIC coverage (iOS
 * `CounterpartParser.parse(publicFigure: true)`, `59c6481`). One
 * search-grounded call on the default model, `purpose: "parse"` — the same
 * purpose and cap iOS uses. The learner's own description is what THEY feel
 * about this person; the profile comes from the open web. Every field is
 * written in the learner's NATIVE language: it is a card they read and edit.
 * Nothing about health, relationships, family or money unless it is the
 * person's own widely reported statement; nothing invented.
 */
object PublicFigureLookup {
    @Serializable
    private data class Payload(
        val identity: String? = null,
        val name: String = "",
        val relationship: String = "",
        val location: String? = null,
        val how_we_met: String? = null,
        val background: String? = null,
        val conversation_style: String? = null,
        val common_topics: String? = null,
    )

    /** Fill [draft]'s profile from coverage. What the learner typed outright
     *  (the name, their relationship) wins over the lookup. */
    suspend fun lookUp(draft: Counterpart, nativeLanguage: String, targetLanguage: String): Counterpart {
        val described = buildList {
            add("Name: ${draft.name}")
            if (draft.relationship.isNotBlank()) add("Why this person: ${draft.relationship}")
            if (draft.howWeMet.isNotBlank()) add("How I came to follow them: ${draft.howWeMet}")
        }.joinToString("\n")
        val user = listOf(
            "language_hint: $targetLanguage",
            "today: ${LocalDate.now()}",
            "spoken_description:",
            described,
        ).joinToString("\n")
        val p = GeminiClient(AuthRepository()).sendJson(
            system = prompt(LanguageCatalog.englishName(nativeLanguage)),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_36,
            maxTokens = 2500,
            searchGrounding = true,
            purpose = "parse",
        )
        return draft.copy(
            relationship = draft.relationship.ifBlank { p.relationship },
            location = p.location?.trim().orEmpty().ifBlank { draft.location },
            howWeMet = draft.howWeMet.ifBlank { p.how_we_met.orEmpty() },
            background = p.background?.trim().orEmpty().ifBlank { draft.background },
            conversationStyle = p.conversation_style?.trim().orEmpty().ifBlank { draft.conversationStyle },
            commonTopics = p.common_topics?.trim().orEmpty().ifBlank { draft.commonTopics },
            isPublicFigure = true,
            publicIdentity = p.identity?.trim()?.takeIf { it.isNotEmpty() },
            factsRefreshedAt = System.currentTimeMillis(),
        )
    }

    private fun prompt(nativeName: String) = """
        The user named a PUBLIC FIGURE — a singer, an actor, an athlete, an author, a politician — they want to practice speaking their target language with, in a simulated conversation (a fan meeting, an interview, a chance meeting). They are not in each other's lives. Look the person up and write a profile from PUBLIC coverage.

        Write EVERY field in $nativeName — this is a card the user reads and edits. Names stay in their usual script; product, album and team names as they are written.

        Return STRICT JSON only — no prose, no code fences:
        {
          "identity": "...",
          "name": "...",
          "relationship": "...",
          "location": "...",
          "how_we_met": "...",
          "background": "...",
          "conversation_style": "...",
          "common_topics": "..."
        }

        Rules:
        - identity: who you settled on, in 3–6 words the user can confirm at a glance — the group or field and the role ("BTS Jimin · singer", "Son Heung-min · footballer"). If the name is ambiguous, pick the most famous reading and say so here.
        - name: as the user said it.
        - relationship: how the USER relates to them, from what they said ("fan since 2019", "I follow their films") — never how the person relates to the user. A few words.
        - location: where they are from and where they are based now, 1 line.
        - how_we_met: how the user came to follow them, IF they said. Else "".
        - background: 3–4 dense sentences from public coverage — origin, what they are known for, their most recent public activity WITH THE YEAR (an album, a season, a film, a return from service), one or two well-known facts fans bring up. Public facts only: nothing about health, relationships, family or money unless it is the person's own widely reported public statement. Nothing invented; if the search finds little, say less.
        - conversation_style: 1–2 sentences on how they come across in interviews and with fans — warmth, humour, energy, formality.
        - common_topics: a short phrase — what fans and interviewers actually talk with them about.
        - Keep anything the user themselves said about why this person matters to them: it belongs in `relationship` or `how_we_met`, not in the person's background.
    """.trimIndent()
}
