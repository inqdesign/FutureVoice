// Coach mode's steer, carried on the learner's last turn (2026-10-08).
//
// It used to be appended to the system instruction. The system instruction
// is now an explicit Gemini cache (reply.ts) — the same ~5k tokens re-sent on
// every generation were 60% of the Gemini bill, and a cached request may not
// carry a system instruction of its own — so the steer rides where the
// native-language note already does: on the model's copy of the learner's
// line, never on screen. Measured against the old placement with
// test/probe-steer-placement.mjs before it shipped.
export function steerTurnText(said: string, steer: string): string {
  return `${said}\n\n[Note for you, not part of what they said:\n${steer}]`
}
