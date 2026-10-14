package com.roro.futurevoice.net

import android.content.Context
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.JapaneseMorph
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.WeekRecap
import com.roro.futurevoice.data.WeekRecapBuilder
import com.roro.futurevoice.data.WeekRecapStore
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SpokenWords
import com.roro.futurevoice.talk.TurnRole
import kotlinx.serialization.Serializable

/**
 * The one model call of "Your week", and the only card that is analysis
 * rather than counting (iOS `WeekRecapCoach`, `633418f`). Handed the raw week
 * — every line the learner said, every correction with its reason, the words
 * they used most with their CEFR grade — and asked for what no count shows:
 * the grammar point that goes wrong across DIFFERENT sentences, the easy word
 * they lean on and the better one a band up, and one habit in how they speak.
 *
 * Nothing it quotes is trusted: an example must be found in the learner's own
 * lines, a leaned-on word is COUNTED here, and a pattern needs two verified
 * sentences to be a pattern. What fails the check is dropped, never shown.
 *
 * Goes through the shared `gemini` edge function like every other call, with
 * `purpose: "week-recap"` (an unknown purpose takes the default daily cap —
 * no server change).
 */
object WeekRecapCoach {

    suspend fun write(context: Context, recap: WeekRecap, targetLanguage: String,
                      level: CefrLevel, nativeLanguage: String): WeekRecap.Coach {
        val sessions = WeekRecapBuilder.sessionsAcrossLanguages(context)
        val evidence = Evidence.gather(recap, sessions, targetLanguage, level)
        var user = evidence.prompt
        WeekRecapStore.recap(context, recap.start)?.coach?.let { previous ->
            user += "\n\n# LAST WEEK'S COACHING (don't repeat it; if a pattern is STILL there, say so with this week's examples)\n"
            user += previous.grammar.joinToString("\n") { "- grammar: ${it.rule}" }
            user += "\n" + previous.upgrades.joinToString("\n") { "- upgrade: ${it.instead} → ${it.better}" }
        }
        // Streamed only for the stream's longer read timeout: three nested
        // arrays on the app's longest evidence prompt can sit silent past the
        // buffered client's 40 s (iOS gives this call 60 s).
        val response = GeminiClient(AuthRepository()).sendJsonStreamAccumulating(
            system = systemPrompt(targetLanguage, nativeLanguage, evidence.level),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER, user)),
            serializer = Payload.serializer(),
            // gen-3 thinks out of the same ceiling — a truncation loses it all.
            maxTokens = 4096,
            purpose = "week-recap",
            onPartial = {},
        )
        val coach = verified(response, evidence.learnerLines, targetLanguage)
        if (coach.headline.isEmpty()) throw IllegalStateException("empty coach")
        return coach
    }

    fun systemPrompt(targetLanguage: String, nativeLanguage: String, level: String): String {
        val targetName = LanguageCatalog.englishName(targetLanguage)
        val nativeName = LanguageCatalog.englishName(nativeLanguage)
        return com.roro.futurevoice.talk.LiftedPrompts.weekRecapSystem(targetName, nativeName, level)
    }

    // MARK: Evidence

    data class Evidence(val learnerLines: List<String>, val level: String, val prompt: String) {
        companion object {
            fun gather(recap: WeekRecap, all: List<Session>, targetLanguage: String,
                       setLevel: CefrLevel): Evidence {
                val sessions = all.filter { session ->
                    val last = session.turns.lastOrNull { it.role == TurnRole.USER }?.timestamp
                    LanguageCatalog.sameLanguage(session.targetLanguage, targetLanguage) &&
                        last != null && last >= recap.start && last < recap.end
                }
                val lines = ArrayList<String>()
                val seen = HashSet<String>()
                for (session in sessions) for (turn in session.turns) {
                    if (!turn.isEvidence) continue
                    val text = turn.transcript.trim()
                    if (text.isEmpty() || !seen.add(text)) continue
                    lines.add(text.take(400))
                }

                val corrections = ArrayList<String>()
                val seenFix = HashSet<String>()
                fun addFix(was: String, now: String, why: String) {
                    val key = CarryoverDetector.normalized(was) + "→" + CarryoverDetector.normalized(now)
                    if (was.isEmpty() || !seenFix.add(key)) return
                    corrections.add("- \"$was\" → \"$now\"" + if (why.isEmpty()) "" else " ($why)")
                }
                for (session in sessions) {
                    for (turn in session.turns) {
                        if (!turn.isEvidence) continue
                        turn.suggestion?.fixes.orEmpty().forEach { addFix(it.was, it.now, it.why) }
                    }
                    session.summary?.grammarIssues.orEmpty().forEach { addFix(it.quote, it.correction, it.note) }
                }

                // The words they lean on, counted and graded here — the model
                // picks from this list rather than guessing what was frequent.
                val frequent = frequentWords(lines, targetLanguage)
                    .take(25).joinToString(", ") { (w, n, l) -> "$w ×$n (${l.code.uppercase()})" }

                val reads = sessions.mapNotNull { it.summary?.scorecard?.cefrLevel?.uppercase() }
                // The talks' own reads outrank the level picked at setup.
                val level = if (reads.isEmpty()) setLevel.code.uppercase() else reads.sorted()[reads.size / 2]

                val shown = recap.used.map { "used from studies: \"${it.item}\"" } +
                    recap.newExpressions.map { "new phrase from the fluent self: \"${it.item}\"" } +
                    recap.stumbles.map { "repeated word for word: \"${it.was}\" → \"${it.now}\" ×${it.count}" }

                val prompt = com.roro.futurevoice.talk.LiftedPrompts.weekRecapEvidence(
                    level = level,
                    lines = lines.take(220).joinToString("\n"),
                    corrections = if (corrections.isEmpty()) "(none)" else corrections.take(90).joinToString("\n"),
                    frequent = frequent.ifEmpty { "(none)" },
                    shown = if (shown.isEmpty()) "(nothing)" else shown.joinToString("\n"),
                )
                return Evidence(lines, level, prompt)
            }

            /** Words said 2+ times that the graded list knows, most first. */
            private fun frequentWords(lines: List<String>, language: String): List<Triple<String, Int, CefrLevel>> {
                val counts = LinkedHashMap<String, Int>()
                for (line in lines) {
                    val tokens = if (WordSplitter.spaced(language))
                        line.lowercase().split(Regex("[^\\p{L}]+"))
                    else JapaneseMorph.headwords(line, CoreVocabulary.set(language), CoreVocabulary.forms(language))
                        .map { it.first }.distinct()
                    for (token in tokens) if (token.length >= 2) counts[token] = (counts[token] ?: 0) + 1
                }
                return counts.mapNotNull { (word, n) ->
                    if (n < 2) return@mapNotNull null
                    val level = CoreVocabulary.levelOfSurface(word, language) ?: return@mapNotNull null
                    Triple(word, n, level)
                }.sortedByDescending { it.second }
            }
        }
    }

    // MARK: Verification

    /** Keep only what the learner's own lines bear out. */
    fun verified(r: Payload, lines: List<String>, language: String = "en"): WeekRecap.Coach {
        fun said(quote: String) = quote.isNotEmpty() && lines.any { SpokenWords.quotes(quote, it) }
        fun clean(s: String?) = s.orEmpty().trim()

        val grammar = r.grammar.orEmpty().mapNotNull { p ->
            val seen = HashSet<String>()
            val examples = p.examples.orEmpty()
                .map { WeekRecap.Coach.Pair(clean(it.was), clean(it.now)) }
                .filter { it.now.isNotEmpty() && it.was != it.now && said(it.was) }
                .filter { seen.add(CarryoverDetector.normalized(it.was)) }
            // A point seen once is not a pattern.
            if (examples.size < 2 || clean(p.rule).isEmpty()) null
            else WeekRecap.Coach.Pattern(clean(p.rule), examples.take(3), clean(p.tip))
        }

        val upgrades = r.upgrades.orEmpty().mapNotNull { u ->
            val instead = clean(u.instead)
            val better = clean(u.better)
            if (instead.isEmpty() || better.isEmpty() ||
                CarryoverDetector.normalized(instead) == CarryoverDetector.normalized(better)) return@mapNotNull null
            val n = occurrences(instead, lines, language)
            if (n < 2) return@mapNotNull null
            val original = clean(u.original)
            val keepLine = said(original) && clean(u.rewritten).isNotEmpty()
            WeekRecap.Coach.Upgrade(instead, n, better,
                original = if (keepLine) original else "",
                rewritten = if (keepLine) clean(u.rewritten) else "",
                note = clean(u.note))
        }

        val quote = clean(r.insight_quote)
        return WeekRecap.Coach(
            headline = clean(r.headline),
            insight = clean(r.insight),
            insightQuote = if (said(quote)) quote else "",
            grammar = grammar.take(3),
            upgrades = upgrades.take(4),
            plan = r.plan.orEmpty().map { clean(it) }.filter { it.isNotEmpty() }.take(3),
        )
    }

    /** How many times a word or short phrase was said — whole words for a
     *  spaced language, plain substrings for one without spaces. */
    fun occurrences(phrase: String, lines: List<String>, language: String = "en"): Int {
        val needle = phrase.lowercase()
        if (WordSplitter.spaced(language)) {
            val regex = Regex("(?<![\\p{L}])" + Regex.escape(needle) + "(?![\\p{L}])")
            return lines.sumOf { regex.findAll(it.lowercase()).count() }
        }
        if (phrase.isEmpty()) return 0
        return lines.sumOf { it.split(phrase).size - 1 }
    }

    @Serializable
    data class Payload(
        val headline: String? = null,
        val insight: String? = null,
        val insight_quote: String? = null,
        val grammar: List<P>? = null,
        val upgrades: List<U>? = null,
        val plan: List<String>? = null,
    ) {
        @Serializable data class P(val rule: String? = null, val examples: List<E>? = null, val tip: String? = null)
        @Serializable data class E(val was: String? = null, val now: String? = null)
        @Serializable data class U(
            val instead: String? = null, val better: String? = null, val original: String? = null,
            val rewritten: String? = null, val note: String? = null,
        )
    }
}
