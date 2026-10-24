// A slash between two words is READ ALOUD by the voice: "UI/UX" came out
// "UI slash UX" on every line of a tutor lesson (device, 2026-10-24), and the
// learner, hearing "slash" each time, took it as something to say. Nobody
// says the slash in "UI/UX" or "and/or", so the synthesizer gets a space
// there. The screen keeps the slash. Only between LETTERS: "1/2" and "24/7"
// are read as numbers and stay as written. LENGTH-PRESERVING (one character
// for one), like calmExclamations, so billing and a timestamped reply's
// character array line up; restoreCharacters puts the slash back.
//
// Twin of gateway/src/spoken-symbols.ts — keep the two identical.

const BETWEEN_LETTERS = /(?<=\p{L} ?)\/(?= ?\p{L})/gu

export function speakableSymbols(text: string): string {
  if (!text.includes("/")) return text
  return text.replace(BETWEEN_LETTERS, " ")
}
