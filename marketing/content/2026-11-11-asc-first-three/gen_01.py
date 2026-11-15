# Shot 01 (founder 11-15): the live hand photo kept, its pixel-font text replaced by the
# same two-tone bold headline every other shot uses.
import sys
D = "/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/dev"
TEXT = {"ko": ("유창한 나에게", "언어를 배우다"), "en": ("Learn a language", "from your fluent self")}
SRC = {"ko": f"{D}/hand_1320.png", "en": f"{D}/hand_en_1320.png"}
OUTF = {"ko": "G-set/01_hand.png", "en": "sets/ios/en/01.png"}
for lang in ("ko", "en"):
    sys.argv = ["x", lang, D]
    import importlib, gen_lang as g
    importlib.reload(g)
    body = (f'<img src="file://{SRC[lang]}" style="position:absolute;left:0;top:0;width:1320px">'
            '<div style="position:absolute;left:0;top:0;width:1320px;height:690px;background:#F5F5F5"></div>'
            + g.title(g.C['hand_title']))
    g.render(body, f"{g.OUT}/{OUTF[lang]}")
    print(OUTF[lang])
