package com.roro.futurevoice.talk

import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.net.PublicPersonaClient

/**
 * What the learner and the person they're talking to actually have in
 * common, worked out in CODE before any prompt is written (iOS
 * `CommonGround`). Two strangers don't open on a randomly chosen fact from
 * one side's biography — they find the overlap and start there. With a thin
 * intro the model had almost nothing to pick, so it invented; if code can
 * work it out, the model doesn't get to guess at it.
 */
object CommonGround {
    /** The other side, whichever shape it came in. */
    class Party(val location: String, val intro: String, val background: String,
                val commonTopics: String, val occupationLike: String, val isUser: Boolean)

    fun of(c: Counterpart) = Party(c.location, c.intro, c.background, c.commonTopics,
        // Own personas keep the work in the free-text background; pool rows in the intro.
        listOf(c.relationship, c.background).joinToString(" "), c.personaKind == "user")
    fun of(p: PublicPersonaClient.PublicPersona) = Party(p.location, p.intro, "", "",
        listOf(p.occupation, p.interests).joinToString(" "), p.isRealUser)

    /** One line per thing the two genuinely share, most concrete first. */
    fun between(learner: UserPersona?, other: Party): List<String> {
        val p = learner ?: return emptyList()
        val found = mutableListOf<String>()
        // Same place beats every other overlap: it gives a scene somewhere to be.
        val theirPlace = other.location.lowercase()
        for (mine in listOf(p.city, p.country)) {
            if (mine.isNotEmpty() && theirPlace.contains(mine.lowercase())) { found += "both in $mine"; break }
        }
        val theirs = (other.commonTopics + " " + other.occupationLike).lowercase()
        for (interest in p.interests) {
            val needle = interest.trim().lowercase()
            if (needle.length >= 3 && theirs.contains(needle)) found += "both into $interest"
        }
        // Same shape of life — what people actually bond over on meeting.
        val theirText = listOf(other.intro, other.background, other.commonTopics, other.location).joinToString(" ").lowercase()
        if (p.household.isNotEmpty() && mentionsFamily(p.household) && mentionsFamily(theirText)) found += "both have kids at home"
        if (other.isUser) found += "both learning this language, and both know what it is to be the slowest person in the room"
        return found
    }

    /** The block to splice into a prompt. Never invents an overlap. */
    fun block(learner: UserPersona?, other: Party): String {
        val shared = between(learner, other)
        if (shared.isEmpty()) return "COMMON GROUND: none found. Don't force one. Open on something concrete from YOUR OWN life (the person you are), the way a real person offers a piece of themselves first, and let the learner pick up whatever interests them."
        return "COMMON GROUND — start here, this is what you two actually share:\n" +
            shared.joinToString("\n") { "- $it" } +
            "\nReal strangers open on the overlap, not on a fact plucked from one side's biography. Take one of these and get specific about it fast."
    }

    private val markers = listOf("kid", "child", "children", "son", "daughter", "kita", "school", "baby", "toddler",
        "아이", "아들", "딸", "육아", "kind", "kinder", "tochter", "sohn")
    private fun mentionsFamily(text: String): Boolean { val l = text.lowercase(); return markers.any { l.contains(it) } }
}
