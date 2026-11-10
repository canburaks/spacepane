// SpacePane app preview film.
//
// One idea: the Space bar. Every preview in the film is brought up by a press of the same key, and the key travels
// from the opening headline to the corner of the frame and finally into the app icon.
//
// window.renderAt(seconds) lays out exactly one frame from the time value. There are no timers, no CSS animations
// and no randomness, so a frame is the same however often and in whatever order it is rendered.
//
// All app interface in the film is a real window capture from footage/. The film moves, scales (never above the
// capture's own pixels), masks and cross-fades those captures; it draws headlines, backgrounds, the key and a few
// annotation marks, and nothing that looks like app interface.
'use strict';

const W = 1920, H = 1080, FPS = 30;

// ---- Beats (seconds) -------------------------------------------------------------------------------------------
const T = {
  press1: 1.25, // Space: the panel opens on settings.json
  push1: 2.5,   // camera pushes into the outline
  s2: 5.3,      // secrets: headline changes, camera goes to the banner
  wipe2: 5.95,  // Outline gives way to Source
  s3: 9.5,      // Space: stations.sqlite
  s4: 13.0,     // Space: release-1.4.zip
  s5: 15.4,     // Space: tide-analysis.ipynb
  s6: 17.8,     // Space: README.md
  s8: 20.0,     // the app: File Types
  s9: 22.2,     // the app: Theme
  end: 24.4,    // end card
};
const DURATION = 27.2;
const PRESSES = [T.press1, T.s3, T.s4, T.s5, T.s6];

// ---- Grid ------------------------------------------------------------------------------------------------------
const COL_X = 96;          // left margin and headline column
const CAP_X = 704;         // left edge of the capture area
const EYEBROW_Y = 290;
const HEAD_Y = 366;
const LINE_H = 84;
const KEY_REST = { x: COL_X, y: 904, w: 284, h: 68, r: 17, fs: 25 };

// ---- Math ------------------------------------------------------------------------------------------------------
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, p) => a + (b - a) * p;
const prog = (t, t0, d) => clamp((t - t0) / d);

function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const fx = (u) => ((ax * u + bx) * u + cx) * u;
  const fy = (u) => ((ay * u + by) * u + cy) * u;
  const dfx = (u) => (3 * ax * u + 2 * bx) * u + cx;
  return (p) => {
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    let u = p;
    for (let i = 0; i < 8; i++) {
      const d = dfx(u);
      if (Math.abs(d) < 1e-6) break;
      u -= (fx(u) - p) / d;
    }
    u = clamp(u);
    return fy(u);
  };
}
// The website's three curves (DESIGN.md in the spacepane-web repository) plus a camera curve and an exit curve.
const ease = {
  soft: bezier(0.22, 1, 0.36, 1),
  glide: bezier(0.2, 0.75, 0.2, 1),
  inOut: bezier(0.62, 0, 0.3, 1),
  in: bezier(0.5, 0, 0.9, 0.5),
  out: bezier(0.1, 0.6, 0.3, 1),
  linear: (p) => clamp(p),
};
// A damped spring from 0 to 1; `seconds` is elapsed time. zeta below 1 overshoots.
function spring(seconds, omega = 15, zeta = 0.62) {
  if (seconds <= 0) return 0;
  const wd = omega * Math.sqrt(1 - zeta * zeta);
  return 1 - Math.exp(-zeta * omega * seconds) * (Math.cos(wd * seconds) + (zeta * omega / wd) * Math.sin(wd * seconds));
}
// Velocity ramps from zero to one: used so slow camera drift never starts or stops with a jerk.
const ramp = (u, tau = 0.7) => (u <= 0 ? 0 : u - tau * (1 - Math.exp(-u / tau)));

// Keyframes: [{t, ...numbers, e}], `e` is the curve of the segment that arrives at that keyframe.
function track(t, frames) {
  if (t <= frames[0].t) return frames[0];
  for (let i = 1; i < frames.length; i++) {
    const a = frames[i - 1], b = frames[i];
    if (t <= b.t) {
      const p = (b.e || ease.inOut)((t - a.t) / (b.t - a.t));
      const out = {};
      for (const k of Object.keys(b)) {
        if (k === 't' || k === 'e') continue;
        out[k] = k === 's' ? Math.exp(lerp(Math.log(a[k]), Math.log(b[k]), p)) : lerp(a[k], b[k], p);
      }
      return out;
    }
  }
  return frames[frames.length - 1];
}

const px = (v) => `${Math.round(v * 1000) / 1000}px`;
function el(tag, cls, parent, html) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (html != null) node.innerHTML = html;
  if (parent) parent.appendChild(node);
  return node;
}
const show = (node, on) => { node.style.display = on ? '' : 'none'; };
function setMask(node, value) {
  node.style.webkitMaskImage = value;
  node.style.maskImage = value;
}

const stage = document.getElementById('stage');

// ---- Worlds (backgrounds) --------------------------------------------------------------------------------------
// Warm paper opens and closes the film (the website's ground). In between, each scene keeps the gradient of its
// approved store screenshot (script/store-screenshots/compose.sh), lit by two slow lights.
const KEY_REST_C = { x: KEY_REST.x + KEY_REST.w / 2, y: KEY_REST.y + KEY_REST.h / 2 };
const WORLDS = [
  { t: -9, kind: 'cut', paper: true },
  { t: T.press1 + 0.02, kind: 'wipe', dur: 1.0, origin: 'inline', colors: ['#4b3cff', '#a64dff', '#ff4f9a', '#ffb547'] },
  { t: T.s2 - 0.1, kind: 'fade', dur: 1.1, colors: ['#3a2be6', '#7b43ff', '#c44dff'] },
  { t: T.s3 + 0.02, kind: 'wipe', dur: 0.85, colors: ['#3a2be6', '#2f7de1', '#32c8c0'] },
  { t: T.s4 + 0.02, kind: 'wipe', dur: 0.85, colors: ['#7b43ff', '#d44fd0', '#ff4f9a'] },
  { t: T.s5 + 0.02, kind: 'wipe', dur: 0.85, colors: ['#d6307f', '#ff5b6e', '#ff9a4a'] },
  { t: T.s6 + 0.02, kind: 'wipe', dur: 0.85, colors: ['#1f5fd6', '#2a9fd6', '#3fd3b5'] },
  { t: T.s8 - 0.05, kind: 'fade', dur: 0.7, colors: ['#e0358a', '#a64dff', '#4b3cff'] },
  { t: T.s9 - 0.1, kind: 'fade', dur: 0.8, colors: ['#4b3cff', '#a64dff', '#ff4f9a', '#ffb547'] },
  { t: T.end + 0.12, kind: 'wipe', dur: 0.9, origin: 'center', paper: true },
];

function rgba(hex, a) {
  const v = parseInt(hex.slice(1), 16);
  return `rgba(${(v >> 16) & 255},${(v >> 8) & 255},${v & 255},${a})`;
}

for (const world of WORLDS) {
  const node = el('div', 'world', stage);
  world.node = node;
  world.base = el('div', 'base', node);
  if (world.paper) {
    world.base.style.background = [
      `radial-gradient(1000px 1000px at 8% 96%, ${rgba('#4b3cff', 0.17)}, ${rgba('#4b3cff', 0.07)} 45%, transparent 100%)`,
      `radial-gradient(940px 940px at 44% 124%, ${rgba('#a64dff', 0.15)}, ${rgba('#a64dff', 0.06)} 45%, transparent 100%)`,
      `radial-gradient(940px 940px at 82% 108%, ${rgba('#ff4f9a', 0.15)}, ${rgba('#ff4f9a', 0.06)} 45%, transparent 100%)`,
      `radial-gradient(860px 860px at 104% 46%, ${rgba('#ffb547', 0.19)}, ${rgba('#ffb547', 0.08)} 45%, transparent 100%)`,
      '#f4f1ea',
    ].join(',');
  } else {
    world.base.style.background = `linear-gradient(125deg, ${world.colors.join(', ')})`;
    world.lightA = el('div', 'light', node);
    world.lightB = el('div', 'light', node);
    world.shade = el('div', 'shade', node);
    const last = world.colors[world.colors.length - 1];
    world.lightA.style.cssText += 'width:1500px;height:1500px;background:radial-gradient(closest-side, rgba(255,255,255,0.20), rgba(255,255,255,0.07) 55%, rgba(255,255,255,0));';
    world.lightB.style.cssText += `width:1700px;height:1700px;background:radial-gradient(closest-side, ${rgba(last, 0.55)}, ${rgba(last, 0.18)} 55%, ${rgba(last, 0)});`;
    // A deeper left edge keeps the white headline at full strength on every gradient.
    world.shade.style.background = 'linear-gradient(90deg, rgba(14,8,64,0.34) 0%, rgba(14,8,64,0.16) 30%, rgba(14,8,64,0) 58%), linear-gradient(0deg, rgba(14,8,64,0.20) 0%, rgba(14,8,64,0) 34%)';
  }
}

function wipeMask(cx, cy, p) {
  const far = Math.max(Math.hypot(cx, cy), Math.hypot(W - cx, cy), Math.hypot(cx, H - cy), Math.hypot(W - cx, H - cy));
  const feather = 150;
  const r = lerp(0, far + feather, p);
  return `radial-gradient(circle at ${px(cx)} ${px(cy)}, #000 ${px(Math.max(0, r - feather))}, rgba(0,0,0,0) ${px(r)})`;
}

let inlineKeyCenter = { x: 400, y: 400 };
let floodMask = 'none'; // the paper-to-color wipe, shared with the white copy of the headline

function renderWorlds(t) {
  let current = 0;
  for (let i = 0; i < WORLDS.length; i++) if (t >= WORLDS[i].t) current = i;
  floodMask = 'none';
  WORLDS.forEach((world, i) => {
    const node = world.node;
    const p = world.kind === 'cut' ? 1 : prog(t, world.t, world.dur);
    const visible = i === current || (i === current - 1 && prog(t, WORLDS[current].t, WORLDS[current].dur) < 1);
    show(node, visible);
    if (!visible) return;
    node.style.opacity = 1;
    setMask(node, 'none');
    if (i === current && p < 1) {
      if (world.kind === 'fade') node.style.opacity = ease.inOut(p);
      if (world.kind === 'wipe') {
        const c = world.origin === 'inline' ? inlineKeyCenter : world.origin === 'center' ? { x: ICON.cx, y: ICON.cy } : KEY_REST_C;
        const mask = wipeMask(c.x, c.y, ease.out(p));
        setMask(node, mask);
        if (world.origin === 'inline') floodMask = mask;
      }
    }
    if (!world.paper) {
      const ax = 1180 + 260 * Math.sin(0.23 * t + 0.6), ay = 180 + 150 * Math.cos(0.19 * t + 1.1);
      const bx = 1560 + 210 * Math.cos(0.17 * t + 2.0), by = 980 + 130 * Math.sin(0.21 * t + 0.3);
      world.lightA.style.transform = `translate(${px(ax - 750)}, ${px(ay - 750)})`;
      world.lightB.style.transform = `translate(${px(bx - 850)}, ${px(by - 850)})`;
    }
  });
}

// ---- Captures --------------------------------------------------------------------------------------------------
const FOOTAGE = '../footage/';
const captures = el('div', 'captures', stage);
captures.style.cssText = 'width:1920px;height:1080px;';
const images = [];

function makeRig(names) {
  const node = el('div', 'rig', captures);
  node.style.cssText = 'position:absolute;left:0;top:0;';
  const rig = { node, img: {} };
  for (const name of names) {
    const img = el('img', '', node);
    img.src = `${FOOTAGE}${name}.png`;
    img.decoding = 'sync';
    rig.img[name] = img;
    images.push(img);
  }
  return rig;
}

function mark(rig, css, html) {
  const node = el('div', 'mark', rig.node, html);
  node.style.cssText += css;
  return node;
}

const rigs = {
  finder: makeRig(['1-finder']),
  settings: makeRig(['1-panel', '2-panel']),
  sqlite: makeRig(['4-panel-summary', '4-panel-table']),
  zip: makeRig(['5-panel']),
  notebook: makeRig(['3-panel']),
  markdown: makeRig(['6-panel']),
  app: makeRig(['8-app', '9-app', '9-app-aurora']),
};

// Annotation marks sit inside a rig, in the capture's own pixel coordinates, so they stay locked to the interface.
const AMBER = '#ffb547', MINT = '#4fe3c1';
const chipCss = (x, y) => `left:${x}px;top:${y - 17}px;width:34px;height:34px;border-radius:17px;background:${AMBER};color:#0b0d1a;` +
  'font:700 21px/34px var(--sans);text-align:center;transform-origin:50% 50%;box-shadow:0 4px 14px rgba(0,0,0,0.5);';
const ringCss = (x0, y0, x1, y1, color, r = 11, w = 2.5) => `left:${x0}px;top:${y0}px;width:${x1 - x0}px;height:${y1 - y0}px;border-radius:${r}px;` +
  `background:${rgba(color, 0.13)};box-shadow:0 0 0 ${w}px ${color}, 0 0 22px 2px ${rgba(color, 0.4)};transform-origin:50% 50%;`;
const marks = {
  ring1: mark(rigs.settings, ringCss(292, 681, 381, 711, AMBER)),
  chip1: mark(rigs.settings, chipCss(399, 696), '1'),
  ring2: mark(rigs.settings, ringCss(196, 810, 283, 839, AMBER)),
  chip2: mark(rigs.settings, chipCss(301, 825), '2'),
  count: mark(rigs.settings, `left:86px;top:192px;width:246px;height:5px;border-radius:3px;background:${AMBER};transform-origin:0 50%;box-shadow:0 0 16px ${rgba(AMBER, 0.5)};`),
  readOnly: mark(rigs.sqlite, ringCss(70, 370, 650, 420, MINT, 13, 3)),
};

// A rig is placed by the screen position of its top-left corner and a scale in output pixels per capture pixel.
// `pop` scales it about a screen point (opening and closing); `opacity` and the shadow follow.
function placeRig(rig, o) {
  if (!o || o.opacity <= 0.001) { show(rig.node, false); return; }
  show(rig.node, true);
  let { x, y, s } = o;
  if (o.drift) { // slow continuous growth about a screen anchor
    const m = 1 + o.drift.rate * ramp(o.drift.elapsed);
    x = o.drift.ax + (x - o.drift.ax) * m;
    y = o.drift.ay + (y - o.drift.ay) * m;
    s *= m;
  }
  if (o.pop) {
    x = o.pop.ox + (x - o.pop.ox) * o.pop.k;
    y = o.pop.oy + (y - o.pop.oy) * o.pop.k;
    s *= o.pop.k;
  }
  if (s > 1.0005) throw new Error(`capture enlarged beyond native pixels: ${s}`);
  rig.node.style.transform = `translate(${px(x)}, ${px(y + (o.dy || 0))}) scale(${Math.round(s * 1e5) / 1e5})`;
  rig.node.style.opacity = clamp(o.opacity == null ? 1 : o.opacity);
  // Shadow sizes are in screen pixels, so divide by the scale.
  const a = o.shadow == null ? 0.48 : o.shadow;
  const shadow = `drop-shadow(0 ${px(30 / s)} ${px(44 / s)} rgba(9,5,36,${a})) drop-shadow(0 ${px(5 / s)} ${px(10 / s)} rgba(9,5,36,${a * 0.5}))`;
  for (const img of Object.values(rig.img)) img.style.filter = shadow;
}

// Opening: the panel springs up from a point (the selected file, later the key), in front of the one that is leaving.
// It arrives opaque, so two previews are never read through each other. Closing is quicker and plainer.
function opening(t, t0, from = 0.88) {
  return { k: lerp(from, 1, spring(t - t0, 14, 0.6)), o: t >= t0 ? 1 : 0 };
}
function closing(t, t1) {
  const p = prog(t, t1, 0.2);
  return { k: lerp(1, 0.955, ease.in(p)), o: 1 - p };
}
const POP_FROM_KEY = { ox: CAP_X - 40, oy: 960 };
const POP_AWAY = { ox: 1320, oy: 520 };

function standardPanel(t, tIn, tOut, cam, drift) {
  if (t < tIn || t > tOut + 0.22) return null;
  const o = { ...cam, opacity: 1 };
  if (drift) o.drift = drift;
  if (t < tOut) {
    const a = opening(t, tIn);
    o.pop = { ...POP_FROM_KEY, k: a.k };
    o.opacity = a.o;
  } else {
    const c = closing(t, tOut);
    o.pop = { ...POP_AWAY, k: c.k };
    o.opacity = c.o;
  }
  return o;
}

// The Finder window of the opening. The panel opens over it at the offset the two windows had on screen
// (footage geometry: panel 270 pt right and 70 pt below the Finder window's corner, 2 pixels per point).
const FINDER = { s: 0.76, x: CAP_X, y: 172 };

function renderCaptures(t) {
  // Finder window: on screen from the first frame, recedes as the camera pushes into the panel.
  {
    const settle = ease.soft(prog(t, 0, 0.7));
    const cam = track(t, [
      { t: T.push1, s: FINDER.s, x: FINDER.x, y: FINDER.y },
      { t: T.push1 + 1.2, s: FINDER.s * 1.05, x: FINDER.x - 110, y: FINDER.y - 30 },
    ]);
    const o = { ...cam, opacity: 1 - ease.inOut(prog(t, T.push1 + 0.08, 0.4)), shadow: lerp(0.3, 0.46, prog(t, T.press1, 0.6)) };
    o.pop = { ox: CAP_X + 600, oy: 560, k: lerp(0.972, 1, settle) };
    o.dy = 20 * (1 - settle);
    placeRig(rigs.finder, t < T.push1 + 0.5 ? o : null);
  }

  // settings.json: opens out of the selected row, Outline first, then Source with the concealed values.
  {
    const rig = rigs.settings;
    const tIn = T.press1 + 0.05, tOut = T.s3 + 0.03;
    let o = null;
    if (t >= tIn && t < tOut + 0.22) {
      const cam = track(t, [
        { t: T.push1, s: FINDER.s, x: FINDER.x + 540 * FINDER.s, y: FINDER.y + 140 * FINDER.s },
        { t: T.push1 + 1.2, s: 0.8, x: CAP_X, y: 108 },
        { t: T.s2 - 0.05, s: 0.8, x: CAP_X, y: 108 },
        { t: T.s2 + 1.0, s: 0.95, x: CAP_X, y: 60 },
      ]);
      o = { ...cam, opacity: 1, drift: { rate: 0.0075, elapsed: t - (T.push1 + 1.0), ax: CAP_X, ay: 420 } };
      if (t < tOut) {
        const a = { k: lerp(0.1, 1, spring(t - tIn, 13, 0.66)), o: 1 };
        o.pop = { ox: FINDER.x + 68 * FINDER.s, oy: FINDER.y + 310 * FINDER.s, k: a.k }; // the settings.json row in the Finder capture
        o.opacity = a.o;
      } else {
        const c = closing(t, tOut);
        o.pop = { ...POP_AWAY, k: c.k };
        o.opacity = c.o;
      }
    }
    placeRig(rig, o);
    // Outline to Source. The title bar, the view control and the findings banner sit at the same pixels in both
    // captures, so the control changes at once (as a click does) and the content below the banner rolls down.
    const wp = prog(t, T.wipe2, 0.52);
    const edge = lerp(240, 1640, ease.inOut(wp));
    rig.img['1-panel'].style.opacity = wp >= 1 ? 0 : 1;
    rig.img['2-panel'].style.opacity = wp <= 0 ? 0 : 1;
    setMask(rig.img['2-panel'], wp >= 1 ? 'none' : `linear-gradient(180deg, #000 ${px(edge - 56)}, rgba(0,0,0,0) ${px(edge)})`);

    const pop = (node, t0, from) => {
      const k = spring(t - t0, 17, 0.55);
      node.style.opacity = prog(t, t0, 0.1);
      node.style.transform = `scale(${lerp(from, 1, k)})`;
    };
    pop(marks.ring1, T.s2 + 1.65, 1.5);
    pop(marks.chip1, T.s2 + 1.75, 0.2);
    pop(marks.ring2, T.s2 + 2.0, 1.5);
    pop(marks.chip2, T.s2 + 2.1, 0.2);
    marks.count.style.opacity = prog(t, T.s2 + 2.5, 0.08);
    marks.count.style.transform = `scaleX(${ease.soft(prog(t, T.s2 + 2.5, 0.5))})`;
  }

  // stations.sqlite: Summary (the read-only line), then Table. Same window, so a straight dissolve.
  {
    const rig = rigs.sqlite;
    const cam = track(t, [
      { t: T.s3 + 1.55, s: 0.86, x: CAP_X, y: 108 },
      { t: T.s3 + 2.55, s: 0.7, x: CAP_X, y: 108 },
    ]);
    placeRig(rig, standardPanel(t, T.s3 + 0.07, T.s4 + 0.03, cam, { rate: 0.01, elapsed: t - (T.s3 + 2.4), ax: CAP_X, ay: 300 }));
    rig.img['4-panel-table'].style.opacity = ease.inOut(prog(t, T.s3 + 1.7, 0.45));
    const k = spring(t - (T.s3 + 0.75), 17, 0.55);
    marks.readOnly.style.opacity = prog(t, T.s3 + 0.75, 0.1) * (1 - prog(t, T.s3 + 1.55, 0.2));
    marks.readOnly.style.transform = `scale(${lerp(1.12, 1, k)})`;
  }

  // release-1.4.zip
  placeRig(rigs.zip, standardPanel(t, T.s4 + 0.07, T.s5 + 0.03, { s: 0.74, x: CAP_X, y: 108 },
    { rate: 0.016, elapsed: t - T.s4, ax: CAP_X, ay: 260 }));

  // tide-analysis.ipynb
  placeRig(rigs.notebook, standardPanel(t, T.s5 + 0.07, T.s6 + 0.03, { s: 0.584, x: CAP_X, y: 100 },
    { rate: 0.007, elapsed: t - T.s5, ax: CAP_X, ay: 100 }));

  // README.md
  placeRig(rigs.markdown, standardPanel(t, T.s6 + 0.07, T.s8 - 0.02, { s: 0.584, x: CAP_X, y: 100 },
    { rate: 0.007, elapsed: t - T.s6, ax: CAP_X, ay: 100 }));

  // The app: File Types, then Theme, then the Aurora scheme picked on the Theme page. One window, pixel-aligned.
  {
    const rig = rigs.app;
    const tIn = T.s8 + 0.08;
    let o = null;
    if (t >= tIn && t < T.end + 0.4) {
      // It comes up from below the frame, opaque: no window is ever read through another.
      const rise = spring(t - tIn, 10.5, 0.8);
      o = { s: 0.62, x: 160, y: 318, opacity: 1, dy: 790 * (1 - rise),
        drift: { rate: 0.008, elapsed: t - T.s8, ax: W / 2, ay: 318 } };
      const out = ease.in(prog(t, T.end - 0.02, 0.4));
      o.dy += 860 * out;
      o.opacity *= 1 - prog(t, T.end + 0.26, 0.12);
    }
    placeRig(rig, o);
    rig.img['9-app'].style.opacity = t >= T.s9 + 0.1 ? 1 : 0; // a page change is a cut, as it is in the app
    rig.img['9-app-aurora'].style.opacity = ease.inOut(prog(t, T.s9 + 0.95, 0.42));
  }
}

// ---- Left column: file label, headline, note ---------------------------------------------------------------------
const FILE_GLYPH = '<svg viewBox="0 0 17 21" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"><path d="M10.2 1H3.4A2.4 2.4 0 0 0 1 3.4v14.2A2.4 2.4 0 0 0 3.4 20h10.2a2.4 2.4 0 0 0 2.4-2.4V6.8L10.2 1Z"/><path d="M10.2 1v3.4a2.4 2.4 0 0 0 2.4 2.4H16"/></svg>';
const SELECT = 0.22; // the file label changes this long before the key goes down
const LEAVE = 0.09;  // and the headline starts to leave this long before, so it is gone when the next preview lands
const EYEBROWS = [
  { text: 'settings.json', t0: -9, t1: T.s3 - SELECT },
  { text: 'stations.sqlite', t0: T.s3 - SELECT, t1: T.s4 - SELECT },
  { text: 'release-1.4.zip', t0: T.s4 - SELECT, t1: T.s5 - SELECT },
  { text: 'tide-analysis.ipynb', t0: T.s5 - SELECT, t1: T.s6 - SELECT },
  { text: 'README.md', t0: T.s6 - SELECT, t1: T.s8 - 0.04 },
  { text: 'File Types', caps: true, t0: T.s8 + 0.2, t1: T.s9 - 0.06 },
  { text: 'Theme', caps: true, t0: T.s9 - 0.06, t1: T.end - 0.04 },
];
// Headlines are the approved ones (docs/release/app-store-listing.md), broken into lines for the column.
// A string is a word; {em} is the serif italic accent; {slot} is where the key sits in the opening line.
const HEADLINES = [
  { t1: T.s2 - 0.04, lines: [
    { t: -9, words: ['Press ', { slot: true }] },
    { t: T.press1 + 0.24, words: ['See ', 'what’s'] },
    { t: T.press1 + 0.34, words: [{ em: 'really' }, ' inside.'] },
  ] },
  { t0: T.s2 + 0.16, t1: T.s3 - LEAVE, lines: [['Likely ', 'secrets'], ['concealed,'], ['and ', { em: 'counted' }, '.']] },
  { t0: T.s3 + 0.16, t1: T.s4 - LEAVE, lines: [['A ', 'database'], ['at ', 'a ', 'glance.'], [{ em: 'Read-only.' }]] },
  { t0: T.s4 + 0.16, t1: T.s5 - LEAVE, lines: [['Look ', 'inside.'], [{ em: 'Nothing' }, ' is'], ['extracted.']] },
  { t0: T.s5 + 0.16, t1: T.s6 - LEAVE, lines: [['Notebooks'], ['as ', 'saved.'], [{ em: 'Never' }, ' run.']] },
  { t0: T.s6 + 0.16, t1: T.s8 - 0.04, lines: [['Markdown,'], [{ em: 'ready' }, ' to ', 'read.']] },
  { t0: T.s8 + 0.26, t1: T.s9 - 0.06, center: true, lines: [['A ', 'switch ', 'for ', { em: 'every' }, ' file ', 'type.']] },
  { t0: T.s9 + 0.1, t1: T.end - 0.04, center: true, lines: [[{ em: 'Your' }, ' colors. ', { em: 'Your' }, ' type.']] },
];

function buildChrome(tone) {
  const root = el('div', `chrome ${tone}`, stage);
  const chrome = { root, eyebrows: [], headlines: [] };
  for (const def of EYEBROWS) {
    const node = el('div', `eyebrow${def.caps ? ' caps' : ''}`, root, def.caps ? def.text : `${FILE_GLYPH}<span>${def.text}</span>`);
    chrome.eyebrows.push({ def, node });
  }
  for (const def of HEADLINES) {
    const node = el('div', `headline${def.center ? ' center' : ''}`, root);
    const words = [];
    def.lines.forEach((line, li) => {
      const lineNode = el('span', 'line', node);
      const lineT = Array.isArray(line) ? def.t0 + li * 0.085 : line.t;
      (Array.isArray(line) ? line : line.words).forEach((word, wi) => {
        let span;
        if (word.slot) span = el('span', 'kslot', lineNode);
        else if (word.em) { span = el('span', 'word', lineNode); el('em', '', span).textContent = word.em; }
        else { span = el('span', 'word', lineNode); span.textContent = word; }
        words.push({ span, t: lineT + wi * 0.055, slot: !!word.slot });
      });
    });
    const entry = { def, node, words };
    if (def.note) {
      entry.note = el('div', 'note', root);
      entry.note.innerHTML = def.note;
    }
    chrome.headlines.push(entry);
  }
  return chrome;
}
const chromeInk = buildChrome('ink');
const chromeWhite = buildChrome('white');

function renderChrome(chrome, t) {
  for (const { def, node } of chrome.eyebrows) {
    const inP = ease.soft(prog(t, def.t0 + 0.07, 0.34)), outP = prog(t, def.t1, 0.13);
    const visible = t >= def.t0 && outP < 1;
    show(node, visible);
    if (!visible) continue;
    const first = def.t0 < 0;
    const opacity = (first ? 1 : prog(t, def.t0 + 0.07, 0.16)) * (1 - outP);
    const dy = (first ? 0 : 14 * (1 - inP)) - 10 * ease.in(outP);
    if (def.caps) {
      node.style.left = px(W / 2 - node.offsetWidth / 2);
      node.style.top = px(84);
    } else {
      node.style.left = px(COL_X);
      node.style.top = px(EYEBROW_Y);
    }
    node.style.opacity = opacity;
    node.style.transform = `translateY(${px(dy)})`;
  }
  for (const { def, node, words, note } of chrome.headlines) {
    const t0 = def.t0 == null ? -9 : def.t0;
    const outP = prog(t, def.t1, 0.16);
    const visible = t >= t0 && outP < 1;
    show(node, visible);
    if (note) show(note, visible);
    if (!visible) continue;
    node.style.left = px(def.center ? 0 : COL_X);
    node.style.top = px(def.center ? 152 : HEAD_Y);
    node.style.opacity = 1 - outP;
    node.style.transform = `translateY(${px(-12 * ease.in(outP))})`;
    for (const word of words) {
      if (word.slot) continue;
      const p = word.t < 0 ? 1 : ease.soft(prog(t, word.t, 0.62));
      word.span.style.transform = `translateY(${(1 - p) * 118}%)`;
      word.span.style.opacity = word.t < 0 ? 1 : prog(t, word.t, 0.14);
    }
    if (note) {
      const p = ease.soft(prog(t, t0 + 0.42, 0.6));
      note.style.left = px(COL_X + 2);
      note.style.top = px(HEAD_Y + def.lines.length * LINE_H + 26 + 14 * (1 - p));
      note.style.opacity = prog(t, t0 + 0.42, 0.3) * (1 - outP) * 0.9;
    }
  }
}

// ---- The key ----------------------------------------------------------------------------------------------------
const ring = el('div', '', stage);
ring.id = 'ring';
const key = el('div', '', stage, '<span>Space</span>');
key.id = 'key';
let KEY_INLINE = { x: 300, y: 370, w: 246, h: 80, r: 17, fs: 64 };

function keyDepth(t) {
  let d = 0;
  for (const P of PRESSES) {
    if (t >= P - 0.3 && t < P - 0.07) d = -0.3 * Math.sin(Math.PI * ease.inOut((t - (P - 0.3)) / 0.23) * 0.5); // a small lift before the press
    else if (t >= P - 0.07 && t < P) d = lerp(-0.3, 1, ease.in((t - (P - 0.07)) / 0.07));
    else if (t >= P && t < P + 0.07) d = 1;
    else if (t >= P + 0.07 && t < P + 0.7) d = Math.max(d, 1 - spring(t - (P + 0.07), 22, 0.5));
  }
  return d;
}

const mix = (a, b, p) => ({ x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p), w: lerp(a.w, b.w, p), h: lerp(a.h, b.h, p), r: lerp(a.r, b.r, p), fs: lerp(a.fs, b.fs, p) });

function renderKey(t) {
  let g, visible = true;
  if (t < T.s2 - 0.06) g = KEY_INLINE;
  else if (t < T.s8 - 0.14) {
    // Leaves the headline and settles in the corner. It drops first and drifts left late, so it never crosses the
    // words it sat beside.
    const p = prog(t, T.s2 - 0.06, 0.8);
    const a = mix(KEY_INLINE, KEY_REST, ease.inOut(p));
    a.x = lerp(KEY_INLINE.x, KEY_REST.x, ease.inOut(prog(t, T.s2 + 0.08, 0.66)));
    g = a;
  } else {
    // The app's own window needs no key: it leaves by the bottom edge. The icon's space bar takes the last press.
    const p = ease.in(prog(t, T.s8 - 0.14, 0.32));
    g = { ...KEY_REST, y: KEY_REST.y + 230 * p };
    visible = p < 1;
  }
  show(key, visible);
  if (!visible) { show(ring, false); return; }
  const d = keyDepth(t);
  const lip = lerp(Math.max(1.5, g.h * 0.085), 1.5, clamp(d));
  key.style.left = px(g.x);
  key.style.top = px(g.y + g.h * 0.07 * d);
  key.style.width = px(g.w);
  key.style.height = px(g.h);
  key.style.borderRadius = px(g.r);
  key.style.borderBottomWidth = px(lip);
  key.style.fontSize = px(g.fs);
  key.style.letterSpacing = g.fs > 40 ? '-0.03em' : '0';
  const lift = 1 - clamp(d);
  key.style.boxShadow = `inset 0 ${px(-g.h * 0.05)} 0 rgba(0,0,0,0.06), 0 ${px(lerp(3, g.h * 0.24, lift))} ${px(lerp(6, g.h * 0.5, lift))} ${px(-g.h * 0.12)} rgba(12,6,56,${lerp(0.5, 0.42, lift)})`;

  // A ring leaves the key on every press. Before the first press a quieter one, in brand ink, points at the key.
  let ringP = -1;
  for (const P of PRESSES) if (t >= P && t < P + 0.6) ringP = (t - P) / 0.6;
  const hint = t < T.press1;
  if (hint) ringP = t >= 0.28 && t < 1.08 ? (t - 0.28) / 0.8 : -1;
  ring.style.borderColor = hint ? 'rgba(75, 60, 255, 0.55)' : 'rgba(255, 255, 255, 0.9)';
  show(ring, ringP >= 0 && (hint || t > T.press1 + 0.5));
  if (ringP >= 0) {
    const grow = hint ? 4 + 30 * ease.out(ringP) : 8 + 54 * ease.out(ringP);
    ring.style.left = px(g.x - grow);
    ring.style.top = px(g.y - grow);
    ring.style.width = px(g.w + 2 * grow);
    ring.style.height = px(g.h + 2 * grow);
    ring.style.borderRadius = px(g.r + grow);
    ring.style.opacity = 0.7 * (1 - ringP) * (1 - ringP);
  }
}

// ---- End card ---------------------------------------------------------------------------------------------------
const endCard = el('div', '', WORLDS[WORLDS.length - 1].node);
endCard.id = 'end';
const ICON = { size: 256, cx: W / 2, cy: 418 };
const glow = el('div', '', endCard);
glow.style.cssText = `left:${ICON.cx - 330}px;top:${ICON.cy - 310}px;width:660px;height:660px;border-radius:50%;background:radial-gradient(closest-side, rgba(166,77,255,0.40), rgba(166,77,255,0.13) 55%, rgba(166,77,255,0));`;
const iconBox = el('div', '', endCard);
iconBox.style.cssText = `left:${ICON.cx - ICON.size / 2}px;top:${ICON.cy - ICON.size / 2}px;width:${ICON.size}px;height:${ICON.size}px;transform-origin:50% 50%;`;
const nameLine = el('div', 'name', endCard, '<span class="word">SpacePane</span><span class="word"> <em>for</em></span><span class="word"> <em>Quick</em></span><span class="word"> <em>Look</em></span>');
nameLine.style.top = '606px';
const subLine = el('div', 'sub', endCard);
subLine.textContent = 'Preview JSON, SQLite, Markdown';
subLine.style.top = '722px';
let iconParts = null;

async function loadIcon() {
  // The icon is footage/icon.svg, unchanged. Inlined so its own bars can arrive one at a time; if the file cannot
  // be read as text (a browser opened without file access), it is shown whole.
  try {
    const text = await new Promise((resolve, reject) => {
      const request = new XMLHttpRequest(); // fetch() refuses file: URLs
      request.open('GET', `${FOOTAGE}icon.svg`);
      request.onload = () => (request.responseText.includes('<svg') ? resolve(request.responseText) : reject(new Error('no icon')));
      request.onerror = () => reject(new Error('no icon'));
      request.send();
    });
    iconBox.innerHTML = text;
    const svg = iconBox.querySelector('svg');
    svg.setAttribute('width', ICON.size);
    svg.setAttribute('height', ICON.size);
    svg.style.cssText = 'display:block;overflow:visible;filter:drop-shadow(0 18px 30px rgba(40,20,110,0.28));';
    const rects = [...svg.querySelectorAll('rect')];
    const ellipses = [...svg.querySelectorAll('ellipse')];
    for (const r of rects) { r.style.transformBox = 'fill-box'; r.style.transformOrigin = '0% 50%'; }
    iconParts = { bars: rects, shadows: ellipses };
  } catch (error) {
    iconBox.innerHTML = `<img src="${FOOTAGE}icon.svg" width="${ICON.size}" height="${ICON.size}">`;
  }
}

// The icon builds from its own parts (three code bars, then the space bar); the space bar is pressed once, and that
// last press brings up the name. The settled icon is footage/icon.svg exactly.
const END = { icon: 0.26, bars: 0.46, press: 0.92, name: 0.98, sub: 1.28 };
function renderEnd(t) {
  const t0 = T.end + END.icon;
  const k = spring(t - t0, 12, 0.58);
  iconBox.style.opacity = prog(t, t0, 0.12);
  iconBox.style.transform = `scale(${lerp(0.72, 1, k)})`;
  glow.style.opacity = ease.soft(prog(t, t0 + 0.1, 0.9));
  if (iconParts) {
    const P = T.end + END.press;
    let d = 0;
    if (t >= P - 0.07 && t < P) d = ease.in((t - (P - 0.07)) / 0.07);
    else if (t >= P && t < P + 0.06) d = 1;
    else if (t >= P + 0.06) d = 1 - spring(t - (P + 0.06), 22, 0.5);
    iconParts.bars.forEach((bar, i) => {
      const b0 = T.end + END.bars + i * 0.09;
      const p = spring(t - b0, 15, 0.62);
      bar.style.transform = `translateY(${i === 3 ? 0.75 * d : 0}px) scaleX(${Math.max(0, p)})`;
      bar.style.opacity = prog(t, b0, 0.06);
      iconParts.shadows[i].style.opacity = prog(t, b0 + 0.18, 0.3) * (i === 3 ? 1 - 0.6 * d : 1);
    });
  }
  [...nameLine.children].forEach((word, i) => {
    const w0 = T.end + END.name + i * 0.07;
    const p = ease.soft(prog(t, w0, 0.7));
    word.style.transform = `translateY(${px(34 * (1 - p))})`;
    word.style.opacity = prog(t, w0, 0.22);
  });
  const s0 = T.end + END.sub;
  const sp = ease.soft(prog(t, s0, 0.7));
  subLine.style.transform = `translateY(${px(18 * (1 - sp))})`;
  subLine.style.opacity = prog(t, s0, 0.3);
}

// ---- Frame -------------------------------------------------------------------------------------------------------
function renderAt(t) {
  t = clamp(t, 0, DURATION);
  renderWorlds(t);
  renderCaptures(t);
  // Ink on paper, white on color. During the opening flood the white copy is revealed by the same circle as the color.
  const flooding = floodMask !== 'none';
  const onColor = t >= T.press1 + 0.02;
  show(chromeInk.root, !onColor || flooding);
  show(chromeWhite.root, onColor && t < T.end + 0.3);
  setMask(chromeWhite.root, flooding ? floodMask : 'none');
  if (!onColor || flooding) renderChrome(chromeInk, t);
  if (onColor) renderChrome(chromeWhite, t);
  renderKey(t);
  if (t >= T.end - 0.1) renderEnd(t);
  return t;
}

window.FILM = { fps: FPS, duration: DURATION, frames: Math.round(DURATION * FPS), width: W, height: H, beats: T };
window.renderAt = renderAt;
window.ready = (async () => {
  await loadIcon();
  await Promise.all([
    document.fonts.load('700 78px system-ui'),
    document.fonts.load('italic 560 78px "Film Serif"'),
    document.fonts.load('500 21px "Film Mono"'),
  ]);
  await document.fonts.ready;
  await Promise.all(images.map((img) => (img.complete && img.naturalWidth ? img.decode() : new Promise((resolve, reject) => {
    img.onload = () => img.decode().then(resolve, resolve);
    img.onerror = () => reject(new Error(`missing footage: ${img.src}`));
  }))));
  for (const img of images) { img.style.width = `${img.naturalWidth}px`; img.style.height = `${img.naturalHeight}px`; }
  // Where the key sits in the opening headline.
  renderAt(0);
  const slot = chromeInk.root.querySelector('.kslot');
  const r = slot.getBoundingClientRect();
  KEY_INLINE = { x: r.left + 4, y: r.top + 5, w: r.width - 4, h: 76, r: 17, fs: 62 };
  inlineKeyCenter = { x: KEY_INLINE.x + KEY_INLINE.w / 2, y: KEY_INLINE.y + KEY_INLINE.h / 2 };
  renderAt(0);
  return window.FILM;
})();

// Inspection in a browser: ?t=12.5 for one frame, ?play for a rough real-time run.
(() => {
  const query = new URLSearchParams(location.search);
  if (query.has('t')) window.ready.then(() => renderAt(parseFloat(query.get('t'))));
  if (query.has('play')) {
    window.ready.then(() => {
      const start = performance.now();
      const tick = () => { renderAt(((performance.now() - start) / 1000) % DURATION); requestAnimationFrame(tick); };
      tick();
    });
  }
})();
