package com.roro.futurevoice.data

/**
 * Weekly test prompts lifted byte for byte from iOS `WeeklyTestEngine`
 * (2026-11-08). Same contract as `talk/LiftedPrompts`, which is generated
 * from a committed iOS ref; these were lifted from the working tree, so they
 * live here until the generator's ref moves past them.
 */
object WeeklyTestPrompts {
    /** iOS `notARuleLine`: what sounds like a slip and is not one in this
     *  language. Empty for the rest, so their prompts stay as measured. */
    fun notARuleLine(language: String): String = when (language) {
        "ko" -> " In Korean, a particle left out in speech and 이/가 on the object of -고 싶다 are normal, not mistakes."
        "ja" -> " In Japanese, choosing は or が before a negative is nuance, and a particle left out in casual speech is normal: neither is a mistake."
        else -> ""
    }

    fun translateSystem(targetName: String, nativeName: String, level: String, drafts: Int, topics: String, language: String): String =
            "You write a short translation quiz for a " +
            targetName +
            " learner whose own language is " +
            nativeName +
            ", level " +
            level +
            ". They answer by laying word tiles in order. You get mistakes they really made.\n\nFirst decide which mistakes can be asked about at all. One qualifies only when a grammar RULE of " +
            targetName +
            " was broken and the same rule could be broken again in a different sentence. Leave out word choice, a sentence the speaker broke off or restarted, words lost to hesitation, and anything a speech recognizer could have caused." +
            notARuleLine(language) +
            "\n\nPick up to " +
            drafts +
            " that qualify, each a DIFFERENT grammar point, and for each write ONE new everyday sentence in which a learner who still has that habit would make THE SAME mistake again.\n\nReturn {\"items\":[{\"source\":n,\"point\":\"...\",\"answer\":\"...\",\"native\":\"...\",\"wrong\":\"...\",\"orders\":[\"...\"],\"decoys\":[\"...\"],\"tip\":\"...\"}]}, keys in that order.\n- source: the number of the mistake it is built on.\n- answer: the " +
            targetName +
            " sentence, the most natural way to say it, at their   level, 5–12 words, about ordinary life (these were their topics:   " +
            topics +
            "), correctly punctuated. NOT their original   sentence. Its words are the tiles, so there must be ONE wording: no   optional words, nothing a learner could naturally say differently with   other words.\n- native: that sentence in " +
            nativeName +
            ", casual and spoken, the way they'd   say it to a friend. Translate the answer and add nothing: no idea in   native that is missing from answer, none in answer that is missing from   native, the same tense and time.\n- wrong: the answer with THAT mistake made again and nothing else changed.   If you cannot write it, this sentence does not test the mistake: write   another.\n- orders: every OTHER order of exactly the same words that is just as   correct. Go through each time, place and duration phrase and each   adverb, and list the sentence with it at the front too wherever that   is natural. [] only if the order is truly fixed.\n- decoys: 1–3 single words from wrong that are not in answer. Before   keeping one, try to build a correct sentence of the same meaning with   it, in any position, using the other words: if you can, it is not a   decoy.\n- point: the grammar point in " +
            nativeName +
            ", 2–5 words. tip: one line in   " +
            nativeName +
            ", at most 14 words, that a teacher would sign: TRUE for THIS   sentence, showing the pattern as the answer uses it. Never a rule you   are unsure of. Write it in the polite everyday register an app speaks   in (Korean 해요체, never 합니다체; Japanese です・ます).\nJSON only."

    fun solveSystem(t: String, n: String): String =
            "A learner sees a sentence in " +
            n +
            " and word tiles in " +
            t +
            ". Not every tile has to be used, and each can be used only as many times as it appears. For each numbered item, list EVERY sentence that can be built from the tiles and is correct, natural " +
            t +
            " saying what the " +
            n +
            " sentence says. Try each tile: casual everyday speech counts, and a different word order or construction counts. List nothing that is wrong.\n\nReturn {\"results\":[{\"n\":1,\"sentences\":[\"...\"]}]}. JSON only."

    fun reviewSystem(t: String, n: String, language: String): String =
            "You review translation quiz items for " +
            t +
            " learners whose own language is " +
            n +
            ", built on a mistake the learner really made. You did not write them. Be strict.\n\nFor each numbered item decide:\n- rule: was the earlier mistake a broken grammar rule of " +
            t +
            "? false when   the earlier wording is also acceptable (casual speech, an optional   particle, a matter of nuance or preference), and for word choice, a   sentence the speaker broke off, hesitation, or a recognizer's error." +
            notARuleLine(language) +
            "\n- repeats: could a learner with that same habit make the SAME mistake in   this new sentence?\n- same_meaning: does the answer say exactly what the " +
            n +
            " sentence says,   nothing left out or added, the same tense?\n- correct: is the answer correct, natural " +
            t +
            ", in every word form?\n- tip_true: is the tip true as written, for this sentence and in general?   true when there is no tip.\n\nReturn {\"results\":[{\"n\":1,\"rule\":true,\"repeats\":true,\"same_meaning\":true,\"correct\":true,\"tip_true\":true}]}. JSON only."

    fun meaningSystem(target: String, native: String): String =
            "You check vocabulary questions for " +
            target +
            " learners whose own language is " +
            native +
            ". Each numbered question has a meaning in " +
            native +
            " and four " +
            target +
            " words. List EVERY word the meaning correctly describes, in any common sense of the word. Judge each word on its own; more than one may fit.\nReturn {\"results\":[{\"n\":1,\"fit\":[\"word\", ...]}]}. JSON only."

    fun secondReadSystem(name: String): String =
            "A learner laid word tiles to say a " +
            name +
            " sentence, and it is not the model answer. Decide whether what they laid is ALSO a right answer: correct, natural " +
            name +
            " that says what the sentence asks, something a careful teacher would accept. Another wording or order is fine. The quiz tests one grammar point, given below with the learner's earlier mistake: a sentence that makes that same mistake again is NOT right, even if a listener would understand it.\nReturn {\"right\": true} or {\"right\": false}. JSON only."
}
