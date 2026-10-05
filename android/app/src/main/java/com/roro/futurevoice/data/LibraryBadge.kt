package com.roro.futurevoice.data

/**
 * The badge in front of a library row (iOS `WordsView` / `ExpressionsView` /
 * `SentencesView` rows) — "Three states, and USED outranks KNOWN":
 *
 * - [STUDYING] bookmark: in the notebook. The bookmark wins on the row — Keep
 *   and I-know are opposite verdicts, and a used word the learner chose to
 *   keep studying must not light both.
 * - [KNOWN] plain check: the learner's own claim ("I know it" / "Got it").
 * - [USED] filled check: they said it in a talk — evidence, the top state.
 * - [NONE]: nothing to say yet.
 */
enum class LibraryBadge {
    NONE, STUDYING, KNOWN, USED;

    companion object {
        /**
         * @param studying in the notebook / bookmarked.
         * @param known known OR used (iOS: a word record of any state; an
         *   expression `hasUsedExpression`; a sentence card on the top rung).
         * @param used the talk's evidence (word record `.used`; expression
         *   count > 0; `DrillCard.usedInTalkAt`).
         */
        fun of(studying: Boolean, known: Boolean, used: Boolean): LibraryBadge = when {
            studying -> STUDYING
            used -> USED
            known -> KNOWN
            else -> NONE
        }
    }
}
