package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.UserPersona

/**
 * The fluent self's half of the profile: what a talk taught it about the
 * PERSON. A learner tells their future self about their job once, out loud,
 * and expects it known next week — so it is written into the same profile
 * they fill in by hand and read back through the persona block.
 */
object PersonaMemory {

    /**
     * The model re-tells the same fact differently every session, so notes
     * dedupe on a punctuation-stripped, lowercased key (iOS `dedupeKey`).
     */
    fun dedupeKey(text: String): String =
        text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString(" ")

    /** Newest 40 survive — this is a notebook, not a transcript. */
    fun absorb(persona: UserPersona, notes: List<PersonaNote>, limit: Int = 40): UserPersona {
        val seen = persona.learnedNotes.map { dedupeKey(it.text) }.toMutableSet()
        val kept = persona.learnedNotes.toMutableList()
        for (n in notes) {
            val k = dedupeKey(n.text)
            if (k.isEmpty() || !seen.add(k)) continue
            kept.add(n)
        }
        return persona.copy(learnedNotes = if (kept.size > limit) kept.takeLast(limit) else kept)
    }

    /**
     * Fold a talk's `about_user` lines in, and — for a plain FREE talk —
     * stamp `metAt`: that is what retires the first-call framing. A scenario
     * casts the model as a barista and a Find-people call as a stranger, and
     * neither of those met the learner.
     *
     * Not `savePersona`: this must not wipe topic suggestions or re-publish
     * the Find-people intro on every talk end, and these lines must never
     * reach the pool — something said to your own future self was not said
     * to strangers.
     */
    suspend fun remember(context: Context, notes: List<PersonaNote>, metAt: Long?) {
        val store = PersonaStore.shared(context)
        var p = store.load() ?: return
        p = absorb(p, notes)
        if (metAt != null && p.metAt == null) p = p.copy(metAt = metAt)
        store.save(p)
        StoreEvents.bump()
    }
}
