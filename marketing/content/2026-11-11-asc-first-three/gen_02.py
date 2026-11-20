# Mockups for shot 02 (voice): three directions, Korean.
import sys
R="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/raw3"
sys.argv=["x","ko",R]
import gen_lang as g
EXTRA="""<style>
.orb{position:absolute;border-radius:50%;overflow:hidden}
.orb img{position:absolute;display:block}
.lab{position:absolute;left:0;right:0;text-align:center;font-weight:700;color:#111}
.lab small{display:block;font-size:40px;font-weight:600;color:#8E8E93;margin-top:8px}
.bub{position:absolute;padding:34px 46px;border-radius:52px;background:#fff;font-size:52px;font-weight:600;line-height:1.3;color:#111;box-shadow:0 30px 80px rgba(0,0,0,.10)}
.chip{position:absolute;padding:26px 48px;border-radius:999px;font-size:60px;font-weight:700;white-space:nowrap}
.arrow{position:absolute;left:640px;width:40px;font-size:110px;color:#0A5CF5;text-align:center;margin-left:-20px;font-weight:300}
</style>"""
def orb(img,cx,cy,r,X,Y,D,extra=""):
    k=D/(2*r)
    return (f'<div class="orb" style="left:{X}px;top:{Y}px;width:{D}px;height:{D}px;{extra}">'
            f'<img src="file://{R}/{img}.png" style="width:{1320*k}px;left:{-(cx-r)*k}px;top:{-(cy-r)*k}px"></div>')
T=g.C["s02"]
# A: before → after, no phone
A=(g.title(T,size=122)+g.sub(g.C["s02sub"],530)+EXTRA
   +orb("voice-recording",660,696,286,460,820,400,"box-shadow:0 30px 80px rgba(0,0,0,.10);background:#fff")
   +'<div class="lab" style="top:1250px;font-size:56px">1분 녹음<small>지금의 내 목소리</small></div>'
   +'<div class="arrow" style="top:1440px">↓</div>'
   +orb("voice-meet",660,795,210,310,1640,700,"box-shadow:0 40px 120px rgba(10,92,245,.35),0 0 0 22px rgba(255,255,255,.7)")
   +'<div class="lab" style="top:2400px;font-size:72px">유창해진 나<small>같은 목소리로, 영어로 말해요</small></div>')
# B: one phone, the orb lifted out of it
B=(g.title(T,size=122)+g.sub(g.C["s02sub"],530)+EXTRA
   +g.phone("voice-meet",170,760,980)
   +orb("voice-meet",660,795,210,360,1060,600,"box-shadow:0 50px 140px rgba(10,92,245,.40),0 0 0 26px #fff")
   +'<div class="bub" style="left:120px;top:1720px;transform:rotate(-2deg)">"Hi! It\'s you, just a few<br>years from now."</div>')
# C: the choice, said with two chips, then one phone
C=(g.title(T,size=122)+EXTRA
   +'<div class="chip" style="left:120px;top:560px;background:#E4E4E8;color:#A3A3A8;text-decoration:line-through">원어민 목소리</div>'
   +'<div class="chip" style="left:700px;top:560px;background:#0A5CF5;color:#fff;box-shadow:0 20px 50px rgba(10,92,245,.35)">내 목소리 ✓</div>'
   +g.phone("voice-meet",170,800,980))
for n,b in (("02A",A),("02B",B),("02C",C)): g.render(b,f"{g.OUT}/out/{n}.png")
from PIL import Image
ims=[Image.open(f"{g.OUT}/out/{n}.png").convert("RGB").resize((440,956)) for n in ("02A","02B","02C")]
old=Image.open(f"{g.OUT}/G-set/02_voice.png").convert("RGB").resize((440,956))
s=Image.new("RGB",(4*460+20,976),"#fff")
for i,im in enumerate([old]+ims): s.paste(im,(20+i*460,10))
s.save(f"{g.OUT}/out/02_options.jpg",quality=88)
