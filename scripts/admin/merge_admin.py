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
  <h2>이상 사용</h2>
  <p class="sub">상한 없는 요금제에서 공정사용 선을 넘은 계정이에요. 넘었다고 통화가 막히지는 않아요 —
  훨씬 위(차단선)까지 가야 멈춰요. 그래서 이 목록을 사람이 보는 게 유일한 제재 경로예요.</p>
  <div class="card scroll"><table id="fairUseTable"></table></div>
</section>

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

function renderFairUse(){
  const rows=(DATA.fairUse||[]);
  const el=document.getElementById('fairUseTable');
  if(!el) return;
  if(!rows.length){ el.innerHTML='<tbody><tr><td class="legend">넘은 계정 없음</td></tr></tbody>'; return; }
  const byId={}; for(const u of DATA.users) byId[u.id]=u;
  let html=`<thead><tr><th>유저</th><th>플랜</th><th class="num">이번 주기 통화</th>
    <th class="num">공정사용 선</th><th class="num">차단선</th><th>주기 시작</th></tr></thead><tbody>`;
  for(const r of rows){
    const u=byId[r.id];
    html+=`<tr>
      <td><span class="uname">${esc(u?nameOf(u):r.id.slice(0,8))}</span></td>
      <td><span class="chip">${PLAN_KO[r.plan]||r.plan}</span></td>
      <td class="num"><b>${fmtMin(r.secs)}</b></td>
      <td class="num">${fmtMin(r.line)}</td>
      <td class="num">${r.stop?fmtMin(r.stop):'없음'}</td>
      <td>${r.since}</td>
    </tr>`;
  }
  el.innerHTML=html+'</tbody>';
}

renderCostTiles(); renderMech(); renderTiers(); renderCostDaily(); renderBuilds(); renderFairUse();
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
    '<label class="toggle"><input type="checkbox" id="devToggle"> 테스트 계정 포함</label>\n'
    '  <a class="toggle" href="__ADMIN_BASE__/logout" style="margin-left:0;text-decoration:none">나가기</a>',
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

# ---------------------------------------------------------------- 13) launch watch
# The page was built to ANALYSE a beta; from 2026-09-12 it also has to WATCH a
# launch. A first tab answers, for the last few days: who signed up, did they
# get through the clone and the first call, did they start a trial, did they
# cancel it. Everything on it reads keys that admin_raw() appends and that the
# offline snapshot's Python gather does not emit, so every read is guarded —
# the tab goes empty, the page never fails.
sub('<button role="tab" data-go="people"   aria-selected="true">사람</button>',
    '<button role="tab" data-go="launch"   aria-selected="true">런칭</button>\n'
    '  <button role="tab" data-go="people"   aria-selected="false">사람</button>', "launch tab button")
sub("let startTab='people';", "let startTab='launch';", "launch default tab")
# a new storage key, so a browser that had 사람 remembered lands on the new tab once
sub("localStorage.getItem('nawana.admin.tab')", "localStorage.getItem('nawana.admin.tab2')", "tab key get")
sub("localStorage.setItem('nawana.admin.tab', name)", "localStorage.setItem('nawana.admin.tab2', name)", "tab key set")

sub("/* ---- cost ---- */", """/* ---- launch ---- */
.xrow{cursor:pointer}
.xrow:hover td{background:var(--chip)}
.xrow[aria-expanded="true"] td{background:var(--chip)}
tr.detail td{background:var(--page); font-size:12.5px; padding:12px 14px 14px}
.dl{display:grid; grid-template-columns:repeat(auto-fit,minmax(250px,1fr)); gap:10px 22px}
.dl h4{margin:0 0 4px; font-size:11px; color:var(--muted); font-weight:600; letter-spacing:.04em; text-transform:uppercase}
.dl ul{margin:0; padding:0; list-style:none}
.dl li{padding:2px 0; font-variant-numeric:tabular-nums; color:var(--ink-2)}
.dl li b{color:var(--ink); font-weight:600}
.ok{color:var(--good-text); font-weight:600}
.bad{color:var(--crit); font-weight:600}
.muted{color:var(--muted)}
.dtl{max-width:220px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap}

/* ---- cost ---- */""", "launch css")

LAUNCH = """
<section data-tab="launch">
  <div class="tiles" id="launchTiles"></div>
  <p class="sub" style="margin:10px 0 0">시각은 이 브라우저의 시간대로 보여요. 테스트 계정 토글을 따라요.</p>
</section>

<section data-tab="launch">
  <h2>가입자 퍼널</h2>
  <p class="sub">가입한 사람이 어디까지 갔는지. 막대 하나가 한 단계, 숫자는 그 단계를 지난 사람 수예요.
  <b>체험 유지</b>는 자동갱신을 끄지 않은 체험(또는 결제 중), <b>결제 전환</b>은 체험을 지나 실제로 청구된 구독이에요 — 무료 제공(comp)은 세지 않아요.
  막대에 올리면 이름이 보여요.</p>
  <div class="seg" id="funnelCohort" role="group" aria-label="가입 기간"></div>
  <div class="card bars" id="funnel"></div>
</section>

<section data-tab="launch">
  <h2>최근 가입자</h2>
  <p class="sub">최근 30일 가입, 최신순. <b>행을 누르면</b> 그 사람의 통화·활동·구독 이벤트·오류·리뷰가 펼쳐져요. 좁은 화면에서는 나머지 열이 접히니 행을 눌러서 보세요.</p>
  <div class="card scroll"><table id="signupTable"></table></div>
</section>

<section data-tab="launch" style="display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:12px">
  <div>
    <h2>구독 이벤트</h2>
    <p class="sub">App Store 서버 알림(Production만). 트랜잭션별 <b>최신 상태</b>라, 체험을 시작하고 자동갱신을 끈 사람은 "자동갱신 해제" 한 줄로 보여요.</p>
    <div class="card scroll"><table id="subEventTable"></table></div>
  </div>
  <div>
    <h2>오류 · 재시도 (7일)</h2>
    <p class="sub">client_events 중 턴 타이밍·전사 로그를 뺀 나머지를 유저×이벤트로 묶었어요.
    <b>섀도잉 취소</b>는 실패가 아니라 사용자가 직접 그만둔 것이라 위 표의 오류 표시에는 안 들어가요.</p>
    <div class="card scroll"><table id="recentErrTable"></table></div>
  </div>
</section>

<section data-tab="launch">
  <h2>통화가 어떻게 끝났나</h2>
  <p class="sub">최근 7일, 게이트웨이가 통화를 끝낸 이유. <b>직접 종료</b>만 학습자가 고른 결말이고
  나머지는 통화가 학습자 밑에서 죽은 거예요. 이 기록은 2026-09-13 빌드부터 올라와요 —
  그 전 통화는 서버 원장에도 흔적이 없어서 여기 안 보여요.</p>
  <div class="card bars" id="rtReasons"></div>
</section>

<section data-tab="launch">
  <h2>최근 통화</h2>
  <p class="sub">최근 14일 통화, 최신순(최대 80개). 과금된 초가 같은 세션 ID로 묶인 단위라, 통화 중 재개가 있으면 한 통화가 둘로 나뉘어 보여요. 10초 미만 조각은 숨겼어요. 턴 수는 세션 시간대 안의 응답 호출을 센 근사치고, 요약 ✓는 통화가 끝난 뒤 요약 호출이 들어왔다는 뜻이에요.</p>
  <div class="card scroll"><table id="sessionTable"></table></div>
</section>
"""
sub('<section data-tab="cost" hidden>\n  <h2>이상 사용</h2>', LAUNCH + '\n<section data-tab="cost" hidden>\n  <h2>이상 사용</h2>', "launch markup")

# One chip for every plan cell on the page: it now says what the subscription
# is DOING. Falls back to the old status word for a snapshot without subState.
sub("""    if(u.plan) meta.push(`<span class="chip"><span class="dot" style="background:${st?st.color:'var(--muted)'}"></span>${PLAN_KO[u.plan]||u.plan} · ${st?st.ko:u.subStatus}</span>`);""",
    """    if(u.plan) meta.push(subChip(u));""", "card sub chip")
sub("""    const plan = u.plan ? `<span class="chip"><span class="dot" style="background:${st?st.color:'var(--muted)'}"></span>${PLAN_KO[u.plan]||u.plan} · ${st?st.ko:u.subStatus}</span>` : '<span class="chip">플랜 없음</span>';""",
    """    const plan = subChip(u);""", "table sub chip")
sub("""  const subs  = users.filter(u=>u.subStatus==='active').length;
  const trial = users.filter(u=>u.subStatus==='trialing').length;
  const expired = users.filter(u=>u.subStatus==='expired').length;""",
    """  const cnt = k => users.filter(u=>stateOf(u)===k).length;
  const subs = cnt('paid')+cnt('cancelling'), trial = cnt('trial')+cnt('trial_cancelled');
  const trialC = cnt('trial_cancelled'), comp = cnt('comp'), expired = cnt('expired');""", "tile sub counts")
sub("""{k:'구독', v:num(subs+trial), d:`구독 중 ${subs} · 체험 ${trial} · 만료 ${expired}`},""",
    """{k:'구독', v:num(subs+trial), d:`결제 ${subs} · 체험 ${trial}${trialC?` (취소 ${trialC})`:''} · 무료 제공 ${comp} · 만료 ${expired}`},""",
    "tile sub caption")

LJS = r"""
/* ================= 런칭 ================= */
const SUB_KO = {
  paid:{ko:'구독 중', color:'var(--good)'},        trial:{ko:'체험 중', color:'var(--s1)'},
  trial_cancelled:{ko:'체험 취소', color:'var(--warn)'}, cancelling:{ko:'해지 예정', color:'var(--warn)'},
  comp:{ko:'무료 제공', color:'var(--muted)'},      expired:{ko:'만료', color:'var(--crit)'},
  past_due:{ko:'결제 실패', color:'var(--crit)'},
};
const PROVIDER_KO = {apple:'Apple', google:'Google', email:'이메일'};
const SUB_EVENT_KO = {
  'SUBSCRIBED/INITIAL_BUY':'구독 시작', 'SUBSCRIBED/RESUBSCRIBE':'재구독', 'SUBSCRIBED':'구독 시작',
  'DID_CHANGE_RENEWAL_STATUS/AUTO_RENEW_DISABLED':'자동갱신 해제',
  'DID_CHANGE_RENEWAL_STATUS/AUTO_RENEW_ENABLED':'자동갱신 재개',
  'DID_RENEW':'갱신', 'DID_RENEW/BILLING_RECOVERY':'갱신 (복구)', 'EXPIRED':'만료', 'EXPIRED/VOLUNTARY':'만료',
  'EXPIRED/BILLING_RETRY':'만료 (결제 실패)', 'DID_FAIL_TO_RENEW':'갱신 실패', 'DID_FAIL_TO_RENEW/GRACE_PERIOD':'갱신 실패 (유예)',
  'GRACE_PERIOD_EXPIRED':'유예 만료', 'REFUND':'환불', 'REVOKE':'환불 회수', 'OFFER_REDEEMED':'코드 사용',
  'DID_CHANGE_RENEWAL_PREF':'플랜 변경 예약', 'DID_CHANGE_RENEWAL_PREF/UPGRADE':'업그레이드',
  // Not an Apple notification: the app POSTing its own live transaction
  // (apple-claim) — an offer code, a restore, or a purchase Apple never
  // attributed to us. It is how those subscriptions reach the server at all.
  'CLIENT_CLAIM':'앱에서 확인됨', 'CLIENT_CLAIM/OFFER':'코드 사용', 'REFUND_DECLINED':'환불 거절',
  'DID_CHANGE_RENEWAL_PREF/DOWNGRADE':'다운그레이드 예약',
};
const EVENT_KO = {
  talk_turn_error:'턴 오류', talk_summary_error:'요약 실패', talk_summary_retry:'요약 재시도',
  talk_summary_regenerated:'요약 재생성', talk_tts_stream_fallback:'TTS 스트림 폴백',
  talk_tts_split_open_failed:'TTS 분할 열기 실패', talk_tts_split_rest_failed:'TTS 분할 나머지 실패',
  shadow_attempt_cancelled:'섀도잉 취소', shadow_rescore_failed:'섀도잉 재채점 실패',
  voice_clone_id_repaired:'클론 ID 복구',
  talk_rt_failed:'통화 끊김', talk_rt_warning:'통화 중 복구', talk_rt_reconnect:'통화 재연결',
};
// Why a realtime call ended. Only `hangup` is the learner's own choice.
const RT_REASON_KO = {
  hangup:'직접 종료', idle:'말이 없어 종료', client_gone:'앱과 끊김',
  socket_closed:'소켓 끊김', transcriber:'받아쓰기 실패', internal:'서버 오류',
  session_ceiling:'1시간 상한', unauthorized:'인증 실패', bad_json:'프로토콜 오류',
  voice_forbidden:'보이스 권한', insufficient_credits:'무료 통화 소진',
  daily_cap_reached:'이번 달 소진', fair_use_limit:'공정사용 확인',
};
const RT_OK = new Set(['hangup']);
// client_events carries more than failures. A cancelled shadowing attempt is
// someone tapping cancel — counting it as 오류 puts a red dot beside a healthy
// account. It stays in the table (it is still worth seeing how often people
// back out of a drill), but it never reaches the signal chip.
// A warning is something the call SURVIVED — a retried reply, one lost
// line of voice. Worth seeing, never a red dot beside a name.
const NOT_A_FAILURE = new Set(['shadow_attempt_cancelled', 'talk_rt_warning',
                               'talk_rt_reconnect', 'talk_summary_retry']);
const failuresOf = idx => forUser(DATA.recentEvents, idx)
  .filter(e => !NOT_A_FAILURE.has(e.event)).reduce((a,e)=>a+e.n, 0);
const ts = iso => iso ? new Date(iso) : null;
const fmtTs = iso => { const d=ts(iso); return d ? d.toLocaleString('ko-KR',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:false}) : '—'; };
const ago = iso => { const d=ts(iso); if(!d) return '—'; const m=Math.round((Date.now()-d)/60000);
  if(m<1) return '방금'; if(m<60) return `${m}분 전`; const h=Math.round(m/60); if(h<48) return `${h}시간 전`; return `${Math.round(h/24)}일 전`; };
const gapMin = (a,b) => (ts(a)&&ts(b)) ? Math.max(0, Math.round((ts(b)-ts(a))/60000)) : null;
const fmtGap = m => m==null ? '—' : m<1 ? '바로' : m<60 ? `${m}분` : m<2880 ? `${Math.round(m/60)}시간` : `${Math.round(m/1440)}일`;
const localDay = d => { const x=new Date(d); return `${x.getFullYear()}-${String(x.getMonth()+1).padStart(2,'0')}-${String(x.getDate()).padStart(2,'0')}`; };
const isToday = iso => !!iso && localDay(iso)===localDay(new Date());
const within = (iso, days) => !!iso && (Date.now()-ts(iso)) < days*86400000;
const stateOf = u => u.subState || ({active:'paid', trialing:'trial'}[u.subStatus] || u.subStatus || 'none');
const isSale = u => stateOf(u)!=='none' && stateOf(u)!=='comp' && u.subSource!=='comp';
const subChip = u => {
  const k = stateOf(u), st = SUB_KO[k];
  if(!st) return '<span class="chip">플랜 없음</span>';
  let tail = '';
  if((k==='trial'||k==='trial_cancelled') && u.trialEndsAt) tail = ` · ${fmtD(u.trialEndsAt.slice(0,10))}까지`;
  else if(k==='cancelling' && u.periodEnd) tail = ` · ${fmtD(u.periodEnd.slice(0,10))}까지`;
  return `<span class="chip"><span class="dot" style="background:${st.color}"></span>${PLAN_KO[u.plan]||u.plan} · ${st.ko}${tail?`<span class="tail">${tail}</span>`:''}</span>`;
};
const forUser = (list, idx) => (list||[]).filter(r=>r.u===idx);
const realSession = s => s.secs>=10;

function renderLaunchTiles(users){
  const cnt = k => users.filter(u=>stateOf(u)===k).length;
  const tiles = [
    {k:'오늘 가입', v:num(users.filter(u=>isToday(u.signedUpAt)).length), d:`최근 7일 ${users.filter(u=>within(u.signedUpAt,7)).length}명`},
    {k:'오늘 통화한 사람', v:num(users.filter(u=>isToday(u.lastTalkAt)).length), d:`그중 첫 통화 ${users.filter(u=>isToday(u.firstTalkAt)).length}명`},
    {k:'체험 중', v:num(cnt('trial')), d:`자동갱신 해제 ${cnt('trial_cancelled')}명`},
    {k:'결제 구독', v:num(cnt('paid')+cnt('cancelling')), d:`해지 예정 ${cnt('cancelling')} · 무료 제공 ${cnt('comp')}`},
    {k:'만료', v:num(cnt('expired')), d:'끝난 구독'},
  ];
  document.getElementById('launchTiles').innerHTML = tiles.map(t=>
    `<div class="tile"><div class="k">${t.k}</div><div class="v">${t.v}</div><div class="d">${t.d}</div></div>`).join('');
}

let funnelDays = 30;   // 0 = everyone
function renderFunnelCohort(){
  const el = document.getElementById('funnelCohort');
  el.innerHTML = [[7,'최근 7일'],[30,'최근 30일'],[0,'전체']].map(([k,lab])=>
    `<button type="button" data-d="${k}" aria-pressed="${k===funnelDays}">${lab}</button>`).join('');
  el.querySelectorAll('button').forEach(b=>b.addEventListener('click', ()=>{
    funnelDays = +b.dataset.d; renderFunnelCohort(); renderFunnel(visibleUsers());
  }));
}
function renderFunnel(users){
  const cohort = users.filter(u => !funnelDays || within(u.signedUpAt, funnelDays));
  const st = u => stateOf(u);
  const steps = [
    {k:'가입',           t:()=>true},
    {k:'보이스 클론',     t:u=>!!u.clone},
    {k:'첫 통화',         t:u=>!!u.firstTalkAt || u.turns>0},
    {k:'통화 5분 이상',   t:u=>u.talkSecs>=300},
    {k:'체험·구독 시작',  t:u=>isSale(u)},
    {k:'체험 유지',       t:u=>isSale(u) && ['trial','paid','cancelling'].includes(st(u))},
    {k:'결제 전환',       t:u=>isSale(u) && ['paid','cancelling'].includes(st(u))},
  ];
  const base = Math.max(1, cohort.length);
  const html = steps.map(s=>{
    const who = cohort.filter(s.t);
    const names = who.map(u=>esc(nameOf(u))).slice(0,14).join(', ') + (who.length>14?` 외 ${who.length-14}명`:'');
    const tip = `<b>${s.k}</b> ${who.length}명${who.length?'<br>'+names:''}`;
    return `<div class="row"><div class="lbl">${s.k}</div>
      <div class="track" data-tip="${tip.replace(/"/g,'&quot;')}"><div class="fill" style="width:${who.length/base*100}%"></div></div>
      <div class="val">${who.length}명 · ${Math.round(who.length/base*100)}%</div></div>`;
  }).join('');
  document.getElementById('funnel').innerHTML = html +
    `<div class="legend">${funnelDays?`최근 ${funnelDays}일 가입자`:'전체 가입자'} ${cohort.length}명 기준${cohort.length?'':' — 이 기간에 가입한 사람이 없어요'}</div>`;
}

function userDetail(u){
  const sess = forUser(DATA.recentSessions, u.idx).filter(realSession).slice(0,15);
  const free = {}; for(const f of forUser(DATA.freeRecent, u.idx)) free[f.purpose]=(free[f.purpose]||0)+f.n;
  const freeRows = Object.entries(free).sort((a,b)=>b[1]-a[1]);
  const subs = forUser(DATA.subEvents, u.idx);
  const errs = forUser(DATA.recentEvents, u.idx);
  const col = (title, items, empty) => `<div><h4>${title}</h4>${items.length?`<ul>${items.join('')}</ul>`:`<div class="muted">${empty}</div>`}</div>`;
  const mail = u.realEmail ? `${esc(u.realEmail)} <span class="muted">· 앱 로그인 ${esc(u.email||'')}</span>` : esc(u.email||'이메일 없음');
  return `<div class="dl">
    ${col('프로필', [
      `<li>${mail}</li>`,
      `<li>${PROVIDER_KO[u.provider]||u.provider||'로그인 방식 미상'}${u.device?' · '+u.device:''}${u.location?' · '+esc(u.location):''}</li>`,
      u.occupation?`<li>${esc(u.occupation)}</li>`:'',
      `<li>가입 ${fmtTs(u.signedUpAt)}${u.lastSignIn?' · 마지막 로그인 '+fmtTs(u.lastSignIn):''}</li>`,
      u.cloneAt?`<li>클론 ${fmtTs(u.cloneAt)} <span class="muted">(가입 ${fmtGap(gapMin(u.signedUpAt,u.cloneAt))} 후)</span></li>`:'<li class="muted">클론 없음</li>',
      `<li>${subChip(u)}${u.subStartedAt?` <span class="muted">시작 ${fmtTs(u.subStartedAt)}</span>`:''}</li>`,
    ].filter(Boolean), '')}
    ${col('최근 통화 (14일)', sess.map(s=>
      `<li>${fmtTs(s.started)} · ${LANG_KO[s.lang]||s.lang||''} <b>${fmtMin(s.secs)}</b> · 턴 ${s.turns} · ${s.summarized?'<span class="ok">요약 ✓</span>':'<span class="muted">요약 없음</span>'}</li>`),
      '최근 14일 통화 없음')}
    ${col('활동 (14일)', freeRows.map(([p,n])=>`<li>${PURPOSE_KO[p]||p} <b>${n}</b>회</li>`), '무료 기능 사용 없음')}
    ${col('통화 종료 (14일)', forUser(DATA.rtSessions, u.idx).slice(0,12).map(r=>{
      const good = RT_OK.has(r.reason);
      return `<li>${fmtTs(r.at)} · <b class="${good?'ok':'bad'}">${RT_REASON_KO[r.reason]||r.reason}</b>`
        + ` · 턴 ${r.turns} · ${fmtMin(r.secs)}`
        + (r.p50?` · 응답 ${(r.p50/1000).toFixed(1)}초`:'')
        + (r.warnings?` · <span class="muted">복구 ${r.warnings}회</span>`:'') + `</li>`;
    }), '기록 없음')}
    ${col('구독 이벤트', subs.map(e=>`<li>${fmtTs(e.at)} · ${subEventLabel(e)} · ${PLAN_KO[e.plan]||e.plan}</li>`), '없음')}
    ${col('오류 · 재시도 (7일)', errs.map(e=>`<li>${EVENT_KO[e.event]||e.event} <b>${e.n}</b>회 · ${ago(e.last)}${e.detail?` <span class="muted">${esc(e.detail)}</span>`:''}</li>`), '없음')}
    ${col('리뷰', (u.reviews||[]).map(r=>`<li>“${esc(r.body)}” <span class="muted">${REVIEW_CTX[r.context]||r.context} · ${fmtD(r.d)}</span></li>`), '없음')}
  </div>`;
}

function renderSignups(users){
  const rows = users.filter(u=>within(u.signedUpAt, 30)).sort((a,b)=> (b.signedUpAt||'').localeCompare(a.signedUpAt||''));
  const el = document.getElementById('signupTable');
  if(!rows.length){ el.innerHTML = `<tbody><tr><td class="muted">${DATA.users.some(u=>u.signedUpAt)?'최근 30일 가입자가 없어요':'이 데이터는 라이브 콘솔에서만 보여요 (admin_raw 갱신 필요)'}</td></tr></tbody>`; return; }
  let html = `<thead><tr><th>유저</th><th>가입</th><th>로그인</th><th>클론</th><th>첫 통화</th><th class="num">통화</th><th class="num">장면</th><th>구독</th><th>마지막 활동</th><th>신호</th></tr></thead><tbody>`;
  for(const u of rows){
    const errs = failuresOf(u.idx);
    const sig = [];
    if(u.reviewCount) sig.push(`<span class="chip">리뷰 ${u.reviewCount}</span>`);
    if(errs) sig.push(`<span class="chip"><span class="dot" style="background:var(--crit)"></span>오류 ${errs}</span>`);
    if(stateOf(u)==='trial_cancelled') sig.push(`<span class="chip"><span class="dot" style="background:var(--warn)"></span>체험 취소</span>`);
    const dropped = forUser(DATA.rtSessions, u.idx).filter(r=>!RT_OK.has(r.reason)).length;
    if(dropped) sig.push(`<span class="chip"><span class="dot" style="background:var(--crit)"></span>끊김 ${dropped}</span>`);
    const last = u.lastTalkAt ? `통화 ${ago(u.lastTalkAt)}` : u.lastSignIn ? `<span class="muted">로그인 ${ago(u.lastSignIn)}</span>` : '—';
    html += `<tr class="xrow" data-u="${u.idx}" aria-expanded="false" title="${esc(u.realEmail||u.email||'')}">
      <td><span class="uname">${esc(nameOf(u))}</span>${badge(u)}<div class="usub">${(u.langs||[]).map(l=>LANG_KO[l]||l).join(' · ')}</div></td>
      <td style="white-space:nowrap"><span class="abs">${fmtTs(u.signedUpAt)}</span><div class="usub rel">${ago(u.signedUpAt)}</div></td>
      <td>${PROVIDER_KO[u.provider]||u.provider||'—'}</td>
      <td style="white-space:nowrap">${u.clone?`<span class="ok">✓</span>${u.cloneAt?`<div class="usub">가입 ${fmtGap(gapMin(u.signedUpAt,u.cloneAt))} 후</div>`:''}`:'<span class="muted">—</span>'}</td>
      <td style="white-space:nowrap">${u.firstTalkAt?`${fmtTs(u.firstTalkAt)}<div class="usub">가입 ${fmtGap(gapMin(u.signedUpAt,u.firstTalkAt))} 후</div>`:(u.turns?'<span class="muted">(시각 없음)</span>':'<span class="muted">—</span>')}</td>
      <td class="num">${u.talkSecs?fmtMin(u.talkSecs):'—'}<div class="usub">${u.talkSessions||0}회 · 턴 ${num(u.turns)}</div></td>
      <td class="num">${u.scenes||'—'}</td>
      <td>${subChip(u)}</td>
      <td style="white-space:nowrap">${last}</td>
      <td>${sig.join(' ')||'<span class="muted">—</span>'}</td>
    </tr>`;
  }
  el.innerHTML = html + '</tbody>';
  const byIdx = {}; for(const u of users) byIdx[u.idx]=u;
  el.querySelectorAll('tr.xrow').forEach(tr=>tr.addEventListener('click', ()=>{
    const open = tr.getAttribute('aria-expanded')==='true';
    const next = tr.nextElementSibling;
    if(next && next.classList.contains('detail')) next.remove();
    tr.setAttribute('aria-expanded', String(!open));
    if(open) return;
    const d = document.createElement('tr'); d.className='detail';
    d.innerHTML = `<td colspan="10">${userDetail(byIdx[+tr.dataset.u])}</td>`;
    tr.after(d);
  }));
}

function subEventLabel(e){
  let lab = SUB_EVENT_KO[`${e.type}/${e.subtype||''}`] || SUB_EVENT_KO[e.type] || e.type;
  if(e.trial && e.type==='SUBSCRIBED') lab = '체험 시작';
  if(e.revoked) lab += ' · 환불됨';
  return lab;
}
function renderSubEvents(users){
  const vis = new Set(users.map(u=>u.idx)), byIdx = {}; for(const u of users) byIdx[u.idx]=u;
  const rows = (DATA.subEvents||[]).filter(e=>vis.has(e.u));
  const el = document.getElementById('subEventTable');
  if(!rows.length){ el.innerHTML = '<tbody><tr><td class="muted">Production 알림이 아직 없어요</td></tr></tbody>'; return; }
  let html = `<thead><tr><th>시각</th><th>유저</th><th>이벤트</th><th>플랜</th><th class="num">금액</th></tr></thead><tbody>`;
  for(const e of rows){
    const u = byIdx[e.u];
    const amt = e.price ? `${num(e.price)} ${e.currency}` : (e.trial ? '<span class="muted">체험</span>' : '—');
    html += `<tr><td style="white-space:nowrap">${fmtTs(e.at)}<div class="usub">${ago(e.at)}</div></td>
      <td><span class="uname">${esc(nameOf(u))}</span></td>
      <td>${subEventLabel(e)}${e.trial&&e.type!=='SUBSCRIBED'?'<div class="usub">체험 중</div>':''}</td>
      <td><span class="chip">${PLAN_KO[e.plan]||e.plan}</span></td>
      <td class="num">${amt}</td></tr>`;
  }
  el.innerHTML = html + '</tbody>';
}

function renderRecentErrors(users){
  const vis = new Set(users.map(u=>u.idx)), byIdx = {}; for(const u of users) byIdx[u.idx]=u;
  const rows = (DATA.recentEvents||[]).filter(e=>vis.has(e.u));
  const el = document.getElementById('recentErrTable');
  if(!rows.length){ el.innerHTML = '<tbody><tr><td class="muted">최근 7일 오류 없음</td></tr></tbody>'; return; }
  let html = `<thead><tr><th>유저</th><th>이벤트</th><th class="num">횟수</th><th>마지막</th><th>빌드</th><th>상세</th></tr></thead><tbody>`;
  for(const e of rows){
    html += `<tr><td><span class="uname">${esc(nameOf(byIdx[e.u]))}</span></td>
      <td style="white-space:nowrap"${NOT_A_FAILURE.has(e.event)?' class="muted"':''}>${EVENT_KO[e.event]||e.event}</td><td class="num">${e.n}</td>
      <td style="white-space:nowrap">${ago(e.last)}</td><td>${e.build||'—'}</td>
      <td class="muted dtl" title="${esc(e.detail||'')}">${esc(e.detail||'')}</td></tr>`;
  }
  el.innerHTML = html + '</tbody>';
}

function renderSessionFeed(users){
  const vis = new Set(users.map(u=>u.idx)), byIdx = {}; for(const u of users) byIdx[u.idx]=u;
  const rows = (DATA.recentSessions||[]).filter(s=>vis.has(s.u)&&realSession(s)).slice(0,80);
  const el = document.getElementById('sessionTable');
  if(!rows.length){ el.innerHTML = '<tbody><tr><td class="muted">최근 14일 통화 없음</td></tr></tbody>'; return; }
  let html = `<thead><tr><th>시각</th><th>유저</th><th>언어</th><th class="num">길이</th><th class="num">턴</th><th>요약</th></tr></thead><tbody>`;
  for(const s of rows){
    const u = byIdx[s.u];
    html += `<tr><td style="white-space:nowrap">${fmtTs(s.started)}<div class="usub">${ago(s.started)}</div></td>
      <td><span class="uname">${esc(nameOf(u))}</span>${badge(u)}</td>
      <td>${LANG_KO[s.lang]||s.lang||'—'}</td>
      <td class="num">${fmtMin(s.secs)}</td><td class="num">${s.turns}</td>
      <td>${s.summarized?'<span class="ok">✓</span>':(s.secs<60?'<span class="muted">—</span>':'<span class="bad">없음</span>')}</td></tr>`;
  }
  el.innerHTML = html + '</tbody>';
}

function renderRtReasons(){
  const el = document.getElementById('rtReasons');
  if(!el) return;
  const rows = (DATA.rtReasons||[]).slice().sort((a,b)=>b.n-a.n);
  if(!rows.length){
    el.innerHTML = '<div class="legend">아직 기록이 없어요 — 이 계측이 들어간 빌드를 쓰는 통화부터 쌓여요.</div>';
    return;
  }
  const total = rows.reduce((a,r)=>a+r.n,0);
  const ok = rows.filter(r=>RT_OK.has(r.reason)).reduce((a,r)=>a+r.n,0);
  const max = Math.max(...rows.map(r=>r.n));
  el.innerHTML = rows.map(r=>{
    const good = RT_OK.has(r.reason);
    return `<div class="row"><div class="lbl">${RT_REASON_KO[r.reason]||r.reason}</div>
      <div class="track"><div class="fill" style="width:${r.n/max*100}%;background:${good?'var(--s3)':'var(--crit)'}"></div></div>
      <div class="val">${r.n}회 · ${r.users}명 · 턴 ${num(r.turns)}</div></div>`;
  }).join('')
   + `<div class="legend">통화 ${total}건 중 <b style="color:var(--ink)">${Math.round(ok/total*100)}%</b>가 학습자가 직접 끝낸 통화예요</div>`;
}

function renderLaunch(users){
  renderLaunchTiles(users); renderFunnel(users); renderSignups(users);
  renderSubEvents(users); renderRecentErrors(users); renderSessionFeed(users);
  renderRtReasons();
}

/* ================= 탭 ================= */"""
sub("/* ================= 탭 ================= */", LJS, "launch js")
sub("renderOwnerNote(); renderCostMonths();", "renderFunnelCohort(); renderOwnerNote(); renderCostMonths();", "wire funnel cohort")
sub("""  renderErrors();
  renderCostTable(users);""", """  renderErrors();
  renderCostTable(users);
  renderLaunch(users);""", "wire launch")


# ---------------------------------------------------------------- 14) charts fit the screen
# Every SVG on this page was drawn at a hardcoded 980 px (440 for the error
# panel) because it was written for a 1060 px desktop. Inside a `.scroll` card
# that does not break — it just means a phone shows the left third of every
# chart and no indication the rest exists. On 2026-09-13 the console became
# something you check from a phone during a launch, so the charts measure the
# box they are in and are redrawn when that box changes (tab switch, rotation,
# window resize). Nothing about the desktop rendering changes: on a wide
# screen the measured width IS ~980.
sub("""const tooltip = document.getElementById('tooltip');""",
    """/* The content width of a card, so an SVG can be drawn to fit it. A hidden
   section measures 0 — hence the floor, and hence redrawCharts() on tab
   switch, which is when the real width first becomes knowable. */
function innerW(el, min){
  if(!el) return 980;
  const cs = getComputedStyle(el);
  const w = el.clientWidth - parseFloat(cs.paddingLeft||0) - parseFloat(cs.paddingRight||0);
  return Math.max(min||230, Math.round(w) || 980);
}
const isNarrow = () => innerHeight && innerWidth <= 700;

const tooltip = document.getElementById('tooltip');""", "innerW helper")

# --- daily small multiples
sub("  const W=980, LEFT=34, RIGHT=8, plotW=W-LEFT-RIGHT, bw=plotW/n;",
    "  const W=innerW(document.getElementById('dailyCard')), LEFT=34, RIGHT=8,\n"
    "        plotW=W-LEFT-RIGHT, bw=plotW/n;", "daily width")

# --- error panel
sub("  const n=DATA.days.length, W=440, H=90, LEFT=26, top=6, bh=H-top-14, bw=(W-LEFT-6)/n;",
    "  const n=DATA.days.length, W=innerW(document.getElementById('errChart'), 230),\n"
    "        H=90, LEFT=26, top=6, bh=H-top-14, bw=(W-LEFT-6)/n;", "error width")

# --- streak lanes: the name and stat gutters are half the width on a phone,
#     and the stat drops its tail rather than being clipped by it.
sub("  const NAME=118, STAT=132, PAD=8;\n"
    "  const cw=Math.min(26, Math.max(6, (980-NAME-STAT-PAD*2)/maxSpan));",
    "  const AVAIL=innerW(document.getElementById('lanes')), narrow=AVAIL<620;\n"
    "  const NAME=narrow?70:118, STAT=narrow?62:132, PAD=narrow?4:8;\n"
    "  const cw=Math.min(26, Math.max(narrow?2.6:6, (AVAIL-NAME-STAT-PAD*2)/maxSpan));", "lanes width")
sub("""    const tail = s.current ? `현재 ${s.current}일째` : `${s.sinceLast}일째 조용`;
    svg+=`<text x="${statX}" y="${y+13}" class="lane-stat">최장 <tspan style="fill:var(--ink);font-weight:600">${s.longest}일</tspan> · ${tail}</text>`;""",
    """    const tail = s.current ? `현재 ${s.current}일째` : `${s.sinceLast}일째 조용`;
    svg+=`<text x="${statX}" y="${y+13}" class="lane-stat">최장 <tspan style="fill:var(--ink);font-weight:600">${s.longest}일</tspan>${narrow?'':` · ${tail}`}</text>`;""",
    "lanes stat tail")
sub("  svg+=`<text x=\"${NAME-6}\" y=\"${y+13}\" text-anchor=\"end\" class=\"lane-name\">${esc(nameOf(u).slice(0,12))}</text>`;",
    "  svg+=`<text x=\"${NAME-6}\" y=\"${y+13}\" text-anchor=\"end\" class=\"lane-name\">${esc(nameOf(u).slice(0, narrow?8:12))}</text>`;",
    "lanes name length")

# --- heatmap: the cell shrinks to fit the month instead of scrolling it away
sub("  const n=DATA.days.length, cs=10, gap=1.5;",
    "  const n=DATA.days.length, gap=1.5;\n"
    "  const nameW=isNarrow()?66:150;\n"
    "  const cs=Math.max(3.5, Math.min(10, (innerW(document.getElementById('heatmap'))-nameW-10)/n - gap));",
    "heatmap cell")
sub("""  let ruler=`<div class="hm-row"><div class="hm-name"></div><svg width="${width}" height="16">`;""",
    """  let ruler=`<div class="hm-row"><div class="hm-name" style="width:${nameW}px"></div><svg width="${width}" height="16">`;""",
    "heatmap ruler name")
sub("""    let svg=`<div class="hm-row"><div class="hm-name" title="${esc(u.realEmail||u.email||u.label)}">${esc(nameOf(u))}</div><svg width="${width}" height="${cs}">`;""",
    """    let svg=`<div class="hm-row"><div class="hm-name" style="width:${nameW}px" title="${esc(u.realEmail||u.email||u.label)}">${esc(nameOf(u))}</div><svg width="${width}" height="${cs}">`;""",
    "heatmap row name")

# --- cost daily
sub("  const W=980, LEFT=40, RIGHT=8, plotW=W-LEFT-RIGHT, bw=plotW/n, H=110, top=8, bh=H-top-16;",
    "  const W=innerW(document.getElementById('costDaily'), 230), LEFT=40, RIGHT=8,\n"
    "        plotW=W-LEFT-RIGHT, bw=plotW/n, H=110, top=8, bh=H-top-16;", "cost daily width")

# --- redraw when the box changes: a tab becomes visible, or the window resizes
sub("""  try{ localStorage.setItem('nawana.admin.tab2', name); }catch(e){}
  hideTip();
}""",
    """  try{ localStorage.setItem('nawana.admin.tab2', name); }catch(e){}
  hideTip();
  redrawCharts();   // a hidden section measures 0 — now it can be measured
}

/* Only the width-dependent drawings. Cheap enough to run on every resize
   frame we let through, and it is the same code path as the first paint, so
   a redraw can never disagree with it. */
function redrawCharts(){
  const users = visibleUsers();
  renderDaily(new Set(users.map(u=>u.idx)));
  renderLanes(users);
  renderHeatmap(users);
  renderErrors();
  renderCostDaily();
}
let redrawTimer;
addEventListener('resize', ()=>{
  clearTimeout(redrawTimer);
  redrawTimer = setTimeout(redrawCharts, 150);
});""", "redraw on tab/resize")


# The mobile block goes LAST in the stylesheet. Spliced in at the top (next to
# the tab CSS) every base rule below it won on source order — `.cards`' 310 px
# floor beat the override and the people cards pushed a 320 px phone sideways.
sub("""</style>""", """@media (max-width: 700px){
  .wrap{padding:24px 14px 60px}
  header{gap:10px 14px}
  h1{font-size:24px}
  .tabs{gap:0; margin:16px 0 4px}
  .tabs button{padding:9px 10px; font-size:13.5px}
  .tiles{grid-template-columns:repeat(auto-fit,minmax(132px,1fr)); gap:8px}
  .tile{padding:11px 12px}
  .tile .v{font-size:22px}
  .card{padding:14px}
  .bars .lbl{width:96px; font-size:12px}
  .bars .val{font-size:11.5px}
  th, td{padding:8px 7px}
  table{font-size:13px}
  /* 최근 가입자: 유저 · 가입 · 구독 · 신호만 */
  #signupTable th:nth-child(3), #signupTable td:nth-child(3),
  #signupTable th:nth-child(4), #signupTable td:nth-child(4),
  #signupTable th:nth-child(5), #signupTable td:nth-child(5),
  #signupTable th:nth-child(6), #signupTable td:nth-child(6),
  #signupTable th:nth-child(7), #signupTable td:nth-child(7),
  #signupTable th:nth-child(9), #signupTable td:nth-child(9),
  #signupTable th:nth-child(10), #signupTable td:nth-child(10){display:none}
  #signupTable .chip{white-space:normal; word-break:keep-all}
  /* 가입 열은 "몇 시간 전"만 — 정확한 시각은 상세에 있고, 여기서 아낀 폭이
     구독 칩을 한 줄로 만들어요 */
  #signupTable .abs{display:none}
  #signupTable .rel{font-size:13px; color:var(--ink)}
  #signupTable tr.detail td{display:table-cell}
  /* 구독 이벤트: 금액은 대부분 "체험" */
  #subEventTable th:nth-child(5), #subEventTable td:nth-child(5){display:none}
  /* 오류: 빌드는 상세 안에 있어요 */
  #recentErrTable th:nth-child(5), #recentErrTable td:nth-child(5){display:none}
  /* 칩의 날짜 꼬리는 접어요 — 상태가 요점이고 날짜는 상세에 있어요 */
  #signupTable .chip .tail{display:none}
  /* 유저별 현황(13열) → 유저 · 플랜 · 활동일 · 통화 */
  #userTable th:nth-child(2), #userTable td:nth-child(2),
  #userTable th:nth-child(5), #userTable td:nth-child(5),
  #userTable th:nth-child(6), #userTable td:nth-child(6),
  #userTable th:nth-child(7), #userTable td:nth-child(7),
  #userTable th:nth-child(8), #userTable td:nth-child(8),
  #userTable th:nth-child(10), #userTable td:nth-child(10),
  #userTable th:nth-child(11), #userTable td:nth-child(11),
  #userTable th:nth-child(12), #userTable td:nth-child(12),
  #userTable th:nth-child(13), #userTable td:nth-child(13){display:none}
  #userTable .chip{white-space:normal; word-break:keep-all}
  /* 유저별 비용(8열) → 유저 · 통화 · 합계 */
  #costTable th:nth-child(2), #costTable td:nth-child(2),
  #costTable th:nth-child(4), #costTable td:nth-child(4),
  #costTable th:nth-child(5), #costTable td:nth-child(5),
  #costTable th:nth-child(6), #costTable td:nth-child(6),
  #costTable th:nth-child(7), #costTable td:nth-child(7){display:none}
  /* 이상 사용(6열) → 유저 · 이번 주기 통화 · 공정사용 선 */
  #fairUseTable th:nth-child(2), #fairUseTable td:nth-child(2),
  #fairUseTable th:nth-child(5), #fairUseTable td:nth-child(5),
  #fairUseTable th:nth-child(6), #fairUseTable td:nth-child(6){display:none}
  /* 사람 카드는 310px 바닥을 못 지켜요 */
  .cards{grid-template-columns:minmax(0,1fr)}
  .mechrow{grid-template-columns:84px 1fr auto; gap:8px}
  .bars .lbl{white-space:normal; line-height:1.25; text-align:left}
  .dtl{max-width:118px}
  code{overflow-wrap:anywhere}
  /* 최근 통화: 언어는 거의 한 가지 */
  #sessionTable th:nth-child(3), #sessionTable td:nth-child(3){display:none}
  .dl{grid-template-columns:1fr; gap:14px}
  /* One column on a phone. The split sections carry an inline
     minmax(320px,1fr), whose 320 px floor is wider than a small phone's
     content box and pushed the whole PAGE sideways.
     minmax(0,…), never plain 1fr: a bare 1fr's automatic minimum is
     min-content, and the widest table in there is ~500 px, so 1fr would set
     a 500 px column and overflow far worse than the thing being fixed. */
  section[data-tab][style*="grid"]{grid-template-columns:minmax(0,1fr) !important}
  .costgrid{grid-template-columns:minmax(0,1fr)}
}
</style>""", "mobile css last")

# ---------------------------------------------------------------- 9) data
data = open(f"{SP}/admin_data.json").read()
assert "__DATA__" in h
h = h.replace("__DATA__", data)

open(f"{SP}/admin.html", "w").write(h)
print(f"wrote admin.html ({len(h)} bytes)")
