# App Store refresh (2026-10-25)

Review page: https://claude.ai/artifact/9jz8X44bv5rbvaLcuHXYrw — nothing uploaded to App Store Connect.

- `screenshots/<set>/NN_<id>.png` — 1320×2868 (6.9"), RGB, one folder per language set
  (`es` serves es-ES and es-MX, `en` serves en-GB and en-US).
- `copy.json` — headlines/sublines per set, the capture each shot uses, callout crops.
- `meta.json` / `meta.py` — proposed name, subtitle, keywords, promo text per locale, length-checked.
  Not in `fastlane/metadata` on purpose: `asc-submit.py` would push it with the next release.

Rebuild: install a Debug build on the iPhone 17 Pro Max simulator, run `capall.sh` (captures into
its own `raw/` dir, edit the paths), then `python3 compose.py copy.json <raw> <out>`.
