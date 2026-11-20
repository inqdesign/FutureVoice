// A letter on its own is something no voice reads right. The pronunciation
// call names sounds, and the model writes them as letters however it is
// told not to (probe, 2026-11-20): "ㅓ와 ㅗ 소리", "처음 ㄸ 소리",
// 「っ」の練習. The founder heard "ㅓ와 ㅗ" come out as noise. So before a
// line is spoken, a lone Korean letter becomes what a Korean teacher says
// out loud (a vowel its syllable, 어; a consonant its name, 쌍디귿), and a
// lone Japanese small tsu or long mark becomes its name (小さいつ, のばす音).
// "Lone" is the point: a run of letters (ㅋㅋ, ㅎㅎ) is laughter, and a mark
// inside a word (待って, ビール) is the word; both are left alone.
//
// Not length-preserving: the call voice sends text without timestamps. The
// screen keeps what the model wrote.

const KO_CONSONANT: Record<string, string> = {
  "ㄱ": "기역", "ㄲ": "쌍기역", "ㄴ": "니은", "ㄷ": "디귿", "ㄸ": "쌍디귿",
  "ㄹ": "리을", "ㅁ": "미음", "ㅂ": "비읍", "ㅃ": "쌍비읍", "ㅅ": "시옷",
  "ㅆ": "쌍시옷", "ㅇ": "이응", "ㅈ": "지읒", "ㅉ": "쌍지읒", "ㅊ": "치읓",
  "ㅋ": "키읔", "ㅌ": "티읕", "ㅍ": "피읖", "ㅎ": "히읗",
}

function koLetter(ch: string): string {
  const c = ch.codePointAt(0)!
  // ㅏ (U+314F) … ㅣ (U+3163): the syllable with the silent ㅇ, 아 … 이.
  if (c >= 0x314f && c <= 0x3163) return String.fromCodePoint(0xc544 + (c - 0x314f) * 28)
  return KO_CONSONANT[ch] ?? ch
}

const KO_JAMO = /[ㄱ-ㅣ]+/g
const LETTER = /\p{L}/u
const JA_MARK: Record<string, string> = { "っ": "小さいつ", "ッ": "小さいツ", "ー": "のばす音" }

export function speakableLetters(text: string): string {
  let out = text
  if (/[ㄱ-ㅣ]/.test(out)) {
    out = out.replace(KO_JAMO, (run) => (run.length === 1 ? koLetter(run) : run))
  }
  if (/[っッー]/.test(out)) {
    const chars = Array.from(out)
    out = chars.map((ch, i) => {
      const name = JA_MARK[ch]
      if (!name) return ch
      const before = chars[i - 1] ?? ""
      // A mark after a letter (kana, kanji, or ー after ー) belongs to the word.
      if (LETTER.test(before) || before === "ー") return ch
      return name
    }).join("")
  }
  return out
}
