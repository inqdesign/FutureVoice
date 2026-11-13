# F: the whole 10-shot set in the E direction, current build (2026-11-13).
import os, gen_e
from gen_e import phone, card, crop, render, CSS, E1, E2, E3
from PIL import Image
OUT=os.path.dirname(os.path.abspath(__file__))
R3="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/raw3"
def r3(n): return f"file://{R3}/{n}.png"
def title(a,b,top=200): return f'<h1 style="top:{top}px">{a}<br><i>{b}</i></h1>'
def full(src,a,b): return title(a,b)+phone(src,170,700,980)
SHOTS=[
 ("01_home",E1),
 ("02_tutor",E2),
 ("03_speech",E3),
 ("04_fix",full(r3("call-focus"),"틀린 문법은","통화 중에 잡아줘요")),
 ("05_coach",full(r3("call-coach"),"말이 막히면","답할 문장이 떠요")
   +card(r3("call-coach"),40,676,322,60,70,2150,1180,pad=50)),
 ("06_challenge",full(r3("speech"),"매일 새 원고로","다 같이 겨뤄요")),
 ("07_pron",full(r3("call-pron"),"소리 하나까지","발음을 잡아줘요")
   +card(r3("call-pron"),14,116,390,140,70,930,1180,pad=40)),
 ("08_watch",full(r3("watchtab-sky"),"내 주변 사람과","미리 겪어 봐요")),
 ("09_book",full(r3("talkdetail"),"통화 한 번이","복습 교재 한 권")),
 ("10_routine",full(r3("activity-week"),"내가 정한 루틴대로","매일 이어가요")),
]
for name,body in SHOTS: render(body,CSS,f"{OUT}/F-set/{name}.png")
ims=[Image.open(f"{OUT}/F-set/{n}.png").convert("RGB").resize((440,956)) for n,_ in SHOTS]
sheet=Image.new("RGB",(5*460+20,2*980+20),"#fff")
for i,im in enumerate(ims): sheet.paste(im,(20+(i%5)*460,20+(i//5)*980))
sheet.save(f"{OUT}/F_sheet.jpg",quality=88)
