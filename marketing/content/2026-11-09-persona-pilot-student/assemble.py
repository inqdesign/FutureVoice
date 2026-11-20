#!/usr/bin/env python3
# Builds timeline.js (what the page draws at each moment) and episode.wav (what is heard).
import json, os, math, array
HERE = os.path.dirname(os.path.abspath(__file__)); SR = 44100
s = json.load(open(f"{HERE}/scene.json")); c = json.load(open(f"{HERE}/copy.json"))
turns = s["turns"]; subs = c["subs"]; assert len(subs) == len(turns)
def load(p):
    a = array.array("h"); a.frombytes(open(f"{HERE}/audio/{p}.pcm", "rb").read())
    v = [x for x in a if abs(x) > 300]; rms = math.sqrt(sum(x*x for x in v)/max(1, len(v))) or 1
    g = min(4.0, 3600/rms)
    return array.array("h", (max(-32000, min(32000, int(x*g))) for x in a))
out = array.array("h"); segs = []
now = lambda: len(out)/SR
def sil(sec): out.extend(array.array("h", [0])*int(sec*SR))
def seg(start, **k): segs.append({"t0": round(start, 3), "t1": round(now(), 3), **k})
def tick():
    n = int(.14*SR); out.extend(array.array("h", (int(5200*math.sin(2*math.pi*880*i/SR)*math.sin(math.pi*i/n)) for i in range(n))))
SPK = {"user": "하린", "counterpart": "영사"}
def say(i, sec, **extra):
    t0 = now(); out.extend(load(f"line{i:02d}"))
    sil(.35); seg(t0, view="line", sec=sec, who=turns[i]["speaker"], name=SPK[turns[i]["speaker"]], en=turns[i]["text"], ko=subs[i], **extra)
def narr(k, view="lead", **extra):
    t0 = now(); out.extend(load(f"n_{k}")); sil(.45); seg(t0, view=view, **extra)
def scene(sec):
    for i in range(len(turns)): say(i, sec)
def dur(i): return os.path.getsize(f"{HERE}/audio/line{i:02d}.pcm")/(2*SR)
# cold open
sil(.3); t0 = now(); out.extend(load("line06")); sil(.3); seg(t0, view="cold", en=turns[6]["text"], ko=subs[6], cap=c["hook_caption"])
t0 = now(); tick(); sil(3.2); seg(t0, view="coldgap", cap=c["hook_caption"], ko=subs[6])
# intro
narr("intro", view="persona")
narr("watch", text=c["narration"]["watch"], sec="듣기")
scene("듣기"); sil(.5)
narr("expr_lead", text=c["narration"]["expr_lead"], sec="표현")
for n, e in enumerate(c["expressions"]):
    t0 = now(); out.extend(load(f"line{(3,5,7)[n]:02d}")); sil(.4)
    narr(f"expr{n+1}", view="expr", sec="표현", n=n+1, en=e["en"], meaning=e["meaning"], note=e["note"])
    segs[-1]["t0"] = round(t0, 3)
narr("repeat", text=c["narration"]["repeat"], sec="따라 말하기")
for i in (3, 5, 7):
    for rep in range(2):
        say(i, "따라 말하기")
        t0 = now(); tick(); sil(dur(i)*1.1+.9); seg(t0, view="gap", mode="repeat", sec="따라 말하기", name="따라 말해 보세요", en=turns[i]["text"], ko=subs[i])
        sil(.3); segs.append({"t0": segs[-1]["t1"], "t1": round(now(), 3), "view": "blank", "sec": "따라 말하기"})
narr("yourturn", text=c["narration"]["yourturn"], sec="내 차례")
for i in range(len(turns)):
    if turns[i]["speaker"] == "counterpart": say(i, "내 차례"); continue
    t0 = now(); tick(); sil(dur(i)*1.25+1.5); seg(t0, view="gap", mode="turn", sec="내 차례", name="내 차례", en="", ko=subs[i])
    t0 = now(); sil(1.4); seg(t0, view="line", sec="내 차례", who="user", name="하린이라면", en=turns[i]["text"], ko=subs[i])
sil(.4)
narr("outro", view="outro"); t0 = now(); sil(4); seg(t0, view="end")
meta = {k: c[k] for k in ("title_card", "disclosure", "outro_screen")}
open(f"{HERE}/timeline.js", "w").write("window.TL="+json.dumps({"segs": segs, "dur": now(), **meta}, ensure_ascii=False)+";")
import wave
with wave.open(f"{HERE}/episode.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes())
print("duration", round(now(), 1), "segments", len(segs))
