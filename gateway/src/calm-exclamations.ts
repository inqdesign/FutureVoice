// "!" makes the voice SHOUT. Reported 2026-10-05: a line with an exclamation
// mark jumps in volume and sounds like yelling. Measured on the founder's
// clone (scripts/tts-exclaim-probe.sh, turbo, production settings): the same
// line with "!" came out 2–4 LUFS louder than with "." on 6 of 7 lines, Korean
// and English alike — and the "." take is the one picked by ear.
//
// So the synthesizer is sent a "." where the text has a "!". The screen keeps
// the "!" — only the voice is calmed. LENGTH-PRESERVING on purpose: billing
// counts the text's characters, and a timestamped reply indexes them, so one
// character is always swapped for exactly one (`restoreCharacters` puts the
// originals back into that reply).
//
// Twin of supabase/functions/_shared/calm-exclamations.ts — keep the two identical.

const BANG = new Set(["!", "！"])
const MARK = new Set(["!", "！", "?", "？"])

/** "!" → "." ("！" → "。"); next to another mark ("!?", "?!", "!!") the
 *  "!" becomes a space so only one mark is left to read. */
export function calmExclamations(text: string): string {
  if (!text.includes("!") && !text.includes("！")) return text
  const chars = Array.from(text)
  const out = chars.map((c, i) => {
    if (!BANG.has(c)) return c
    const wide = c === "！"
    const next = chars[i + 1] ?? ""
    const prev = chars[i - 1] ?? ""
    if (MARK.has(next) || prev === "?" || prev === "？") return wide ? "　" : " "
    return wide ? "。" : "."
  })
  return out.join("")
}

/** Put the original characters back into a timestamped reply's `characters`
 *  array wherever `calmExclamations` changed one — the app draws shadowing
 *  words from these and compares them to the line it shows. Only when the
 *  array lines up with the text one-for-one; otherwise left alone. */
export function restoreCharacters(characters: unknown, original: string, sent: string): void {
  if (!Array.isArray(characters)) return
  const o = Array.from(original), s = Array.from(sent)
  if (characters.length !== o.length || o.length !== s.length) return
  for (let i = 0; i < o.length; i++) {
    if (o[i] !== s[i] && characters[i] === s[i]) characters[i] = o[i]
  }
}
