// A learner who can't find the words says them in their OWN language
// (2026-10-08). Measured on real calls: a Korean learner of English said
// "가벼운", "일단", "나는 즐기기로 마음 먹었기 때문에…" mid-call — and until this
// file the re-read (reread.ts), told to write English only, turned each into
// an English sentence nobody said ("a cupboard", "I mean enjoy as long as
// it's fun"), which the fluent self then answered and the coach corrected.
//
// Now the re-read says WHICH language was spoken, and a native line reaches
// the reply model as what it is. The learner's bubble shows exactly what
// they said; only the model's copy carries this note, so the app's system
// prompt stays byte-identical and the note costs nothing on every other turn.
/** The learner's line as the reply model sees it when (part of) it was said
 *  in their native language. `t` / `n` are language NAMES ("English"), from
 *  transcriber.ts `languageName` — taken as arguments so this file imports
 *  nothing and the probe can load it on its own. */
export function nativeTurnText(said: string, t: string, n: string): string {
  return [
    said,
    "",
    `[Note, not part of what they said: they said this in ${n}, their own language — they couldn't find the ${t}. ` +
    `Answer in ${t} only, never ${n}. Inside your reply, give them the ${t} way to say what they meant, ` +
    `once, short and at their level, as a friend would ("Oh, light — a light bag?"), not as a lesson. ` +
    `Then carry on the conversation as usual.]`,
  ].join("\n")
}
