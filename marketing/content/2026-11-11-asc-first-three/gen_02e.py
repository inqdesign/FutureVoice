# Shot 02 (founder 11-14): meet the fluent you, same-size phone, four reasons each with a drawing
# (gpt-image-2, the speech challenge pictures' style; sources in scratchpad/ill).
import sys
R="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/raw3"
I="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/ill"
sys.argv=["x","ko",R]
import gen_lang as g
from PIL import Image
STYLE="""<style>html{background:#E4E4E8}
.rc{position:absolute;width:560px;height:250px;border-radius:48px;background:#fff;box-shadow:0 24px 70px rgba(0,0,0,.13)}
.rc img{position:absolute;bottom:22px}
.rc .tx{position:absolute;top:44px;right:34px;width:300px}
.rc small{display:block;font-size:32px;font-weight:700;color:#8E8E93;margin-bottom:8px}
.rc b{display:block;font-size:46px;font-weight:800;line-height:1.22;color:#111;letter-spacing:-0.02em}
</style>"""
def rc(pic,tag,text,x,y,h=330):
    w,hh=Image.open(f"{I}/{pic}_a.png").size; k=min(h/hh,180/w); iw,ih=w*k,hh*k
    return (f'<div class="rc" style="left:{x}px;top:{y}px"><img src="file://{I}/{pic}_a.png" style="left:{24+(180-iw)/2}px;height:{ih}px">'
            f'<div class="tx"><small>{tag}</small><b>{text}</b></div></div>')
body=(g.title(("유창해진 나를","만나요"))+STYLE+g.phone("voice-meet",170,700,980)
      +rc("shadow","쉐도잉","내 목소리라<br>그대로 따라 해요",30,1180)
      +rc("fix","교정","틀린 말은<br>바로 고쳐 줘요",730,1560)
      +rc("calm","안정감","상대가 나라서<br>창피하지 않아요",30,1990,300)
      +rc("goal","목표","되고 싶은 내가<br>눈앞에 있어요",730,2380))
g.render(body,f"{g.OUT}/out/02G.png")
