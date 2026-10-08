// Can the wrong-script re-read tell a learner who SWITCHED to their native
// language from one whose target-language words were written in the native
// script? (2026-10-08)
//
// Real finals over 14 days: "이 트랭키 마네카피 마이스탐 미트밀씨" is German
// ("Ich trinke meinen Kaffee mit Milch") in Hangul — the re-read is right to
// rewrite it. "이거 포인트 어떻게 뽑죠?" is Korean, and the re-read, told to
// write German only, invented "Ich habe heute etwas Brot." This probe builds
// both kinds with a native Korean library voice (transliteration read by a
// Korean voice is the accent, near enough) and runs the OLD prompt and the
// NEW classifying prompt over them.
//
//   node test/probe-reread-native.mjs [runs=2]
// Audio is cached under test/.reread-native/ (gitignored by .wrangler? no —
// see .gitignore) so re-runs cost only Gemini.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs"

const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const env = (k) => process.env[k] ?? vars.match(new RegExp(`^${k}\\s*=\\s*"?([^"\\n]+)`, "m"))?.[1]
const GEMINI = env("GEMINI_API_KEY"), ELEVEN = env("ELEVENLABS_API_KEY")
const runs = Number(process.argv[2] ?? 2)
const model = "gemini-3.1-flash-lite"
const VOICES = ["NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0"]   // 시안, 민준

// [spoken text, target, expected: target|native|none]
const CASES = [
  // The learner switched to Korean — every one of these came back invented.
  ["나는 즐기기로 마음 먹었기 때문에 재밌을 때까지만 할 거야.", "en", "native"],
  ["이거 포인트 어떻게 뽑죠?", "de", "native"],
  ["내 차도 수리해야 되는데.", "de", "native"],
  ["연말 정산, 어, 13월의 월급.", "de", "native"],
  ["가벼운", "en", "native"],
  ["일단", "en", "native"],
  ["어, 그래야겠지만, 어.", "en", "native"],
  ["그걸 영어로 뭐라고 하지?", "en", "native"],
  ["잘 모르겠어요. 너무 어려워.", "en", "native"],
  ["회사에서 회의가 너무 많아서 피곤해.", "en", "native"],
  // Target-language words, said with a Korean accent (Hangul read aloud).
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
  // Japanese target, Korean native (2026-10-08, a real learner's calls):
  // Korean-accented Japanese came out of the live model as real KOREAN
  // words — "이게 내 애가입니다" was 家で映画をみた — so here a wrong
  // classification would throw away a Japanese line. Japanese read by the
  // Korean voices with language_code ja (the accent); Korean as Korean.
  ["家で映画をみた。", "ja", "target", "ja"],
  ["全然ない。", "ja", "target", "ja"],
  ["十分ぐらいなら大丈夫だよ。", "ja", "target", "ja"],
  ["サーモンが好きやん。", "ja", "target", "ja"],
  ["ほら、絵が上手でしょう。", "ja", "target", "ja"],
  ["最近ちいかわのシリーズが終わっちゃった。", "ja", "target", "ja"],
  ["えっと、日本語で話します。", "ja", "target", "ja"],
  ["최근 K-pop에 빠져서 아이돌 노래를 자주 들어.", "ja", "native"],
  ["음, 10분 정도면 괜찮아요.", "ja", "native"],
  ["잘 잤어.", "ja", "native"],
  ["그걸 일본어로 뭐라고 해?", "ja", "native"],
  ["호랑이가 나오는 영화.", "ja", "native"],
  // Hesitation only.
  ["음…", "en", "none"],
  ["어… 어…", "de", "none"],
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

// Must stay byte-identical to src/reread.ts `classifyingSystem`.
export function newSystem(target, native) {
  const t = name[target], nv = name[native]
  return [
    `You hear one utterance from a ${nv} speaker who is learning ${t}, in the middle of a ${t} conversation. Decide which language they actually SPOKE, then transcribe it.`,
    `"target": they spoke ${t} — however strong the ${nv} accent, however broken the grammar, however much it sounds like ${nv} sounds. Words of ${t} pronounced the ${nv} way are still ${t}. Write it in ${t}'s own writing system, word for word, never corrected.`,
    `"native": they spoke ${nv} — real ${nv} words and grammar, the way they would talk to another ${nv} speaker. A learner who is stuck often does this. Write exactly what they said, in ${nv}'s own writing system. Never translate it into ${t}.`,
    `If most of it is ${t} with one or two ${nv} words inside, it is "target": write the ${t} words in ${t} and the ${nv} word in ${nv}.`,
    `"none": only hesitation sounds (uh, um, 어, 음) or no words at all; text is empty.`,
    `Only write words you actually hear. Never invent a sentence to fill unclear audio.`,
  ].join("\n")
}

function newBody(target, native, wavB64) {
  return {
    systemInstruction: { parts: [{ text: newSystem(target, native) }] },
    contents: [{ role: "user", parts: [
      { inlineData: { mimeType: "audio/wav", data: wavB64 } }, { text: "Classify and transcribe this utterance." }] }],
    generationConfig: {
      maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" },
      responseMimeType: "application/json",
      responseSchema: { type: "OBJECT", properties: {
        language: { type: "STRING", enum: ["target", "native", "none"] },
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
  const tag = CASES[i][3] ? `-${CASES[i][3]}` : ""
  const f = new URL(`case${i}${tag}-${voice.slice(0, 4)}.wav`, dir)
  if (existsSync(f)) return readFileSync(f)
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=pcm_16000`, {
    method: "POST", headers: { "xi-api-key": ELEVEN, "Content-Type": "application/json" },
    body: JSON.stringify({ text: CASES[i][0], model_id: "eleven_turbo_v2_5", language_code: CASES[i][3] ?? "ko" }),
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

// The Hangul cases above were cached before the Japanese ones were inserted:
// their file names carry the index, so the new cases are tagged by language
// and the old indices keep pointing at the same audio.
let newRight = 0, newTotal = 0, oldInvented = 0, nativeTotal = 0
const ms = []
const only = process.env.ONLY_TARGET
for (let i = 0; i < CASES.length; i++) {
  if (only && CASES[i][1] !== only) continue
  const [said, target, expected] = CASES[i]
  for (const voice of VOICES) {
    const w = (await audio(i, voice)).toString("base64")
    for (let r = 0; r < runs; r++) {
      const [o, n] = await Promise.all([gemini(oldBody(target, w)), gemini(newBody(target, "ko", w))])
      ms.push(n.ms)
      let parsed = {}
      try { parsed = JSON.parse(n.text) } catch { parsed = { language: "PARSE", text: n.text } }
      const ok = parsed.language === expected
      newTotal += 1; if (ok) newRight += 1
      if (expected === "native") { nativeTotal += 1; if (!/[가-힣]/.test(o.text) && o.text) oldInvented += 1 }
      console.log(`${ok ? "✓" : "✗"} [${expected}/${target}] ${said}\n    old: ${o.text}\n    new: ${parsed.language} · ${parsed.text}  (${n.ms}ms)`)
    }
  }
}
ms.sort((a, b) => a - b)
console.log(`\nnew prompt: ${newRight}/${newTotal} classified right · p50 ${ms[ms.length >> 1]}ms · max ${ms.at(-1)}ms`)
console.log(`old prompt: wrote a target-language sentence for ${oldInvented}/${nativeTotal} Korean utterances`)
