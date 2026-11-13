import os,subprocess,sys,tempfile
S=os.path.dirname(os.path.abspath(__file__)); ROOT="/Users/eunggyuelee/FutureVoice"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W,H=1320,2868
def k(n): return f"file://{S}/k/{n}-ko.png"
BASE=f"""@font-face{{font-family:GP;src:url(file://{ROOT}/web/GeistPixel.ttf)}}
@font-face{{font-family:GM;src:url(file://{ROOT}/web/Galmuri14.woff2)}}
*{{margin:0;padding:0;box-sizing:border-box}}html,body{{height:{H}px;overflow:hidden}}
body{{font-family:-apple-system,'Apple SD Gothic Neo',sans-serif;position:relative;word-break:keep-all}}
.ph{{position:absolute;border-radius:150px;background:#0D1117;padding:24px}}
.ph .sc{{width:100%;height:100%;border-radius:128px;overflow:hidden;background:#fff}}
.ph img{{width:100%;display:block}}
.crop{{position:absolute;overflow:hidden}} .crop img{{position:absolute;display:block}}
"""
def phone(src,x,y,w,rot=0,extra=""):
    h=int(w*2172/1000); 
    return f'<div class="ph" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;transform:rotate({rot}deg);padding:{w*.024}px;border-radius:{w*.15}px;{extra}"><div class="sc" style="border-radius:{w*.128}px"><img src="{src}"></div></div>'
def crop(src,px,py,pw,ph,x,y,w,extra="",cls=""):
    """crop a region given in iOS points from a 402pt-wide screen, drawn w px wide at (x,y)"""
    s=w/pw
    return (f'<div class="crop {cls}" style="left:{x}px;top:{y}px;width:{w}px;height:{ph*s}px;{extra}">'
            f'<img src="{src}" style="width:{402*s}px;left:{-px*s}px;top:{-py*s}px"></div>')
def card(src,px,py,pw,ph,x,y,w,pad=40,extra=""):
    sc=(w-2*pad)/pw
    return (f'<div class="card" style="position:absolute;left:{x}px;top:{y}px;width:{w}px;height:{ph*sc+2*pad}px;{extra}">'
            f'<div class="crop" style="left:{pad}px;top:{pad}px;width:{w-2*pad}px;height:{ph*sc}px">'
            f'<img src="{src}" style="width:{402*sc}px;left:{-px*sc}px;top:{-py*sc}px"></div></div>')
def render(body,css,out,w=W):
    html=f'<!doctype html><meta charset="utf-8"><style>{BASE}html,body{{width:{w}px}}{css}</style><body>{body}</body>'
    p=f"{S}/_t.html"; open(p,"w").write(html)
    subprocess.run([CHROME,"--headless=new","--disable-gpu","--hide-scrollbars",f"--user-data-dir={S}/prof",
      "--allow-file-access-from-files","--force-device-scale-factor=1",f"--window-size={w},{H}",
      "--virtual-time-budget=1500",f"--screenshot={out}",f"file://{p}"],check=True,capture_output=True)

# ───────── A: ink, left-aligned bold sans, one phone bleeding off the bottom
A_CSS="""body{background:#0D1117;color:#fff}
.n{position:absolute;left:100px;top:170px;font:400 44px GP;color:#6FA1FF;letter-spacing:2px}
h1{position:absolute;left:96px;top:250px;font-weight:800;font-size:150px;line-height:1.14;letter-spacing:-5px}
h1 em{font-style:normal;color:#6FA1FF}
p{position:absolute;left:100px;top:660px;font-size:54px;line-height:1.36;color:#9AA3B2;font-weight:500}
.ph{background:#23272F;box-shadow:0 0 0 3px #3a404b inset,0 80px 200px rgba(10,92,245,.35)}
.glow{position:absolute;left:-200px;top:1100px;width:1720px;height:1720px;border-radius:50%;background:radial-gradient(closest-side,rgba(10,92,245,.45),rgba(10,92,245,0))}
"""
A=[("01","<em>유창해진 나</em>와<br>통화해요","60초 녹음으로 만든 내 목소리.<br>첫 20분은 무료예요.","nw-ring-answered"),
   ("02","매일 그 시간,<br><em>전화</em>가 울려요","알람처럼 울리니까 매일 말하게 돼요.","nw-ring-ring"),
   ("03","통화 한 번이<br><em>교재 한 권</em>","단어, 표현, 고친 문장이 그대로 남아요.","nw-bookpage-cover")]
# ───────── B: blue ground, no device, zoomed real UI pieces
B_CSS="""body{background:#0A5CF5;color:#fff}
h1{position:absolute;left:0;right:0;top:230px;text-align:center;font-weight:800;font-size:164px;line-height:1.13;letter-spacing:-6px}
p{position:absolute;left:0;right:0;top:650px;text-align:center;font-size:54px;line-height:1.36;color:rgba(255,255,255,.78);font-weight:500}
.card{border-radius:72px;background:#fff;box-shadow:0 60px 140px rgba(3,30,90,.45)}
.circle{border-radius:50%;box-shadow:0 60px 140px rgba(3,30,90,.45),0 0 0 14px rgba(255,255,255,.25)}
"""
B=[("내 목소리가<br>유창하게 말해요","60초 녹음이면 돼요. 첫 20분은 무료예요.",
     crop(k("nw-home-home"),61,302,280,280,160,900,1000,cls="circle")+card(k("nw-call-speaking"),10,596,340,118,90,2060,1140)),
   ("틀린 말은<br>바로 고쳐줘요","통화 중에, 내가 한 말 그대로.",
     card(k("nw-call-fix"),50,176,346,220,40,920,1240,pad=30)+card(k("nw-call-fix"),10,402,330,198,120,1820,1100)),
   ("막히면<br>답할 문장이 떠요","질문마다 내 레벨에 맞는 한 문장.",
     card(k("nw-call-coach"),56,286,340,92,300,880,980)+card(k("nw-call-coach"),10,404,330,138,40,1340,1060)
     +card(k("nw-call-coach"),64,646,274,152,130,1930,1150,pad=50))]
# ───────── C: one panorama, sliced in three
C_CSS="""body{background:#EEF1F6;color:#0D1117}
h1{position:absolute;top:210px;width:1320px;text-align:center;font:400 168px/1.1 GM,GP;letter-spacing:-2px}
h1 em{font-style:normal;color:#0A5CF5}
p{position:absolute;top:470px;width:1320px;text-align:center;font-size:52px;color:#59606D;font-weight:500;line-height:1.36}
.ph{box-shadow:0 0 0 3px #2a2f38 inset,60px 90px 140px rgba(13,17,23,.22)}
.circle{border-radius:50%;box-shadow:0 50px 120px rgba(13,17,23,.16)}
.card{border-radius:64px;background:#fff;box-shadow:0 50px 120px rgba(13,17,23,.16)}
.band{position:absolute;left:-100px;top:1500px;width:4200px;height:760px;background:#0A5CF5;transform:rotate(-4deg)}
"""
C_BODY=('<div class="band"></div>'
 '<h1 style="left:0"><em>유창해진 나</em>와</h1><p style="left:0">60초 녹음으로 만든 내 목소리</p>'
 '<h1 style="left:1320px">매일 <em>통화</em>하고</h1><p style="left:1320px">틀린 말은 통화 중에 고쳐줘요</p>'
 '<h1 style="left:2640px"><em>교재</em>로 남겨요</h1><p style="left:2640px">단어, 표현, 고친 문장 그대로</p>'
 + crop(k("nw-home-home"),61,302,280,280,90,860,760,cls="circle")
 + phone(k("nw-ring-answered"),830,760,980,-6)
 + phone(k("nw-bookpage-cover"),2160,820,980,6)
 + card(k("nw-call-fix"),50,176,346,220,1600,2160,700,pad=22,extra="transform:rotate(3deg)")
 + card(k("nw-routine-day-kept"),0,200,402,300,3200,1000,720,pad=20,extra="transform:rotate(-3deg);overflow:hidden")
 + card(k("nw-sayagain-yourline"),14,644,374,188,3190,1960,740,pad=20,extra="transform:rotate(2deg)"))

os.makedirs(f"{S}/out",exist_ok=True)
which=sys.argv[1] if len(sys.argv)>1 else "ABC"
if "A" in which:
    for i,(n,t,s,src) in enumerate(A,1):
        body=f'<div class="glow"></div><div class="n">{n}</div><h1>{t}</h1><p>{s}</p>'+phone(k(src),130,900,1060)
        render(body,A_CSS,f"{S}/out/A{i}.png")
if "B" in which:
    for i,(t,s,b) in enumerate(B,1): render(f"<h1>{t}</h1><p>{s}</p>{b}",B_CSS,f"{S}/out/B{i}.png")
if "C" in which:
    render(C_BODY,C_CSS,f"{S}/out/C_pano.png",w=3960)
    from PIL import Image
    im=Image.open(f"{S}/out/C_pano.png").convert("RGB")
    for i in range(3): im.crop((i*1320,0,(i+1)*1320,H)).save(f"{S}/out/C{i+1}.png")
# preview sheets
from PIL import Image
for d in which:
    ims=[Image.open(f"{S}/out/{d}{i}.png").convert("RGB").resize((440,956)) for i in (1,2,3)]
    sh=Image.new("RGB",(440*3+ (0 if d=="C" else 40),956),"#888")
    for i,im in enumerate(ims): sh.paste(im,(i*(440+(0 if d=="C" else 20)),0))
    sh.save(f"{S}/out/{d}_sheet.jpg",quality=85)
