import { chromium } from 'playwright';
import { spawn } from 'child_process';
const [,, file, out] = process.argv, FPS = 30;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
await p.goto('file://' + file + '?export');
await p.waitForFunction(() => window.READY, null, { timeout: 30000 });
const D = await p.evaluate(() => window.REEL_DURATION());
const n = Math.ceil(D * FPS);
const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', '-preset', 'medium', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
for (let i = 0; i < n; i++) {
  await p.evaluate(t => window.seekTo(t), i / FPS);
  const buf = await p.screenshot({ type: 'jpeg', quality: 95, clip: { x: 0, y: 0, width: 1080, height: 1920 } });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 150 === 0) console.log(`frame ${i}/${n}`);
}
ff.stdin.end(); await new Promise(r => ff.on('close', r)); await b.close(); console.log('done', n);
