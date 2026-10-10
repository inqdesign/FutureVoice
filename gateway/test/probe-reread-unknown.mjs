// The wrong-script re-read when the app did NOT say which language the
// learner speaks (2026-10-10). Every build before 1.1.5 sends no
// `start.native`; the gateway guesses one only from Hangul or kana, so a
// final the live model wrote in Devanagari — what it writes for a Korean
// 어/아, or a short Korean line — went to the old "write <target> only"
// prompt, which invents a target sentence: "हम दो आए हैं" → "drohen kann",
// answered and corrected as if said (a real German learner on 1.1.4, 10-09).
//
// This runs the OLD prompt and the UNKNOWN-native classifying prompt
// (src/reread.ts `unknownNativeSystem`) over the same synthesized cases as
// probe-reread-native.mjs (Korean voices: real Korean, Hangul-read
// English/German/Japanese, fillers) plus a few short Korean lines.
//
//   node test/probe-reread-unknown.mjs [runs=2]
// Audio is shared with probe-reread-native.mjs (test/.reread-native/).
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs"

const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const env = (k) => process.env[k] ?? vars.match(new RegExp(`^${k}\\s*=\\s*"?([^"\\n]+)`, "m"))?.[1]
const GEMINI = env("GEMINI_API_KEY"), ELEVEN = env("ELEVENLABS_API_KEY")
const runs = Number(process.argv[2] ?? 2)
const model = "gemini-3.1-flash-lite"
const VOICES = ["NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0"]   // 시안, 민준

// Same order and indices as probe-reread-native.mjs (the cache is keyed by
// index); "native" there is "other" here. New cases go at the END, tagged.
const CASES = [
  ["나는 즐기기로 마음 먹었기 때문에 재밌을 때까지만 할 거야.", "en", "other"],
  ["이거 포인트 어떻게 뽑죠?", "de", "other"],
  ["내 차도 수리해야 되는데.", "de", "other"],
  ["연말 정산, 어, 13월의 월급.", "de", "other"],
  ["가벼운", "en", "other"],
  ["일단", "en", "other"],
  ["어, 그래야겠지만, 어.", "en", "other"],
  ["그걸 영어로 뭐라고 하지?", "en", "other"],
  ["잘 모르겠어요. 너무 어려워.", "en", "other"],
  ["회사에서 회의가 너무 많아서 피곤해.", "en", "other"],
  ["이히 트링케 마이넨 카페 미트 밀히.", "de", "target"],
  ["이히 에세 마이스텐스 모르겐스 브로트.", "de", "target"],
  ["야, 만히말 레제 이히 아이네 슈툰데.", "de", "target"],
  ["나인, 이히 게에 아인파흐 디렉트 나흐 하우제.", "de", "target"],
  ["아이 고 투 워크 바이 버스 에브리 데이.", "en", "target"],
  ["마이 도터 이즈 식스 이어즈 올드.", "en", "target"],
  ["아이 디사이디드 투 엔조이 잇 애즈 롱 애즈 잇츠 펀.", "en", "target"],
  ["예스, 아이 띵크 소.", "en", "target"],
  ["아이 라이크 커피 앤드 티.", "en", "target"],
  ["웰, 아이 원트 투 레스트 투데이.", "en", "target"],
  ["家で映画をみた。", "ja", "target", "ja"],
  ["全然ない。", "ja", "target", "ja"],
  ["十分ぐらいなら大丈夫だよ。", "ja", "target", "ja"],
  ["サーモンが好きやん。", "ja", "target", "ja"],
  ["ほら、絵が上手でしょう。", "ja", "target", "ja"],
  ["最近ちいかわのシリーズが終わっちゃった。", "ja", "target", "ja"],
  ["えっと、日本語で話します。", "ja", "target", "ja"],
  ["최근 K-pop에 빠져서 아이돌 노래를 자주 들어.", "ja", "other"],
  ["음, 10분 정도면 괜찮아요.", "ja", "other"],
  ["잘 잤어.", "ja", "other"],
  ["그걸 일본어로 뭐라고 해?", "ja", "other"],
  ["호랑이가 나오는 영화.", "ja", "other"],
  ["음…", "en", "none"],
  ["어… 어…", "de", "none"],
  // Short Korean, the kind the live model writes in Devanagari.
  ["몰라.", "de", "other", "ko", "x"],
  ["맞아 맞아.", "de", "other", "ko", "x"],
  ["우리 둘이 왔어요.", "de", "other", "ko", "x"],
  ["아 잠깐만.", "en", "other", "ko", "x"],
  ["어… 음… 아…", "en", "none", "ko", "x"],
]

const name = { en: "English", de: "German", ko: "Korean", ja: "Japanese" }

function pin(code) {
  const n = name[code]
  return [
    `You transcribe a language LEARNER speaking ${n}. Write down exactly what you hear, word for word.`,
    `The language is settled before you hear anything: the speaker is speaking ${n}, and every line you write is ${n}. That holds for the first words of an utterance, when you have heard almost nothing yet, and for short replies that sound the same in several languages — write those in ${n} too.`,
    `The speaker has a foreign accent, hesitates, and makes grammar mistakes. That is what a learner sounds like. It is never evidence that they switched to another language, and never a reason to write their words in another language, another spelling or another script.`,
    `Hesitation sounds — uh, um, a drawn-out vowel before the first word — belong to the ${n} utterance too. Write them the way ${n} writes a filler, or leave them out; they are never a word of another language and never another script.`,
    `Never translate and never correct — their mistakes are the material. If part of an utterance is unintelligible, write the ${n} words you are sure of and leave the rest out; do not fill the gap with another language.`,
  ].join("\n")
}

function oldBody(target, wavB64) {
  const n = name[target]
  return {
    systemInstruction: { parts: [{ text: [pin(target),
      `The audio may begin or end with silence or a little of another voice; transcribe only the learner's ${n}.`,
      `Reply with the transcript alone, in ${n} and in ${n}'s own writing system — no quotes, no notes. If the audio holds only hesitation sounds or no words at all, reply with nothing.`,
    ].join("\n") }] },
    contents: [{ role: "user", parts: [
      { inlineData: { mimeType: "audio/wav", data: wavB64 } }, { text: `Transcribe this ${n}.` }] }],
    generationConfig: { maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" } },
  }
}

// Must stay byte-identical to src/reread.ts `unknownNativeSystem`.
export function unknownSystem(target) {
  const t = name[target]
  return [
    `You hear one utterance from someone learning ${t}, in the middle of a ${t} conversation. Their own language is not known. Decide which language they actually SPOKE, then transcribe it.`,
    `"target": they spoke ${t} — however strong the accent, however broken the grammar, however much it sounds like another language. Words of ${t} pronounced with a foreign accent are still ${t}. Write it in ${t}'s own writing system, word for word, never corrected.`,
    `"other": they spoke a different language — real words and grammar of that language, the way they would talk to someone who speaks it. A learner who is stuck often switches to their own language. Write exactly what they said, in that language's own writing system. Never translate it into ${t}.`,
    `If most of it is ${t} with one or two words of another language inside, it is "target": write the ${t} words in ${t} and the other word as said.`,
    `"none": only hesitation sounds (uh, um, 어, 음, अ) or no words at all; text is empty.`,
    `Only write words you actually hear. Never invent a sentence to fill unclear audio.`,
  ].join("\n")
}

function newBody(target, wavB64) {
  return {
    systemInstruction: { parts: [{ text: unknownSystem(target) }] },
    contents: [{ role: "user", parts: [
      { inlineData: { mimeType: "audio/wav", data: wavB64 } }, { text: "Classify and transcribe this utterance." }] }],
    generationConfig: {
      maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" },
      responseMimeType: "application/json",
      responseSchema: { type: "OBJECT", properties: {
        language: { type: "STRING", enum: ["target", "other", "none"] },
        text: { type: "STRING" } }, required: ["language", "text"], propertyOrdering: ["language", "text"] },
    },
  }
}

function wav(pcm) {
  const h = Buffer.alloc(44)
  h.write("RIFF", 0); h.writeUInt32LE(36 + pcm.length, 4); h.write("WAVE", 8)
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22)
  h.writeUInt32LE(16000, 24); h.writeUInt32LE(32000, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write("data", 36); h.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([h, pcm])
}

const dir = new URL("./.reread-native/", import.meta.url)
mkdirSync(dir, { recursive: true })
async function audio(i, voice) {
  const c = CASES[i]
  const tag = c[4] ? `-${c[4]}` : c[3] ? `-${c[3]}` : ""
  const f = new URL(`case${i}${tag}-${voice.slice(0, 4)}.wav`, dir)
  if (existsSync(f)) return readFileSync(f)
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=pcm_16000`, {
    method: "POST", headers: { "xi-api-key": ELEVEN, "Content-Type": "application/json" },
    body: JSON.stringify({ text: c[0], model_id: "eleven_turbo_v2_5", language_code: c[3] ?? "ko" }),
  })
  if (!res.ok) throw new Error(`tts ${res.status} ${await res.text()}`)
  const w = wav(Buffer.from(await res.arrayBuffer()))
  writeFileSync(f, w)
  return w
}

async function gemini(body) {
  const t0 = Date.now()
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI}`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
  const j = await res.json()
  const text = (j.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text ?? "").join("").trim()
  return { ms: Date.now() - t0, text: res.ok ? text : `ERR ${res.status}` }
}

const tally = { target: [0, 0], other: [0, 0], none: [0, 0] }
let oldInvented = 0, otherTotal = 0, invented = 0
const ms = []
for (let i = 0; i < CASES.length; i++) {
  const [said, target, expected] = CASES[i]
  for (const voice of VOICES) {
    const w = (await audio(i, voice)).toString("base64")
    for (let r = 0; r < runs; r++) {
      const [o, n] = await Promise.all([gemini(oldBody(target, w)), gemini(newBody(target, w))])
      ms.push(n.ms)
      let p = {}
      try { p = JSON.parse(n.text) } catch { p = { language: "PARSE", text: n.text } }
      const ok = p.language === expected
      tally[expected][1] += 1; if (ok) tally[expected][0] += 1
      if (expected === "other") {
        otherTotal += 1
        if (o.text && !/[가-힣]/.test(o.text)) oldInvented += 1
        // The failure that matters: a Korean line labelled TARGET and written
        // in the target script — the line the fluent self would answer.
        if (p.language === "target" && p.text && !/[가-힣]/.test(p.text)) invented += 1
      }
      console.log(`${ok ? "✓" : "✗"} [${expected}/${target}] ${said}\n    old: ${o.text}\n    new: ${p.language} · ${p.text}  (${n.ms}ms)`)
    }
  }
}
ms.sort((a, b) => a - b)
const f = (k) => `${tally[k][0]}/${tally[k][1]}`
console.log(`\nnew: target ${f("target")} · other ${f("other")} · none ${f("none")} · p50 ${ms[ms.length >> 1]}ms · max ${ms.at(-1)}ms`)
console.log(`invented a target sentence for another-language speech: old ${oldInvented}/${otherTotal} · new ${invented}/${otherTotal}`)
