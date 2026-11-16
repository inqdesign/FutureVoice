#!/usr/bin/env python3
"""Lift a speech challenge picture off its cream paper (2026-11-16).

    scripts/speech-picture-key.py <drawn.png> <out.png> [--preview <dark.png>]

The picture is drawn on flat cream #FBF8F0 (the prompt asks for one flat
colour, no grain). Background = EVERY patch of that exact paper colour, not
only the part joined to the edge: the gaps the figure encloses, between the
feet or between a chin and a microphone, are paper too, and a flood from the
edge never reached them (founder, 2026-11-16: "do I have to point these out
one by one?"). Specks under 20 px stay, so a highlight can't be punched out.
Vision's subject mask was tried the same day and counted the microphone gap
as the person. A 2 px soft edge keeps the outline from looking cut. It
prints what it left, and --preview draws the result over a dark ground:
look at it before uploading.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as nd

PAPER = np.array([0xFB, 0xF8, 0xF0])
MIN_PATCH = 20

a = sys.argv[1:]
src, dst = a[0], a[1]
im = np.array(Image.open(src).convert("RGB")).astype(int)
d = np.abs(im - PAPER).max(-1)
paper = d < 14
lab, n = nd.label(paper)
sizes = nd.sum(paper, lab, range(1, n + 1)) if n else np.array([])
edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
keep = [i + 1 for i, s in enumerate(sizes) if (i + 1) in edge or s >= MIN_PATCH]
core = np.isin(lab, keep)
band = nd.binary_dilation(core, iterations=2) & ~core
alpha = np.full(d.shape, 255)
alpha[core] = 0
alpha[band] = (np.clip((d[band] - 10) / 30, 0, 1) * 255).astype(int)
Image.fromarray(np.dstack([im, alpha]).astype(np.uint8), "RGBA").save(dst)
holes = sorted(int(s) for i, s in enumerate(sizes) if (i + 1) not in edge and s >= MIN_PATCH)
print(f"keyed {dst}: {len(holes)} enclosed gap(s) cleared {holes}")
if "--preview" in a:
    al = alpha[..., None] / 255
    Image.fromarray((im * al + np.array([20, 20, 22]) * (1 - al)).astype(np.uint8)).save(a[a.index("--preview") + 1])
