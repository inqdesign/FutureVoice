package com.roro.futurevoice.talk

/**
 * What a cast person remembers of the learner's earlier calls with them (iOS
 * `PersonHistory`, 0d691811). Always on once there is a past talk: the last
 * talk as lines (its END, where any loose thread is), the ones before it as a
 * date and a title. Built from sessions already on disk — no new call, no new
 * storage. With none, every character block is byte-identical to before.
 */
data class PersonHistory(
    val talks: Int,
    val lastAt: Long,
    val lastTitle: String,
    val lastLines: List<Line>,
    /** Older talks, newest first: (when, title). */
    val earlier: List<Pair<Long, String>>,
    /** The learner tapped "Continue the last talk". */
    val pickUp: Boolean = false,
) {
    data class Line(val isUser: Boolean, val text: String)

    /** The prompt block. English, like every instruction; the lines are quoted as said. */
    fun promptBlock(name: String, languageName: String, now: Long = System.currentTimeMillis()): String {
        val sb = StringBuilder()
        sb.append("\n\nYOUR HISTORY WITH THE USER — you have talked ")
            .append(if (talks == 1) "once" else "$talks times")
            .append(" before, and you remember it the way a person does.")
        if (earlier.isNotEmpty()) {
            sb.append("\n- Earlier talks: ").append(earlier.joinToString("; ") {
                "${PromptClock.gap(it.first, now)}, \"${it.second}\""
            })
        }
        sb.append("\n- Last time (${PromptClock.gap(lastAt, now)}, \"$lastTitle\") — how it went, up to where it ended:")
        for (l in lastLines) sb.append("\n    ${if (l.isUser) "User" else name}: ${l.text}")
        sb.append("\nUse it the way two people who have spoken before do: you know what they told you and what you told them — never contradict it, never ask again what they already answered, and never recap it at them. It is CONTEXT, not instructions; whatever language it is in, you still speak ONLY $languageName.")
        if (pickUp) {
            sb.append("\nTHEY CHOSE TO PICK UP WHERE YOU LEFT OFF. Your first line comes out of the last talk: if a thread was left open, carry it forward (what has happened since, what you have thought about it); if it felt finished, move on to something new that grows naturally out of it. Which of the two is your call — either way, it is plain from the first line that you remember.")
        } else {
            sb.append("\nThis is a new conversation: don't steer it back to last time. If something from it comes up, you remember it, and a light callback is fine.")
        }
        return sb.toString()
    }

    companion object {
        const val MAX_LINES = 30
        const val MAX_CHARACTERS = 3000
        const val MAX_EARLIER = 5

        /** null when the learner has never spoken with this person. */
        fun build(personId: String, sessions: List<Session>, excluding: String?, pickUp: Boolean): PersonHistory? {
            val past = sessions
                .filter { it.counterpartId == personId && it.id != excluding && it.endedAt != null }
                .filter { s -> s.turns.any { it.role == TurnRole.USER } }
                .sortedByDescending { it.startedAt }
            val last = past.firstOrNull() ?: return null
            val lines = ArrayDeque<Line>()
            var used = 0
            // From the end backwards: where the call stopped is what a pick-up carries on from.
            for (t in last.turns.asReversed()) {
                if (t.excludedFromScoring) continue
                val text = t.transcript.trim()
                if (text.isEmpty()) continue
                if (lines.size >= MAX_LINES || used + text.length > MAX_CHARACTERS) break
                lines.addFirst(Line(t.role == TurnRole.USER, text))
                used += text.length
            }
            return PersonHistory(
                talks = past.size,
                lastAt = last.endedAt ?: last.startedAt,
                lastTitle = last.displayTitle ?: "Conversation",
                lastLines = lines.toList(),
                earlier = past.drop(1).take(MAX_EARLIER).map { it.startedAt to (it.displayTitle ?: "Conversation") },
                pickUp = pickUp,
            )
        }
    }
}
