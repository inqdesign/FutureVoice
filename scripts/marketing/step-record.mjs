#!/usr/bin/env node
// Record a page FRAME BY FRAME: for every frame the page's own window.renderAt(t) draws that moment (and seeks
// any video to it), then a screenshot is taken. Exact at any frame rate however heavy the page, unlike
// record.mjs's real-time screencast, which drops frames on a busy page. The page must define renderAt(t) → Promise
// and should not animate by itself in the mode its URL asks for (e.g. ?manual).
//
//   node22 scripts/marketing/step-record.mjs "<repo-path>?manual" --size 1080x1920 --seconds 16.8 --fps 30 --out x.mp4
//     --ss N   render at N× density, then lanczos down (default 1)
// The static server answers Range requests, so <video> can seek.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, writeFile, rm, stat } from "node:fs/promises";
import { createReadStream, existsSync } from "node:fs";
import { join, extname, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const target = args.find((a, i) => !a.startsWith("--") && (i === 0 || !args[i - 1].startsWith("--")));
const OUT = opt("--out", "out.mp4");
const [W, H] = opt("--size", "1080x1920").split("x").map(Number);
const SECONDS = +opt("--seconds", 10), FPS = +opt("--fps", 30), SS = +opt("--ss", 1);
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".jpg": "image/jpeg",
  ".svg": "image/svg+xml", ".woff2": "font/woff2", ".ttf": "font/ttf", ".mp4": "video/mp4", ".json": "application/json" };

const server = createServer(async (req, res) => {
  const file = join(ROOT, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!file.startsWith(ROOT) || !existsSync(file)) { res.writeHead(404).end(); return; }
  const size = (await stat(file)).size, type = MIME[extname(file)] || "application/octet-stream";
  const m = /bytes=(\d*)-(\d*)/.exec(req.headers.range || "");
  if (m) {
    const a = m[1] ? +m[1] : 0, b = m[2] ? +m[2] : size - 1;
    res.writeHead(206, { "Content-Type": type, "Content-Range": `bytes ${a}-${b}/${size}`, "Accept-Ranges": "bytes", "Content-Length": b - a + 1 });
    createReadStream(file, { start: a, end: b }).pipe(res);
  } else {
    res.writeHead(200, { "Content-Type": type, "Accept-Ranges": "bytes", "Content-Length": size });
    createReadStream(file).pipe(res);
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/${target.replace(/^\//, "")}`;

const profile = await mkdtemp(join(tmpdir(), "nw-step-"));
const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--hide-scrollbars",
  "--mute-audio", "--no-first-run", "--autoplay-policy=no-user-gesture-required", `--window-size=${W},${H}`, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
const wsUrl = await new Promise((ok, no) => { let buf = ""; chrome.stderr.on("data", (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) ok(m[1]); }); setTimeout(() => no(new Error("Chrome did not start")), 15000); });
const pages = await (await fetch(`http://127.0.0.1:${new URL(wsUrl).port}/json`)).json();
const ws = new WebSocket(pages.find((p) => p.type === "page").webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let seq = 0; const pending = new Map(), handlers = [];
ws.addEventListener("message", (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else handlers.forEach((h) => h(m)); });
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: SS, mobile: false });
await send("Page.navigate", { url });
await new Promise((r) => handlers.push((m) => m.method === "Page.loadEventFired" && r()));
for (let i = 0; i < 300; i++) { const v = await send("Runtime.evaluate", { expression: "!!document.documentElement.dataset.scene", returnByValue: true }); if (v.result?.result?.value) break; await sleep(50); }

const dir = await mkdtemp(join(tmpdir(), "nw-stepf-"));
const N = Math.round(SECONDS * FPS);
for (let i = 0; i < N; i++) {
  const r = await send("Runtime.evaluate", { expression: `window.renderAt(${(i / FPS).toFixed(5)})`, awaitPromise: true });
  if (r.result?.exceptionDetails) { console.error(JSON.stringify(r.result.exceptionDetails).slice(0, 400)); process.exit(1); }
  const shot = await send("Page.captureScreenshot", { format: "png" });
  await writeFile(join(dir, `f${String(i).padStart(5, "0")}.png`), Buffer.from(shot.result.data, "base64"));
  if (i % 60 === 0) process.stderr.write(`${i}/${N}\n`);
}
ws.close(); chrome.kill(); server.close();
await new Promise((ok, no) => {
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(FPS), "-i", join(dir, "f%05d.png"),
    "-vf", `scale=${W}:${H}:flags=lanczos,format=yuv420p`, "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-profile:v", "high",
    "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-movflags", "+faststart", OUT], { stdio: "inherit" });
  ff.on("exit", (c) => (c === 0 ? ok() : no(new Error("ffmpeg failed"))));
});
await rm(dir, { recursive: true, force: true }); await rm(profile, { recursive: true, force: true });
console.log("wrote", OUT, `(${N} frames at ${FPS} fps)`);
