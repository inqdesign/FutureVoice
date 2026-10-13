package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartCast
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.cast
import com.roro.futurevoice.data.isClose
import com.roro.futurevoice.net.GeminiClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The line a person says when the learner comes across them on the Watch map
 * — a greeting in character, not a prompt to practise (iOS `GreetingEngine`).
 * Written once per person per target language (when a person is saved
 * without one, when a learner publishes their introduction, or the first time
 * the map needs it) and kept; the learner can rewrite it in the person form.
 */
object GreetingEngine {
    /** Bump when the prompt changes enough that lines already written should
     *  be written again ([Counterpart.greetingNeedsWriting]). 2: no opening
     *  on "Hi <learner's name>" — every line on a learner's map began that way. */
    const val PROMPT_VERSION = 2

    @Suppress("UNUSED_PARAMETER")
    suspend fun write(c: Counterpart, persona: UserPersona?, targetLanguage: String): String {
        val language = LanguageCatalog.englishName(targetLanguage)
        val system = LiftedPrompts.greetingSystem(language)
        val lines = mutableListOf("Person: ${c.name}")
        if (c.cast == CounterpartCast.PUBLIC_FIGURE) {
            lines += "Who: ${c.publicIdentity ?: c.name}, the real public figure; the learner is a fan meeting them"
        } else {
            if (c.relationship.isNotEmpty()) lines += "To the learner: ${c.relationship}"
            if (c.intro.isNotEmpty()) lines += "Their self-introduction: ${c.intro}"
            if (c.background.isNotEmpty()) lines += "Shared context: ${c.background}"
            if (c.location.isNotEmpty()) lines += "About them: ${c.location}"
            if (c.conversationStyle.isNotEmpty()) lines += "Talks like: ${c.conversationStyle}"
            if (c.theyCallMe.isNotEmpty()) lines += "They call the learner: ${c.theyCallMe}"
            lines += if (c.isClose) "They are close: casual." else "Not close: polite."
        }
        val text = GeminiClient(AuthRepository()).sendText(
            system = system,
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, lines.joinToString("\n"))),
            model = GeminiClient.Model.FLASH_LITE_31,
            // Thinking spends from the same ceiling: at 120 the model thought ~110
            // tokens and the line was cut to 4-6 ("Let's talk about nawana").
            maxTokens = 600,
            purpose = "greeting",
        )
        val clean = text.trim().trim('"', '“', '”', '«', '»', '「', '」')
        if (clean.isEmpty()) throw IllegalStateException("empty greeting")
        return clean
    }

    /** Writes one for a person on file that has none in this language (or one
     *  an older prompt wrote), and saves it. Silent on failure. [draft] is
     *  the person as just saved — the store write may still be in flight. */
    suspend fun ensure(context: Context, draft: Counterpart, language: String) {
        if (!draft.greetingNeedsWriting(language, PROMPT_VERSION)) return
        val store = CounterpartStore.shared(context)
        val c = store.load().firstOrNull { it.id == draft.id } ?: draft
        if (!c.greetingNeedsWriting(language, PROMPT_VERSION)) return
        val line = runCatching { write(c, null, language) }.getOrNull() ?: return
        val fresh = store.load().firstOrNull { it.id == draft.id } ?: return
        if (!fresh.greetingNeedsWriting(language, PROMPT_VERSION)) return
        val saved = fresh.withGreeting(line, language)
        store.save(saved.copy(greetingVersionByLanguage = saved.greetingVersionByLanguage + (language to PROMPT_VERSION)))
        StoreEvents.bump()
    }

    private val background = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** [ensure] on a scope that outlives the form that saved the person. */
    fun ensureInBackground(context: Context, draft: Counterpart, language: String) {
        if (!draft.greetingNeedsWriting(language, PROMPT_VERSION)) return
        val app = context.applicationContext
        background.launch { ensure(app, draft, language) }
    }
}
