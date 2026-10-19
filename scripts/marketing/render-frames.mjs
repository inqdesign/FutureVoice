#!/usr/bin/env node
// Render a TIMELINE page to video, frame by frame — for motion pieces where every frame must land
// (an App Store preview), unlike record.mjs, which films a page in real time.
//
// The page exposes `window.__render(t)` (t in seconds) that puts the whole scene into its state at
// t, synchronously, and `window.__ready` (a promise: fonts + images loaded). Each frame: set t, wait
// two animation frames so layout and paint settle, screenshot at DPR, pipe to ffmpeg.
//
//   node22 scripts/marketing/render-frames.mjs <path> --out x.mp4 [--size 886x1920] [--seconds 29.5]
//     [--fps 30] [--ss 2] [--from 0] [--to <seconds>] [--png-at t ...]   (repeatable: stills only)
//     [--silent-audio]   add a silent stereo AAC track (App Store previews want an audio track)
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile, mkdtemp, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, extname, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const all = (k) => args.flatMap((a, i) => (a === k ? [args[i + 1]] : []));
const target = args[0];
const [W, H] = opt("--size", "886x1920").split("x").map(Number);
const FPS = +opt("--fps", 30), SS = +opt("--ss", 2);
const FROM = +opt("--from", 0), TO = +opt("--to", opt("--seconds", 29.5));
const OUT = opt("--out", null);
const PNGS = all("--png-at").map(Number);
const SILENT = args.includes("--silent-audio");

const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
  ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".ttf": "font/ttf" };
const server = createServer(async (req, res) => {
  const p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const file = join(ROOT, p);
  if (!file.startsWith(ROOT) || !existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "Content-Type": MIME[extname(file)] || "application/octet-stream" });
  res.end(await readFile(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/${target.replace(/^\//, "")}`;

const profile = await mkdtemp(join(tmpdir(), "nw-rf-"));
const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--hide-scrollbars", "--mute-audio", "--no-first-run", `--window-size=${W},${H}`, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
const wsUrl = await new Promise((ok, no) => {
  let buf = "";
  chrome.stderr.on("data", (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) ok(m[1]); });
  setTimeout(() => no(new Error("Chrome did not start")), 15000);
});
const port = new URL(wsUrl).port;
const pages = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const ws = new WebSocket(pages.find((p) => p.type === "page").webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let seq = 0; const pending = new Map(); const handlers = [];
ws.addEventListener("message", (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else handlers.forEach((h) => h(m));
});
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const evalP = async (expr) => {
  const r = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails));
  return r.result?.result?.value;
};

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: SS, mobile: false });
await send("Page.navigate", { url });
await new Promise((r) => handlers.push((m) => m.method === "Page.loadEventFired" && r()));
await evalP("window.__ready");

const frameAt = async (t) => {
  await evalP(`(window.__render(${t}), new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))`);
  return Buffer.from((await send("Page.captureScreenshot", { format: "png" })).result.data, "base64");
};
const ffmpeg = (a, input) => new Promise((ok, no) => {
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", ...a], { stdio: [input ? "pipe" : "ignore", "inherit", "inherit"] });
  ff.on("exit", (c) => (c === 0 ? ok() : no(new Error("ffmpeg failed"))));
  if (input) input(ff.stdin);
});

for (const t of PNGS) {
  const dir = await mkdtemp(join(tmpdir(), "nw-still-")); const f = join(dir, "s.png");
  await writeFile(f, await frameAt(t));
  const out = (OUT || "still.png").replace(/(\.\w+)?$/, `-${t.toFixed(2)}.png`);
  await ffmpeg(["-i", f, "-vf", `scale=${W}:${H}:flags=lanczos`, out]);
  console.log("wrote", out);
}

if (OUT && !PNGS.length) {
  const n = Math.round((TO - FROM) * FPS);
  let feed;
  const done = ffmpeg([
    "-f", "image2pipe", "-framerate", String(FPS), "-i", "-",
    ...(SILENT ? ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"] : []),
    "-vf", `scale=${W}:${H}:flags=lanczos:out_color_matrix=bt709:out_range=tv,format=yuv420p`,
    "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", "4.0", "-r", String(FPS),
    "-b:v", "11M", "-maxrate", "12M", "-bufsize", "24M",
    "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
    ...(SILENT ? ["-c:a", "aac", "-b:a", "256k", "-shortest"] : []),
    "-movflags", "+faststart", OUT], (stdin) => { feed = stdin; });
  for (let i = 0; i < n; i++) {
    const buf = await frameAt(FROM + i / FPS);
    if (!feed.write(buf)) await new Promise((r) => feed.once("drain", r));
    if (i % 30 === 0) process.stdout.write(`\r${i}/${n}`);
  }
  feed.end(); await done; console.log(`\nwrote ${OUT} (${n} frames)`);
}
ws.close(); chrome.kill(); server.close();
await rm(profile, { recursive: true, force: true }).catch(() => {});
