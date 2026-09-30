#!/usr/bin/env python3
"""Cut a 30-second social teaser (1080×1920, Reels/Threads) out of a screen-recorded
demo, with burned-in captions, and end on a brand card.

The demo is the founder holding the app and talking over it: the strongest moment
the product has is its own voice speaking fluently, so the cut opens on that, not
on a problem statement. Every caption is what is actually said in that span
(checked against a whisper transcript), because a burned caption can't be fixed
after posting.

    python3 scripts/teaser/make-teaser.py "/path/to/speak_again.MP4" out.mp4

Needs ffmpeg and Pillow. The plan (source spans, captions) is PLAN below.
"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1080, 1920, 30
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SDG = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
GEIST = os.path.join(ROOT, "web", "GeistPixel.ttf")
INK, PAPER, DIM, ACCENT = (18, 17, 16), (237, 236, 232), (156, 154, 148), (91, 123, 255)

# (source start, source end, title-or-None, [(t0, t1, caption) relative to the span])
PLAN = [
    (105.4, 110.7, "이 목소리,\n유창해진 제 목소리예요.",
     [(0.0, 2.6, "So users can tweak things\nlike the voice speed"),
      (2.6, 5.3, "or the background right\nin the middle of it.")]),
    (26.9, 35.8, None,
     [(0.0, 4.7, "나와나에서는 머릿속에 있는 말을\n그냥 꺼내면 돼요"),
      (4.7, 8.9, "상대가 유창한 나니까\n틀려도 괜찮아요")]),
    (65.8, 80.2, None,
     [(0.0, 5.0, "중요한 건 이게 교재에 있는\n남의 문장이 아니라는 거예요"),
      (5.0, 7.6, "아까 내가 하려던 말이에요"),
      (7.6, 14.4, "내 생각, 내 의도는 그대로고\n문장만 자연스러워진 거죠")]),
]
END_SECONDS = 3.2


def font(size, index=6):
    return ImageFont.truetype(SDG, size, index=index)


def caption_png(text, path):
    """White text on a soft dark pill, lower third."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n")
    size = 56
    while True:  # never wider than the frame: shrink rather than clip
        f = font(size, 6)
        widths = [d.textlength(l, font=f) for l in lines]
        if max(widths) <= W - 160 or size <= 36:
            break
        size -= 2
    lh = int(size * 1.36)
    bw, bh = max(widths) + 72, lh * len(lines) + 44
    x0, y0 = (W - bw) / 2, H * 0.74 - bh / 2
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=28, fill=(0, 0, 0, 165))
    for i, l in enumerate(lines):
        d.text((W / 2, y0 + 22 + lh * i + lh / 2), l, font=f, fill=(255, 255, 255, 255), anchor="mm")
    img.save(path)


def title_png(text, path):
    """Big hook line at the top, over a gradient so it reads on any frame."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    grad = Image.new("L", (1, 560))
    for y in range(560):
        grad.putpixel((0, y), int(200 * (1 - y / 560) ** 1.4))
    band = Image.new("RGBA", (W, 560), (0, 0, 0, 255)); band.putalpha(grad.resize((W, 560)))
    img.alpha_composite(band, (0, 0))
    d = ImageDraw.Draw(img)
    f = font(84, 14)  # ExtraBold
    for i, l in enumerate(text.split("\n")):
        d.text((W / 2, 190 + i * 110), l, font=f, fill=(255, 255, 255, 255), anchor="mm")
    img.save(path)


def end_card(path):
    img = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(img)
    wm = ImageFont.truetype(GEIST, 150)
    d.text((W / 2, H * 0.40), "nawana", font=wm, fill=PAPER, anchor="mm")
    tag = font(58, 6)
    d.text((W / 2, H * 0.40 + 170), "유창한 나에게", font=tag, fill=PAPER, anchor="mm")
    d.text((W / 2, H * 0.40 + 250), "언어를 배우세요.", font=tag, fill=PAPER, anchor="mm")
    d.text((W / 2, H * 0.40 + 420), "App Store에서 nawana", font=font(40, 4), fill=DIM, anchor="mm")
    d.text((W / 2, H * 0.40 + 480), "nawana.app", font=ImageFont.truetype(GEIST, 44), fill=ACCENT, anchor="mm")
    img.save(path)


def run(args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def main():
    src, out = sys.argv[1], sys.argv[2]
    tmp = tempfile.mkdtemp(prefix="teaser-")
    parts = []
    for n, (a, b, title, caps) in enumerate(PLAN):
        inputs, chain = ["-ss", str(a), "-to", str(b), "-i", src], []
        chain.append(f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},fps={FPS},format=yuva420p[v0]")
        last, k = "v0", 1
        overlays = []
        if title:
            p = os.path.join(tmp, f"t{n}.png"); title_png(title, p); overlays.append((p, 0, b - a))
        for i, (t0, t1, text) in enumerate(caps):
            p = os.path.join(tmp, f"c{n}_{i}.png"); caption_png(text, p); overlays.append((p, t0, t1))
        for p, t0, t1 in overlays:
            inputs += ["-i", p]
            chain.append(f"[{last}][{k}:v]overlay=0:0:enable='between(t,{t0},{t1})'[v{k}]")
            last = f"v{k}"; k += 1
        dur = b - a
        chain.append(f"[{last}]format=yuv420p[vo]")
        chain.append(f"[0:a]aresample=48000,afade=t=in:d=0.08,afade=t=out:st={dur - 0.12}:d=0.12[ao]")
        part = os.path.join(tmp, f"p{n}.mp4")
        run([*inputs, "-filter_complex", ";".join(chain), "-map", "[vo]", "-map", "[ao]",
             "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-c:a", "aac", "-b:a", "160k",
             "-ac", "2", "-ar", "48000", part])
        parts.append(part)
    card = os.path.join(tmp, "end.png"); end_card(card)
    endmp4 = os.path.join(tmp, "end.mp4")
    run(["-loop", "1", "-t", str(END_SECONDS), "-i", card, "-f", "lavfi", "-t", str(END_SECONDS),
         "-i", "anullsrc=r=48000:cl=stereo", "-vf", f"fps={FPS},format=yuv420p,fade=t=in:d=0.35",
         "-c:v", "libx264", "-crf", "20", "-c:a", "aac", "-b:a", "160k", "-shortest", endmp4])
    parts.append(endmp4)
    lst = os.path.join(tmp, "list.txt")
    open(lst, "w").write("".join(f"file '{p}'\n" for p in parts))
    run(["-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-crf", "20", "-preset", "medium",
         "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out])
    print(out)


if __name__ == "__main__":
    main()
