// Try a talk on OpenAI gpt-realtime with the app's own conversation prompt.
// Local only: the API key stays on this Mac, the browser gets a short-lived
// client secret per call.
//
//   node scripts/realtime-trial/server.mjs      → open http://localhost:8787
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

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      return res.end(fs.readFileSync(path.join(DIR, "index.html")));
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
  console.log(`realtime trial → http://localhost:${PORT}` + (apiKey() ? "" : "   (no key yet: ~/keys/openai.txt)"));
});
