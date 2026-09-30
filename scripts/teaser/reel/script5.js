// ============ SCRIPT ============
// v5 — the message first. v3 spent 22 s on worries everyone has before the one
// thing only this app does; here the fluent self speaks in the first second and
// the rest proves it. Pacing rule kept: a line holds ≥1.6 s after its last word.
const G = .24;
let t;

// S1 — this is your voice (0–4.3): the orb is already speaking
const s1 = scene(); show(s1, 0, 4.3);
tl.set(O, { x: 540, y: 720, size: 60, alpha: 0 }, 0);
tl.to(O, { alpha: 1, duration: .2 }, .05);
tl.to(O, { size: 600, duration: 1.0, ease: 'expo.out' }, .1);
tl.to(O, { speak: 1, duration: .4 }, .3);
const chip1 = document.createElement('div'); chip1.className = 'chip'; chip1.style.top = '1070px';
chip1.innerHTML = '<b>Future you</b><span><em>speaking in your voice</em></span>';
s1.appendChild(chip1);
tl.fromTo(chip1, { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: .5, ease: 'back.out(2)' }, .5);
const h1 = row(s1, 1330, 104, ['This', 'is', '*your', '*voice.']);
seq(h1, .7, G);
outAll(h1, 3.9);

// S2 — speaking fluent English (4.3–7.7)
const s2 = scene(); show(s2, 4.3, 7.7);
const h2a = row(s2, 1300, 96, ['Speaking']);
const h2b = row(s2, 1415, 96, ['*fluent', 'English.']);
t = seq(h2a, 4.35, G); seq(h2b, t + .05, G);
outAll([...h2a, ...h2b], 7.3);
tl.to(chip1, { opacity: 0, y: -10, duration: .3 }, 7.3);

// S3 — record once, then talk to yourself (7.7–11.8)
const s3 = scene(); show(s3, 7.7, 11.8);
tl.to(O, { size: 250, y: 250, speak: .15, duration: 1, ease: 'power3.inOut' }, 7.5);
const r1 = row(s3, 860, 92, ['Record', 'your', 'voice', 'once.']);
const r2 = row(s3, 990, 92, ['Then', '*call', '*yourself.']);
t = seq(r1, 8.0, G); seq(r2, t + .25, G);
outAll([...r1, ...r2], 11.4);

// S4 — the call (11.8–24.4), same beats as v3's call, tightened
const T = 11.8;
const s4 = scene(); show(s4, T, T + 12.6);
const chip2 = document.createElement('div'); chip2.className = 'chip'; chip2.style.top = '400px';
chip2.innerHTML = '<b>Future you</b><span><em class="k1">speaking</em><em class="k2" style="opacity:0">listening…</em><em class="k3" style="opacity:0">nice!</em></span>';
s4.appendChild(chip2);
tl.fromTo(chip2, { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: .5, ease: 'back.out(2)' }, T + .2);
const swapChip = (from, to, at) => { tl.to(chip2.querySelector(from), { opacity: 0, y: -8, duration: .2 }, at); tl.fromTo(chip2.querySelector(to), { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: .25 }, at + .1); };
const w1 = who(s4, 'Future you', { x: 92, y: 540 });
const L1 = bubble(s4, 'So what did you do last weekend?', { x: 60, y: 585 });
tl.to(O, { speak: 1, duration: .2 }, T + .6); tl.to(O, { speak: .15, duration: .4 }, T + 2.0);
tl.to(w1, { opacity: 1, duration: .3 }, T + .6); popB(L1, T + .65);
swapChip('.k1', '.k2', T + 2.2);
const w2 = who(s4, 'You', { right: 92, y: 780 });
const R1 = bubble(s4, 'I go to hiking with my friends.', { right: 60, y: 825, mine: true, words: true });
tl.to(w2, { opacity: 1, duration: .3 }, T + 2.4); popB(R1, T + 2.4);
tl.to(R1.querySelectorAll('.sw'), { opacity: 1, duration: .15, stagger: .22 }, T + 2.55);
const card = document.createElement('div'); card.className = 'card'; card.style.left = '130px'; card.style.top = '1030px';
card.innerHTML = '<div class="k">Say it like this</div><div class="v">I <span class="hl">went hiking</span> with my friends.</div>';
s4.appendChild(card);
tl.fromTo(card, { opacity: 0, y: 40, scale: .9 }, { opacity: 1, y: 0, scale: 1, duration: .6, ease: 'back.out(1.8)' }, T + 4.7);
tl.fromTo(card.querySelector('.hl'), { backgroundColor: 'rgba(220,230,255,0)' }, { backgroundColor: 'rgba(220,230,255,1)', duration: .4 }, T + 5.2);
tl.to(cam, { scale: 1.3, y: -190, duration: 1.1, ease: 'power3.inOut' }, T + 4.9);
tl.to(cam, { scale: 1, y: 0, duration: 1, ease: 'power3.inOut' }, T + 7.4);
const R2 = bubble(s4, 'I went hiking with my friends!', { right: 60, y: 1310, mine: true, words: true });
popB(R2, T + 8.5); tl.to(R2.querySelectorAll('.sw'), { opacity: 1, duration: .15, stagger: .16 }, T + 8.6);
const ck = document.createElement('div'); ck.className = 'check'; ck.style.left = '110px'; ck.style.top = '1330px';
ck.innerHTML = '<svg width="38" height="30" viewBox="0 0 38 30"><path d="M3 15 L14 26 L35 4" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
s4.appendChild(ck);
tl.fromTo(ck, { opacity: 0, scale: 0 }, { opacity: 1, scale: 1, duration: .5, ease: 'back.out(3)' }, T + 9.8);
swapChip('.k2', '.k3', T + 9.8);
tl.to(O, { speak: 1, duration: .15 }, T + 9.85);
tl.to([w1, L1, w2, R1, card, R2, ck, chip2], { opacity: 0, y: -40, filter: 'blur(10px)', duration: .45, stagger: .03, ease: 'power2.in' }, T + 11.6);
tl.to(O, { alpha: 0, size: 120, duration: .4, ease: 'power2.in' }, T + 11.7);

// S5 — the only one you're not embarrassed in front of (24.4–29.4)
const s5 = scene(); show(s5, 24.4, 29.4);
const g1 = row(s5, 760, 96, ['No', 'teacher.']);
const g2 = row(s5, 875, 96, ['No', 'stranger.']);
const g3 = row(s5, 1060, 150, ['Only', '*you.']);
t = seq(g1, 24.6, G); t = seq(g2, t + .15, G); seq(g3, t + .35, .3);
outAll([...g1, ...g2, ...g3], 29.0);

// S6 — na·wa·na (29.4–34.2)
const s6 = scene(); show(s6, 29.4, 34.4);
const n1 = row(s6, 840, 190, ['*na', '*wa', '*na']);
seq(n1, 29.6, .3);
const n2 = row(s6, 990, 30, ['me', '·', 'and', '·', 'me'], 'mono');
seq(n2, 30.6, .1);
const n3 = row(s6, 1210, 64, ['Learn', 'a', 'language']);
const n4 = row(s6, 1295, 64, ['from', 'your', '*fluent', 'self.']);
t = seq(n3, 31.3, .14); seq(n4, t, .14);
outAll([...n1, ...n2, ...n3, ...n4], 33.9);

// end card
const end = $('#end');
end.innerHTML = `<div class="logo">${sprite('logo', 26, '#ffffff')}</div><div class="name">nawana</div><div class="url">nawana.app</div>`;
tl.set(end, { visibility: 'visible' }, 34.2);
tl.fromTo(end, { opacity: 0 }, { opacity: 1, duration: .35 }, 34.2);
tl.fromTo(end.children, { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: .6, stagger: .15, ease: 'back.out(2)' }, 34.4);
tl.to({}, { duration: .1 }, 36.8);
const D = tl.duration();
