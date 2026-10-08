// Does `inputAudioTranscription.languageCodes` make the LIVE transcriber
// write a learner's short sounds the way the target language would — and
// what does it cost? (2026-10-08)
//
// A learner of English who says "어" has said "uh": the right transcript is
// "uh" or nothing. The live model writes it "어" (Korean) or "अह" (Hindi) —
// 128 Devanagari finals from ~25 learners in 14 days — because all it has is
// the pin (systemInstruction), a request it does not keep for a lone sound.
// `languageCodes` was rejected at setup on 2026-09-01 and is accepted now.
// This runs four kinds of clip, voiced by Korean library voices, through
// both setups and scores each in code:
//   filler   어, 음…           good = empty or an English/German filler
//   answer   예스, 오케이…      good = Latin script, the expected words
//   word     진짜?, 글쎄…       good = Hangul (kept as said); INVENTED =
//                              a target-language word that was never said
//   sentence real Korean lines good = Hangul
//   node test/probe-live-language-codes.mjs [runs=3]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs"

const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const env = (k) => vars.match(new RegExp(`^${k}\\s*=\\s*"?([^"\\n]+)`, "m"))?.[1]
const GEMINI = env("GEMINI_API_KEY"), ELEVEN = env("ELEVENLABS_API_KEY")
const runs = Number(process.argv[2] ?? 3)
const MODEL = "models/gemini-3.5-transcribe-live"
const dir = new URL("./.reread-native/live/", import.meta.url)
mkdirSync(dir, { recursive: true })
const VOICES = ["NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0"]

// [kind, spoken (Hangul, read by a Korean voice), targets, expected words]
const CLIPS = [
  ...["어", "음", "아", "어…", "음…", "으음", "에"].map((t) => ["filler", t, ["en", "de"], ""]),
  ["answer", "예스.", ["en"], "yes"],
  ["answer", "오케이.", ["en"], "okay"],
  ["answer", "노.", ["en"], "no"],
  ["answer", "어, 아이 띵크 쏘.", ["en"], "i think so"],
  ["answer", "아이 돈 노.", ["en"], "i don't know"],
  ["answer", "쏘리?", ["en"], "sorry"],
  ["answer", "땡큐.", ["en"], "thank you"],
  ["answer", "음, 아이 라이크 잇.", ["en"], "i like it"],
  ["answer", "왓?", ["en"], "what"],
  ["answer", "리얼리?", ["en"], "really"],
  ["answer", "굿.", ["en"], "good"],
  ["answer", "야.", ["de"], "ja"],
  ["answer", "나인.", ["de"], "nein"],
  ["answer", "이히 바이스 니히트.", ["de"], "ich weiß nicht"],
  ["answer", "단케.", ["de"], "danke"],
  ["answer", "게나우.", ["de"], "genau"],
  ["answer", "음, 이히 글라우베 쇼.", ["de"], "ich glaube schon"],
  ...["진짜?", "글쎄", "잠깐만", "그러니까", "아니", "맞아", "몰라", "대박", "그래", "왜?"]
    .map((t) => ["word", t, ["en", "de"], ""]),
  ...["나는 즐기기로 마음 먹었기 때문에 재밌을 때까지만 할 거야.", "이거 포인트 어떻게 뽑죠?",
      "내 차도 수리해야 되는데.", "회사에서 회의가 너무 많아서 피곤해.", "잘 모르겠어요. 너무 어려워."]
    .map((t) => ["sentence", t, ["en", "de"], ""]),
]

const NAME = { en: "English", de: "German" }
const pin = (n) => [   // src/transcriber.ts `languagePin` for en/de, verbatim
  `You transcribe a language LEARNER speaking ${n}. Write down exactly what you hear, word for word.`,
  `The language is settled before you hear anything: the speaker is speaking ${n}, and every line you write is ${n}. That holds for the first words of an utterance, when you have heard almost nothing yet, and for short replies that sound the same in several languages — write those in ${n} too.`,
  `The speaker has a foreign accent, hesitates, and makes grammar mistakes. That is what a learner sounds like. It is never evidence that they switched to another language, and never a reason to write their words in another language, another spelling or another script.`,
  `Hesitation sounds — uh, um, a drawn-out vowel before the first word — belong to the ${n} utterance too. Write them the way ${n} writes a filler, or leave them out; they are never a word of another language and never another script.`,
  `Never translate and never correct — their mistakes are the material. If part of an utterance is unintelligible, write the ${n} words you are sure of and leave the rest out; do not fill the gap with another language.`,
].join("\n")

function wav(pcm) {
  const h = Buffer.alloc(44)
  h.write("RIFF", 0); h.writeUInt32LE(36 + pcm.length, 4); h.write("WAVE", 8)
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22)
  h.writeUInt32LE(16000, 24); h.writeUInt32LE(32000, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write("data", 36); h.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([h, pcm])
}
async function clip(i, voice) {
  const f = new URL(`c${i}-${voice.slice(0, 4)}.wav`, dir)
  if (existsSync(f)) return readFileSync(f).subarray(44)
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=pcm_16000`, {
    method: "POST", headers: { "xi-api-key": ELEVEN, "Content-Type": "application/json" },
    body: JSON.stringify({ text: CLIPS[i][1], model_id: "eleven_turbo_v2_5", language_code: "ko" }) })
  if (!res.ok) throw new Error(`tts ${res.status}`)
  const pcm = Buffer.from(await res.arrayBuffer())
  writeFileSync(f, wav(pcm))
  return pcm
}

const SETUPS = {
  pin: () => ({}),
  "pin+languageCodes": (t) => ({ inputAudioTranscription: { languageCodes: [t === "en" ? "en-US" : "de-DE"] } }),
}

function transcribe(pcm, target, extra) {
  return new Promise((resolve) => {
    const ws = new WebSocket(`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${GEMINI}`)
    let final = ""
    const timer = setTimeout(() => { try { ws.close() } catch {}; resolve(final || "TIMEOUT") }, 40000)
    ws.onopen = () => ws.send(JSON.stringify({ setup: { model: MODEL, generationConfig: { responseModalities: ["TEXT"] },
      systemInstruction: { parts: [{ text: pin(NAME[target]) }] },
      realtimeInputConfig: { automaticActivityDetection: {} }, ...extra } }))
    ws.onmessage = async (ev) => {
      const text = typeof ev.data === "string" ? ev.data : await ev.data.text()
      let msg; try { msg = JSON.parse(text) } catch { return }
      if (msg.setupComplete !== undefined) {
        const all = Buffer.concat([Buffer.alloc(12800), pcm, Buffer.alloc(80000)])
        for (let off = 0; off < all.length; off += 3200) {
          ws.send(JSON.stringify({ realtimeInput: { audio: { data: all.subarray(off, off + 3200).toString("base64"), mimeType: "audio/pcm;rate=16000" } } }))
          await new Promise((r) => setTimeout(r, 100))
        }
        clearTimeout(timer); try { ws.close() } catch {}; resolve(final)
        return
      }
      const f = msg.serverContent?.inputTranscription?.text
      if (f?.trim()) final = final ? `${final} ${f.trim()}` : f.trim()
    }
    ws.onclose = (e) => { clearTimeout(timer); resolve(final || (e.code !== 1000 && e.code !== 1005 ? `CLOSED ${e.code}` : "")) }
  })
}

const isFiller = (s) => { const w = s.toLowerCase().split(/[^\p{L}]+/u).filter(Boolean)
  return w.length > 0 && w.every((x) => /^(u+h*m*|u+m+|e+r+m*|a+h+m*|ä+h*m*|ö+h+|e+h+|o+h+|h+m+|m+h*m+|h*m+)$/u.test(x)) }
const words = (s) => s.toLowerCase().normalize("NFC").replace(/[’']/g, "'").split(/[^\p{L}']+/u).filter((w) => w && !isFiller(w))
const latin = /\p{Script=Latin}/u, hangul = /\p{Script=Hangul}/u
function score(kind, out, expected) {
  const has = /\p{L}/u.test(out)
  const script = !has ? "empty" : latin.test(out) && !hangul.test(out) ? "latin" : hangul.test(out) && !latin.test(out) ? "hangul" : latin.test(out) || hangul.test(out) ? "mixed" : "other"
  if (kind === "filler") return script === "empty" || (script === "latin" && isFiller(out)) ? "good" : script === "other" ? "foreign" : script === "hangul" ? "hangul" : "word"
  if (kind === "answer") {
    if (script !== "latin") return script === "other" ? "foreign" : script
    const got = words(out).join(" "), want = words(expected).join(" ")
    return got === want ? "good" : "wrong-words"
  }
  // word / sentence: said in Korean
  if (script === "hangul" || script === "empty") return "good"
  if (script === "latin") return isFiller(out) ? "filler" : "INVENTED"
  return script === "other" ? "foreign" : "mixed"
}

const jobs = []
for (let i = 0; i < CLIPS.length; i++) for (const v of VOICES) for (const t of CLIPS[i][2])
  for (const name of Object.keys(SETUPS)) for (let r = 0; r < runs; r++) jobs.push({ i, v, t, name })
for (let i = 0; i < CLIPS.length; i++) for (const v of VOICES) await clip(i, v)

const tally = {}, examples = []
let next = 0
async function worker() {
  while (next < jobs.length) {
    const { i, v, t, name } = jobs[next++]
    const [kind, said, , expected] = CLIPS[i]
    const out = await transcribe(await clip(i, v), t, SETUPS[name](t))
    const s = score(kind, out, expected)
    const key = `${kind}|${name}`
    tally[key] ??= {}; tally[key][s] = (tally[key][s] ?? 0) + 1; tally[key].n = (tally[key].n ?? 0) + 1
    if (s !== "good") examples.push(`${name.padEnd(17)} ${kind.padEnd(8)} ${t} ${v.slice(0, 4)} ${said} → ${out || "(nothing)"}  [${s}]`)
  }
}
await Promise.all(Array.from({ length: 10 }, worker))
examples.sort()
console.log(examples.join("\n"))
console.log("\nkind      setup              n   result")
for (const k of Object.keys(tally).sort()) {
  const [kind, name] = k.split("|"); const { n, ...rest } = tally[k]
  console.log(`${kind.padEnd(9)} ${name.padEnd(17)} ${String(n).padStart(3)}   ${Object.entries(rest).sort((a, b) => b[1] - a[1]).map(([x, c]) => `${x} ${c}`).join(" · ")}`)
}
