# E: the D direction on real captures from the current app (2026-11-13).
# Raw captures: iPhone 17 Pro Max simulator, Debug build, -capture tabs / -tutorShow chat / speech-season2.
import gen, os
from gen import card, crop, render
def phone(src,x,y,w,island=False,extra=''):
    p=w*.026; h=(w-2*p)*2868/1320+2*p
    return (f'<div class="ph" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;padding:{p}px;border-radius:{w*.15}px;{extra}">'
            f'<div class="sc" style="border-radius:{w*.125}px;position:relative"><img src="{src}">'
            + (f'<div style="position:absolute;left:50%;top:{w*.03}px;width:{w*.3}px;height:{w*.085}px;margin-left:-{w*.15}px;border-radius:{w*.05}px;background:#000"></div>' if island else '')
            + '</div></div>')
OUT=os.path.dirname(os.path.abspath(__file__))
FR="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/fr"
RAW="/private/tmp/claude-502/-Users-eunggyuelee-FutureVoice/28555fe9-7198-4899-99bf-1aa90e91e314/scratchpad/asc/raw2"
def r(n): return f"file://{RAW}/{n}.png"
ICON="file:///Users/eunggyuelee/FutureVoice/FutureVoice/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
CSS="""body{background:linear-gradient(#F1F1F3,#E4E4E8);color:#111}
h1{position:absolute;left:0;right:0;text-align:center;font-weight:800;font-size:140px;line-height:1.18;letter-spacing:-6px}
h1 i{font-style:normal;color:#A3A3A8}
h1.l{text-align:left;left:100px}
p{position:absolute;font-size:54px;line-height:1.42;font-weight:500;letter-spacing:-1.5px;color:#6E6E73}
.ph{background:linear-gradient(120deg,#C9CBD0,#F4F4F6 40%,#B9BBC1);box-shadow:0 0 0 4px #A9ABB1 inset,0 50px 120px rgba(0,0,0,.14)}
.icon{position:absolute;border-radius:23%;overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,.25),0 0 0 20px #fff}
.icon img{width:100%;display:block}
.card{border-radius:64px;background:#fff;box-shadow:0 0 0 18px rgba(255,255,255,.6),0 30px 80px rgba(0,0,0,.08)}
.g{background:#F2F2F7}
.face{border-radius:50%;box-shadow:0 30px 80px rgba(0,0,0,.14)}
.tile{position:absolute;left:100px;top:200px;width:200px;height:200px;border-radius:48px;background:#0A5CF5;display:grid;place-items:center}
"""
E1=('<h1 style="top:200px">유창해진 나와<br><i>매일 통화</i></h1>'
    + phone(r("tabs"),170,700,980)
    + f'<div class="icon" style="left:550px;top:560px;width:220px;height:220px"><img src="{ICON}"></div>')
E2=('<h1 style="top:200px">시험도 면접도<br><i>튜터가 챙겨요</i></h1>'
    + '<p style="left:0;right:0;top:580px;text-align:center">날짜에 맞춰 오늘 할 일을 골라 줘요.</p>'
    + crop(r("tabs"),328,728,55,55,560,820,200,cls="face")
    + card(r("tutor"),21,162,324,130,90,1100,1140,pad=46,extra="background:#F2F2F7")
    + card(r("tutor"),21,334,324,235,90,1720,1140,pad=46,extra="background:#F2F2F7"))
TROPHY='<svg width="110" height="110" viewBox="0 0 24 24" fill="#fff"><path d="M7 3h10v2h3v3a4 4 0 0 1-4 4h-.3A5 5 0 0 1 13 14.9V17h3v3H8v-3h3v-2.1A5 5 0 0 1 8.3 12H8a4 4 0 0 1-4-4V5h3V3zm0 4H6v1a2 2 0 0 0 1 1.7V7zm10 0v2.7A2 2 0 0 0 18 8V7h-1z"/></svg>'
E3=(f'<div class="tile">{TROPHY}</div>'
    '<h1 class="l" style="top:470px">같은 원고로<br>순위를 겨뤄요</h1>'
    '<p style="left:104px;right:90px;top:860px">원고를 읽으면 점수가 나와요.<br>잘한 기록이 리더보드에 올라가요.</p>'
    + card(r("speech-season2"),22,194,358,169,90,1180,1140,pad=40)
    + card(r("speech-season2"),22,392,166,185,90,1860,550,pad=26)
    + card(r("speech-season2"),214,392,166,185,680,1860,550,pad=26))
def sheet(x,y,w):
    # the result page's score container, cut out on its own rounded edge
    sx,sy,sw,sh,rad=26,2111,1155,400,100
    k=w/sw
    return (f'<div style="position:absolute;left:{x}px;top:{y}px;width:{w}px;height:{sh*k}px;border-radius:{rad*k}px;overflow:hidden;'
            f'box-shadow:0 40px 100px rgba(0,0,0,.28),0 0 0 3px rgba(255,255,255,.7)">'
            f'<img src="file://{FR}/score_clean.png" style="position:absolute;width:{1206*k}px;left:{-sx*k}px;top:{-sy*k}px"></div>')
E3=('<h1 style="top:200px">카메라 보고 읽으면<br><i>바로 점수가 나와요</i></h1>'
    + phone(f"file://{FR}/split_h.png",170,700,980,island=True))
for i,b in enumerate([E1,E2,E3],1): render(b,CSS,f"{OUT}/E-latest/E{i}.png")
from PIL import Image
im=Image.new("RGB",(1320*3+80,2868),"#fff")
for i in range(3): im.paste(Image.open(f"{OUT}/E-latest/E{i+1}.png").convert("RGB"),(i*1360,0))
im.resize((im.width//3,im.height//3)).save(f"{OUT}/E_sheet.jpg",quality=88)
