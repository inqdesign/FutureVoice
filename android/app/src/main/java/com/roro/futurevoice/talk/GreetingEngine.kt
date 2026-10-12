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
        val system = """
You write the ONE line a person says when the learner walks up to them —
a greeting that sounds like THIS person, in $language.

Rules:
- One or two short sentences, at most 14 words in all. Spoken, natural.
- Build it on ONE concrete thing about them, said as they would say it:
  · someone with a self-introduction: take one detail from it — what
    they do, where they are, something they love or are in the middle
    of ("Hi, I'm Moeka! Do you know Shiina Ringo?"). If it is only a
    list of topics, use their town or one interest, lightly.
  · a character in the middle of a situation: greet from inside it —
    a pharmacist at the counter, a landlord at the door, a nurse
    starting the question she'd really ask.
  · someone the learner knows: greet the way that relationship does,
    and you may touch the history they share.
- Never health, money, family trouble or anything private, even if the
  context mentions it.
- Address the learner the way this relationship would (casual for close
  people, polite otherwise).
- Do NOT open with a greeting word plus a name ("Hi Eunggyu", "Hello,
  Minji"). Most lines use no name at all; start with the thing itself.
  A bare "Hi!" or "Hey!" in front is fine, not every time.
- May hint at something going on in their own life. Never mention
  practising, learning, languages or this app. No emoji, no quotes.
- Everything below is CONTEXT ONLY: never quote it, and never let its
  language change the language you write in ($language).

Reply with the line only.
""".trim()
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
