// German finals are re-read from their audio EVERY line (2026-11-02,
// `CallSession.checkTargetLine`). Does that make what the learner said come
// out right more often — and does it ever make a right line worse?
//
// A German learner's 1-star review: "English and even Spanish come out, I
// have to say each word slowly." A wrong German final is in the same letters
// as a right one, so nothing could flag it; the fix re-reads every line.
// This runs each clip through the LIVE transcriber with the production pin
// (before), then through the classifying re-read and the session's rule for
// using it (after), and scores both against the words actually said.
//
//   accent-heavy   German written in Hangul, read by Korean voices (an A1)
//   accent-light   German text read by Korean voices in German
//   native         German text read by German voices (must not get worse)
//   korean         Korean lines (must stay Korean, never become German)
//
//   node test/probe-reread-every-line.mjs [runs=2]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs"

const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const env = (k) => vars.match(new RegExp(`^${k}\\s*=\\s*"?([^"\\n]+)`, "m"))?.[1]
const GEMINI = env("GEMINI_API_KEY"), CARTESIA = env("CARTESIA_API_KEY")
const runs = Number(process.argv[2] ?? 2)
const LIVE = "models/gemini-3.5-transcribe-live"
const REREAD = "gemini-3.1-flash-lite"
const dir = new URL("./.reread-every-line/", import.meta.url)
mkdirSync(dir, { recursive: true })
const KO = ["cac92886-4b7c-4bc1-a524-e0f79c0381be", "537a82ae-4926-4bfb-9aec-aff0b80a12a5"]
const DE = ["1ade29fc-6b82-4607-9e70-361720139b12", "dff81230-ff75-49a4-af44-f6b2f43500d8"]

// [German, the same in Hangul]
const LINES = [
  ["Nein, danke.", "나인, 단케."],
  ["Ja, genau.", "야, 게나우."],
  ["Ich wohne in Berlin.", "이히 보네 인 베를린."],
  ["Ich möchte einen Kaffee, bitte.", "이히 뫼히테 아이넨 카페, 비테."],
  ["Ich arbeite als Lehrerin.", "이히 아르바이테 알스 레러린."],
  ["Am Wochenende gehe ich gern spazieren.", "암 보헨엔데 게에 이히 게른 슈파치렌."],
  ["Ich verstehe das nicht.", "이히 페어슈테에 다스 니히트."],
  ["Kannst du das bitte wiederholen?", "칸스트 두 다스 비테 비더홀렌?"],
  ["Ich fahre im Sommer in die Schweiz.", "이히 파레 임 조머 인 디 슈바이츠."],
  ["Ich lerne seit drei Monaten Deutsch.", "이히 레르네 자이트 드라이 모나텐 도이치."],
]
const KOREAN = ["잘 모르겠어요. 너무 어려워.", "연습해야 될 것 같아요.", "진짜 안 되네.", "그러니까 어제 회사에서 늦게 끝났어."]

const CLIPS = []
for (const [de, hangul] of LINES) {
  for (const v of KO) CLIPS.push({ kind: "accent-heavy", text: hangul, lang: "ko", voice: v, want: de })
  for (const v of KO) CLIPS.push({ kind: "accent-light", text: de, lang: "de", voice: v, want: de })
  for (const v of DE) CLIPS.push({ kind: "native", text: de, lang: "de", voice: v, want: de })
}
for (const k of KOREAN) for (const v of KO) CLIPS.push({ kind: "korean", text: k, lang: "ko", voice: v, want: k })

// src/transcriber.ts `languagePin("de")` verbatim, German guard included.
const PIN = [
  `You transcribe a language LEARNER speaking German. Write down exactly what you hear, word for word.`,
  `The language is settled before you hear anything: the speaker is speaking German, and every line you write is German. That holds for the first words of an utterance, when you have heard almost nothing yet, and for short replies that sound the same in several languages — write those in German too.`,
  `The speaker has a foreign accent, hesitates, and makes grammar mistakes. That is what a learner sounds like. It is never evidence that they switched to another language, and never a reason to write their words in another language, another spelling or another script.`,
  `Hesitation sounds — uh, um, a drawn-out vowel before the first word — belong to the German utterance too. Write them the way German writes a filler, or leave them out; they are never a word of another language and never another script.`,
  `Never translate and never correct — their mistakes are the material. If part of an utterance is unintelligible, write the German words you are sure of and leave the rest out; do not fill the gap with another language.`,
  "German and English share many sounds. A short answer is German: write Nein, never \"nine\"; Ja, never \"yeah\" or \"yes\"; Genau, Doch, Danke, Gut, Na ja, Also as German words. Never write an English word for a German one that sounds like it.",
].join("\n")

// src/reread.ts `classifyingSystem("de", "ko")` verbatim.
const REREAD_SYSTEM = [
  `You hear one utterance from a Korean speaker who is learning German, in the middle of a German conversation. Decide which language they actually SPOKE, then transcribe it.`,
  `"target": they spoke German — however strong the Korean accent, however broken the grammar, however much it sounds like Korean sounds. Words of German pronounced the Korean way are still German. Write it in German's own writing system, word for word, never corrected.`,
  `"native": they spoke Korean — real Korean words and grammar, the way they would talk to another Korean speaker. A learner who is stuck often does this. Write exactly what they said, in Korean's own writing system. Never translate it into German.`,
  `If most of it is German with one or two Korean words inside, it is "target": write the German words in German and the Korean word in Korean.`,
  `"none": only hesitation sounds (uh, um, 어, 음) or no words at all; text is empty.`,
  `Only write words you actually hear. Never invent a sentence to fill unclear audio.`,
].join("\n")

function wav(pcm) {
  const h = Buffer.alloc(44)
  h.write("RIFF", 0); h.writeUInt32LE(36 + pcm.length, 4); h.write("WAVE", 8)
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22)
  h.writeUInt32LE(16000, 24); h.writeUInt32LE(32000, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write("data", 36); h.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([h, pcm])
}
async function pcmOf(c) {
  const f = new URL(`${c.kind}-${Buffer.from(c.text).toString("hex").slice(0, 24)}-${c.voice.slice(0, 4)}.wav`, dir)
  if (existsSync(f)) return readFileSync(f).subarray(44)
  const res = await fetch("https://api.cartesia.ai/tts/bytes", {
    method: "POST",
    headers: { "Authorization": `Bearer ${CARTESIA}`, "Cartesia-Version": "2026-08-14", "Content-Type": "application/json" },
    body: JSON.stringify({ model_id: "sonic-3.6", transcript: c.text, voice: { mode: "id", id: c.voice },
      language: c.lang, output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: 16000 } }),
  })
  if (!res.ok) throw new Error(`tts ${res.status} ${await res.text()}`)
  const pcm = Buffer.from(await res.arrayBuffer())
  writeFileSync(f, wav(pcm))
  return pcm
}

function live(pcm) {
  return new Promise((resolve) => {
    const ws = new WebSocket(`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${GEMINI}`)
    let final = ""
    const timer = setTimeout(() => { try { ws.close() } catch {}; resolve(final || "TIMEOUT") }, 40000)
    ws.onopen = () => ws.send(JSON.stringify({ setup: { model: LIVE, generationConfig: { responseModalities: ["TEXT"] },
      systemInstruction: { parts: [{ text: PIN }] }, realtimeInputConfig: { automaticActivityDetection: {} } } }))
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

async function reread(pcm) {
  const started = Date.now()
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${REREAD}:generateContent?key=${GEMINI}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: REREAD_SYSTEM }] },
      contents: [{ role: "user", parts: [{ inlineData: { mimeType: "audio/wav", data: wav(pcm).toString("base64") } },
        { text: "Classify and transcribe this utterance." }] }],
      generationConfig: { maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" }, responseMimeType: "application/json",
        responseSchema: { type: "OBJECT", properties: { language: { type: "STRING", enum: ["target", "native", "none"] },
          text: { type: "STRING" } }, required: ["language", "text"], propertyOrdering: ["language", "text"] } },
    }),
  })
  const ms = Date.now() - started
  if (!res.ok) return { r: null, ms }
  const j = await res.json()
  try {
    const p = JSON.parse((j.candidates?.[0]?.content?.parts ?? []).filter((x) => !x.thought).map((x) => x.text ?? "").join(""))
    return { r: { spoken: p.language, text: (p.text ?? "").trim() }, ms }
  } catch { return { r: null, ms } }
}

const norm = (s) => s.toLowerCase().normalize("NFC").replace(/[^\p{L}\p{N}]+/gu, " ").trim()
const words = (s) => norm(s).split(" ").filter(Boolean)
const isFiller = (s) => words(s).length > 0 && words(s).every((w) =>
  /^(u+h*m*|u+m+|e+r+m*|a+h+m*|ä+h*m*|ö+h+|e+h+|e+u+h+|o+h+|h+m+|m+h*m+|h*m+)$/u.test(w))
const hangul = /\p{Script=Hangul}/u
// The session's rule (`checkTargetLine`): only German or Korean words replace
// the line; anything else keeps it. Lines the live model wrote in another
// script never reach it (the old re-read path handles them) — scored the same.
function after(liveText, r) {
  const usable = r && r.text && !isFiller(r.text) && (r.spoken === "target" || r.spoken === "native")
  return usable ? r.text : liveText
}
function accuracy(got, want) {   // LCS of words / words said
  const a = words(got), b = words(want)
  const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0))
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    dp[i][j] = a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1])
  return { hit: dp[a.length][b.length], n: b.length, extra: a.length - dp[a.length][b.length] }
}

for (const c of CLIPS) await pcmOf(c)
const jobs = []
for (const c of CLIPS) for (let r = 0; r < runs; r++) jobs.push(c)
const tally = {}, lines = [], rereadMs = []
let next = 0
async function worker() {
  while (next < jobs.length) {
    const c = jobs[next++]
    const pcm = await pcmOf(c)
    const before = await live(pcm)
    const { r, ms } = await reread(pcm)
    rereadMs.push(ms)
    const out = after(before, r)
    const t = (tally[c.kind] ??= { n: 0, bHit: 0, aHit: 0, words: 0, bExact: 0, aExact: 0, worse: 0, better: 0, bKo: 0, aKo: 0 })
    t.n++
    if (c.kind === "korean") {
      if (hangul.test(before)) t.bKo++
      if (hangul.test(out)) t.aKo++
    } else {
      const b = accuracy(before, c.want), a = accuracy(out, c.want)
      t.words += b.n; t.bHit += b.hit; t.aHit += a.hit
      if (b.hit === b.n && b.extra === 0) t.bExact++
      if (a.hit === a.n && a.extra === 0) t.aExact++
      const bs = b.hit - b.extra, as = a.hit - a.extra
      if (as < bs) t.worse++
      if (as > bs) t.better++
    }
    if (norm(before) !== norm(c.want) || norm(out) !== norm(c.want))
      lines.push(`${c.kind.padEnd(12)} ${c.want}\n    live:   ${before || "(nothing)"}\n    after:  ${out || "(nothing)"}   [${r?.spoken ?? "fail"}]`)
  }
}
await Promise.all(Array.from({ length: 10 }, worker))
lines.sort()
console.log(lines.join("\n"))
console.log("\nkind          n   words right (live → after)   exact lines   better/worse")
for (const [k, t] of Object.entries(tally)) {
  if (k === "korean") { console.log(`${k.padEnd(12)} ${String(t.n).padStart(3)}   kept Korean ${t.bKo} → ${t.aKo}`); continue }
  console.log(`${k.padEnd(12)} ${String(t.n).padStart(3)}   ${t.bHit}/${t.words} → ${t.aHit}/${t.words}`.padEnd(48)
    + `${t.bExact} → ${t.aExact}`.padEnd(14) + `${t.better}/${t.worse}`)
}
rereadMs.sort((a, b) => a - b)
console.log(`\nre-read ms: p50 ${rereadMs[Math.floor(rereadMs.length / 2)]} · p90 ${rereadMs[Math.floor(rereadMs.length * 0.9)]}`)
