package com.roro.futurevoice.data

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File

/**
 * One learner's "student file" (docs/personal-report-plan.md, part 2; iOS
 * `LearnerState`, 465331f6): where they stand on every item of the level map,
 * built from what they actually said. Founder, 2026-10-30: one file every part
 * of the app can read — the tutor chat answers from it, the planner (step 4)
 * will build the week from it. Behind the scenes only: no screen draws it.
 *
 * **Stored per TALK, read per ITEM.** What is on disk is each tagged talk's
 * verified verdicts ([SessionTag]), keyed by session id; the per-item counts,
 * dates, quotes and status are computed on read ([items]). That makes tagging
 * idempotent by construction — a talk tagged twice replaces its own entry
 * instead of counting twice — and a talk that grew (resumed, or a line marked
 * misheard) is re-tagged and replaces its old contribution.
 */
@Serializable
data class LearnerState(
    val version: Int = 1,
    /** Tagged talks, keyed by `Session.id`. */
    val sessions: Map<String, SessionTag> = emptyMap(),
    /** Failed tagging attempts per talk. A talk that fails [MAX_FAILURES]
     *  times is not tried again — a decode that always fails would otherwise
     *  be one paid call per launch, forever. */
    val failures: Map<String, Int> = emptyMap(),
    /** Which [FAILURES_EPOCH] the counts above belong to. Null on a file from
     *  before the epochs. */
    val failuresEpoch: Int? = null,
) {
    /** The same state with failure counts from an older epoch dropped, so
     *  those talks are tried again. */
    fun clearingOldFailures(): LearnerState =
        if (failuresEpoch == FAILURES_EPOCH) this
        else copy(failures = emptyMap(), failuresEpoch = FAILURES_EPOCH)

    @Serializable
    data class SessionTag(
        /** When the talk happened (its last line) — the dates on an item. */
        @Serializable(with = IsoDateMillisSerializer::class)
        val talkDate: Long,
        @Serializable(with = IsoDateMillisSerializer::class)
        val taggedAt: Long,
        /** `LevelTagger.fingerprint` of the learner lines it was tagged from. */
        val fingerprint: String,
        /** The map version it was tagged against. A new map re-tags. */
        val mapVersion: Int,
        val items: List<ItemTag>,
    )

    @Serializable
    enum class Kind { @SerialName("grammar") GRAMMAR, @SerialName("function") FUNCTION }

    /** One item's verdict in one talk. Quotes are the learner's own words,
     *  checked in code (`LevelTagger.isTheirs`). */
    @Serializable
    data class ItemTag(
        val id: String,
        val kind: Kind,
        val right: Int,
        val wrong: Int,
        val quotes: List<Quote>,
    )

    @Serializable
    data class Quote(
        val text: String,
        /** A right use or the error. */
        val right: Boolean,
        /** Filled from the talk's date when the item is read. */
        @Serializable(with = IsoDateMillisSerializer::class)
        val date: Long? = null,
    )

    /** Where a learner stands on one item. Decided by [status] from the
     *  counts, never by a model. */
    enum class Status {
        UNSEEN, TRIED, SHAKY, SOLID;

        /** Order of WORK: the closest to done first (shaky, then tried), then
         *  what has never come up; solid is done. */
        val workRank: Int get() = when (this) {
            SHAKY -> 0
            TRIED -> 1
            UNSEEN -> 2
            SOLID -> 3
        }
    }

    /** One map item as the learner stands on it. */
    data class ItemState(
        val id: String,
        val kind: Kind,
        val level: CefrLevel,
        val name: String,
        val requires: List<String>,
        val right: Int = 0,
        val wrong: Int = 0,
        /** Talks in which it came up at all, and in which it came up right. */
        val talks: Int = 0,
        val rightTalks: Int = 0,
        val firstSeen: Long? = null,
        val lastSeen: Long? = null,
        /** Up to three of the learner's own lines, newest first. */
        val quotes: List<Quote> = emptyList(),
    ) {
        val status: Status get() = status(right = right, wrong = wrong, rightTalks = rightTalks)
    }

    /** Every map item, in map order, with this learner's counts folded in. */
    fun items(map: LevelMap): List<ItemState> {
        val states = HashMap<String, ItemState>()
        for (g in map.grammar) {
            states[g.id] = ItemState(id = g.id, kind = Kind.GRAMMAR, level = g.level,
                name = g.name, requires = g.requires)
        }
        for (f in map.functions) {
            states[f.id] = ItemState(id = f.id, kind = Kind.FUNCTION, level = f.level,
                name = f.name, requires = emptyList())
        }
        val quotes = HashMap<String, MutableList<Quote>>()
        for (tag in sessions.values) {
            for (item in tag.items) {
                val s = states[item.id] ?: continue
                states[item.id] = s.copy(
                    right = s.right + item.right,
                    wrong = s.wrong + item.wrong,
                    talks = s.talks + 1,
                    rightTalks = s.rightTalks + if (item.right > 0) 1 else 0,
                    firstSeen = minOf(s.firstSeen ?: tag.talkDate, tag.talkDate),
                    lastSeen = maxOf(s.lastSeen ?: tag.talkDate, tag.talkDate),
                )
                quotes.getOrPut(item.id) { mutableListOf() } += item.quotes.map { it.copy(date = tag.talkDate) }
            }
        }
        for ((id, qs) in quotes) {
            // Newest talk first; within a talk the error before the right use,
            // which is the order the tagger wrote them in.
            val ordered = qs.withIndex().sortedWith { a, b ->
                val da = a.value.date ?: Long.MIN_VALUE
                val db = b.value.date ?: Long.MIN_VALUE
                if (da != db) db.compareTo(da) else a.index.compareTo(b.index)
            }.map { it.value }
            states[id] = states.getValue(id).copy(quotes = ordered.take(MAX_QUOTES_PER_ITEM))
        }
        return (map.grammar.map { it.id } + map.functions.map { it.id }).mapNotNull { states[it] }
    }

    companion object {
        const val MAX_FAILURES = 2
        /** Bump when a fix makes old failures meaningless. 1 (2026-11-09):
         *  talks given up on because of the 4096 ceiling, the refused
         *  retries, and tagging before sign-in. */
        const val FAILURES_EPOCH = 1

        /** SOLID takes three right uses spread over at least two talks, with
         *  at most one error in five. One good talk is not command of a
         *  structure (it may have been one lucky sentence), and a structure
         *  that keeps breaking is not command either, however often it is
         *  reached for. */
        const val SOLID_RIGHT_USES = 3
        const val SOLID_TALKS = 2
        const val SOLID_ACCURACY = 0.8

        const val MAX_QUOTES_PER_ITEM = 3

        /**
         * The status rule, all of it:
         * - **unseen** — never produced.
         * - **solid** — [SOLID_RIGHT_USES]+ right uses in [SOLID_TALKS]+ talks,
         *   and right in at least [SOLID_ACCURACY] of all tries.
         * - **shaky** — not solid, and at least one error on file.
         * - **tried** — produced right, never wrong, not yet enough to be solid.
         * Counts are ALL-TIME on purpose for now: an early error is outweighed
         * by right uses as they pile up. Weighting recent talks is the
         * planner's question (step 4), not the file's.
         */
        fun status(right: Int, wrong: Int, rightTalks: Int): Status {
            val total = right + wrong
            if (total == 0) return Status.UNSEEN
            if (right >= SOLID_RIGHT_USES && rightTalks >= SOLID_TALKS &&
                right.toDouble() >= SOLID_ACCURACY * total.toDouble()) {
                return Status.SOLID
            }
            return if (wrong > 0) Status.SHAKY else Status.TRIED
        }
    }
}

/**
 * `filesDir/lang/<code>/learner_state.json`, one file per target language
 * (iOS `LearnerStateStore`).
 *
 * Every call names its language, so a switch has nothing to repoint.
 * Device-local and not synced — it is derived from the talks, which do sync,
 * and the other device builds its own from them.
 */
class LearnerStateStore(
    /** Injected by tests; the app writes under [LanguageScope]. */
    private val directory: (String) -> File,
    /** The learner's level in a language, when [promptLines] isn't given one. */
    private val levelSetting: (String) -> CefrLevel? = { null },
) {
    companion object {
        const val FILENAME = "learner_state.json"

        /** The most lines [promptLines] returns, header included. */
        const val MAX_PROMPT_LINES = 25

        @Volatile private var instance: LearnerStateStore? = null

        fun shared(context: Context): LearnerStateStore =
            instance ?: synchronized(this) {
                instance ?: run {
                    val app = context.applicationContext
                    LevelMap.init(app)
                    LearnerStateStore(
                        directory = { LanguageScope.directory(app, it) },
                        levelSetting = { code ->
                            LanguageScope.level(app, code, "").takeIf { it.isNotEmpty() }
                                ?.let { raw -> CefrLevel.entries.firstOrNull { it.code == raw } }
                        },
                    ).also { instance = it }
                }
            }

        /** The pure half of [promptLines], for tests. */
        fun promptLines(items: List<LearnerState.ItemState>, level: CefrLevel,
                        talks: Int, language: String): String {
            val order = CefrLevel.entries
            fun rank(l: CefrLevel) = order.indexOf(l)
            // The map stops at its top step; a learner above it is read against it.
            val top = items.maxByOrNull { rank(it.level) }?.level ?: CefrLevel.B2
            val currentRank = minOf(rank(level), rank(top))
            val nextRank = minOf(currentRank + 1, rank(top))
            val next = order[nextRank]

            val grammar = items.filter { it.kind == LearnerState.Kind.GRAMMAR && rank(it.level) <= nextRank }
            val functions = items.filter { it.kind == LearnerState.Kind.FUNCTION && rank(it.level) <= nextRank }

            val lines = mutableListOf("LEARNER STATE — $language level map, from $talks tagged talk${if (talks == 1) "" else "s"}; level ${order[currentRank].code.uppercase()}, next ${next.code.uppercase()}.")

            val solid = grammar.filter { it.status == LearnerState.Status.SOLID }
            lines += "Solid: " + (if (solid.isEmpty()) "none yet" else solid.joinToString("; ") { it.name })

            // Gaps to name: anything begun, plus never-seen items at the
            // current and next level.
            val gaps = grammar.filter {
                when (it.status) {
                    LearnerState.Status.SOLID -> false
                    LearnerState.Status.SHAKY, LearnerState.Status.TRIED -> true
                    LearnerState.Status.UNSEEN -> rank(it.level) >= currentRank
                }
            }
            val ordered = workOrder(gaps, ::rank)

            val functionLines = 2
            val budget = MAX_PROMPT_LINES - lines.size - 1 - functionLines
            if (ordered.isNotEmpty()) lines += "Next to work on, in order:"
            for (item in ordered.take(maxOf(0, budget))) {
                val tag = "${item.name} (${item.id}, ${item.level.code.uppercase()})"
                when (item.status) {
                    LearnerState.Status.SHAKY -> {
                        val q = item.quotes.firstOrNull { !it.right } ?: item.quotes.firstOrNull()
                        lines += "- $tag: shaky, ${item.right} right / ${item.wrong} wrong" + quoted(q)
                    }
                    LearnerState.Status.TRIED ->
                        lines += "- $tag: tried, ${item.right} right in ${item.rightTalks} talk${if (item.rightTalks == 1) "" else "s"}" + quoted(item.quotes.firstOrNull())
                    LearnerState.Status.UNSEEN -> lines += "- $tag: not heard yet"
                    LearnerState.Status.SOLID -> Unit
                }
            }

            val done = functions.filter { it.status != LearnerState.Status.UNSEEN }
            val notYet = functions.filter { it.status == LearnerState.Status.UNSEEN }
            lines += "Can do: " + (if (done.isEmpty()) "nothing tagged yet" else done.joinToString("; ") { it.name })
            if (notYet.isNotEmpty()) {
                lines += "Not done yet: " + notYet.joinToString("; ") { it.name }
            }
            return lines.take(MAX_PROMPT_LINES).joinToString("\n")
        }

        private fun quoted(q: LearnerState.Quote?): String {
            if (q == null || q.text.isEmpty()) return ""
            return "; they said: \"${q.text}\""
        }

        /** Kahn's order over the gaps: an item waits for every gap it
         *  requires; among the free ones, shaky → tried → unseen, then lower
         *  level, then map order. */
        fun workOrder(gaps: List<LearnerState.ItemState>,
                      rank: (CefrLevel) -> Int): List<LearnerState.ItemState> {
            val ids = gaps.map { it.id }.toSet()
            val index = gaps.withIndex().associate { (i, item) -> item.id to i }
            val waiting = gaps.toMutableList()
            val emitted = HashSet<String>()
            val out = mutableListOf<LearnerState.ItemState>()
            while (waiting.isNotEmpty()) {
                val free = waiting.filter { item ->
                    item.requires.all { it !in ids || it in emitted }
                }
                // A cycle in the map would stall here; take everything left then.
                val pool = free.ifEmpty { waiting }
                val best = pool.minWithOrNull(
                    compareBy<LearnerState.ItemState>({ it.status.workRank }, { rank(it.level) },
                        { index[it.id] ?: 0 }))!!
                out += best
                emitted += best.id
                waiting.removeAll { it.id == best.id }
            }
            return out
        }
    }

    private val lock = Any()
    private val cache = HashMap<String, LearnerState>()
    private val json = StoreJson.json

    private fun key(language: String) = language.substringBefore('-')

    private fun file(language: String) = File(directory(key(language)), FILENAME)

    fun state(language: String): LearnerState = synchronized(lock) { loadLocked(language) }

    private fun loadLocked(language: String): LearnerState {
        cache[key(language)]?.let { return it }
        val state = runCatching {
            json.decodeFromString(LearnerState.serializer(), file(language).readText())
        }.getOrNull()?.clearingOldFailures() ?: LearnerState().clearingOldFailures()
        cache[key(language)] = state
        return state
    }

    private fun update(language: String, edit: (LearnerState) -> LearnerState) = synchronized(lock) {
        val state = edit(loadLocked(language))
        cache[key(language)] = state
        runCatching {
            val target = file(language)
            target.parentFile?.mkdirs()
            val tmp = File(target.parentFile, "$FILENAME.tmp")
            tmp.writeText(json.encodeToString(LearnerState.serializer(), state))
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }

    /** Whether this talk still needs a tagging call: never tagged, tagged
     *  from different lines or an older map, and not given up on. */
    fun needsTagging(sessionId: String, fingerprint: String, mapVersion: Int, language: String): Boolean {
        val state = state(language)
        if ((state.failures[sessionId] ?: 0) >= LearnerState.MAX_FAILURES) return false
        val tag = state.sessions[sessionId] ?: return true
        return tag.fingerprint != fingerprint || tag.mapVersion != mapVersion
    }

    /** Files (or REPLACES) one talk's verdicts. */
    fun record(tag: LearnerState.SessionTag, sessionId: String, language: String) = update(language) {
        it.copy(sessions = it.sessions + (sessionId to tag), failures = it.failures - sessionId)
    }

    fun recordFailure(sessionId: String, language: String) = update(language) {
        it.copy(failures = it.failures + (sessionId to (it.failures[sessionId] ?: 0) + 1))
    }

    /** Drops the verdicts of talks that no longer exist (deleted by the
     *  learner): what they said there is no longer on file anywhere else. */
    fun forgetSessions(notIn: Set<String>, language: String) {
        val stale = state(language).sessions.keys.filter { it !in notIn }
        if (stale.isEmpty()) return
        update(language) { it.copy(sessions = it.sessions - stale.toSet(), failures = it.failures - stale.toSet()) }
    }

    /** Every map item with this learner's standing; empty for a language
     *  with no map. */
    fun items(language: String): List<LearnerState.ItemState> {
        val map = LevelMap.load(language) ?: return emptyList()
        return state(language).items(map)
    }

    // MARK: - The block a prompt reads

    /**
     * A short plain-text block for a prompt (the tutor chat first): the path
     * to the step after the learner's level, as the plan orders it.
     *
     * - one line of what is SOLID up to that step;
     * - then every gap up to that step, in WORK order: an item never comes
     *   before an item it requires that is also a gap (past simple before
     *   present perfect), and among those that are free, shaky before tried
     *   before unseen, lower level first. Shaky and tried items carry one of
     *   the learner's own lines (an error, for shaky); unseen items are named
     *   only at the current and next level — a gap two levels down that never
     *   came up is more likely unheard than unknown;
     * - the functions, done and not yet, one line each.
     *
     * Empty when the language has no map or no talk has been tagged yet: a
     * file with nothing in it would read as "knows nothing", which is untrue.
     * Machine text, English; the quotes are the learner's words.
     *
     * [level] defaults to the learner's level setting in [language].
     */
    fun promptLines(language: String, level: CefrLevel? = null): String {
        val map = LevelMap.load(language) ?: return ""
        val state = state(language)
        if (state.sessions.isEmpty()) return ""
        val current = level ?: levelSetting(language) ?: CefrLevel.B1
        return promptLines(items = state.items(map), level = current,
            talks = state.sessions.size, language = LanguageCatalog.englishName(language))
    }
}
