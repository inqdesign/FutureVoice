package com.roro.futurevoice.net

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.CoachingLanguage
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.security.MessageDigest

/**
 * The public intro is a PORTRAIT written by a model, never the notebook read
 * out (iOS `PublicIntroComposer`, 2026-09-25). The concatenation it replaces
 * read as a memo pad — "Gained a new app user from Hong Kong", in two
 * languages, introducing nobody. One flash-lite call writes 4–6 first-person
 * sentences in the TARGET language from occupation · place · interests ·
 * situations · the stranger-safe FACT lines, told to describe the person and
 * the areas they can speak to, never the events. Cached per language under a
 * hash of every input, so preview, mirror and editor show ONE text and the
 * model is asked again only when an input changed. What is private never
 * reaches it.
 */
object PublicIntroComposer {
    const val PROMPT_VERSION = "2"
    const val MAX_FACTS = 14

    data class Sources(
        val language: String, val name: String, val occupation: String,
        val city: String, val country: String, val stay: String,
        val interests: List<String>, val situations: List<String>, val facts: List<String>,
    ) {
        val isEmpty: Boolean get() = occupation.isEmpty() && city.isEmpty() && interests.isEmpty() &&
            situations.isEmpty() && facts.isEmpty()
        val key: String get() {
            val fields = listOf(PROMPT_VERSION, language, name, occupation, city, country, stay, "|") +
                interests + "|" + situations + "|" + facts
            return MessageDigest.getInstance("SHA-256").digest(fields.joinToString("\u001F").toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
    }

    fun sources(p: UserPersona, language: String) = Sources(
        language = language, name = p.displayName, occupation = p.occupation.trim(),
        city = p.city, country = p.country, stay = p.lengthOfStay,
        interests = p.interests.filter { it.isNotEmpty() },
        situations = p.situations.filter { it.isNotEmpty() },
        // Standing facts only: a `now` line is news, not who you are.
        facts = p.currentNotes().filter { it.kind == com.roro.futurevoice.talk.PersonaNote.Kind.FACT }
            .mapNotNull { it.strangerLine }.takeLast(MAX_FACTS),
    )

    @Volatile private var appContext: Context? = null
    fun init(context: Context) { appContext = context.applicationContext }

    /** Cached portrait or the deterministic fallback — never asks the model. */
    fun current(p: UserPersona, language: String): String {
        val s = sources(p, language)
        return cached(s) ?: fallback(s)
    }

    private val inflight = HashMap<String, Deferred<String>>()

    /** The portrait, written if needed. Falls back on any failure.
     *  [fresh] asks again even when the cache holds a paragraph for these
     *  inputs — the profile page's "write it again" (iOS 2026-10-12): the
     *  same notes can be told better, and a learner who finds it flat should
     *  not have to change a fact to get another try. */
    suspend fun compose(p: UserPersona, language: String, fresh: Boolean = false): String {
        val s = sources(p, language)
        if (fresh) {
            val intro = (if (s.isEmpty) null
                else runCatching { write(s, attempt = java.util.UUID.randomUUID().toString()) }.getOrNull())
                ?: return cached(s) ?: fallback(s)
            save(s, intro)
            return intro
        }
        cached(s)?.let { return it }
        if (s.isEmpty) return ""
        return coroutineScope {
            val job = synchronized(inflight) {
                inflight[s.key] ?: async {
                    runCatching { write(s) }.onSuccess { save(s, it) }.getOrElse { fallback(s) }
                }.also { inflight[s.key] = it }
            }
            val result = job.await()
            synchronized(inflight) { inflight.remove(s.key) }
            result
        }
    }

    fun fallback(s: Sources): String {
        val parts = ArrayList<String>()
        if (s.occupation.isNotEmpty()) parts.add(s.occupation)
        if (s.stay.isNotEmpty() && s.city.isNotEmpty()) parts.add("${s.city} · ${s.stay}")
        if (s.situations.isNotEmpty()) parts.add(s.situations.joinToString(", "))
        parts.addAll(s.facts)
        return parts.joinToString("\n")
    }

    @Serializable private data class Payload(val intro: String = "")

    private suspend fun write(s: Sources, attempt: String = ""): String {
        val payload = GeminiClient(AuthRepository()).sendJson(
            system = prompt(s),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, "Write the introduction.")),
            serializer = Payload.serializer(),
            model = GeminiClient.Model.FLASH_LITE_31,
            maxTokens = 800,
            purpose = "public-intro",
            idempotencyKey = "public-intro:${s.key}" + if (attempt.isEmpty()) "" else ":$attempt",
        )
        return payload.intro.trim().ifEmpty { throw IllegalStateException("empty intro") }
    }

    fun prompt(s: Sources): String {
        val languageName = LanguageCatalog.englishName(s.language)
        val about = ArrayList<String>()
        if (s.name.isNotEmpty()) about.add("- Name: ${s.name}")
        val place = listOf(s.city, s.country).filter { it.isNotEmpty() }.joinToString(", ")
        if (place.isNotEmpty()) about.add("- Lives in: $place${if (s.stay.isEmpty()) "" else " (${s.stay})"}")
        if (s.occupation.isNotEmpty()) about.add("- Does: ${s.occupation}")
        if (s.interests.isNotEmpty()) about.add("- Interests: ${s.interests.joinToString(", ")}")
        if (s.situations.isNotEmpty()) about.add("- Uses $languageName for: ${s.situations.joinToString(", ")}")
        if (s.facts.isNotEmpty()) {
            about.add("- Things they've said about their life (each is a plain fact, or an OUTLINE they chose to keep vague):")
            s.facts.forEach { about.add("  · $it") }
        }
        return com.roro.futurevoice.talk.LiftedPrompts.publicIntro(languageName, about.joinToString("\n"))
    }

    // ── Cache: one entry per language, `files/public_intro.json` ──

    @Serializable private data class Entry(val key: String, val intro: String, val writtenAt: Long)

    private fun file(): File? = appContext?.let { File(it.filesDir, "public_intro.json") }
    private val serializer = MapSerializer(String.serializer(), Entry.serializer())
    @Volatile private var loaded: Map<String, Entry>? = null

    private fun entries(): Map<String, Entry> = loaded ?: runCatching {
        file()?.takeIf { it.exists() }?.readText()?.let { Edge.json.decodeFromString(serializer, it) }
    }.getOrNull().orEmpty().also { loaded = it }

    fun cached(s: Sources): String? = entries()[s.language]?.takeIf { it.key == s.key }?.intro

    private fun save(s: Sources, intro: String) {
        val next = entries() + (s.language to Entry(s.key, intro, System.currentTimeMillis()))
        loaded = next
        runCatching { file()?.writeText(Edge.json.encodeToString(serializer, next)) }
    }
}
