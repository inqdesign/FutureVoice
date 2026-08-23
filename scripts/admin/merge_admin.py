"""Fold the cost/margin views into the existing 유저 활동 page, behind tabs.

The existing page is kept whole — every chart, table and note it already had
still renders from the same DATA shape. This only adds: a tab bar, a 비용 tab,
a cost column on the user table, and the build-version panel.
"""
import json, re, sys
import os, pathlib
HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(os.environ.get("ADMIN_OUT", HERE / "build")); OUT.mkdir(parents=True, exist_ok=True)


SP = str(OUT)
# base.html is the previous published page, kept beside this script.
h = (HERE / "base.html").read_text()

def sub(old, new, label, count=1):
    global h
    assert old in h, f"anchor missing: {label}"
    h = h.replace(old, new, count)

# ---------------------------------------------------------------- 1) identity
sub("<title>nawana 유저 활동</title>", "<title>nawana 어드민</title>", "title")
sub("<h1>유저 활동</h1>", "<h1>어드민</h1>", "h1")
sub('<p class="eyebrow">nawana · 내부 분석</p>',
    '<p class="eyebrow">nawana · 내부 운영</p>', "eyebrow")

# ---------------------------------------------------------------- 2) tab CSS
sub("""*{box-sizing:border-box}""", """/* ---- tabs ---- */
.tabs{display:flex; gap:4px; flex-wrap:wrap; margin:22px 0 4px;
  border-bottom:1px solid var(--grid); position:sticky; top:0; z-index:5;
  background:var(--page); padding-top:6px}
.tabs button{appearance:none; background:none; border:none; cursor:pointer;
  font:inherit; font-size:14px; font-weight:600; color:var(--muted);
  padding:9px 14px; border-bottom:2px solid transparent; margin-bottom:-1px;
  border-radius:6px 6px 0 0}
.tabs button:hover{color:var(--ink-2); background:var(--chip)}
.tabs button[aria-selected="true"]{color:var(--ink); border-bottom-color:var(--s1)}
.tabs button:focus-visible{outline:2px solid var(--s1); outline-offset:-2px}
/* !important is load-bearing: two sections carry an inline display:grid,
   which outranks both the [hidden] UA rule and a plain stylesheet rule —
   without it those two leak into every other tab. */
section[data-tab][hidden]{display:none !important}

/* ---- cost ---- */
.costgrid{display:grid; grid-template-columns:repeat(auto-fit,minmax(230px,1fr)); gap:12px}
.mechrow{display:grid; grid-template-columns:120px 1fr auto; gap:12px; align-items:center; margin:10px 0}
.mechrow .mn{font-size:13px; color:var(--ink-2); display:flex; align-items:center; gap:7px}
.mechbar{height:20px; background:var(--chip); border-radius:4px; overflow:hidden}
.mechbar i{display:block; height:100%; border-radius:4px}
.mechval{font-size:12.5px; font-variant-numeric:tabular-nums; white-space:nowrap; font-weight:600}
.mechnote{font-size:11.5px; color:var(--muted); margin-top:4px}
.tiercard{background:var(--surface); border:1px solid var(--ring); border-radius:10px;
  padding:16px 18px; display:flex; flex-direction:column; gap:11px}
.tiercard.risk{border-color:var(--crit)}
.tiertop{display:flex; justify-content:space-between; align-items:baseline; gap:8px}
.tiername{font-size:16px; font-weight:700; letter-spacing:-.01em}
.alloc{display:flex; height:22px; border-radius:5px; overflow:hidden; background:var(--chip); gap:2px}
.tstats{display:grid; grid-template-columns:1fr 1fr; gap:8px 12px;
  border-top:1px solid var(--grid); padding-top:9px}
.tstats .k{font-size:11px; color:var(--muted); font-weight:600}
.tstats .v{font-size:15px; font-weight:700; font-variant-numeric:tabular-nums}
.flagbox{background:var(--surface); border:1px solid var(--warn); border-radius:10px; padding:16px 18px}
.flagbox code{background:var(--chip); padding:1px 5px; border-radius:4px; font-size:12.5px}
*{box-sizing:border-box}""", "tab css")

# ---------------------------------------------------------------- 3) tab bar
sub("""</header>""", """</header>

<nav class="tabs" role="tablist" aria-label="어드민 섹션">
  <button role="tab" data-go="people"   aria-selected="true">사람</button>
  <button role="tab" data-go="activity" aria-selected="false">활동</button>
  <button role="tab" data-go="cost"     aria-selected="false">비용 · 마진</button>
  <button role="tab" data-go="notes"    aria-selected="false">주석</button>
</nav>""", "tab bar")

# ---------------------------------------------------------------- 4) tag sections
TAGS = [
    ('<section>\n  <h2>이 사람들은 누구인가</h2>', 'people'),
    ('<section>\n  <h2>일별 활동</h2>', 'activity'),
    ('<section>\n  <h2>유저별 현황</h2>', 'people'),
    ('<section>\n  <h2>연속 사용 (streak)</h2>', 'activity'),
    ('<section>\n  <h2>활동 히트맵</h2>', 'activity'),
    ('<section>\n  <h2>기능 사용</h2>', 'activity'),
    ('<section>\n  <h2>유입 경로</h2>', 'people'),
    ('<section>\n  <h2>데이터 주석</h2>', 'notes'),
]
for anchor, tab in TAGS:
    sub(anchor, anchor.replace('<section>', f'<section data-tab="{tab}">'), f"tag {tab}")

# the two split (grid) sections
sub('<section style="display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px">\n  <div>\n    <h2>돌아오기까지 걸린 시간</h2>',
    '<section data-tab="activity" style="display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px">\n  <div>\n    <h2>돌아오기까지 걸린 시간</h2>',
    "tag gaps")
sub('<section style="display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px">\n  <div>\n    <h2>통화 세션 길이</h2>',
    '<section data-tab="activity" style="display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px">\n  <div>\n    <h2>통화 세션 길이</h2>',
    "tag sessions")

# ---------------------------------------------------------------- 5) cost markup
COST = """
<section data-tab="cost" hidden>
  <h2>단가</h2>
  <p class="sub">구독 요금제를 설계할 때 필요한 세 숫자예요. 통화 1분과 Watch 장면 1개가 각각 얼마인지,
  그리고 둘의 비율. 비율은 요율 가정과 무관해서 가장 단단한 숫자예요.</p>
  <div class="costgrid" id="costTiles"></div>
</section>

<section data-tab="cost" hidden>
  <h2>장면이 비싼 이유</h2>
  <p class="sub">배수가 두 번 겹쳐요. 장면은 전부 합성 음성인데 통화는 절반이 학습자 말이라 글자가 안 나가고,
  게다가 장면만 fidelity 모델이라 글자당 2배예요.</p>
  <div class="card" id="mech"></div>
</section>

<section data-tab="cost" hidden>
  <h2>요금제를 다 쓰면</h2>
  <p class="sub">산 걸 전부 썼을 때 남는지 보는 테스트예요. Plus는 통화에 상한이 없어서 장면 쪽만 한계를 매길 수 있어요 —
  통화는 "말하는 게 힘들다"는 것 말고 상한이 없어요.</p>
  <div class="costgrid" id="tierCards"></div>
  <p class="sub" style="margin-top:12px">손익분기 사용률은 순매출이 사라지기까지 쓸 수 있는 할당 비율이에요.
  Gemini가 아직 빠져 있어서 실제로는 이보다 더 빨리 넘어가요.</p>
</section>

<section data-tab="cost" hidden>
  <h2>일별 소진</h2>
  <p class="sub">ElevenLabs 글자를 아래 요율로 환산한 값이에요. Gemini는 오늘까지 한 번도 측정된 적이 없어서 비어 있어요.</p>
  <div class="card" id="costDaily"></div>
</section>

<section data-tab="cost" hidden>
  <h2>유저별 비용</h2>
  <p class="sub">가입 이후 누적이에요. 통화·장면과 나란히 두면 무엇이 돈을 쓰는지 바로 보여요.</p>
  <div class="card scroll"><table id="costTable"></table></div>
</section>

<section data-tab="cost" hidden>
  <h2>이 숫자들이 기대고 있는 것</h2>
  <div class="costgrid">
    <div class="flagbox">
      <h3 style="margin:0 0 6px;font-size:14px">숫자 하나가 전부를 움직여요</h3>
      <p class="notes" style="margin:0">이 탭의 모든 금액은 ElevenLabs 크레딧당 단가에 선형으로 비례해요.
      지금은 <b id="rateNow"></b>(Creator 티어)로 넣어뒀어요. 실제 티어를 확인하면 한 줄로 과거까지 전부 다시 계산돼요:</p>
      <p style="margin:8px 0 0"><code>select set_elevenlabs_usd_per_credit(0.000xx);</code></p>
    </div>
    <div class="card">
      <h3 style="margin:0 0 6px;font-size:14px">아직 안 재는 것</h3>
      <div class="notes"><ul>
        <li><b>Gemini 토큰</b> — 기록은 2026-08-23에 배포됐고, 위 숫자는 전부 ElevenLabs만이에요.
        통화 1분당 Gemini 호출이 약 8.8회라 반올림 오차가 아니에요.</li>
        <li><b>Supabase 대역폭</b> — PCM 오디오가 엣지 함수를 양방향으로 통과해요.</li>
        <li><b>보이스 클론 슬롯</b> — 호출당이 아니라 좌석당 비용이에요.</li>
      </ul></div>
    </div>
    <div class="card">
      <h3 style="margin:0 0 6px;font-size:14px">앱 빌드 분포</h3>
      <p class="notes" style="margin:0 0 8px">대화 턴은 있는데 <code>talk_time</code>이 0인 계정이 여럿이에요.
      구버전 앱인지 계측 버그인지 가르려면 빌드 번호가 필요해서, 이제 모든 client_event에 찍혀요.</p>
      <div class="bars" id="builds"></div>
    </div>
  </div>
</section>
"""
sub('<section data-tab="notes">\n  <h2>데이터 주석</h2>', COST + '\n<section data-tab="notes">\n  <h2>데이터 주석</h2>', "cost markup")

# ---------------------------------------------------------------- 6) cost column
sub("""<th class="num">장면</th><th class="num">리뷰</th></tr></thead><tbody>`;""",
    """<th class="num">장면</th><th class="num">비용</th><th class="num">리뷰</th></tr></thead><tbody>`;""",
    "cost th")
sub("""      <td class="num">${u.scenes||'—'}</td>
      <td class="num">${u.reviewCount||'—'}</td>""",
    """      <td class="num">${u.scenes||'—'}</td>
      <td class="num">${costOf(u.idx)?'$'+costOf(u.idx).usd.toFixed(2):'—'}</td>
      <td class="num">${u.reviewCount||'—'}</td>""",
    "cost td")

# ---------------------------------------------------------------- 7) cost JS
JS = """
/* ================= 비용 · 마진 ================= */
const C = DATA.cost;
const costOf = i => C.byUser[String(i)] || null;
const usd = (n,d=2) => '$' + Number(n).toFixed(d);

function renderCostTiles(){
  document.getElementById('costTiles').innerHTML = `
    <div class="tile"><div class="k">통화 1분</div><div class="v">${usd(C.usd_per_talk_min,4)}</div>
      <div class="d">${C.talk_credits_per_min} 크레딧 · ${Math.round(C.chars_per_min)}자</div></div>
    <div class="tile"><div class="k">Watch 장면 1개</div><div class="v">${usd(C.usd_per_scene,4)}</div>
      <div class="d">${num(C.scene_credits)} 크레딧 · ${num(Math.round(C.chars_per_scene))}자</div></div>
    <div class="tile"><div class="k">비율</div><div class="v">${C.ratio}배</div>
      <div class="d">장면 1개 = 통화 ${C.ratio}분 · 요율과 무관</div></div>`;
}

function renderMech(){
  const max = Math.max(C.talk_credits_per_min, C.scene_credits);
  const rows = [
    {n:'통화 1분', c:C.talk_credits_per_min, col:'var(--s1)',
     f:`${Math.round(C.chars_per_min)}자 × 0.5 크레딧 (turbo)`},
    {n:'장면 1개', c:C.scene_credits, col:'var(--s2)',
     f:`${num(Math.round(C.chars_per_scene))}자 × 1.0 크레딧 (fidelity)`}];
  document.getElementById('mech').innerHTML = rows.map(r=>`
    <div class="mechrow">
      <span class="mn"><span class="swatch" style="background:${r.col}"></span>${r.n}</span>
      <div><div class="mechbar"><i style="width:${(r.c/max*100).toFixed(1)}%;background:${r.col}"></i></div>
        <div class="mechnote">${r.f}</div></div>
      <span class="mechval">${num(Math.round(r.c))} cr</span>
    </div>`).join('');
}

function renderTiers(){
  document.getElementById('tierCards').innerHTML = C.tiers.map(t=>{
    const risk = t.margin < 0;
    const talkPct  = t.capped_credits ? t.talk_credits/t.capped_credits*100 : 0;
    const scenePct = t.capped_credits ? t.scene_credits/t.capped_credits*100 : 0;
    const talkLbl = t.talk_unlimited ? '상한 없음' : `${t.talk_min}분`;
    return `<div class="tiercard ${risk?'risk':''}">
      <div class="tiertop"><span class="tiername">${(PLAN_KO[t.id]||t.id)}</span>
        <span style="font-size:12.5px;color:var(--ink-2);font-variant-numeric:tabular-nums">
        ${usd(t.price)}/월 → 순 ${usd(t.net)}</span></div>
      <div class="alloc">
        ${t.talk_credits?`<div style="width:${talkPct}%;background:var(--s1)"></div>`:''}
        <div style="width:${scenePct}%;background:var(--s2)"></div></div>
      <div style="display:flex;flex-wrap:wrap;gap:5px 14px;font-size:12px;color:var(--ink-2)">
        <span><span class="swatch" style="background:var(--s1)"></span> 통화 ${talkLbl}${t.talk_credits?' · '+num(t.talk_credits)+' cr':''}</span>
        <span><span class="swatch" style="background:var(--s2)"></span> 장면 ${t.scenes}개 · ${num(t.scene_credits)} cr</span>
      </div>
      <div class="tstats">
        <div><div class="k">상한 내 원가</div><div class="v" style="color:${risk?'var(--crit)':'var(--ink)'}">${usd(t.capped_cost)}</div></div>
        <div><div class="k">마진</div><div class="v" style="color:${risk?'var(--crit)':'var(--good-text)'}">${t.margin<0?'−':'+'}${usd(Math.abs(t.margin))}</div></div>
        <div><div class="k">손익분기 사용률</div><div class="v">${t.fill_breakeven_pct}%</div></div>
        <div><div class="k">하루 장면 한계</div><div class="v">${t.scenes_per_day_breakeven}개</div></div>
      </div>
      <div style="font-size:12px;color:var(--muted)">할당의 ${t.scene_share}%가 장면이에요</div>
    </div>`;
  }).join('');
  document.getElementById('rateNow').textContent = '$' + C.rate.toFixed(8) + ' / 크레딧';
}

function renderCostDaily(){
  const n = DATA.days.length, el = Array(n).fill(0);
  for(const [d,e] of C.daily) el[d] += e;
  const W=980, LEFT=40, RIGHT=8, plotW=W-LEFT-RIGHT, bw=plotW/n, H=110, top=8, bh=H-top-16;
  const max = Math.max(0.0001, ...el);
  let s=`<div class="panel-label"><span class="swatch" style="background:var(--s2)"></span>ElevenLabs 원가
    <span style="font-weight:400;color:var(--muted);margin-left:auto">합계 ${usd(el.reduce((a,b)=>a+b,0))}</span></div>`;
  s+=`<svg width="${W}" height="${H}" role="img" aria-label="일별 ElevenLabs 원가">`;
  s+=`<line x1="${LEFT}" y1="${top+bh}" x2="${W-RIGHT}" y2="${top+bh}" class="baseline"/>`;
  s+=`<text x="${LEFT-6}" y="${top+8}" text-anchor="end" class="axis">${usd(max)}</text>`;
  DATA.days.forEach((d,i)=>{ if(!d.endsWith('-01')) return;
    const x=LEFT+i*bw;
    s+=`<line x1="${x}" y1="${top}" x2="${x}" y2="${top+bh}" class="gridline"/>`;
    s+=`<text x="${x+3}" y="${H-2}" class="axis">${+d.split('-')[1]}월</text>`; });
  for(let i=0;i<n;i++){
    if(!el[i]) continue;
    const hh=Math.max(2, el[i]/max*bh);
    const tip=`<b>${fmtDate(DATA.days[i])}</b><br>ElevenLabs ${usd(el[i],3)}`;
    s+=`<rect x="${(LEFT+i*bw).toFixed(1)}" y="${(top+bh-hh).toFixed(1)}" width="${Math.max(1.5,bw-1).toFixed(1)}"
      height="${hh.toFixed(1)}" rx="1.5" fill="var(--s2)" data-tip="${tip.replace(/"/g,'&quot;')}"/>`;
  }
  s+='</svg>';
  document.getElementById('costDaily').innerHTML=s;
}

function renderCostTable(users){
  let html=`<thead><tr><th>유저</th><th>플랜</th><th class="num">통화</th><th class="num">장면</th>
    <th class="num">TTS 글자</th><th class="num">ElevenLabs</th><th class="num">Gemini</th><th class="num">합계</th></tr></thead><tbody>`;
  const rows=[...users].map(u=>({u, c:costOf(u.idx)})).filter(r=>r.c)
    .sort((a,b)=> b.c.usd - a.c.usd);
  for(const {u,c} of rows){
    html+=`<tr>
      <td><span class="uname">${esc(nameOf(u))}</span>${u.dev?'<span class="devchip">DEV</span>':''}</td>
      <td><span class="chip">${PLAN_KO[u.plan]||u.plan||'플랜 없음'}</span></td>
      <td class="num">${u.talkSecs?fmtMin(u.talkSecs):'—'}</td>
      <td class="num">${u.scenes||'—'}</td>
      <td class="num">${num(Math.round(c.chars))}</td>
      <td class="num">${usd(c.el,3)}</td>
      <td class="num" style="color:var(--muted)">${c.gm>0?usd(c.gm,3):'미측정'}</td>
      <td class="num"><b>${usd(c.usd,3)}</b></td>
    </tr>`;
  }
  document.getElementById('costTable').innerHTML=html+'</tbody>';
}

function renderBuilds(){
  const bs=C.builds||[];
  if(!bs.length){ document.getElementById('builds').innerHTML='<div class="legend">기록 없음</div>'; return; }
  const max=Math.max(...bs.map(b=>b.users));
  document.getElementById('builds').innerHTML = bs.map(b=>
    `<div class="row"><div class="lbl">${b.build==='(unknown)'?'빌드 미상 (구버전)':'빌드 '+b.build}</div>
     <div class="track"><div class="fill" style="width:${b.users/max*100}%"></div></div>
     <div class="val">${b.users}명 · ~${fmtD(b.last_seen)}</div></div>`).join('')
   + `<div class="legend">빌드 스탬프는 2026-08-23 이후 빌드부터 찍혀요</div>`;
}

/* ================= 탭 ================= */
function showTab(name){
  document.querySelectorAll('section[data-tab]').forEach(s=>{
    s.hidden = s.dataset.tab !== name;
  });
  document.querySelectorAll('.tabs button').forEach(b=>{
    b.setAttribute('aria-selected', String(b.dataset.go === name));
  });
  try{ localStorage.setItem('nawana.admin.tab', name); }catch(e){}
  hideTip();
}
document.querySelectorAll('.tabs button').forEach(b=>{
  b.addEventListener('click', ()=>showTab(b.dataset.go));
});
let startTab='people';
try{ const t=localStorage.getItem('nawana.admin.tab');
     if(t && document.querySelector(`.tabs button[data-go="${t}"]`)) startTab=t; }catch(e){}
showTab(startTab);

renderCostTiles(); renderMech(); renderTiers(); renderCostDaily(); renderBuilds();
"""
sub("""renderFeatures();
renderChannels();
render();""", JS + """
renderFeatures();
renderChannels();
render();""", "cost js")

# cost table must re-render with the dev toggle
sub("""  renderSessions(vis);
  renderErrors();""", """  renderSessions(vis);
  renderErrors();
  renderCostTable(users);""", "wire cost table")

# ---------------------------------------------------------------- 8) plan names
sub("const PLAN_KO = {light_monthly:'라이트', plus_monthly:'플러스', light_yearly:'라이트(연)', plus_yearly:'플러스(연)'};",
    "const PLAN_KO = {light_monthly:'Light 월간', plus_monthly:'Plus 월간', "
    "light_annual:'Light 연간', plus_annual:'Plus 연간', "
    "light_yearly:'Light(연)', plus_yearly:'Plus(연)'};", "plan names")

# ---------------------------------------------------------------- 10) owner is a user
# The owner practises on the app daily and is the only account with enough
# metered talk to derive a cost per minute from, so he counts as a user rather
# than as a fixture. The toggle now governs ONLY the synthetic device-test
# account. What stays true — and is now said where the aggregates are, not
# buried in the notes — is that his volume dominates every total.
sub('<label class="toggle"><input type="checkbox" id="devToggle"> 개발·테스트 계정 포함</label>',
    '<label class="toggle"><input type="checkbox" id="devToggle"> 테스트 계정 포함</label>',
    "toggle label")

sub(".devchip{font-size:10.5px;",
    ".ownchip{font-size:10.5px; font-weight:600; color:var(--s1); border:1px solid var(--s1);"
    " border-radius:4px; padding:0 5px; margin-left:6px; vertical-align:1px}\n"
    ".devchip{font-size:10.5px;", "own chip css")

# card + table badges
sub("""<div class="top"><span class="nm">${esc(nameOf(u))}</span>${u.dev?'<span class="devchip">DEV</span>':''}</div>""",
    """<div class="top"><span class="nm">${esc(nameOf(u))}</span>${badge(u)}</div>""", "card badge")
sub("""<span class="uname">${esc(nameOf(u))}</span>${u.dev?'<span class="devchip">DEV</span>':''}""",
    """<span class="uname">${esc(nameOf(u))}</span>${badge(u)}""", "table badge")
sub("""<span class="uname">${esc(nameOf(u))}</span>${u.dev?'<span class="devchip">DEV</span>':''}</td>""",
    """<span class="uname">${esc(nameOf(u))}</span>${badge(u)}</td>""", "cost table badge")

# one badge helper, defined next to nameOf
sub("const nameOf = u => u.name || (u.email ? u.email.split('@')[0] : u.label);",
    "const nameOf = u => u.name || (u.email ? u.email.split('@')[0] : u.label);\n"
    "const badge = u => u.owner ? '<span class=\"ownchip\">본인</span>'\n"
    "  : u.dev ? '<span class=\"devchip\">TEST</span>' : '';", "badge helper")

sub("""{k:'가입 계정', v:num(users.length), d:document.getElementById('devToggle').checked?'개발·테스트 포함':'실사용자만'},""",
    """{k:'가입 계정', v:num(users.length), d:document.getElementById('devToggle').checked?'테스트 계정 포함':'테스트 계정 제외'},""",
    "tile caption")

# Say the distortion where it bites, not only in the notes.
sub("""<section>
  <div class="tiles" id="tiles"></div>
</section>""", """<section>
  <div class="tiles" id="tiles"></div>
  <p class="sub" style="margin:10px 0 0" id="ownerNote"></p>
</section>""", "owner note slot")

sub("renderCostTiles(); renderMech();",
    "renderOwnerNote(); renderCostTiles(); renderMech();", "wire owner note")

sub("/* ================= 탭 ================= */", """function renderOwnerNote(){
  const o = DATA.users.find(u=>u.owner);
  if(!o) return;
  const turns = DATA.users.reduce((a,u)=>a+u.turns,0);
  const secs  = DATA.users.reduce((a,u)=>a+u.talkSecs,0);
  const pt = turns ? Math.round(o.turns/turns*100) : 0;
  const ps = secs  ? Math.round(o.talkSecs/secs*100) : 0;
  document.getElementById('ownerNote').innerHTML =
    `본인 계정(<b>${esc(nameOf(o))}</b>)도 한 명의 유저로 포함돼 있어요 — 매일 쓰는 실사용이고, `
  + `통화 시간이 제대로 측정되는 유일한 계정이라 원가 계산이 여기서 나와요. `
  + `다만 전체 대화 턴의 <b>${pt}%</b>, 통화 시간의 <b>${ps}%</b>가 이 한 계정이라 `
  + `합계·평균은 거의 본인 숫자로 읽으세요. 개인별 비교는 아래 표가 정확해요.`;
}

/* ================= 탭 ================= */""", "owner note fn")

# notes rewrite
sub("대화 턴은 통화 중 Gemini 응답 호출 수예요.",
    "대화 턴은 <b>응답 생성 호출 1건 = 1턴</b>이에요. 전사 호출과 둘로 쪼개 보내는 TTS는 빼고, "
    "버려지는 투기 호출도 빼요 — 예전 집계는 이것들을 같이 세서 수치가 3배쯤 컸어요.",
    "turn definition")

sub("<li>개발 계정 2개(본인 계정, android-dev-test)는 기본으로 제외돼요 — 본인 계정이 전체 활동의 대부분이라 포함하면 실제 유저의 패턴이 묻혀요.</li>",
    "<li><b>본인 계정은 유저로 셈해요</b> — 매일 쓰는 실사용이고, 통화 시간이 측정되는 사실상 유일한 계정이라 "
    "원가·세션 통계가 여기서 나와요. 대신 활동량이 압도적이라 <b>합계와 평균은 본인 숫자에 가깝다</b>는 걸 "
    "감안해서 보세요 — 개인별 비교는 표를 쓰면 돼요. 합성 테스트 계정(android-dev-test)만 기본 제외예요.</li>",
    "notes dev")
sub("무료 기능의 일일 사용 기록(free_usage_daily) 누적 호출 수 — 전 계정 합산이라 개발 계정 토글의 영향을 받지 않아요.",
    "무료 기능의 일일 사용 기록(free_usage_daily) 누적 호출 수 — 전 계정 합산이라 테스트 계정 토글의 영향을 받지 않아요.",
    "notes features")
sub("전 계정 합산 — 개발 계정 토글의 영향을 받지 않아요.",
    "전 계정 합산 — 테스트 계정 토글의 영향을 받지 않아요.", "legend features")
sub("통화 시간이 측정되는 실사용자가 1명뿐이라, 하루 240초를 넘긴 날은 개발 계정에만 있어요.",
    "통화 시간이 측정되는 계정이 사실상 본인 하나뿐이라, 하루 240초를 넘긴 날이 거기에만 있어요.",
    "notes core")

# ---------------------------------------------------------------- 11) window
# The page now starts the day Talk became the unit of account. Two things have
# to follow, or the charts quietly lie about people who were already here.
sub("const signup = DATA.days.indexOf(DATA.users[idx].signedUp);",
    "// Observation origin, not signup: for anyone who joined before the\n"
    "  // cutover the first weeks are simply not in this data, and indexing on\n"
    "  // signedUp would return -1 and poison every span below.\n"
    "  const signup = DATA.days.indexOf(DATA.users[idx].origin);",
    "streak origin")

# Week-N retention is meaningless for someone whose week 0 predates the data.
sub("""    for(const u of users){
      const s=streakOf(u.idx), a=s.signup+w*7, b=s.signup+w*7+6;""",
    """    for(const u of users){
      if(u.preWindow) continue;   // week 0 is outside the window
      const s=streakOf(u.idx), a=s.signup+w*7, b=s.signup+w*7+6;""",
    "retention window")

sub("<p class=\"sub\">그 주에 한 번이라도 대화한 사람 수. 해당 주를 다 채운 유저만 셈에 넣어요.</p>",
    "<p class=\"sub\">그 주에 한 번이라도 대화한 사람 수. 해당 주를 다 채운 유저만, "
    "그리고 <b>측정 시작 이후에 가입한 유저만</b> 세요 — 그 전에 가입한 사람은 첫 주가 데이터 밖이에요.</p>",
    "retention copy")

sub("가로축은 가입 후 경과일", "가로축은 측정 시작(또는 가입) 후 경과일", "lane axis legend")
sub(">${d===0?'가입일':d+'일'}<", ">${d===0?'시작':d+'일'}<", "lane axis tick")

# The as-of line has to say what window it is reporting on.
sub("document.getElementById('asof').textContent = `${fmtDate(DATA.asOf)} 기준 · 프로덕션 DB에서 직접 집계`;",
    "document.getElementById('asof').textContent = "
    "`${fmtDate(DATA.windowStart)} ~ ${fmtDate(DATA.asOf)} · 프로덕션 DB에서 직접 집계`;",
    "asof line")

sub("<li><b>통화 시간</b>은 TalkMeter가 배포된 <b>2026-08-10부터</b>만 측정돼요. 베타 유저들의 7월 대화는 턴 수에는 있지만 통화 시간에는 0으로 보여요.</li>",
    "<li><b>이 페이지는 2026-08-10부터예요</b> — Talk이 계산 단위가 된 날이고, "
    "`talk_time`·`tts_scene`·`free_usage_daily`가 모두 그날 처음 기록됐어요. 그 이전은 턴 수 말고는 "
    "비교할 게 없어서 평균만 끌어내려요. 6~7월 베타 활동은 의도적으로 빠져 있어요.</li>",
    "notes window")

sub("<li><b>Watch 장면</b>도 장면 단위 과금이 시작된 8/10 이후 기록이에요.</li>",
    "<li><b>Watch 장면 수</b>는 장면 단위 과금이 켜진 <b>8/14</b>부터예요 — 8/10~13의 장면 오디오는 "
    "원가에는 잡히지만 재생 횟수로는 안 남아서, 장면 개당 단가는 8/14 이후 창으로만 계산해요.</li>",
    "notes scenes")

# ---------------------------------------------------------------- 12) period filter
sub("""  <p class="sub">가입 이후 누적이에요. 통화·장면과 나란히 두면 무엇이 돈을 쓰는지 바로 보여요.</p>
  <div class="card scroll"><table id="costTable"></table></div>""",
    """  <p class="sub">통화·장면과 나란히 두면 무엇이 돈을 쓰는지 바로 보여요. 달로 끊어 볼 수 있어요.</p>
  <div class="seg" id="costMonths" role="group" aria-label="기간"></div>
  <div class="card scroll"><table id="costTable"></table></div>""",
    "period markup")

sub("/* ---- cost ---- */", """.seg{display:flex; gap:4px; flex-wrap:wrap; margin:0 0 12px}
.seg button{appearance:none; font:inherit; font-size:13px; font-weight:600; cursor:pointer;
  background:var(--surface); color:var(--ink-2); border:1px solid var(--ring);
  border-radius:7px; padding:6px 12px; font-variant-numeric:tabular-nums}
.seg button:hover{background:var(--chip)}
.seg button[aria-pressed="true"]{background:var(--ink); color:var(--page); border-color:var(--ink)}
.seg button:focus-visible{outline:2px solid var(--s1); outline-offset:2px}

/* ---- cost ---- */""", "seg css")

# The table reads whichever period is selected; 전체 keeps the windowed totals.
sub("""function renderCostTable(users){""",
    """let costPeriod = 'all';   // 'all' | 'YYYY-MM'

function costRow(idx){
  if(costPeriod === 'all'){
    const c = costOf(idx);
    if(!c) return null;
    const u = DATA.users[idx];
    return {usd:c.usd, el:c.el, gm:c.gm, chars:c.chars,
            talk_secs:u.talkSecs, scenes:u.scenes};
  }
  return (C.byUserMonth[costPeriod]||{})[String(idx)] || null;
}

function renderCostMonths(){
  const el = document.getElementById('costMonths');
  const opts = [['all','전체']].concat(C.months.map(m=>{
    const [y,mm] = m.split('-');
    return [m, `${y}년 ${+mm}월`];
  }));
  el.innerHTML = opts.map(([k,lab])=>
    `<button type="button" data-p="${k}" aria-pressed="${k===costPeriod}">${lab}</button>`).join('');
  el.querySelectorAll('button').forEach(b=>b.addEventListener('click', ()=>{
    costPeriod = b.dataset.p;
    renderCostMonths();
    renderCostTable(visibleUsers());
  }));
}

function renderCostTable(users){""",
    "period state")

sub("""  const rows=[...users].map(u=>({u, c:costOf(u.idx)})).filter(r=>r.c)
    .sort((a,b)=> b.c.usd - a.c.usd);
  for(const {u,c} of rows){""",
    """  const rows=[...users].map(u=>({u, c:costRow(u.idx)})).filter(r=>r.c && r.c.usd>0)
    .sort((a,b)=> b.c.usd - a.c.usd);
  if(!rows.length){
    document.getElementById('costTable').innerHTML =
      html + `<tr><td colspan="8" style="color:var(--muted)">이 기간에는 기록이 없어요.</td></tr></tbody>`;
    return;
  }
  for(const {u,c} of rows){""",
    "period rows")

sub("""      <td class="num">${u.talkSecs?fmtMin(u.talkSecs):'—'}</td>
      <td class="num">${u.scenes||'—'}</td>
      <td class="num">${num(Math.round(c.chars))}</td>""",
    """      <td class="num">${c.talk_secs?fmtMin(c.talk_secs):'—'}</td>
      <td class="num">${c.scenes||'—'}</td>
      <td class="num">${num(Math.round(c.chars))}</td>""",
    "period cells")

# total row, so a month has a headline
sub("""  document.getElementById('costTable').innerHTML=html+'</tbody>';
}

function renderBuilds(){""",
    """  const tot = rows.reduce((a,{c})=>({usd:a.usd+c.usd, el:a.el+c.el, gm:a.gm+c.gm,
      chars:a.chars+c.chars, talk:a.talk+(c.talk_secs||0), sc:a.sc+(c.scenes||0)}),
      {usd:0,el:0,gm:0,chars:0,talk:0,sc:0});
  html += `<tr style="border-top:2px solid var(--baseline)">
      <td><b>합계</b></td><td></td>
      <td class="num"><b>${tot.talk?fmtMin(tot.talk):'—'}</b></td>
      <td class="num"><b>${tot.sc||'—'}</b></td>
      <td class="num"><b>${num(Math.round(tot.chars))}</b></td>
      <td class="num"><b>${usd(tot.el,3)}</b></td>
      <td class="num" style="color:var(--muted)"><b>${tot.gm>0?usd(tot.gm,3):'미측정'}</b></td>
      <td class="num"><b>${usd(tot.usd,3)}</b></td></tr>`;
  document.getElementById('costTable').innerHTML=html+'</tbody>';
}

function renderBuilds(){""",
    "period total")

sub("renderOwnerNote(); renderCostTiles();",
    "renderOwnerNote(); renderCostMonths(); renderCostTiles();", "wire months")

# ---------------------------------------------------------------- 9) data
data = open(f"{SP}/admin_data.json").read()
assert "__DATA__" in h
h = h.replace("__DATA__", data)

open(f"{SP}/admin.html", "w").write(h)
print(f"wrote admin.html ({len(h)} bytes)")
