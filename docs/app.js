/* Selector — AI DJ. Plans the night, talks like a DJ, plays through Apple Music. */
(() => {
'use strict';

/* ---------------- helpers ---------------- */
const $ = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const fmtT = s => { s = Math.max(0, Math.round(s)); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60; return h ? `${h}:${String(m).padStart(2, '0')}:${String(x).padStart(2, '0')}` : `${m}:${String(x).padStart(2, '0')}`; };
const fmtClock = d => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
const fmtLen = s => { const m = Math.round(s / 60); if (m < 60) return `${m} min`; const h = Math.floor(m / 60), r = m % 60; return r ? `${h} h ${r} min` : `${h} h`; };
const lsGet = (k, d) => { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } };
const lsSet = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} };
const isIOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
let toastTimer;
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, 1600 + msg.length * 30); }
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

/* ---------------- vibes, occasions ---------------- */
const VIBES = {
  bollywood: { name: 'Bollywood', color: '#D83A8E' },
  punjabi: { name: 'Punjabi', color: '#E4572E' },
  southindian: { name: 'Telugu & Tamil', color: '#1E9E8A' },
  mideast: { name: 'Arabic, Persian & Turkish', short: 'Middle East', color: '#C98500' },
  reggaeton: { name: 'Reggaeton', color: '#E0B000', dark: true },
  latin: { name: 'Latin', color: '#F28C38' },
  afro: { name: 'Afrobeats', color: '#8A5CF5' },
  kpop: { name: 'K-Pop & J-Pop', color: '#FF5FA2' },
  techno: { name: 'Techno', color: '#3B6CF0' },
  house: { name: 'House', color: '#5C8DFF' },
  trance: { name: 'Trance', color: '#7B61FF' },
  edm: { name: 'EDM', color: '#2E55C5' },
  bass: { name: 'Drum & Bass', color: '#1F3FA8' },
  disco: { name: 'Disco & Funk', color: '#B02A7A' },
  hiphop: { name: 'Hip-Hop & R&B', color: '#6E3FD6' },
  pop: { name: 'Pop', color: '#15806F' },
};
const ORDER = ['bollywood', 'punjabi', 'southindian', 'mideast', 'reggaeton', 'latin', 'afro', 'kpop', 'techno', 'house', 'trance', 'edm', 'bass', 'disco', 'hiphop', 'pop'];
const ELEC = new Set(['techno', 'house', 'edm', 'trance', 'bass']);
const vname = k => VIBES[k] ? (VIBES[k].short || VIBES[k].name) : k;

const OCCASIONS = [
  { key: 'sangeet', label: 'Sangeet night', desc: 'Family in the room, dhol by the second hour', weights: { bollywood: 3, punjabi: 3, southindian: 1, edm: 1 }, minutes: 120, arc: 'wedding', clean: true, fam: 0.8 },
  { key: 'party', label: 'House party', desc: 'Friends over, drinks out, peak around the second hour', weights: { pop: 3, hiphop: 1, punjabi: 1, afro: 1 }, minutes: 120, arc: 'party', clean: false, fam: 0.75 },
  { key: 'reggaeton', label: 'Reggaeton rooftop', desc: 'Sunset, dembow and a little afrobeats', weights: { reggaeton: 3, latin: 1, afro: 1 }, minutes: 90, arc: 'party', clean: false, fam: 0.75 },
  { key: 'sunset', label: 'Sunset to peak', desc: 'Starts at golden hour, ends in the dark', weights: { house: 3, disco: 1, techno: 1 }, minutes: 180, arc: 'sunset', clean: false, fam: 0.5 },
  { key: 'techno', label: 'Warehouse techno', desc: 'Long blends, no vocals, no breaks', weights: { techno: 3, house: 1 }, minutes: 120, arc: 'club', clean: false, fam: 0.4 },
  { key: 'mideast', label: 'Middle East night', desc: 'Arabic, Persian and Turkish pop with a dance edge', weights: { mideast: 3, pop: 1, edm: 1 }, minutes: 90, arc: 'party', clean: true, fam: 0.7 },
  { key: 'afro', label: 'Afro house party', desc: 'Afrobeats, amapiano and house', weights: { afro: 3, house: 1, hiphop: 1 }, minutes: 120, arc: 'party', clean: false, fam: 0.7 },
  { key: 'dinner', label: 'Dinner that turns into a party', desc: 'Quiet while people eat, then the tables get pushed back', weights: { disco: 2, pop: 2, bollywood: 1 }, minutes: 180, arc: 'sunset', clean: true, fam: 0.8 },
];
const LENGTHS = [30, 60, 90, 120, 180, 240];
const ARC_LABELS = { club: 'Club night', wedding: 'Wedding / sangeet', party: 'House party', sunset: 'Sunset to peak', peak: 'Peak time' };
const SHAPES = {
  wedding: [[0, -.7], [.12, -.45], [.3, .25], [.4, -.55], [.5, .1], [.65, .6], [.85, 1], [.95, .85], [1, .45]],
  party: [[0, -.4], [.2, .3], [.4, .7], [.55, .35], [.75, 1], [.9, .85], [1, .25]],
  sunset: [[0, -1], [.3, -.45], [.6, .3], [.85, 1], [1, .9]],
  peak: [[0, .45], [.15, .85], [.5, .75], [.8, 1], [1, .8]],
};
function interp(pts, p) { if (p <= pts[0][0]) return pts[0][1]; for (let k = 1; k < pts.length; k++) if (p <= pts[k][0]) { const [x0, y0] = pts[k - 1], [x1, y1] = pts[k]; return y0 + (y1 - y0) * (p - x0) / (x1 - x0); } return pts[pts.length - 1][1]; }

/* ---------------- state ---------------- */
const S = Object.assign({
  occasion: 'sangeet', weights: { bollywood: 3, punjabi: 3, southindian: 1, edm: 1 }, minutes: 120, arc: 'wedding', clean: true, fam: 0.8, useTaste: true, seed: 7,
}, lsGet('selector.settings', {}));
let TASTE = lsGet('selector.taste', null);
let NIGHTS = lsGet('selector.nights', []);
let NIGHT = null;          // the current plan and its playback state
let D = null, T = null, N = 0, VK = [], VI = {};
let CAMN, CAML, titleKey, byArtist, artistIdx;
let clubE = null, clubT = null;
const CFG = window.SELECTOR_CONFIG || {};
const DEMO_ONLY = !!CFG.demoOnly;

function saveSettings() { lsSet('selector.settings', { occasion: S.occasion, weights: S.weights, minutes: S.minutes, arc: S.arc, clean: S.clean, fam: S.fam, useTaste: S.useTaste, seed: S.seed }); }

/* ---------------- music theory + learned model ---------------- */
function camelot(k) { const key = k % 12, mode = k >= 12 ? 1 : 0, kk = mode ? key : (key + 3) % 12; return [((kk * 7) % 12 + 7) % 12 + 1, mode]; }
function camRel(i, j) { let d = Math.abs(CAMN[i] - CAMN[j]); d = Math.min(d, 12 - d); const s = CAML[i] === CAML[j]; if (d === 0 && s) return 'same'; if (d === 0) return 'relative'; if (d === 1 && s) return 'adjacent'; if (d === 2 && s) return 'energy2'; if (d === 1) return 'diag'; return 'clash'; }
const HARMONIC = new Set(['same', 'relative', 'adjacent', 'energy2']);
function tempoPct(a, b) { let best = Infinity; for (const f of [0.5, 1, 2]) { const v = Math.abs(Math.log2(b * f / a)); if (v < best) best = v; } return (Math.pow(2, best) - 1) * 100; }
function binOf(b, x) { for (let k = 0; k < b.length - 1; k++) if (x >= b[k] && x < b[k + 1]) return k; return b.length - 2; }
function logit(i, j) {
  const M = D.model, C = M.coef;
  let z = M.intercept;
  z += C['t' + binOf(M.tbins, tempoPct(T.bpm[i], T.bpm[j]))] || 0;
  z += C['cam_' + camRel(i, j)] || 0;
  const de = T.e[j] - T.e[i];
  z += (C['e' + binOf(M.ebins, Math.abs(de))] || 0) + (C.up_energy || 0) * Math.max(0, de);
  z += (C.ad_dance || 0) * Math.abs(T.d[j] - T.d[i]) + (C.ad_val || 0) * Math.abs(T.v[j] - T.v[i]) + (C.ad_loud || 0) * Math.abs(T.l[j] - T.l[i]) / 20 + (C.ad_instr || 0) * Math.abs(T.i[j] - T.i[i]);
  return z;
}
function normA(s) { return String(s || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/^the\s+/, '').replace(/[^\p{L}\p{N}]/gu, ''); }
function shape(arc) { return arc === 'club' ? clubE : SHAPES[arc] || SHAPES.party; }

/* transition in plain words; '' means a smooth blend the listener needn't know about */
function transitionWord(i, j) {
  const tp = tempoPct(T.bpm[i], T.bpm[j]), rel = camRel(i, j), de = T.e[j] - T.e[i];
  if (tp <= 3 && HARMONIC.has(rel)) return '';
  if (tp <= 3) return 'Beat switch';
  if (tp <= 6) return de > 0.08 ? 'Bass drop' : 'Bass swap';
  if (tp <= 12) return de > 0 ? 'Speed up' : 'Loop and cut';
  return de < -0.1 ? 'Fade down' : 'Echo out';
}

/* ---------------- planner ---------------- */
function prepareData(data) {
  D = data; T = D.t; N = T.id.length; VK = D.vibes.map(v => v.key); VI = Object.fromEntries(VK.map((k, i) => [k, i]));
  CAMN = new Int8Array(N); CAML = new Int8Array(N);
  for (let i = 0; i < N; i++) { const [n, m] = camelot(T.k[i]); CAMN[i] = n; CAML[i] = m; }
  titleKey = new Array(N); byArtist = new Map();
  for (let i = 0; i < N; i++) {
    titleKey[i] = normA(T.n[i].split(/\s[-(\[]/)[0]).slice(0, 24) + '|' + T.a[i];
    for (const a of T.ar[i].split(', ')) { const k = normA(a); if (!k) continue; if (!byArtist.has(k)) byArtist.set(k, []); byArtist.get(k).push(i); }
  }
  artistIdx = new Map(D.artists.map((a, i) => [normA(a), i]));
  const all = D.arc.arc.all;
  const sm = a => a.map((v, k) => { const s = a.slice(Math.max(0, k - 1), k + 2); return s.reduce((x, y) => x + y, 0) / s.length; });
  const eS = sm(all.energy), eMax = Math.max(...eS.map(Math.abs)) || 1;
  clubE = [[0, eS[0] / eMax]].concat(eS.map((v, k) => [(k + .5) / 10, v / eMax])).concat([[1, eS[9] / eMax]]);
  const tS = sm(all.tempo);
  clubT = [[0, tS[0]]].concat(tS.map((v, k) => [(k + .5) / 10, v])).concat([[1, tS[9]]]);
}

/* Plans a set. `tail` plans only the remainder after a fixed prefix (used for live steering). */
function buildSet(cfg) {
  const sel = Object.entries(cfg.weights).filter(([, w]) => w > 0).filter(([k]) => !(cfg.exclude && cfg.exclude.has(k)));
  if (!sel.length) return null;
  const sumW = sel.reduce((a, [, w]) => a + w, 0);
  const share = new Float32Array(VK.length); let mask = 0;
  for (const [k, w] of sel) { if (VI[k] === undefined) continue; share[VI[k]] = w / sumW; mask |= 1 << VI[k]; }
  if (cfg.boost) for (const [k, b] of Object.entries(cfg.boost)) if (VI[k] !== undefined) share[VI[k]] += b;
  const pool = []; const pv = new Int8Array(N).fill(-1);
  for (let i = 0; i < N; i++) {
    if (!(T.vm[i] & mask)) continue; if (cfg.clean && T.x[i]) continue;
    let best = -1, bw = -1; for (const [k, w] of sel) { const v = VI[k]; if (v !== undefined && (T.vm[i] & (1 << v)) && w > bw) { bw = w; best = v; } }
    pv[i] = best; pool.push(i);
  }
  if (!pool.length) return null;
  let baseE = 0; for (const [k, w] of sel) baseE += (D.vibes[VI[k]].energy_med || .6) * w / sumW;
  const amp = cfg.arc === 'club' ? 0.10 : 0.17, sh = shape(cfg.arc);
  const off = cfg.energyOff || (() => 0);
  const targetEv = (v, p) => clamp((D.vibes[v].energy_med || .6) + amp * interp(sh, p) + off(p), 0.22, 0.97);
  const bpmOff = p => cfg.arc === 'club' ? interp(clubT, p) : 3.5 * interp(sh, p);
  const targetB = (v, p) => (D.vibes[v].bpm_med || 120) + bpmOff(p);
  const tw = cfg.tw, fam = cfg.fam, rnd = mulberry32(cfg.seed), durS = cfg.durS, xf = cfg.xf || 0;
  const nGuess = Math.max(4, Math.round(durS / 200)), maxA = Math.max(2, Math.ceil(nGuess / 10));
  const playSec = j => Math.max(T.dur[j] - xf, 30);

  function stepScore(b, j, p) {
    const n = b.seq.length, prev = n ? b.seq[n - 1] : -1, v = pv[j];
    let s = 0;
    if (prev >= 0) s += logit(prev, j);
    s -= 4.0 * Math.abs(T.e[j] - targetEv(v, p));
    s -= 0.5 * Math.min(Math.abs(T.bpm[j] - targetB(v, p)) / 8, 2);
    const cur = n ? b.vc[v] / n : 0;
    s += 3.0 * (share[v] - cur) - 10.0 * Math.max(0, cur - share[v] - 0.03);
    if (prev >= 0 && pv[prev] === v && b.block < 4) s += 0.35;
    s += 0.4 * interp(sh, p) * ((D.vibes[v].energy_med || .6) - baseE) / 0.15;
    if (tw) s += 0.6 * tw[j];
    s += (fam - 0.5) * 2.2 * (T.p[j] / 100) + 0.25 * T.d[j];
    return s + rnd() * 0.3;
  }
  function ok(b, j) {
    if (b.used.has(j) || b.titles.has(titleKey[j])) return false;
    const a = T.a[j], n = b.seq.length, last = b.alast.get(a);
    if (last !== undefined && last > n - 6) return false;
    return (b.acount.get(a) || 0) < maxA;
  }
  // seed beam with the fixed prefix (already played / kept tracks)
  const root = { seq: [], score: 0, used: new Set(), titles: new Set(), alast: new Map(), acount: new Map(), vc: new Float32Array(VK.length), block: 0, t: 0, short: false };
  for (const j of (cfg.prefix || [])) {
    const n = root.seq.length;
    root.seq.push(j); root.used.add(j); root.titles.add(titleKey[j]); root.alast.set(T.a[j], n); root.acount.set(T.a[j], (root.acount.get(T.a[j]) || 0) + 1);
    const v = pv[j] >= 0 ? pv[j] : 0; root.vc[v] += 1; root.t += playSec(j);
  }
  if (cfg.elapsed !== undefined) root.t = cfg.elapsed;
  const prefixLen = root.seq.length;
  let beams = [root]; const B = 5, K = 8; let guard = 0;
  while (beams.some(b => b.t < durS) && guard++ < 200) {
    const cand = [];
    for (const b of beams) {
      if (b.t >= durS) { cand.push({ b, j: -1, sc: b.score }); continue; }
      const p = Math.min(1, (b.t + 100) / durS), top = [];
      for (const j of pool) {
        if (!ok(b, j)) continue; const sc = stepScore(b, j, p);
        if (top.length < K) { top.push({ j, sc }); top.sort((x, y) => y.sc - x.sc); } else if (sc > top[K - 1].sc) { top[K - 1] = { j, sc }; top.sort((x, y) => y.sc - x.sc); }
      }
      if (!top.length) { b.t = durS; b.short = true; cand.push({ b, j: -1, sc: b.score }); continue; }
      for (const c of top) cand.push({ b, j: c.j, sc: b.score + c.sc });
    }
    cand.sort((x, y) => y.sc - x.sc);
    const next = [], seen = new Set();
    for (const c of cand) {
      if (next.length >= B) break;
      if (c.j < 0) { if (!next.includes(c.b)) next.push(c.b); continue; }
      const key = c.j + ':' + c.b.seq.length; if (seen.has(key)) continue; seen.add(key);
      const b = c.b, j = c.j, n = b.seq.length, v = pv[j];
      const nb = { seq: b.seq.concat(j), score: c.sc, used: new Set(b.used).add(j), titles: new Set(b.titles).add(titleKey[j]), alast: new Map(b.alast).set(T.a[j], n), acount: new Map(b.acount).set(T.a[j], (b.acount.get(T.a[j]) || 0) + 1), vc: Float32Array.from(b.vc), block: (n && pv[b.seq[n - 1]] === v) ? b.block + 1 : 1, t: b.t + playSec(j), short: b.short };
      nb.vc[v] += 1; next.push(nb);
    }
    beams = next;
  }
  beams.sort((x, y) => y.score / Math.max(1, y.seq.length - prefixLen) - x.score / Math.max(1, x.seq.length - prefixLen));
  const best = beams[0];
  return { seq: best.seq.slice(prefixLen), pv, pool, short: !!best.short, baseE, amp, targetEv };
}

function newPlan() {
  const tw = (S.useTaste && TASTE) ? Float32Array.from(TASTE.tw) : null;
  const r = buildSet({ weights: S.weights, durS: S.minutes * 60, arc: S.arc, clean: S.clean, fam: S.fam, tw, seed: S.seed, xf: 0 });
  if (!r) return null;
  const occ = OCCASIONS.find(o => o.key === S.occasion);
  const heads = Object.entries(S.weights).filter(([, w]) => w > 0).sort((x, y) => y[1] - x[1]).map(([k]) => vname(k));
  const title = occ ? occ.label : `${heads.slice(0, 2).join(' & ')} night`;
  return { seq: r.seq, pv: r.pv, pool: r.pool, short: r.short, baseE: r.baseE, amp: r.amp, weights: { ...S.weights }, arc: S.arc, clean: S.clean, fam: S.fam, tw, durS: S.minutes * 60, title, exclude: null, boost: null, energyOff: null };
}

function alternative(plan, pos, exclude) {
  const seq = plan.seq, prev = pos ? seq[pos - 1] : -1, next = pos < seq.length - 1 ? seq[pos + 1] : -1;
  const st = startTimes(plan), p = (st[pos] + 60) / plan.durS;
  const used = new Set(seq), titles = new Set(seq.map(j => titleKey[j]));
  const near = new Set(); for (let k = Math.max(0, pos - 5); k < Math.min(seq.length, pos + 6); k++) if (k !== pos) near.add(T.a[seq[k]]);
  const sh = shape(plan.arc);
  let best = -1, bs = -Infinity;
  for (const j of plan.pool) {
    if (used.has(j) || exclude.has(j) || titles.has(titleKey[j]) || near.has(T.a[j])) continue;
    const v = plan.pv[j];
    let s = 0; if (prev >= 0) s += logit(prev, j); if (next >= 0) s += logit(j, next);
    s -= 4 * Math.abs(T.e[j] - clamp((D.vibes[v].energy_med || .6) + plan.amp * interp(sh, p), .22, .97));
    if (plan.tw) s += 0.6 * plan.tw[j]; s += (plan.fam - 0.5) * 2.2 * (T.p[j] / 100);
    if (s > bs) { bs = s; best = j; }
  }
  return best;
}
function startTimes(plan) { let t = 0; return plan.seq.map(j => { const s = t; t += T.dur[j]; return s; }); }
function totalSeconds(plan) { return plan.seq.reduce((a, j) => a + T.dur[j], 0); }

/* phases of the night, from the planned energy */
function phases(plan) {
  const seq = plan.seq, n = seq.length; if (n < 4) return [{ key: 'all', label: 'The night', from: 0, to: n }];
  const st = startTimes(plan), tot = totalSeconds(plan);
  const e = seq.map(j => T.e[j]);
  const sm = e.map((_, k) => { const s = e.slice(Math.max(0, k - 2), k + 3); return s.reduce((a, b) => a + b, 0) / s.length; });
  // peak: the quarter of the set with the highest average energy, not starting before 40%
  const win = Math.max(3, Math.round(n * 0.25)); let bestK = Math.round(n * 0.6), bestV = -1;
  for (let k = Math.round(n * 0.4); k + win <= n; k++) { const v = sm.slice(k, k + win).reduce((a, b) => a + b, 0) / win; if (v > bestV) { bestV = v; bestK = k; } }
  const peakFrom = bestK, peakTo = Math.min(n, bestK + win);
  const liftFrom = Math.max(Math.round(n * 0.3), peakFrom - Math.max(2, Math.round(n * 0.12)));
  const arriveTo = Math.min(liftFrom - 1, Math.max(2, Math.round(n * 0.2)));
  const landFrom = peakTo >= n - 1 ? n - 1 : peakTo;
  const out = [
    { key: 'arrive', label: 'Arrive', from: 0, to: arriveTo },
    { key: 'build', label: 'Build', from: arriveTo, to: liftFrom },
    { key: 'lift', label: 'Lift', from: liftFrom, to: peakFrom },
    { key: 'peak', label: 'Peak', from: peakFrom, to: landFrom },
    { key: 'land', label: 'Land', from: landFrom, to: n },
  ].filter(p => p.to > p.from);
  out.forEach(p => { p.start = st[p.from]; p.end = p.to < n ? st[p.to] : tot; });
  return out;
}
function phaseOf(plan, k) { const ph = phases(plan); return ph.find(p => k >= p.from && k < p.to) || ph[ph.length - 1]; }

/* the DJ explains the night */
function topArtists(plan, from, to, n = 2, vibe) {
  const c = new Map();
  for (let k = from; k < to; k++) { if (vibe && VK[plan.pv[plan.seq[k]]] !== vibe) continue; const a = T.ar[plan.seq[k]].split(', ')[0]; c.set(a, (c.get(a) || 0) + 1 + (plan.tw ? plan.tw[plan.seq[k]] : 0)); }
  if (!c.size && vibe) return topArtists(plan, from, to, n);
  return [...c.entries()].sort((a, b) => b[1] - a[1]).slice(0, n).map(x => x[0]);
}
function topVibe(plan, from, to) {
  const c = new Map(); for (let k = from; k < to; k++) { const v = VK[plan.pv[plan.seq[k]]]; c.set(v, (c.get(v) || 0) + 1); }
  return [...c.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
}
function joinNames(a) { return a.length > 1 ? a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1] : a[0] || ''; }
function whenText(sec) {
  if (NIGHT && NIGHT.startedAt) return 'at ' + fmtClock(new Date(NIGHT.startedAt + sec * 1000));
  const m = Math.round(sec / 60);
  if (m >= 25 && m <= 35) return 'around the half hour';
  if (m < 60) return `about ${m} minutes in`;
  return `at ${fmtT(sec).replace(/:\d\d$/, '')}`;
}
function djNote(plan) {
  const ph = phases(plan), seq = plan.seq, n = seq.length;
  const get = k => ph.find(p => p.key === k);
  const arrive = get('arrive'), build = get('build'), lift = get('lift'), peak = get('peak'), land = get('land');
  if (!arrive || !peak) return `A ${fmtLen(totalSeconds(plan))} set of ${n} songs. I'll read the room and keep it moving.`;
  const opener = T.ar[seq[0]].split(', ')[0];
  const A = topArtists(plan, arrive.from, arrive.to).filter(x => x !== opener).slice(0, 1);
  const overall = topVibe(plan, 0, n), liftV = lift ? topVibe(plan, lift.from, lift.to) : null, peakV = topVibe(plan, peak.from, peak.to);
  const gentle = ['wedding', 'sunset', 'club'].includes(plan.arc);
  let s = gentle ? `I'll ease people in with ${joinNames([opener].concat(A))} while they arrive` : `I'll open with ${joinNames([opener].concat(A))} to get the room moving`;
  if (build) { const B = topArtists(plan, build.from, build.to); s += `, start building ${whenText(build.start)} with ${joinNames(B)}`; }
  if (lift) {
    const L = topArtists(plan, lift.from, lift.to, 1);
    s += liftV && liftV !== overall ? `, then lift into a run of ${vname(liftV)} ${whenText(lift.start)} so everyone's on the floor.` : `, then lift it ${whenText(lift.start)} with ${joinNames(L)} so everyone's on the floor.`;
  } else s += '.';
  const P = topArtists(plan, peak.from, peak.to, 2, peakV);
  s += ` From ${whenText(peak.start).replace(/^at /, '')} it's peak ${vname(peakV)} with ${joinNames(P)}`;
  const closer = T.n[seq[n - 1]].replace(/\s*[\(\[].*$/, '');
  const soft = land && T.e[seq[n - 1]] < T.e[seq[peak.from]] - 0.08;
  s += `, and I'll land the night ${soft ? 'softly ' : ''}with ${closer}.`;
  return s;
}

/* ---------------- Apple Music ---------------- */
const AM = { music: null, sf: 'us', devToken: CFG.developerToken || '', ready: false, authorized: false, subscribed: null, failed: '' };
const MATCH_CACHE = lsGet('selector.matches.v2', {});
const META = new Map(); // apple id -> {id,url,art,bg,text,preview,dur,explicit}
function hasApple() { return !!AM.devToken && !DEMO_ONLY; }
async function amInit() {
  if (!hasApple()) return;
  try {
    if (!window.MusicKit) await Promise.race([window.__mkReady, new Promise((_, rej) => setTimeout(() => rej(new Error('MusicKit did not load')), 12000))]);
    await MusicKit.configure({ developerToken: AM.devToken, app: { name: 'Selector', build: '1.0.0' } });
    AM.music = MusicKit.getInstance(); AM.ready = true; AM.sf = AM.music.storefrontId || 'us';
    AM.authorized = !!AM.music.isAuthorized;
    const m = AM.music;
    m.addEventListener('nowPlayingItemDidChange', () => Player.onFullItem());
    m.addEventListener('playbackStateDidChange', () => Player.onFullState());
    m.addEventListener('playbackTimeDidChange', () => Player.onFullTime());
    if (AM.authorized) checkSubscription();
  } catch (e) { AM.failed = e.message || String(e); }
  renderAvatar();
}
async function checkSubscription() {
  try { const r = await AM.music.api.music('/v1/me/storefront'); AM.subscribed = !!(r && r.data); } catch (e) { AM.subscribed = false; }
  if (AM.subscribed) AM.sf = AM.music.storefrontId || AM.sf;
  renderAvatar();
}
async function authorize() {
  if (!AM.ready) { toast(AM.failed ? 'Apple Music failed to start: ' + AM.failed : 'Apple Music is still loading'); return false; }
  try { await AM.music.authorize(); } catch (e) { toast('Apple Music sign-in was cancelled'); return false; }
  AM.authorized = !!AM.music.isAuthorized; if (AM.authorized) await checkSubscription();
  return AM.authorized;
}
const searchTitle = s => String(s).replace(/\(From\s+"[^"]*"\)/gi, ' ').replace(/\((feat|ft|with)\.?[^)]*\)/gi, ' ').replace(/\s+-\s+(From|Remaster|Remastered|Original|Radio|Extended|Single|Spotify).*$/i, '').replace(/[\(\)\[\]"]/g, ' ').replace(/\s+/g, ' ').trim();
const normT = s => normA(String(s).replace(/\s*[\(\[][^\)\]]*[\)\]]/g, ' ').split(/\s+-\s+/)[0]);
function metaFrom(s) {
  const a = s.attributes || {};
  const art = a.artwork ? a.artwork.url.replace('{w}', '600').replace('{h}', '600') : '';
  return { id: s.id, url: a.url || '', art, bg: a.artwork && a.artwork.bgColor ? '#' + a.artwork.bgColor : '', text: a.artwork && a.artwork.textColor1 ? '#' + a.artwork.textColor1 : '', preview: a.previews && a.previews[0] ? a.previews[0].url : '', dur: a.durationInMillis ? a.durationInMillis / 1000 : 0, explicit: a.contentRating === 'explicit', name: a.name, artist: a.artistName };
}
async function findOnApple(j, clean) {
  if (!AM.ready) return null;
  const key = AM.sf + (clean ? ':c:' : ':') + T.id[j];
  if (key in MATCH_CACHE) { const c = MATCH_CACHE[key]; if (!c) return null; META.set(c.id, c); return c; }
  const want = normT(T.n[j]), arts = T.ar[j].split(', ').map(normA).filter(Boolean);
  const title = searchTitle(T.n[j]), artist = T.ar[j].split(', ')[0];
  let best = null, bs = 0, searched = false;
  for (const term of [`${title} ${artist}`, title]) {
    let r = null;
    for (let k = 0; k < 3 && !r; k++) { try { r = await AM.music.api.music(`/v1/catalog/${AM.sf}/search`, { term, types: 'songs', limit: 10 }); } catch (e) { await new Promise(res => setTimeout(res, 500 * (k + 1))); } }
    if (!r) continue; searched = true;
    for (const s of (r.data && r.data.results && r.data.results.songs ? r.data.results.songs.data : [])) {
      const a = s.attributes || {}; if (!a.playParams) continue; if (clean && a.contentRating === 'explicit') continue;
      const tt = normT(a.name || ''); const ts = tt === want ? 1 : ((tt.includes(want) || want.includes(tt)) && Math.min(tt.length, want.length) >= 4 ? 0.8 : 0);
      const an = normA(a.artistName || ''); const as = arts.some(x => an.includes(x) || x.includes(an)) ? 1 : 0;
      const dd = Math.abs((a.durationInMillis || 0) / 1000 - T.dur[j]); const ds = dd <= 4 ? 1 : dd <= 15 ? 0.6 : dd <= 40 ? 0.2 : 0;
      const sc = ts * 0.55 + as * 0.35 + ds * 0.10; if (sc > bs) { bs = sc; best = s; }
    }
    if (bs >= 0.8) break;
  }
  if (!searched) return undefined;
  const hit = best && bs >= 0.72 ? metaFrom(best) : null;
  MATCH_CACHE[key] = hit; lsSet('selector.matches.v2', MATCH_CACHE);
  if (hit) META.set(hit.id, hit);
  return hit;
}
/* match every track of the night; swap in close fits when Apple Music lacks one */
async function resolveNight(night) {
  if (!hasApple() || !AM.ready || night.resolving) return;
  night.resolving = true; night.resolveNote = '';
  const plan = night.plan, clean = plan.clean;
  const todo = plan.seq.map((_, k) => k).filter(k => !night.am[k]);
  let done = plan.seq.length - todo.length, failed = 0;
  const setStatus = () => { if (NIGHT === night) renderPlanStatus(`Finding your songs on Apple Music… ${done} of ${plan.seq.length}`); };
  setStatus();
  const claimed = new Set();
  async function work(k) {
    let j = plan.seq[k], hit = await findOnApple(j, clean);
    if (hit === undefined) failed++;
    const tried = new Set([j]); let tries = 0;
    while (!hit && tries < 6 && NIGHT === night) {
      const alt = alternative(plan, k, new Set([...tried, ...claimed, ...plan.seq])); if (alt < 0) break;
      tried.add(alt); claimed.add(alt); hit = await findOnApple(alt, clean); if (hit) { plan.seq[k] = alt; night.replaced.add(k); } tries++;
    }
    night.am[k] = hit || null; done++; setStatus();
  }
  const q = todo.slice(); const workers = [];
  for (let w = 0; w < 4; w++) workers.push((async () => { while (q.length && NIGHT === night) await work(q.shift()); })());
  await Promise.all(workers);
  night.resolving = false;
  if (NIGHT !== night) return;
  const keep = plan.seq.map((_, k) => k).filter(k => night.am[k]);
  const dropped = plan.seq.length - keep.length;
  if (dropped) { plan.seq = keep.map(k => plan.seq[k]); night.am = keep.map(k => night.am[k]); night.replaced = new Set([...night.replaced].filter(k => keep.includes(k)).map(k => keep.indexOf(k))); }
  night.resolved = true;
  night.resolveNote = failed ? `Some searches failed, so a few songs may be missing. Pull to retry.` : (dropped ? `${dropped} song${dropped > 1 ? 's' : ''} wasn't on Apple Music, so your DJ replaced ${dropped > 1 ? 'them' : 'it'}.` : '');
  renderPlanStatus(night.resolveNote || `All ${plan.seq.length} songs found on Apple Music.`);
  renderCurrentScreen();
}

/* ---------------- playback ---------------- */
const Player = {
  mode: 'none', idx: -1, playing: false, elapsed: 0, dur: 0, loved: false, a: null, b: null, fading: false, timer: null, xf: isIOS ? 0 : 4,
  meta(k) { return NIGHT && NIGHT.am[k] ? NIGHT.am[k] : null; },
  async start(k, mode) {
    if (!NIGHT) return;
    this.stop(true);
    this.mode = mode; this.idx = k;
    if (!NIGHT.startedAt) NIGHT.startedAt = Date.now() - startTimes(NIGHT.plan)[k] * 1000;
    if (mode === 'full') {
      const ids = NIGHT.am.slice(k).map(m => m && m.id).filter(Boolean);
      try { await AM.music.setQueue({ songs: ids }); await AM.music.play(); } catch (e) { toast("Couldn't start Apple Music playback"); return; }
    } else if (mode === 'preview') {
      this.ensureAudio(); this.playPreview(k);
    } else { this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; this.playing = true; this.startDemoClock(); }
    this.onTrack(k);
  },
  ensureAudio() {
    if (this.a) return;
    this.a = new Audio(); this.b = new Audio(); this.a.preload = 'auto'; this.b.preload = 'auto';
    for (const el of [this.a, this.b]) {
      el.addEventListener('timeupdate', () => this.onPreviewTime(el));
      el.addEventListener('ended', () => this.onPreviewEnded(el));
      el.addEventListener('play', () => { if (el === this.a) { this.playing = true; renderTransport(); } });
      el.addEventListener('pause', () => { if (el === this.a && !this.fading) { this.playing = false; renderTransport(); } });
    }
  },
  playPreview(k) {
    const m = this.meta(k); if (!m || !m.preview) { this.advance(); return; }
    this.a.src = m.preview; this.a.volume = 1; this.a.currentTime = 0;
    this.a.play().catch(() => { toast('Tap play to start sound'); this.playing = false; renderTransport(); });
    const next = this.meta(k + 1); if (next && next.preview) { this.b.src = next.preview; this.b.load(); }
    this.dur = 30; this.elapsed = 0;
  },
  onPreviewTime(el) {
    if (el !== this.a) return;
    this.elapsed = el.currentTime; this.dur = el.duration && isFinite(el.duration) ? el.duration : 30;
    if (this.xf > 0 && !this.fading && this.dur - this.elapsed <= this.xf && this.meta(this.idx + 1) && this.meta(this.idx + 1).preview) this.crossfade();
    renderProgress();
  },
  crossfade() {
    this.fading = true;
    const out = this.a, inn = this.b, k = this.idx + 1, m = this.meta(k);
    if (inn.src !== m.preview) inn.src = m.preview;
    inn.volume = 0; inn.currentTime = 0; inn.play().catch(() => {});
    const t0 = performance.now(), dur = this.xf * 1000;
    const step = () => { const p = clamp((performance.now() - t0) / dur, 0, 1); try { out.volume = 1 - p; inn.volume = p; } catch (e) {} if (p < 1 && this.fading) requestAnimationFrame(step); };
    requestAnimationFrame(step);
    setTimeout(() => { if (!this.fading) return; out.pause(); this.a = inn; this.b = out; this.fading = false; this.idx = k; this.dur = 30; const nx = this.meta(k + 1); if (nx && nx.preview) { this.b.src = nx.preview; this.b.load(); } this.onTrack(k); }, dur);
  },
  onPreviewEnded(el) { if (el === this.a && !this.fading) this.advance(); },
  startDemoClock() { clearInterval(this.timer); this.timer = setInterval(() => { if (!this.playing) return; this.elapsed += 6; if (this.elapsed >= this.dur) this.advance(); else renderProgress(); }, 1000); },
  advance() { if (!NIGHT) return; if (this.idx + 1 >= NIGHT.plan.seq.length) { this.finish(); return; } const k = this.idx + 1; if (this.mode === 'preview') { this.idx = k; this.playPreview(k); this.onTrack(k); } else if (this.mode === 'demo') { this.idx = k; this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; this.onTrack(k); } },
  onTrack(k) {
    this.idx = k; NIGHT.played.add(k);
    const m = this.meta(k); const j = NIGHT.plan.seq[k];
    this.loved = NIGHT.loved.has(j);
    if (NIGHT.plan.seq.length - k === 1) { /* last song */ }
    renderNowPlaying(); renderMini(); if (current === 'songs') renderSongs();
  },
  async toggle() {
    if (this.mode === 'full') { if (this.playing) AM.music.pause(); else { try { await AM.music.play(); } catch (e) {} } }
    else if (this.mode === 'preview') { if (this.playing) this.a.pause(); else this.a.play().catch(() => {}); }
    else { this.playing = !this.playing; renderTransport(); }
  },
  async next() { if (this.mode === 'full') { try { await AM.music.skipToNextItem(); } catch (e) {} } else { this.fading = false; if (this.b) { this.b.pause(); } this.advance(); } },
  async prev() { if (this.elapsed > 5) { this.seek(0); return; } if (this.mode === 'full') { try { await AM.music.skipToPreviousItem(); } catch (e) {} } else if (this.idx > 0) { const k = this.idx - 1; if (this.mode === 'preview') { this.fading = false; this.playPreview(k); } else { this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; } this.onTrack(k); } },
  seek(t) { if (this.mode === 'full') AM.music.seekToTime(t); else if (this.mode === 'preview') this.a.currentTime = t; else this.elapsed = t; },
  /* the plan changed after the current song: rebuild what's queued */
  async requeue() {
    if (this.mode === 'full') { const k = this.idx, t = AM.music.currentPlaybackTime || 0, wasPlaying = this.playing; const ids = NIGHT.am.slice(k).map(m => m && m.id).filter(Boolean); try { await AM.music.setQueue({ songs: ids }); await AM.music.seekToTime(t); if (wasPlaying) await AM.music.play(); } catch (e) {} }
    else if (this.mode === 'preview') { const nx = this.meta(this.idx + 1); if (nx && nx.preview && this.b) { this.b.src = nx.preview; this.b.load(); } }
    renderNowPlaying();
  },
  stop(silent) {
    clearInterval(this.timer); this.fading = false;
    if (this.mode === 'full' && AM.music) { try { AM.music.stop(); } catch (e) {} }
    if (this.a) { this.a.pause(); this.b.pause(); }
    this.mode = 'none'; this.playing = false; this.idx = -1; this.elapsed = 0;
    if (!silent) { renderMini(); }
  },
  finish() { this.stop(true); finishNight(); },
  /* MusicKit events */
  onFullItem() {
    if (this.mode !== 'full' || !NIGHT) return;
    const it = AM.music.nowPlayingItem; if (!it) return;
    const id = it.id || (it.attributes && it.attributes.playParams && it.attributes.playParams.id);
    const k = NIGHT.am.findIndex((m, i) => i >= Math.max(0, this.idx) && m && m.id === id);
    if (k >= 0 && k !== this.idx) this.onTrack(k);
    else if (k < 0) { const k2 = NIGHT.am.findIndex(m => m && m.id === id); if (k2 >= 0 && k2 !== this.idx) this.onTrack(k2); }
  },
  onFullState() {
    if (this.mode !== 'full') return;
    const PS = MusicKit.PlaybackStates, st = AM.music.playbackState;
    this.playing = st === PS.playing; renderTransport();
    if ((st === PS.completed || st === PS.ended) && NIGHT && this.idx >= NIGHT.plan.seq.length - 1) this.finish();
  },
  onFullTime() { if (this.mode !== 'full') return; this.elapsed = AM.music.currentPlaybackTime || 0; this.dur = AM.music.currentPlaybackDuration || this.dur; renderProgress(); },
};

/* ---------------- the night ---------------- */
function makeNight(plan) {
  return { plan, am: new Array(plan.seq.length).fill(undefined), replaced: new Set(), resolving: false, resolved: false, resolveNote: '', startedAt: null, played: new Set(), loved: new Set(), requests: [], saved: false, undo: null, createdAt: Date.now() };
}
function planNight() {
  const plan = newPlan();
  if (!plan) { toast('Pick at least one sound'); return false; }
  NIGHT = makeNight(plan);
  Player.stop();
  if (hasApple() && AM.ready) resolveNight(NIGHT);
  return true;
}
function clockAt(k) { const base = NIGHT.startedAt || roundedNow(); return new Date(base + startTimes(NIGHT.plan)[k] * 1000); }
function roundedNow() { const d = new Date(); d.setSeconds(0, 0); d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5); return d.getTime(); }
function endsAt(minutes) { return fmtClock(new Date(roundedNow() + minutes * 60000)); }

function swapAt(k) {
  const plan = NIGHT.plan;
  const tried = NIGHT.swaps?.[k] || new Set([plan.seq[k]]);
  const alt = alternative(plan, k, tried);
  if (alt < 0) { toast('No other song fits this spot'); return; }
  tried.add(alt); NIGHT.swaps = NIGHT.swaps || {}; NIGHT.swaps[k] = tried;
  plan.seq[k] = alt; NIGHT.am[k] = undefined; NIGHT.replaced.delete(k);
  renderCurrentScreen();
  if (hasApple() && AM.ready) findOnApple(alt, plan.clean).then(hit => { if (!NIGHT || NIGHT.plan.seq[k] !== alt) return; NIGHT.am[k] = hit || null; if (!hit) toast("That one isn't on Apple Music. Swap again."); renderCurrentScreen(); if (Player.mode !== 'none' && k > Player.idx) Player.requeue(); });
  if (Player.mode === 'demo' && k > Player.idx) Player.requeue();
}
function removeAt(k) {
  if (Player.mode !== 'none' && k <= Player.idx) { toast('That one already played'); return; }
  NIGHT.plan.seq.splice(k, 1); NIGHT.am.splice(k, 1);
  renderCurrentScreen(); if (Player.mode !== 'none') Player.requeue();
}

/* live steering: re-plan everything after the current song */
function steer(action, arg) {
  if (!NIGHT) return '';
  const plan = NIGHT.plan, cur = Player.mode !== 'none' ? Player.idx : -1;
  const keep = cur + 1;                                // songs that stay: played + the one playing
  const prefix = plan.seq.slice(0, keep);
  const st = startTimes(plan), elapsed = keep < plan.seq.length ? st[keep] : totalSeconds(plan);
  NIGHT.undo = { seq: plan.seq.slice(), am: NIGHT.am.slice(), opts: { exclude: plan.exclude, boost: plan.boost, energyOff: plan.energyOff, fam: plan.fam, durS: plan.durS } };
  let durS = plan.durS, fam = plan.fam, energyOff = plan.energyOff, boost = plan.boost ? { ...plan.boost } : null, exclude = plan.exclude ? new Set(plan.exclude) : null, reply = '';
  const curVibe = cur >= 0 ? VK[plan.pv[plan.seq[cur]]] : null;
  const tailStart = elapsed / durS;
  if (action === 'up') { energyOff = p => (p < tailStart + 0.18 ? 0.12 : 0.05); reply = "Got it. I'll lift the energy over the next two songs and keep it up from there."; }
  else if (action === 'down') { energyOff = p => (p < tailStart + 0.18 ? -0.12 : -0.05); reply = "Easing it down after this one. I'll hold it mellow for a stretch."; }
  else if (action === 'familiar') { fam = 0.95; reply = "Switching to the songs everyone knows for the rest of the night."; }
  else if (action === 'surprise') { fam = 0.35; reply = "Going deeper. Fewer hits, more finds."; }
  else if (action === 'more') { boost = { ...(boost || {}), [arg]: ((boost || {})[arg] || 0) + 0.35 }; if (exclude) exclude.delete(arg); reply = `More ${vname(arg)} coming, starting after this one.`; }
  else if (action === 'skip') { const v = arg || curVibe; if (!v) return ''; exclude = new Set(exclude || []); exclude.add(v); const left = Object.keys(plan.weights).filter(k => !exclude.has(k)); if (!left.length) { exclude.delete(v); return "That's the only sound in the night, so I'll keep it."; } reply = `No more ${vname(v)} for now. I'll lean on ${joinNames(left.map(vname))}.`; }
  else if (action === 'wrap') { durS = elapsed + (arg || 20) * 60; energyOff = p => -0.25 * clamp((p - tailStart) / Math.max(0.05, 1 - tailStart), 0, 1); reply = `Wrapping up. ${arg || 20} more minutes, then I'll bring it home.`; }
  else return '';
  const tw = plan.tw;
  const r = buildSet({ weights: plan.weights, durS, arc: plan.arc, clean: plan.clean, fam, tw, seed: (S.seed = (S.seed * 48271) % 2147483647 || 11), xf: 0, prefix, elapsed, energyOff, boost, exclude });
  if (!r || !r.seq.length) { NIGHT.undo = null; return "I couldn't find enough songs for that. Try another request."; }
  plan.seq = prefix.concat(r.seq); plan.fam = fam; plan.energyOff = energyOff; plan.boost = boost; plan.exclude = exclude; plan.durS = durS;
  NIGHT.am = NIGHT.am.slice(0, keep).concat(new Array(r.seq.length).fill(undefined));
  NIGHT.replaced = new Set([...NIGHT.replaced].filter(k => k < keep));
  NIGHT.requests.push({ action, arg, at: Date.now() });
  if (action === 'up' && r.seq.length) { let hot = -1, he = -1; for (let i = 0; i < Math.min(4, r.seq.length); i++) if (T.e[r.seq[i]] > he) { he = T.e[r.seq[i]]; hot = i; } if (hot >= 0) reply = `Got it. I'll lift the energy over the next two songs and bring ${T.n[r.seq[hot]].replace(/\s*[\(\[].*$/, '')} forward to ${fmtClock(clockAt(keep + hot))}.`; }
  if (hasApple() && AM.ready) resolveNight(NIGHT).then(() => Player.requeue()); else Player.requeue();
  renderCurrentScreen();
  return reply;
}
function undoSteer() {
  if (!NIGHT || !NIGHT.undo) return;
  const u = NIGHT.undo; NIGHT.plan.seq = u.seq; NIGHT.am = u.am; Object.assign(NIGHT.plan, u.opts); NIGHT.undo = null; NIGHT.requests.pop();
  Player.requeue(); renderCurrentScreen();
}
function parseRequest(text) {
  const t = ' ' + text.toLowerCase().replace(/[^a-z0-9&\s]/g, ' ') + ' ';
  if (/(wrap|wind down|last song|end it|end the night|finish|close out)/.test(t)) { const m = t.match(/(\d+)\s*(min|minute)/); return ['wrap', m ? +m[1] : 20]; }
  for (const k of ORDER) {
    const tokens = [VIBES[k].name, VIBES[k].short || '', k].join(' & ').toLowerCase().split(/\s*&\s*|\s*,\s*|\s+/).map(x => x.trim()).filter(x => x.length >= 3 && !['and', 'the'].includes(x));
    if (tokens.some(n => t.includes(' ' + n))) { if (/(no more|skip|less|enough|drop|stop|without)/.test(t)) return ['skip', k]; return ['more', k]; }
  }
  if (/(slow|chill|mellow|bring it down|calm|softer|lower|down)/.test(t)) return ['down'];
  if (/(energy|hype|turn up|louder|faster|harder|up|bang|lift|dance)/.test(t)) return ['up'];
  if (/(know|familiar|hits|classic|sing along|popular)/.test(t)) return ['familiar'];
  if (/(surprise|deep cut|new|discover|underground)/.test(t)) return ['surprise'];
  return null;
}

function finishNight() {
  if (!NIGHT) return;
  const rec = recapOf(NIGHT);
  NIGHTS = [rec].concat(NIGHTS.filter(n => n.id !== rec.id)).slice(0, 12); lsSet('selector.nights', NIGHTS);
  RECAP = rec; lsSet('selector.night', null);
  go('recap');
}
function recapOf(night) {
  const plan = night.plan, played = [...night.played].sort((a, b) => a - b);
  const pool = played.length ? played : plan.seq.map((_, k) => k);
  let peakK = pool[0], pe = -1; for (const k of pool) { const e = T.e[plan.seq[k]]; if (e > pe) { pe = e; peakK = k; } }
  const base = night.startedAt || roundedNow();
  return { id: night.createdAt, title: plan.title, date: new Date(base).toLocaleDateString([], { weekday: 'long' }), seconds: played.length ? played.reduce((a, k) => a + T.dur[plan.seq[k]], 0) : totalSeconds(plan), songs: pool.length, peakK, peakJ: plan.seq[peakK], peakAt: fmtClock(new Date(base + startTimes(plan)[peakK] * 1000)), peakArt: night.am[peakK] ? night.am[peakK].art : '', loved: night.loved.size, requests: night.requests.length, saved: night.saved, vibes: Object.keys(plan.weights).map(vname), seq: plan.seq.slice(0, 15), arts: plan.seq.slice(0, 15).map((_, k) => night.am[k] ? night.am[k].art : ''), weights: plan.weights, minutes: Math.round(plan.durS / 60), arc: plan.arc, clean: plan.clean, fam: plan.fam, occasion: S.occasion };
}

/* ---------------- taste ---------------- */
function tasteFrom(names, source) {
  const tw = new Float32Array(N); const matched = []; const aff = {};
  names.forEach((name, r) => {
    const w = 1 - 0.6 * r / Math.max(1, names.length - 1), k = normA(name), tr = byArtist.get(k); if (!tr) return;
    matched.push(name);
    for (const i of tr) { if (tw[i] < w) tw[i] = w; VK.forEach((v, vi) => { if (T.vm[i] & (1 << vi)) aff[v] = (aff[v] || 0) + w; }); }
    const ai = artistIdx.get(k); if (ai !== undefined) for (const nb of D.an[ai] || []) for (const i of byArtist.get(normA(D.artists[nb])) || []) if (tw[i] < 0.45 * w) tw[i] = 0.45 * w;
  });
  if (!matched.length) return null;
  const top = Object.entries(aff).sort((a, b) => b[1] - a[1]).slice(0, 4).map(x => x[0]);
  return { tw: Array.from(tw), matched, total: names.length, top, source };
}
async function tasteFromLibrary() {
  if (!await authorize()) return;
  try {
    const seen = new Map(); let got = 0;
    for (const path of ['/v1/me/recent/played/tracks', '/v1/me/library/songs']) {
      let next = path, params = { limit: path.includes('recent') ? 30 : 100 }, pages = 0;
      while (next && pages < 4) {
        const r = await AM.music.api.music(next, params); pages++;
        const items = r.data && r.data.data ? r.data.data : [];
        for (const it of items) { const a = it.attributes && it.attributes.artistName; if (!a) continue; got++; seen.set(a, (seen.get(a) || 0) + (path.includes('recent') ? 3 : 1)); }
        next = r.data && r.data.next ? r.data.next : null; params = {};
      }
    }
    const ranked = [...seen.entries()].sort((a, b) => b[1] - a[1]).slice(0, 80).map(x => x[0]);
    const t = tasteFrom(ranked, `Your Apple Music (${got} recent plays)`);
    if (!t) { toast("None of your recent artists are in your DJ's crate yet"); return; }
    TASTE = t; lsSet('selector.taste', TASTE); renderBrief(); renderTonight(); toast(`Learned your taste from ${t.matched.length} artists`);
  } catch (e) { toast("Couldn't read your Apple Music library"); }
}

/* ---------------- rendering ---------------- */
let current = 'tonight'; const stack = [];
function coverEl(j, k, cls) {
  const m = NIGHT && k !== undefined && k !== null ? NIGHT.am[k] : null;
  if (m && m.art) return `<div class="cover ${cls || ''}" style="background-image:url('${m.art}')"></div>`;
  return `<div class="cover ph ${cls || ''}" style="--c:${phColor(j)}"></div>`;
}
function phColor(j) { const v = VK[(NIGHT && NIGHT.plan.pv[j] >= 0) ? NIGHT.plan.pv[j] : 0] || 'pop'; const base = VIBES[v] ? VIBES[v].color : '#444'; const h = (j * 37) % 3; return shade(base, [0, -14, 12][h]); }
function shade(hex, pct) { const n = parseInt(hex.slice(1), 16); let r = n >> 16, g = n >> 8 & 255, b = n & 255; const f = 1 + pct / 100; r = clamp(Math.round(r * f), 0, 255); g = clamp(Math.round(g * f), 0, 255); b = clamp(Math.round(b * f), 0, 255); return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0'); }
function mosaic(el, ks) { el.innerHTML = ks.map(k => coverEl(NIGHT.plan.seq[k], k)).join(''); }

function renderAvatar() { const a = $('#btn-you'); a.classList.toggle('on', AM.authorized && AM.subscribed !== false); }

function renderTonight() {
  const h = new Date().getHours();
  $('#dayline').textContent = new Date().toLocaleDateString([], { weekday: 'long' }) + (h < 12 ? ' morning' : h < 17 ? ' afternoon' : ' evening');
  const occ = OCCASIONS.find(o => o.key === S.occasion) || OCCASIONS[0];
  const headsH = Object.entries(S.weights).filter(([, w]) => w > 0).sort((x, y) => y[1] - x[1]).map(([k]) => vname(k));
  $('#hero-title').textContent = S.occasion ? occ.label : `${headsH.slice(0, 2).join(' & ')} night`;
  const sel = Object.entries(S.weights).filter(([, w]) => w > 0).sort((a, b) => b[1] - a[1]).map(([k]) => vname(k));
  $('#hero-sub').textContent = `${fmtLen(S.minutes * 60)} · ${sel.slice(0, 3).join(', ')}${sel.length > 3 ? ` +${sel.length - 3}` : ''}`;
  $('#hero-why').textContent = TASTE ? `Tuned to ${TASTE.matched.slice(0, 2).join(' and ')}${TASTE.matched.length > 2 ? ' and more' : ''}` : 'From the sounds you pick most';
  const cols = Object.keys(S.weights).filter(k => S.weights[k] > 0).slice(0, 4); while (cols.length < 4) cols.push(cols[cols.length - 1] || 'pop');
  $('#hero-mosaic').innerHTML = cols.map((k, i) => `<div class="cover ph" style="--c:${shade(VIBES[k].color, [0, -14, 12, -6][i])}"></div>`).join('');
  $('#quick-starts').innerHTML = OCCASIONS.filter(o => o.key !== S.occasion).slice(0, 6).map(o => { const k = Object.keys(o.weights)[0], v = VIBES[k]; return `<button class="qtile ${v.dark ? 'dark' : ''}" type="button" data-occ="${o.key}" style="background:${v.color}">${esc(o.label)}<div class="cover ph" style="--c:${shade(v.color, -30)}"></div></button>`; }).join('');
  const ns = $('#nights-section'); ns.hidden = !NIGHTS.length;
  $('#nights-list').innerHTML = NIGHTS.slice(0, 3).map((n, i) => `<button class="night-row" type="button" data-night="${i}"><div class="mosaic">${n.arts.slice(0, 4).map((a, q) => a ? `<div class="cover" style="background-image:url('${a}')"></div>` : `<div class="cover ph" style="--c:${shade(VIBES[Object.keys(n.weights)[q % Object.keys(n.weights).length] || 'pop'].color, -10 * q)}"></div>`).join('')}</div><div class="night-text"><b>${esc(n.title)}</b><span>${esc(n.date)} · ${fmtLen(n.seconds)} · peaked with ${esc(T.n[n.peakJ].replace(/\s*[\(\[].*$/, ''))}</span></div><svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg></button>`).join('');
  renderAvatar();
}

function renderBrief() {
  const occ = OCCASIONS.find(o => o.key === S.occasion);
  $('#val-occasion').textContent = occ ? occ.label : 'Custom';
  $('#val-length').textContent = fmtLen(S.minutes * 60).replace(' min', ' min').replace(/^(\d+) h$/, '$1 hour' + (S.minutes === 60 ? '' : 's'));
  $('#val-ends').textContent = '· ends ' + endsAt(S.minutes);
  $('#val-crowd').textContent = S.clean ? 'Family-friendly' : 'Anything goes';
  $('#val-crowd2').textContent = S.fam >= 0.65 ? '· songs we know' : '· surprise us';
  const heads = Object.entries(S.weights).filter(([, w]) => w >= 3).map(([k]) => k);
  $('#vibe-grid').innerHTML = ORDER.map(k => { const v = VIBES[k], w = S.weights[k] || 0, meta = D.vibes[VI[k]]; return `<div class="tile ${w ? 'on' : ''} ${w >= 3 ? 'head' : ''} ${v.dark ? 'dark' : ''}" style="--c:${v.color}" data-vibe="${k}"><span class="tile-dot"></span><button class="tile-main" type="button" data-act="toggle" aria-pressed="${!!w}">${esc(v.short || v.name)}<span class="tile-count">${k === 'mideast' ? 'mostly Turkish for now' : (meta ? meta.n.toLocaleString() + ' songs' : '')}</span></button><button class="tile-star" type="button" data-act="star" aria-label="${w >= 3 ? 'Headliner' : 'Make headliner'}" aria-pressed="${w >= 3}"><svg viewBox="0 0 24 24"><path d="M12 2l3 7 7 .6-5.3 4.6L18.4 22 12 18.2 5.6 22l1.7-7.8L2 9.6 9 9z"/></svg></button><span class="tile-check" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></div>`; }).join('');
  $('#taste-text').textContent = TASTE ? `${TASTE.source}. Your DJ knows ${TASTE.matched.length} of your artists${TASTE.matched.length ? ': ' + TASTE.matched.slice(0, 5).join(', ') : ''}${TASTE.matched.length > 5 ? ` and ${TASTE.matched.length - 5} more` : ''}.` : "Not loaded yet. Your DJ leans on the sounds you pick and what's popular.";
  $('#btn-taste-clear').hidden = !TASTE;
  $('#btn-taste-library').hidden = !hasApple();
  void heads;
}

function renderPlanStatus(msg) { const el = $('#plan-status'); if (el) el.textContent = msg || ''; }
function renderPlan() {
  if (!NIGHT) return;
  const plan = NIGHT.plan, n = plan.seq.length, tot = totalSeconds(plan);
  $('#plan-title').textContent = plan.title;
  $('#plan-meta').textContent = `${fmtLen(tot)} · ${n} songs · ends ${fmtClock(new Date((NIGHT.startedAt || roundedNow()) + tot * 1000))}`;
  mosaic($('#plan-mosaic'), [0, Math.floor(n / 3), Math.floor(2 * n / 3), n - 1].map(k => clamp(k, 0, n - 1)));
  $('#dj-note').textContent = djNote(plan);
  $('#btn-start span').textContent = Player.mode !== 'none' ? 'Back to the night' : 'Start the night';
  $('#btn-save').classList.toggle('filled', NIGHT.saved);
  $('#btn-save').innerHTML = NIGHT.saved ? '<svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10" fill="none" stroke="#fff" stroke-width="2.4"/></svg>' : '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>';
  renderPlanStatus(NIGHT.resolving ? 'Finding your songs on Apple Music…' : (NIGHT.resolveNote || (NIGHT.resolved ? `All ${n} songs found on Apple Music.` : (hasApple() ? '' : (DEMO_ONLY ? 'Demo: the plan is real, playback needs the full app.' : 'Add your Apple Music key to hear it.')))));
  renderJourney();
  $('#link-all').textContent = `All ${n} songs`;
  $('#plan-first').innerHTML = [0, 1].filter(k => k < n).map(k => songRow(k, { time: fmtClock(clockAt(k)) })).join('');
}
function renderJourney() {
  const plan = NIGHT.plan, seq = plan.seq, n = seq.length, st = startTimes(plan), tot = totalSeconds(plan);
  const e = seq.map(j => T.e[j]); const sm = e.map((_, k) => { const s = e.slice(Math.max(0, k - 2), k + 3); return s.reduce((a, b) => a + b, 0) / s.length; });
  const lo = Math.min(...sm) - 0.04, hi = Math.max(...sm) + 0.04;
  const W = 358, H = 64; const pts = seq.map((j, k) => [16 + (W - 32) * (st[k] + T.dur[j] / 2) / tot, 6 + (H - 10) * (1 - (sm[k] - lo) / (hi - lo))]);
  const cr = p => { let d = `M${p[0][0].toFixed(1)},${p[0][1].toFixed(1)}`; for (let i = 0; i < p.length - 1; i++) { const p0 = p[Math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(i + 2, p.length - 1)]; d += `C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(1)},${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(1)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(1)},${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`; } return d; };
  const d = cr(pts), ph = phases(plan), peak = ph.find(p => p.key === 'peak');
  let peakPt = pts[peak ? peak.from : 0]; if (peak) { let be = -1; for (let k = peak.from; k < peak.to; k++) if (sm[k] > be) { be = sm[k]; peakPt = pts[k]; } }
  const nowX = Player.mode !== 'none' && Player.idx >= 0 ? pts[Player.idx][0] : null;
  $('#journey-svg').innerHTML = `<path class="area" d="${d} L${pts[pts.length - 1][0].toFixed(1)},70 L${pts[0][0].toFixed(1)},70 Z"/><path class="line" d="${d}"/><circle class="dot" cx="${peakPt[0].toFixed(1)}" cy="${peakPt[1].toFixed(1)}" r="4"/>${nowX !== null ? `<line class="now" x1="${nowX.toFixed(1)}" x2="${nowX.toFixed(1)}" y1="0" y2="70"/>` : ''}`;
  $('#journey-labels').innerHTML = ph.map(p => p.key === 'peak' ? `<b>Peak · ${esc(whenText(p.start).replace(/^at /, '').replace(/^about /, ''))}</b>` : `<span>${p.label}</span>`).join('');
}

let phaseFilter = 'all';
function songRow(k, opt = {}) {
  const j = NIGHT.plan.seq[k], m = NIGHT.am[k];
  const status = m === null ? '<span class="dim"> · not on Apple Music</span>' : (NIGHT.replaced.has(k) ? '<span class="dim"> · close match</span>' : '');
  const cls = (Player.idx === k && Player.mode !== 'none') ? 'now' : (NIGHT.played.has(k) && Player.idx > k ? 'played' : '');
  const artist = T.ar[j].split(', ').slice(0, 2).join(', ');
  return `<button class="song ${cls}" type="button" data-k="${k}">${coverEl(j, k, 'row')}<div class="text"><div class="name">${esc(T.n[j])}</div><div class="artist">${esc(artist)}${status}</div></div><span class="time">${opt.time || ''}</span>${opt.more ? '<span class="more" data-more="' + k + '"><svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg></span>' : ''}</button>`;
}
function renderSongs() {
  if (!NIGHT) return;
  const plan = NIGHT.plan, n = plan.seq.length, ph = phases(plan);
  $('#songs-title').textContent = `${n} songs`;
  $('#phase-chips').innerHTML = [{ key: 'all', label: 'All' }].concat(ph).map(p => `<button class="pchip ${phaseFilter === p.key ? 'on' : ''}" type="button" data-phase="${p.key}">${esc(p.label)}</button>`).join('');
  let html = '';
  for (const p of ph) {
    if (phaseFilter !== 'all' && phaseFilter !== p.key) continue;
    html += `<div class="phase-head"><span>${esc(p.label.toUpperCase())}</span><span>${fmtClock(clockAt(p.from))} – ${fmtClock(new Date((NIGHT.startedAt || roundedNow()) + p.end * 1000))}</span></div>`;
    for (let k = p.from; k < p.to; k++) {
      if (k > p.from || phaseFilter !== 'all') { const w = k > 0 ? transitionWord(plan.seq[k - 1], plan.seq[k]) : ''; if (w) html += `<div class="tx-label ${/drop|switch|speed/i.test(w) ? 'hot' : ''}"><i></i><span>${esc(w.toUpperCase())}</span><i></i></div>`; }
      html += `<div class="swipe" data-k="${k}">${songRow(k, { time: fmtClock(clockAt(k)), more: true })}<div class="actions"><button class="swapb" type="button" data-swap="${k}"><svg viewBox="0 0 24 24"><path d="M4 7h13l-3-3M20 17H7l3 3"/></svg>Swap</button><button type="button" data-remove="${k}"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>Remove</button></div></div>`;
    }
  }
  $('#song-list').innerHTML = html;
  $('#btn-start2').innerHTML = Player.mode !== 'none' ? '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>Back to the night' : '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>Start the night';
  $('#songs-cta').hidden = Player.mode !== 'none';
}

function renderNowPlaying() {
  if (!NIGHT || Player.idx < 0) return;
  const k = Player.idx, j = NIGHT.plan.seq[k], m = NIGHT.am[k];
  $('#np-set').textContent = NIGHT.plan.title;
  const art = $('#np-art');
  if (m && m.art) { art.style.backgroundImage = `url('${m.art}')`; art.classList.remove('ph'); art.style.removeProperty('--c'); } else { art.style.backgroundImage = ''; art.classList.add('ph'); art.style.setProperty('--c', phColor(j)); }
  const tint = m && m.bg ? mixDark(m.bg) : mixDark(phColor(j));
  $('#s-playing').style.setProperty('--tint', tint); const tc = document.querySelector('meta[name=theme-color]'); if (tc) tc.setAttribute('content', current === 'playing' ? tint : '#0A0A0D');
  $('#np-name').textContent = T.n[j]; $('#np-artist').textContent = T.ar[j];
  $('#btn-love').classList.toggle('on', NIGHT.loved.has(j));
  const nk = k + 1, nj = NIGHT.plan.seq[nk];
  if (nj !== undefined) {
    $('#next-card').hidden = false;
    $('#next-art').outerHTML = coverEl(nj, nk, 'sm').replace('class="cover', 'id="next-art" class="cover');
    $('#next-name').innerHTML = `${esc(T.n[nj])} <span>· ${esc(T.ar[nj].split(', ')[0])}</span>`;
  } else { $('#next-card').hidden = true; }
  const heads = Object.entries(NIGHT.plan.weights).filter(([, w]) => w >= 3).map(([k2]) => k2);
  const chips = [['up', 'More energy', 'M12 19V5M6 11l6-6 6 6'], ['down', 'Bring it down', 'M12 5v14M6 13l6 6 6-6'], ['familiar', 'Something we know'], ...heads.slice(0, 1).map(h => ['more', `More ${vname(h)}`, '', h]), ['skip', 'Skip this vibe'], ['wrap', 'Wrap up in 20 min', '', 20]];
  $('#steer-row').innerHTML = chips.map(c => `<button class="chip light" type="button" data-steer="${c[0]}" data-arg="${c[3] ?? ''}">${c[2] ? `<svg viewBox="0 0 24 24"><path d="${c[2]}"/></svg>` : ''}${esc(c[1])}</button>`).join('');
  $('#np-mode').textContent = Player.mode === 'full' ? (isIOS ? 'Full songs from your Apple Music. Keep Selector open to hear the whole night.' : 'Full songs from your Apple Music.') : Player.mode === 'preview' ? `Preview mode: 30 seconds of each song${Player.xf ? ', blended' : ''}. Connect Apple Music for full songs.` : 'Demo: the clock runs six times faster than the music would. Playback needs the full app.';
  renderTransport(); renderProgress(); renderMini();
}
function mixDark(hex) { try { const n = parseInt(hex.slice(1), 16); const r = n >> 16, g = n >> 8 & 255, b = n & 255; const f = 0.28; return `rgb(${Math.round(r * f + 10)},${Math.round(g * f + 10)},${Math.round(b * f + 13)})`; } catch (e) { return '#1A0F12'; } }
function renderTransport() { const p = Player.playing; $('#play-icon').innerHTML = p ? '<path d="M7 5h4v14H7zM13 5h4v14h-4z"/>' : '<path d="M7 4.5v15l12-7.5z"/>'; $('#btn-play').setAttribute('aria-label', p ? 'Pause' : 'Play'); $('#mini-play').innerHTML = p ? '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zM13 5h4v14h-4z"/></svg>' : '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>'; }
function renderProgress() {
  const d = Player.dur || 1, e = Player.elapsed;
  $('#np-bar').style.width = clamp(100 * e / d, 0, 100).toFixed(1) + '%';
  $('#np-el').textContent = fmtT(e); $('#np-rem').textContent = '−' + fmtT(Math.max(0, d - e));
  const rem = Math.max(0, d - e), xf = Player.mode === 'preview' ? Player.xf : 0;
  $('#next-kicker').textContent = rem <= Math.max(xf, 10) + 0.5 && xf ? `BLENDING IN · ${fmtT(rem)}` : `UP NEXT · ${fmtT(rem)}`;
  $('#ring-fg').style.strokeDashoffset = (69.1 * (1 - clamp(e / d, 0, 1))).toFixed(1);
}
function renderMini() {
  const m = $('#mini'); const show = Player.mode !== 'none' && current !== 'playing' && NIGHT && Player.idx >= 0;
  m.hidden = !show; document.body.classList.toggle('has-mini', show);
  if (!show) return;
  const k = Player.idx, j = NIGHT.plan.seq[k];
  $('#mini-art').outerHTML = coverEl(j, k, 'sm').replace('class="cover', 'id="mini-art" class="cover');
  $('#mini-name').textContent = T.n[j]; $('#mini-artist').textContent = T.ar[j].split(', ')[0];
  renderTransport();
}
let RECAP = null;
function renderRecap() {
  const r = RECAP; if (!r) return;
  $('#recap-title').textContent = r.title;
  $('#recap-meta').textContent = `${r.date} · ${fmtLen(r.seconds)} · ${r.songs} songs${r.requests === 0 ? ' · no requests needed' : ''}`;
  $('#recap-mosaic').innerHTML = r.seq.map((j, i) => r.arts[i] ? `<div class="cover" style="background-image:url('${r.arts[i]}')"></div>` : `<div class="cover ph" style="--c:${shade(VIBES[VK[(NIGHT && NIGHT.plan.pv[j] >= 0) ? NIGHT.plan.pv[j] : 0]] ? VIBES[VK[NIGHT ? NIGHT.plan.pv[j] : 0]].color : '#444', (i % 3) * 9 - 9)}"></div>`).join('');
  $('#recap-kicker').textContent = `THE FLOOR PEAKED AT ${r.peakAt.toUpperCase()}`;
  $('#recap-art').outerHTML = (r.peakArt ? `<div id="recap-art" class="cover md" style="background-image:url('${r.peakArt}')"></div>` : `<div id="recap-art" class="cover md ph" style="--c:${VIBES[VK[NIGHT ? NIGHT.plan.pv[r.peakJ] : 0]] ? VIBES[VK[NIGHT.plan.pv[r.peakJ]]].color : '#E4572E'}"></div>`);
  $('#recap-song').textContent = T.n[r.peakJ].replace(/\s*[\(\[].*$/, ''); $('#recap-artist').textContent = T.ar[r.peakJ];
  $('#recap-stats').innerHTML = `<div><b>${r.songs}</b><span>songs</span></div><div><b>${r.loved}</b><span>you loved</span></div><div><b>${r.requests}</b><span>request${r.requests === 1 ? '' : 's'}</span></div>`;
  $('#recap-saved').hidden = !r.saved;
}

function renderCurrentScreen() { ({ tonight: renderTonight, brief: renderBrief, plan: renderPlan, songs: renderSongs, playing: renderNowPlaying, recap: renderRecap })[current]?.(); renderMini(); }

/* ---------------- router ---------------- */
function go(name, opts = {}) {
  if (name === 'back') { name = stack.pop() || 'tonight'; } else if (!opts.replace && current !== name) stack.push(current);
  if (stack.length > 12) stack.shift();
  $$('.screen').forEach(s => { s.hidden = s.id !== 's-' + name; s.classList.remove('enter'); });
  const el = $('#s-' + name); if (!el) return; void el.offsetWidth; el.classList.add('enter');
  current = name; closeSheets();
  renderCurrentScreen();
  const tc = document.querySelector('meta[name=theme-color]'); if (tc) tc.setAttribute('content', name === 'playing' ? getComputedStyle(el).getPropertyValue('--tint') || '#0A0A0D' : '#0A0A0D');
  const sc = el.querySelector('.scroll'); if (sc && !opts.keepScroll) sc.scrollTop = 0;
}
function openSheet(id) { closeSheets(); $('#backdrop').hidden = false; $('#' + id).hidden = false; }
function closeSheets() { $('#backdrop').hidden = true; $$('.sheet').forEach(s => { s.hidden = true; }); }

/* ---------------- flows ---------------- */
async function startNight(fromK = 0) {
  if (!NIGHT) { if (!planNight()) return; }
  if (Player.mode !== 'none') { go('playing'); return; }
  if (!hasApple()) { await Player.start(fromK, 'demo'); go('playing'); return; }
  if (!AM.ready) { toast(AM.failed ? 'Apple Music failed to start: ' + AM.failed : 'Apple Music is still loading, one moment'); return; }
  if (NIGHT.resolving) { toast('Still finding your songs. One moment.'); return; }
  if (!NIGHT.resolved) { await resolveNight(NIGHT); }
  if (!NIGHT.am.some(Boolean)) { toast("None of these songs are on Apple Music here. Try other sounds."); return; }
  if (AM.authorized && AM.subscribed) { await Player.start(fromK, 'full'); go('playing'); return; }
  pendingStart = fromK; openConnect();
}
let pendingStart = 0;
function openConnect() {
  $('#connect-title').textContent = AM.authorized && AM.subscribed === false ? 'No Apple Music subscription on this Apple ID' : 'Hear the whole night';
  $('#connect-text').textContent = AM.authorized && AM.subscribed === false ? 'Full songs need an active Apple Music subscription. You can still hear 30-second previews of every song.' : 'Connect Apple Music to play full songs. Or start with 30-second previews of every song, no sign-in needed.';
  $('#connect-actions').innerHTML = `${AM.authorized && AM.subscribed === false ? '' : '<button class="chip on" type="button" data-connect="full">Connect Apple Music</button>'}<button class="chip" type="button" data-connect="preview">Play previews</button>`;
  openSheet('sheet-connect');
}
async function savePlaylist() {
  if (!NIGHT) return;
  if (!hasApple() || !AM.ready) { toast('Saving needs the Apple Music key'); return; }
  if (!await authorize()) return;
  if (!NIGHT.resolved && !NIGHT.resolving) await resolveNight(NIGHT);
  const ids = NIGHT.am.filter(Boolean).map(m => m.id); if (!ids.length) { toast('Nothing to save yet'); return; }
  try {
    const res = await fetch('https://api.music.apple.com/v1/me/library/playlists', { method: 'POST', headers: { Authorization: 'Bearer ' + AM.devToken, 'Music-User-Token': AM.music.musicUserToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ attributes: { name: `Selector · ${NIGHT.plan.title}`, description: `Planned by your Selector DJ. ${Object.keys(NIGHT.plan.weights).map(vname).join(', ')}.` }, relationships: { tracks: { data: ids.map(id => ({ id, type: 'songs' })) } } }) });
    if (!res.ok) throw new Error(res.status);
    NIGHT.saved = true; renderPlan(); toast('Saved to your Apple Music library. In the Music app, turn on AutoMix for blended transitions.');
  } catch (e) { toast("Couldn't save the playlist"); }
}
async function shareRecap() {
  const r = RECAP; if (!r) return;
  const text = `${r.title} · ${fmtLen(r.seconds)} · ${r.songs} songs. The floor peaked at ${r.peakAt} with ${T.n[r.peakJ].replace(/\s*[\(\[].*$/, '')} by ${T.ar[r.peakJ]}. Planned by Selector.`;
  try { if (navigator.share) { await navigator.share({ title: r.title, text }); return; } } catch (e) { return; }
  try { await navigator.clipboard.writeText(text); toast('Copied. Paste it anywhere.'); } catch (e) { toast(text); }
}

/* ---------------- events ---------------- */
function bind() {
  document.addEventListener('click', e => {
    const goBtn = e.target.closest('[data-go]'); if (goBtn) { go(goBtn.dataset.go); return; }
    const occ = e.target.closest('[data-occ]'); if (occ) { applyOccasion(occ.dataset.occ); go('brief'); return; }
    const night = e.target.closest('[data-night]'); if (night) { RECAP = NIGHTS[+night.dataset.night]; go('recap'); return; }
  });
  $('#btn-ask').addEventListener('click', () => go('brief'));
  $('#btn-hero-change').addEventListener('click', () => go('brief'));
  $('#btn-quick-all').addEventListener('click', () => { go('brief'); openSheet('sheet-occasion'); renderOccasionSheet(); });
  $('#btn-hero-start').addEventListener('click', () => { if (planNight()) { go('plan'); } });
  $('#btn-you').addEventListener('click', async () => { if (!hasApple()) { toast(DEMO_ONLY ? 'This demo plans the night; the full app plays it through Apple Music.' : 'Add your Apple Music developer token in config.js to connect.'); return; } if (AM.authorized) { toast(AM.subscribed ? 'Apple Music connected' : 'Connected, but this Apple ID has no Apple Music subscription'); return; } if (await authorize()) toast('Apple Music connected'); });
  $('#btn-reset').addEventListener('click', () => { applyOccasion('sangeet'); renderBrief(); });
  $('#row-occasion').addEventListener('click', () => { renderOccasionSheet(); openSheet('sheet-occasion'); });
  $('#row-length').addEventListener('click', () => { renderLengthSheet(); openSheet('sheet-length'); });
  $('#row-crowd').addEventListener('click', () => { renderCrowdSheet(); openSheet('sheet-crowd'); });
  $('#vibe-grid').addEventListener('click', e => {
    const b = e.target.closest('button[data-act]'); if (!b) return; const k = b.closest('.tile').dataset.vibe, w = S.weights[k] || 0;
    if (b.dataset.act === 'toggle') { if (w) delete S.weights[k]; else S.weights[k] = 1; }
    else { if (w >= 3) S.weights[k] = 1; else { const heads = Object.entries(S.weights).filter(([, x]) => x >= 3).map(([x]) => x); if (heads.length >= 2) { const drop = heads[0]; S.weights[drop] = 1; toast(`${vname(drop)} is no longer a headliner`); } S.weights[k] = 3; } }
    S.occasion = (OCCASIONS.find(o => sameWeights(S.weights, o.weights)) || {}).key || null;
    saveSettings(); renderBrief();
  });
  $('#btn-plan').addEventListener('click', () => { if (planNight()) go('plan'); });
  $('#btn-taste-library').addEventListener('click', tasteFromLibrary);
  $('#btn-taste-type').addEventListener('click', () => { $('#taste-input').value = TASTE && TASTE.source.startsWith('You typed') ? TASTE.matched.join(', ') : ''; openSheet('sheet-taste'); setTimeout(() => $('#taste-input').focus(), 50); });
  $('#btn-taste-clear').addEventListener('click', () => { TASTE = null; lsSet('selector.taste', null); renderBrief(); renderTonight(); });
  $('#taste-form').addEventListener('submit', e => { e.preventDefault(); const names = $('#taste-input').value.split(',').map(s => s.trim()).filter(Boolean); if (!names.length) return; const t = tasteFrom(names, `You typed ${names.length} artist${names.length > 1 ? 's' : ''}`); if (!t) { toast("None of those are in your DJ's crate yet"); return; } TASTE = t; lsSet('selector.taste', TASTE); closeSheets(); renderBrief(); renderTonight(); });
  $('#backdrop').addEventListener('click', closeSheets);
  $('#btn-newtake').addEventListener('click', () => { if (Player.mode !== 'none') { toast("The night's already playing. Use Tell your DJ instead."); return; } S.seed = (S.seed * 48271) % 2147483647 || 11; saveSettings(); planNight(); renderPlan(); });
  $('#btn-start').addEventListener('click', () => startNight(0));
  $('#btn-start2').addEventListener('click', () => startNight(0));
  $('#btn-save').addEventListener('click', savePlaylist);
  $('#plan-first').addEventListener('click', e => { if (e.target.closest('.song')) go('songs'); });
  $('#phase-chips').addEventListener('click', e => { const b = e.target.closest('[data-phase]'); if (!b) return; phaseFilter = b.dataset.phase; renderSongs(); });
  $('#song-list').addEventListener('click', e => {
    const sw = e.target.closest('[data-swap]'); if (sw) { closeSwipes(); swapAt(+sw.dataset.swap); return; }
    const rm = e.target.closest('[data-remove]'); if (rm) { closeSwipes(); removeAt(+rm.dataset.remove); return; }
    const more = e.target.closest('[data-more]'); if (more) { e.stopPropagation(); const w = more.closest('.swipe'); const open = w.classList.contains('open'); closeSwipes(); w.classList.toggle('open', !open); return; }
    const row = e.target.closest('.song'); if (row && !row.closest('.swipe.open')) { const k = +row.dataset.k; if (Player.mode !== 'none') { Player.start(k, Player.mode).then(() => go('playing')); } else startNight(k); }
  });
  bindSwipe($('#song-list'));
  $('#btn-play').addEventListener('click', () => Player.toggle());
  $('#btn-next').addEventListener('click', () => Player.next());
  $('#btn-prev').addEventListener('click', () => Player.prev());
  $('#btn-love').addEventListener('click', () => { if (!NIGHT || Player.idx < 0) return; const j = NIGHT.plan.seq[Player.idx]; if (NIGHT.loved.has(j)) NIGHT.loved.delete(j); else NIGHT.loved.add(j); $('#btn-love').classList.toggle('on', NIGHT.loved.has(j)); });
  $('#next-card').addEventListener('click', () => go('songs'));
  $('#steer-row').addEventListener('click', e => { const b = e.target.closest('[data-steer]'); if (!b) return; openSteer(b.dataset.steer, b.dataset.arg); });
  $('#steer-chips').addEventListener('click', e => { const b = e.target.closest('[data-steer]'); if (!b) return; doSteer(b.dataset.steer, b.dataset.arg); });
  $('#steer-form').addEventListener('submit', e => { e.preventDefault(); const t = $('#steer-input').value.trim(); if (!t) return; const p = parseRequest(t); if (!p) { showReply("I didn't catch that. Try 'more energy', 'slow it down', 'more Punjabi', or 'wrap up in 15 minutes'."); return; } $('#steer-input').value = ''; doSteer(p[0], p[1]); });
  $('#btn-undo').addEventListener('click', () => { undoSteer(); $('#dj-reply').hidden = true; $$('#steer-chips .chip').forEach(c => c.classList.remove('on')); toast('Back to the earlier plan'); });
  $('#mini').addEventListener('click', e => { if (e.target.closest('#mini-play')) { Player.toggle(); return; } go('playing'); });
  $('#mini-play').addEventListener('click', e => { e.stopPropagation(); Player.toggle(); });
  $('#connect-actions').addEventListener('click', async e => { const b = e.target.closest('[data-connect]'); if (!b) return; if (b.dataset.connect === 'full') { if (!await authorize()) return; if (!AM.subscribed) { openConnect(); return; } closeSheets(); await Player.start(pendingStart, 'full'); go('playing'); } else { closeSheets(); await Player.start(pendingStart, 'preview'); go('playing'); } });
  $('#btn-share').addEventListener('click', shareRecap);
  $('#btn-again').addEventListener('click', () => { const r = RECAP; if (!r) return; S.weights = { ...r.weights }; S.minutes = r.minutes; S.arc = r.arc; S.clean = r.clean; S.fam = r.fam; S.occasion = r.occasion; saveSettings(); if (planNight()) go('plan'); });
  $('#occasion-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; applyOccasion(b.dataset.pick); closeSheets(); renderBrief(); });
  $('#length-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; S.minutes = +b.dataset.pick; saveSettings(); closeSheets(); renderBrief(); });
  $('#crowd-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; const v = b.dataset.pick; if (v === 'clean') S.clean = !S.clean; if (v === 'known') S.fam = 0.85; if (v === 'surprise') S.fam = 0.4; if (v === 'taste') S.useTaste = !S.useTaste; saveSettings(); renderCrowdSheet(); renderBrief(); });
  window.addEventListener('pagehide', () => { if (NIGHT) lsSet('selector.night', { seq: NIGHT.plan.seq, weights: NIGHT.plan.weights, arc: NIGHT.plan.arc, clean: NIGHT.plan.clean, fam: NIGHT.plan.fam, durS: NIGHT.plan.durS, title: NIGHT.plan.title, startedAt: NIGHT.startedAt, played: [...NIGHT.played], loved: [...NIGHT.loved], requests: NIGHT.requests, saved: NIGHT.saved, createdAt: NIGHT.createdAt }); });
}
function sameWeights(a, b) { if (!b) return false; const ka = Object.keys(a).filter(k => a[k] > 0), kb = Object.keys(b); return ka.length === kb.length && ka.every(k => a[k] === b[k]); }
function applyOccasion(key) { const o = OCCASIONS.find(x => x.key === key); if (!o) return; S.occasion = key; S.weights = { ...o.weights }; S.minutes = o.minutes; S.arc = o.arc; S.clean = o.clean; S.fam = o.fam; saveSettings(); renderTonight(); }
function renderOccasionSheet() { $('#occasion-list').innerHTML = OCCASIONS.map(o => `<button class="opt ${S.occasion === o.key ? 'on' : ''}" type="button" data-pick="${o.key}"><div><b>${esc(o.label)}</b><span>${esc(o.desc)}</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>`).join(''); }
function renderLengthSheet() { $('#length-list').innerHTML = LENGTHS.map(m => `<button class="opt ${S.minutes === m ? 'on' : ''}" type="button" data-pick="${m}"><div><b>${fmtLen(m * 60)}</b><span>ends around ${endsAt(m)}</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>`).join(''); }
function renderCrowdSheet() { $('#crowd-list').innerHTML = `<button class="toggle-row" type="button" data-pick="clean"><div><b>Family-friendly</b><span>No explicit versions</span></div><span class="switch ${S.clean ? 'on' : ''}"></span></button><button class="opt ${S.fam >= 0.65 ? 'on' : ''}" type="button" data-pick="known"><div><b>Songs we know</b><span>The hits, the sing-alongs</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button><button class="opt ${S.fam < 0.65 ? 'on' : ''}" type="button" data-pick="surprise"><div><b>Surprise us</b><span>Deeper cuts, fewer obvious picks</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>${TASTE ? `<button class="toggle-row" type="button" data-pick="taste"><div><b>Lean on my taste</b><span>${esc(TASTE.matched.slice(0, 3).join(', '))}</span></div><span class="switch ${S.useTaste ? 'on' : ''}"></span></button>` : ''}`; $$('#crowd-list .opt b, #crowd-list .toggle-row b').forEach(b => { b.style.display = 'block'; }); }
function openSteer(action, arg) {
  const heads = NIGHT ? Object.entries(NIGHT.plan.weights).filter(([, w]) => w >= 3).map(([k]) => k) : [];
  const chips = [['up', 'More energy', 'M12 19V5M6 11l6-6 6 6'], ['down', 'Bring it down', 'M12 5v14M6 13l6 6 6-6'], ['familiar', 'Something we know'], ['surprise', 'Surprise us'], ...heads.map(h => ['more', `More ${vname(h)}`, '', h]), ['skip', 'Skip this vibe'], ['wrap', 'Wrap up in 20 min', '', 20]];
  $('#steer-chips').innerHTML = chips.map(c => `<button class="chip" type="button" data-steer="${c[0]}" data-arg="${c[3] ?? ''}">${c[2] ? `<svg viewBox="0 0 24 24"><path d="${c[2]}"/></svg>` : ''}${esc(c[1])}</button>`).join('');
  $('#dj-reply').hidden = true; openSheet('sheet-steer');
  if (action) doSteer(action, arg);
}
function doSteer(action, arg) {
  const a = action === 'wrap' ? +arg || 20 : arg || null;
  const reply = steer(action, a);
  $$('#steer-chips .chip').forEach(c => c.classList.toggle('on', c.dataset.steer === action && (c.dataset.arg || '') === String(arg ?? '')));
  showReply(reply || "I couldn't do that one.");
}
function showReply(text) { $('#dj-reply').hidden = false; $('#dj-reply-text').textContent = text; $('#btn-undo').hidden = !(NIGHT && NIGHT.undo); }
function closeSwipes() { $$('.swipe.open').forEach(w => w.classList.remove('open')); }
function bindSwipe(list) {
  let startX = 0, startY = 0, el = null, dx = 0, horizontal = null;
  list.addEventListener('pointerdown', e => { el = e.target.closest('.swipe'); if (!el) return; startX = e.clientX; startY = e.clientY; dx = 0; horizontal = null; el.querySelector('.song').style.transition = 'none'; }, { passive: true });
  list.addEventListener('pointermove', e => { if (!el) return; const mx = e.clientX - startX, my = e.clientY - startY; if (horizontal === null && (Math.abs(mx) > 8 || Math.abs(my) > 8)) horizontal = Math.abs(mx) > Math.abs(my); if (!horizontal) return; el.classList.add('dragging'); dx = clamp(mx + (el.classList.contains('open') ? -176 : 0), -176, 0); el.querySelector('.song').style.transform = `translateX(${dx}px)`; }, { passive: true });
  const end = () => { if (!el) return; const s = el.querySelector('.song'); s.style.transition = ''; s.style.transform = ''; const w = el; if (horizontal) { const open = dx < -88; closeSwipes(); w.classList.toggle('open', open); } setTimeout(() => w.classList.remove('dragging'), 220); el = null; };
  list.addEventListener('pointerup', end); list.addEventListener('pointercancel', end);
}

/* ---------------- boot ---------------- */
async function boot() {
  try {
    const res = await fetch('data.json'); const data = await res.json(); prepareData(data);
  } catch (e) { document.body.innerHTML = '<p style="padding:40px;color:#fff">Couldn\'t load the music data. Serve this folder over http (see README).</p>'; return; }
  bind();
  renderTonight();
  const saved = lsGet('selector.night', null);
  if (saved && Date.now() - saved.createdAt < 12 * 3600 * 1000) {
    const tw = (S.useTaste && TASTE) ? Float32Array.from(TASTE.tw) : null;
    const r = buildSet({ weights: saved.weights, durS: 60, arc: saved.arc, clean: saved.clean, fam: saved.fam, tw, seed: 1, xf: 0 });
    if (r) { NIGHT = makeNight({ seq: saved.seq, pv: r.pv, pool: r.pool, short: false, baseE: r.baseE, amp: r.amp, weights: saved.weights, arc: saved.arc, clean: saved.clean, fam: saved.fam, tw, durS: saved.durS, title: saved.title, exclude: null, boost: null, energyOff: null }); NIGHT.startedAt = saved.startedAt; NIGHT.played = new Set(saved.played); NIGHT.loved = new Set(saved.loved); NIGHT.requests = saved.requests || []; NIGHT.saved = !!saved.saved; NIGHT.createdAt = saved.createdAt; }
  }
  go('tonight', { replace: true });
  amInit().then(() => { if (NIGHT && AM.ready) resolveNight(NIGHT); });
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
}
boot();
})();
