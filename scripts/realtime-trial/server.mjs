// Try a talk on OpenAI gpt-realtime with the app's own conversation prompt.
// Local only: the API key stays on this Mac, the browser gets a short-lived
// client secret per call.
//
//   node scripts/realtime-trial/server.mjs      → open http://localhost:8787
//                                                  GPT-Live tutor: /live
//
// Key: ~/keys/openai.txt (or OPENAI_API_KEY). Prompts: prompts/<lang>-<level>.txt,
// dumped by ConversationPromptDumpTests (see scripts/beginner-probe.py).
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);

function apiKey() {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY.trim();
  const f = path.join(os.homedir(), "keys", "openai.txt");
  return fs.existsSync(f) ? fs.readFileSync(f, "utf8").trim() : "";
}

function instructions(lang, level) {
  const p = path.join(DIR, "prompts", `${lang}-${level}.txt`);
  if (!fs.existsSync(p)) throw new Error(`no prompt for ${lang}-${level}`);
  return fs.readFileSync(p, "utf8") + "\n" + fs.readFileSync(path.join(DIR, "prompts", "_style.txt"), "utf8");
}

const TRANSCRIBE_LANG = { en: "en", ko: "ko", ja: "ja", de: "de", es: "es" };

async function mintSecret(q) {
  const key = apiKey();
  if (!key) throw new Error("No OpenAI key. Save it to ~/keys/openai.txt");
  const session = {
    type: "realtime",
    model: q.model,
    instructions: instructions(q.lang, q.level),
    audio: {
      input: {
        // The learner's lines as text, like the app keeps them. Billed apart.
        transcription: { model: "gpt-4o-mini-transcribe", language: TRANSCRIBE_LANG[q.lang] },
        turn_detection: q.vad === "server"
          ? { type: "server_vad", silence_duration_ms: Number(q.silence) || 800, prefix_padding_ms: 300 }
          : { type: "semantic_vad", eagerness: q.eagerness || "low" },
      },
      output: { voice: q.voice },
    },
  };
  const r = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expires_after: { anchor: "created_at", seconds: 600 }, session }),
  });
  const body = await r.text();
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${body}`);
  return JSON.parse(body).value;
}

// ── GPT-Live (gpt-live-1, full duplex, POST /v1/live/sessions) ──────────────
// A different model and endpoint from gpt-realtime above: it listens while it
// speaks and decides many times a second whether to talk, so there is no turn
// detection to tune. Tried as the AI TUTOR's voice (presets only, no clone).

const LANG_NAME = { en: "English", ko: "Korean", ja: "Japanese", de: "German", es: "Spanish" };
const NATIVE_NAME = { ko: "Korean", en: "English", ja: "Japanese", de: "German", es: "Spanish" };
const LEVEL_SHAPE = {
  a1: "A1: one fact per sentence, the most common words, very short lines.",
  a2: "A2: two facts or a reason per answer (because, and, but), everyday words.",
  b1: "B1: reasons, a short story, a follow-up question.",
};

// The app's tutor runs on an app-side judge (TutorJudge + notes). Here GPT-Live
// judges by itself, which is the thing being tested.
function tutorInstructions(q) {
  const target = LANG_NAME[q.lang], native = NATIVE_NAME[q.native] || "Korean";
  const topic = (q.topic || "").trim();
  return `You are a friendly ${target} TUTOR on a live phone call with one learner.
Their native language is ${native}. Their level is ${LEVEL_SHAPE[q.level] || LEVEL_SHAPE.a2}

THE GOAL OF THE CALL: by the end they can SAY one practical thing in ${target} properly, out loud, with no mistakes.

HOW THE CALL GOES
1. ${topic ? `Today's topic is "${topic}". Say so in one short line and start.` : "Ask what they want to be able to say today. If they don't know, offer two concrete everyday topics and let them pick."}
2. Plan three small challenges for that topic, at their level (for you only, never read the plan out). The third puts the first two together.
3. Run ONE challenge at a time: ask a question about THEIR life that calls for it, and give one example line ("you could say: ..."). They try.
   - A real mistake (grammar, wrong word, missing word): say their line back the right way, name the one thing that changed in a few words, and ask them to say it again. Never praise an answer that had a mistake.
   - Right: a short "yes, that's it" and move to the next challenge.
   - Right only after a correction: ask for it ONCE MORE before moving on.
   - They chat, ask you something, or speak ${native}: answer like a person, help them say it in ${target}, then come back to the challenge.
4. After the third: ask them to say it all in one go, in their own words, no hints. Then tell them honestly how it went, and ask whether to practice more or pick another topic.

HOW YOU SPEAK
- This is a phone call. One to three short sentences per turn, ONE question at most.
- Speak ${target} only, at their level. Use ${native} only for a single word they are missing, and only if they are stuck.
- Never correct how a sentence is spelled or punctuated; you only hear it. Casual spoken forms are not mistakes.
- Never read out lists, labels, numbers of challenges or stage directions.`;
}

function liveInstructions(q) {
  if (q.prompt === "call") return instructions(q.lang, q.level);
  return tutorInstructions(q);
}

function greeting(q) {
  const target = LANG_NAME[q.lang];
  return q.prompt === "call"
    ? `The call just connected. Greet them now in ${target}, in one or two short sentences, ask one easy question, then pause and listen.`
    : `The call just connected. Greet them now in ${target} as their tutor, in one short sentence, ${q.topic ? "say today's topic and ask the first challenge's question" : "and ask what they want to be able to say today"}. Then pause and listen.`;
}

async function createLiveSession(body) {
  const key = apiKey();
  if (!key) throw new Error("No OpenAI key. Save it to ~/keys/openai.txt");
  const q = body.q || {};
  const session = {
    model: "gpt-live-1",
    instructions: liveInstructions(q),
    audio: { output: { voice: q.voice || "marin" } },
    input: [{ type: "message", role: "developer", content: [{ type: "input_text", text: greeting(q) }] }],
  };
  const t0 = Date.now();
  const r = await fetch("https://api.openai.com/v1/live/sessions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ session, transport: { type: "webrtc", sdp: body.sdp } }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${text}`);
  const out = JSON.parse(text);
  out.create_ms = Date.now() - t0;
  out.greeting = greeting(q);
  return out;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let s = "";
    req.on("data", (c) => { s += c; if (s.length > 200_000) reject(new Error("body too large")); });
    req.on("end", () => { try { resolve(JSON.parse(s || "{}")); } catch (e) { reject(e); } });
    req.on("error", reject);
  });
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      return res.end(fs.readFileSync(path.join(DIR, "index.html")));
    }
    if (url.pathname === "/live") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      return res.end(fs.readFileSync(path.join(DIR, "live.html")));
    }
    if (url.pathname === "/live-session" && req.method === "POST") {
      const out = await createLiveSession(await readBody(req));
      res.writeHead(201, { "Content-Type": "application/json" });
      return res.end(JSON.stringify(out));
    }
    if (url.pathname === "/secret") {
      const q = Object.fromEntries(url.searchParams);
      const value = await mintSecret(q);
      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ value }));
    }
    res.writeHead(404).end();
  } catch (e) {
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: String(e.message || e) }));
  }
}).listen(PORT, "127.0.0.1", () => {
  console.log(`realtime trial → http://localhost:${PORT}   GPT-Live tutor → http://localhost:${PORT}/live` +(apiKey() ? "" : "   (no key yet: ~/keys/openai.txt)"));
});
