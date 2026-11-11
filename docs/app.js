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
  bollywood: { name: 'Bollywood', color: '#FF4FA0' },
  punjabi: { name: 'Punjabi', color: '#FF8A1F' },
  southindian: { name: 'Telugu & Tamil', color: '#19C3A6' },
  mideast: { name: 'Arabic, Persian & Turkish', short: 'Middle East', color: '#E9B44C' },
  reggaeton: { name: 'Reggaeton', color: '#FFD60A' },
  latin: { name: 'Latin', color: '#FF5E3A' },
  afro: { name: 'Afrobeats', color: '#5BD66B' },
  kpop: { name: 'K-Pop & J-Pop', color: '#6FD3FF' },
  techno: { name: 'Techno', color: '#4D7DFF' },
  house: { name: 'House', color: '#2ED3E6' },
  trance: { name: 'Trance', color: '#9B8CFF' },
  edm: { name: 'EDM', color: '#B8F03C' },
  bass: { name: 'Drum & Bass', color: '#FF3B4E' },
  disco: { name: 'Disco & Funk', color: '#F25BD6' },
  hiphop: { name: 'Hip-Hop & R&B', color: '#C9A4FF' },
  pop: { name: 'Pop', color: '#FF7A90' },
};
const ORDER = ['bollywood', 'punjabi', 'southindian', 'mideast', 'reggaeton', 'latin', 'afro', 'kpop', 'techno', 'house', 'trance', 'edm', 'bass', 'disco', 'hiphop', 'pop'];
const REGIONAL = ['bollywood', 'punjabi', 'southindian', 'mideast', 'reggaeton', 'latin', 'afro', 'kpop'];
const byWeight = w => Object.entries(w).filter(([, x]) => x > 0).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([k]) => k);
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
  buildLexicon();
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
  const homeVibe = i => { let best = 0, bs = -1; for (let v = 0; v < VK.length; v++) if ((T.vm[i] & (1 << v)) && share[v] > bs) { bs = share[v]; best = v; } return best; };
  const favor = cfg.favor || {}, banned = cfg.banned || new Set();
  // songs asked for by name or artist come along even when their sound wasn't picked
  for (const [k, f] of Object.entries(favor)) { const i = +k; if (f >= 2 && pv[i] < 0 && !(cfg.clean && T.x[i])) { pv[i] = homeVibe(i); pool.push(i); } }
  for (const j of (cfg.prefix || [])) if (pv[j] < 0) pv[j] = homeVibe(j);
  if (!pool.length) return null;
  // how much each sound was asked for, 0..1: headliners own the peak, the rest fill the valleys
  const maxW = Math.max(...sel.map(([, w]) => w)); const want = new Float32Array(VK.length); for (const [k, w] of sel) if (VI[k] !== undefined) want[VI[k]] = w / maxW;
  // a song that also belongs to a regional sound nobody asked for would stick out, so it has to earn its place
  let foreignMask = 0; for (const k of REGIONAL) if (VI[k] !== undefined && !(mask & (1 << VI[k]))) foreignMask |= 1 << VI[k];
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
    const arcNow = interp(sh, p);
    s += 0.15 * arcNow * ((D.vibes[v].energy_med || .6) - baseE) / 0.15;
    s += (arcNow > 0 ? 1.1 : 0.5) * arcNow * (want[v] - 0.6);
    if ((T.vm[j] & foreignMask) && favor[j] === undefined) s -= 1.6;
    if (tw) s += 0.6 * tw[j];
    if (favor[j] !== undefined) s += favor[j];
    if (p > 0.93 || n === 0) s += 1.4 * T.p[j] / 100;      // open and close on songs people know
    s += (fam - 0.5) * 2.2 * (T.p[j] / 100) + 0.25 * T.d[j];
    return s + rnd() * 0.3;
  }
  function ok(b, j) {
    if (b.used.has(j) || b.titles.has(titleKey[j])) return false;
    const a = T.a[j], n = b.seq.length, last = b.alast.get(a);
    if (banned.has(a)) return false;
    if (last !== undefined && last > n - 6) return false;
    return (b.acount.get(a) || 0) < maxA;
  }
  // seed beam with the fixed prefix (already played / kept tracks)
  const root = { seq: [], score: 0, used: new Set(), titles: new Set(), alast: new Map(), acount: new Map(), vc: new Float32Array(VK.length), block: 0, t: 0, short: false };
  for (const j of (cfg.prefix || [])) {
    const n = root.seq.length;
    root.seq.push(j); root.used.add(j); root.titles.add(titleKey[j]); root.alast.set(T.a[j], n); root.acount.set(T.a[j], (root.acount.get(T.a[j]) || 0) + 1);
    root.vc[pv[j]] += 1; root.t += playSec(j);
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

let briefTitle = null;
function nightTitle(w) { const h = byWeight(w).map(vname); return h.length ? `${h.slice(0, 2).join(' & ')} night` : 'Your night'; }
function newPlan() {
  const tw = (S.useTaste && TASTE) ? Float32Array.from(TASTE.tw) : null;
  const r = buildSet({ weights: S.weights, durS: S.minutes * 60, arc: S.arc, clean: S.clean, fam: S.fam, tw, seed: S.seed, xf: 0 });
  if (!r) return null;
  const occ = OCCASIONS.find(o => o.key === S.occasion);
  const title = occ ? occ.label : (briefTitle || nightTitle(S.weights)); briefTitle = null;
  return { seq: r.seq, pv: r.pv, pool: r.pool, short: r.short, baseE: r.baseE, amp: r.amp, weights: { ...S.weights }, arc: S.arc, clean: S.clean, fam: S.fam, tw, durS: S.minutes * 60, title, exclude: null, boost: null, energyOff: null, favor: {}, banned: new Set() };
}

function alternative(plan, pos, exclude) {
  const seq = plan.seq, prev = pos ? seq[pos - 1] : -1, next = pos < seq.length - 1 ? seq[pos + 1] : -1;
  const st = startTimes(plan), p = (st[pos] + 60) / plan.durS;
  const used = new Set(seq), titles = new Set(seq.map(j => titleKey[j]));
  const near = new Set(); for (let k = Math.max(0, pos - 5); k < Math.min(seq.length, pos + 6); k++) if (k !== pos) near.add(T.a[seq[k]]);
  const sh = shape(plan.arc);
  let best = -1, bs = -Infinity;
  for (const j of plan.pool) {
    if (used.has(j) || exclude.has(j) || titles.has(titleKey[j]) || near.has(T.a[j]) || (plan.banned && plan.banned.has(T.a[j]))) continue;
    const v = plan.pv[j];
    let s = 0; if (prev >= 0) s += logit(prev, j); if (next >= 0) s += logit(j, next);
    s -= 4 * Math.abs(T.e[j] - clamp((D.vibes[v].energy_med || .6) + plan.amp * interp(sh, p), .22, .97));
    if (plan.tw) s += 0.6 * plan.tw[j]; if (plan.favor && plan.favor[j] !== undefined) s += plan.favor[j]; s += (plan.fam - 0.5) * 2.2 * (T.p[j] / 100);
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
/* ---- no key, no sign-in: Apple's public lookup gives artwork and a 30-second preview ---- */
const LOOKUP_CACHE = lsGet('selector.lookup.v1', {});
let lookupLast = 0, lookupGap = 1300, lookupSeq = 0;
function jsonp(url) {
  return new Promise((resolve, reject) => {
    const cb = '__selcb' + (++lookupSeq), s = document.createElement('script');
    const done = (fn, v) => { clearTimeout(timer); delete window[cb]; s.remove(); fn(v); };
    const timer = setTimeout(() => done(reject, new Error('timeout')), 12000);
    window[cb] = data => done(resolve, data);
    s.onerror = () => done(reject, new Error('blocked'));
    s.src = url + '&callback=' + cb; document.head.appendChild(s);
  });
}
async function findOnLookup(j, clean) {
  const key = (clean ? 'c:' : '') + T.id[j];
  if (key in LOOKUP_CACHE) return LOOKUP_CACHE[key];
  const want = normT(T.n[j]), arts = T.ar[j].split(', ').map(normA).filter(Boolean);
  const term = `${searchTitle(T.n[j])} ${T.ar[j].split(', ')[0]}`;
  const wait = lookupLast + lookupGap - Date.now(); lookupLast = Math.max(Date.now(), lookupLast + lookupGap);
  if (wait > 0) await new Promise(r => setTimeout(r, wait));
  let data;
  try { data = await jsonp(`https://itunes.apple.com/search?term=${encodeURIComponent(term)}&entity=song&limit=8`); }
  catch (e) { lookupGap = Math.min(lookupGap + 1000, 4000); return undefined; }
  let best = null, bs = 0;
  for (const s of (data && data.results) || []) {
    if (!s.previewUrl || !s.trackName) continue; if (clean && s.trackExplicitness === 'explicit') continue;
    const tt = normT(s.trackName); const ts = tt === want ? 1 : ((tt.includes(want) || want.includes(tt)) && Math.min(tt.length, want.length) >= 4 ? 0.8 : 0);
    const an = normA(s.artistName || ''); const as = arts.some(x => an.includes(x) || x.includes(an)) ? 1 : 0;
    const dd = Math.abs((s.trackTimeMillis || 0) / 1000 - T.dur[j]); const ds = dd <= 4 ? 1 : dd <= 15 ? 0.6 : dd <= 40 ? 0.2 : 0;
    const sc = ts * 0.55 + as * 0.35 + ds * 0.10; if (sc > bs) { bs = sc; best = s; }
  }
  const hit = best && bs >= 0.72 ? { id: 'l' + best.trackId, url: best.trackViewUrl || '', art: (best.artworkUrl100 || '').replace('100x100', '600x600'), bg: '', text: '', preview: best.previewUrl, dur: (best.trackTimeMillis || 0) / 1000, explicit: best.trackExplicitness === 'explicit', name: best.trackName, artist: best.artistName, lookup: true } : null;
  LOOKUP_CACHE[key] = hit; lsSet('selector.lookup.v1', LOOKUP_CACHE);
  return hit;
}
/* fills the night in the background, what plays soonest first; positions never shift */
async function resolveNightLookup(night) {
  if (night.resolving) return;
  night.resolving = true; night.resolveNote = '';
  const plan = night.plan; let fails = 0;
  const next = () => { const n = plan.seq.length, start = Math.max(0, Player.mode !== 'none' ? Player.idx : (night.priority || 0)); for (let o = 0; o < n; o++) { const k = (start + o) % n; if (night.am[k] === undefined) return k; } return -1; };
  while (NIGHT === night && fails < 3) {
    const k = next(); if (k < 0) break;
    const j = plan.seq[k]; let hit = await findOnLookup(j, plan.clean);
    if (NIGHT !== night || plan.seq[k] !== j) continue;
    if (hit === undefined) { fails++; continue; }
    fails = 0;
    if (!hit) { const alt = alternative(plan, k, new Set(plan.seq)); if (alt >= 0) { const h2 = await findOnLookup(alt, plan.clean); if (NIGHT !== night || plan.seq[k] !== j) continue; if (h2) { plan.seq[k] = alt; night.replaced.add(k); hit = h2; } } }
    night.am[k] = hit || null;
    const found = night.am.filter(m => m !== undefined).length;
    if (current === 'plan') renderPlanStatus(found < plan.seq.length ? `Finding your songs… ${found} of ${plan.seq.length}` : `All ${plan.seq.length} songs ready.`);
    if (found % 4 === 0 || found === plan.seq.length || k === (night.priority || 0)) renderCurrentScreen();
  }
  night.resolving = false;
  if (NIGHT !== night) return;
  night.lookupFailed = fails >= 3;
  night.resolved = !night.lookupFailed && night.am.every(m => m !== undefined);
  night.resolveNote = night.lookupFailed ? "Can't reach the song lookup right now. Check your connection." : '';
  renderCurrentScreen();
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

/* ---------------- the mix: beatmatching, bass swaps, tempo rides, echo-outs ----------------
   Previews are plain audio, so they can be mixed the way a DJ mixes: find each song's beat grid,
   bring the next one in at the same tempo and on the beat with its bass cut, swap the bass
   mid-phrase, and let the tempo settle. When two songs are too far apart to beatmatch, ride the
   tempo toward the next one and cut on the beat with an echo, or filter out and drop.          */
function analyzeBeats(buf, hint) {
  const sr = buf.sampleRate, hop = Math.round(sr * 0.01), hopSec = hop / sr, frames = Math.floor(buf.length / hop);
  const c0 = buf.getChannelData(0), c1 = buf.numberOfChannels > 1 ? buf.getChannelData(1) : null;
  const full = new Float32Array(frames), low = new Float32Array(frames), a = Math.exp(-2 * Math.PI * 150 / sr); let lp = 0;
  for (let f = 0, i = 0; f < frames; f++) { let e = 0, el = 0; for (let h = 0; h < hop; h++, i++) { const x = c1 ? (c0[i] + c1[i]) * 0.5 : c0[i]; lp = (1 - a) * x + a * lp; e += x * x; el += lp * lp; } full[f] = Math.log1p(2000 * e / hop); low[f] = Math.log1p(8000 * el / hop); }
  const onset = new Float32Array(frames); let mean = 0;
  for (let f = 1; f < frames; f++) { const v = 2 * Math.max(0, low[f] - low[f - 1]) + Math.max(0, full[f] - full[f - 1]); onset[f] = v; mean += v; }
  mean = mean / Math.max(1, frames) || 1e-9;
  const flat = mean < 0.004;                                   // no hits to speak of (a drone, silence): there is no grid to find
  const at = x => { const i = Math.round(x); return i >= 1 && i < frames - 1 ? Math.max(onset[i], 0.6 * onset[i - 1], 0.6 * onset[i + 1]) : 0; };
  const score = bpm => { const per = 60 / bpm / hopSec; let best = -1, bph = 0; for (let ph = 0; ph < per; ph++) { let s = 0, n = 0; for (let x = ph; x < frames; x += per) { s += at(x); n++; } s /= Math.max(1, n); if (s > best) { best = s; bph = ph; } } return { s: best / mean, ph: bph, per }; };
  const search = (lo, hi, step) => { let b = null; for (let bpm = lo; bpm <= hi; bpm += step) { const r = score(bpm); if (!b || r.s > b.s) b = { bpm, ...r }; } return b; };
  let best = search(hint * 0.92, hint * 1.08, 0.05);
  // the catalog tempo is usually right; when the audio clearly says otherwise, believe the audio
  const wide = search(84, 176, 0.25); if (wide.s > Math.max(1.8, best.s * 1.5)) best = search(wide.bpm - 0.5, wide.bpm + 0.5, 0.05);
  // refine the phase between frames, weighting by onset strength
  let num = 0, den = 0; for (let x = best.ph; x < frames; x += best.per) { const i = Math.round(x); if (i < 1 || i >= frames - 1) continue; const w0 = onset[i - 1], w1 = onset[i], w2 = onset[i + 1], w = w0 + w1 + w2; if (w > 0) { num += (w2 - w0) / w * w1; den += w1; } }
  const first = Math.max(0, (best.ph + (den ? num / den : 0)) * hopSec);
  return { bpm: best.bpm, first, period: 60 / best.bpm, conf: flat ? 0 : best.s };
}
const Mix = {
  ctx: null, out: null, delay: null, cur: null, inc: null, plan: null, timer: null, cache: new Map(), label: '', log: [], fails: 0,
  init() {
    if (this.ctx) return true;
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return false;
    const c = this.ctx = new AC();
    this.out = c.createDynamicsCompressor(); this.out.threshold.value = -6; this.out.ratio.value = 6; this.out.connect(c.destination);
    this.delay = c.createDelay(2); const fb = c.createGain(); fb.gain.value = 0.5; const wet = c.createGain(); wet.gain.value = 0.7;
    this.delay.connect(fb); fb.connect(this.delay); this.delay.connect(wet); wet.connect(this.out);
    return true;
  },
  unlock() { if (this.init() && this.ctx.state === 'suspended') this.ctx.resume().catch(() => {}); },
  /* fetch + decode + find the beat grid; resolves null when the audio can't be read (then the plain player takes over) */
  load(k) {
    const m = Player.meta(k); if (!m || !m.preview || !NIGHT) return Promise.resolve(null);
    if (this.cache.has(m.preview)) return this.cache.get(m.preview).promise;
    const hint = T.bpm[NIGHT.plan.seq[k]], rec = { entry: null };
    rec.promise = (async () => {
      try {
        const res = await fetch(m.preview, { mode: 'cors' }); if (!res.ok) throw new Error(res.status);
        const ab = await res.arrayBuffer();
        const buf = await new Promise((ok, no) => this.ctx.decodeAudioData(ab, ok, no));
        rec.entry = { buf, ...analyzeBeats(buf, hint) }; return rec.entry;
      } catch (e) { rec.failed = true; return null; }
    })();
    this.cache.set(m.preview, rec);
    if (this.cache.size > 5) for (const key of this.cache.keys()) { if (this.cache.size <= 5) break; const cur = Player.meta(Player.idx), nx = Player.meta(Player.idx + 1); if (key !== m.preview && key !== (cur && cur.preview) && key !== (nx && nx.preview)) this.cache.delete(key); }
    return rec.promise;
  },
  loaded(k) { const m = Player.meta(k), r = m && m.preview ? this.cache.get(m.preview) : null; return r ? r.entry : null; },
  deck(entry, k) {
    const c = this.ctx, src = c.createBufferSource(); src.buffer = entry.buf;
    const low = c.createBiquadFilter(); low.type = 'lowshelf'; low.frequency.value = 180;
    const hp = c.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 20; hp.Q.value = 0.9;
    const gain = c.createGain(), send = c.createGain(); send.gain.value = 0;
    src.connect(low); low.connect(hp); hp.connect(gain); gain.connect(this.out); hp.connect(send); send.connect(this.delay);
    return { entry, k, src, low, hp, gain, send, pos: 0, last: 0, started: false };
  },
  kill(d, when) { if (!d) return; try { d.src.stop(when || 0); } catch (e) {} const off = () => { try { d.gain.disconnect(); d.send.disconnect(); } catch (e) {} }; if (when) setTimeout(off, Math.max(0, (when - this.ctx.currentTime) * 1000) + 3000); else off(); },
  /* can this night be mixed? true once the song at k has been fetched and analysed */
  async ready(k) { if (!this.init()) return false; const e = await Promise.race([this.load(k), new Promise(r => setTimeout(() => r(null), 9000))]); return !!e; },
  async playFrom(k) {
    this.cancel(); this.kill(this.cur); this.cur = null;
    // the lookup may still be finding this one: give it a moment
    for (let w = 0; w < 50 && NIGHT && Player.meta(k) === undefined && Player.mode === 'mix' && Player.idx === k; w++) await new Promise(r => setTimeout(r, 120));
    const known = NIGHT && Player.meta(k);
    const e = await this.load(k); if (Player.mode !== 'mix' || Player.idx !== k) return;
    if (!e) {
      if (known && known.preview && ++this.fails >= 2) { Player.mode = 'preview'; Player.ensureAudio(); Player.playPreview(k); renderNowPlaying(); return; }   // the audio can't be read here: plain player
      Player.advance(); return;
    }
    this.fails = 0;
    const d = this.deck(e, k), t = this.ctx.currentTime + 0.06; d.src.start(t, 0); d.t0 = t; d.pos = 0; d.last = t; this.cur = d; this.label = '';
    Player.dur = e.buf.duration; Player.elapsed = 0; Player.playing = this.ctx.state === 'running';
    this.load(k + 1);
    clearInterval(this.timer); this.timer = setInterval(() => this.tick(), 80);
  },
  rate(d) { return d.src.playbackRate.value || 1; },
  tick() {
    const d = this.cur; if (!d || Player.mode !== 'mix' || !NIGHT) return;
    const now = this.ctx.currentTime;
    for (const x of [d, this.inc]) if (x) { if (now > x.t0) x.pos += (now - Math.max(x.last, x.t0)) * this.rate(x); x.last = now; }
    if (this.plan && now >= this.plan.swapAt) { const p = this.plan, old = d; this.cur = this.inc; this.inc = null; this.plan = null; this.kill(old, now + 0.2); Player.fading = false; this.label = ''; Player.dur = this.cur.entry.buf.duration; Player.elapsed = this.cur.pos; Player.onTrack(p.k); this.load(p.k + 1); return; }
    Player.playing = this.ctx.state === 'running'; Player.elapsed = d.pos; Player.dur = d.entry.buf.duration;
    Player.fading = !!(this.plan && now >= this.plan.tS);
    const remaining = (d.entry.buf.duration - d.pos) / this.rate(d);
    if (!this.plan) {
      const k = d.k + 1;
      if (k < NIGHT.plan.seq.length && Player.meta(k) === undefined) { /* still being looked up */ }
      else if (k < NIGHT.plan.seq.length) this.load(k);
      const e = k < NIGHT.plan.seq.length ? this.loaded(k) : null;
      if (e && remaining <= 16 * d.entry.period / this.rate(d) + 1.4) this.schedule(e, k, remaining);
      else if (remaining <= 0.06) { clearInterval(this.timer); Player.advance(); return; }
    }
    renderProgress();
  },
  /* decide how to get from the song that's on to the next one, and schedule it sample-accurately */
  schedule(e, k, remaining) {
    const c = this.ctx, now = c.currentTime, o = this.cur, rO = this.rate(o), oe = o.entry;
    const beatO = oe.period / rO, outBpm = oe.bpm * rO;
    const beatAt = n => now + (oe.first + n * oe.period - o.pos) / rO;                 // when the outgoing song's nth beat sounds
    const nFrom = t => Math.ceil(((t - now) * rO + o.pos - oe.first) / oe.period);
    const end = now + remaining - 0.12;
    let rI = outBpm / e.bpm; for (const f of [0.5, 2]) if (Math.abs(rI * f - 1) < Math.abs(rI - 1)) rI *= f;
    const gap = Math.abs(rI - 1) * 100, sure = oe.conf >= 2.2 && e.conf >= 2.2;
    const inc = this.deck(e, k); let plan = null;
    // a blend of about eight seconds: 16 beats at club tempo, 8 when the song is slow or there's little of it left
    for (const beats of (sure && gap <= 6.5 ? (16 * beatO <= 8.5 ? [16, 8, 4] : [8, 4]) : [])) {
      // the last beat of the outgoing song that still leaves room for the whole blend
      const n0 = Math.floor(((end - beats * beatO - now) * rO + o.pos - oe.first) / oe.period), tS = beatAt(n0), tE = tS + beats * beatO, tSwap = tS + (beats / 2) * beatO;
      if (tS < now + 0.2) continue;
      // beatmatched blend: same tempo, on the beat, bass cut; swap the bass half way; let the tempo settle afterwards
      inc.src.playbackRate.setValueAtTime(rI, now); inc.src.start(tS, e.first); inc.t0 = tS; inc.pos = e.first;
      inc.gain.gain.setValueAtTime(0, now); inc.gain.gain.setValueAtTime(0, tS); inc.gain.gain.linearRampToValueAtTime(1, tS + Math.min(4, beats / 4) * beatO);
      inc.low.gain.setValueAtTime(-30, now); inc.low.gain.setValueAtTime(-30, tSwap - 0.02); inc.low.gain.linearRampToValueAtTime(0, tSwap + 0.03);
      o.low.gain.setValueAtTime(0, tSwap - 0.02); o.low.gain.linearRampToValueAtTime(-30, tSwap + 0.03);
      o.gain.gain.setValueAtTime(1, tSwap); o.gain.gain.linearRampToValueAtTime(0, tE);
      o.hp.frequency.setValueAtTime(20, tSwap); o.hp.frequency.exponentialRampToValueAtTime(900, tE);
      if (Math.abs(rI - 1) > 0.004) { inc.src.playbackRate.setValueAtTime(rI, tE); inc.src.playbackRate.linearRampToValueAtTime(1, tE + 10); }
      let err = 0; for (let b = 0; b < beats; b++) err = Math.max(err, Math.abs((tS + b * (e.period / rI)) - beatAt(n0 + b)));
      plan = { k, type: 'blend', tS, swapAt: tE, label: `Beatmatched at ${Math.round(outBpm)} BPM, swapping the bass`, beats, rI, err };
      break;
    }
    if (!plan) {
      const tCut = Math.max(now + 0.3, beatAt(nFrom(end - 0.35))), ride = sure && gap > 1.5 && gap <= 14, echo = sure && gap <= 1.5;
      if (ride) { const target = rO * clamp(1 / rI, 0.92, 1.08), t0 = Math.max(now + 0.05, tCut - 6); o.src.playbackRate.setValueAtTime(rO, t0); o.src.playbackRate.linearRampToValueAtTime(target, tCut); }
      else if (!echo) { const t0 = Math.max(now + 0.05, tCut - 4); o.hp.frequency.setValueAtTime(20, t0); o.hp.frequency.exponentialRampToValueAtTime(1800, tCut); }
      // cut on the beat: the outgoing song leaves as an echo, the new one lands on its first beat at full weight
      this.delay.delayTime.setValueAtTime(clamp(beatO * 0.75, 0.15, 1.2), now);
      o.send.gain.setValueAtTime(0, Math.max(now, tCut - 2 * beatO)); o.send.gain.linearRampToValueAtTime(0.9, tCut - 0.02); o.send.gain.linearRampToValueAtTime(0, tCut + 0.08);
      o.gain.gain.setValueAtTime(1, tCut - 0.03); o.gain.gain.linearRampToValueAtTime(0, tCut + 0.02);
      inc.src.start(tCut, e.first); inc.t0 = tCut; inc.pos = e.first; inc.gain.gain.setValueAtTime(1, now);
      plan = { k, type: ride ? 'ride' : echo ? 'echo' : 'drop', tS: Math.max(now, tCut - (ride ? 6 : echo ? 1 : 4)), swapAt: tCut + 0.04, label: echo ? 'Echo out, in on the beat' : ride ? (e.bpm > outBpm ? `Speeding up to ${Math.round(e.bpm)} BPM, then an echo out` : `Slowing down to ${Math.round(e.bpm)} BPM, then an echo out`) : 'Filtering out, then the drop', rI, gap };
    }
    inc.last = now; this.inc = inc; this.plan = plan; this.label = plan.label;
    this.log.push({ k, type: plan.type, from: +outBpm.toFixed(1), to: +e.bpm.toFixed(1), rate: +(plan.rI || 1).toFixed(4), beats: plan.beats || 0, alignMs: plan.err !== undefined ? +(plan.err * 1000).toFixed(1) : null, conf: [+oe.conf.toFixed(1), +e.conf.toFixed(1)] });
  },
  /* the plan changed, or the listener skipped: drop anything scheduled but not yet audible */
  cancel() {
    if (!this.plan && !this.inc) return;
    const now = this.ctx.currentTime, o = this.cur;
    this.kill(this.inc); this.inc = null; this.plan = null; this.label = ''; Player.fading = false;
    if (o) for (const p of [o.gain.gain, o.low.gain, o.hp.frequency, o.send.gain, o.src.playbackRate]) { const v = p.value; p.cancelScheduledValues(now); p.setValueAtTime(v, now); }
    if (o) { o.gain.gain.linearRampToValueAtTime(1, now + 0.2); o.low.gain.linearRampToValueAtTime(0, now + 0.2); o.hp.frequency.linearRampToValueAtTime(20, now + 0.2); o.send.gain.setValueAtTime(0, now); }
  },
  stop() { clearInterval(this.timer); if (!this.ctx) return; this.kill(this.inc); this.kill(this.cur); this.inc = this.cur = this.plan = null; this.label = ''; },
  now() { const d = this.cur; return d ? { bpm: d.entry.bpm * this.rate(d), conf: d.entry.conf } : null; },
};

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
    } else if (mode === 'mix') {
      this.dur = 30; this.elapsed = 0; this.playing = true; Mix.playFrom(k);
    } else if (mode === 'preview') {
      this.ensureAudio(); this.playPreview(k);
    } else { this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; this.playing = true; this.startDemoClock(); }
    this.onTrack(k);
  },
  /* how far the night is committed: the song that's on, or the next one once it has started blending in */
  committed() { return this.mode === 'none' ? -1 : this.idx + (this.fading ? 1 : 0); },
  unlock() {
    Mix.unlock();
    this.ensureAudio();
    const silent = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
    for (const el of [this.a, this.b]) { try { el.src = silent; const p = el.play(); if (p && p.then) p.then(() => el.pause()).catch(() => {}); } catch (e) {} }
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
  advance() { if (!NIGHT) return; if (this.idx + 1 >= NIGHT.plan.seq.length) { this.finish(); return; } const k = this.idx + 1; if (this.mode === 'mix') { this.idx = k; Mix.playFrom(k); this.onTrack(k); } else if (this.mode === 'preview') { this.idx = k; this.playPreview(k); this.onTrack(k); } else if (this.mode === 'demo') { this.idx = k; this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; this.onTrack(k); } },
  onTrack(k) {
    this.idx = k; NIGHT.played.add(k);
    const j = NIGHT.plan.seq[k];
    this.loved = NIGHT.loved.has(j);
    if (!NIGHT.firstPlay) NIGHT.firstPlay = Date.now();
    // keep the printed times honest after skips and jumps: this song started now
    NIGHT.startedAt = Date.now() - (startTimes(NIGHT.plan)[k] + (this.mode === 'full' ? this.elapsed : 0)) * 1000;
    if (NIGHT.undo && k > NIGHT.undo.at + 1) NIGHT.undo = null;
    renderNowPlaying(); renderMini(); if (current === 'songs') renderSongs();
  },
  async toggle() {
    if (this.mode === 'full') { if (this.playing) AM.music.pause(); else { try { await AM.music.play(); } catch (e) {} } }
    else if (this.mode === 'mix') { if (Mix.ctx.state === 'running') await Mix.ctx.suspend(); else await Mix.ctx.resume(); this.playing = Mix.ctx.state === 'running'; renderTransport(); }
    else if (this.mode === 'preview') { if (this.playing) this.a.pause(); else this.a.play().catch(() => {}); }
    else { this.playing = !this.playing; renderTransport(); }
  },
  async next() { if (this.mode === 'full') { try { await AM.music.skipToNextItem(); } catch (e) {} } else if (this.mode === 'mix') { if (Mix.ctx.state !== 'running') await Mix.ctx.resume(); this.fading = false; this.advance(); } else { this.fading = false; if (this.b) { this.b.pause(); } this.advance(); } },
  async prev() { if (this.mode === 'mix') { const k = this.elapsed > 5 || this.idx === 0 ? this.idx : this.idx - 1; this.idx = k; this.fading = false; Mix.playFrom(k); this.onTrack(k); return; } if (this.elapsed > 5) { this.seek(0); return; } if (this.mode === 'full') { try { await AM.music.skipToPreviousItem(); } catch (e) {} } else if (this.idx > 0) { const k = this.idx - 1; if (this.mode === 'preview') { this.fading = false; this.playPreview(k); } else { this.dur = T.dur[NIGHT.plan.seq[k]]; this.elapsed = 0; } this.onTrack(k); } },
  seek(t) { if (this.mode === 'full') AM.music.seekToTime(t); else if (this.mode === 'preview') this.a.currentTime = t; else this.elapsed = t; },
  /* the plan changed after the current song: rebuild what's queued */
  async requeue() {
    if (this.mode === 'full') { const k = this.idx, t = AM.music.currentPlaybackTime || 0, wasPlaying = this.playing; const ids = NIGHT.am.slice(k).map(m => m && m.id).filter(Boolean); try { await AM.music.setQueue({ songs: ids }); await AM.music.seekToTime(t); if (wasPlaying) await AM.music.play(); } catch (e) {} }
    else if (this.mode === 'mix') { if (Mix.plan && Mix.ctx.currentTime < Mix.plan.tS) Mix.cancel(); Mix.load(this.committed() + 1); }
    else if (this.mode === 'preview') { const nx = this.meta(this.idx + 1); if (nx && nx.preview && this.b) { this.b.src = nx.preview; this.b.load(); } }
    renderNowPlaying();
  },
  stop(silent) {
    clearInterval(this.timer); this.fading = false; Mix.stop();
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
  if (Player.mode !== 'none') { toast('A night is already playing. End it first from the playing screen.'); return false; }
  const plan = newPlan();
  if (!plan) { toast('Pick at least one sound'); return false; }
  NIGHT = makeNight(plan); phaseFilter = 'all';
  Player.stop(); applyAccent();
  if (hasApple() && AM.ready) resolveNight(NIGHT); else if (!hasApple() && !DEMO_ONLY) resolveNightLookup(NIGHT);
  return true;
}
function clockAt(k) { const base = NIGHT.startedAt || roundedNow(); return new Date(base + startTimes(NIGHT.plan)[k] * 1000); }
function roundedNow() { const d = new Date(); d.setSeconds(0, 0); d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5); return d.getTime(); }
function endsAt(minutes) { return fmtClock(new Date(roundedNow() + minutes * 60000)); }

function swapAt(k) {
  const plan = NIGHT.plan;
  if (Player.mode !== 'none' && k <= Player.committed()) { toast(k > Player.idx ? "That one's already blending in" : 'That one already played'); return; }
  const tried = NIGHT.swaps?.[k] || new Set([plan.seq[k]]);
  const alt = alternative(plan, k, tried);
  if (alt < 0) { toast('No other song fits this spot'); return; }
  tried.add(alt); NIGHT.swaps = NIGHT.swaps || {}; NIGHT.swaps[k] = tried;
  plan.seq[k] = alt; NIGHT.am[k] = undefined; NIGHT.replaced.delete(k);
  renderCurrentScreen();
  if (hasApple() && AM.ready) findOnApple(alt, plan.clean).then(hit => { if (!NIGHT || NIGHT.plan.seq[k] !== alt) return; NIGHT.am[k] = hit || null; if (!hit) toast("That one isn't on Apple Music. Swap again."); renderCurrentScreen(); if (Player.mode !== 'none' && k > Player.idx) Player.requeue(); });
  if (!hasApple() && !DEMO_ONLY) resolveNightLookup(NIGHT);
  if (Player.mode === 'demo' && k > Player.idx) Player.requeue();
}
function removeAt(k) {
  if (Player.mode !== 'none' && k <= Player.committed()) { toast(k > Player.idx ? "That one's already blending in" : 'That one already played'); return; }
  NIGHT.plan.seq.splice(k, 1); NIGHT.am.splice(k, 1);
  renderCurrentScreen(); if (Player.mode !== 'none') Player.requeue();
}

/* ---------------- understanding requests ---------------- */
const ALIASES = [['bollywood', 'bollywood'], ['hindi', 'bollywood'], ['desi', 'bollywood'], ['filmi', 'bollywood'], ['punjabi', 'punjabi'], ['bhangra', 'punjabi'], ['dhol', 'punjabi'],
  ['telugu', 'southindian'], ['tamil', 'southindian'], ['tollywood', 'southindian'], ['kollywood', 'southindian'], ['south indian', 'southindian'], ['kuthu', 'southindian'], ['malayalam', 'southindian'], ['kannada', 'southindian'],
  ['arabic', 'mideast'], ['persian', 'mideast'], ['turkish', 'mideast'], ['middle east', 'mideast'], ['middle eastern', 'mideast'], ['farsi', 'mideast'], ['khaleeji', 'mideast'], ['iranian', 'mideast'], ['dabke', 'mideast'],
  ['reggaeton', 'reggaeton'], ['regueton', 'reggaeton'], ['perreo', 'reggaeton'], ['dembow', 'reggaeton'], ['latin', 'latin'], ['salsa', 'latin'], ['bachata', 'latin'], ['cumbia', 'latin'], ['merengue', 'latin'], ['spanish', 'latin'],
  ['afrobeats', 'afro'], ['afrobeat', 'afro'], ['afro', 'afro'], ['amapiano', 'afro'], ['naija', 'afro'], ['k pop', 'kpop'], ['kpop', 'kpop'], ['j pop', 'kpop'], ['jpop', 'kpop'], ['korean', 'kpop'],
  ['techno', 'techno'], ['house', 'house'], ['deep house', 'house'], ['tech house', 'house'], ['trance', 'trance'], ['edm', 'edm'], ['big room', 'edm'], ['festival', 'edm'], ['electronic', 'edm'],
  ['drum and bass', 'bass'], ['drum n bass', 'bass'], ['dnb', 'bass'], ['dubstep', 'bass'], ['jungle', 'bass'], ['disco', 'disco'], ['funk', 'disco'], ['funky', 'disco'], ['nu disco', 'disco'],
  ['hip hop', 'hiphop'], ['hiphop', 'hiphop'], ['rap', 'hiphop'], ['r&b', 'hiphop'], ['rnb', 'hiphop'], ['trap', 'hiphop'], ['pop', 'pop'], ['top 40', 'pop'], ['chart', 'pop']].sort((a, b) => b[0].length - a[0].length);
const STOP_TITLES = new Set(['up', 'down', 'more', 'energy', 'play', 'next', 'stop', 'dance', 'party', 'tonight', 'the night', 'slow', 'faster', 'something', 'music', 'song', 'songs', 'love', 'please', 'now', 'one more', 'hello', 'thank you', 'home']);
const COMMON = new Set([...STOP_TITLES, 'less', 'some', 'want', 'this', 'that', 'hear', 'skip', 'slower', 'family', 'everyone', 'chill', 'house', 'latin', 'disco', 'wrap', 'know', 'hits', 'classic', 'classics', 'future', 'blue', 'black', 'white', 'young', 'little', 'after', 'before', 'night', 'hour', 'hours', 'minutes', 'bring', 'anything', 'nothing', 'again', 'there', 'friends', 'people', 'girls', 'boys', 'kids', 'mostly', 'mainly', 'heavy', 'clean', 'explicit', 'wedding', 'birthday', 'sunset', 'dinner', 'rooftop', 'warehouse', 'three', 'seven', 'eight', 'loving', 'lovely', 'happy', 'crazy', 'sweet', 'super', 'royal', 'magic', 'golden', 'silver', 'sound', 'sounds', 'funky', 'electric', 'radio', 'summer', 'winter', 'money', 'queen', 'prince', 'king', 'kings', 'lady', 'mister', 'miss', 'today', 'always', 'never', 'every', 'great', 'good', 'best', ...ALIASES.flatMap(a => a[0].split(' '))]);
const words = s => String(s || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[-'’]/g, '').replace(/[^a-z0-9&]+/g, ' ').trim();
const shortTitle = s => String(s).replace(/\s*[\(\[].*$/, '');
const rx = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const has = (text, pattern) => new RegExp('(^| )(' + pattern + ')( |$)').test(text);
let artistByWords = null, songByWords = null;
function buildLexicon() {
  artistByWords = new Map(); songByWords = new Map();
  const count = new Map(); for (let j = 0; j < N; j++) for (const a of T.ar[j].split(', ')) { const k = normA(a); count.set(k, (count.get(k) || 0) + 1); }
  const first = new Map();
  for (const name of D.artists) {
    const w = words(name); if (w.length >= 4 && !COMMON.has(w)) artistByWords.set(w, name);
    const parts = w.split(' '); if (parts.length >= 2 && parts[0].length >= 5 && !COMMON.has(parts[0]) && (count.get(normA(name)) || 0) >= 4) { if (!first.has(parts[0])) first.set(parts[0], []); first.get(parts[0]).push(name); }
  }
  for (const [f, names] of first) if (names.length === 1 && !artistByWords.has(f)) artistByWords.set(f, names[0]);   // "more Diljit"
  for (let j = 0; j < N; j++) { const w = words(shortTitle(T.n[j])); if (w.length < 3 || STOP_TITLES.has(w)) continue; const old = songByWords.get(w); if (old !== undefined && T.p[old] >= T.p[j]) continue; songByWords.set(w, j); }
}
function vibesIn(text) {
  const found = [];
  for (const [w, v] of ALIASES) { if (!has(text, rx(w)) || found.includes(v)) continue; if (v === 'pop' && found.includes('kpop') && !has(text.replace(/[kj] pop/g, ''), 'pop')) continue; found.push(v); }
  return found;
}
function entitiesIn(text) {
  const w = text.split(' '), artists = [], songs = [];
  for (let i = 0; i < w.length;) {
    let matched = 0;
    for (let len = Math.min(6, w.length - i); len >= 1; len--) {
      const phrase = w.slice(i, i + len).join(' ');
      if (artistByWords.has(phrase)) { const n = artistByWords.get(phrase); if (!artists.includes(n)) artists.push(n); matched = len; break; }
      if (len >= 2 && songByWords.has(phrase)) { const j = songByWords.get(phrase); if (!songs.includes(j)) songs.push(j); matched = len; break; }
    }
    i += Math.max(1, matched);
  }
  return { artists, songs };
}
/* what the listener asked for, as a list of intents: {t:'energy',up} {t:'familiar'} {t:'surprise'} {t:'more',v} {t:'less',v} {t:'wrap',m} {t:'song',j} {t:'artist',name} {t:'noartist',name} */
const intentKey = i => i.t + '|' + (i.v ?? i.m ?? i.j ?? i.name ?? (i.up === undefined ? '' : i.up ? 'up' : 'down'));
function parseRequest(raw) {
  const text = words(raw); if (!text) return [];
  const out = [], add = i => { if (!out.some(o => intentKey(o) === intentKey(i))) out.push(i); };
  // "no more punjabi, more Arijit": each comma or "and" starts a new request
  const clauses = String(raw).split(/[,;]+|\.\s/).flatMap(part => words(part).replace(/drum and bass/g, 'dnb').replace(/sing along/g, 'singalong').split(/ and | then | but /)).map(s => s.trim()).filter(Boolean);
  for (const c of clauses) {
    const negative = has(c, 'no more|no|less|fewer|enough|skip|stop|without|not so much|tired of|sick of|done with|drop the|lose the|cut the');
    if (has(c, 'wrap|wrap up|wind down|last song|last few|end it|end the night|finish|close out|closing|bring it home|call it') || /\d+ ?(min|mins|minutes|minute) (left|more)/.test(c)) {
      let m = 20; const d = c.match(/\d+/); if (d) m = clamp(+d[0], 5, 120); else if (has(c, 'half an hour|half hour')) m = 30; else if (has(c, 'an hour|one hour')) m = 60; else if (has(c, 'last song')) m = 5;
      add({ t: 'wrap', m }); continue;
    }
    const vs = vibesIn(c), ent = entitiesIn(c);
    for (const v of vs) add(negative ? { t: 'less', v } : { t: 'more', v });
    for (const a of ent.artists) add(negative ? { t: 'noartist', name: a } : { t: 'artist', name: a });
    let askedSong = false;
    if (!negative) {
      const playVerb = has(c, 'play|put on|queue|drop|spin|request|hear');
      for (const j of ent.songs) if (playVerb || words(shortTitle(T.n[j])) === c) { add({ t: 'song', j }); askedSong = true; }   // without "play", a title only counts when it's the whole request
      if (!askedSong && !ent.artists.length) { const m = c.match(/(^| )(play|put on|queue|drop|spin) (the song |some )?([a-z0-9]+)/); if (m && songByWords.has(m[4])) { add({ t: 'song', j: songByWords.get(m[4]) }); askedSong = true; } }
    }
    if (vs.length || ent.artists.length || askedSong) continue;
    if (negative && has(c, 'this|this vibe|this stuff|this one|these')) { add({ t: 'less', v: null }); continue; }
    // the room, described
    if (has(c, 'aunties|aunty|uncles|parents|grandparents|elders|family|everyone|everybody|crowd pleaser|crowd pleasers|singalong|wedding classics')) add({ t: 'familiar' });
    if (has(c, 'dead|boring|bored|asleep|sleepy|sitting|nobody|no one|empty|flat|lame|wake')) { add({ t: 'energy', up: true }); add({ t: 'familiar' }); continue; }
    if (has(c, 'too loud|too much|too fast|too hard|too intense|headache|breather|break|talk|chat|dinner|eating|romantic|slow dance|couples')) { add({ t: 'energy', up: false }); continue; }
    const down = has(c, 'slow|slower|chill|chiller|mellow|calm|calmer|softer|quieter|lower|down|easy|ease|relax|cool it|cool down|tone it');
    const up = has(c, 'energy|hype|turn up|turn it up|louder|faster|harder|up|bang|bangers|banger|lift|dance|dancing|peak|party|pump|fire|lit|go off|wild|crazy');
    if (down && !(up && !negative && !has(c, 'down|slow|slower|lower|less'))) add({ t: 'energy', up: false }); else if (up) add({ t: 'energy', up: !negative });
    if (has(c, 'know|familiar|hits|hit|classic|classics|popular|famous|throwback|throwbacks|old school|favorites|favourites|anthems')) add(negative ? { t: 'surprise' } : { t: 'familiar' });
    else if (has(c, 'surprise|deep cut|deep cuts|new|discover|underground|different|fresh|unexpected|rare|obscure|weird')) add({ t: 'surprise' });
  }
  return out;
}
function minutesUntil(phrase) {
  let hour, minute = 0;
  if (phrase.includes('midnight')) hour = 0;
  else { const nums = (phrase.match(/\d+/g) || []).map(Number); if (!nums.length || nums[0] > 24) return null; hour = nums[0]; if (nums.length > 1) minute = Math.min(nums[1], 59);
    if (phrase.includes('pm') && hour < 12) hour += 12; else if (phrase.includes('am') && hour === 12) hour = 0; else if (!/am|pm/.test(phrase) && hour > 6 && hour < 12) hour += 12; }
  const now = new Date(), target = new Date(now); target.setHours(hour % 24, minute, 0, 0); if (target <= now) target.setDate(target.getDate() + 1);
  const mins = Math.floor((target - now) / 60000); return mins > 0 && mins <= 720 ? mins : null;
}
/* "Sangeet, mostly Punjabi, three hours" -> settings */
function parseBrief(raw) {
  const text = words(raw), r = { occasion: null, weights: {}, minutes: null, clean: null, fam: null, arc: null, artists: [] }; if (!text) return r;
  const occs = [['sangeet|mehndi|mehendi|haldi|baraat|shaadi|wedding|reception|garba|diwali|eid|navratri', 'sangeet'], ['warehouse|rave|underground', 'techno'], ['rooftop|pool party|beach', 'reggaeton'], ['sunset|golden hour|sundowner', 'sunset'], ['dinner|brunch|cocktail|cocktails', 'dinner'], ['house party|birthday|bday|pregame|pre game|afterparty|after party|kickback|game night|friends over|housewarming|party', 'party']];
  for (const [pat, key] of occs) if (has(text, pat)) { r.occasion = key; break; }
  if (has(text, 'workout|gym|run|running|spin class')) r.arc = 'peak';
  let m;
  if ((m = text.match(/(\d+) ?(h|hr|hrs|hour|hours)( (\d+))?( |$)/))) r.minutes = +m[1] * 60 + (m[4] ? +m[4] : 0);
  else if ((m = text.match(/(\d+) ?(m|min|mins|minute|minutes)( |$)/))) r.minutes = +m[1];
  else if (has(text, 'half an hour|half hour')) r.minutes = 30; else if (has(text, 'an hour|one hour')) r.minutes = 60; else if (has(text, 'couple of hours|couple hours|two hours')) r.minutes = 120; else if (has(text, 'three hours')) r.minutes = 180; else if (has(text, 'four hours')) r.minutes = 240; else if (has(text, 'all night|whole night')) r.minutes = 240;
  if ((m = text.match(/(till|until|til|to|ends at|end at) (midnight|\d{1,2}( ?\d\d)? ?(am|pm)?)/))) { const mins = minutesUntil(m[0]); if (mins) r.minutes = mins; }
  if (r.minutes) r.minutes = clamp(Math.ceil(r.minutes / 15) * 15, 30, 360);
  const strong = 'mostly|mainly|lots of|heavy on|heavy|all|only|pure|strictly|big on|tons of|primarily|focus on', light = 'some|a little|a bit of|bit of|little|touch of|sprinkle of|sprinkle|few|occasional|hint of|dash of|maybe';
  const order = [];
  for (const [w0, v] of ALIASES) {
    const w = rx(w0); if (!has(text, w) || r.weights[v] !== undefined) continue;
    if (v === 'house' && has(text, 'house party') && !has(text.replace(/house party/g, ''), 'house')) continue;
    if (v === 'pop' && has(text, 'k pop|j pop') && !has(text.replace(/[kj] pop/g, ''), 'pop')) continue;
    if (w0 === 'festival') continue;
    if (has(text, '(no|not|without|skip|except) (any )?' + w)) continue;
    r.weights[v] = has(text, '(' + strong + ') (the )?' + w) ? 3 : has(text, '(' + light + ') (the )?' + w) ? 1 : 2;
    order.push([v, text.search(new RegExp('(^| )' + w + '( |$)'))]);
  }
  if (order.length && !Object.values(r.weights).includes(3)) { order.sort((a, b) => a[1] - b[1]); r.weights[order[0][0]] = 3; }   // with no emphasis given, the first sound named leads
  for (const k of Object.keys(r.weights)) if (r.weights[k] === 2) r.weights[k] = 1;
  if (has(text, 'family|kids|children|parents|aunties|uncles|grandparents|clean|pg|office|work party|colleagues')) r.clean = true;
  if (has(text, 'explicit|uncensored|adults only|no kids|dirty')) r.clean = false;
  if (has(text, 'hits|know|singalong|sing along|classics|classic|crowd pleasers|familiar|popular|throwbacks|anthems|aunties|everyone')) r.fam = 0.85;
  if (has(text, 'deep cuts|underground|surprise|new stuff|discover|obscure|different')) r.fam = 0.4;
  r.artists = entitiesIn(text).artists;
  r.understood = !!(r.occasion || Object.keys(r.weights).length || r.minutes || r.clean !== null || r.fam !== null || r.artists.length);
  return r;
}
function planFromText(text) {
  const r = parseBrief(text);
  if (!r.understood) { toast('Tell me the occasion, the sounds, or how long. For example: house party, hip-hop and afrobeats, two hours.'); return false; }
  if (Player.mode !== 'none') { toast('A night is playing. End it first, or tell your DJ what to change.'); return false; }
  const o = OCCASIONS.find(x => x.key === r.occasion), custom = Object.keys(r.weights).length > 0;
  if (o) { if (!custom) S.weights = { ...o.weights }; S.arc = o.arc; S.clean = o.clean; S.fam = o.fam; S.minutes = o.minutes; }
  if (custom) S.weights = r.weights;
  S.occasion = custom ? ((OCCASIONS.find(x => sameWeights(S.weights, x.weights)) || {}).key || null) : r.occasion || S.occasion;
  briefTitle = custom && o ? o.label : null;
  if (r.minutes) S.minutes = r.minutes; if (r.clean !== null) S.clean = r.clean; if (r.fam !== null) S.fam = r.fam; if (r.arc) S.arc = r.arc;
  if (r.artists.length) { const t = tasteFrom(r.artists, `You asked for ${joinNames(r.artists)}`); if (t) { TASTE = t; lsSet('selector.taste', TASTE); S.useTaste = true; } }
  saveSettings();
  if (!planNight()) return false;
  stack.length = 0; go('plan'); return true;
}

/* ---------------- live steering: re-plan everything after the current song ---------------- */
function tracksBy(name) { return byArtist.get(normA(name)) || []; }
function steer(intents) {
  if (!NIGHT || !intents.length) return '';
  const plan = NIGHT.plan, cur = Player.committed();
  const keep = Math.min(cur + 1, plan.seq.length);                 // songs that stay: played + the one playing
  const prefix = plan.seq.slice(0, keep);
  const st = startTimes(plan); let elapsed = keep < plan.seq.length ? st[keep] : totalSeconds(plan);
  const undo = { seq: plan.seq.slice(), am: NIGHT.am.slice(), at: cur, opts: { exclude: plan.exclude, boost: plan.boost, energyOff: plan.energyOff, fam: plan.fam, durS: plan.durS, weights: plan.weights, favor: plan.favor, banned: plan.banned, pv: plan.pv, pool: plan.pool } };
  let durS = plan.durS, fam = plan.fam, energyOff = plan.energyOff; const boost = { ...(plan.boost || {}) }, exclude = new Set(plan.exclude || []), weights = { ...plan.weights }, favor = { ...(plan.favor || {}) }, banned = new Set(plan.banned || []);
  const forced = [], replies = [], applied = [];
  const curVibe = cur >= 0 && cur < plan.seq.length ? VK[plan.pv[plan.seq[cur]]] : null;
  const tailStart = durS > 0 ? Math.min(elapsed / durS, 1) : 0; let lifted = false;
  for (const it of intents) {
    if (it.t === 'energy') { const d = it.up ? 1 : -1; energyOff = p => d * (p < tailStart + 0.18 ? 0.12 : 0.05); lifted = it.up; replies.push(it.up ? "I'll lift the energy over the next two songs and keep it up." : 'Easing it down after this one, and holding it mellow for a stretch.'); }
    else if (it.t === 'familiar') { fam = 0.95; replies.push('Switching to the songs everyone knows.'); }
    else if (it.t === 'surprise') { fam = 0.35; replies.push('Going deeper: fewer hits, more finds.'); }
    else if (it.t === 'more') { if (!weights[it.v]) weights[it.v] = 1; boost[it.v] = (boost[it.v] || 0) + 0.35; exclude.delete(it.v); replies.push(`More ${vname(it.v)} coming, starting after this one.`); }
    else if (it.t === 'less') { const v = it.v || curVibe; if (!v) continue; const left = Object.keys(weights).filter(k => weights[k] > 0 && !exclude.has(k) && k !== v).sort(); if (!left.length) { replies.push(`${vname(v)} is the only sound tonight, so I'll keep it.`); continue; } if (!weights[v]) { replies.push(`There's no ${vname(v)} in tonight's plan.`); continue; } exclude.add(v); delete boost[v]; replies.push(`No more ${vname(v)} for now. I'll lean on ${joinNames(left.map(vname))}.`); }
    else if (it.t === 'wrap') { durS = elapsed + it.m * 60; const span = Math.max(0.05, 1 - tailStart); energyOff = p => -0.25 * clamp((p - tailStart) / span, 0, 1); replies.push(`${it.m} more minutes, then I'll bring it home.`); }
    else if (it.t === 'song') { const j = it.j, title = shortTitle(T.n[j]); if (plan.clean && T.x[j]) { replies.push(`${title} is explicit, and tonight is family-friendly.`); continue; } if (cur >= 0 && plan.seq[cur] === j) { replies.push(`${title} is playing right now.`); continue; } if (prefix.includes(j)) { replies.push(`${title} already played tonight.`); continue; } forced.push(j); favor[j] = 2.5; replies.push(`${title} by ${T.ar[j].split(', ')[0]} is up next.`); }
    else if (it.t === 'artist') { const tr = tracksBy(it.name).filter(j => !prefix.includes(j) && !(plan.clean && T.x[j])); if (!tr.length) { replies.push(`I've played everything I have by ${it.name}.`); continue; } for (const j of tr) { favor[j] = Math.max(favor[j] || 0, 2.5); banned.delete(T.a[j]); } replies.push(`More ${it.name} on the way.`); }
    else if (it.t === 'noartist') { const key = normA(it.name); for (const j of tracksBy(it.name)) { favor[j] = -8; if (normA(T.ar[j].split(', ')[0]) === key) banned.add(T.a[j]); } replies.push(`No more ${it.name} tonight.`); }
    else continue;
    applied.push(it);
  }
  if (!applied.length) return replies.join(' ');
  for (const j of forced) if (!prefix.includes(j)) { prefix.push(j); elapsed += T.dur[j]; }
  const hasBoost = Object.keys(boost).length > 0;
  const r = buildSet({ weights, durS: Math.max(durS, elapsed + 60), arc: plan.arc, clean: plan.clean, fam, tw: plan.tw, seed: (S.seed = (S.seed * 48271) % 2147483647 || 11), xf: 0, prefix, elapsed, energyOff, boost: hasBoost ? boost : null, exclude: exclude.size ? exclude : null, favor, banned });
  if (!r || (!r.seq.length && !forced.length)) return "I couldn't find enough songs for that. Try another request.";
  NIGHT.undo = undo;
  plan.seq = prefix.concat(r.seq);
  const pv = r.pv; for (const j of plan.seq.slice(0, keep)) if (pv[j] < 0 && plan.pv[j] >= 0) pv[j] = plan.pv[j];   // keep the sound of songs that already played
  Object.assign(plan, { pv, pool: r.pool, weights, fam, energyOff, boost: hasBoost ? boost : null, exclude: exclude.size ? exclude : null, favor, banned, durS });
  NIGHT.am = NIGHT.am.slice(0, keep).concat(new Array(plan.seq.length - keep).fill(undefined));
  NIGHT.replaced = new Set([...NIGHT.replaced].filter(k => k < keep)); NIGHT.swaps = {};
  for (const it of applied) NIGHT.requests.push({ action: intentKey(it), at: Date.now() });
  if (!phases(plan).some(p => p.key === phaseFilter)) phaseFilter = 'all';
  if (lifted && applied.length === 1 && r.seq.length) { let hot = -1, he = -1; for (let i = 0; i < Math.min(4, r.seq.length); i++) if (T.e[r.seq[i]] > he) { he = T.e[r.seq[i]]; hot = i; } if (hot >= 0) { replies.length = 0; replies.push(`I'll lift the energy over the next two songs and bring ${shortTitle(T.n[r.seq[hot]])} forward to ${fmtClock(clockAt(prefix.length + hot))}.`); } }
  if (hasApple() && AM.ready) resolveNight(NIGHT).then(() => Player.requeue()); else { if (!hasApple() && !DEMO_ONLY) resolveNightLookup(NIGHT); Player.requeue(); }
  renderCurrentScreen();
  return replies.join(' ');
}
function undoSteer() {
  if (!NIGHT || !NIGHT.undo) return;
  // only what hasn't played yet goes back; the song that's on stays on
  const u = NIGHT.undo, plan = NIGHT.plan, keep = Math.min(Math.max(Player.committed() + 1, 0), Math.min(u.seq.length, plan.seq.length));
  const played = plan.seq.slice(0, keep), idx = u.seq.map((_, i) => i).slice(keep).filter(i => !played.includes(u.seq[i]));
  const oldPv = plan.pv;
  plan.seq = played.concat(idx.map(i => u.seq[i])); NIGHT.am = NIGHT.am.slice(0, keep).concat(idx.map(i => u.am[i]));
  Object.assign(plan, u.opts); for (const j of played) if (plan.pv[j] < 0 && oldPv[j] >= 0) plan.pv[j] = oldPv[j];
  NIGHT.undo = null; NIGHT.requests.pop(); NIGHT.replaced = new Set([...NIGHT.replaced].filter(k => k < keep));
  if (!hasApple() && !DEMO_ONLY) resolveNightLookup(NIGHT);
  Player.requeue(); renderCurrentScreen();
}
/* loving a song nudges the rest of the night toward that artist */
function toggleLove() {
  if (!NIGHT || Player.idx < 0) return;
  const j = NIGHT.plan.seq[Player.idx], plan = NIGHT.plan, tr = tracksBy(T.ar[j].split(', ')[0]); plan.favor = plan.favor || {};
  if (NIGHT.loved.has(j)) { NIGHT.loved.delete(j); for (const k of tr) if (plan.favor[k] === 0.9) delete plan.favor[k]; }
  else { NIGHT.loved.add(j); for (const k of tr) if (plan.favor[k] === undefined) plan.favor[k] = 0.9; }
  $('#btn-love').classList.toggle('on', NIGHT.loved.has(j)); $('#btn-love').setAttribute('aria-label', NIGHT.loved.has(j) ? 'Loved' : 'Love this');
}
/* two quick skips of the same sound and the DJ eases off it */
async function skipSong() {
  if (!NIGHT || Player.idx < 0) { await Player.next(); return; }
  const k = Player.idx, plan = NIGHT.plan, j = plan.seq[k], early = Player.elapsed < Math.min(45, Math.max(8, Player.dur * 0.35)), real = Player.mode === 'full';
  await Player.next();
  if (!early || !real) return;
  plan.favor = plan.favor || {}; plan.favor[j] = -4; NIGHT.skips = NIGHT.skips || []; NIGHT.skips.push(k);
  const v = VK[plan.pv[j]], recent = NIGHT.skips.slice(-2);
  if (recent.length === 2 && k - recent[0] <= 3 && VK[plan.pv[plan.seq[recent[0]]]] === v && Object.keys(plan.weights).filter(x => plan.weights[x] > 0 && !(plan.exclude && plan.exclude.has(x))).length > 1) { NIGHT.skips = []; const reply = steer([{ t: 'less', v }]); if (reply) toast('Two quick skips. ' + reply); }
}

function finishNight() {
  if (!NIGHT) return;
  const rec = recapOf(NIGHT);
  NIGHTS = [rec].concat(NIGHTS.filter(n => n.id !== rec.id)).slice(0, 12); lsSet('selector.nights', NIGHTS);
  RECAP = rec; lsSet('selector.night', null);
  Player.stop(true); NIGHT = null; stack.length = 0; applyAccent();
  go('recap', { replace: true });
}
function recapOf(night) {
  const plan = night.plan, played = [...night.played].sort((a, b) => a - b);
  const pool = played.length ? played : plan.seq.map((_, k) => k);
  let peakK = pool[0], pe = -1; for (const k of pool) { const e = T.e[plan.seq[k]]; if (e > pe) { pe = e; peakK = k; } }
  const base = night.startedAt || roundedNow();
  return { id: night.createdAt, title: plan.title, date: new Date(base).toLocaleDateString([], { weekday: 'long' }), seconds: night.firstPlay ? (Date.now() - night.firstPlay) / 1000 : totalSeconds(plan), songs: pool.length, peakK, peakJ: plan.seq[peakK], peakAt: fmtClock(new Date(base + startTimes(plan)[peakK] * 1000)), peakArt: night.am[peakK] ? night.am[peakK].art : '', loved: night.loved.size, requests: night.requests.length, saved: night.saved, vibes: byWeight(plan.weights).map(vname), seq: plan.seq.slice(0, 15), arts: plan.seq.slice(0, 15).map((_, k) => night.am[k] ? night.am[k].art : ''), weights: plan.weights, minutes: Math.round(plan.durS / 60), arc: plan.arc, clean: plan.clean, fam: plan.fam, occasion: S.occasion };
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
/* the sound that leads tonight: its colour is the app's accent */
function leadVibe() { const w = NIGHT ? NIGHT.plan.weights : S.weights; return byWeight(w)[0] || 'punjabi'; }
function applyAccent() { const c = (VIBES[leadVibe()] || VIBES.punjabi).color, st = document.documentElement.style; st.setProperty('--accent', c); st.setProperty('--accent-hi', shade(c, 6)); st.setProperty('--accent-lo', shade(c, -20)); }
const posterSize = (el, text) => { el.textContent = text; el.classList.toggle('long', text.length > 16); };

function renderAvatar() { const on = hasApple() && AM.authorized && AM.subscribed === true; $('#btn-you').classList.toggle('on', on); $('#you-text').textContent = on ? 'Apple Music' : 'Previews'; }

function renderTonight() {
  applyAccent();
  const h = new Date().getHours();
  $('#dayline').textContent = new Date().toLocaleDateString([], { weekday: 'long' }) + (h < 12 ? ' morning' : h < 17 ? ' afternoon' : ' evening');
  const open = NIGHT && (NIGHT.startedAt || Player.mode !== 'none') ? NIGHT : null, live = Player.mode !== 'none';
  const occ = OCCASIONS.find(o => o.key === S.occasion);
  const sounds = byWeight(open ? open.plan.weights : S.weights).map(vname);
  $('#hero-kicker').textContent = open ? (live ? 'Playing now' : 'Pick up where you left off') : 'Tonight';
  posterSize($('#hero-title'), open ? open.plan.title : (occ ? occ.label : nightTitle(S.weights)));
  $('#hero-sub').textContent = (open ? [] : [fmtLen(S.minutes * 60).replace(/^(\d+) h$/, (m, n) => n === '1' ? '1 hour' : n + ' hours')]).concat(sounds.slice(0, 3)).join(', ') + (sounds.length > 3 ? ' and more' : '');
  $('#btn-hero-start span').textContent = open ? (live ? 'Back to the night' : 'Continue') : 'Start the night';
  $('#btn-hero-change').hidden = !!open;
  $('#hero').classList.toggle('playing-now', live && Player.playing);
  $('#quick-starts').innerHTML = OCCASIONS.filter(o => o.key !== S.occasion).map(o => { const c = VIBES[byWeight(o.weights)[0]].color; return `<button class="qtile" type="button" data-occ="${o.key}" style="--hi:${shade(c, 6)};--lo:${shade(c, -18)}"><span>${fmtLen(o.minutes * 60)}</span><b>${esc(o.label)}</b></button>`; }).join('');
  const ns = $('#nights-section'); ns.hidden = !NIGHTS.length;
  $('#nights-list').innerHTML = NIGHTS.slice(0, 4).map((n, i) => { const ks = byWeight(n.weights); return `<button class="night-row" type="button" data-night="${i}"><div class="mosaic">${[0, 1, 2, 3].map(q => n.arts[q] ? `<div class="cover" style="background-image:url('${n.arts[q]}')"></div>` : `<div class="cover ph" style="--c:${shade((VIBES[ks[q % ks.length]] || VIBES.pop).color, -10 * q)}"></div>`).join('')}</div><div class="night-text"><b>${esc(n.title)}</b><span>${esc(n.date)}, ${fmtLen(n.seconds)}. Peaked with ${esc(shortTitle(T.n[n.peakJ] || ''))}</span></div><svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg></button>`; }).join('');
  renderAvatar();
}

function renderBrief() {
  const occ = OCCASIONS.find(o => o.key === S.occasion);
  $('#val-occasion').textContent = occ ? occ.label : 'Custom';
  $('#val-length').textContent = fmtLen(S.minutes * 60).replace(' min', ' min').replace(/^(\d+) h$/, '$1 hour' + (S.minutes === 60 ? '' : 's'));
  $('#val-ends').textContent = 'ends ' + endsAt(S.minutes);
  $('#val-crowd').textContent = S.clean ? 'Family-friendly' : 'Anything goes';
  $('#val-crowd2').textContent = S.fam >= 0.65 ? 'songs we know' : 'surprise us';
  const heads = Object.entries(S.weights).filter(([, w]) => w >= 3).map(([k]) => k);
  $('#vibe-grid').innerHTML = ORDER.map(k => { const v = VIBES[k], w = S.weights[k] || 0, meta = D.vibes[VI[k]]; return `<div class="tile ${w ? 'on' : ''} ${w >= 3 ? 'head' : ''}" style="--c:${v.color}" data-vibe="${k}"><span class="tile-dot"></span><button class="tile-main" type="button" data-act="toggle" aria-pressed="${!!w}">${esc(v.short || v.name)}<span class="tile-count">${k === 'mideast' ? 'mostly Turkish for now' : (meta ? meta.n.toLocaleString() + ' songs' : '')}</span></button><button class="tile-star" type="button" data-act="star" aria-label="${w >= 3 ? 'Headliner' : 'Make headliner'}" aria-pressed="${w >= 3}"><svg viewBox="0 0 24 24"><path d="M12 2l3 7 7 .6-5.3 4.6L18.4 22 12 18.2 5.6 22l1.7-7.8L2 9.6 9 9z"/></svg></button></div>`; }).join('');
  $('#taste-text').textContent = TASTE ? `${TASTE.source}. Your DJ knows ${TASTE.matched.length} of your artists${TASTE.matched.length ? ': ' + TASTE.matched.slice(0, 5).join(', ') : ''}${TASTE.matched.length > 5 ? ` and ${TASTE.matched.length - 5} more` : ''}.` : "Not loaded yet. Your DJ leans on the sounds you pick and what's popular.";
  $('#btn-taste-clear').hidden = !TASTE;
  $('#btn-taste-library').hidden = !hasApple();
  void heads; applyAccent();
}

function renderPlanStatus(msg) { const el = $('#plan-status'); if (el) el.textContent = msg || ''; }
function renderPlan() {
  if (!NIGHT) return;
  applyAccent();
  const plan = NIGHT.plan, n = plan.seq.length, tot = totalSeconds(plan);
  posterSize($('#plan-title'), plan.title);
  $('#plan-meta').textContent = `${n} songs, ${fmtLen(tot)}. Ends around ${fmtClock(new Date((NIGHT.startedAt || roundedNow()) + tot * 1000))}.`;
  mosaic($('#plan-fan'), [0, Math.floor(n / 3), Math.floor(2 * n / 3), n - 1].map(k => clamp(k, 0, n - 1)));
  $('#dj-note').textContent = djNote(plan);
  $('#btn-start span').textContent = Player.mode !== 'none' ? 'Back to the night' : (startNight.busy ? 'Cueing up…' : 'Start the night');
  $('#btn-newtake').hidden = Player.mode !== 'none';
  $('#btn-save').classList.toggle('filled', NIGHT.saved);
  $('#btn-save').innerHTML = NIGHT.saved ? '<svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg>' : '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>';
  $('#btn-save').hidden = !hasApple();
  const found = NIGHT.am.filter(m => m !== undefined).length;
  renderPlanStatus(startNight.busy ? 'Cueing up the first song…' : NIGHT.resolving ? (found ? `Finding your songs… ${found} of ${n}` : 'Finding your songs…') : (NIGHT.resolveNote || (NIGHT.resolved ? (hasApple() ? `All ${n} songs found on Apple Music.` : `All ${n} songs ready.`) : (DEMO_ONLY ? 'Demo: the plan is real, playback needs the full app.' : ''))));
  renderJourney();
  $('#link-all').textContent = `See all ${n} songs`;
  $('#plan-first').innerHTML = [0, 1, 2].filter(k => k < n).map(k => songRow(k, { time: fmtClock(clockAt(k)) })).join('');
}
function renderJourney() {
  const plan = NIGHT.plan, seq = plan.seq, n = seq.length, st = startTimes(plan), tot = totalSeconds(plan);
  const e = seq.map(j => T.e[j]); const sm = e.map((_, k) => { const s = e.slice(Math.max(0, k - 2), k + 3); return s.reduce((a, b) => a + b, 0) / s.length; });
  const lo = Math.min(...sm) - 0.04, hi = Math.max(...sm) + 0.04;
  const W = 358, H = 120; const pts = seq.map((j, k) => [6 + (W - 12) * (st[k] + T.dur[j] / 2) / tot, 8 + (H - 16) * (1 - (sm[k] - lo) / (hi - lo))]);
  const cr = p => { let d = `M${p[0][0].toFixed(1)},${p[0][1].toFixed(1)}`; for (let i = 0; i < p.length - 1; i++) { const p0 = p[Math.max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[Math.min(i + 2, p.length - 1)]; d += `C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(1)},${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(1)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(1)},${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`; } return d; };
  const d = cr(pts), ph = phases(plan), peak = ph.find(p => p.key === 'peak');
  let peakPt = pts[peak ? peak.from : 0]; if (peak) { let be = -1; for (let k = peak.from; k < peak.to; k++) if (sm[k] > be) { be = sm[k]; peakPt = pts[k]; } }
  const now = Player.mode !== 'none' && Player.idx >= 0 && pts[Player.idx] ? pts[Player.idx] : null;
  const c = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#FF4FA0';
  $('#journey-svg').innerHTML = `<defs><linearGradient id="jg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c}" stop-opacity=".42"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></linearGradient></defs><path fill="url(#jg)" d="${d} L${pts[pts.length - 1][0].toFixed(1)},${H} L${pts[0][0].toFixed(1)},${H} Z"/><path class="line" d="${d}"/>${now ? `<line class="now" x1="${now[0].toFixed(1)}" x2="${now[0].toFixed(1)}" y1="0" y2="${H}"/><circle class="nowdot" cx="${now[0].toFixed(1)}" cy="${now[1].toFixed(1)}" r="5.5"/>` : ''}<circle class="dot" cx="${peakPt[0].toFixed(1)}" cy="${peakPt[1].toFixed(1)}" r="6"/>`;
  $('#journey-labels').innerHTML = ph.map(p => p.key === 'peak' ? `<b>Peak ${esc(fmtClock(new Date((NIGHT.startedAt || roundedNow()) + p.start * 1000)))}</b>` : `<span>${p.label}</span>`).join('');
}

let phaseFilter = 'all';
function songRow(k, opt = {}) {
  const j = NIGHT.plan.seq[k], m = NIGHT.am[k];
  const status = m === null ? ' · not available' : (NIGHT.replaced.has(k) ? ' · close match' : '');
  const now = Player.idx === k && Player.mode !== 'none';
  const cls = now ? 'now' : (Player.mode !== 'none' && Player.idx > k ? 'played' : '');
  const artist = T.ar[j].split(', ').slice(0, 2).join(', ');
  return `<button class="song ${cls}" type="button" data-k="${k}">${now ? coverEl(j, k, 'row').replace(/<\/div>$/, '<span class="bars"><i></i><i></i><i></i></span></div>') : coverEl(j, k, 'row')}<div class="text"><div class="name">${esc(T.n[j])}</div><div class="artist">${esc(artist)}${status}</div></div><span class="time">${opt.time || ''}</span>${opt.more ? '<span class="more" data-more="' + k + '"><svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg></span>' : ''}</button>`;
}
function renderSongs() {
  if (!NIGHT) return;
  const plan = NIGHT.plan, n = plan.seq.length, ph = phases(plan);
  $('#songs-title').textContent = `${n} songs`;
  $('#phase-chips').innerHTML = [{ key: 'all', label: 'All' }].concat(ph).map(p => `<button class="pchip ${phaseFilter === p.key ? 'on' : ''}" type="button" data-phase="${p.key}">${esc(p.label)}</button>`).join('');
  let html = '';
  for (const p of ph) {
    if (phaseFilter !== 'all' && phaseFilter !== p.key) continue;
    html += `<div class="phase-head"><span>${esc(p.label)}</span><span>${fmtClock(clockAt(p.from))} to ${fmtClock(new Date((NIGHT.startedAt || roundedNow()) + p.end * 1000))}</span></div>`;
    for (let k = p.from; k < p.to; k++) {
      { const w = k > 0 ? transitionWord(plan.seq[k - 1], plan.seq[k]) : ''; if (w) html += `<div class="tx-label ${/drop|switch|speed/i.test(w) ? 'hot' : ''}"><i></i><span>${esc(w)}</span></div>`; }
      html += `<div class="swipe" data-k="${k}">${songRow(k, { time: fmtClock(clockAt(k)), more: true })}<div class="actions"><button class="swapb" type="button" data-swap="${k}"><svg viewBox="0 0 24 24"><path d="M4 7h13l-3-3M20 17H7l3 3"/></svg>Swap</button><button type="button" data-remove="${k}"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>Remove</button></div></div>`;
    }
  }
  $('#song-list').innerHTML = html + '<div class="list-foot">Swipe a song left to swap or remove it.</div>';
  $('#btn-start2').innerHTML = Player.mode !== 'none' ? '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>Back to the night' : '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>Start the night';
  $('#songs-cta').hidden = Player.mode !== 'none';
}

function renderNowPlaying() {
  if (!NIGHT || Player.idx < 0) return;
  const k = Player.idx, j = NIGHT.plan.seq[k], m = NIGHT.am[k], n = NIGHT.plan.seq.length;
  $('#np-set').textContent = NIGHT.plan.title;
  const ph = phaseOf(NIGHT.plan, k); $('#np-phase').textContent = `${ph ? ph.label + ', ' : ''}song ${k + 1} of ${n}`;
  const art = $('#np-art'), back = $('#np-backdrop');
  if (m && m.art) { art.style.backgroundImage = `url('${m.art}')`; art.classList.remove('ph'); back.style.backgroundImage = `url('${m.art.replace('600x600', '200x200')}')`; }
  else { art.style.backgroundImage = ''; art.classList.add('ph'); back.style.backgroundImage = ''; }
  art.style.setProperty('--c', phColor(j)); back.style.setProperty('--c', phColor(j));
  $('#np-name').textContent = T.n[j]; $('#np-artist').textContent = T.ar[j];
  $('#btn-love').classList.toggle('on', NIGHT.loved.has(j));
  const nk = k + 1, nj = NIGHT.plan.seq[nk];
  if (nj !== undefined) {
    $('#next-card').hidden = false;
    $('#next-art').outerHTML = coverEl(nj, nk, 'sm').replace('class="cover', 'id="next-art" class="cover');
    $('#next-name').textContent = T.n[nj];
  } else { $('#next-card').hidden = true; }
  $('#steer-row').innerHTML = steerChips(true).map((c, i) => `<button class="chip light" type="button" data-chip="${i}">${esc(c.label)}</button>`).join('');
  $('#np-mode').textContent = Player.mode === 'full' ? (isIOS ? 'Full songs from your Apple Music. Keep Selector open to hear the whole night.' : 'Full songs from your Apple Music.') : Player.mode === 'mix' ? 'Previews, mixed live: beatmatched, with bass swaps and echo-outs.' : Player.mode === 'preview' ? `Previews: 30 seconds of each song${Player.xf ? ', blended' : ''}.${hasApple() ? ' Connect Apple Music for full songs.' : ''}` : 'Demo: the clock runs six times faster than the music would.';
  renderTransport(); renderProgress(); renderMini();
}
function steerChips(short) {
  const heads = NIGHT ? Object.entries(NIGHT.plan.weights).filter(([, w]) => w >= 3).map(([k]) => k).sort() : [];
  const chips = [{ label: 'More energy', it: { t: 'energy', up: true } }, { label: 'Bring it down', it: { t: 'energy', up: false } }, { label: 'Something we know', it: { t: 'familiar' } }];
  if (!short) chips.push({ label: 'Surprise us', it: { t: 'surprise' } });
  for (const h of (short ? heads.slice(0, 1) : heads)) chips.push({ label: `More ${vname(h)}`, it: { t: 'more', v: h } });
  chips.push({ label: 'Skip this vibe', it: { t: 'less', v: null } }, { label: 'Wrap up in 20 min', it: { t: 'wrap', m: 20 } });
  return chips;
}
function mixDark(hex) { try { const n = parseInt(hex.slice(1), 16); const r = n >> 16, g = n >> 8 & 255, b = n & 255; const f = 0.28; return `rgb(${Math.round(r * f + 10)},${Math.round(g * f + 10)},${Math.round(b * f + 13)})`; } catch (e) { return '#1A0F12'; } }
function renderTransport() { const p = Player.playing; $('#np-art').classList.toggle('paused', !p && Player.mode !== 'none'); $('#hero').classList.toggle('playing-now', p && Player.mode !== 'none'); $('#play-icon').innerHTML = p ? '<path d="M7 5h4v14H7zM13 5h4v14h-4z"/>' : '<path d="M7 4.5v15l12-7.5z"/>'; $('#btn-play').setAttribute('aria-label', p ? 'Pause' : 'Play'); $('#mini-play').innerHTML = p ? '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zM13 5h4v14h-4z"/></svg>' : '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z"/></svg>'; }
function renderProgress() {
  const d = Player.dur || 1, e = Player.elapsed;
  $('#np-bar').style.width = clamp(100 * e / d, 0, 100).toFixed(1) + '%';
  $('#np-el').textContent = fmtT(e); $('#np-rem').textContent = '-' + fmtT(Math.max(0, d - e));
  const rem = Math.max(0, d - e), xf = Player.mode === 'preview' ? Player.xf : 0, blending = Player.fading || (xf > 0 && rem <= xf + 0.5);
  const k = Player.idx, seq = NIGHT ? NIGHT.plan.seq : [], w = seq[k + 1] !== undefined ? transitionWord(seq[k], seq[k + 1]) : '';
  const nl = $('#next-kicker'), mixing = Player.mode === 'mix' && Mix.label;
  nl.textContent = mixing ? Mix.label : blending ? 'Blending in now' : `Next, ${w ? w.toLowerCase() : 'a smooth blend'} in ${fmtT(rem)}`; nl.classList.toggle('hot', !!mixing || blending);
  const mn = Player.mode === 'mix' ? Mix.now() : null, j = seq[k];
  $('#np-deck').textContent = j === undefined ? '' : `${Math.round(mn ? mn.bpm : T.bpm[j])} BPM, key ${CAMN[j]}${CAML[j] ? 'B' : 'A'}`;
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
  const ks = byWeight(r.weights), c = (VIBES[ks[0]] || VIBES.punjabi).color, card = $('#recap-card');
  card.style.setProperty('--hi', shade(c, 6)); card.style.setProperty('--lo', shade(c, -22));
  document.documentElement.style.setProperty('--accent', c);
  $('#recap-date').textContent = `${r.date} night`;
  posterSize($('#recap-title'), r.title);
  $('#recap-fan').innerHTML = [0, 1, 2, 3, 4].map(i => r.arts[i] ? `<div class="cover" style="background-image:url('${r.arts[i]}')"></div>` : `<div class="cover ph" style="--c:${shade((VIBES[ks[i % ks.length]] || VIBES.pop).color, -12 * (i % 3) - 18)}"></div>`).join('');
  $('#recap-kicker').textContent = `The floor peaked at ${r.peakAt} with`;
  $('#recap-song').textContent = shortTitle(T.n[r.peakJ] || ''); $('#recap-artist').textContent = T.ar[r.peakJ] || '';
  $('#recap-stats').innerHTML = `<div><b>${r.songs}</b><span>songs</span></div><div><b>${esc(fmtLen(r.seconds))}</b><span>of music</span></div>${r.loved ? `<div><b>${r.loved}</b><span>loved</span></div>` : ''}${r.requests ? `<div><b>${r.requests}</b><span>request${r.requests === 1 ? '' : 's'}</span></div>` : ''}`;
  $('#recap-saved').hidden = !r.saved;
}

function renderCurrentScreen() { ({ tonight: renderTonight, brief: renderBrief, plan: renderPlan, songs: renderSongs, playing: renderNowPlaying, recap: renderRecap })[current]?.(); renderMini(); }

/* ---------------- router ---------------- */
function go(name, opts = {}) {
  if (name === 'back') { name = stack.pop() || 'tonight'; }
  else if (name === 'tonight') stack.length = 0;
  else if (stack.includes(name)) stack.length = stack.indexOf(name);          // going somewhere we've been: unwind to it
  else if (!opts.replace && current !== name) stack.push(current);
  if (name === 'plan' && !NIGHT) name = 'tonight';
  if (stack.length > 12) stack.shift();
  $$('.screen').forEach(s => { s.hidden = s.id !== 's-' + name; s.classList.remove('enter'); });
  const el = $('#s-' + name); if (!el) return; void el.offsetWidth; el.classList.add('enter');
  current = name; closeSheets();
  renderCurrentScreen();
  if (name !== 'recap') applyAccent();
  const sc = el.querySelector('.scroll'); if (sc && !opts.keepScroll) sc.scrollTop = 0;
}
function openSheet(id) { closeSheets(); $('#backdrop').hidden = false; $('#' + id).hidden = false; }
function closeSheets() { $('#backdrop').hidden = true; $$('.sheet').forEach(s => { s.hidden = true; }); }

/* ---------------- flows ---------------- */
/* previews: mixed like a DJ when the audio can be read, plainly crossfaded when it can't */
async function startPreviews(k) { const mixed = await Mix.ready(k); await Player.start(k, mixed ? 'mix' : 'preview'); }
async function startNight(fromK = 0) {
  if (!NIGHT) { if (!planNight()) return; }
  if (Player.mode !== 'none') { go('playing'); return; }
  if (!hasApple()) {
    if (DEMO_ONLY) { await Player.start(fromK, 'demo'); go('playing'); return; }
    if (startNight.busy) return; startNight.busy = true;
    Player.unlock();                                   // inside the tap, so the browser lets sound start later
    const night = NIGHT; night.priority = fromK;
    renderPlanStatus('Cueing up the first song…');
    resolveNightLookup(night);
    const t0 = Date.now();
    while (NIGHT === night && night.am[fromK] === undefined && !night.lookupFailed && Date.now() - t0 < 15000) await new Promise(r => setTimeout(r, 120));
    startNight.busy = false;
    if (NIGHT !== night) return;
    let first = -1; for (let k = fromK; k < night.am.length; k++) if (night.am[k] && night.am[k].preview) { first = k; break; }
    if (first < 0) { toast("Couldn't reach the song lookup, so this is a silent run-through."); await Player.start(fromK, 'demo'); go('playing'); return; }
    await startPreviews(first); go('playing'); return;
  }
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
    NIGHT.saved = true; renderPlan(); toast('Saved to your Apple Music library.');
  } catch (e) { toast("Couldn't save the playlist"); }
}
async function shareRecap() {
  const r = RECAP; if (!r) return;
  const text = `${r.title}: ${r.songs} songs, ${fmtLen(r.seconds)}. The floor peaked at ${r.peakAt} with ${T.n[r.peakJ].replace(/\s*[\(\[].*$/, '')} by ${T.ar[r.peakJ]}. Planned by Selector.`;
  try { if (navigator.share) { await navigator.share({ title: r.title, text }); return; } } catch (e) { return; }
  try { await navigator.clipboard.writeText(text); toast('Copied. Paste it anywhere.'); } catch (e) { toast(text); }
}

/* ---------------- events ---------------- */
function bind() {
  document.addEventListener('click', e => {
    const goBtn = e.target.closest('[data-go]'); if (goBtn) { go(goBtn.dataset.go); return; }
    const occ = e.target.closest('[data-occ]'); if (occ) { if (Player.mode !== 'none') { toast('A night is already playing.'); return; } applyOccasion(occ.dataset.occ); if (planNight()) go('plan'); return; }
    const night = e.target.closest('[data-night]'); if (night) { RECAP = NIGHTS[+night.dataset.night]; go('recap'); return; }
  });
  $('#ask-form').addEventListener('submit', e => { e.preventDefault(); const v = $('#ask-input').value.trim(); if (!v) return; $('#ask-input').blur(); if (planFromText(v)) $('#ask-input').value = ''; });
  $('#btn-hero-change').addEventListener('click', () => go('brief'));
  $('#btn-hero-start').addEventListener('click', () => { if (NIGHT && Player.mode !== 'none') { go('playing'); return; } if (NIGHT && NIGHT.startedAt) { go('plan'); return; } if (planNight()) go('plan'); });
  $('#btn-end').addEventListener('click', () => { if (!NIGHT) return; if (!$('#btn-end').classList.contains('sure')) { $('#btn-end').classList.add('sure'); $('#btn-end').textContent = 'End now?'; setTimeout(() => { $('#btn-end').classList.remove('sure'); $('#btn-end').textContent = 'End'; }, 3000); return; } $('#btn-end').classList.remove('sure'); $('#btn-end').textContent = 'End'; Player.finish(); });
  $('#btn-tell').addEventListener('click', () => openSteer());
  $('#btn-you').addEventListener('click', async () => { if (!hasApple()) { toast(DEMO_ONLY ? 'This demo plans the night; the full app plays it.' : 'You hear 30-second previews of every song. Full songs need an Apple Music key on this site.'); return; } if (AM.authorized) { toast(AM.subscribed ? 'Apple Music connected' : 'Connected, but this Apple ID has no Apple Music subscription'); return; } if (await authorize()) toast('Apple Music connected'); });
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
    const row = e.target.closest('.song'); if (row && !row.closest('.swipe.open')) { const k = +row.dataset.k; if (Player.mode !== 'none') { if (Player.mode === 'mix' && !Mix.loaded(k) && !(NIGHT.am[k] && NIGHT.am[k].preview)) { toast('Still finding that one'); return; } Player.start(k, Player.mode).then(() => go('playing')); } else startNight(k); }
  });
  bindSwipe($('#song-list'));
  $('#btn-play').addEventListener('click', () => Player.toggle());
  $('#btn-next').addEventListener('click', () => skipSong());
  $('#btn-prev').addEventListener('click', () => Player.prev());
  $('#btn-love').addEventListener('click', toggleLove);
  $('#next-card').addEventListener('click', () => go('songs'));
  $('#steer-row').addEventListener('click', e => { const b = e.target.closest('[data-chip]'); if (!b) return; const c = steerChips(true)[+b.dataset.chip]; openSteer(); if (c) doSteer([c.it]); });
  $('#steer-chips').addEventListener('click', e => { const b = e.target.closest('[data-chip]'); if (!b) return; const c = steerChips(false)[+b.dataset.chip]; if (c) doSteer([c.it]); });
  $('#steer-form').addEventListener('submit', e => { e.preventDefault(); const t = $('#steer-input').value.trim(); if (!t) return; const its = parseRequest(t); $('#steer-input').value = ''; if (!its.length) { $$('#steer-chips .chip').forEach(c => c.classList.remove('on')); showReply('I didn\'t catch that. Try "more energy", "play Brown Munde", "no more techno", or "wrap up in 15 minutes".'); return; } doSteer(its); });
  $('#btn-undo').addEventListener('click', () => { undoSteer(); $('#dj-reply').hidden = true; $$('#steer-chips .chip').forEach(c => c.classList.remove('on')); toast('Back to the earlier plan'); });
  $('#mini').addEventListener('click', e => { if (e.target.closest('#mini-play')) { Player.toggle(); return; } go('playing'); });
  $('#mini-play').addEventListener('click', e => { e.stopPropagation(); Player.toggle(); });
  $('#connect-actions').addEventListener('click', async e => { const b = e.target.closest('[data-connect]'); if (!b) return; if (b.dataset.connect === 'full') { if (!await authorize()) return; if (!AM.subscribed) { openConnect(); return; } closeSheets(); await Player.start(pendingStart, 'full'); go('playing'); } else { closeSheets(); Player.unlock(); await startPreviews(pendingStart); go('playing'); } });
  $('#btn-share').addEventListener('click', shareRecap);
  $('#btn-again').addEventListener('click', () => { const r = RECAP; if (!r) return; S.weights = { ...r.weights }; S.minutes = r.minutes; S.arc = r.arc; S.clean = r.clean; S.fam = r.fam; S.occasion = r.occasion; saveSettings(); if (planNight()) go('plan'); });
  $('#occasion-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; applyOccasion(b.dataset.pick); closeSheets(); renderBrief(); });
  $('#length-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; S.minutes = +b.dataset.pick; saveSettings(); closeSheets(); renderBrief(); });
  $('#crowd-list').addEventListener('click', e => { const b = e.target.closest('[data-pick]'); if (!b) return; const v = b.dataset.pick; if (v === 'clean') S.clean = !S.clean; if (v === 'known') S.fam = 0.85; if (v === 'surprise') S.fam = 0.4; if (v === 'taste') S.useTaste = !S.useTaste; saveSettings(); renderCrowdSheet(); renderBrief(); });
  window.addEventListener('pagehide', () => { if (!NIGHT) lsSet('selector.night', null); else lsSet('selector.night', { seq: NIGHT.plan.seq, weights: NIGHT.plan.weights, arc: NIGHT.plan.arc, clean: NIGHT.plan.clean, fam: NIGHT.plan.fam, durS: NIGHT.plan.durS, title: NIGHT.plan.title, startedAt: NIGHT.startedAt, played: [...NIGHT.played], loved: [...NIGHT.loved], requests: NIGHT.requests, saved: NIGHT.saved, createdAt: NIGHT.createdAt }); });
}
function sameWeights(a, b) { if (!b) return false; const ka = Object.keys(a).filter(k => a[k] > 0), kb = Object.keys(b); return ka.length === kb.length && ka.every(k => a[k] === b[k]); }
function applyOccasion(key) { const o = OCCASIONS.find(x => x.key === key); if (!o) return; S.occasion = key; S.weights = { ...o.weights }; S.minutes = o.minutes; S.arc = o.arc; S.clean = o.clean; S.fam = o.fam; saveSettings(); renderTonight(); }
function renderOccasionSheet() { $('#occasion-list').innerHTML = OCCASIONS.map(o => `<button class="opt ${S.occasion === o.key ? 'on' : ''}" type="button" data-pick="${o.key}"><div><b>${esc(o.label)}</b><span>${esc(o.desc)}</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>`).join(''); }
function renderLengthSheet() { $('#length-list').innerHTML = LENGTHS.map(m => `<button class="opt ${S.minutes === m ? 'on' : ''}" type="button" data-pick="${m}"><div><b>${fmtLen(m * 60)}</b><span>ends around ${endsAt(m)}</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>`).join(''); }
function renderCrowdSheet() { $('#crowd-list').innerHTML = `<button class="toggle-row" type="button" data-pick="clean"><div><b>Family-friendly</b><span>No explicit versions</span></div><span class="switch ${S.clean ? 'on' : ''}"></span></button><button class="opt ${S.fam >= 0.65 ? 'on' : ''}" type="button" data-pick="known"><div><b>Songs we know</b><span>The hits, the sing-alongs</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button><button class="opt ${S.fam < 0.65 ? 'on' : ''}" type="button" data-pick="surprise"><div><b>Surprise us</b><span>Deeper cuts, fewer obvious picks</span></div><span class="check"><svg viewBox="0 0 24 24"><path d="M5 12l5 5 9-10"/></svg></span></button>${TASTE ? `<button class="toggle-row" type="button" data-pick="taste"><div><b>Lean on my taste</b><span>${esc(TASTE.matched.slice(0, 3).join(', '))}</span></div><span class="switch ${S.useTaste ? 'on' : ''}"></span></button>` : ''}`; $$('#crowd-list .opt b, #crowd-list .toggle-row b').forEach(b => { b.style.display = 'block'; }); }
function openSteer() {
  $('#steer-chips').innerHTML = steerChips(false).map((c, i) => `<button class="chip" type="button" data-chip="${i}" data-key="${esc(intentKey(c.it))}">${esc(c.label)}</button>`).join('');
  $('#dj-reply').hidden = true; openSheet('sheet-steer');
}
function doSteer(intents) {
  const reply = steer(intents), key = intentKey(intents[0]);
  $$('#steer-chips .chip').forEach(c => c.classList.toggle('on', c.dataset.key === key));
  showReply(reply || "I couldn't do that one.");
}
function showReply(text) { const r = $('#dj-reply'); r.hidden = true; void r.offsetWidth; r.hidden = false; $('#dj-reply-text').textContent = text; $('#btn-undo').hidden = !(NIGHT && NIGHT.undo); }
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
  if (saved && Date.now() - saved.createdAt < 12 * 3600 * 1000 && Array.isArray(saved.seq) && saved.seq.every(j => j >= 0 && j < N)) {
    const tw = (S.useTaste && TASTE) ? Float32Array.from(TASTE.tw) : null;
    const r = buildSet({ weights: saved.weights, durS: 60, arc: saved.arc, clean: saved.clean, fam: saved.fam, tw, seed: 1, xf: 0 });
    if (r) { NIGHT = makeNight({ seq: saved.seq, pv: r.pv, pool: r.pool, short: false, baseE: r.baseE, amp: r.amp, weights: saved.weights, arc: saved.arc, clean: saved.clean, fam: saved.fam, tw, durS: saved.durS, title: saved.title, exclude: null, boost: null, energyOff: null, favor: {}, banned: new Set() }); for (const j of saved.seq) if (NIGHT.plan.pv[j] < 0) NIGHT.plan.pv[j] = VI[byWeight(saved.weights)[0]] ?? 0; NIGHT.startedAt = saved.startedAt; NIGHT.played = new Set(saved.played); NIGHT.loved = new Set(saved.loved); NIGHT.requests = saved.requests || []; NIGHT.saved = !!saved.saved; NIGHT.createdAt = saved.createdAt; }
  }
  go('tonight', { replace: true });
  if (TASTE && TASTE.tw.length !== N) { TASTE = null; lsSet('selector.taste', null); }
  amInit().then(() => { if (NIGHT && AM.ready) resolveNight(NIGHT); else if (NIGHT && !hasApple() && !DEMO_ONLY) resolveNightLookup(NIGHT); });
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
}
window.__selector = { parseRequest, parseBrief, intentKey, analyzeBeats, Mix, Player, bpmOfLookup: id => { const k = NIGHT ? NIGHT.am.findIndex(m => m && m.id === id) : -1; return k < 0 ? 0 : T.bpm[NIGHT.plan.seq[k]]; } };   // for the console and for tests
boot();
})();
