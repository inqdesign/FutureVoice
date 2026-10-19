#!/usr/bin/env node
// Record a web page (a carousel card, a kit screen, a site section) to MP4 and/or PNG.
//
// Real Chrome, real time: the page is served from the repo root, opened headless at the
// exact pixel size, and recorded with the DevTools screencast, so CSS transitions and the
// kit's timers run exactly as in a browser (virtual time freezes transitions — don't use it).
// No npm packages: Node 22's built-in WebSocket speaks the DevTools protocol directly.
//
//   node22 scripts/marketing/record.mjs <path-or-url> [options]
//     <path>            repo-relative, e.g. marketing/content/2026-10-11-what-you-can-do/carousel.html?solo=2
//     --out <file>      .mp4 and/or .png (repeatable)         default: ./out.mp4
//     --size WxH        viewport, CSS px                       default: 1080x1350 (4:5 feed)
//     --seconds N       recording length                       default: 10
//     --warmup N        seconds to wait before recording       default: 1.2
//     --png-at N        for a .png out: seconds after warmup    default: end of recording
//     --fps N           output frame rate                      default: 30
//     --scale N         device pixel ratio (3 = an iPhone capture) default: 1
//     --ss N            supersample: render at N× the output density, then downscale (lanczos)
//                       so text and edges stay sharp after Instagram re-encodes   default: 2
//     --wait-for JS     poll this expression until truthy before the warmup starts, e.g.
//                       "document.documentElement.dataset.scene" (a carousel sets it when its scene
//                       starts), so the recording never opens on the page still loading
//
// Node 22 is at /opt/homebrew/opt/node@22/bin/node (the shell's default node is 20, which
// has no WebSocket).
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile, mkdtemp, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, extname, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const outs = args.flatMap((a, i) => (a === "--out" ? [args[i + 1]] : []));
if (!outs.length) outs.push("out.mp4");
const target = args.find((a, i) => !a.startsWith("--") && (i === 0 || !args[i - 1].startsWith("--")));
if (!target) { console.error("usage: record.mjs <path-or-url> --out x.mp4 [--size 1080x1350] [--seconds 10]"); process.exit(2); }
const [W, H] = opt("--size", "1080x1350").split("x").map(Number);
const SECONDS = +opt("--seconds", 10), WARMUP = +opt("--warmup", 1.2), FPS = +opt("--fps", 30);
const PNG_AT = opt("--png-at", null);
const SCALE = +opt("--scale", 1);
const SS = +opt("--ss", 2);            // render density multiplier; output stays W*SCALE × H*SCALE
const DPR = SCALE * SS;
const WAIT_FOR = opt("--wait-for", null);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ── a static server over the repo root (the page imports /web/kit/…) ── */
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".woff2": "font/woff2",
  ".ttf": "font/ttf", ".mp3": "audio/mpeg", ".mp4": "video/mp4" };
const server = createServer(async (req, res) => {
  const p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const file = join(ROOT, p.endsWith("/") ? p + "index.html" : p);
  if (!file.startsWith(ROOT) || !existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "Content-Type": MIME[extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
  res.end(await readFile(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = /^https?:/.test(target) ? target : `http://127.0.0.1:${server.address().port}/${target.replace(/^\//, "")}`;

/* ── Chrome + DevTools ── */
const profile = await mkdtemp(join(tmpdir(), "nw-rec-"));
const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--hide-scrollbars", "--mute-audio", "--no-first-run", `--force-device-scale-factor=${DPR}`, `--window-size=${W},${H}`, "about:blank"],
  { stdio: ["ignore", "ignore", "pipe"] });
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
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else handlers.forEach((h) => h(m));
});
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: DPR, mobile: false });
await send("Page.navigate", { url });
await new Promise((r) => handlers.push((m) => m.method === "Page.loadEventFired" && r()));
if (WAIT_FOR) {
  const until = Date.now() + 15000;
  while (Date.now() < until) {
    const v = await send("Runtime.evaluate", { expression: `!!(${WAIT_FOR})`, returnByValue: true });
    if (v.result?.result?.value) break;
    await sleep(30);
  }
}
await sleep(WARMUP * 1000);

/* ── record ── */
const frames = [];
handlers.push((m) => {
  if (m.method !== "Page.screencastFrame") return;
  frames.push({ data: m.params.data, t: m.params.metadata.timestamp });
  send("Page.screencastFrameAck", { sessionId: m.params.sessionId });
});
const wantMp4 = outs.some((o) => o.endsWith(".mp4"));
let pngShot = null;
if (wantMp4) await send("Page.startScreencast", { format: "png", maxWidth: W * DPR, maxHeight: H * DPR, everyNthFrame: 1 });
const t0 = Date.now();
if (PNG_AT !== null) { await sleep(+PNG_AT * 1000); pngShot = (await send("Page.captureScreenshot", { format: "png" })).result.data; }
await sleep(Math.max(0, SECONDS * 1000 - (Date.now() - t0)));
if (wantMp4) await send("Page.stopScreencast");
if (!pngShot) pngShot = (await send("Page.captureScreenshot", { format: "png" })).result.data;

for (const out of outs) {
  if (out.endsWith(".png")) {
    // the shot is taken at DPR; bring it back to the output size with a lanczos downscale
    const raw = join(await mkdtemp(join(tmpdir(), "nw-png-")), "shot.png");
    await writeFile(raw, Buffer.from(pngShot, "base64"));
    await new Promise((ok, no) => {
      const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-i", raw, "-vf", `scale=${W * SCALE}:${H * SCALE}:flags=lanczos`, out], { stdio: "inherit" });
      ff.on("exit", (c) => (c === 0 ? ok() : no(new Error("ffmpeg png failed"))));
    });
    console.log("wrote", out); continue;
  }
  if (!frames.length) { console.error("no frames captured"); continue; }
  // the screencast sends a frame only when something changes; hold each one until the next.
  // Frames stamped after the window (delivered while the screencast was stopping) are dropped,
  // or the file runs longer than --seconds.
  { const cut = frames[0].t + SECONDS; for (let i = frames.length - 1; i > 0; i--) if (frames[i].t >= cut) frames.splice(i, 1); }
  const dir = await mkdtemp(join(tmpdir(), "nw-frames-"));
  let list = "";
  const end = frames[0].t + SECONDS;
  for (let i = 0; i < frames.length; i++) {
    const f = join(dir, `f${String(i).padStart(5, "0")}.png`);
    await writeFile(f, Buffer.from(frames[i].data, "base64"));
    const next = i + 1 < frames.length ? frames[i + 1].t : end;
    list += `file '${f}'\nduration ${Math.max(0.001, next - frames[i].t).toFixed(4)}\n`;
  }
  list += `file '${join(dir, `f${String(frames.length - 1).padStart(5, "0")}.png`)}'\n`;
  await writeFile(join(dir, "list.txt"), list);
  await new Promise((ok, no) => {
    const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", join(dir, "list.txt"),
      // supersampled PNG frames → lanczos down to the output size, limited-range BT.709 (what phones
      // expect; JPEG input used to leave full-range yuvj420p), and a high-quality H.264 so Instagram's
      // own re-encode starts from a clean source instead of a 0.4 Mbps one.
      "-vf", `fps=${FPS},scale=${W * SCALE}:${H * SCALE}:flags=lanczos:out_color_matrix=bt709:out_range=tv,format=yuv420p`,
      "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-tune", "animation", "-profile:v", "high", "-level", "4.2",
      "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
      "-movflags", "+faststart", "-t", String(SECONDS), out], { stdio: "inherit" });
    ff.on("exit", (c) => (c === 0 ? ok() : no(new Error("ffmpeg failed"))));
  });
  await rm(dir, { recursive: true, force: true });
  console.log("wrote", out, `(${frames.length} frames)`);
}

ws.close(); chrome.kill(); server.close();
await rm(profile, { recursive: true, force: true }).catch(() => {});
