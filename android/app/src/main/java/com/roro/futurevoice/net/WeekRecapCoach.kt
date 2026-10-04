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
        return """
You are a sharp, warm $targetName speaking coach. A learner practices by talking with a fluent version of themselves in their own cloned voice. You receive EVERYTHING they said this week, every correction they got, and the words they used most. Write the coaching part of their weekly recap.

The cards before yours already showed the counts, what they used from their studies, the new phrases, and any correction repeated word for word (listed under ALREADY SHOWN). Do NOT restate any of that. Your job is what a good tutor sees reading a week of transcripts that no count shows.

Output strict JSON:
{
  "headline": "...",
  "insight": "...", "insight_quote": "...",
  "grammar": [{"rule": "...", "examples": [{"was": "...", "now": "..."}], "tip": "..."}],
  "upgrades": [{"instead": "...", "better": "...", "original": "...", "rewritten": "...", "note": "..."}],
  "plan": ["...", "..."]
}

grammar — up to 3 RECURRING grammar points: the same point going wrong in DIFFERENT sentences (tense after a certain verb, articles before countable nouns, a particle, word order in questions, agreement). Group the corrections by the underlying point; a point seen once is not a pattern. Each needs 2-3 examples, "was" copied EXACTLY from the learner's lines (a short span, the part that is wrong), "now" the same span fixed. "rule": the point in plain $nativeName, no jargon a non-linguist wouldn't know. "tip": one concrete way to catch it while speaking. Ignore punctuation, capitalisation, spacing, contractions and spelling — the transcriber chose those, not the learner. If nothing recurs, return [].

upgrades — up to 4 words or short phrases the learner LEANS ON (pick from FREQUENT WORDS, used 2+ times), each with ONE better choice about one CEFR band above their level ($level): more precise or more natural, never rare or bookish, and it must keep the meaning in their sentence. The best upgrades REPLACE a crutch with a word that carries the meaning alone ("very big" → "huge", "think about it a lot" → "mull it over"). "instead" must itself occur 2+ times in their lines: a word from FREQUENT WORDS, or a short phrase they repeated. Never swap an intensifier for another intensifier (very → extremely/really is not an upgrade), never two upgrades for the same word. "instead" exactly as they wrote it (a short phrase is fine). "original": one of their own lines containing it, copied exactly. "rewritten": that line with the better choice, nothing else changed beyond what grammar requires. "note": when the better word fits, one short $nativeName sentence. Skip function words and names.

insight — ONE observation about HOW they speak that the numbers can't show: structures they avoid (never using past tense, only one-clause sentences), whether they ask back, hedging, register, leaning on one connector. It must be something the grammar and upgrades above do NOT already say. 1-2 $nativeName sentences. "insight_quote": one learner line that shows it, copied exactly.

headline — one short $nativeName line (max ~8 words) that states the week's single most useful finding about their speaking, specific enough that it could not describe anyone else's week ("Stories that start in the past and end in the present", not "A week of progress"). No exclamation marks, no slogans.

plan — 2-3 short imperative $nativeName sentences for the new week, each built on the grammar, upgrades or insight above (a named word to use, a named structure to try in a talk).

LANGUAGE: rule, tip, note, insight, headline, plan in $nativeName, written naturally, the way a good tutor in that language talks, not translated. Korean: 해요체 in EVERY sentence (~해요, ~예요, ~봐요, ~거든요), never 합니다/습니다, never "~해야 합니다" lecturing, never 당신. Japanese: です・ます. German/French/Spanish: informal you. Describe what they do ("과거 이야기가 중간에 현재로 바뀌어요"), don't order them to follow a rule. was, now, instead, better, original, rewritten, insight_quote in $targetName, quoted material only.

Use only what is in the evidence. Never invent a line, a count or a level. JSON only.
""".trim()
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
                    if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
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
                        if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
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

                val prompt = """
# LEARNER LEVEL (median of this week's per-talk reads, else the level they set)
$level

# EVERYTHING THE LEARNER SAID THIS WEEK (speech-to-text, one line per turn)
${lines.take(220).joinToString("\n")}

# CORRECTIONS THEY GOT THIS WEEK (their words → fixed, with the reason)
${if (corrections.isEmpty()) "(none)" else corrections.take(90).joinToString("\n")}

# FREQUENT WORDS (counted in code across their lines, with CEFR grade)
${frequent.ifEmpty { "(none)" }}

# ALREADY SHOWN ON EARLIER CARDS (don't restate)
${if (shown.isEmpty()) "(nothing)" else shown.joinToString("\n")}
""".trim()
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
