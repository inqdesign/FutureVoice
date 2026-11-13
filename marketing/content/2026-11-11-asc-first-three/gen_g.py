# G: the 10-shot set after the founder's notes of 2026-11-13 night.
# Call screens are the founder's own device screenshots (current UI, status bar
# replaced by the simulator's 9:41); speech is the live App Store speech screen.
import os
from gen_e import phone, card, crop, render, CSS, E2
from PIL import Image
OUT=os.path.dirname(os.path.abspath(__file__))
A="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc"
def f(p): return f"file://{A}/{p}"
def title(a,b,top=200,size=140): return f'<h1 style="top:{top}px;font-size:{size}px">{a}<br><i>{b}</i></h1>'
def full(src,a,b,**k): return title(a,b,**k)+phone(src,170,700,980)
X="""
.langrow{position:absolute;left:0;right:0;top:580px;display:flex;justify-content:center;gap:14px;flex-wrap:nowrap}
.lc{padding:14px 26px;border-radius:999px;background:rgba(255,255,255,.7);color:#8E8E93;font-size:38px;font-weight:600;white-space:nowrap}
.lc.on{background:#0A5CF5;color:#fff}
.chip{position:absolute;padding:26px 46px;border-radius:999px;background:#fff;font-size:58px;font-weight:700;color:#111;
 box-shadow:0 0 0 2px rgba(0,0,0,.04),0 24px 60px rgba(0,0,0,.14);white-space:nowrap;letter-spacing:-1px}
.chip.b{background:#0A5CF5;color:#fff}
.cut{position:absolute;overflow:hidden;box-shadow:0 26px 70px rgba(0,0,0,.18)}
.cut img{position:absolute;display:block}
.script{position:absolute;left:130px;width:1060px;top:640px;height:820px;overflow:hidden;font-family:-apple-system,'SF Pro Display',sans-serif;font-size:70px;line-height:1.5;font-weight:700;letter-spacing:.01em;word-spacing:.08em;color:#111;-webkit-mask-image:linear-gradient(#000 50%,rgba(0,0,0,.25) 85%,transparent 100%)}
.ill{position:absolute;border-radius:56px;overflow:hidden;background:#fff;box-shadow:0 30px 80px rgba(0,0,0,.18)}
"""
def chip(t,x,y,rot=0,cls=""): return f'<div class="chip {cls}" style="left:{x}px;top:{y}px;transform:rotate({rot}deg)">{t}</div>'
LANGS=[("English ✓",True),("日本語",False),("Español",False),("Deutsch",False),("Français",False),("中文",False)]
ROW="".join(f'<span class="lc{" on" if on else ""}">{t}</span>' for t,on in LANGS)
G1=(title("유창해진 미래의 나와","통화해요",size=124)
    +f'<div class="langrow">{ROW}</div>'
    +phone(f("raw2/tabs.png"),170,760,980))
V=f"{A}/raw3"
G2=(title("원어민 흉내 말고","유창한 나를 따라 해요",size=122)+'<p style="left:0;right:0;top:530px;text-align:center">내 목소리 그대로, 유창해진 내가 말해요.</p>'
    +phone(f("raw3/voice-recording.png"),40,860,820,extra="transform:rotate(-5deg)")
    +phone(f("raw3/voice-meet.png"),460,960,820,extra="transform:rotate(4deg)"))
SP=f"{A}/raw3/speech.png"; LIVE=f"{A}/live/ko_07.png"
def cut(src,sw,x,y,w,h,X,Y,W,rad,extra=""):
    # one region of a screenshot, cut on its own edge: no frame, no padding
    k=W/w
    return (f'<div class="cut" style="left:{X}px;top:{Y}px;width:{W}px;height:{h*k}px;border-radius:{rad*k}px;{extra}">'
            f'<img src="file://{src}" style="width:{sw*k}px;left:{-x*k}px;top:{-y*k}px"></div>')
SCRIPT=("<div class='script'>Have you ever had the perfect sentence in your head, only to watch it fall apart "
        "the moment you said it? Speaking is a skill, not just knowledge. You can know the words and the grammar, "
        "but if your mouth has never actually built the sentence, it tends to fall apart.</div>")
# one grid: the script and the camera card share x 130..1190; the card ends where the phones do (2760)
CAM_W=1060; CAM_H=CAM_W*890/863; CAM_Y=2760-CAM_H
G3=(title("매일 새 원고로","소리 내어 연습해요")+SCRIPT
    +cut(LIVE,1242,190,1652,863,890,130,CAM_Y,CAM_W,62,"box-shadow:0 40px 100px rgba(0,0,0,.20)")
    +cut(SP,1320,48,610,594,900,40,CAM_Y-150,290,86,"transform:rotate(-5deg)")
    +cut(SP,1320,678,1546,594,900,990,CAM_Y-150,290,86,"transform:rotate(5deg)"))
CB=f("raw3/composer-box.png")
G7=(title("어떤 상황이든","직접 만들어 연습해요",size=130)+phone(f("raw3/watchtab-sky.png"),170,700,980)
    +card(CB,8,655,388,160,50,2240,1220,pad=10,extra="background:#F2F2F7"))
SHOTS=[
 ("01_hand",None),
 ("02_voice",G2),
 ("03_tutor",E2),
 ("04_speech",G3),
 ("05_fix",full(f("dev/fix.png"),"틀린 문법은","통화 중에 잡아줘요")),
 ("06_coach",full(f("dev/coach.png"),"말이 막히면","답할 문장이 떠요")),
 ("07_shadow",full(f("raw3/shadow-result.png"),"입에 붙을 때까지","따라 말해요")),
 ("08_situation",G7),
 ("09_book",full(f("raw3/talkdetail.png"),"통화 한 번이","복습 교재 한 권")),
 ("10_routine",full(f("raw3/activity-week.png"),"내가 정한 루틴대로","매일 이어가요")),
]
import shutil
for name,body in SHOTS:
    if body is None: shutil.copy(f"{A}/dev/hand_1320.png", f"{OUT}/G-set/{name}.png")  # the live store opener, kept as is
    else: render(body,CSS+X,f"{OUT}/G-set/{name}.png")
ims=[Image.open(f"{OUT}/G-set/{n}.png").convert("RGB").resize((440,956)) for n,_ in SHOTS]
sheet=Image.new("RGB",(5*460+20,2*980+20),"#fff")
for i,im in enumerate(ims): sheet.paste(im,(20+(i%5)*460,20+(i//5)*980))
sheet.save(f"{OUT}/G_sheet.jpg",quality=88)
